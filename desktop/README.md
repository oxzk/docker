# GNOME Desktop

使用 Ubuntu 24.04, GNOME X11, KasmVNC 1.5.0 和 Cloudflared. 使用非 root 用户 `admin` 运行桌面, 使用软件渲染. 不安装 SSH Server, 不要求 privileged 或宿主机 systemd.

## 启动

在本目录创建 `.env`, 设置至少 6 个字符的桌面密码:

```dotenv
PASSWORD=replace-with-your-password
```

将容器环境变量统一写入与 `compose.yml` 同目录的 `.env`, 通过 `env_file` 加载. 按需添加 `CLOUDFLARED_TOKEN`, `DESKTOP_WIDTH` 等配置; 省略可选项以使用默认值. 修改 `.env` 后执行 `docker compose up -d desktop` 重新创建容器, 使配置生效.

执行:

```bash
docker compose pull desktop
docker compose up -d
docker compose logs -f desktop
```

打开 `http://localhost:8444`, 使用用户名 `admin` 和 `.env` 中的密码登录. Cloudflared 始终启动, 未配置令牌时使用 Quick Tunnel, 从容器日志读取 `https://*.trycloudflare.com` 地址后可直接使用浏览器访问.

默认主机名为 `vm`. 系统用户 `admin` 无密码, 可免密执行 `sudo`. KasmVNC 网页登录仍使用 `.env` 中的 `PASSWORD`.

需要固定域名时在 `.env` 中设置 `CLOUDFLARED_TOKEN`, 在 Cloudflare 控制台将该域名的服务配置为 `http://localhost:8444`.

## 单独构建和运行

在仓库根目录执行:

```bash
docker build -t oxzk/desktop:latest ./desktop
docker run -d --name desktop --hostname vm --shm-size=2g \
  --tmpfs /run:rw,nosuid,nodev,mode=755 \
  -p 127.0.0.1:8444:8444 \
  --env-file ./desktop/.env \
  -v "$(pwd)/desktop/data/desktop:/home/admin" \
  oxzk/desktop:latest
```

使用默认绑定挂载 `./data/desktop:/home/admin`, 相对路径以 `compose.yml` 所在目录为基准, 对应仓库内的 `desktop/data/desktop`. 保留该目录以保存桌面文件和应用配置. 不要在多个容器间共用同一个桌面目录.

保持入口脚本以 root 启动, 由脚本将挂载目录本身的所有者设置为 `admin` (UID/GID 1000), 权限设置为 `0700`, 再以 `admin` 运行桌面. 确保挂载可读写且宿主机文件系统允许修改所有者和权限. 迁入已有文件时, 确保这些文件也允许 UID/GID 1000 访问; 启动脚本不会递归修改桌面数据的权限.

更新入口脚本后, 先构建并发布新版镜像, 再执行 `docker compose pull desktop` 和 `docker compose up -d desktop` 拉取镜像并重新创建容器.

## 配置

| 配置 | 默认值 | 约束 |
| --- | --- | --- |
| `PASSWORD` | 必填 | 至少 6 个字符, 不包含换行 |
| `CLOUDFLARED_TOKEN` | 空 | 为空时创建 Quick Tunnel |
| `KASMVNC_WEBSOCKET_PORT` | `8444` | 修改时同时更新端口映射和受管 Tunnel 配置 |
| `DESKTOP_WIDTH` | `1920` | 1..8192 |
| `DESKTOP_HEIGHT` | `1080` | 1..8192 |

使用构建参数 `KASMVNC_VERSION` 和 `CLOUDFLARED_VERSION` 指定组件版本. 支持 `linux/amd64` 和 `linux/arm64` 对应的官方软件包.

关键服务退出时容器返回非零状态, 由重启策略重新启动. 使用 `docker compose down` 停止服务, 保留宿主机数据目录.
