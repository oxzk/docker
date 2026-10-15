#!/usr/bin/env bash
# 文件编码：UTF-8 无 BOM
#
# HF 容器构建脚本，安装 SSH、开发工具链、frpc 与 FastAPI 运行环境。
set -Eeuo pipefail

readonly APP_WORKDIR="/workspace"
readonly TARGET_ARCH="${TARGETARCH:-$(dpkg --print-architecture)}"

report_error() {
    local status="$1" line="$2" command="$3"
    printf 'Installation failed (exit=%s, line=%s): %s\n' "$status" "$line" "$command" >&2
    exit "$status"
}
trap 'report_error "$?" "$LINENO" "$BASH_COMMAND"' ERR

install_system_packages() {
    apt-get update
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
        wget
}

configure_sshd() {
    mkdir -p /run/sshd
    echo "root:${PASSWORD:-admin}" | chpasswd
    sed -ri 's/^#?PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config
    sed -ri 's/^#?PermitRootLogin .*/PermitRootLogin yes/' /etc/ssh/sshd_config
    sed -ri 's/^#?Port .*/Port 22/' /etc/ssh/sshd_config
}

install_docker_cli() {
    curl -fsSL https://get.docker.com | sh
    docker --version
}

install_go() {
    local go_package="go${GO_VERSION}.linux-${TARGET_ARCH}.tar.gz"

    curl -fsSL "https://go.dev/dl/${go_package}" -o "/tmp/${go_package}"
    rm -rf /usr/local/go
    tar -zxf "/tmp/${go_package}" -C /usr/local
    rm -f "/tmp/${go_package}"
    go version
}

install_node() {
    mkdir -p "${NVM_DIR}"
    curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_INSTALL_VERSION}/install.sh" | bash
    . "${NVM_DIR}/nvm.sh"
    nvm install "${NODE_VERSION}"
    nvm alias default "${NODE_VERSION}"
    nvm use default

    local node_bin node_dir node_command
    node_bin="$(nvm which default)"
    node_dir="$(dirname "${node_bin}")"
    for node_command in node npm npx corepack; do
        ln -sf "${node_dir}/${node_command}" "/usr/local/bin/${node_command}"
    done

    node --version
    npm --version
}

install_fastfetch() {
    local fastfetch_package fastfetch_release_path

    fastfetch_package="fastfetch-linux-${TARGET_ARCH}.deb"
    if [[ "${FASTFETCH_VERSION}" == "latest" ]]; then
        fastfetch_release_path="latest/download"
    else
        fastfetch_release_path="download/${FASTFETCH_VERSION}"
    fi

    wget -q "https://github.com/fastfetch-cli/fastfetch/releases/${fastfetch_release_path}/${fastfetch_package}" -O "/tmp/${fastfetch_package}"
    apt-get update
    apt-get install -y --no-install-recommends "/tmp/${fastfetch_package}"
    rm -f "/tmp/${fastfetch_package}"
    fastfetch --version
}

# 安装指定版本的 frpc 客户端。
install_frpc() {
    local package="frp_${FRP_VERSION}_linux_${TARGET_ARCH}"
    local download_dir
    download_dir="$(mktemp -d)"

    curl -fsSL \
        "https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${package}.tar.gz" \
        -o "${download_dir}/${package}.tar.gz"
    tar -xzf "${download_dir}/${package}.tar.gz" -C "${download_dir}" "${package}/frpc"
    install -m 0755 "${download_dir}/${package}/frpc" /usr/local/bin/frpc
    rm -rf "${download_dir}"
}

install_python_environment() {
    install -d -m 0755 "${APP_WORKDIR}"
    curl -LsSf https://astral.sh/uv/install.sh | sh
    "${HOME}/.local/bin/uv" python install "${PYTHON_VERSION}"
    "${HOME}/.local/bin/uv" venv "${PYTHON_VENV}"
    "${HOME}/.local/bin/uv" pip install \
        --python "${PYTHON_VENV}/bin/python" \
        fastapi \
        uvicorn
}

configure_shell() {
    {
        echo 'export GOPATH=/root/.local/share/go';
        echo 'export NVM_DIR=/root/.nvm';
        echo 'export PATH="/usr/local/go/bin:/root/.local/bin:$PATH"';
        echo '[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"';
        echo 'nvm use default >/dev/null 2>&1 || true';
        echo '# 交互式登录（SSH）自动激活虚拟环境并进入工作目录。';
        echo 'if [[ $- == *i* ]]; then';
        echo "    [ -r '${PYTHON_VENV}/bin/activate' ] && . '${PYTHON_VENV}/bin/activate'";
        echo "    cd '${APP_WORKDIR}' 2>/dev/null || true";
        echo 'fi';
    } >> /root/.bashrc
    # 登录 shell 优先读取 .bash_profile，缺失时补一个用于加载 .bashrc。
    if [[ ! -e /root/.bash_profile ]]; then
        printf '%s\n' 'if [ -f /root/.bashrc ]; then . /root/.bashrc; fi' > /root/.bash_profile
    fi
}

verify_installation() {
    sshd -t
    frpc --version
    "${PYTHON_VENV}/bin/python" -c 'import fastapi, uvicorn'
}

cleanup_build_files() {
    npm cache clean --force >/dev/null 2>&1 || true
    go clean -cache -modcache -testcache >/dev/null 2>&1 || true
    rm -rf \
        /root/.npm \
        /root/.nvm/.cache \
        /root/.nvm/versions/node/*/lib/node_modules/npm/docs \
        /root/.nvm/versions/node/*/lib/node_modules/npm/html \
        /root/.nvm/versions/node/*/lib/node_modules/npm/man \
        /root/.nvm/versions/node/*/lib/node_modules/npm/tap-snapshots \
        /root/.nvm/versions/node/*/lib/node_modules/npm/test \
        /usr/local/go/api \
        /usr/local/go/doc \
        /usr/local/go/test \
        /var/cache/apt/archives \
        /var/lib/apt/lists/* \
        /var/tmp/*
    apt-get autoremove -y
    apt-get clean
}

main() {
    export DEBIAN_FRONTEND=noninteractive

    install_system_packages
    configure_sshd
    install_docker_cli
    install_go
    install_node
    install_fastfetch
    install_frpc
    install_python_environment
    configure_shell
    verify_installation
    cleanup_build_files
}

main "$@"
