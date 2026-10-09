#!/usr/bin/env bash
# 在同一构建层安装和清理全部软件, 不把下载包和运行时状态写入镜像层.
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive
arch="${TARGETARCH:-$(dpkg --print-architecture)}"
case "$arch" in amd64|arm64) ;; *) echo "Unsupported architecture: $arch" >&2; exit 1 ;; esac

# 下载失败时重试, 让 HTTP 错误直接终止构建.
download() {
    curl --fail --silent --show-error --location --retry 3 "$1" -o "$2"
}

# 统一解析 GitHub 的固定版本和最新版本下载地址.
release_url() {
    local repository="$1" version="$2" asset="$3" path="download/$2"
    if [[ "$version" == latest ]]; then path=latest/download; fi
    printf 'https://github.com/%s/releases/%s/%s' "$repository" "$path" "$asset"
}

# 安装前排除离线文档, 保留版权文件和全部运行时语言资源.
printf '%s\n' \
    'path-exclude=/usr/share/doc/*' \
    'path-include=/usr/share/doc/*/copyright' \
    'path-exclude=/usr/share/man/*' \
    'path-exclude=/usr/share/info/*' \
    'path-exclude=/usr/share/lintian/*' \
    > /etc/dpkg/dpkg.cfg.d/01-desktop-minimal

apt-get update
apt-get install -y --no-install-recommends ca-certificates curl
install -d -m 0755 /etc/apt/keyrings
download https://packages.mozilla.org/apt/repo-signing-key.gpg /etc/apt/keyrings/packages.mozilla.org.asc
chmod 0644 /etc/apt/keyrings/packages.mozilla.org.asc
printf '%s\n' \
    'deb [signed-by=/etc/apt/keyrings/packages.mozilla.org.asc] https://packages.mozilla.org/apt mozilla main' \
    > /etc/apt/sources.list.d/mozilla.list
# 强制选用 Mozilla deb, 避免 Ubuntu Firefox 过渡包安装 Snap.
printf '%s\n' 'Package: *' 'Pin: origin packages.mozilla.org' 'Pin-Priority: 1000' \
    > /etc/apt/preferences.d/mozilla

download "$(release_url kasmtech/KasmVNC "v${KASMVNC_VERSION}" "kasmvncserver_noble_${KASMVNC_VERSION}_${arch}.deb")" /tmp/kasmvnc.deb
download "$(release_url fastfetch-cli/fastfetch "$FASTFETCH_VERSION" "fastfetch-linux-${arch}.deb")" /tmp/fastfetch.deb
packages=(/tmp/kasmvnc.deb /tmp/fastfetch.deb firefox firefox-l10n-zh-cn)
if [[ "$arch" == amd64 ]]; then
    download https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb /tmp/google-chrome.deb
    packages+=(/tmp/google-chrome.deb)
fi

# 一次求解桌面和应用依赖, 避免分层更新相同的库和包数据库.
apt-get update
apt-get install -y --no-install-recommends \
        ca-certificates curl dbus dbus-x11 fontconfig locales tini util-linux sudo \
        fonts-noto-cjk fonts-noto-color-emoji fonts-noto-mono \
        gnome-shell ubuntu-session gnome-settings-daemon \
        gnome-terminal nautilus \
        gnome-shell-extension-ubuntu-dock gnome-shell-extension-appindicator \
        gnome-shell-extension-desktop-icons-ng \
        yaru-theme-gtk yaru-theme-icon yaru-theme-gnome-shell ubuntu-wallpapers \
        librsvg2-common libgdk-pixbuf2.0-bin at-spi2-core gjs \
        libgl1-mesa-dri libegl1 libgl1 libglib2.0-bin mesa-utils \
        language-pack-zh-hans language-pack-gnome-zh-hans \
        procps ssl-cert xauth x11-utils x11-xserver-utils xdg-user-dirs \
    "${packages[@]}"

uv_path="${UV_VERSION}/install.sh"
if [[ "$UV_VERSION" == latest ]]; then uv_path=install.sh; fi
download "https://astral.sh/uv/${uv_path}" /tmp/uv-install.sh
UV_UNMANAGED_INSTALL=/usr/local/bin sh /tmp/uv-install.sh
download "$(release_url cloudflare/cloudflared "$CLOUDFLARED_VERSION" "cloudflared-linux-${arch}")" /usr/local/bin/cloudflared
chmod 0755 /usr/local/bin/cloudflared

locale-gen zh_CN.UTF-8 en_US.UTF-8
usermod -l admin -d /home/admin -m ubuntu
groupmod -n admin ubuntu
usermod --shell /bin/bash --append --groups ssl-cert,sudo admin
passwd -d admin
printf 'admin ALL=(ALL:ALL) NOPASSWD: ALL\n' > /etc/sudoers.d/admin
chmod 0440 /etc/sudoers.d/admin
fc-cache -f

uv --version
uvx --version
fastfetch --version
firefox --version
if [[ "$arch" == amd64 ]]; then google-chrome --version; fi
cloudflared --version
command -v Xvnc
command -v vncpasswd

# 在创建安装层之前清理临时文件, 避免后续层删除仍占用底层空间.
apt-get clean
rm -rf /var/lib/apt/lists/* /var/cache/debconf/*-old /run/* /tmp/* /var/tmp/*
rm -f /etc/machine-id /var/lib/dbus/machine-id
find /var/log -type f -exec truncate -s 0 {} +
