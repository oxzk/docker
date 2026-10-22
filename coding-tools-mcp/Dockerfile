FROM oxzk/debian

ARG TARGETARCH
ARG CODING_TOOLS_MCP_VERSION=0.5.0
ARG PYTHON_VERSION=3.12

ENV PYTHON_VENV=/opt/venv \
    UV_PYTHON_INSTALL_DIR=/opt/python \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    MCP_MODE=http \
    MCP_HOST=0.0.0.0 \
    MCP_PORT=8765 \
    MCP_WORKSPACE=/workspace \
    CODING_TOOLS_MCP_WORKSPACE=/workspace \
    CODING_TOOLS_MCP_HOST=0.0.0.0 \
    CODING_TOOLS_MCP_PORT=8765 \
    CODING_TOOLS_MCP_PERMISSION_MODE=trusted \
    CODING_TOOLS_MCP_AUTH_MODE=oauth \
    CODING_TOOLS_MCP_OAUTH_CLIENT_ID=oxzk-coding-tools-mcp \
    CODING_TOOLS_MCP_OAUTH_CLIENT_SECRET=f3c0e38d5004ca9303fe9edc1d5112e5 \
    CODING_TOOLS_MCP_OAUTH_REDIRECT_URIS=http://127.0.0.1/callback,http://localhost/callback \
    CLOUDFLARED_TUNNEL_URL=http://127.0.0.1:8765 \
    PATH="/opt/venv/bin:/usr/local/bin:${PATH}"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# oxzk/debian 已提供 curl、ca-certificates、git、openssl 与 bash。
# 用官方脚本安装 uv 和固定版本 Python，在独立虚拟环境里安装 coding-tools-mcp，
# 并按目标架构安装 cloudflared。
RUN set -eux; \
    curl -LsSf https://astral.sh/uv/install.sh \
        | env UV_INSTALL_DIR=/usr/local/bin UV_NO_MODIFY_PATH=1 sh; \
    uv python install "${PYTHON_VERSION}"; \
    uv venv --python "${PYTHON_VERSION}" "${PYTHON_VENV}"; \
    uv pip install --python "${PYTHON_VENV}/bin/python" \
        "coding-tools-mcp==${CODING_TOOLS_MCP_VERSION}"; \
    build_arch="${TARGETARCH:-$(dpkg --print-architecture)}"; \
    case "${build_arch}" in \
        amd64) cloudflared_arch="amd64" ;; \
        arm64) cloudflared_arch="arm64" ;; \
        *) echo "不支持的架构：${build_arch}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${cloudflared_arch}" \
        -o /usr/local/bin/cloudflared; \
    chmod +x /usr/local/bin/cloudflared; \
    cloudflared --version; \
    "${PYTHON_VENV}/bin/coding-tools-mcp" --version; \
    "${PYTHON_VENV}/bin/coding-tools-mcp" --help >/dev/null; \
    rm -rf /root/.cache/uv

WORKDIR /workspace

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8765

ENTRYPOINT ["/entrypoint.sh"]
