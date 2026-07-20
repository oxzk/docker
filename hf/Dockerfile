FROM oxzk/python

ARG TARGETARCH
ARG FRPC_VERSION=0.68.0
ARG FASTFETCH_VERSION=latest
ARG GO_VERSION=1.24.3
ARG NVM_INSTALL_VERSION=v0.40.3
ARG NODE_VERSION=22
ARG RUST_TOOLCHAIN=stable

ENV APP_VERSION=1.0.0 \
    API_HOST=0.0.0.0 \
    API_PORT=7860 \
    SSH_PORT=22 \
    PASSWORD=admin \
    USER=admin \
    SERVER_ADDR=sz.api01.eu.org \
    SERVER_PORT=7000 \
    REMOTE_PORT=2222 \
    PROXY_NAME=ssh \
    PYTHON_VENV=/opt/venv \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    DEBIAN_FRONTEND=noninteractive \
    GOPATH=/root/.local/share/go \
    NVM_DIR=/root/.nvm \
    CARGO_HOME=/root/.cargo \
    RUSTUP_HOME=/root/.rustup \
    PATH="/opt/venv/bin:/usr/local/go/bin:/root/.cargo/bin:/root/.local/bin:${PATH}"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# 安装 SSH、sudo 与运行时基础工具，并启用 root 密码登录。
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        iproute2 \
        libssl-dev \
        openssh-server \
        pkg-config \
        procps \
        sudo \
        unzip \
        vim \
        wget; \
    mkdir -p /run/sshd; \
    echo "root:${PASSWORD}" | chpasswd; \
    sed -ri 's/^#?PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config; \
    sed -ri 's/^#?PermitRootLogin .*/PermitRootLogin yes/' /etc/ssh/sshd_config; \
    sed -ri 's/^#?Port .*/Port 22/' /etc/ssh/sshd_config; \
    rm -rf /var/lib/apt/lists/*

# 安装 Docker、Go、nvm/Node.js 与 Rust 工具链。
RUN set -eux; \
    curl -fsSL https://get.docker.com | sh; \
    docker --version; \
    build_arch="${TARGETARCH:-$(dpkg --print-architecture)}"; \
    case "${build_arch}" in \
        amd64) go_arch="amd64" ;; \
        arm64) go_arch="arm64" ;; \
        *) echo "不支持的 Go 架构：${build_arch}" >&2; exit 1 ;; \
    esac; \
    go_package="go${GO_VERSION}.linux-${go_arch}.tar.gz"; \
    curl -fsSL "https://go.dev/dl/${go_package}" -o "/tmp/${go_package}"; \
    rm -rf /usr/local/go; \
    tar -zxf "/tmp/${go_package}" -C /usr/local; \
    go version; \
    mkdir -p "${NVM_DIR}"; \
    curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_INSTALL_VERSION}/install.sh" | bash; \
    . "${NVM_DIR}/nvm.sh"; \
    nvm install "${NODE_VERSION}"; \
    nvm alias default "${NODE_VERSION}"; \
    nvm use default; \
    node_bin="$(nvm which default)"; \
    node_dir="$(dirname "${node_bin}")"; \
    for node_command in node npm npx corepack; do \
        ln -sf "${node_dir}/${node_command}" "/usr/local/bin/${node_command}"; \
    done; \
    node --version; \
    npm --version; \
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
        | sh -s -- -y --default-toolchain "${RUST_TOOLCHAIN}" --profile minimal; \
    . "${CARGO_HOME}/env"; \
    rustup component add rustfmt clippy; \
    rustc --version; \
    cargo --version; \
    { \
        echo 'export GOPATH=/root/.local/share/go'; \
        echo 'export NVM_DIR=/root/.nvm'; \
        echo 'export CARGO_HOME=/root/.cargo'; \
        echo 'export RUSTUP_HOME=/root/.rustup'; \
        echo 'export PATH="/usr/local/go/bin:/root/.cargo/bin:$PATH"'; \
        echo '[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"'; \
        echo 'nvm use default >/dev/null 2>&1 || true'; \
    } >> /root/.bashrc; \
    rm -rf \
        /tmp/${go_package} \
        /root/.cache \
        /root/.npm \
        /root/.cargo/git \
        /root/.cargo/registry \
        /root/.nvm/.cache \
        /root/.nvm/versions/node/*/lib/node_modules/npm/docs \
        /root/.nvm/versions/node/*/lib/node_modules/npm/html \
        /root/.nvm/versions/node/*/lib/node_modules/npm/man \
        /root/.nvm/versions/node/*/lib/node_modules/npm/tap-snapshots \
        /root/.nvm/versions/node/*/lib/node_modules/npm/test \
        /root/.rustup/downloads \
        /root/.rustup/tmp \
        /root/.rustup/toolchains/*/share/doc \
        /root/.rustup/toolchains/*/share/man \
        /usr/local/go/api \
        /usr/local/go/doc \
        /usr/local/go/test; \
    apt-get autoremove -y; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# 从官方 deb 包安装 fastfetch，避免 zip 二进制缺少运行时依赖。
RUN set -eux; \
    build_arch="${TARGETARCH:-$(dpkg --print-architecture)}"; \
    case "${build_arch}" in \
        amd64) fastfetch_arch="amd64" ;; \
        arm64) fastfetch_arch="aarch64" ;; \
        *) echo "不支持的 fastfetch 架构：${build_arch}" >&2; exit 1 ;; \
    esac; \
    fastfetch_package="fastfetch-linux-${fastfetch_arch}.deb"; \
    if [[ "${FASTFETCH_VERSION}" == "latest" ]]; then \
        fastfetch_release_path="latest/download"; \
    else \
        fastfetch_release_path="download/${FASTFETCH_VERSION}"; \
    fi; \
    wget -q "https://github.com/fastfetch-cli/fastfetch/releases/${fastfetch_release_path}/${fastfetch_package}" -O "/tmp/${fastfetch_package}"; \
    apt-get update; \
    apt-get install -y --no-install-recommends "/tmp/${fastfetch_package}"; \
    fastfetch --version; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* "/tmp/${fastfetch_package}"

# 安装 FastAPI 示例服务依赖。
RUN --mount=type=cache,target=/root/.cache/uv \
    set -eux; \
    uv venv "${PYTHON_VENV}"; \
    . "${PYTHON_VENV}/bin/activate"; \
    uv pip install --no-cache-dir \
        fastapi \
        uvicorn

# 安装 frpc，用于按环境变量映射容器内远程登录端口。
RUN set -eux; \
    build_arch="${TARGETARCH:-$(dpkg --print-architecture)}"; \
    case "${build_arch}" in \
        amd64) frp_arch="amd64" ;; \
        *) echo "不支持的架构：${build_arch}" >&2; exit 1 ;; \
    esac; \
    wget -q "https://github.com/fatedier/frp/releases/download/v${FRPC_VERSION}/frp_${FRPC_VERSION}_linux_${frp_arch}.tar.gz" -O /tmp/frp.tar.gz; \
    tar -xzf /tmp/frp.tar.gz -C /tmp/; \
    mv /tmp/frp_*/frpc /usr/local/bin/frpc; \
    chmod +x /usr/local/bin/frpc; \
    rm -rf /tmp/frp*

# 清理构建缓存、包管理器缓存和工具链文档，保留运行与开发所需命令。
RUN set -eux; \
    npm cache clean --force >/dev/null 2>&1 || true; \
    if command -v go >/dev/null 2>&1; then \
        go clean -cache -modcache -testcache >/dev/null 2>&1 || true; \
    fi; \
    if command -v cargo >/dev/null 2>&1; then \
        cargo clean >/dev/null 2>&1 || true; \
    fi; \
    rm -rf \
        /root/.cache \
        /root/.npm \
        /root/.cargo/git \
        /root/.cargo/registry \
        /root/.nvm/.cache \
        /root/.nvm/versions/node/*/lib/node_modules/npm/docs \
        /root/.nvm/versions/node/*/lib/node_modules/npm/html \
        /root/.nvm/versions/node/*/lib/node_modules/npm/man \
        /root/.nvm/versions/node/*/lib/node_modules/npm/tap-snapshots \
        /root/.nvm/versions/node/*/lib/node_modules/npm/test \
        /root/.rustup/downloads \
        /root/.rustup/tmp \
        /root/.rustup/toolchains/*/share/doc \
        /root/.rustup/toolchains/*/share/man \
        /usr/local/go/api \
        /usr/local/go/doc \
        /usr/local/go/test \
        /var/cache/apt/archives \
        /var/lib/apt/lists/* \
        /tmp/* \
        /var/tmp/*; \
    apt-get autoremove -y; \
    apt-get clean

WORKDIR /app

COPY app.py /app/app.py
COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

EXPOSE 22 7860

ENTRYPOINT ["/entrypoint.sh"]
