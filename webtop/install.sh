#!/usr/bin/env bash
set -Eeuo pipefail

readonly USER="${USER:-admin}"
readonly APP_HOME="${HOME:-/home/${USER}}"
readonly APP_WORKDIR="${WORKDIR:-/workspace}"

report_error() {
    local status="$1" line="$2" command="$3"
    printf 'Installation failed (exit=%s, line=%s): %s\n' "$status" "$line" "$command" >&2
    exit "$status"
}
trap 'report_error "$?" "$LINENO" "$BASH_COMMAND"' ERR

resolve_architecture() {
    case "${TARGETARCH:-$(dpkg --print-architecture)}" in
        amd64) printf amd64 ;;
        arm64) printf arm64 ;;
        *) printf 'Unsupported architecture: %s\n' "${TARGETARCH:-unknown}" >&2; return 1 ;;
    esac
}

install_system_packages() {
    apt-get update
    apt-get install -y --no-install-recommends \
        ca-certificates curl sudo dbus dbus-x11 xfce4 xfce4-terminal \
        fonts-noto-cjk fonts-noto-color-emoji locales procps iproute2 \
        libgtk-3-0t64 libx11-xcb1 libasound2t64 \
        util-linux x11-utils xauth
}

install_kasmvnc() {
    local architecture="$1"
    curl -fsSL \
        "https://github.com/kasmtech/KasmVNC/releases/download/v${KASMVNC_VERSION}/kasmvncserver_noble_${KASMVNC_VERSION}_${architecture}.deb" \
        -o /tmp/kasmvnc.deb
    apt-get install -y --no-install-recommends /tmp/kasmvnc.deb
}

install_release_tools() {
    local architecture="$1"
    local warpscout_archive="warpscout_${WARPSCOUT_VERSION#v}_linux_${architecture}.tar.gz"
    curl -fsSL \
        "https://github.com/vernette/warpscout/releases/download/${WARPSCOUT_VERSION}/${warpscout_archive}" \
        -o /tmp/warpscout.tar.gz
    tar -xzf /tmp/warpscout.tar.gz -C /tmp warpscout
    install -m 0755 /tmp/warpscout /usr/local/bin/warpscout
    curl -fsSL \
        "https://github.com/cloudflare/cloudflared/releases/download/${CLOUDFLARED_VERSION}/cloudflared-linux-${architecture}" \
        -o /usr/local/bin/cloudflared
    chmod 0755 /usr/local/bin/cloudflared
}

create_user() {
    if ! id "$USER" >/dev/null 2>&1; then
        useradd --create-home --home-dir "$APP_HOME" --shell /bin/bash "$USER"
    fi
    install -d -o "$USER" -g "$USER" -m 0755 "$APP_HOME" "$APP_WORKDIR"
    printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$USER" > "/etc/sudoers.d/${USER}"
    chmod 0440 "/etc/sudoers.d/${USER}"
}

install_browser_tool() {
    install -o "$USER" -g "$USER" -m 0644 /tmp/main.py "${APP_WORKDIR}/main.py"
}

install_python_environment() {
    local venv_bin="${APP_WORKDIR}/.venv/bin"
    local smoke_test=/tmp/camoufox-smoke-test.py
    su - "$USER" -c "set -o pipefail; curl -LsSf https://astral.sh/uv/install.sh | sh"
    su - "$USER" -c \
        "'${APP_HOME}/.local/bin/uv' python install '${PYTHON_VERSION}' && '${APP_HOME}/.local/bin/uv' venv '${APP_WORKDIR}/.venv' && '${APP_HOME}/.local/bin/uv' pip install --python '${APP_WORKDIR}/.venv/bin/python' 'camoufox[geoip]' requests"
    # 下载 Camoufox 浏览器, 安装完成后执行无头冒烟验证.
    su - "$USER" -c "'${venv_bin}/camoufox' fetch"
    cat > "$smoke_test" <<'PYEOF'
from camoufox.sync_api import Camoufox

with Camoufox(headless=True) as browser:
    page = browser.new_page()
    page.goto("about:blank", timeout=20000)
    page.close()
PYEOF
    # 冒烟验证失败不中断安装流程, 仅输出警告.
    if ! su - "$USER" -c "'${venv_bin}/python' '${smoke_test}'"; then
        printf 'Warning: Camoufox smoke test failed, installation continues\n' >&2
    fi
    rm -f "$smoke_test"
}

configure_user_shell() {
    printf '%s\n' \
        'export PATH="$HOME/.local/bin:$PATH"' \
        "if [ -r '${APP_WORKDIR}/.venv/bin/activate' ]; then . '${APP_WORKDIR}/.venv/bin/activate'; fi" \
        > "${APP_HOME}/.bashrc"
    chown "$USER:$USER" "${APP_HOME}/.bashrc"
}

cleanup_build_files() {
    apt-get clean
    rm -rf /var/lib/apt/lists/* /tmp/kasmvnc.deb /tmp/warpscout.tar.gz \
        /tmp/warpscout /tmp/main.py /tmp/webtop-install.sh
}

main() {
    export DEBIAN_FRONTEND=noninteractive
    local architecture
    architecture="$(resolve_architecture)"
    install_system_packages
    install_kasmvnc "$architecture"
    install_release_tools "$architecture"
    create_user
    install_browser_tool
    install_python_environment
    configure_user_shell
    locale-gen en_US.UTF-8
    cleanup_build_files
}

main "$@"
