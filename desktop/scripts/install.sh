#!/usr/bin/env bash
# 在单个构建层内安装, 验证并清理桌面运行环境.
set -Eeuo pipefail

export DEBIAN_FRONTEND=noninteractive
readonly ARCH="${TARGETARCH:-$(dpkg --print-architecture)}"
readonly UV_VERSION="${UV_VERSION:-0.12.23}"
readonly PYTHON_VERSION="${PYTHON_VERSION:-3.12.13}"
readonly WORKSPACE_HOME=/home/workspace
readonly VENV_PATH="${WORKSPACE_HOME}/.venv"

# 输出未处理错误的退出码, 行号和失败命令.
report_error() {
    local status="$1" line="$2" command="$3"
    printf 'Installation failed (exit=%s, line=%s): %s\n' "$status" "$line" "$command" >&2
    exit "$status"
}
trap 'report_error "$?" "$LINENO" "$BASH_COMMAND"' ERR

case "$ARCH" in
    amd64)
        readonly FASTFETCH_ARCH=amd64
        ;;
    arm64)
        readonly FASTFETCH_ARCH=aarch64
        ;;
    *)
        printf 'Unsupported architecture: %s\n' "$ARCH" >&2
        exit 1
        ;;
esac

# 校验构建参数, 避免缺失值被拼接成无效下载地址.
require_build_args() {
    local name
    for name in KASMVNC_VERSION CLOUDFLARED_VERSION FASTFETCH_VERSION WARPSCOUT_VERSION; do
        if [[ -z "${!name:-}" ]]; then
            printf 'Missing build argument: %s\n' "$name" >&2
            return 1
        fi
    done
}

# 下载文件并在失败时保留 curl 状态码和目标地址.
download() {
    local url="$1" destination="$2" status=0
    curl \
        --fail \
        --silent \
        --show-error \
        --location \
        --connect-timeout 20 \
        --max-time 600 \
        --retry 3 \
        --retry-all-errors \
        --retry-max-time 1800 \
        --output "$destination" \
        "$url" || status=$?
    if (( status != 0 )); then
        printf 'Download failed (curl exit %s): %s\n' "$status" "$url" >&2
        return "$status"
    fi
}

# 校验命令并在成功时输出最终解析路径.
require_command() {
    local name="$1"
    if ! command -v "$name"; then
        printf 'Missing command: %s\n' "$name" >&2
        return 1
    fi
}

# 生成固定版本的 GitHub Release 下载地址.
release_url() {
    printf 'https://github.com/%s/releases/download/%s/%s' "$1" "$2" "$3"
}

# 配置最小化安装策略并安装系统运行依赖.
install_system_packages() {
    local -a packages=(
        /tmp/kasmvnc.deb
        at-spi2-core
        dbus
        dbus-x11
        fontconfig
        fonts-noto-cjk
        fonts-noto-color-emoji
        fonts-noto-mono
        gjs
        gnome-settings-daemon
        gnome-shell
        gnome-shell-extension-appindicator
        gnome-shell-extension-desktop-icons-ng
        gnome-shell-extension-ubuntu-dock
        gnome-terminal
        language-pack-gnome-zh-hans
        language-pack-zh-hans
        libasound2t64
        libegl1
        libgdk-pixbuf2.0-bin
        libgl1
        libgl1-mesa-dri
        libglib2.0-bin
        libgtk-3-0t64
        librsvg2-common
        libx11-xcb1
        iproute2
        locales
        mesa-utils
        nautilus
        procps
        ssl-cert
        tini
        ubuntu-session
        ubuntu-wallpapers
        util-linux
        x11-utils
        x11-xserver-utils
        xauth
        xdg-user-dirs
        yaru-theme-gnome-shell
        yaru-theme-gtk
        yaru-theme-icon
    )

    printf '%s\n' \
        'path-exclude=/usr/share/doc/*' \
        'path-include=/usr/share/doc/*/copyright' \
        'path-exclude=/usr/share/man/*' \
        'path-exclude=/usr/share/info/*' \
        'path-exclude=/usr/share/lintian/*' \
        > /etc/dpkg/dpkg.cfg.d/01-desktop-minimal

    apt-get update
    # 先安装下载工具, 再获取需要与其依赖一起求解的 KasmVNC deb.
    apt-get install -y --no-install-recommends ca-certificates curl
    download \
        "$(release_url kasmtech/KasmVNC "v${KASMVNC_VERSION}" "kasmvncserver_noble_${KASMVNC_VERSION}_${ARCH}.deb")" \
        /tmp/kasmvnc.deb
    apt-get install -y --no-install-recommends "${packages[@]}"
}

# 安装固定版本的独立二进制工具.
install_release_tools() {
    local fastfetch_root warpscout_archive
    fastfetch_root="fastfetch-linux-${FASTFETCH_ARCH}"
    warpscout_archive="warpscout_${WARPSCOUT_VERSION#v}_linux_${ARCH}.tar.gz"

    install -d -m 0755 /usr/local/bin

    download \
        "$(release_url fastfetch-cli/fastfetch "$FASTFETCH_VERSION" "${fastfetch_root}.tar.gz")" \
        /tmp/fastfetch.tar.gz
    tar -xzf /tmp/fastfetch.tar.gz -C /tmp "${fastfetch_root}/usr/bin/fastfetch"
    install -m 0755 "/tmp/${fastfetch_root}/usr/bin/fastfetch" /usr/local/bin/fastfetch

    download \
        "https://astral.sh/uv/${UV_VERSION}/install.sh" \
        /tmp/uv-installer.sh
    sh /tmp/uv-installer.sh

    download \
        "$(release_url vernette/warpscout "$WARPSCOUT_VERSION" "$warpscout_archive")" \
        /tmp/warpscout.tar.gz
    tar -xzf /tmp/warpscout.tar.gz -C /tmp warpscout
    install -m 0755 /tmp/warpscout /usr/local/bin/warpscout

    download \
        "$(release_url cloudflare/cloudflared "$CLOUDFLARED_VERSION" "cloudflared-linux-${ARCH}")" \
        /usr/local/bin/cloudflared
    chmod 0755 /usr/local/bin/cloudflared
}

# 生成区域, 字体和系统配置.
configure_system() {
    locale-gen zh_CN.UTF-8 en_US.UTF-8
    fc-cache -f
}

# 安装 Python, 项目依赖和 Camoufox 浏览器资源.
install_python_project() {
    uv python install "$PYTHON_VERSION"
    uv venv --python "$PYTHON_VERSION" "$VENV_PATH"
    source "$VENV_PATH/bin/activate"
    uv pip install --upgrade 'camoufox[geoip]' requests
    python -m camoufox fetch
}

# 安装镜像脚本, Python 环境和桌面配置到最终路径.
install_desktop_files() {
    install -d -m 0755 /usr/local/share/desktop/scripts
    install -d -m 0755 "$WORKSPACE_HOME"
    install -m 0755 /opt/desktop/scripts/entrypoint.sh /opt/desktop/scripts/healthcheck.sh \
        /usr/local/share/desktop/scripts/
    install -m 0755 /opt/desktop/scripts/warpscout-proxy /usr/local/bin/warpscout-proxy
    install -m 0644 /opt/desktop/main.py "${WORKSPACE_HOME}/main.py"
    install -m 0644 /opt/desktop/99-desktop.gschema.override /usr/share/glib-2.0/schemas/
    glib-compile-schemas --strict /usr/share/glib-2.0/schemas
    printf '%s\n' \
        'export PATH="$HOME/.local/bin:$PATH"' \
        "if [ -r \"${VENV_PATH}/bin/activate\" ]; then . \"${VENV_PATH}/bin/activate\"; fi" \
        > ~/.bashrc
}

# 验证关键工具.
verify_installation() {
    uv --version
    uvx --version
    fastfetch --version
    warpscout version
    cloudflared --version
    require_command Xvnc
    require_command vncpasswd
}

# 删除仅构建阶段使用的索引, 临时文件, 构建上下文和运行时标识.
cleanup_build_files() {
    apt-get clean
    rm -rf /var/lib/apt/lists/* /var/cache/debconf/*-old /run/* /tmp/* /var/tmp/*
    rm -rf /opt/desktop
    rm -f /etc/machine-id /var/lib/dbus/machine-id
    find /var/log -type f -exec truncate -s 0 {} +
}

# 按依赖顺序执行完整安装流程.
main() {
    require_build_args
    install_system_packages
    configure_system
    install_release_tools
    install_python_project
    install_desktop_files
    verify_installation
    cleanup_build_files
}

main "$@"
