#!/usr/bin/env python3
"""使用 Camoufox 打开网页, 并通过 Kryva 管理浏览器 profile。"""

from __future__ import annotations

import argparse
import asyncio
import os
import shutil
import stat
import sys
import tarfile
import tempfile
import unicodedata
from collections.abc import Sequence
from pathlib import Path, PurePosixPath
from urllib.parse import urlsplit

import requests

DATA_DIR = Path(__file__).resolve().parent / "data"
KRYVA_DEFAULT_API_URL = "https://kryva.oozuo.com/"
KRYVA_PLATFORM = "remote-desktop"
KRYVA_TIMEOUT = (15, 600)


class ProfileArchive:
    """筛选、打包并恢复浏览器 profile 中的站点数据。"""

    SQLITE_SUFFIXES = ("", "-wal", "-shm", "-journal")
    PROFILE_DATABASES = {
        f"{name}{suffix}"
        for name in ("cookies.sqlite", "webappsstore.sqlite", "storage.sqlite")
        for suffix in ("", "-wal", "-shm", "-journal")
    }
    LS_ARCHIVE_FILES = {
        f"storage/ls-archive.sqlite{suffix}"
        for suffix in ("", "-wal", "-shm", "-journal")
    }

    def __init__(self, data_dir: Path) -> None:
        """记录包含全部 profile 的数据目录。"""
        self.data_dir = data_dir

    def profile_path(self, profile: str) -> Path:
        """返回 profile 目录并拒绝可能越出数据目录的符号链接。"""
        if self.data_dir.is_symlink():
            raise RuntimeError("data 目录不能是符号链接")
        path = self.data_dir / profile
        if path.is_symlink():
            raise RuntimeError("profile 目录不能是符号链接")
        if path.exists() and not path.is_dir():
            raise RuntimeError("profile 路径必须是目录")
        return path

    @classmethod
    def is_profile_data_file(cls, relative: PurePosixPath) -> bool:
        """判断相对路径是否属于 Cookies、localStorage 或 IndexedDB。"""
        path = relative.as_posix()
        if path in cls.PROFILE_DATABASES or path in cls.LS_ARCHIVE_FILES:
            return True
        parts = relative.parts
        if (
            len(parts) < 4
            or parts[0] != "storage"
            or parts[1] not in {"default", "permanent", "temporary"}
        ):
            return False
        if parts[2].startswith("moz-extension"):
            return False
        if len(parts) == 4 and parts[3] in {".metadata", ".metadata-v2"}:
            return True
        return len(parts) >= 5 and parts[3] in {"ls", "idb"}

    def collect_files(self, profile: str) -> list[tuple[Path, PurePosixPath]]:
        """收集 profile 中允许备份的普通文件。"""
        root = self.profile_path(profile)
        if not root.exists():
            raise RuntimeError(f"profile 不存在: {profile}")
        selected: list[tuple[Path, PurePosixPath]] = []
        for current_root, directories, files in os.walk(root, followlinks=False):
            current = Path(current_root)
            directories[:] = sorted(
                name for name in directories if not (current / name).is_symlink()
            )
            for name in sorted(files):
                source = current / name
                if source.is_symlink() or not stat.S_ISREG(
                    source.stat(follow_symlinks=False).st_mode
                ):
                    continue
                relative = PurePosixPath(source.relative_to(root).as_posix())
                if self.is_profile_data_file(relative):
                    selected.append((source, relative))
        return selected

    def create(self, profile: str, destination: Path) -> bool:
        """将 profile 的站点数据写入 gzip tar 归档。"""
        files = self.collect_files(profile)
        if not files:
            return False
        with tarfile.open(destination, mode="w:gz") as archive:
            for source, relative in files:
                archive_name = PurePosixPath(profile, relative)
                info = archive.gettarinfo(str(source), arcname=archive_name.as_posix())
                if not info.isfile():
                    continue
                with source.open("rb") as stream:
                    archive.addfile(info, stream)
        return True

    def validate_members(
        self,
        profile: str,
        archive: tarfile.TarFile,
    ) -> list[tuple[tarfile.TarInfo, PurePosixPath]]:
        """校验归档成员并返回允许恢复的普通文件。"""
        selected: list[tuple[tarfile.TarInfo, PurePosixPath]] = []
        seen: set[str] = set()
        for member in archive.getmembers():
            member_path = PurePosixPath(member.name)
            if (
                member_path.is_absolute()
                or ".." in member_path.parts
                or not member_path.parts
            ):
                raise RuntimeError("Kryva 归档包含非法路径")
            if member.isdir():
                if member_path.parts[0] != profile:
                    raise RuntimeError("Kryva 归档包含非目标 profile 目录")
                continue
            if (
                not member.isfile()
                or member_path.parts[0] != profile
                or len(member_path.parts) < 2
            ):
                raise RuntimeError("Kryva 归档包含非目标 profile 文件")
            relative = PurePosixPath(*member_path.parts[1:])
            if not self.is_profile_data_file(relative):
                raise RuntimeError("Kryva 归档包含非站点数据")
            key = relative.as_posix()
            if key in seen:
                raise RuntimeError("Kryva 归档包含重复文件")
            seen.add(key)
            selected.append((member, relative))
        if not selected:
            raise RuntimeError("Kryva 归档中没有可恢复的站点数据")
        return selected

    def extract(self, profile: str, archive_path: Path) -> None:
        """将归档中的白名单文件原子写入指定 profile。"""
        target_root = self.profile_path(profile)
        with tarfile.open(archive_path, mode="r:gz") as archive:
            members = self.validate_members(profile, archive)
            target_root.mkdir(parents=True, exist_ok=True)
            for member, relative in members:
                source = archive.extractfile(member)
                if source is None:
                    raise RuntimeError("无法读取 Kryva 归档文件")
                parent = target_root
                for part in relative.parts[:-1]:
                    parent /= part
                    if parent.is_symlink():
                        raise RuntimeError("profile 包含指向目录外的符号链接")
                    parent.mkdir(exist_ok=True)
                destination = parent / relative.name
                if destination.is_symlink():
                    raise RuntimeError("profile 包含指向目录外的符号链接")
                temporary: Path | None = None
                try:
                    with source, tempfile.NamedTemporaryFile(
                        dir=parent, delete=False
                    ) as output:
                        temporary = Path(output.name)
                        shutil.copyfileobj(source, output, length=1024 * 1024)
                    temporary.replace(destination)
                except Exception:
                    if temporary is not None:
                        temporary.unlink(missing_ok=True)
                    raise


class KryvaClient:
    """使用 requests 调用 Kryva 文件上传和下载接口。"""

    def __init__(
        self, api_key: str, api_url: str, session: requests.Session | None = None
    ) -> None:
        """校验 Kryva 配置并初始化 HTTP 会话。"""
        parsed = urlsplit(api_url)
        if (
            parsed.scheme not in {"http", "https"}
            or not parsed.netloc
            or parsed.username is not None
            or parsed.query
            or parsed.fragment
        ):
            raise RuntimeError("KRYVA_API_URL 必须是完整的 HTTP 或 HTTPS 地址")
        self.api_key = api_key
        self.api_url = api_url.rstrip("/")
        self.session = session or requests.Session()

    @classmethod
    def from_environment(cls) -> KryvaClient:
        """从系统环境变量创建 Kryva 客户端。"""
        api_key = os.environ.get("KRYVA_API_KEY", "").strip()
        api_url = os.environ.get("KRYVA_API_URL", "").strip() or KRYVA_DEFAULT_API_URL
        if not api_key:
            raise RuntimeError("KRYVA_API_KEY 未配置")
        return cls(api_key, api_url)

    def endpoint(self, path: str) -> str:
        """返回 Kryva API 的完整地址。"""
        return f"{self.api_url}/{path.lstrip('/')}"

    def raise_for_status(self, response: requests.Response) -> None:
        """将 Kryva 非成功响应转换为不包含凭据的错误。"""
        if 200 <= response.status_code < 300:
            return
        if response.status_code == 401:
            raise RuntimeError("KRYVA_API_KEY 无效")
        detail = response.text.strip()
        message = f"Kryva 请求失败, HTTP {response.status_code}"
        if detail:
            message = f"{message}: {detail[:500]}"
        raise RuntimeError(message)

    def upload(self, profile: str, archive: Path) -> None:
        """使用固定 platform 和 profile 文件名上传归档。"""
        filename = RemoteDesktopApp.profile_archive_name(profile)
        with archive.open("rb") as stream:
            response = self.session.post(
                self.endpoint("/api/v1/files/upload"),
                headers={"Authorization": f"Bearer {self.api_key}"},
                data={"platform": KRYVA_PLATFORM},
                files={"file": (filename, stream, "application/gzip")},
                timeout=KRYVA_TIMEOUT,
            )
        self.raise_for_status(response)

    def download(self, profile: str, destination: Path) -> bool:
        """按 platform 和 profile 文件名下载最新归档。"""
        response = self.session.get(
            self.endpoint("/api/v1/files/download"),
            headers={"Authorization": f"Bearer {self.api_key}"},
            params={
                "platform": KRYVA_PLATFORM,
                "filename": RemoteDesktopApp.profile_archive_name(profile),
            },
            timeout=KRYVA_TIMEOUT,
            stream=True,
        )
        with response:
            if response.status_code == 404:
                return False
            self.raise_for_status(response)
            with destination.open("wb") as output:
                for chunk in response.iter_content(chunk_size=1024 * 1024):
                    if chunk:
                        output.write(chunk)
        return True


class RemoteDesktopApp:
    """提供浏览器启动、profile 备份和 profile 恢复命令。"""

    def __init__(self, data_dir: Path = DATA_DIR) -> None:
        """初始化 profile 数据目录和归档服务。"""
        self.data_dir = data_dir
        self.archives = ProfileArchive(data_dir)

    @staticmethod
    def profile_archive_name(profile: str) -> str:
        """返回 Kryva 使用的 NFC 规范化 profile 归档文件名。"""
        return f"{unicodedata.normalize('NFC', profile)}.tar.gz"

    @classmethod
    def build_parser(cls) -> argparse.ArgumentParser:
        """创建包含 start、backup 和 restore 的参数解析器。"""
        parser = argparse.ArgumentParser(
            description="使用 Camoufox 打开网页并管理浏览器 profile"
        )
        commands = parser.add_subparsers(dest="command", required=True)

        start_parser = commands.add_parser("start", help="启动浏览器")
        start_parser.add_argument(
            "--url",
            default="https://muse.ai",
            help="需要打开的完整 URL",
        )
        start_parser.add_argument(
            "--profile",
            metavar="NAME",
            help="将数据持久化到 ./data/NAME",
        )
        start_parser.add_argument(
            "--proxy",
            help="代理地址, 如 socks5://127.0.0.1:40000",
        )

        backup_parser = commands.add_parser("backup", help="备份浏览器 profile")
        backup_parser.add_argument("--profile", required=True, metavar="NAME")

        restore_parser = commands.add_parser("restore", help="恢复浏览器 profile")
        restore_parser.add_argument("--profile", required=True, metavar="NAME")
        return parser

    @staticmethod
    async def wait_for_exit() -> None:
        """等待用户输入 exit 后继续退出流程。"""
        while True:
            try:
                command = await asyncio.to_thread(input, "请输入 exit 关闭浏览器: ")
            except EOFError:
                return
            if command.strip().lower() == "exit":
                return

    async def open_url(
        self,
        url: str,
        profile: str | None = None,
        proxy: str | None = None,
    ) -> None:
        """启动可见浏览器, 并按需使用持久化上下文和指定代理。"""
        from camoufox.async_api import AsyncCamoufox

        options: dict[str, object] = {"headless": False, "geoip": True}
        if proxy:
            options["proxy"] = {"server": proxy}
        else:
            options["firefox_user_prefs"] = {
                "network.proxy.type": 1,
                "network.proxy.socks": "127.0.0.1",
                "network.proxy.socks_port": 40000,
                "network.proxy.socks_version": 5,
                "network.proxy.socks_remote_dns": True,
            }
        if profile:
            profile_dir = self.archives.profile_path(profile)
            profile_dir.mkdir(parents=True, exist_ok=True)
            options.update(persistent_context=True, user_data_dir=str(profile_dir))
        async with AsyncCamoufox(**options) as browser:
            page = await browser.new_page()
            await page.goto(url, wait_until="domcontentloaded")
            print(f"已打开: {page.url} | {await page.title()}")
            await self.wait_for_exit()

    def backup(self, profile: str) -> int:
        """创建并上传指定 profile 的站点数据归档。"""
        with tempfile.TemporaryDirectory(
            prefix="remote-desktop-backup-"
        ) as temporary_dir:
            archive = Path(temporary_dir) / self.profile_archive_name(profile)
            if not self.archives.create(profile, archive):
                print(
                    f"profile={profile} 没有 Cookies, localStorage 或 IndexedDB 数据, 跳过备份"
                )
                return 0
            KryvaClient.from_environment().upload(profile, archive)
        print(
            f"已备份: platform={KRYVA_PLATFORM}, filename={self.profile_archive_name(profile)}"
        )
        return 0

    def restore(self, profile: str) -> int:
        """从 Kryva 下载并恢复指定 profile 的站点数据。"""
        with tempfile.TemporaryDirectory(
            prefix="remote-desktop-restore-"
        ) as temporary_dir:
            archive = Path(temporary_dir) / self.profile_archive_name(profile)
            if not KryvaClient.from_environment().download(profile, archive):
                print(f"profile={profile} 暂无可恢复的 Kryva 备份")
                return 0
            self.archives.extract(profile, archive)
        print(
            f"已恢复: platform={KRYVA_PLATFORM}, filename={self.profile_archive_name(profile)}"
        )
        return 0

    def run(self, argv: Sequence[str] | None = None) -> int:
        """解析命令并执行对应操作。"""
        args = self.build_parser().parse_args(argv)
        try:
            if args.command == "start":
                asyncio.run(self.open_url(args.url, args.profile, args.proxy))
                return 0
            if args.command == "backup":
                return self.backup(args.profile)
            return self.restore(args.profile)
        except (
            OSError,
            RuntimeError,
            requests.RequestException,
            tarfile.TarError,
        ) as error:
            print(str(error), file=sys.stderr)
            return 1


def main(argv: Sequence[str] | None = None) -> int:
    """创建应用并运行命令行入口。"""
    return RemoteDesktopApp().run(argv)


if __name__ == "__main__":
    sys.exit(main())
