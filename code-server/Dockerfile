FROM oxzk/debian

ENV SERVER_PORT=9091 \
    SSH_PORT=22 \
    DEBIAN_FRONTEND=noninteractive

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# 软件索引和下载包保留在 BuildKit 缓存挂载中, 不写入最终镜像.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    set -eux; \
    rm -f /etc/apt/apt.conf.d/docker-clean; \
    printf 'Binary::apt::APT::Keep-Downloaded-Packages "true";\n' > /etc/apt/apt.conf.d/keep-cache; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates curl git git-lfs iputils-ping jq libatomic1 \
        neofetch iproute2 openssh-client openssh-server procps unzip vim wget zsh; \
    mkdir -p /run/sshd; \
    sed -ri 's/^#?PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config; \
    sed -ri 's/^#?PermitRootLogin .*/PermitRootLogin yes/' /etc/ssh/sshd_config; \
    sed -ri 's/^#?PubkeyAuthentication .*/PubkeyAuthentication yes/' /etc/ssh/sshd_config; \
    sed -ri 's/^#?Port .*/Port 22/' /etc/ssh/sshd_config

# 通过构建参数集中固定工具版本和插件提交, 更新时显式修改版本.
ARG TARGETARCH
ARG CODE_SERVER_VERSION=4.141.0
ARG DOCKER_VERSION=29.5.3
ARG BUILDX_VERSION=0.38.0
ARG COMPOSE_VERSION=5.6.0
ARG GO_VERSION=1.24.3
ARG SHFMT_VERSION=3.14.1
ARG UV_VERSION=0.12.23
ARG PYTHON_VERSION=3.11.15
ARG NVM_VERSION=v0.40.3
ARG NODE_VERSION=22.23.3
ARG COREPACK_VERSION=0.36.0
ARG PNPM_VERSION=12.10.1
ARG CODEX_VERSION=0.161.0
ARG WRANGLER_VERSION=4.148.0
ARG RUSTUP_VERSION=1.28.2
ARG RUST_VERSION=1.99.0
ARG RCLONE_VERSION=1.75.1
ARG DENO_VERSION=2.9.7
ARG OH_MY_ZSH_REVISION=60c9a7a839b790cd905d0fd4419435124fd1bdc0
ARG ZSH_HIGHLIGHT_REVISION=0bfcb582e71d3abe604ce67bc0fe5a21f377507e
ARG ZSH_SUGGEST_REVISION=85919cd1ffa7d2d5412f6d3fe437ebdbeeec4fc5
ARG DRACULA_ZSH_REVISION=a3e27d47ea2ed1e3b435f44aa71caf71d3219af6
ARG DRACULA_VIM_REVISION=e7817b4baccfb3529f709ac048c621f35cdbc5b3

# 镜像环境由交互终端, SSH 和编辑器任务共同继承, 不依赖 .zshrc 激活工具链.
ENV GOPATH=/root/.local/share/go \
    NVM_DIR=/root/.nvm \
    PNPM_HOME=/root/.local/share/pnpm \
    PNPM_GLOBAL_BIN_DIR=/root/.local/share/pnpm/bin \
    CARGO_HOME=/root/.cargo \
    RUSTUP_HOME=/root/.rustup \
    UV_LINK_MODE=copy \
    PATH="/root/.local/bin:/root/.cargo/bin:/usr/local/go/bin:/root/.local/share/go/bin:/root/.nvm/versions/node/v${NODE_VERSION}/bin:/root/.local/share/pnpm/bin:/root/.local/share/pnpm:${PATH}"

COPY install.sh /usr/local/lib/code-server/install.sh
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    bash /usr/local/lib/code-server/install.sh

# 扩展清单独立成层, 修改扩展不重新安装工具链.
COPY extensions.txt /usr/local/share/code-server/extensions.txt
RUN set -eu; \
    while IFS= read -r extension || [ -n "$extension" ]; do \
        case "$extension" in ''|'#'*) continue ;; esac; \
        code-server --install-extension "$extension"; \
    done < /usr/local/share/code-server/extensions.txt; \
    rm -rf /root/.local/share/code-server/coder-logs

# 配置和用户命令最后复制, 编辑字体或快捷命令仅更新轻量配置层.
COPY config/zshrc /root/.zshrc
COPY config/vimrc /root/.vimrc
COPY config/gitconfig /root/.gitconfig
COPY config/settings.json /root/.local/share/code-server/User/settings.json
COPY ginit /usr/local/bin/ginit
COPY entrypoint.sh /entrypoint.sh
# PAM 会为 SSH 登录读取此文件, 保持其工具路径与容器进程一致.
RUN set -eu; \
    chmod 755 /usr/local/bin/ginit /entrypoint.sh; \
    install -d -m 700 /root/.git; \
    mkdir -p /workspace; \
    for name in PATH GOPATH NVM_DIR PNPM_HOME PNPM_GLOBAL_BIN_DIR CARGO_HOME RUSTUP_HOME UV_LINK_MODE; do \
        printf '%s="%s"\n' "$name" "${!name}"; \
    done >> /etc/environment

WORKDIR /workspace
EXPOSE 9091 22
ENTRYPOINT ["/entrypoint.sh"]
