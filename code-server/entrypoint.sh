#!/usr/bin/env bash
# 管理编辑器进程组, 验证运行参数并等待服务有序退出.
set -Eeuo pipefail

declare -a PIDS=()
declare -A SERVICE_NAMES=()

# 在配置进入服务参数前检查端口和退出等待时间.
require_number() {
    local name="$1" maximum="$2" value="${!1}"
    if [[ ! "$value" =~ ^[1-9][0-9]{0,4}$ ]] || (( 10#$value > maximum )); then
        printf 'Invalid %s: expected 1..%s\n' "$name" "$maximum" >&2
        exit 1
    fi
}

# 要求显式设置密码, 避免遗漏配置时暴露固定凭据.
require_password() {
    : "${PASSWORD:?Set PASSWORD for code-server login}"
    if (( ${#PASSWORD} < 6 )) || [[ "$PASSWORD" == *$'\n'* || "$PASSWORD" == *$'\r'* ]]; then
        printf 'PASSWORD must contain at least 6 characters and no line breaks\n' >&2
        exit 1
    fi
}

# 同时通知所有服务, 等待进程组退出, 仅强制结束超过期限的服务.
cleanup() {
    local status=$? pid pending deadline=$((SECONDS + SHUTDOWN_TIMEOUT))
    trap - EXIT
    trap '' TERM INT
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

# 用独立进程组启动服务, 保留名称以定位异常退出来源.
start_service() {
    local name="$1"
    shift
    setsid "$@" &
    PIDS+=("$!")
    SERVICE_NAMES[$!]="$name"
}

# 校验后启动服务, 服务退出时终止实例并保留退出来源.
main() {
    SERVER_PORT="${SERVER_PORT:-9091}"
    SHUTDOWN_TIMEOUT="${SHUTDOWN_TIMEOUT:-15}"
    require_number SERVER_PORT 65535
    require_number SHUTDOWN_TIMEOUT 120
    require_password
    trap cleanup EXIT
    trap 'exit 143' TERM
    trap 'exit 130' INT
    # 只向编辑器进程传递登录密码.
    export -n PASSWORD
    start_service code-server env PASSWORD="$PASSWORD" code-server \
        --bind-addr "0.0.0.0:$SERVER_PORT" --app-name code-server \
        --disable-telemetry --auth password /workspace
    unset PASSWORD
    local status=0 exited_pid
    wait -n -p exited_pid "${PIDS[@]}" || status=$?
    printf 'Service %s exited (status=%s)\n' "${SERVICE_NAMES[${exited_pid:-0}]:-unknown}" "$status" >&2
    (( status != 0 )) || status=1
    exit "$status"
}

main "$@"
