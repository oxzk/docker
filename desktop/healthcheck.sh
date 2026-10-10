#!/usr/bin/env bash
# 同时检查本地桌面就绪状态和实际 WARP 出口, 健康检查不会主动切换直连.
set -Eeuo pipefail

# CLI 状态确认本容器的客户端已连接, 出口探测确认数据平面可用.
check_warp() {
    local status trace
    local -a proxy_args=(--noproxy '*')
    case "${WARP_ENABLED:-proxy}" in
        off) return 0 ;;
        tun) ;;
        # 清空代理绕过列表并通过 SOCKS5 解析域名, 确保检查的是代理出口.
        proxy) proxy_args=(--noproxy '' --proxy socks5h://127.0.0.1:40000) ;;
        *) return 1 ;;
    esac
    status="$(LC_ALL=C timeout 3 warp-cli --accept-tos status)" || return 1
    grep -Eq '^Status update: Connected[[:space:]]*$' <<< "$status" || return 1
    trace="$(curl "${proxy_args[@]}" --fail --silent --show-error \
        --connect-timeout 3 --max-time 5 https://www.cloudflare.com/cdn-cgi/trace)" || return 1
    grep -Eq '^warp=(on|plus)$' <<< "$trace"
}

if [[ "${1:-}" != warp ]]; then
    test -f /run/desktop/ready
    runuser -u admin -- timeout 3 xdpyinfo -display "$DISPLAY" >/dev/null
    runuser -u admin -- timeout 3 gdbus call --session \
        --dest org.gnome.Shell --object-path /org/gnome/Shell \
        --method org.freedesktop.DBus.Peer.Ping >/dev/null
fi
check_warp
