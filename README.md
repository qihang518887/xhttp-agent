# xhttp-agent

XHTTP的大厦已经建成，只有几朵乌云

## 使用方法

适用于 Debian、Ubuntu、CentOS 和 Alpine。下载后运行：

```sh
wget -O install.sh https://raw.githubusercontent.com/qihang518887/xhttp-agent/main/install.sh && sh install.sh
```

也可以使用 curl（Alpine 未安装时先执行 `apk add --no-cache curl`）：

```sh
curl -L -o install.sh https://raw.githubusercontent.com/qihang518887/xhttp-agent/main/install.sh && sh install.sh
```

安装时选择 `1.任意组合安装`，再选择 H3 直连、CDN，或同时安装两者。

## 特色

### H3 直连

- 使用 VLESS + XHTTP over TLS，通过 QUIC/UDP 直连服务器。
- 可设置目标速度；非 `0` 时在 H3 inbound 启用 Xray `force-brutal`，填 `0` 则不启用。

### CDN 接入

- 客户端可用 H3 连接 CDN 边缘节点，再由 CDN 通过 H2/TLS 回源。
- 同时生成 H2、H3 两种 CDN 节点，可按网络环境选择。
- CDN 域名需开启 Cloudflare 橙云；SNI 和 Host 使用证书域名。

### 管理功能

- 支持账号管理；生成本地 VLESS 订阅，并通过 OpenSSL HTTPS 在 `8443` 端口提供 Mihomo YAML 订阅。
- 支持证书续期、Xray core 管理和脚本更新。

## 注意事项

- H3 直连使用 QUIC/UDP；除了服务器系统防火墙，还需在云厂商安全组放行所选 UDP 端口。
- CDN 回源要求证书域名在 Cloudflare 开启橙云。客户端到 CDN 可使用 H3，CDN 到源站仍通过 H2/TLS 回源。
- CDN 只能使用 Cloudflare 支持代理的 HTTPS 端口，例如 `443`、`2053`、`2083`、`2087`、`2096`、`8443`。随机端口适合 H3 直连，不保证能用于 CDN。
- 优选地址只用于连接 CDN 边缘；SNI 和 Host 始终使用证书域名。
- VLESS + XHTTP 节点需要启用 TLS。若订阅转换后显示 `tls: false`，需检查转换器生成的客户端配置。
- 请先下载到文件，再用 `sh install.sh` 运行；不要把下载内容直接 pipe 给 `sh`。Alpine 上脚本会处理 Bash 启动。
- Mihomo HTTPS 订阅使用 `8443/tcp`，除系统防火墙外，还需在云厂商安全组放行该端口。
- HTTPS 订阅链接使用原版同类的每用户哈希路径作为访问凭证，请妥善保管；任何获得链接的人都能下载对应 YAML。

## 致谢

感谢 [mack-a/v2ray-agent](https://github.com/mack-a/v2ray-agent) 项目提供的原始脚本与思路。本项目基于该项目改造，谨致谢意。
