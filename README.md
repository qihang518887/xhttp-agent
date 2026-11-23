# xhttp-agent

Xray VLESS + XHTTP over TLS 安装脚本，支持 H3 直连和 CDN 回源。适用于 Debian、Ubuntu、CentOS 和 Alpine。

## 使用方法

先下载到文件，成功后再用 `sh` 运行（用 `&&` 串成一行；不要把下载内容直接 pipe 给 `sh`）：

### wget（Alpine BusyBox 也适用）

```sh
wget -O install.sh https://raw.githubusercontent.com/qihang518887/xhttp-agent/main/install.sh && sh install.sh
```

### curl

Alpine 如未安装 curl，先执行 `apk add --no-cache curl`。

```sh
curl -L -o install.sh https://raw.githubusercontent.com/qihang518887/xhttp-agent/main/install.sh && sh install.sh
```

Alpine 上脚本会检查并安装 Bash，再由 Bash 执行安装流程。

## 安装选项

主菜单选择 `2.任意组合安装`：

- `1`：H3 直连，客户端通过 UDP/QUIC 直连源站；直连地址可留空使用公网 IP。
- `2`：CDN 回源，源站使用 TCP/TLS，生成经 CDN 访问的 H2、H3 节点。
- `1,2`：同时安装直连和 CDN 配置。

选择 CDN 时，证书域名必须在 Cloudflare 开启橙云，端口必须是 Cloudflare 支持代理的端口（如 `443`、`2053`、`2083`、`2087`、`2096`、`8443`）。回车随机端口仅适合 H3 直连。

脚本只面向新部署，不提供旧版迁移；订阅只生成本地文件，不部署 HTTP 订阅服务。
