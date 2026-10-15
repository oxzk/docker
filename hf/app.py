"""
FastAPI 示例服务。

本模块提供一个简单的接口，用于返回容器当前 IP 与应用版本。
"""

from __future__ import annotations

import logging
import socket
import sys

from fastapi import FastAPI

logger = logging.getLogger(__name__)

APP_VERSION = "1.0.0"

app = FastAPI(title="Api Demo", version=APP_VERSION)


def get_current_ip() -> str:
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
        logger.warning("获取当前 IP 失败，使用回环地址：%s", exc)
        return "127.0.0.1"


@app.get("/")
async def read_root() -> dict[str, str]:
    """
    返回当前 IP、应用版本与 Python 版本。

    Returns:
        运行时信息字典。
    """
    return {
        "ip": get_current_ip(),
        "version": APP_VERSION,
        "python_version": sys.version.split()[0],
    }


@app.get("/health")
async def read_health() -> dict[str, str]:
    """
    返回健康检查结果。

    Returns:
        健康状态字典。
    """
    return {"status": "ok"}
