#!/usr/bin/env bash
# 一次安装全部工具链. 终端配置, 扩展和 ginit 在安装过程中写入.
set -Eeuo pipefail

# 输出未处理错误的退出码, 行号和失败命令.
report_error() {
    local status="$1" line="$2" command="$3"
    printf 'Installation failed (exit=%s, line=%s): %s\n' "$status" "$line" "$command" >&2
    exit "$status"
}
trap 'report_error "$?" "$LINENO" "$BASH_COMMAND"' ERR

# 输出当前安装阶段.
log() {
    printf '[install] %s\n' "$*"
}

# 下载文件, 失败时保留 curl 状态码和目标地址.
download() {
    local url="$1" destination="$2" status=0
    curl --fail --silent --show-error --location \
        --connect-timeout 20 --max-time 600 --retry 3 --retry-all-errors \
        --retry-max-time 1800 --output "$destination" "$url" || status=$?
    if (( status != 0 )); then
        printf 'Download failed (curl exit %s): %s\n' "$status" "$url" >&2
        return "$status"
    fi
}

# 要求当前组件所需的版本变量已由构建参数传入.
require_versions() {
    local name
    for name in "$@"; do
        if [[ -z "${!name:-}" ]]; then
            printf 'Missing build argument: %s\n' "$name" >&2
            exit 1
        fi
    done
}

# 下载仓库默认分支的当前快照, 不保留用于在线更新的仓库元数据.
install_repository() {
    local repository="$1" destination="$2" archive
    archive="$(mktemp "$INSTALL_TMP_DIR/repository.XXXXXX")"
    download "https://github.com/${repository}/archive/refs/heads/master.tar.gz" "$archive"
    mkdir -p "$destination"
    tar -xzf "$archive" --strip-components=1 -C "$destination"
}

# 安装 Oh My Zsh 与两个插件的默认分支, 并写入交互式终端配置.
install_shell() {
    log 'Installing Oh My Zsh and plugins'
    install_repository ohmyzsh/ohmyzsh /root/.oh-my-zsh
    install_repository zsh-users/zsh-syntax-highlighting \
        /root/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting
    install_repository zsh-users/zsh-autosuggestions \
        /root/.oh-my-zsh/custom/plugins/zsh-autosuggestions
    cat > /root/.zshrc <<'EOF'
# 使用镜像提供的语言工具路径, 只配置交互式终端行为.
export SHELL=/bin/zsh
export ZSH=/root/.oh-my-zsh
export ZSH_CUSTOM="$ZSH/custom"
ZSH_THEME=robbyrussell

# 构建时安装默认分支快照且已移除 Git 元数据, 禁止启动后在线更新.
zstyle ':omz:update' mode disabled
plugins=(git zsh-autosuggestions zsh-syntax-highlighting)
typeset -U path PATH

source "$NVM_DIR/nvm.sh"
source "$ZSH/oh-my-zsh.sh"
EOF
    chsh -s /usr/bin/zsh root
}

# 先完整下载再执行 Docker 官方安装脚本, 安装引擎, CLI, buildx 和 compose.
install_docker() {
    log 'Installing Docker from https://get.docker.com'
    run_installer https://get.docker.com sh
}

# 安装指定版本的 Go 工具链.
install_go() {
    local archive
    require_versions GO_VERSION
    log "Installing Go $GO_VERSION"
    archive="$INSTALL_TMP_DIR/go.tar.gz"
    download "https://go.dev/dl/go${GO_VERSION}.linux-${BUILD_ARCH}.tar.gz" "$archive"
    rm -rf /usr/local/go
    tar -xzf "$archive" -C /usr/local
}

# 使用 uv 官方安装脚本, 再安装固定版本的全局 Python, 不创建或激活虚拟环境.
install_python() {
    require_versions PYTHON_VERSION
    log "Installing uv and Python $PYTHON_VERSION"
    # 官方脚本默认写入 ~/.local/bin. 禁止它改写已生成的 shell 配置.
    UV_NO_MODIFY_PATH=1 run_installer https://astral.sh/uv/install.sh sh
    uv python install --default "$PYTHON_VERSION"
}

# 使用 rclone 官方安装脚本安装当前稳定版.
install_rclone() {
    log 'Installing rclone from https://rclone.org/install.sh'
    run_installer https://rclone.org/install.sh bash
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

# 安装 nvm 与指定 Node, 再用 npm 安装全局包.
install_node() {
    local node_bin name
    require_versions NVM_VERSION NODE_VERSION
    log "Installing Node $NODE_VERSION and global packages"
    mkdir -p "$NVM_DIR"
    PROFILE=/dev/null run_installer \
        "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" bash
    # shellcheck disable=SC1091
    source "$NVM_DIR/nvm.sh"
    nvm install "$NODE_VERSION"
    nvm alias default "$NODE_VERSION"
    node_bin="$(dirname "$(nvm which current)")"
    export PATH="${node_bin}:${PATH}"
    npm install --global @openai/codex wrangler
    # 版本目录不进入镜像 PATH, 只链接实际存在的命令.
    for name in node npm npx codex wrangler; do
        if [[ -x "${node_bin}/${name}" ]]; then
            ln -sfn "${node_bin}/${name}" "/usr/local/bin/${name}"
        fi
    done
}

# 安装固定的 code-server 扩展. 每项是 publisher.name, 可追加 @version.
install_extensions() {
    local extension
    local -a extensions=(
        tamasfe.even-better-toml
        esbenp.prettier-vscode
        ms-python.python
        ms-python.black-formatter
        pkief.material-icon-theme
        redhat.vscode-yaml
        golang.go
    )
    log 'Installing code-server extensions'
    for extension in "${extensions[@]}"; do
        code-server --install-extension "$extension"
    done
    rm -rf /root/.local/share/code-server/coder-logs
}

# 安装 ginit. 用空白分支重建一次根提交, 传入远程地址时再强制推送.
install_ginit() {
    log 'Installing ginit'
    cat > /usr/local/bin/ginit <<'EOF'
#!/usr/bin/env bash
# 用空白分支重建一次根提交. 用法: ginit [分支名] [提交信息] [远程地址]
set -euo pipefail

if [[ $# -gt 3 ]]; then
    printf 'Usage: ginit [branch] [message] [remote]\n' >&2
    exit 1
fi

branch="${1:-main}"
message="${2:-init}"
remote="${3:-}"

git init -q
git checkout -q --orphan ginit-root
git add -A
git commit -q --allow-empty -m "$message"
git branch -M ginit-root "$branch"

if [[ -n "$remote" ]]; then
    git remote add origin "$remote" 2>/dev/null || git remote set-url origin "$remote"
    git push -f -u origin "$branch"
fi
EOF
    chmod 755 /usr/local/bin/ginit
}

# 使用 code-server 官方安装脚本, 再安装扩展和 ginit.
install_code_server() {
    log 'Installing code-server from https://code-server.dev/install.sh'
    run_installer https://code-server.dev/install.sh sh
    install_extensions
    install_ginit
}

# 写入 Git 默认身份、拉取方式和凭据存储位置.
configure_git() {
    log 'Configuring Git'
    git config --global user.name oxzk
    git config --global user.email riverecho520@gmail.com
    git config --global pull.rebase false
    git config --global credential.helper 'store --file=/workspace/.git/.git-credentials'
    git config --global init.defaultBranch main
}

# 打印一条工具版本, 只保留首行.
print_version() {
    local name="$1" output
    shift
    if ! output="$("$@" 2>&1)"; then
        printf 'Version command failed: %s\n' "$name" >&2
        return 1
    fi
    printf '%s: %s\n' "$name" "${output%%$'\n'*}"
}

# 在清理缓存前输出全部工具版本, 便于从构建日志确认实际安装结果.
print_tool_versions() {
    log 'Installed tool versions'
    print_version zsh zsh --version
    print_version git git --version
    print_version docker docker --version
    print_version buildx docker buildx version
    print_version compose docker compose version
    print_version go go version
    print_version uv uv --version
    print_version python python3 --version
    print_version rclone rclone version
    print_version node node --version
    print_version npm npm --version
    print_version codex codex --version
    print_version wrangler wrangler --version
    print_version code-server code-server --version
}

# 清理构建缓存, 不删除已安装的工具本体.
cleanup_image() {
    log 'Removing download caches'
    if command -v npm >/dev/null 2>&1; then
        npm cache clean --force >/dev/null 2>&1 || true
    fi
    if command -v go >/dev/null 2>&1; then
        go clean -cache -modcache -testcache >/dev/null 2>&1 || true
    fi
    if command -v uv >/dev/null 2>&1; then
        uv cache clean >/dev/null 2>&1 || true
    fi
    rm -rf /root/.cache /root/.npm /root/.nvm/.cache /tmp/* /var/tmp/*
    # 只清下载包和软件索引, 不 autoremove, 避免误删运行时依赖.
    if command -v apt-get >/dev/null 2>&1; then
        apt-get clean >/dev/null 2>&1 || true
        rm -rf /var/lib/apt/lists/*
    fi
}

# 解析构建架构后按顺序安装全部工具.
main() {
    if [[ $# -ne 0 ]]; then
        printf 'Usage: install.sh\n' >&2
        exit 1
    fi
    BUILD_ARCH="${TARGETARCH:-$(dpkg --print-architecture)}"
    case "$BUILD_ARCH" in
        amd64|arm64) ;;
        *) printf 'Unsupported architecture: %s\n' "$BUILD_ARCH" >&2; exit 1 ;;
    esac
    INSTALL_TMP_DIR="$(mktemp -d /tmp/code-server-install.XXXXXX)"
    readonly BUILD_ARCH INSTALL_TMP_DIR
    trap 'rm -rf "$INSTALL_TMP_DIR"' EXIT
    install_shell
    install_docker
    install_go
    install_python
    install_rclone
    install_node
    install_code_server
    configure_git
    print_tool_versions
    cleanup_image
}

main "$@"
