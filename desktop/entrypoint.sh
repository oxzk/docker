#!/usr/bin/env bash
# 分别管理 D-Bus、Xvnc、GNOME Shell、设置服务和 Tunnel 的生命周期.
set -Eeuo pipefail

# 在数值进入进程参数之前校验范围.
require_number() {
    local name="$1" maximum="$2" value="${!1}"
    if [[ ! "$value" =~ ^[1-9][0-9]{0,4}$ ]] || (( 10#$value > maximum )); then
        printf 'Invalid %s: expected 1..%s\n' "$name" "$maximum" >&2
        exit 1
    fi
}

: "${PASSWORD:?Set PASSWORD for the desktop login}"
if (( ${#PASSWORD} < 6 )) || [[ "$PASSWORD" == *$'\n'* || "$PASSWORD" == *$'\r'* ]]; then
    printf 'PASSWORD must contain at least 6 characters and no line breaks\n' >&2
    exit 1
fi
require_number KASMVNC_WEBSOCKET_PORT 65535
require_number DESKTOP_WIDTH 8192
require_number DESKTOP_HEIGHT 8192
SHUTDOWN_TIMEOUT="${SHUTDOWN_TIMEOUT:-15}"
require_number SHUTDOWN_TIMEOUT 120
WARP_ENABLED="${WARP_ENABLED:-proxy}"
case "$WARP_ENABLED" in
    off|proxy|tun) ;;
    *) printf 'Invalid WARP_ENABLED: expected off, proxy or tun\n' >&2; exit 1 ;;
esac

declare -a PIDS=()
declare -A SERVICE_NAMES=()

# 将停止信号传播到所有服务的进程组, 由 tini 回收孤儿进程.
cleanup() {
    local status=$? pid pending deadline
    trap - EXIT
    trap '' TERM INT
    if [[ -n "${WARP_PID:-}" ]]; then
        if (( status != 0 && status != 130 && status != 143 )); then
            tail -n 40 /run/desktop/warp.log >&2 || true
        fi
        # 停止守护进程前先断开, 让客户端恢复它管理的路由和 DNS.
        timeout --kill-after=1 5 warp-cli --accept-tos disconnect >/dev/null 2>&1 || true
    fi
    deadline=$((SECONDS + SHUTDOWN_TIMEOUT))
    for pid in "${PIDS[@]}"; do
        kill -TERM -- "-$pid" 2>/dev/null || true
    done
    while :; do
        pending=0
        for pid in "${PIDS[@]}"; do
            if kill -0 -- "-$pid" 2>/dev/null; then pending=1; fi
        done
        (( pending != 0 )) || break
        if (( SECONDS >= deadline )); then
            printf 'Shutdown timed out, terminating remaining services\n' >&2
            for pid in "${PIDS[@]}"; do
                kill -KILL -- "-$pid" 2>/dev/null || true
            done
            break
        fi
        sleep 0.1
    done
    for pid in "${PIDS[@]}"; do wait "$pid" 2>/dev/null || true; done
    exit "$status"
}
trap cleanup EXIT
trap 'exit 143' TERM
trap 'exit 130' INT

# 用独立进程组运行前台服务, 统一输出日志并记录退出来源.
start_service() {
    local name="$1"
    shift
    setsid "$@" &
    PIDS+=("$!")
    SERVICE_NAMES[$!]="$name"
}

# 等待初始化条件时检查全部关键服务, 失败立即退出并给出服务名称.
wait_until() {
    local label="$1" deadline=$((SECONDS + 90)) pid status
    shift
    until "$@" >/dev/null 2>&1; do
        for pid in "${PIDS[@]}"; do
            if ! kill -0 "$pid" 2>/dev/null; then
                status=0
                wait "$pid" || status=$?
                printf 'Service %s exited during %s (status=%s)\n' "${SERVICE_NAMES[$pid]}" "$label" "$status" >&2
                exit 1
            fi
        done
        if (( SECONDS >= deadline )); then
            printf 'Timed out waiting for %s\n' "$label" >&2
            exit 1
        fi
        sleep 1
    done
}

# 用真实出口请求确认 WARP 已接管流量, 避免把 CLI 接受连接请求当作连接成功.
warp_connected() {
    /opt/desktop/healthcheck.sh warp
}

# 按开关初始化客户端, 复用持久化注册信息, 将守护进程纳入统一生命周期管理.
start_warp() {
    [[ "$WARP_ENABLED" != off ]] || return 0
    # 仅全局隧道模式需要内核设备和网络管理权限, 本地代理使用用户态连接.
    if [[ "$WARP_ENABLED" == tun ]]; then
        if [[ ! -c /dev/net/tun ]]; then
            printf 'WARP requires /dev/net/tun to be passed into the container\n' >&2
            exit 1
        fi
        if ! capsh --has-p=cap_net_admin >/dev/null 2>&1; then
            printf 'WARP requires the NET_ADMIN container capability\n' >&2
            exit 1
        fi
    fi
    install -d -m 700 /var/lib/cloudflare-warp
    start_service warp warp-svc > /run/desktop/warp.log 2>&1
    WARP_PID=$!
    # 未注册时连接状态本来就不正常, 使用配置接口确认守护进程已经就绪.
    wait_until warp-daemon timeout 2 warp-cli --accept-tos settings
    if [[ ! -s /var/lib/cloudflare-warp/reg.json ]]; then
        timeout 30 warp-cli --accept-tos registration new >/dev/null
    fi
    if [[ "$WARP_ENABLED" == proxy ]]; then
        timeout 10 warp-cli --accept-tos mode proxy >/dev/null
        timeout 10 warp-cli --accept-tos proxy port 40000 >/dev/null
    else
        timeout 10 warp-cli --accept-tos mode warp+doh >/dev/null
    fi
    timeout 10 warp-cli --accept-tos connect >/dev/null
    wait_until warp-connection warp_connected
    printf 'WARP connected\n'
    if [[ "$WARP_ENABLED" == proxy ]]; then
        printf 'WARP SOCKS5 proxy: 127.0.0.1:40000 (configure applications to use it)\n'
    fi
}

# 各次启动重新创建本容器的认证文件和套接字, 持久化目录只存用户数据.
install -d -m 700 -o admin -g admin /home/admin /run/desktop "$XDG_RUNTIME_DIR"
install -d -m 755 /run/dbus
install -d -m 1777 /tmp/.X11-unix /tmp/.ICE-unix
rm -f /run/dbus/pid /run/dbus/system_bus_socket "$XDG_RUNTIME_DIR/bus" \
    /tmp/.X1-lock /tmp/.X11-unix/X1 "$XAUTHORITY" /run/desktop/ready
dbus-uuidgen --ensure=/etc/machine-id
ln -sf /etc/machine-id /var/lib/dbus/machine-id
install -m 600 -o admin -g admin /dev/null "$XAUTHORITY"
runuser -u admin -- xauth -f "$XAUTHORITY" add "$DISPLAY" MIT-MAGIC-COOKIE-1 "$(mcookie)"
printf '%s\n%s\n' "$PASSWORD" "$PASSWORD" \
    | runuser -u admin -- vncpasswd -u admin -ow /run/desktop/kasmpasswd
test -s /run/desktop/kasmpasswd
chmod 600 /run/desktop/kasmpasswd
unset PASSWORD

start_service system-bus dbus-daemon --system --nofork --nopidfile
wait_until system-bus test -S /run/dbus/system_bus_socket
start_warp
start_service user-bus runuser -u admin -- dbus-daemon --session --nofork --nopidfile \
    --address="$DBUS_SESSION_BUS_ADDRESS"
wait_until user-bus runuser -u admin -- timeout 2 gdbus call --session \
    --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus \
    --method org.freedesktop.DBus.ListNames

# 直接运行 Xvnc, 不再经由 vncserver/xstartup 嵌套创建第二套会话和用户总线.
start_service xvnc runuser -u admin -- Xvnc "$DISPLAY" \
    -auth "$XAUTHORITY" -geometry "${DESKTOP_WIDTH}x${DESKTOP_HEIGHT}" -depth 24 \
    -KasmPasswordFile /run/desktop/kasmpasswd -DisableBasicAuth 0 \
    -SecurityTypes None -AlwaysShared -sslOnly 0 \
    -httpd /usr/share/kasmvnc/www \
    -websocketPort "$KASMVNC_WEBSOCKET_PORT" -interface 0.0.0.0 \
    -PublicIP 127.0.0.1 -udpPort 0 -Log '*:stdout:30'
wait_until x-server runuser -u admin -- timeout 2 xdpyinfo -display "$DISPLAY"
runuser -u admin -- dbus-update-activation-environment DISPLAY XAUTHORITY XDG_RUNTIME_DIR \
    XDG_SESSION_TYPE XDG_SESSION_DESKTOP XDG_CURRENT_DESKTOP GNOME_SHELL_SESSION_MODE
runuser -u admin -- /opt/desktop/desktop-settings.sh

# 只运行远程桌面需要的用户服务, 不启动依赖物理登录席位的宿主机电源/USB 管理.
for component in xsettings keyboard media-keys sound a11y-settings; do
    start_service "settings-$component" runuser -u admin -- "/usr/libexec/gsd-$component"
done
start_service gnome-shell runuser -u admin -- gnome-shell --x11 --mode=ubuntu
printf 'GNOME desktop starting: http://localhost:%s, username=admin\n' "$KASMVNC_WEBSOCKET_PORT"

if [[ -n "${CLOUDFLARED_TOKEN:-}" ]]; then
    start_service cloudflared env TUNNEL_TOKEN="$CLOUDFLARED_TOKEN" cloudflared tunnel --no-autoupdate run
else
    start_service cloudflared cloudflared tunnel --no-autoupdate --url "http://127.0.0.1:${KASMVNC_WEBSOCKET_PORT}"
fi
unset CLOUDFLARED_TOKEN
touch /run/desktop/ready

status=0
wait -n -p exited_pid "${PIDS[@]}" || status=$?
printf 'Service %s exited (status=%s)\n' "${SERVICE_NAMES[${exited_pid:-0}]:-unknown}" "$status" >&2
(( status != 0 )) || status=1
exit "$status"
