# 校园网共享检测教程核验与当前两路方案

核验日期：2026 年 10 月 12 日。本文只读公开博客、上游文档、固定版本源码和本任务已有的相关验证材料。没有 SSH、安装、认证试验或路由器改动。设备基线由主代理提供：AX6000 RB06、OpenWrt SNAPSHOT、Linux 6.18.55；Android 与 Linux 两路认证稳定，第三路会相互扰动，保持停用；OpenClash 为唯一客户端透明入口；需处理的直连 TCP 经 UA3F 3.7.0 的 `127.0.0.1:1080` SOCKS5；独立 nft 在明确 WAN 出口将 IPv4 TTL ≥ 10 改为 64；原 UA3F TC TTL、flow offload 与 WED 关闭。

当前优先补齐实际包路径与测速证据，保留两路稳定认证。博客支持 TTL、明文 HTTP UA、部分应用特征这几个检查方向，却不足以证明本校使用哪些检测，也不足以说明带宽未到 700 Mbps 的原因。不要把 UA2F、IPID、Timestamp、QUIC 阻断、NTP、DNS、IPv6 和多种卸载一次全开。

## 博客读到了什么，哪些内容可以用

| 原文与时间 | 可用线索 | 核验后的适用边界 |
| --- | --- | --- |
| [SunBK201：关于某大学校园网共享上网检测机制的研究与解决方案](https://blog.sunbk201.site/posts/crack-campus-network)，正文含 2025 年 11 月更新 | 作者按 TTL、HTTP UA、TCP 时钟偏移、应用特征分层；主张应用特征流量通过加密代理 | 这是某校经验与作者判断。不能把文中 IPID 检测已无必要、四类机制都会出现或安装即生效推广到当前设备。实际包默认 disabled，当前配置和出口读回优先。 |
| [Looking4U：重庆大学校园网多设备检测对抗实战](https://lucky-z.fun/p/1e43e556.html)，2026-05-16 | 明确检查 IPv6、TCP 接管范围、TTL 与 offload、UDP/443 和 NTP；报告关闭 offload 后负载增加 | CQU 登录协议与当前 ESurfing 不同。作者自己的负载数据不能作 AX6000 性能预测。“TCP 重建后全部特征统一”只适用于相应 TCP 栈字段，不包括客户端 TLS、QUIC 和行为。 |
| [zzyan：校园网共享配置指北](https://blog.zzyan.com/p/campus-network-sharing-guide/)，2024-09-23 | 给出 UA、TTL 入口，展示同机 IPID、TSval 不连续的抓包 | 这能否定“同机所有连接都必须同一递增序列”的简单前提，不能据此证明时间戳或 IPID 检测不存在。Linux 默认每连接加入随机 Timestamp offset。 |
| [L3zc：长沙理工大学校园网共享指南](https://blog.l3zc.com/zh-hant-tw/2023/09/csust-network-guide/)，2023 路径 | 区分包字段与应用审计，说明本校情况可能不同 | `POSTROUTING -o br-lan --ttl-set 65` 处理向 LAN 发出的包；终端看到 ping 回复 TTL 65 不能证明出 WAN 请求 TTL 已规范化。NTP 收敛也不能证明 TCP Timestamp 或时钟偏移统一。 |
| [Narcssu：AX3000T + OpenWrt 校园网多设备共享踩坑全记录](https://blog.narcssu.top/posts/campus-openwrt-share/)，2026-09-15 | 多套透明链、DNS 重定向和开机时序值得检查 | 原文“只监听本地端口即可透明接管”和“UA3F 与 Mihomo 同时运行必然冲突”不符合上游接入契约。`connection reset by peer` 也不唯一指向链冲突。官方提供两者经 SOCKS5 共存示例，应检查真正的流量归属和回环绕过。 |

以上博客作为线索使用。实际能力判断依据下面的上游代码和协议文档；没有以教程作者的“恢复正常”替代当前设备验收。

## 当前配置能覆盖到哪一层

| 信号 | 目前能做什么 | 仍会留下什么，或需查什么 |
| --- | --- | --- |
| IPv4 TTL | 独立 nft 按 `wan`、`eswan2` 出口改成 64；保留 TTL < 10 的诊断包 | 已有两出口 ICMP 抓包显示 TTL 64 且源 MAC 保持。这里只证明相关 ICMP 样本。还需检查实际 LAN TCP／UDP、路由器自身出站和重连后路径，不能用规则计数代替实际包值。 |
| 明文 HTTP UA | 经 UA3F 的 HTTP 请求可重写，当前用固定值 `FFF` | 需覆盖实际直连 TCP 范围和非 80 端口。固定值本身不是客户端身份，也不能保证检测通过；改成很长的浏览器 UA 不是带宽修复。认证与校园服务保持明确绕过。 |
| TCP 栈特征 | 经过本地 SOCKS5 的上游 TCP 由路由器建立，MSS、窗口、Timestamp 等通常来自路由器栈 | 普通 NAT／UDP／绕过流量仍保留客户端特征。代理新建 OUTPUT 不自动继承客户端原 WAN 选择，须检查它自己的 mark、GID 与策略路由。 |
| TLS 与 HTTPS | MitM 关闭时转发客户端加密字节；HTTP Header 受 TLS 保护 | 本地 UA3F 不统一 TLS ClientHello。SNI 是否可见取决于实际 TLS／ECH；目标地址、时序和流量量仍在。远端加密隧道只覆盖确实进隧道的流量，并有可见外层行为。 |
| QUIC／其他 UDP | 当前 UA3F SOCKS 节点设 `udp:false` | 这不等于全局没有 UDP/443。要核对 OpenClash 的 UDP 实际选择、LAN 绕过和 IPv6。UA3F UDP ASSOCIATE 是中继，不是 QUIC 指纹重写。 |
| DNS | 客户端普通 DNS 可集中到路由器，再按校园／公网分流 | TCP/UDP 53 重定向不覆盖客户端自带 DoH/DoT。DNS 路径正确有助于域名规则和避免解析循环，已经建立的大文件 TLS 下载不会因此自动提速。 |
| NTP | 路由器可提供局域网 NTP 服务并减少外发 UDP/123 目的地 | 对时不等于 TCP 时间戳统一；客户端还可能使用蜂窝、HTTPS 或其他时间来源。强制重定向不支持带认证的全部时间协议。 |
| IPv6 | 必须单独核对 LAN 地址、RA/DHCPv6、默认路由与实际连接 | UA3F 3.7.0 的 TC 程序检查 IPv4，不提供 IPv6 Hop Limit 重写。`Clash ipv6:false` 本身不能证明 LAN/WAN IPv6 已关闭或全部入代理。 |
| 账号／会话与统计 | 当前两路身份和各自认证、心跳隔离是可观察事实 | 第三路扰动可能属于服务器策略或会话绑定；改 UA／TTL 不一定解决。并发、时序、目标群体与总流量不会被本地字段改写消除。 |

源：[官方 SOCKS5 接入文档](https://github.com/SunBK201/UA3F/blob/v3.7.0/docs/zh/guide/proxy-integration.md)、[官方 Clash 示例](https://github.com/SunBK201/UA3F/blob/v3.7.0/configs/clash/ua3f-socks5-global.yaml)、[SOCKS5 拨号与 UDP 实现](https://github.com/SunBK201/UA3F/blob/v3.7.0/internal/server/socks5/socks5.go)、[TCP mark](https://github.com/SunBK201/UA3F/blob/v3.7.0/internal/server/base/tcp_linux.go)、[HTTP／TLS 转发](https://github.com/SunBK201/UA3F/blob/v3.7.0/internal/server/base/server.go)。现有 ICMP 证据：`../ua3f/nft-active-wan-packets.txt`、`../ua3f/nft-active-eswan2-packets.txt`。

## 可以实施的调整与验收顺序

### 1. 保持单一透明入口，先检查真实出口

保留 OpenClash → 本地 UA3F SOCKS5 的直连 TCP 分支和独立远端代理分支。认证、校园 DNS、网关与控制流量按当前固定 WAN 直连。不要再部署第二套全 TCP TPROXY／REDIRECT 或 NFQUEUE。对 LAN、UA3F 的新 OUTPUT、Ninja 的外层连接分别读实际 socket、mark、源地址、路由表和 WAN 计数；原 LAN 连接的 mwan3 标记不能证明后两类用了同一出口。

验收选择少量自有请求：明文 HTTP 回显检查 UA；HTTPS 检查响应码和完整下载；每条 WAN 各抓少量请求方向的 IP/TCP 头，读 TTL、源 MAC、TCP options 和实际出接口。不要抓认证正文或把共享凭据写入报告。测试保持第三路停用。

### 2. 独立 nft TTL 继续使用，先不为了测速重开 offload

Linux flowtable 命中后绕过 ingress 后的传统转发 hooks，因此 postrouting TTL 规则不能覆盖所有软件／硬件 offload 包。上游 v3.7.0 已有入口 TTL = 目标 + 1 的补偿方案，故“软件卸载永远无法与 TTL 共存”也过于绝对；但它改变入口范围，不能把当前严格按 WAN 的规则直接视为已兼容。当前原 TC `parse_l2` 缺陷的回放证据仍成立，保持退役，不用旧教程重开。

软件卸载若以后确有需要，必须设计受限的 LAN ingress 补偿、优先级、转发出口、LAN 内路由和低 TTL 例外，再读 WAN 上完整连接生命周期中的真实包。硬件 PPE／WED 的覆盖与抓包可见性需独立验证。开启它们不是当前用户态 TCP 代理链的已证实优化。

源：[Linux flowtable 原理](https://www.kernel.org/doc/html/latest/networking/nf_flowtable.html)、[固定版本 TTL 说明](https://github.com/SunBK201/UA3F/blob/v3.7.0/docs/zh/l3/ttl.md)、[入口补偿与 postrouting 源码](https://github.com/SunBK201/UA3F/blob/v3.7.0/internal/server/netlink/nftables.go)、[TC 解析源码](https://github.com/SunBK201/UA3F/blob/v3.7.0/internal/bpf/tc/tc.c)。本任务缺陷回放见 `../ua3f/ttl-l2-reproduction.json`；它不是线上损坏帧直接取证。

### 3. QUIC 只做受限比较，不全局封 UDP

如果抓包确认某个待覆盖的浏览器直连 UDP/443 绕过当前 TCP 链，可对单个测试客户端、互联网出口、UDP/443 做短时 reject 比较，检查浏览器是否转为 TCP、视频是否正常、延迟和吞吐是否变化。保留认证、校园服务和已有远端代理例外，结束后回退。QUIC 不只使用 443；UDP/443 也可能承载远端隧道。所有 UDP 的全局禁用会波及游戏、实时通信和 DNS，不由此推导。

UA3F 官方阻断功能实际是 UDP/443 丢弃，不能把开关解释成 QUIC 全识别。TCP 回落是否发生、何时发生由应用和网络共同决定，不保证所有 App 回落成功。

源：[UA3F QUIC 阻断](https://github.com/SunBK201/UA3F/blob/v3.7.0/docs/zh/l3/block-quic.md)、[HTTP/3 协议](https://www.rfc-editor.org/rfc/rfc9114.html)。

### 4. DNS 与 NTP 先收敛配置，不承诺消除检测

DNS 由一个明确入口接收并送入当前解析链，校园／认证域名保留本地正确答案。检查客户端解析结果、实际上游与 `dnsmasq`／OpenClash 是否循环；对客户端 DoH/DoT 另作可观察检查，不能仅靠 53 端口规则断言无泄漏。NTP 可先通过 DHCP 提供路由器时间服务；没有外发多目的地证据时，不新增强制劫持。二者作为网络正确性和减少外发差异的措施，不把它们写成统一 TCP 时间戳的证明。

Linux 6.18 文档明确 `tcp_timestamps=1` 默认每连接随机偏移。不同连接 TSval 不同是正常现象；NTP 校时也不会消除该偏移。Timestamp 用于 RTT 测量和 PAWS，清除有真实传输取舍。

源：[Linux 6.18 IP sysctl](https://github.com/torvalds/linux/blob/v6.18/Documentation/networking/ip-sysctl.rst)、[RFC 7323](https://www.rfc-editor.org/rfc/rfc7323.html)。

### 5. IPID、Timestamp 与 UA2F 不作为当前默认加装

IPID 与分片重组相关；原 UA3F TC 清零实现没有按 DF/MF 限定，仅凭教程不宜全包清零。RFC 6864 允许 atomic datagram 的 ID 任意，但 non-atomic／分片仍有约束。旧 `CHN-beta/rkp-ipid` 已归档，当前内核 6.18.55 的额外模块还涉及精确 ABI 与退出回退；它不是必要通用组件。

经过 SOCKS5 的 TCP 已由路由器重建，继续删 Timestamp 的边际收益需依据抓包和断线原因判断。UA3F TC Timestamp 程序只改初始 SYN；非 BPF 路径可能引入 NFQUEUE。不要在尚有吞吐疑问时增加包队列和 connmark 处理。

UA2F 上游是 **Zxilly/UA2F**，不是 SunBK201/UA2F。本次实时 API 确认最新正式版为 **v5.2.0，2026-06-13**。该版本支持 NFQUEUE、REDIRECT、TPROXY、多个 worker，旧教程把它描述成只能队列处理已过时。其 NFQUEUE 自定义 UA 保持包长，会截断或补空格；`disable_connmark` 可减少与其他程序的冲突，但作者明确有性能代价。现有 UA3F 已承担相关功能，没有叠装必要；若以后确要替换，应只做单独替换比较，并保护 mwan3 mark/mask 契约。

源：[RFC 6864](https://www.rfc-editor.org/rfc/rfc6864.html)、[UA3F TC 实现](https://github.com/SunBK201/UA3F/blob/v3.7.0/internal/bpf/tc/tc.c)、[UA2F v5.2.0 原文配置](https://github.com/Zxilly/UA2F/blob/v5.2.0/README.md)、[正式发布](https://github.com/Zxilly/UA2F/releases/tag/v5.2.0)、[rkp-ipid](https://github.com/CHN-beta/rkp-ipid)。

## 带宽未到 700 Mbps：先按路径拆开

普通 mwan3 做连接分配与故障切换；一个普通 TCP 连接不会因为有两条认证自动把下载拆到两个 WAN。UA3F／OpenClash 新建的本机连接也要按自身路由读回。Ninja 若复用为少量长连接，很多内层请求可能共用同一外层 WAN，这要检查实际 sockets，不能按 App 并发数推定两路聚合。

本任务无线代理回报，HE80 的路由器 RAM → PC 局域网测试达到约 695～763 Mbps；这说明此前 300～400 Mbps 公网结果不能简单归因为无线硬上限。它不证明路由器两路公网可持续达到 700 Mbps，也不证明并发代理性能。

主代理最新报告：固定微软 HTTP URL 和目的 IPv4 `171.108.209.190`，路由器裸出口两 WAN 各 4 × 128 MiB，合计 1 GiB 在 13.91 秒完成，全程均值 617.54 Mbps，两个出口约 580／542 MB、CPU 约 24%；PC 经 OpenClash → UA3F 的 8 × 128 MiB 请求耗时约 25 秒、部分超时，WAN2 约 1079 MB、main 约 49 MB，两 WAN 始终 online。这里是主代理回报，本文未独立执行。它表明本轮直连有可叠加容量，而代理请求明显偏向 WAN2；尚需确认 8 个实际新外层 TCP 的数量、标记与规则命中，不能据此认定 UA3F 连接池、学校限速或硬件满载。主代理此前已修复 LAN 与外层共用递增计数器形成的奇偶耦合，生产普通 policy 现为 `numgen random`。

先做下面的受限比较；每阶段保持相同目标、Range 大小与时段，检查 HTTP 206、下载字节数和总耗时。可复用 USTC／TUNA 官方 HTTPS ISO 的 16～32 MiB Range，避免下载完整镜像。两目标是对照来源，不视为保证足量带宽的标准测试端点。

| 顺序 | 请求路径 | 要观察什么 | 能定位的问题 |
| --- | --- | --- | --- |
| A | 路由器 → WAN1、WAN2，各自直连，不经 UA3F | 两路分别的稳定吞吐、RTT、错误、WAN 字节计数与认证心跳 | 上游目标／认证会话／单路容量；这不是转发或无线测试 |
| B | A 两路同时、各用独立请求，并确保明确绑定出口 | 同时总量与分别数值，心跳有无扰动 | 两会话是否有可叠加容量；同时变慢也可能是公共物理口、校园策略或目标瓶颈 |
| C | 路由器 → UA3F SOCKS → 同一目标 | 与 A 比较；UA3F 单线程、各核心 CPU、softirq、RSS、重传／错误 | UA3F 与本机路由成本；此路径的 WAN 选择必须实际确认 |
| D | LAN PC → OpenClash 直连 TCP 分支 → UA3F → 目标 | 与 C 比较，OpenClash CPU，WAN 分布；先有线后 WiFi | OpenClash 接管／二次转发成本，再区分无线路径 |
| E | LAN PC → 实际 Ninja 节点 → 目标 | 实际外层连接数、出 WAN、CPU、节点负载／协议 | 远端节点、隧道或复用限制；不能与裸校园出口直接等同 |

每次只改一个因素，记录配置摘要和时间，2～3 次短请求足以判断是否需要下一步；不要用短样本宣布稳定 700 Mbps。32 MiB 在 700 Mbps 约 0.38 秒即完成，握手、慢启动、进程调度会显著影响全程均值，短 Range 更适合相对定位。统计应标明是全程均值还是稳定区段，不能混用。WiFi 的 LAN 测试和公网 HTTPS 对照也不是同一测量口径。

如果 A/B 已低于目标且 CPU 低，先查上游与会话，不增加防检测插件。如果 A/B 足量而 C 降、UA3F 核心饱和，才查 UA3F 转发；如果 C 足量而 D 降，查 OpenClash／LAN；如果只有 E 降，查实际节点和隧道。DNS 返回更快不能解决已建立 TCP 的持续吞吐。

源：[OpenWrt mwan3：本机流量与 sticky 规则](https://openwrt.org/docs/guide-user/network/wan/multiwan/mwan3)、[Linux flowtable](https://www.kernel.org/doc/html/latest/networking/nf_flowtable.html)。普通 flowtable 面向 IP 转发；本地进程接收、重建的 TCP 不等于可卸载的贯通转发流。

## UA3F HTTP 连接复用与独立出站轮换

### 当前 SOCKS5 路径没有跨连接 HTTP 连接池

正式 v3.7.0 的 `socks5.handleConnect` 每收到一条 SOCKS CONNECT，都会调用 `base.Connect(destAddr, s.so_mark)`；Linux 实现新建 `net.Dialer` 并调用 `Dial("tcp", addr)`。新连接作为独立 `ConnLink.RConn` 传给 `ServeConnLink`。`ProcessLR` 解析 HTTP/1 请求后，直接 `c.Metadata.Request.Write(c.RConn)`；不会为请求挑选另一个共享上游 socket，也没有主动 HTTP/2 合并。`Accept` 后每个客户端由独立 goroutine 处理。

SOCKS5 的 `Cache` 是 512 项、30 分钟的非 HTTP 目标嗅探跳过集合，`BufioReaderPool` 只复用读缓冲，两者都不是 TCP 连接池。HTTP keep-alive 可以让同一条下游 TCP 上的连续请求继续使用其同一上游 TCP，但不同下游 TCP 不会被这条实现合成一条上游 TCP。因此，如果测试确为 8 个独立 curl 进程／TCP，请求同一个 URL 和 IP 不会由 UA3F 自动压成一个 TCP。若下载器复用一条下游 HTTP 连接，则本来就没有 8 次路由选择；应数实际连接，不能按任务数判断。

存在连接池的是 **server-mode=HTTP 的普通非 CONNECT 路径**：`http.handleHTTP` 调用 `http.DefaultTransport.RoundTrip(req)`，Go DefaultTransport 保留空闲连接并可尝试 HTTPS 的 HTTP/2。当前服务为 SOCKS5，并不调用这个函数。HTTP mode 的 CONNECT 路径则仍通过 `base.Connect` 单独建 TCP。不能因文件名有 HTTP 就把 HTTP mode 的池行为套到当前 SOCKS5，也不建议为这次测速切换 mode。

核验位置：[SOCKS5 handleConnect，213～240 行](https://github.com/SunBK201/UA3F/blob/v3.7.0/internal/server/socks5/socks5.go#L213)、[base.Connect，17～34 行](https://github.com/SunBK201/UA3F/blob/v3.7.0/internal/server/base/tcp_linux.go#L17)、[ProcessLR 的 Request.Write，270 行](https://github.com/SunBK201/UA3F/blob/v3.7.0/internal/server/base/server.go#L270)、[HTTP handleHTTP，122～146 行](https://github.com/SunBK201/UA3F/blob/v3.7.0/internal/server/http/http.go#L122)、[server mode 分派](https://github.com/SunBK201/UA3F/blob/v3.7.0/internal/server/server.go)、[Go DefaultTransport](https://github.com/golang/go/blob/go1.25.0/src/net/http/transport.go)。

v3.7.0 Config／CLI 没有可直接设置的 `DisableKeepAlives` 或关闭上游复用选项。最小可逆验证应在客户端进行：每个 Range 使用独立 curl 进程、强制 `--http1.1`、请求头 `Connection: close`，并给每条请求不同标识以便计数；不改 UA3F。`curl --no-keepalive` 关闭的是 TCP keepalive 探针，**不是 HTTP 连接复用**，不能用它验证此猜测。HTTP 明文下载也不会凭同一 URL 自动成为 HTTP/2 multiplex，除非实际客户端和服务协商／升级使用该协议。

### 更合适的最小修复：UA3F OUTPUT 使用独立 policy

主代理提出的专用 `ua3f_bal` 可以消除 LAN 与外层共享计数器，以及小样本 random 全偏一侧的风险。方案在静态审阅中成立，必须满足以下条件：

1. **用独立、等权为 1 的 IPv4 members。** 两成员同 metric、weight 各为 1，专用 policy 使用 `numgen inc mod 2`；LAN 和其他普通 policy 继续 random。若复用 weight 3／3 的 members，生成的是连续三次一侧再三次另一侧，任意 8 次可能 5:3，不能承诺 4:4。
2. **只匹配 UA3F 新建出站 socket。** 当前代码固定 `SO_MARK=0xc9`；SOCKS5 `New` 将 `s.so_mark` 设为该常量，`handleConnect` 将它交给拨号函数。当前方案可匹配 `meta nfproto ipv4`、MWAN 高位 `0x3f000000` 为 0、低 24 位 `0x00ffffff` 等于 `0xc9`。它不匹配 inject mark `0xc91`。但源码未检查 `SetsockoptInt` 返回错误，固定常量不等于每次实际设置成功，仍须读回实际 mark／链命中。
3. **保留 CT 恢复与内网绕过顺序。** 专用跳转在 `mwan3_output` 的 conntrack 恢复之后；保留 `ifaces_in`、custom／connected／dynamic 检查，再紧挨普通 `mwan3_rules` 之前放专用跳转。这样已分类流不重复轮换，校园／内网目的地先得到原有绕过。不要用不带范围的 0xc9 规则抢在这些检查之前强制平衡所有目的。
4. **只修改 MWAN mask。** policy 的 setter 用原来的 OR／mask 形式赋值，保留 low bits 的 `0xc9` 和其他未覆盖字段；conntrack 保存／恢复同样只改 `0x3f000000`。后续包先恢复已选 WAN，因此按连接固定，不按包轮换。专用 policy 不能被普通 rules 随后再次覆盖。
5. **由生成脚本与 health 事件持久维护。** `mwan3_set_policy` 只纳入当前 online、family 匹配且最低 metric 的 members。一条线下线后 policy 应变为剩余成员的直接 mark；两条都下线用 `last_resort unreachable`。专用跳转、policy 内容和目标 setter 应在同一批事务中建立，避免跳入尚空的 policy 后落到普通 rules。只临时插入内核规则会在 reload／事件重建后丢失，不能算修复完成。

一个普通 policy 只有一个 `numgen inc` expression；Linux 为每个 expression 单独分配 atomic counter。独立 UA3F policy 因而不会被 LAN policy 消耗计数。两线 online、等权 1、policy 不重建且没有其他匹配 UA3F 新连接插入时，连续 8 个实际新外层 TCP 会交替分到两路。UA3F 背景新连接、policy 重建和下载器重试都会影响这批请求的观察比例，所以仍需检查真实 5-tuple 和 mark。

故障回退只保证新连接选择仍 online 的出口。旧 TCP 连接不能迁移为另一源地址继续同一下载；失败 member 的 conntrack 可能被清理，应用应重试。它不是无缝连接迁移。两线都 offline 时 unreachable 的行为是显式失败，不静默绕至 main。当前两线在线并不意味着已建立 conntrack 的出口会自动重新均分。

如果 8 条全新、独立、等权 random 选择确实全落指定的 WAN2，理想独立抽样概率为 `1/256 ≈ 0.39%`；任意一侧全中的概率为 `1/128 ≈ 0.78%`。这个模型不能排除现有 conntrack、规则错位、计数器共享或样本选择偏差。先确认实际新外层连接数，再将它视作偶然，不能仅由下载字节计数证明 8/8 抽样。

最小验收应记录同一批 8 个独立短／中等 HTTP 请求：UA3F `New connection link` 数、目标和端口，出站连接的源地址／mark，两 WAN 分别字节数；观察专用 policy 的新连接计数以及 CT 后续包是否保持。完成后用同样的 8 × 128 MiB 方法比较分布与完成率，不按字节流量强求严格 50:50。一线状态变化的自动重建可用规则读回验证，实际断线行为再在受控窗口测试。本文没有执行该修复或验证。

参考：[Linux 6.18 numgen 独立 counter 实现](https://github.com/torvalds/linux/blob/v6.18/net/netfilter/nft_numgen.c)、[nftables load balancing](https://wiki.nftables.org/wiki-nftables/index.php/Load_balancing)、[curl no-keepalive 定义](https://github.com/curl/curl/blob/master/docs/cmdline-opts/no-keepalive.md)。mwan3 审阅依据为本任务 `mwan3-fixed.sh` 中 `mwan3_set_policy`、`mwan3_create_policies_nft` 与 `mwan3_output` 生成段；没有修改该公共脚本。

## socket BPF 是另一个候选，但先不部署

UA3F v3.7.0 有通用 `bpf-offload`／`--bpf-offload`／`UA3F_BPF_OFFLOAD`。它使用 `SOCKHASH`、`sk_skb` stream parser/verdict 在成对 TCP sockets 之间转发，与已退役的 `l3-rewrite.bpf-offload`／TC TTL 不同，也不调用 `parse_l2`。stock OpenWrt init 没导入这一开关，只设置同名 UCI 不能证明启用。内核版本足够也不证明所需配置、map、verifier 和 attach 成功。

这条源码尚有需要实测的生命周期问题：`TryOffload` 注释要求成功后等待 `OffloadDone` 且不再用户态 copy，但 `ConnLink` 不含该字段；调用方未根据返回值停止 copy，GLOBAL 的非 HTTP 缓存命中也不再次尝试 offload。这些是源码事实，不在没有运行证据时断言一定故障或一定无效。程序 map 各有 131072 个最大项，实际内存成本还需设备测量。

只有 C 段证实 CPU 瓶颈后，才考虑在限范围、可立即回退的独立实例中验证：开启日志、实际 offload 激活、首条与重复同目标 HTTPS、大小下载完整性、长连接、半关闭、关闭后清理和 WARN/ERROR。仍保持所有 L3 BPF 标志关闭。未通过这些检查，不把 socket BPF 改成常驻，更不承诺它能到 700 Mbps。

源：[通用 BPF flag/env](https://github.com/SunBK201/UA3F/blob/v3.7.0/cmd/root.go)、[sockmap 加载与 attach](https://github.com/SunBK201/UA3F/blob/v3.7.0/internal/bpf/sockmap/sockmap_linux.go)、[转发 BPF 程序](https://github.com/SunBK201/UA3F/blob/v3.7.0/internal/bpf/sockmap/sockmap.c)、[TryOffload](https://github.com/SunBK201/UA3F/blob/v3.7.0/internal/server/base/server_linux.go)、[调用路径](https://github.com/SunBK201/UA3F/blob/v3.7.0/internal/server/base/server.go)、[连接结构](https://github.com/SunBK201/UA3F/blob/v3.7.0/internal/common/connlink.go)、[stock init](https://github.com/SunBK201/UA3F/blob/v3.7.0/openwrt/files/ua3f.init)。

本次通过 Agent Reach 既有入口调用 Exa；它返回免费 MCP 配额限制，未改 API key 或配置。随后使用 Agent Reach 的 Jina Reader、本机现有代理、公开 GitHub API／raw 源码和网页读取完成核验。UA3F 固定在正式 v3.7.0；UA2F、rkp-ipid 状态为本次读取快照。本文提出的后续比较均未执行，不代表校园检测、700 Mbps、实际冷启动或新 BPF 功能已经通过。
