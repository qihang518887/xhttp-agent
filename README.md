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

## 特色

- Xray VLESS + XHTTP over TLS，支持 H3 直连和 CDN 回源，可组合安装。
- 账号管理并生成本地订阅，不部署 HTTP 订阅服务。
- 提供证书、Xray core 和脚本更新管理。
