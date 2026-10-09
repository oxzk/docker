# syntax=docker/dockerfile:1
FROM ubuntu:24.04

ARG TARGETARCH
ARG KASMVNC_VERSION=1.5.0
ARG CLOUDFLARED_VERSION=latest
ARG UV_VERSION=latest
ARG FASTFETCH_VERSION=latest
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# 使用临时构建挂载执行安装, 将软件安装与清理收敛到同一层.
RUN --mount=type=bind,source=install.sh,target=/build/install.sh \
    bash /build/install.sh

ENV LANG=zh_CN.UTF-8 \
    LANGUAGE=zh_CN:zh \
    HOME=/home/admin \
    DISPLAY=:1 \
    XAUTHORITY=/run/desktop/Xauthority \
    XDG_RUNTIME_DIR=/run/user/1000 \
    DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
    XDG_SESSION_TYPE=x11 \
    XDG_SESSION_DESKTOP=ubuntu \
    DESKTOP_SESSION=ubuntu \
    XDG_CURRENT_DESKTOP=ubuntu:GNOME \
    GNOME_SHELL_SESSION_MODE=ubuntu \
    GDK_BACKEND=x11 \
    LIBGL_ALWAYS_SOFTWARE=1 \
    GALLIUM_DRIVER=llvmpipe \
    GSK_RENDERER=cairo \
    WARP_ENABLED=true \
    KASMVNC_WEBSOCKET_PORT=8444 \
    DESKTOP_WIDTH=1920 \
    DESKTOP_HEIGHT=1080

COPY --chmod=755 entrypoint.sh desktop-settings.sh /opt/desktop/

WORKDIR /home/admin
EXPOSE 8444
ENTRYPOINT ["/usr/bin/tini", "--", "/opt/desktop/entrypoint.sh"]
