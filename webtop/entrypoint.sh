#!/usr/bin/env bash
set -Eeuo pipefail

readonly USER="${USER:-admin}"
export HOME="${HOME:-$(getent passwd "$USER" | cut -d: -f6)}"
export DISPLAY="${DISPLAY:-:1}"
export KASMVNC_WEBSOCKET_PORT="${KASMVNC_WEBSOCKET_PORT:-8444}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/runtime-${USER}}"
readonly WORKDIR="${WORKDIR:-/workspace}"
readonly KASMPASSWD_FILE="/tmp/kasmpasswd-${USER}"

declare -a PIDS=()
USE_QUICK_TUNNEL=0

prepare_runtime() {
    cd "$WORKDIR"
    install -d -m 0700 "$XDG_RUNTIME_DIR" "$HOME/.local/state"
    # 目录已存在且属主为 root 时 install -d 无法 chmod 会失败, 因此容忍失败.
    mkdir -p /tmp/.X11-unix /tmp/.ICE-unix 2>/dev/null || true
    chmod 1777 /tmp/.X11-unix /tmp/.ICE-unix 2>/dev/null || true
    rm -f "$KASMPASSWD_FILE"
}

cleanup() {
    local status=$? pid
    trap - EXIT
    for pid in "${PIDS[@]}"; do kill "$pid" 2>/dev/null || true; done
    for pid in "${PIDS[@]}"; do wait "$pid" 2>/dev/null || true; done
    warpscout-proxy stop >/dev/null 2>&1 || true
    exit "$status"
}

start_kasmvnc() {
    # 设置 PASSWORD 时启用 Web Basic Auth, 否则关闭认证直接进入桌面.
    local -a security_args=(-SecurityTypes None -AlwaysShared)
    if [[ -n "${PASSWORD:-}" ]]; then
        printf '%s\n%s\n' "$PASSWORD" "$PASSWORD" \
            | vncpasswd -u "$USER" -ow "$KASMPASSWD_FILE"
        chmod 600 "$KASMPASSWD_FILE"
        security_args+=(-KasmPasswordFile "$KASMPASSWD_FILE" -DisableBasicAuth 0)
        unset PASSWORD
    else
        security_args+=(-DisableBasicAuth 1)
    fi
    Xvnc "$DISPLAY" -geometry 1920x1080 -depth 24 \
        "${security_args[@]}" -sslOnly 0 \
        -httpd /usr/share/kasmvnc/www -websocketPort "$KASMVNC_WEBSOCKET_PORT" \
        -interface 0.0.0.0 -PublicIP 127.0.0.1 -udpPort 0 -Log '*:stdout:30' &
    PIDS+=("$!")
}

wait_for_x_server() {
    local attempt
    for attempt in {1..90}; do
        if xdpyinfo -display "$DISPLAY" >/dev/null 2>&1; then return 0; fi
        if ! kill -0 "${PIDS[0]}" 2>/dev/null; then
            printf 'KasmVNC exited before X became available\n' >&2
            return 1
        fi
        sleep 1
    done
    printf 'Timed out waiting for KasmVNC X server\n' >&2
    return 1
}

start_desktop() {
    dbus-run-session -- startxfce4 &
    PIDS+=("$!")
}

start_cloudflared() {
    if [[ -n "${CLOUDFLARED_TOKEN:-}" ]]; then
        cloudflared tunnel --no-autoupdate run --token "$CLOUDFLARED_TOKEN" \
            >/tmp/cloudflared.log 2>&1 &
    else
        USE_QUICK_TUNNEL=1
        cloudflared tunnel --no-autoupdate --url "http://127.0.0.1:${KASMVNC_WEBSOCKET_PORT}" \
            >/tmp/cloudflared.log 2>&1 &
    fi
    PIDS+=("$!")
    unset CLOUDFLARED_TOKEN
}

print_quick_tunnel_url() {
    local attempt tunnel_url
    for attempt in {1..60}; do
        tunnel_url="$(grep -Eo 'https://[a-zA-Z0-9.-]+\.trycloudflare\.com' /tmp/cloudflared.log | tail -n 1 || true)"
        if [[ -n "$tunnel_url" ]]; then
            printf 'Cloudflare Quick Tunnel: %s\n' "$tunnel_url"
            return 0
        fi
        if ! kill -0 "${PIDS[2]}" 2>/dev/null; then
            printf 'cloudflared exited before a temporary address was parsed\n' >&2
            cat /tmp/cloudflared.log >&2
            return 1
        fi
        sleep 1
    done
    printf 'Timed out waiting for Cloudflare Quick Tunnel address\n' >&2
    return 1
}

main() {
    prepare_runtime
    trap cleanup EXIT
    trap 'exit 143' TERM
    trap 'exit 130' INT
    start_kasmvnc
    wait_for_x_server
    start_desktop
    start_cloudflared
    # Warpscout 不可用时仅告警, 不阻断桌面启动.
    warpscout-proxy start \
        || printf 'Warning: Warpscout proxy failed to start, desktop continues without proxy\n' >&2
    if (( USE_QUICK_TUNNEL != 0 )); then
        print_quick_tunnel_url
    fi
    printf 'XFCE desktop ready: http://localhost:%s, user=%s\n' \
        "$KASMVNC_WEBSOCKET_PORT" "$USER"
    wait -n "${PIDS[@]}"
}

main "$@"
