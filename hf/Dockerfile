# syntax=docker/dockerfile:1
FROM oxzk/debian

ARG TARGETARCH
ARG FRP_VERSION=0.71.1
ARG PYTHON_VERSION=3.12.13
ARG FASTFETCH_VERSION=latest
ARG GO_VERSION=1.24.3
ARG NVM_INSTALL_VERSION=v0.40.3
ARG NODE_VERSION=22

ENV PASSWORD=admin \
    PYTHON_VENV=/workspace/.venv \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    DEBIAN_FRONTEND=noninteractive \
    GOPATH=/root/.local/share/go \
    NVM_DIR=/root/.nvm \
    PATH="/workspace/.venv/bin:/usr/local/go/bin:/root/.local/bin:${PATH}"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

COPY install.sh /tmp/hf-install.sh
RUN --mount=type=cache,target=/root/.cache/uv \
    chmod +x /tmp/hf-install.sh && \
    /tmp/hf-install.sh && \
    rm -f /tmp/hf-install.sh

WORKDIR /workspace

COPY app.py /workspace/app.py
COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

EXPOSE 22 7860

ENTRYPOINT ["/entrypoint.sh"]
