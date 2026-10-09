FROM ubuntu:24.04

ARG TARGETARCH
ARG KASMVNC_VERSION=1.5.0
ARG CLOUDFLARED_VERSION=latest

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# 安装完整 GNOME 会话所需组件, 使用软件渲染, 不安装显示管理器.
RUN set -eux; \
    export DEBIAN_FRONTEND=noninteractive; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates curl dbus dbus-x11 fontconfig \
        fonts-noto-cjk fonts-noto-color-emoji fonts-noto-mono \
        gnome-session gnome-shell gnome-settings-daemon gnome-terminal \
        gnome-control-center nautilus adwaita-icon-theme \
        libgl1-mesa-dri libegl1 libgl1 libglib2.0-bin locales procps ssl-cert sudo \
        tini util-linux x11-xserver-utils xauth xdg-user-dirs; \
    locale-gen zh_CN.UTF-8 en_US.UTF-8; \
    arch="${TARGETARCH:-$(dpkg --print-architecture)}"; \
    case "$arch" in amd64|arm64) ;; *) echo "Unsupported architecture: $arch" >&2; exit 1 ;; esac; \
    curl --fail --location --retry 3 \
        "https://github.com/kasmtech/KasmVNC/releases/download/v${KASMVNC_VERSION}/kasmvncserver_noble_${KASMVNC_VERSION}_${arch}.deb" \
        -o /tmp/kasmvnc.deb; \
    apt-get install -y --no-install-recommends /tmp/kasmvnc.deb; \
    release_path="download/${CLOUDFLARED_VERSION}"; \
    if [ "$CLOUDFLARED_VERSION" = latest ]; then release_path=latest/download; fi; \
    curl --fail --location --retry 3 \
        "https://github.com/cloudflare/cloudflared/releases/${release_path}/cloudflared-linux-${arch}" \
        -o /usr/local/bin/cloudflared; \
    chmod 755 /usr/local/bin/cloudflared; \
    cloudflared --version; \
    command -v Xvnc; \
    command -v vncpasswd; \
    rm -f /tmp/kasmvnc.deb /etc/machine-id /var/lib/dbus/machine-id; \
    rm -rf /var/lib/apt/lists/*

# 复用 Ubuntu 基础镜像的 UID 1000, 为持久化桌面目录固定用户身份.
RUN set -eux; \
    if id ubuntu >/dev/null 2>&1; then \
        usermod -l admin -d /home/admin -m ubuntu; \
        groupmod -n admin ubuntu; \
    else \
        useradd --create-home --user-group --uid 1000 --shell /bin/bash admin; \
    fi; \
    usermod --shell /bin/bash --append --groups ssl-cert,sudo admin; \
    passwd -d admin; \
    printf 'admin ALL=(ALL:ALL) NOPASSWD: ALL\n' > /etc/sudoers.d/admin; \
    chmod 0440 /etc/sudoers.d/admin; \
    mkdir -p /opt/desktop; \
    fc-cache -f

ENV LANG=zh_CN.UTF-8 \
    LANGUAGE=zh_CN:zh \
    DISPLAY=:1 \
    XDG_RUNTIME_DIR=/run/user/1000 \
    XDG_SESSION_TYPE=x11 \
    XDG_SESSION_DESKTOP=gnome \
    XDG_CURRENT_DESKTOP=GNOME \
    GNOME_SHELL_SESSION_MODE=user \
    GDK_BACKEND=x11 \
    CLUTTER_BACKEND=x11 \
    LIBGL_ALWAYS_SOFTWARE=1 \
    GALLIUM_DRIVER=llvmpipe \
    GSK_RENDERER=cairo \
    KASMVNC_WEBSOCKET_PORT=8444 \
    DESKTOP_WIDTH=1920 \
    DESKTOP_HEIGHT=1080

# 容器不管理宿主机电源或物理 USB, 禁止将这些依赖 logind 的组件作为会话必需项.
# 同时禁用自动启动, 避免仅修改 RequiredComponents 后仍反复拉起失败进程.
RUN set -eux; \
    for component in Power UsbProtection; do \
        sed -i "s/org.gnome.SettingsDaemon.${component};//g" /usr/share/gnome-session/sessions/gnome.session; \
        printf '\nHidden=true\n' >> "/etc/xdg/autostart/org.gnome.SettingsDaemon.${component}.desktop"; \
    done

COPY entrypoint.sh xstartup /opt/desktop/
RUN chmod 755 /opt/desktop/*.sh /opt/desktop/xstartup

WORKDIR /home/admin
EXPOSE 8444
ENTRYPOINT ["/usr/bin/tini", "--", "/opt/desktop/entrypoint.sh"]
