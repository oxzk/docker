"""
FastAPI 示例服务。

本模块提供一个简单的接口，用于返回容器当前 IP 与应用版本。
"""

from __future__ import annotations

import logging
import os
import socket
import sys
from dataclasses import dataclass, field

from fastapi import FastAPI

logger = logging.getLogger(__name__)


@dataclass
class RuntimeInfoService:
    """
    运行时信息服务。

    Attributes:
        app_version: 应用版本号。
        _logger:    模块日志记录器。
    """

    app_version: str = field(default_factory=lambda: os.getenv("APP_VERSION", "1.0.0"))
    _logger: logging.Logger = field(default=logger, init=False, repr=False)

    def get_current_ip(self) -> str:
        """
        获取容器当前出站 IP。

        Returns:
            当前容器优先用于出站连接的 IP，失败时返回回环地址。
        """
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
                # 使用 UDP 探测默认路由，不实际发送业务数据。
                sock.connect(("8.8.8.8", 80))
                return str(sock.getsockname()[0])
        except OSError as exc:
            self._logger.warning("获取当前 IP 失败，使用回环地址：%s", exc)
            return "127.0.0.1"

    def get_runtime_info(self) -> dict[str, str]:
        """
        获取运行时信息。

        Returns:
            包含当前 IP、应用版本与 Python 版本的字典。
        """
        return {
            "ip": self.get_current_ip(),
            "version": self.app_version,
            "python_version": sys.version.split()[0],
        }


class FastApiApplication:
    """
    FastAPI 应用工厂。

    负责注册路由并暴露 ASGI 应用实例。
    """

    def __init__(self, runtime_info_service: RuntimeInfoService) -> None:
        """
        初始化应用工厂。

        Args:
            runtime_info_service: 运行时信息服务。
        """
        self._runtime_info_service = runtime_info_service
        self.app = FastAPI(title="Api Demo", version=runtime_info_service.app_version)
        self._register_routes()

    def _register_routes(self) -> None:
        """注册 HTTP 路由。"""

        @self.app.get("/")
        async def read_root() -> dict[str, str]:
            """
            返回当前 IP 与版本信息。

            Returns:
                运行时信息字典。
            """
            return self._runtime_info_service.get_runtime_info()

        @self.app.get("/health")
        async def read_health() -> dict[str, str]:
            """
            返回健康检查结果。

            Returns:
                健康状态字典。
            """
            return {"status": "ok"}


application = FastApiApplication(RuntimeInfoService())
app = application.app
