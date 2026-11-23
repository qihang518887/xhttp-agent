# xhttp-agent

Xray VLESS + XHTTP over TLS 一键脚本，由 v2ray-agent 删减而来。只做两件事：h3 直连、CDN 回源。

## 安装

菜单 `2.任意组合安装`，然后选：

```
1.H3直连
2.CDN(H2+H3)
```

可以单选，也可以 `1,2`。

| 选择 | 装的 inbound | 放行 | 用途 |
| --- | --- | --- | --- |
| 1 | `01_VLESS_XHTTP_H3_inbounds.json`（alpn 只有 h3） | UDP | 客户端 QUIC 直连源站 |
| 2 | `02_VLESS_XHTTP_TLS_inbounds.json`（alpn h2） | TCP | 给 CDN 回源 |
| 1,2 | 两份都装 | TCP + UDP | 直连和 CDN 并存 |

h3 只有 UDP，h2 只有 TCP，所以选 `1,2` 时同一个端口 TCP/UDP 各监听一次，不冲突。

不支持 REALITY，所以**不做 h2 直连**：现在的网络环境下 TLS 直连既不稳也不好用。选 2 时只输出走 CDN 的节点，源站直连那条不再生成。

## 端口怎么填

**选 2 时，端口必须是 CDN 会代理的端口**，否则那条 CDN 节点必然连不上（不是脚本问题，是 CDN 根本不代理这个端口）：

```
Cloudflare：443 / 2053 / 2083 / 2087 / 2096 / 8443
```

回车随机的 `10000-30000` 只适合纯直连（选 1）。选了 2 又用随机端口，客户端连 CDN 的对应端口会直接被拒。

源站监听的就是这里填的端口，CDN 回源也回到这个端口，两边必须一致。

## 直连域名/IP

选 1 时问：

- 留空 → 用公网 IP
- 填了 → 填什么写什么（域名或 IP 都行）

选 `1,2` 时必填，因为 CDN 那套的地址是证书域名，h3 直连那套得单独有个能拨的地址。

这个值存在 `/etc/v2ray-agent/xhttp-direct-address`，只影响 h3 直连节点的地址，SNI 始终是证书域名。

## CDN 节点怎么成立

CF 边缘是 anycast，客户端拨哪个 CF 边缘 IP 都行：边缘靠 TLS 的 SNI 认出域名属于哪个 zone，再按端口回源。所以 CDN 节点里两个值分工不同：

- **address / server**：拨号地址，落到 CF 边缘就行
- **sni + host**：证书域名，CF 靠它找到你的 zone，必须是你自己那个已开启代理（橙云）的域名

「优选」的本质就是换 address：换成别人调好、解析到快节点的域名，跟 SNI 没关系，也不需要跟你有任何关系，只要解析到 CF 就行。

**硬前提**：证书域名必须在 CF 上橙云。否则 CF 边缘拿到这个 SNI 找不到 zone，直接握手失败（不是变成直连，是连不上）。

## 优选CNAME

选 2 时问，只支持一个：

- **回车** → 用证书域名当 address，也就是拿自己的域名当边缘入口，不优选，速度看运气
- **填了** → 用填的域名替换 address，填谁解析到 CF 的都行

## 节点长什么样

| 节点 | 什么时候有 | 地址 | 端口 | 传输 |
| --- | --- | --- | --- | --- |
| `<账号>-VLESS_XHTTP_TLS_cdn1` | 选 2 | 证书域名 / 优选CNAME | 输入端口 | h2，mode packet-up |
| `<账号>-VLESS_XHTTP_TLS_cdn1_h3` | 选 2 | 同上 | 输入端口 | h3，mode packet-up（客户端到 CDN 边缘走 QUIC，回源仍是 h2） |
| `<账号>-VLESS_XHTTP_TLS` | 只选 1 | 直连域名/IP | 输入端口 | h3，mode auto |
| `<账号>-VLESS_XHTTP_TLS_h3` | 选 1,2 | 直连域名/IP | 输入端口 | h3，mode auto |

选 2 时固定出两条（h2 + h3），地址就是优选域名，回车则用证书域名。

客户端 `auto` 在 TLS 下实际解析成 `packet-up`（Xray 的 `splithttp/dialer.go`，只有 REALITY 才会走 stream-one/stream-up），所以 h3 和 CDN 节点都是 packet-up。为避免 h3 单连接默认 100 条流跑满后上传卡死，h3 inbound 里已写死 `finalmask.quicParams.maxIncomingStreams=4096`。

## 本地订阅

不部署订阅服务，只生成本地文件，账号管理里可以查看/复制：

```
/etc/v2ray-agent/subscribe_local/default/<账号键>      # Base64 通用订阅
/etc/v2ray-agent/subscribe_local/clashMeta/<账号键>    # Mihomo 节点
```

`<账号键>` 是 email 去掉 `-` 后面那段（`alice-VLESS_XHTTP_TLS` → `alice`），一个账号的所有节点写进同一个文件。

## 其他

- 只面向新部署，不管旧版本迁移和残留清理
- h3 需要放行 UDP，脚本里按选择自动 `allowPort <端口> udp`
- 勾选 2 时若端口被 UDP 占用会直接报错退出，随机端口会自动重抽
- Xray 装 GitHub 最新 release，h3 依赖较新版本