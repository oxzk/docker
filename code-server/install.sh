#!/usr/bin/env bash
# 只安装版本固定的工具链, 终端和编辑器配置由 Dockerfile 后续复制.
set -Eeuo pipefail

# 输出当前安装阶段.
log() {
    printf '[install] %s\n' "$*"
}

# 为直接下载统一设置连接超时, 单次超时和重试总时间.
download() {
    curl --fail --silent --show-error --location \
        --connect-timeout 20 --max-time 600 --retry 3 --retry-max-time 1800 \
        "$1" -o "$2" || return "$?"
}

# 从完整下载的脚本执行安装, 避免下载与执行同时进行.
run_installer() {
    local url="$1" interpreter="$2" installer
    shift 2
    installer="$(mktemp "$INSTALL_TMP_DIR/installer.XXXXXX")"
    download "$url" "$installer"
    "$interpreter" "$installer" "$@"
    rm -f "$installer"
}

# 提取固定 Git 提交的源码, 不保留用于在线更新的仓库元数据.
install_repository() {
    local repository="$1" revision="$2" destination="$3" archive
    archive="$(mktemp "$INSTALL_TMP_DIR/repository.XXXXXX")"
    download "https://github.com/${repository}/archive/${revision}.tar.gz" "$archive"
    mkdir -p "$destination"
    tar -xzf "$archive" --strip-components=1 -C "$destination"
}

# 安装固定版本的 Oh My Zsh, 第三方插件和编辑器主题.
install_shell() {
    log 'Installing shell plugins and themes'
    install_repository ohmyzsh/ohmyzsh "$OH_MY_ZSH_REVISION" /root/.oh-my-zsh
    install_repository zsh-users/zsh-syntax-highlighting "$ZSH_HIGHLIGHT_REVISION" \
        /root/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting
    install_repository zsh-users/zsh-autosuggestions "$ZSH_SUGGEST_REVISION" \
        /root/.oh-my-zsh/custom/plugins/zsh-autosuggestions
    install_repository dracula/zsh "$DRACULA_ZSH_REVISION" /root/.oh-my-zsh/custom/themes/dracula
    ln -s /root/.oh-my-zsh/custom/themes/dracula/dracula.zsh-theme \
        /root/.oh-my-zsh/custom/themes/dracula.zsh-theme
    install_repository dracula/vim "$DRACULA_VIM_REVISION" /root/.vim/pack/themes/start/dracula
    chsh -s /usr/bin/zsh root
}

# 只安装连接宿主机或远程引擎所需的 Docker CLI 和两个官方插件.
install_docker_cli() {
    log "Installing Docker CLI $DOCKER_VERSION"
    download "https://download.docker.com/linux/static/stable/${MACHINE_ARCH}/docker-${DOCKER_VERSION}.tgz" \
        "$INSTALL_TMP_DIR/docker.tgz"
    tar -xzf "$INSTALL_TMP_DIR/docker.tgz" -C "$INSTALL_TMP_DIR" docker/docker
    install -m 755 "$INSTALL_TMP_DIR/docker/docker" /usr/local/bin/docker
    install -d /usr/local/lib/docker/cli-plugins
    download "https://github.com/docker/buildx/releases/download/v${BUILDX_VERSION}/buildx-v${BUILDX_VERSION}.linux-${BUILD_ARCH}" \
        /usr/local/lib/docker/cli-plugins/docker-buildx
    download "https://github.com/docker/compose/releases/download/v${COMPOSE_VERSION}/docker-compose-linux-${MACHINE_ARCH}" \
        /usr/local/lib/docker/cli-plugins/docker-compose
    chmod 755 /usr/local/lib/docker/cli-plugins/docker-*
}

# 安装 Go 和 shfmt 发行二进制, 不在构建时编译 shfmt 或下载 Go 模块.
install_go() {
    log "Installing Go $GO_VERSION and shfmt $SHFMT_VERSION"
    download "https://go.dev/dl/go${GO_VERSION}.linux-${BUILD_ARCH}.tar.gz" "$INSTALL_TMP_DIR/go.tar.gz"
    tar -xzf "$INSTALL_TMP_DIR/go.tar.gz" -C /usr/local
    download "https://github.com/mvdan/sh/releases/download/v${SHFMT_VERSION}/shfmt_v${SHFMT_VERSION}_linux_${BUILD_ARCH}" \
        /usr/local/bin/shfmt
    chmod 755 /usr/local/bin/shfmt
}

# 安装 uv 和全局可用的托管 Python, 不创建或激活虚拟环境.
install_python() {
    log "Installing uv $UV_VERSION and Python $PYTHON_VERSION"
    download "https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-${RUST_TARGET}.tar.gz" \
        "$INSTALL_TMP_DIR/uv.tar.gz"
    tar -xzf "$INSTALL_TMP_DIR/uv.tar.gz" -C "$INSTALL_TMP_DIR"
    install -m 755 "$INSTALL_TMP_DIR/uv-${RUST_TARGET}/uv" /usr/local/bin/uv
    install -m 755 "$INSTALL_TMP_DIR/uv-${RUST_TARGET}/uvx" /usr/local/bin/uvx
    uv python install --default "$PYTHON_VERSION"
}

# 保留 nvm 的版本切换能力, 并固定 Node 和全局包的默认安装版本.
install_node() {
    log "Installing Node $NODE_VERSION and global packages"
    mkdir -p "$NVM_DIR" "$PNPM_HOME" "$PNPM_GLOBAL_BIN_DIR"
    PROFILE=/dev/null run_installer \
        "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" bash
    # shellcheck disable=SC1091
    source "$NVM_DIR/nvm.sh"
    nvm install "$NODE_VERSION"
    nvm alias default "$NODE_VERSION"
    npm install --global "corepack@${COREPACK_VERSION}"
    corepack enable
    corepack prepare "pnpm@${PNPM_VERSION}" --activate
    pnpm config set global-bin-dir "$PNPM_GLOBAL_BIN_DIR"
    pnpm add -g "@openai/codex@${CODEX_VERSION}" "wrangler@${WRANGLER_VERSION}"
}

# 使用版本固定的 rustup 安装固定 Rust 工具链和开发组件.
install_rust() {
    log "Installing Rust $RUST_VERSION"
    download "https://static.rust-lang.org/rustup/archive/${RUSTUP_VERSION}/${RUST_TARGET}/rustup-init" \
        "$INSTALL_TMP_DIR/rustup-init"
    chmod 755 "$INSTALL_TMP_DIR/rustup-init"
    "$INSTALL_TMP_DIR/rustup-init" -y --no-modify-path --profile minimal \
        --default-toolchain "$RUST_VERSION" --component rustfmt --component clippy
}

# 安装固定版本的 rclone 和 Deno, 将二进制直接放入系统 PATH.
install_utilities() {
    log "Installing rclone $RCLONE_VERSION and Deno $DENO_VERSION"
    download "https://downloads.rclone.org/v${RCLONE_VERSION}/rclone-v${RCLONE_VERSION}-linux-${BUILD_ARCH}.zip" \
        "$INSTALL_TMP_DIR/rclone.zip"
    unzip -q "$INSTALL_TMP_DIR/rclone.zip" -d "$INSTALL_TMP_DIR/rclone"
    install -m 755 "$INSTALL_TMP_DIR/rclone/rclone-v${RCLONE_VERSION}-linux-${BUILD_ARCH}/rclone" /usr/local/bin/rclone
    download "https://github.com/denoland/deno/releases/download/v${DENO_VERSION}/deno-${RUST_TARGET}.zip" \
        "$INSTALL_TMP_DIR/deno.zip"
    unzip -q "$INSTALL_TMP_DIR/deno.zip" -d "$INSTALL_TMP_DIR/deno"
    install -m 755 "$INSTALL_TMP_DIR/deno/deno" /usr/local/bin/deno
}

# 安装固定版本的 code-server, 保留挂载的 APT 下载缓存和软件索引.
install_code_server() {
    log "Installing code-server $CODE_SERVER_VERSION"
    download "https://github.com/coder/code-server/releases/download/v${CODE_SERVER_VERSION}/code-server_${CODE_SERVER_VERSION}_${BUILD_ARCH}.deb" \
        "$INSTALL_TMP_DIR/code-server.deb"
    apt-get update
    apt-get install -y --no-install-recommends "$INSTALL_TMP_DIR/code-server.deb"
    git lfs install --system
}

# 只删除构建下载缓存, 不删除工具源码资源或 APT 的 BuildKit 缓存.
cleanup_image() {
    log 'Removing build caches'
    if [[ "$INSTALL_COMPONENT" == node ]]; then
        npm cache clean --force
        pnpm store prune
    fi
    rm -rf /root/.cache/uv /root/.npm /root/.nvm/.cache \
        /root/.rustup/downloads /root/.rustup/tmp
}

# 按依赖顺序安装, 为各平台选择匹配的官方二进制包.
main() {
    INSTALL_COMPONENT="${1:?Set an installation component}"
    BUILD_ARCH="${TARGETARCH:-$(dpkg --print-architecture)}"
    case "$BUILD_ARCH" in
        amd64) MACHINE_ARCH=x86_64 ;;
        arm64) MACHINE_ARCH=aarch64 ;;
        *) printf 'Unsupported architecture: %s\n' "$BUILD_ARCH" >&2; exit 1 ;;
    esac
    RUST_TARGET="${MACHINE_ARCH}-unknown-linux-gnu"
    INSTALL_TMP_DIR="$(mktemp -d /tmp/code-server-install.XXXXXX)"
    readonly INSTALL_COMPONENT BUILD_ARCH MACHINE_ARCH RUST_TARGET INSTALL_TMP_DIR
    trap 'rm -rf "$INSTALL_TMP_DIR"' EXIT
    case "$INSTALL_COMPONENT" in
        shell) install_shell ;;
        docker) install_docker_cli ;;
        go) install_go ;;
        python) install_python ;;
        node) install_node ;;
        rust) install_rust ;;
        utilities) install_utilities ;;
        editor) install_code_server ;;
        *) printf 'Unknown installation component: %s\n' "$INSTALL_COMPONENT" >&2; exit 1 ;;
    esac
    cleanup_image
}

main "$@"
