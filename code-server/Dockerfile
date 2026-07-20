FROM oxzk/debian

ENV SERVER_PORT=9091 \
    SSH_PORT=22 \
    PASSWORD=code001 \
    DEBIAN_FRONTEND=noninteractive

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# 安装 code-server 运行与构建所需的基础工具，不安装系统 Python 包。
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        git-lfs \
        iputils-ping \
        jq \
        libatomic1 \
        neofetch \
        iproute2 \
        openssh-client \
        openssh-server \
        procps \
        unzip \
        vim \
        wget \
        zsh; \
    mkdir -p /run/sshd; \
    sed -ri 's/^#?PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config; \
    sed -ri 's/^#?PermitRootLogin .*/PermitRootLogin yes/' /etc/ssh/sshd_config; \
    sed -ri 's/^#?PubkeyAuthentication .*/PubkeyAuthentication yes/' /etc/ssh/sshd_config; \
    sed -ri 's/^#?Port .*/Port 22/' /etc/ssh/sshd_config; \
    rm -rf /var/lib/apt/lists/*

# 安装 code-server 与常用扩展。
RUN set -eux; \
    curl -fsSL https://code-server.dev/install.sh | sh; \
    extensions=( \
        tamasfe.even-better-toml \
        esbenp.prettier-vscode \
        denoland.vscode-deno \
        dracula-theme.theme-dracula \
        ms-python.python \
        ms-python.black-formatter \
        foxundermoon.shell-format \
        pkief.material-icon-theme \
        redhat.vscode-yaml \
        golang.go \
        # rust-lang.rust-analyzer \
        # openai.chatgpt \
    ); \
    for extension in "${extensions[@]}"; do \
        code-server --install-extension "${extension}"; \
    done; \
    rm -rf /root/.cache /tmp/* /var/tmp/*

COPY install.sh /tmp/install.sh
RUN chmod +x /tmp/install.sh && /tmp/install.sh

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 9091 22

ENTRYPOINT ["/entrypoint.sh"]
