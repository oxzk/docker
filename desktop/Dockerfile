FROM ubuntu:24.04

ARG TARGETARCH
ARG KASMVNC_VERSION=1.5.0
ARG CLOUDFLARED_VERSION=latest
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# 安装容器桌面的完整渲染链和 Ubuntu Shell 扩展, 显式声明无推荐安装时缺失的组件.
RUN set -eux; \
    export DEBIAN_FRONTEND=noninteractive; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates curl dbus dbus-x11 fontconfig locales tini util-linux sudo \
        fonts-noto-cjk fonts-noto-color-emoji fonts-noto-mono \
        gnome-shell ubuntu-session gnome-settings-daemon gnome-control-center \
        gnome-terminal nautilus gnome-system-monitor gnome-text-editor \
        gnome-shell-extension-ubuntu-dock gnome-shell-extension-appindicator \
        gnome-shell-extension-desktop-icons-ng gnome-shell-extension-ubuntu-tiling-assistant \
        yaru-theme-gtk yaru-theme-icon yaru-theme-gnome-shell ubuntu-wallpapers \
        librsvg2-common libgdk-pixbuf2.0-bin at-spi2-core gjs \
        libgl1-mesa-dri libegl1 libgl1 libglib2.0-bin mesa-utils \
        language-pack-zh-hans language-pack-gnome-zh-hans \
        procps ssl-cert xauth x11-utils x11-xserver-utils xdg-user-dirs; \
    locale-gen zh_CN.UTF-8 en_US.UTF-8; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

# 独立安装远程访问组件, 保留版本参数和 amd64/arm64 构建支持.
RUN set -eux; \
    arch="${TARGETARCH:-$(dpkg --print-architecture)}"; \
    case "$arch" in amd64|arm64) ;; *) echo "Unsupported architecture: $arch" >&2; exit 1 ;; esac; \
    curl --fail --location --retry 3 \
        "https://github.com/kasmtech/KasmVNC/releases/download/v${KASMVNC_VERSION}/kasmvncserver_noble_${KASMVNC_VERSION}_${arch}.deb" \
        -o /tmp/kasmvnc.deb; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends /tmp/kasmvnc.deb; \
    release_path="download/${CLOUDFLARED_VERSION}"; \
    if [ "$CLOUDFLARED_VERSION" = latest ]; then release_path=latest/download; fi; \
    curl --fail --location --retry 3 \
        "https://github.com/cloudflare/cloudflared/releases/${release_path}/cloudflared-linux-${arch}" \
        -o /usr/local/bin/cloudflared; \
    chmod 755 /usr/local/bin/cloudflared; \
    cloudflared --version; \
    command -v Xvnc; \
    command -v vncpasswd; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /tmp/kasmvnc.deb

# 固定持久化目录的用户身份, 仅由入口进程负责系统服务和目录权限.
RUN set -eux; \
    usermod -l admin -d /home/admin -m ubuntu; \
    groupmod -n admin ubuntu; \
    usermod --shell /bin/bash --append --groups ssl-cert,sudo admin; \
    passwd -d admin; \
    printf 'admin ALL=(ALL:ALL) NOPASSWD: ALL\n' > /etc/sudoers.d/admin; \
    chmod 0440 /etc/sudoers.d/admin; \
    fc-cache -f

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
    KASMVNC_WEBSOCKET_PORT=8444 \
    DESKTOP_WIDTH=1920 \
    DESKTOP_HEIGHT=1080

COPY entrypoint.sh desktop-settings.sh desktop-ready.sh /opt/desktop/
# /run 是运行时状态, 不将安装软件时生成的 systemd seats 等目录打包进镜像.
RUN chmod 755 /opt/desktop/*.sh; \
    rm -rf /run/* /tmp/* /var/tmp/*; \
    rm -f /etc/machine-id /var/lib/dbus/machine-id

WORKDIR /home/admin
EXPOSE 8444
HEALTHCHECK --interval=30s --timeout=10s --start-period=90s --retries=3 CMD /opt/desktop/desktop-ready.sh
ENTRYPOINT ["/usr/bin/tini", "--", "/opt/desktop/entrypoint.sh"]
