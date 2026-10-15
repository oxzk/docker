# syntax=docker/dockerfile:1
FROM ubuntu:24.04

ARG TARGETARCH
ARG KASMVNC_VERSION=1.5.0
ARG CLOUDFLARED_VERSION=2026.10.0
ARG FASTFETCH_VERSION=2.69.0
ARG WARPSCOUT_VERSION=v0.16.0
ENV HOME=/home \
    PATH=/home/.local/bin:$PATH
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

COPY . /opt/desktop/
RUN --mount=type=cache,target=/var/cache/uv \
    bash /opt/desktop/scripts/install.sh

ENV LANG=zh_CN.UTF-8 \
    LANGUAGE=zh_CN:zh \
    DISPLAY=:1 \
    XAUTHORITY=/run/desktop/Xauthority \
    XDG_RUNTIME_DIR=/run/user/0 \
    DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/0/bus \
    XDG_SESSION_TYPE=x11 \
    XDG_SESSION_DESKTOP=ubuntu \
    DESKTOP_SESSION=ubuntu \
    XDG_CURRENT_DESKTOP=ubuntu:GNOME \
    GNOME_SHELL_SESSION_MODE=ubuntu \
    GDK_BACKEND=x11 \
    LIBGL_ALWAYS_SOFTWARE=1 \
    GALLIUM_DRIVER=llvmpipe \
    GSK_RENDERER=cairo \
    KASMVNC_WEBSOCKET_PORT=8444 \
    DESKTOP_WIDTH=1920 \
    DESKTOP_HEIGHT=1080
ARG BUILD_REVISION=unknown
LABEL org.opencontainers.image.revision=$BUILD_REVISION
HEALTHCHECK --interval=30s --timeout=20s --start-period=300s --retries=3 \
    CMD ["/usr/local/share/desktop/scripts/healthcheck.sh"]

USER root
WORKDIR /home/workspace
EXPOSE 8444
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/share/desktop/scripts/entrypoint.sh"]
