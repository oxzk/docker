#!/bin/bash

ARCH=$(dpkg --print-architecture)

sh -c "$(wget https://raw.github.com/robbyrussell/oh-my-zsh/master/tools/install.sh -O -)"
chsh -s $(which zsh)
export SHELL=$(which zsh)
echo "current shell: $SHELL\n"
ls -la

git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ~/.oh-my-zsh/plugins/zsh-syntax-highlighting
echo "source ~/.oh-my-zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" >>~/.zshrc

git clone https://github.com/zsh-users/zsh-autosuggestions ~/.oh-my-zsh/plugins/zsh-autosuggestions
echo "source ~/.oh-my-zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh" >>~/.zshrc

# 获取系统架构
get_arch() {
    local arch=$(uname -m)
    case $arch in
    x86_64)
        echo "amd64"
        ;;
    aarch64 | arm64)
        echo "arm64"
        ;;
    *)
        echo "amd64" # 默认使用amd64
        ;;
    esac
}

# 验证命令安装是否成功
verify_installation() {
    local cmd_name="$1"
    local cmd_path="$2"
    local version_flag="${3:---version}"

    # 如果指定了路径，优先使用路径
    local check_cmd
    if [ -n "$cmd_path" ] && [ -x "$cmd_path" ]; then
        check_cmd="$cmd_path"
    elif command -v "$cmd_name" >/dev/null 2>&1; then
        check_cmd="$cmd_name"
    else
        echo "错误: $cmd_name 安装失败，命令不可用"
        return 1
    fi

    echo "$cmd_name 安装成功:"
    if ! $check_cmd "$version_flag" 2>/dev/null; then
        # 如果 --version 失败，尝试其他常见的版本参数
        case "$version_flag" in
        "--version")
            $check_cmd -version 2>/dev/null || $check_cmd version 2>/dev/null || echo "版本信息获取失败"
            ;;
        *)
            echo "版本信息获取失败"
            ;;
        esac
    fi
    return 0
}

# 安装 cwebp
install_cwebp() {
    local version=${1:-"1.5.0"}
    local arch=${2:-$(get_arch)}
    local url_base="https://storage.googleapis.com/downloads.webmproject.org/releases/webp/"
    local cwebp_arch

    case $arch in
    amd64)
        cwebp_arch="x86-64"
        ;;
    arm64)
        cwebp_arch="aarch64"
        ;;
    *)
        cwebp_arch="x86-64"
        ;;
    esac

    local filename="libwebp-${version}-linux-${cwebp_arch}.tar.gz"
    local download_url="${url_base}${filename}"

    echo "Installing cwebp ${version} for ${arch} architecture..."
    echo "Download URL: ${download_url}"

    # 下载文件
    if ! curl -f --no-progress-meter "${download_url}" --output "/tmp/${filename}"; then
        echo "错误: 下载 cwebp 失败"
        return 1
    fi

    # 解压和安装
    if ! tar --strip-components=1 -zxf "/tmp/${filename}" -C /tmp; then
        echo "错误: 解压 cwebp 失败"
        return 1
    fi

    # 移动二进制文件
    if ! mv /tmp/bin/* /usr/local/bin/ 2>/dev/null; then
        echo "错误: 安装 cwebp 到 /usr/local/bin 失败，可能需要 sudo 权限"
        return 1
    fi

    # 验证安装
    verify_installation "cwebp" "/usr/local/bin/cwebp" "-version"
}
# 安装 v2ray
install_v2ray() {
    local version=${1:-"v4.45.2"}
    local arch=${2:-$(get_arch)}
    local v2ray_arch

    case $arch in
    amd64)
        v2ray_arch="64"
        ;;
    arm64)
        v2ray_arch="arm64-v8a"
        ;;
    *)
        v2ray_arch="64"
        ;;
    esac

    local filename="v2ray-linux-${v2ray_arch}.zip"
    local download_url="https://github.com/v2fly/v2ray-core/releases/download/${version}/${filename}"

    echo "Installing v2ray ${version} for ${arch} architecture..."
    echo "Download URL: ${download_url}"

    # 下载文件
    if ! curl -o "/tmp/${filename}" -L "${download_url}"; then
        echo "错误: 下载 v2ray 失败"
        return 1
    fi

    # 创建安装目录
    mkdir -p /usr/local/v2ray

    # 解压文件
    if ! unzip -o "/tmp/${filename}" -d /usr/local/v2ray; then
        echo "错误: 解压 v2ray 失败"
        return 1
    fi

    # 设置执行权限
    chmod +x /usr/local/v2ray/v2ray

    # 创建软链接到系统PATH
    if [ ! -L /usr/local/bin/v2ray ]; then
        ln -sf /usr/local/v2ray/v2ray /usr/local/bin/v2ray
    fi

    # 验证安装
    verify_installation "v2ray" "/usr/local/v2ray/v2ray" "--version"
}
# 安装 golang
install_golang() {
    local version=${1:-"1.24.3"}
    local arch=${2:-$(get_arch)}
    local golang_arch

    case $arch in
    amd64)
        golang_arch="amd64"
        ;;
    arm64)
        golang_arch="arm64"
        ;;
    *)
        golang_arch="amd64"
        ;;
    esac

    local filename="go${version}.linux-${golang_arch}.tar.gz"
    local download_url="https://go.dev/dl/${filename}"

    echo "Installing Go ${version} for ${arch} architecture..."
    echo "Download URL: ${download_url}"

    # 下载文件
    if ! curl -o "/tmp/${filename}" -L "${download_url}"; then
        echo "错误: 下载 Go 失败"
        return 1
    fi

    # 解压安装
    if ! tar zxf "/tmp/${filename}" -C /usr/local/; then
        echo "错误: 解压 Go 失败"
        return 1
    fi

    export PATH=$PATH:/usr/local/go/bin

    verify_installation "go" "/usr/local/go/bin/go" "version"
}

install_cwebp
install_v2ray
install_golang

echo 'alias ll="ls -lah"' >>~/.zshrc
echo 'alias vi="vim"' >>~/.zshrc
echo 'alias gs="git status"' >>~/.zshrc
echo 'alias gc="git commit -m"' >>~/.zshrc
echo 'alias guc="git commit -am"' >>~/.zshrc
echo 'export LANG=zh_CN.UTF-8' >>~/.zshrc
echo 'export LANGUAGE=zh_CN.UTF-8' >>~/.zshrc
echo 'export SHELL=/bin/zsh' >>~/.zshrc
echo 'DRACULA_DISPLAY_CONTEXT=1' >>~/.zshrc
echo 'DRACULA_DISPLAY_FULL_CWD=1' >>~/.zshrc
echo 'DRACULA_DISPLAY_GIT=1' >>~/.zshrc
echo 'export GOPATH=~/.local/share/go' >>~/.zshrc
echo 'export DENO_DEPLOY_TOKEN=""' >>~/.zshrc
echo 'export PATH=/usr/local/go/bin:$PATH' >>~/.zshrc
echo 'export PATH=/root/.deno/bin:$PATH' >>~/.zshrc

curl https://rclone.org/install.sh | zsh

curl -fsSL https://deno.land/install.sh | zsh
export PATH="/root/.deno/bin:$PATH"
deno --version
deno install -gArf jsr:@deno/deployctl
deployctl --version

curl -fsSL https://get.pnpm.io/install.sh | zsh -
export PNPM_HOME="/root/.local/share/pnpm"
export PATH="$PNPM_HOME:$PATH"
pnpm env use 22 --global
pnpm add -g edgeone
# pnpm add -g wrangler@latest
# pnpm add -g eslint
# pnpm add supabase --save-dev --allow-build=supabase

git config --global user.name "oxzk"
git config --global user.email "riverecho520@gmail.com"
git config --global pull.rebase false
git config --global init.defaultBranch main
git config --global credential.helper "store --file=~/.git/.git-credentials"

cat >~/.vimrc <<EOF
syntax on
set encoding=utf-8
set smartindent
set wrap
set ruler
EOF

cat >~/.local/share/code-server/User/settings.json <<EOF
{
    "editor.fontFamily": "JetBrains Mono, Menlo, Monaco, Consolas, 'Courier New', monospace",
    "window.menuBarVisibility": "classic",
    "editor.fontSize": 22,
    "editor.wordWrap": "on",
    "terminal.integrated.fontSize": 18,
    "workbench.preferredDarkColorTheme": "Dracula Theme",
    "workbench.preferredLightColorTheme": "Dracula Theme",
    "workbench.iconTheme": "material-icon-theme",
    "window.autoDetectColorScheme": true,
    "workbench.layoutControl.enabled": false,
    "editor.minimap.enabled": false,
    "editor.pasteAs.enabled": false,
    "editor.formatOnSave": true,
    "deno.enable": true,
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

mkdir -p /workspace/.vscode/

cd /workspace
python3 -m venv .venv
# . .venv/bin/activate
# pip install playwright sanic requests aioredis aiohttp pysocks python-dotenv
# playwright install chrome

apt-get purge make gcc g++ -y
apt-get autoremove -y
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
