FROM oxzk/python

ARG TARGETARCH
ARG NOVNC_VERSION=1.7.0

ENV DISPLAY=:99 \
    PYTHON_VENV=/opt/venv \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    DEBIAN_FRONTEND=noninteractive \
    XVFB_WHD=1920x1080x24 \
    VNC_PORT=5900 \
    NOVNC_PORT=15902 \
    CLOUDFLARED_TUNNEL_ENABLE=0 \
    CLOUDFLARED_TUNNEL_URL=http://127.0.0.1:15902 \
    PATH="/opt/venv/bin:${PATH}"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# 安装 Camoufox 图形运行、VNC 与入口脚本所需的系统依赖。
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        coreutils \
        curl \
        libgtk-3-0 \
        libx11-xcb1 \
        libasound2 \
        dbus \
        dnsutils \
        fluxbox \
        fonts-noto-cjk \
        iproute2 \
        procps \
        xauth \
        x11vnc \
        xvfb; \
    rm -rf /var/lib/apt/lists/*

# 安装 Python 依赖与 Camoufox 浏览器文件。
RUN --mount=type=cache,target=/root/.cache/uv \
    set -eux; \
    uv venv "${PYTHON_VENV}"; \
    . "${PYTHON_VENV}/bin/activate"; \
    uv pip install \
        "camoufox[geoip]" \
        websockify; \
    python -m camoufox fetch;
    # python -m playwright install-deps firefox; 
    
# 安装 noVNC 与 cloudflared。
RUN set -eux; \
    mkdir -p /opt/noVNC; \
    curl -fsSL "https://github.com/novnc/noVNC/archive/refs/tags/v${NOVNC_VERSION}.tar.gz" \
        | tar -xz --strip-components=1 -C /opt/noVNC; \
    build_arch="${TARGETARCH:-$(dpkg --print-architecture)}"; \
    case "${build_arch}" in \
        amd64) cloudflared_arch="amd64" ;; \
        arm64) cloudflared_arch="arm64" ;; \
        *) echo "不支持的架构：${build_arch}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${cloudflared_arch}" \
        -o /usr/local/bin/cloudflared; \
    chmod +x /usr/local/bin/cloudflared

# 安装完成后执行 Camoufox 冒烟验证，构建期使用无头模式降低图形环境影响。
RUN set -eux; \
     python -c $'from camoufox.sync_api import Camoufox\nwith Camoufox(headless=True) as b:\n    page = b.new_page()\n    page.goto("about:blank", timeout=20000)\n    page.close()'

WORKDIR /app

RUN mkdir -p /app/user_data

COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

EXPOSE 5900 15902

ENTRYPOINT ["/entrypoint.sh"]
