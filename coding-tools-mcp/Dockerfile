FROM oxzk/python

ARG TARGETARCH
ARG CODING_TOOLS_MCP_VERSION=0.3.0

ENV PYTHON_VENV=/opt/venv \
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
    CODING_TOOLS_MCP_AUTH_MODE=bearer \
    CODING_TOOLS_MCP_OAUTH_CLIENT_ID=oxzk-coding-tools-mcp \
    CODING_TOOLS_MCP_OAUTH_CLIENT_SECRET=f3c0e38d5004ca9303fe9edc1d5112e5 \
    CODING_TOOLS_MCP_OAUTH_REDIRECT_URIS=http://127.0.0.1/callback,http://localhost/callback \
    CLOUDFLARED_TUNNEL_URL=http://127.0.0.1:8765 \
    PATH="/opt/venv/bin:${PATH}"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# 安装 coding-tools-mcp 到独立虚拟环境，并按目标架构安装 cloudflared。
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl; \
    build_arch="${TARGETARCH:-$(dpkg --print-architecture)}"; \
    case "${build_arch}" in \
        amd64) cloudflared_arch="amd64" ;; \
        arm64) cloudflared_arch="arm64" ;; \
        *) echo "不支持的架构：${build_arch}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${cloudflared_arch}" \
        -o /usr/local/bin/cloudflared; \
    chmod +x /usr/local/bin/cloudflared; \
    uv venv "${PYTHON_VENV}"; \
    uv pip install --python "${PYTHON_VENV}/bin/python" \
        "coding-tools-mcp==${CODING_TOOLS_MCP_VERSION}"; \
    cloudflared --version; \
    "${PYTHON_VENV}/bin/coding-tools-mcp" --help >/dev/null; \
    rm -rf /root/.cache/uv /var/lib/apt/lists/*

WORKDIR /workspace

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8765

ENTRYPOINT ["/entrypoint.sh"]
