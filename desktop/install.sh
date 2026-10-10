#!/usr/bin/env bash
# 在同一构建层安装和清理全部软件, 不把下载包和运行时状态写入镜像层.
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive
arch="${TARGETARCH:-$(dpkg --print-architecture)}"
# Fastfetch 使用 aarch64 命名 ARM64 压缩包, 其他下载源仍使用 Debian 的 arm64.
case "$arch" in
    amd64) fastfetch_arch=amd64; machine_arch=x86_64 ;;
    arm64) fastfetch_arch=aarch64; machine_arch=aarch64 ;;
    *) echo "Unsupported architecture: $arch" >&2; exit 1 ;;
esac

# 下载失败时输出对应 URL 并保留 curl 退出码, 让构建错误能定位到具体软件包.
download() {
    local status=0
    curl --fail --silent --show-error --location --connect-timeout 20 --max-time 600 --retry 3 --retry-max-time 1800 "$1" -o "$2" || status=$?
    if (( status != 0 )); then
        printf 'Download failed (curl exit %s): %s\n' "$status" "$1" >&2
        return "$status"
    fi
}

# 按指定版本构造 GitHub 发布文件的下载地址.
release_url() {
    printf 'https://github.com/%s/releases/download/%s/%s' "$1" "$2" "$3"
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

# 使用支持 Noble 双架构的官方 WARP 软件源, APT 可直接读取 ASCII 公钥.
download https://pkg.cloudflareclient.com/pubkey.gpg /etc/apt/keyrings/cloudflare-warp.asc
chmod 0644 /etc/apt/keyrings/cloudflare-warp.asc
printf '%s\n' \
    'deb [signed-by=/etc/apt/keyrings/cloudflare-warp.asc] https://pkg.cloudflareclient.com/ noble main' \
    > /etc/apt/sources.list.d/cloudflare-warp.list

download "$(release_url kasmtech/KasmVNC "v${KASMVNC_VERSION}" "kasmvncserver_noble_${KASMVNC_VERSION}_${arch}.deb")" /tmp/kasmvnc.deb
packages=(/tmp/kasmvnc.deb firefox firefox-l10n-zh-cn)
if [[ "$arch" == amd64 ]]; then
    # 浏览器通过签名 APT 仓库更新, 避免直接下载会变化的 current deb 包.
    download https://dl.google.com/linux/linux_signing_key.pub /etc/apt/keyrings/google-chrome.asc
    chmod 0644 /etc/apt/keyrings/google-chrome.asc
    printf '%s\n' \
        'deb [arch=amd64 signed-by=/etc/apt/keyrings/google-chrome.asc] https://dl.google.com/linux/chrome/deb/ stable main' \
        > /etc/apt/sources.list.d/google-chrome.list
    packages+=(google-chrome-stable)
fi

# 一次求解桌面和应用依赖, 避免分层更新相同的库和包数据库.
apt-get update
apt-get install -y --no-install-recommends \
        ca-certificates curl dbus dbus-x11 fontconfig locales tini util-linux sudo cloudflare-warp \
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

# 从官方 Linux 压缩包中仅提取并安装 Fastfetch 可执行文件.
download "$(release_url fastfetch-cli/fastfetch "$FASTFETCH_VERSION" "fastfetch-linux-${fastfetch_arch}.tar.gz")" /tmp/fastfetch.tar.gz
fastfetch_root="fastfetch-linux-${fastfetch_arch}"
tar -xzf /tmp/fastfetch.tar.gz -C /tmp "$fastfetch_root/usr/bin/fastfetch"
install -d -m 0755 /usr/local/bin
install -m 0755 "/tmp/$fastfetch_root/usr/bin/fastfetch" /usr/local/bin/fastfetch

uv_target="${machine_arch}-unknown-linux-gnu"
download "$(release_url astral-sh/uv "$UV_VERSION" "uv-${uv_target}.tar.gz")" /tmp/uv.tar.gz
tar -xzf /tmp/uv.tar.gz -C /tmp
install -m 0755 "/tmp/uv-${uv_target}/uv" /usr/local/bin/uv
install -m 0755 "/tmp/uv-${uv_target}/uvx" /usr/local/bin/uvx
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
warp-cli --version
command -v warp-svc
command -v Xvnc
command -v vncpasswd

# 记录固定工具版本和 APT 实际解析的版本, 供发布后排查.
install -d /usr/local/share/image-build
{ printenv | LC_ALL=C sort | grep -E '^[A-Z_]+_VERSION=';
  dpkg-query -W -f='${binary:Package}=${Version}\n'; } \
    > /usr/local/share/image-build/versions.txt

# 在创建安装层之前清理临时文件, 避免后续层删除仍占用底层空间.
apt-get clean
rm -rf /var/lib/apt/lists/* /var/cache/debconf/*-old /run/* /tmp/* /var/tmp/*
rm -f /etc/machine-id /var/lib/dbus/machine-id
find /var/log -type f -exec truncate -s 0 {} +
