#!/usr/bin/env bash
# 文件编码：UTF-8 无 BOM
#
# code-server 容器入口脚本，负责启动 SSH 服务与 code-server。

set -Eeuo pipefail

log() {
    echo "[code-server] $*"
}

fail() {
    echo "[code-server] 错误：$*" >&2
    exit 1
}

configure_root_login() {
    local login_password="${PASSWORD:-code001}"

    echo "root:${login_password}" | chpasswd
}

start_ssh_server() {
    log "启动 SSH 服务，监听端口：${SSH_PORT:-22}"

    mkdir -p /run/sshd
    ssh-keygen -A >/dev/null

    if [[ -n "${SSH_PORT:-}" && "${SSH_PORT}" != "22" ]]; then
        sed -ri "s/^#?Port .*/Port ${SSH_PORT}/" /etc/ssh/sshd_config
    fi

    /usr/sbin/sshd -D -e >/tmp/sshd.log 2>&1 &
}

start_code_server() {
    log "启动 code-server，监听端口：${SERVER_PORT:-9091}"

    code-server \
        --bind-addr "0.0.0.0:${SERVER_PORT:-9091}" \
        --app-name code-server \
        --disable-telemetry \
        --auth password \
        /workspace &
}

wait_for_processes() {
    wait -n || {
        fail "后台进程异常退出，请检查 /tmp/sshd.log 或 code-server 输出"
    }

    fail "后台进程已退出，容器即将停止"
}

main() {
    configure_root_login
    start_ssh_server
    start_code_server
    wait_for_processes
}

main "$@"
