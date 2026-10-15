#!/usr/bin/env bash
# 文件编码：UTF-8 无 BOM
#
# HF 容器入口脚本，负责启动远程登录、FastAPI 与 frpc 隧道。
set -Eeuo pipefail

readonly API_HOST="0.0.0.0"
readonly API_PORT=7860

declare -a PIDS=()
FRPC_CONFIG_DIR=""
FRPC_CONFIG_PATH=""

log() {
    echo "[hf] $*"
}

fail() {
    echo "[hf] 错误：$*" >&2
    exit 1
}

cleanup() {
    local status=$? pid
    trap - EXIT
    for pid in "${PIDS[@]}"; do kill "$pid" 2>/dev/null || true; done
    for pid in "${PIDS[@]}"; do wait "$pid" 2>/dev/null || true; done
    if [[ -n "${FRPC_CONFIG_DIR}" ]]; then
        rm -rf "${FRPC_CONFIG_DIR}"
    fi
    exit "$status"
}

configure_root_password() {
    local login_password="${PASSWORD:-admin}"

    echo "root:${login_password}" | chpasswd
}

start_ssh_server() {
    mkdir -p /run/sshd
    ssh-keygen -A >/dev/null

    /usr/sbin/sshd -D -e > /tmp/sshd.log 2>&1 &
    PIDS+=("$!")
}

# 解析唯一配置来源，并在启动服务前校验配置。
configure_frpc() {
    if [[ -n "${FRPC_CONFIG:-}" && -n "${FRPC_CONFIG_BASE64:-}" ]]; then
        fail "FRPC_CONFIG 与 FRPC_CONFIG_BASE64 只能设置一个"
    fi
    if [[ -z "${FRPC_CONFIG:-}" && -z "${FRPC_CONFIG_BASE64:-}" ]]; then
        fail "必须设置 FRPC_CONFIG 或 FRPC_CONFIG_BASE64"
    fi

    if [[ -n "${FRPC_CONFIG_BASE64:-}" || "${FRPC_CONFIG:-}" == http://* || "${FRPC_CONFIG:-}" == https://* ]]; then
        # 将含凭据的配置限制在私有临时目录中，退出时统一清理。
        FRPC_CONFIG_DIR="$(mktemp -d /tmp/hf-frpc.XXXXXX)"
        FRPC_CONFIG_PATH="${FRPC_CONFIG_DIR}/frpc.toml"
        if [[ -n "${FRPC_CONFIG_BASE64:-}" ]]; then
            printf '%s' "${FRPC_CONFIG_BASE64}" | base64 --decode >"${FRPC_CONFIG_PATH}" \
                || fail "FRPC_CONFIG_BASE64 不是有效的 Base64 字符串"
        else
            curl --fail --silent --show-error --location \
                --proto '=http,https' --proto-redir '=http,https' \
                --connect-timeout 10 --max-time 60 \
                "${FRPC_CONFIG}" -o "${FRPC_CONFIG_PATH}" \
                || fail "下载 frpc 配置失败"
        fi
        chmod 0600 "${FRPC_CONFIG_PATH}"
    else
        FRPC_CONFIG_PATH="${FRPC_CONFIG}"
    fi

    unset FRPC_CONFIG_BASE64
    [[ -f "${FRPC_CONFIG_PATH}" && -r "${FRPC_CONFIG_PATH}" && -s "${FRPC_CONFIG_PATH}" ]] \
        || fail "frpc 配置文件必须存在、可读且非空"
    frpc verify -c "${FRPC_CONFIG_PATH}" || fail "frpc 配置校验失败"
}

# 将 frpc 纳入容器进程监管，并直接输出日志。
start_frpc() {
    log "启动 frpc 隧道"
    frpc -c "${FRPC_CONFIG_PATH}" &
    PIDS+=("$!")
}

start_fastapi_server() {
    log "启动 FastAPI 服务：http://${API_HOST}:${API_PORT}"

    python -m uvicorn app:app \
        --host "${API_HOST}" \
        --port "${API_PORT}" &
    PIDS+=("$!")
}

wait_for_processes() {
    wait -n "${PIDS[@]}" || {
        fail "后台进程异常退出，请检查上方日志"
    }

    fail "后台进程已退出，容器即将停止"
}

main() {
    trap cleanup EXIT
    trap 'exit 143' TERM
    trap 'exit 130' INT

    configure_frpc
    configure_root_password
    start_ssh_server
    start_fastapi_server
    start_frpc
    wait_for_processes
}

main "$@"
