#!/usr/bin/env bash
set -Eeuo pipefail

MCP_PID=""
CLOUDFLARED_PID=""
AUTH_ARGS=()
MCP_LOG=/tmp/coding-tools-mcp.log
CLOUDFLARED_LOG=/tmp/cloudflared.log

log() {
    echo "[coding-tools-mcp] $*"
}

cleanup() {
    local exit_code=$?

    if [[ -n "${CLOUDFLARED_PID}" ]]; then
        kill "${CLOUDFLARED_PID}" >/dev/null 2>&1 || true
        wait "${CLOUDFLARED_PID}" >/dev/null 2>&1 || true
    fi

    if [[ -n "${MCP_PID}" ]]; then
        kill "${MCP_PID}" >/dev/null 2>&1 || true
        wait "${MCP_PID}" >/dev/null 2>&1 || true
    fi

    exit "${exit_code}"
}

terminate() {
    log "收到停止信号，正在关闭服务"
    exit 143
}

trap cleanup EXIT
trap terminate TERM INT

require_directory() {
    if [[ ! -d "${MCP_WORKSPACE}" ]]; then
        log "错误：workspace 不存在：${MCP_WORKSPACE}" >&2
        exit 1
    fi
}

wait_for_port() {
    local host="$1"
    local port="$2"
    local timeout="${3:-30}"

    for i in $(seq 1 "${timeout}"); do
        if (echo >"/dev/tcp/${host}/${port}") >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done

    return 1
}

# 从 cloudflared 日志解析 quick tunnel 访问地址，最多等待指定秒数。
wait_for_cloudflared_url() {
    local timeout="${1:-60}"
    local tunnel_url=""

    for i in $(seq 1 "${timeout}"); do
        tunnel_url="$(grep -Eo 'https://[a-zA-Z0-9.-]+[.]trycloudflare[.]com' "${CLOUDFLARED_LOG}" 2>/dev/null | tail -n 1 || true)"
        if [[ -n "${tunnel_url}" ]]; then
            log "cloudflared 访问地址：${tunnel_url}"
            return 0
        fi

        if [[ -n "${CLOUDFLARED_PID}" ]] && ! kill -0 "${CLOUDFLARED_PID}" >/dev/null 2>&1; then
            log "警告：cloudflared 已退出，未解析到访问地址"
            return 1
        fi

        log "等待 cloudflared 访问地址... (${i}/${timeout})"
        sleep 1
    done

    log "警告：${timeout} 秒内未解析到 cloudflared 访问地址，请查看 ${CLOUDFLARED_LOG}"
    return 1
}

prepare_authentication() {
    local auth_mode="${CODING_TOOLS_MCP_AUTH_MODE:-oauth}"

    export CODING_TOOLS_MCP_AUTH_MODE="${auth_mode}"

    case "${auth_mode}" in
        bearer)
            if [[ -z "${CODING_TOOLS_MCP_AUTH_TOKEN:-}" ]]; then
                CODING_TOOLS_MCP_AUTH_TOKEN="$(openssl rand -hex 32)"
                export CODING_TOOLS_MCP_AUTH_TOKEN
                log "未设置 CODING_TOOLS_MCP_AUTH_TOKEN，已自动生成 MCP bearer token：${CODING_TOOLS_MCP_AUTH_TOKEN}"
            fi
            AUTH_ARGS=(--auth-token "${CODING_TOOLS_MCP_AUTH_TOKEN}")
            ;;
        oauth)
            if [[ -z "${CODING_TOOLS_MCP_OAUTH_PASSWORD:-}" ]]; then
                CODING_TOOLS_MCP_OAUTH_PASSWORD="$(openssl rand -hex 32)"
                export CODING_TOOLS_MCP_OAUTH_PASSWORD
                log "未设置 CODING_TOOLS_MCP_OAUTH_PASSWORD，已自动生成 OAuth 授权页密码：${CODING_TOOLS_MCP_OAUTH_PASSWORD}"
            fi
            if [[ -n "${CODING_TOOLS_MCP_OAUTH_CLIENT_ID:-}" ]]; then
                log "预注册 OAuth 客户端：${CODING_TOOLS_MCP_OAUTH_CLIENT_ID}（固定 client_id，重启后仍有效）"
                if [[ -n "${CODING_TOOLS_MCP_OAUTH_REDIRECT_URIS:-}" ]]; then
                    log "预注册客户端回调地址：${CODING_TOOLS_MCP_OAUTH_REDIRECT_URIS}"
                else
                    log "提示：未设置 CODING_TOOLS_MCP_OAUTH_REDIRECT_URIS，上游使用回环地址回退；生产客户端请显式设置回调地址"
                fi
            fi
            log "OAuth 2.1 Authorization Code + PKCE 已启用；MCP 客户端访问 HTTPS /mcp 地址后自动发现并注册，授权时输入上面的密码"
            AUTH_ARGS=(--oauth-mode)
            ;;
        noauth)
            log "警告：noauth 模式未启用认证，仅适合回环地址或受信任的内网环境"
            ;;
        *)
            log "错误：CODING_TOOLS_MCP_AUTH_MODE 必须是 bearer、oauth 或 noauth，当前为：${auth_mode}" >&2
            exit 1
            ;;
    esac
}

start_mcp_http() {
    log "启动 HTTP MCP：${MCP_HOST}:${MCP_PORT}"
    log "workspace：${MCP_WORKSPACE}"

    # 服务日志实时输出到容器日志，同时通过 tee 保留到文件以便失败时查看。
    # 使用进程替换而非管道，确保 MCP_PID 仍是服务进程本身。
    coding-tools-mcp \
        --workspace "${MCP_WORKSPACE}" \
        --host "${MCP_HOST}" \
        --port "${MCP_PORT}" \
        --permission-mode "${CODING_TOOLS_MCP_PERMISSION_MODE}" \
        "${AUTH_ARGS[@]}" \
        > >(tee "${MCP_LOG}") 2>&1 &
    MCP_PID="$!"

    if ! wait_for_port "127.0.0.1" "${MCP_PORT}" 30; then
        log "错误：MCP 未在端口 ${MCP_PORT} 启动，日志如下：" >&2
        sed -n '1,160p' "${MCP_LOG}" >&2 || true
        exit 1
    fi

    log "MCP 已监听端口 ${MCP_PORT}，端点：http://127.0.0.1:${MCP_PORT}/mcp"
}

start_cloudflared() {
    if [[ -n "${CLOUDFLARED_TUNNEL_TOKEN:-}" ]]; then
        log "启动 cloudflared token tunnel"
        # token 仅通过参数传递给 cloudflared，不写入日志。
        cloudflared tunnel --no-autoupdate run \
            --token "${CLOUDFLARED_TUNNEL_TOKEN}" \
            >"${CLOUDFLARED_LOG}" 2>&1 &
    else
        log "启动 cloudflared quick tunnel：${CLOUDFLARED_TUNNEL_URL}"
        cloudflared tunnel --no-autoupdate \
            --url "${CLOUDFLARED_TUNNEL_URL}" \
            >"${CLOUDFLARED_LOG}" 2>&1 &
    fi
    CLOUDFLARED_PID="$!"

    sleep 2
    if ! kill -0 "${CLOUDFLARED_PID}" >/dev/null 2>&1; then
        log "错误：cloudflared 启动失败，日志如下：" >&2
        sed -n '1,160p' "${CLOUDFLARED_LOG}" >&2 || true
        exit 1
    fi

    if [[ -z "${CLOUDFLARED_TUNNEL_TOKEN:-}" ]]; then
        wait_for_cloudflared_url 60 || true
    else
        log "cloudflared token tunnel 已启动，日志：${CLOUDFLARED_LOG}"
    fi
}

main() {
    export MCP_MODE="${MCP_MODE:-http}"
    export MCP_HOST="${MCP_HOST:-${CODING_TOOLS_MCP_HOST:-0.0.0.0}}"
    export MCP_PORT="${MCP_PORT:-${CODING_TOOLS_MCP_PORT:-8765}}"
    export MCP_WORKSPACE="${MCP_WORKSPACE:-${CODING_TOOLS_MCP_WORKSPACE:-/workspace}}"
    export CODING_TOOLS_MCP_PERMISSION_MODE="${CODING_TOOLS_MCP_PERMISSION_MODE:-trusted}"
    export CLOUDFLARED_TUNNEL_URL="${CLOUDFLARED_TUNNEL_URL:-http://127.0.0.1:${MCP_PORT}}"

    require_directory

    case "${MCP_MODE}" in
        stdio)
            log "启动 stdio MCP，workspace：${MCP_WORKSPACE}"
            exec coding-tools-mcp --stdio --workspace "${MCP_WORKSPACE}" "$@"
            ;;
        http)
            prepare_authentication
            start_mcp_http
            start_cloudflared
            ;;
        *)
            log "错误：MCP_MODE 必须是 http 或 stdio，当前为：${MCP_MODE}" >&2
            exit 1
            ;;
    esac

    if [[ $# -gt 0 ]]; then
        log "执行自定义命令：$*"
        exec "$@"
    fi

    while kill -0 "${MCP_PID}" >/dev/null 2>&1; do
        if [[ -n "${CLOUDFLARED_PID}" ]] && ! kill -0 "${CLOUDFLARED_PID}" >/dev/null 2>&1; then
            log "错误：cloudflared 已退出，日志如下：" >&2
            sed -n '1,160p' "${CLOUDFLARED_LOG}" >&2 || true
            exit 1
        fi
        sleep 2
    done

    log "错误：coding-tools-mcp 已退出，日志如下：" >&2
    sed -n '1,160p' "${MCP_LOG}" >&2 || true
    exit 1
}

main "$@"
