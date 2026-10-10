#!/usr/bin/env bash
# 独立管理可选 WARP, 初始化失败后保留客户端供手动诊断和重连.
set -Eeuo pipefail

WARP_ENABLED="${WARP_ENABLED:-proxy}"
WARP_PID=''

# 退出时断开本次连接并停止守护进程, 外层入口负责进程组的最终回收.
cleanup() {
    local status=$?
    trap - EXIT
    trap '' TERM INT
    if [[ -n "$WARP_PID" ]]; then
        timeout --kill-after=1 5 warp-cli --accept-tos disconnect >/dev/null 2>&1 || true
        kill -TERM "$WARP_PID" 2>/dev/null || true
        wait "$WARP_PID" 2>/dev/null || true
    fi
    exit "$status"
}
trap cleanup EXIT
trap 'exit 143' TERM
trap 'exit 130' INT

# 等待 WARP 自身就绪, 将超时作为局部失败返回, 不影响桌面服务.
wait_for_warp() {
    local label="$1" deadline=$((SECONDS + 90))
    shift
    until "$@" >/dev/null 2>&1; do
        if ! kill -0 "$WARP_PID" 2>/dev/null; then
            printf 'WARP daemon exited during %s\n' "$label" >&2
            return 1
        fi
        if (( SECONDS >= deadline )); then
            printf 'Timed out waiting for %s\n' "$label" >&2
            return 1
        fi
        sleep 1
    done
}

# 显式传播每一步失败, 避免条件调用函数时 Bash 忽略 errexit.
configure_warp() {
    wait_for_warp warp-daemon timeout 2 warp-cli --accept-tos settings || return
    if [[ ! -s /var/lib/cloudflare-warp/reg.json ]]; then
        timeout 30 warp-cli --accept-tos registration new >/dev/null || return
    fi
    if [[ "$WARP_ENABLED" == proxy ]]; then
        timeout 10 warp-cli --accept-tos mode proxy >/dev/null || return
        timeout 10 warp-cli --accept-tos proxy port 40000 >/dev/null || return
    else
        timeout 10 warp-cli --accept-tos mode warp+doh >/dev/null || return
    fi
    timeout 10 warp-cli --accept-tos connect >/dev/null || return
    wait_for_warp warp-connection /opt/desktop/healthcheck.sh warp || return
    printf 'WARP connected\n'
    if [[ "$WARP_ENABLED" == proxy ]]; then
        printf 'WARP proxy: 127.0.0.1:40000\n'
    fi
}

case "$WARP_ENABLED" in
    off) exit 0 ;;
    proxy) ;;
    tun)
        if [[ ! -c /dev/net/tun ]]; then
            printf 'WARP unavailable: tun requires /dev/net/tun; desktop remains running\n' >&2
            exit 1
        fi
        ;;
    *) printf 'Invalid WARP_ENABLED: expected off, proxy or tun\n' >&2; exit 1 ;;
esac

# 当前 Linux 客户端在代理模式下也维护 fwmark 策略路由, 必须有网络管理权限.
if ! capsh --has-p=cap_net_admin >/dev/null 2>&1; then
    printf 'WARP unavailable: %s requires NET_ADMIN for fwmark policy rules; desktop remains running\n' "$WARP_ENABLED" >&2
    exit 1
fi

install -d -m 700 /var/lib/cloudflare-warp
warp-svc > /run/desktop/warp.log 2>&1 &
WARP_PID=$!
if ! configure_warp; then
    printf 'WARP initialization failed; desktop remains running. Inspect /run/desktop/warp.log and warp-cli status\n' >&2
fi

# 即使初始化失败也保留守护进程, 允许通过 docker compose exec 修复连接.
status=0
wait "$WARP_PID" || status=$?
printf 'WARP daemon exited (status=%s); desktop remains running\n' "$status" >&2
(( status != 0 )) || status=1
exit "$status"
