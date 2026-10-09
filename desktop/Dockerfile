# syntax=docker/dockerfile:1
FROM ubuntu:24.04

ARG TARGETARCH
ARG KASMVNC_VERSION=1.5.0
ARG CLOUDFLARED_VERSION=2026.10.0
ARG UV_VERSION=0.12.23
ARG FASTFETCH_VERSION=2.69.0
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
    SHUTDOWN_TIMEOUT=15 \
    KASMVNC_WEBSOCKET_PORT=8444 \
    DESKTOP_WIDTH=1920 \
    DESKTOP_HEIGHT=1080

COPY --chmod=755 entrypoint.sh desktop-settings.sh healthcheck.sh /opt/desktop/
COPY 99-desktop.gschema.override /usr/share/glib-2.0/schemas/
RUN glib-compile-schemas --strict /usr/share/glib-2.0/schemas

ARG BUILD_REVISION=unknown
LABEL org.opencontainers.image.revision=$BUILD_REVISION
HEALTHCHECK --interval=30s --timeout=20s --start-period=300s --retries=3 \
    CMD ["/opt/desktop/healthcheck.sh"]

WORKDIR /home/admin
EXPOSE 8444
ENTRYPOINT ["/usr/bin/tini", "--", "/opt/desktop/entrypoint.sh"]
