# GNOME Desktop

使用 Ubuntu 24.04, Ubuntu GNOME Shell X11, KasmVNC 1.5.0 和 Cloudflared. 使用非 root 用户 `admin` 运行桌面, 使用软件渲染. 由入口脚本分别管理 Xvnc、用户 D-Bus、GNOME Shell 和设置服务. 不安装 SSH Server, 不要求 tmpfs、privileged 或宿主机 systemd.

## 启动

在本目录创建 `.env`, 设置至少 6 个字符的桌面密码:

```dotenv
PASSWORD=replace-with-your-password
```

将容器环境变量统一写入与 `compose.yml` 同目录的 `.env`, 通过 `env_file` 加载. 按需添加 `WARP_ENABLED`, `CLOUDFLARED_TOKEN`, `DESKTOP_WIDTH` 等配置; 省略可选项以使用默认值. 修改 `.env` 后执行 `docker compose up -d desktop` 重新创建容器, 使配置生效.

执行:

```bash
docker compose pull desktop
docker compose up -d
docker compose logs -f desktop
```

打开 `http://localhost:8444`, 使用用户名 `admin` 和 `.env` 中的密码登录. Cloudflared 始终启动, 未配置令牌时使用 Quick Tunnel, 从容器日志读取 `https://*.trycloudflare.com` 地址后可直接使用浏览器访问.

默认主机名为 `vm`. 系统用户 `admin` 无密码, 可免密执行 `sudo`. KasmVNC 网页登录仍使用 `.env` 中的 `PASSWORD`.

需要固定域名时在 `.env` 中设置 `CLOUDFLARED_TOKEN`, 在 Cloudflare 控制台将该域名的服务配置为 `http://localhost:8444`.

## WARP 客户端

默认启用 Cloudflare WARP, 使用 `warp+doh` 模式处理容器的出站流量和 DNS. 保留 Compose 中的 `/dev/net/tun` 设备映射和 `NET_ADMIN` 能力, 并确保 Linux 宿主机存在该设备. 首次启用时由脚本使用 `--accept-tos` 注册客户端并连接, 将注册信息保存在 `./data/warp`.

需要关闭 WARP 时, 在 `.env` 中设置:

```dotenv
WARP_ENABLED=false
```

执行 `docker compose up -d desktop` 重新创建容器. 设为 `true` 或省略该变量以启用 WARP. 关闭时不启动 `warp-svc`, 不注册或连接 WARP, 保留已安装的 `warp-cli` 和注册数据. Cloudflared Tunnel 仍按原配置启动.

等待日志出现 `WARP connected`, 该提示表示实际出口检查返回 `warp=on` 或 `warp=plus`. 连接失败时让容器明确报错退出, 不自动切换为直连. 需要查看状态时在部署机器执行 `docker compose exec desktop warp-cli --accept-tos status`.

Compose 中的设备映射和网络能力不会随 `WARP_ENABLED` 自动移除. 若宿主机不提供 TUN 设备, 关闭 WARP 后同时移除服务的 `devices` 和 `cap_add` 配置.

## 单独构建和运行

在仓库根目录执行:

```bash
docker build -t oxzk/desktop:latest ./desktop
docker run -d --name desktop --hostname vm --shm-size=2g \
  --cap-add NET_ADMIN --device /dev/net/tun:/dev/net/tun \
  -p 127.0.0.1:8444:8444 \
  --env-file ./desktop/.env \
  -v "$(pwd)/desktop/data/desktop:/home/admin" \
  -v "$(pwd)/desktop/data/warp:/var/lib/cloudflare-warp" \
  oxzk/desktop:latest
```

使用默认绑定挂载 `./data/desktop:/home/admin`, 相对路径以 `compose.yml` 所在目录为基准, 对应仓库内的 `desktop/data/desktop`. 保留该目录以保存桌面文件和应用配置. 不要在多个容器间共用同一个桌面目录.

保持入口脚本以 root 启动, 由脚本将挂载目录本身的所有者设置为 `admin` (UID/GID 1000), 权限设置为 `0700`, 再以 `admin` 运行桌面. 确保挂载可读写且宿主机文件系统允许修改所有者和权限. 迁入已有文件时, 确保这些文件也允许 UID/GID 1000 访问; 启动脚本不会递归修改桌面数据的权限.

更新入口脚本后, 先构建并发布新版镜像, 再执行 `docker compose pull desktop` 和 `docker compose up -d desktop` 拉取镜像并重新创建容器.

## 内置软件

在桌面终端使用 `uv`, `uvx` 和 `fastfetch`, 两种架构均安装这些工具. 工具安装在系统目录, 挂载 `/home/admin` 后仍可使用.

使用官方 Linux `.tar.gz` 压缩包安装 Fastfetch, 将可执行文件放在 `/usr/local/bin/fastfetch`, 权限设为 `0755`.

在 `linux/amd64` 桌面的应用菜单启动 Google Chrome 稳定版, 或在终端执行 `google-chrome`. `linux/arm64` 不安装 Chrome.

保留 Chrome 默认沙箱. 若启动时出现 `Failed to move to new namespace` 或 `Operation not permitted`, 检查宿主机及容器对用户命名空间和沙箱的权限限制; 当前验证环境存在该限制, 尚未验证 Chrome 页面渲染.

在两种架构的应用菜单启动 Firefox, 或在终端执行 `firefox`. 使用 Mozilla 官方 deb 仓库的稳定版及简体中文语言包, 通过 APT 更新.

通过构建参数 `UV_VERSION` 和 `FASTFETCH_VERSION` 固定工具版本, 默认使用 `latest`. 分别填写对应上游发布标签, 例如 uv 使用 `0.8.22`, fastfetch 使用 `2.52.0`. Chrome 使用构建时的官方稳定版.

使用支持 BuildKit 的 Docker 构建镜像. 通过 `install.sh` 在同一层完成依赖安装与临时文件清理. 保留桌面组件, 字体, 语言资源和软件版权文件; 不安装离线手册及软件包说明文档.

## 配置

| 配置 | 默认值 | 约束 |
| --- | --- | --- |
| `PASSWORD` | 必填 | 至少 6 个字符, 不包含换行 |
| `WARP_ENABLED` | `true` | 仅接受 `true` 或 `false`, 控制 WARP 客户端启动和连接 |
| `CLOUDFLARED_TOKEN` | 空 | 为空时创建 Quick Tunnel |
| `KASMVNC_WEBSOCKET_PORT` | `8444` | 修改时同时更新端口映射和受管 Tunnel 配置 |
| `DESKTOP_WIDTH` | `1920` | 1..8192 |
| `DESKTOP_HEIGHT` | `1080` | 1..8192 |

使用构建参数 `KASMVNC_VERSION` 和 `CLOUDFLARED_VERSION` 指定组件版本. 支持 `linux/amd64` 和 `linux/arm64` 对应的官方软件包.

关键服务退出时容器返回非零状态, 由重启策略重新启动. 使用 `docker compose down` 停止服务, 保留宿主机数据目录.
