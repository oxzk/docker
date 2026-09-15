#!/usr/bin/env bash
# 文件编码：UTF-8 无 BOM
#
# code-server 开发环境安装脚本。

set -Eeuo pipefail

readonly WORKSPACE_DIR="/workspace"
readonly VENV_DIR="${WORKSPACE_DIR}/.venv"
readonly ZSHRC="/root/.zshrc"
readonly CODE_SERVER_USER_DIR="/root/.local/share/code-server/User"
readonly GO_VERSION="1.24.3"
readonly NVM_INSTALL_VERSION="v0.40.3"
readonly NODE_VERSION="22"
readonly RUST_TOOLCHAIN="stable"

log() {
    echo "[install] $*"
}

get_arch() {
    local arch
    arch="$(uname -m)"

    case "${arch}" in
    x86_64)
        echo "amd64"
        ;;
    aarch64 | arm64)
        echo "arm64"
        ;;
    *)
        echo "amd64"
        ;;
    esac
}

verify_command() {
    local name="$1"
    local path="${2:-}"
    local version_flag="${3:---version}"
    local command_path

    if [[ -n "${path}" && -x "${path}" ]]; then
        command_path="${path}"
    elif command -v "${name}" >/dev/null 2>&1; then
        command_path="${name}"
    else
        echo "错误：${name} 安装失败，命令不可用" >&2
        return 1
    fi

    log "${name} 安装成功"
    "${command_path}" "${version_flag}" 2>/dev/null \
        || "${command_path}" -version 2>/dev/null \
        || "${command_path}" version 2>/dev/null \
        || true
}

install_zsh_environment() {
    log "安装 oh-my-zsh 与常用插件"
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c \
        "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
        "" --unattended

    chsh -s "$(command -v zsh)" || true
    export SHELL="$(command -v zsh)"

    mkdir -p /root/.oh-my-zsh/plugins
    git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git \
        /root/.oh-my-zsh/plugins/zsh-syntax-highlighting
    git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions \
        /root/.oh-my-zsh/plugins/zsh-autosuggestions
    git clone --depth=1 https://github.com/dracula/zsh.git /root/.oh-my-zsh/themes/dracula
    ln -sf /root/.oh-my-zsh/themes/dracula/dracula.zsh-theme \
        /root/.oh-my-zsh/themes/dracula.zsh-theme
}

install_docker() {
    log "安装 Docker"
    curl -fsSL https://get.docker.com | sh
    verify_command "docker" "/usr/bin/docker" "--version"
}

install_go() {
    local arch
    local filename
    local download_url

    arch="$(get_arch)"
    filename="go${GO_VERSION}.linux-${arch}.tar.gz"
    download_url="https://go.dev/dl/${filename}"

    log "安装 Go ${GO_VERSION} (${arch})"
    curl -fsSL "${download_url}" -o "/tmp/${filename}"
    rm -rf /usr/local/go
    tar -zxf "/tmp/${filename}" -C /usr/local/
    export PATH="/usr/local/go/bin:${PATH}"

    verify_command "go" "/usr/local/go/bin/go" "version"
}

install_shfmt() {
    log "安装 shfmt"
    export PATH="/usr/local/go/bin:${PATH}"
    GOBIN=/usr/local/bin go install mvdan.cc/sh/v3/cmd/shfmt@latest
    verify_command "shfmt" "/usr/local/bin/shfmt" "-version"
}

install_uv_python() {
    log "安装 uv 并创建 Python 3.11 虚拟环境"
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="/root/.local/bin:${PATH}"
    export UV_LINK_MODE=copy

    mkdir -p "${WORKSPACE_DIR}"
    cd "${WORKSPACE_DIR}"
    rm -rf "${VENV_DIR}"
    uv python install --default 3.11
    uv venv --managed-python --python 3.11 "${VENV_DIR}"
    . "${VENV_DIR}/bin/activate"
    python --version
    python3 --version

    verify_command "uv" "/root/.local/bin/uv" "--version"
}

install_nvm_node() {
    local node_bin
    local node_dir
    local node_command

    log "安装 nvm ${NVM_INSTALL_VERSION} 与 Node.js ${NODE_VERSION}"
    export NVM_DIR="/root/.nvm"
    export PNPM_HOME="/root/.local/share/pnpm"
    export PNPM_GLOBAL_BIN_DIR="${PNPM_HOME}/bin"
    export PATH="${PNPM_GLOBAL_BIN_DIR}:${PNPM_HOME}:${PATH}"
    mkdir -p "${NVM_DIR}"
    mkdir -p "${PNPM_HOME}" "${PNPM_GLOBAL_BIN_DIR}"
    curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_INSTALL_VERSION}/install.sh" | bash
    . "${NVM_DIR}/nvm.sh"

    nvm install "${NODE_VERSION}"
    nvm alias default "${NODE_VERSION}"
    nvm use default

    # npm install -g edgeone @openai/codex wrangler@latest @anthropic-ai/claude-code
    # corepack enable
    # corepack prepare pnpm@latest --activate
    # pnpm config set global-bin-dir "${PNPM_GLOBAL_BIN_DIR}"
    # pnpm add -g edgeone @openai/codex wrangler@latest 
    # # @anthropic-ai/claude-code

    # node_bin="$(nvm which default)"
    # node_dir="$(dirname "${node_bin}")"
    # for node_command in node npm npx corepack pnpm edgeone codex wrangler; do
    #     if [[ -x "${node_dir}/${node_command}" ]]; then
    #         ln -sf "${node_dir}/${node_command}" "/usr/local/bin/${node_command}"
    #     elif [[ -x "${PNPM_GLOBAL_BIN_DIR}/${node_command}" ]]; then
    #         ln -sf "${PNPM_GLOBAL_BIN_DIR}/${node_command}" "/usr/local/bin/${node_command}"
    #     fi
    # done

    node --version
    npm --version
    # pnpm --version
}

install_rust() {
    log "安装 Rust ${RUST_TOOLCHAIN} 工具链"
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
        | sh -s -- -y --default-toolchain "${RUST_TOOLCHAIN}" --profile minimal
    . /root/.cargo/env
    rustup component add rustfmt clippy
    verify_command "rustc" "/root/.cargo/bin/rustc" "--version"
    verify_command "cargo" "/root/.cargo/bin/cargo" "--version"
}

install_rclone() {
    log "安装 rclone"
    curl -fsSL https://rclone.org/install.sh | zsh
}

install_deno() {
    log "安装 Deno"
    curl -fsSL https://deno.land/install.sh | zsh
    export PATH="/root/.deno/bin:${PATH}"
    deno --version
}

configure_zsh() {
    log "写入 zsh 配置"
    cat >"${ZSHRC}" <<'EOF'
# 文件编码：UTF-8 无 BOM
export LANG=zh_CN.UTF-8
export LANGUAGE=zh_CN.UTF-8
export SHELL=/bin/zsh
export GOPATH=~/.local/share/go
export DENO_DEPLOY_TOKEN=""
export UV_LINK_MODE=copy
export NVM_DIR="/root/.nvm"
export PNPM_HOME="/root/.local/share/pnpm"
export PNPM_GLOBAL_BIN_DIR="/root/.local/share/pnpm/bin"
export ZSH="/root/.oh-my-zsh"
export CARGO_HOME="/root/.cargo"
export RUSTUP_HOME="/root/.rustup"
ZSH_THEME="dracula"
plugins=(git)

export PATH=/usr/local/go/bin:$PATH
export PATH=/root/.deno/bin:$PATH
export PATH=/root/.local/bin:$PATH
export PATH=/root/.local/share/pnpm/bin:$PATH
export PATH=/root/.local/share/pnpm:$PATH
export PATH=/workspace/.venv/bin:$PATH
export PATH=/root/.cargo/bin:$PATH

[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
nvm use default >/dev/null 2>&1 || true

if [ -s "$ZSH/oh-my-zsh.sh" ]; then
    source "$ZSH/oh-my-zsh.sh"
fi

# 进入 code-server 终端时自动激活工作区 Python 虚拟环境。
if [ -z "$VIRTUAL_ENV" ] && [ -f /workspace/.venv/bin/activate ]; then
    . /workspace/.venv/bin/activate
fi

source ~/.oh-my-zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
source ~/.oh-my-zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh

alias ll="ls -lah"
alias vi="vim"
alias gs="git status"
alias gc="git commit -m"
alias guc="git commit -am"
EOF
}

configure_git() {
    log "写入 Git 默认配置"
    git lfs install --system
    git config --global user.name "riverecho520"
    git config --global user.email "riverecho520@gmail.com"
    git config --global pull.rebase false
    git config --global init.defaultBranch main
    git config --global credential.helper "store --file=~/.git/.git-credentials"
}

configure_vim() {
    log "写入 Vim 配置"
    mkdir -p /root/.vim/pack/themes/start
    git clone --depth=1 https://github.com/dracula/vim.git /root/.vim/pack/themes/start/dracula

    cat >/root/.vimrc <<'EOF'
syntax on
set encoding=utf-8
set termguicolors
set background=dark
set smartindent
set wrap
set ruler
colorscheme dracula
EOF
}

configure_code_server() {
    log "写入 code-server 用户配置"
    mkdir -p "${CODE_SERVER_USER_DIR}" "${WORKSPACE_DIR}/.vscode"

    cat >"${CODE_SERVER_USER_DIR}/settings.json" <<'EOF'
{
    "editor.fontFamily": "JetBrains Mono, Menlo, Monaco, Consolas, 'Courier New', monospace",
    "window.menuBarVisibility": "classic",
    "editor.fontSize": 22,
    "editor.wordWrap": "on",
    "terminal.integrated.fontSize": 18,
    "terminal.integrated.defaultProfile.linux": "zsh",
    "terminal.integrated.profiles.linux": {
        "zsh": {
            "path": "/bin/zsh"
        }
    },
    "workbench.preferredDarkColorTheme": "Dracula Theme",
    "workbench.preferredLightColorTheme": "Dracula Theme",
    "workbench.iconTheme": "material-icon-theme",
    "window.autoDetectColorScheme": true,
    "editor.minimap.enabled": false,
    "editor.pasteAs.enabled": false,
    "editor.formatOnSave": true,
    "[shellscript]": {
        "editor.defaultFormatter": "foxundermoon.shell-format"
    },
    "[javascript]": {
        "editor.defaultFormatter": "esbenp.prettier-vscode"
    },
    "[css]": {
        "editor.defaultFormatter": "esbenp.prettier-vscode"
    },
    "[html]": {
        "editor.defaultFormatter": "esbenp.prettier-vscode"
    },
    "[typescript]": {
        "editor.defaultFormatter": "esbenp.prettier-vscode"
    },
    "[jsonc]": {
        "editor.defaultFormatter": "esbenp.prettier-vscode"
    },
    "[json]": {
        "editor.defaultFormatter": "esbenp.prettier-vscode"
    },
    "[python]": {
        "editor.defaultFormatter": "ms-python.black-formatter"
    },
    "prettier.printWidth": 120,
    "prettier.tabWidth": 4,
    "prettier.semi": false,
    "prettier.singleQuote": true,
    "prettier.bracketSpacing": true,
    "prettier.endOfLine": "auto"
}
EOF
}

cleanup_image() {
    log "清理构建缓存"
    npm cache clean --force >/dev/null 2>&1 || true
    pnpm store prune >/dev/null 2>&1 || true
    find /root/.oh-my-zsh /root/.vim -type d -name .git -prune -exec rm -rf {} + 2>/dev/null || true
    find /root/.local/share/code-server/extensions -type d \
        \( -name .git -o -name test -o -name tests -o -name __tests__ -o -name .github \) \
        -prune -exec rm -rf {} + 2>/dev/null || true
    find /root/.local/share/code-server/extensions -type f \
        \( -name '*.map' -o -name '*.tsbuildinfo' -o -iname 'CHANGELOG*' -o -iname 'README*' -o -iname 'LICENSE*' \) \
        -delete 2>/dev/null || true
    rm -rf \
        /root/.cache/go-build \
        /root/.cache/node-gyp \
        /root/.cache/pip \
        /root/.cache/pnpm \
        /root/.cache/uv \
        /root/.npm \
        /root/.local/share/pnpm/store \
        /root/.nvm/.cache \
        /root/.nvm/versions/node/*/lib/node_modules/npm/docs \
        /root/.nvm/versions/node/*/lib/node_modules/npm/html \
        /root/.nvm/versions/node/*/lib/node_modules/npm/man \
        /root/.nvm/versions/node/*/lib/node_modules/npm/tap-snapshots \
        /root/.nvm/versions/node/*/lib/node_modules/npm/test \
        /root/.cargo/git \
        /root/.cargo/registry \
        /root/.rustup/downloads \
        /root/.rustup/tmp \
        /root/.rustup/toolchains/*/share/doc \
        /root/.rustup/toolchains/*/share/man \
        /usr/local/go/api \
        /usr/local/go/doc \
        /usr/local/go/test \
        /root/.local/share/code-server/CachedData \
        /root/.local/share/code-server/coder-logs \
        /root/.local/share/code-server/logs \
        /root/.local/share/code-server/tmp \
        /root/.local/share/code-server/User/workspaceStorage \
        /root/.local/share/code-server/User/History \
        "${WORKSPACE_DIR}/.cache" \
        "${WORKSPACE_DIR}/target"
    if command -v go >/dev/null 2>&1; then
        go clean -cache -modcache -testcache >/dev/null 2>&1 || true
    fi
    if command -v cargo >/dev/null 2>&1; then
        cargo clean >/dev/null 2>&1 || true
    fi
    apt-get autoremove -y
    apt-get clean
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
}

main() {
    install_zsh_environment
    install_docker
    install_uv_python
    install_go
    install_shfmt
    install_nvm_node
    install_rust
    install_rclone
    install_deno
    configure_zsh
    configure_git
    configure_vim
    configure_code_server
    cleanup_image
}

main "$@"
