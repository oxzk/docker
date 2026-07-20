FROM oxzk/debian

ENV UV_LINK_MODE=copy \
    PATH="/root/.local/bin:${PATH}"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

WORKDIR /workspace

# 使用 uv 安装 Python 3.11, 并将其作为默认运行时。
RUN set -eux; \
    curl -LsSf https://astral.sh/uv/install.sh | sh; \
    uv python install --default 3.11; \
    { \
        echo 'export UV_LINK_MODE=copy'; \
        echo 'export PATH="/root/.local/bin:$PATH"'; \
    } >> /root/.bashrc; \
    printf '%s\n' 'if [ -f ~/.bashrc ]; then' '    . ~/.bashrc' 'fi' > /root/.bash_profile; \
    python --version; \
    python3 --version; \
    uv --version

CMD ["bash", "-l"]
