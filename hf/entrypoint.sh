#!/usr/bin/env bash
# 文件编码：UTF-8 无 BOM
#
# HF 容器入口脚本，负责启动远程登录、FastAPI 与可选端口映射。
set -Eeuo pipefail

readonly FRPC_CONFIG="/tmp/frpc-login.toml"

log() {
    echo "[hf] $*"
}

fail() {
    echo "[hf] 错误：$*" >&2
    exit 1
}

configure_admin_user() {
    local login_password="${PASSWORD:-admin}"

    echo "root:${login_password}" | chpasswd
}

start_ssh_server() {
    # log "启动远程登录服务，监听端口：${SSH_PORT}"

    mkdir -p /run/sshd
    ssh-keygen -A >/dev/null

    if [[ "${SSH_PORT}" != "22" ]]; then
        sed -ri "s/^#?Port .*/Port ${SSH_PORT}/" /etc/ssh/sshd_config
    fi

    /usr/sbin/sshd -D -e > /tmp/sshd.log 2>&1 &
}

write_frpc_config() {

    cat >"${FRPC_CONFIG}" <<EOF
serverAddr = "${SERVER_ADDR}"
serverPort = ${SERVER_PORT}
user = "${USER:-admin}"
auth.token = "${TOKEN:-token123}"

[[proxies]]
name = "${PROXY_NAME:-ssh}"
type = "tcp"
localIP = "127.0.0.1"
localPort = ${SSH_PORT}
remotePort = ${REMOTE_PORT}
EOF
}

start_frpc_if_configured() {
    if [[ -z "${SERVER_ADDR:-}" ]]; then
        log "未设置 SERVER_ADDR，跳过"
        return 0
    fi

    # log "启动端口映射，远端端口：${REMOTE_PORT}"
    write_frpc_config

    frpc -c "${FRPC_CONFIG}" >/tmp/frpc.log 2>&1 &
}

start_fastapi_server() {
    log "启动 FastAPI 服务：http://${API_HOST}:${API_PORT}"

    python -m uvicorn app:app \
        --host "${API_HOST}" \
        --port "${API_PORT}" &
}

wait_for_processes() {
    wait -n || {
        fail "后台进程异常退出，请检查上方日志"
    }

    fail "后台进程已退出，容器即将停止"
}

main() {
    configure_admin_user
    start_ssh_server
    start_frpc_if_configured
    start_fastapi_server
    wait_for_processes
}

main "$@"
