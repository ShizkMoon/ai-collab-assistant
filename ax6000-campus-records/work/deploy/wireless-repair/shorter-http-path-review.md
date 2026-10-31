# 复用 UA3F 缩短明文 HTTP 路径的只读审阅

结论：当前配置没有可复用的透明 HTTP listener。现有 `SOCKS5 + GLOBAL` 入口不能直接承接原始 HTTP；切换现有实例到 `REDIRECT` 会替换 SOCKS5 入口，而且默认透明规则不能保持 Ninja 的 DIRECT／香港代理选择。当前不建议把这条方案作为立即上线的修复。继续使用已经限定为自有 12 条 outer socket 的接收缓冲对照，更容易保持其他生产契约并解释结果。

本次只读范围为 `work/deploy/ua3f/`、已有 aggregation／esurfing 报告、UA3F 本地源码快照，以及 GitHub 固定提交 `e464514ab313e3afe308881d7e5732a5baf41ce2` 的 HTTP、REDIRECT 与 firewall 源码。没有连接设备、运行流量或修改生产配置。生产当前状态来自主代理读回；本地 `ua3f.baseline.conf` 是配置模板，其中 `enabled=0` 不能用作当前服务开关的证据。

## 当前入口与两种 DIRECT 的含义

本地模板配置为 `server_mode=SOCKS5`、`bind=127.0.0.1`、`port=1080`、`rewrite_mode=GLOBAL`、`ua=FFF`。`ServerMode` 决定入口协议，`RewriteMode` 决定连接内的处理。`GLOBAL` 不是另一个监听端口。`internal/server/server.go` 的 `NewServer()` 根据一个 `cfg.ServerMode` 返回一个 HTTP、SOCKS5、TPROXY、REDIRECT 或 NFQUEUE server；stock init 脚本只有一次 `procd_open_instance`，传入一个模式、端口和 bind。没有混合 listener 或第二个已有 REDIRECT 实例的配置证据。

Ninja 规则中的 DIRECT 是出站选择；UA3F 的 `RewriteModeDIRECT` 则直接复制数据，跳过普通 HTTP 改写。不能为了表达“明文 HTTP 直连”而把 UA3F 的改写模式改成 DIRECT。

SOCKS5 入口先读取 SOCKS methods，再读取 SOCKS request。成功 CONNECT 后，它通过带 mark 的 `base.Connect()` 建立 outer，并进入 `ServeConnLink()`。把原始 HTTP 用 nft redirect 导入当前 `127.0.0.1:1080` 不满足这个协议。只改变 Ninja 的 UA3F 出站协议仍保留 Ninja 接收 PC 连接、Ninja→UA3F loopback 和 UA3F outer 三段，不能达到本方案要删除中间一段的目标。

来源：[入口选择](https://github.com/SunBK201/UA3F/blob/e464514ab313e3afe308881d7e5732a5baf41ce2/internal/server/server.go)、[SOCKS5 入口](https://github.com/SunBK201/UA3F/blob/e464514ab313e3afe308881d7e5732a5baf41ce2/internal/server/socks5/socks5.go)、本地 `package-etc__init.d__ua3f`。

## REDIRECT 有基本能力，但不是当前可复用入口

固定源码中的 REDIRECT server 先安装透明 firewall，再监听 `0.0.0.0:<port>`；这条实现没有沿用配置的 `BindAddress`。它取 `SO_ORIGINAL_DST`，拒绝绕回本入口，通过 `base.Connect(originalDst, SO_MARK_C9)` 建立 outer，再进入同一个 `ServeConnLink()`。因此，这个模式具备“透明接收 TCP、带 C9 出站、处理明文 HTTP”的基础能力，但切换单个生产实例会替换 Ninja 仍使用的 SOCKS5 listener，并把监听面从回环改变为所有 IPv4 地址。

默认 nft PREROUTING NAT 链优先级为 `dstnat -20`。它过滤非 `br-lan`、非 TCP、reply、LAN／skip 地址、skip ports 和 C9 后，对其余 TCP 做 redirect。firewall 初始化的 skip ports 包含 `22,51080,51090`，并有若干 Steam CDN 跳过规则。它没有读 Ninja 的规则、DIRECT 决策或固定香港选择。默认范围也不限于明文 HTTP。

把这套透明规则直接装在 PC 入站路径，会在 Ninja 判断之前处理符合规则的流量。外国明文 HTTP 可以进入 UA3F 的 C9 直连，不能保持“仍由 Ninja 规则决定走香港”的要求。仅限制 `tcp dport 80`、国内 IP 或某个 CDN IP 也不能等价复现 Ninja 的域名／IP／规则顺序。共享 CDN 地址、DNS 变化和规则例外均会改变判断对象。

来源：[REDIRECT server](https://github.com/SunBK201/UA3F/blob/e464514ab313e3afe308881d7e5732a5baf41ce2/internal/server/redirect/redirect_linux.go)、[REDIRECT nft 规则](https://github.com/SunBK201/UA3F/blob/e464514ab313e3afe308881d7e5732a5baf41ce2/internal/server/redirect/nftables.go)、[firewall 默认值与安装](https://github.com/SunBK201/UA3F/blob/e464514ab313e3afe308881d7e5732a5baf41ce2/internal/netfilter/firewall.go)。

## HTTP 模式还有不同的 mark 路径

固定源码的 HTTP listener 对 CONNECT 通过 `base.Connect(req.Host, s.so_mark)` 建立外层连接；普通 HTTP 分支先改写 request，然后调用 `http.DefaultTransport.RoundTrip(req)`。在这个分支没有看到 `base.Connect()` 或为 Transport 显式配置 C9 的操作。不能把 CONNECT 的 C9 行为直接推到普通 HTTP 分支，也不能据此宣称普通 HTTP 已满足三路分流。

即便改成 HTTP listener，再让 Ninja 使用这个入口，依然保留 Ninja→UA3F 的 loopback 连接。如果让 PC 直接连接 UA3F，需要新的 LAN bind、访问限制和客户端流量选择；PC 的外国 HTTP 不会因此自动经过原有 Ninja 规则。这超出“复用当前生产配置、无需新实例和复杂策略”的条件。

来源：[HTTP listener 与两条处理分支](https://github.com/SunBK201/UA3F/blob/e464514ab313e3afe308881d7e5732a5baf41ce2/internal/server/http/http.go)。

## UA 连续改写与 TTL 契约

`ServeConnLink()` 的 GLOBAL 分支把客户端→服务器方向交给 `ProcessLR()`；常规 HTTP 路径循环读取 request、改写、写出，因此正常 keep-alive 上的后续 HTTP request 也会被处理。下载方向的复制与这条请求处理路径独立。

不过 GLOBAL 源码存在明确例外：空 UA、内置 UA whitelist，以及被远端地址缓存判为跳过处理的连接。whitelist 包括 MicroMessenger、部分 Bilibili、Steam、Go HTTP client 和 ByteDance PCDN 标识。不能仅凭 `GLOBAL + ua=FFF` 宣称任意 UA、任意连续请求都无例外变成 FFF。这是现有源码的行为边界；本次不建议为短路径临时更换改写模式或扩大改写政策。若验收要求确实是所有普通明文 HTTP 请求，必须把上述例外列入实际验收，不能用单个下载 request 代替。

现有 WAN TTL64 来自生产 nft 规则。启用 UA3F REDIRECT 不会自动证明这些规则仍位于新出站路径，也不能用 UA3F 的 L3 TTL 选项替代当前已验证的 nft 行为。C9 只能表达 socket mark；三路认证与出口分配还依赖现有 WAN／mwan 规则。原 esurfing 源码报告也将认证出站 mark 与其他应用出站区分，不能通过改 listener 假定所有生产 mark 契约仍成立。

来源：[连接处理](https://github.com/SunBK201/UA3F/blob/e464514ab313e3afe308881d7e5732a5baf41ce2/internal/server/base/server.go)、[GLOBAL 例外与缓存](https://github.com/SunBK201/UA3F/blob/e464514ab313e3afe308881d7e5732a5baf41ce2/internal/rewrite/global.go)、本地 `work/deploy/esurfing/three-channel-source-review.md`。

## 方案判断

| 候选动作 | 能否删除 Ninja→UA3F 段 | 当前条件与结论 |
| --- | --- | --- |
| 将原始 HTTP redirect 到现有 SOCKS5 1080 | 不能正确建立协议 | 拒绝；入口需要 SOCKS 握手。 |
| 用现有单实例改成 REDIRECT | 可以为被透明选择的流量缩短路径 | 替换现有 SOCKS 契约；默认规则提前直连流量，不能保持外国 HTTP 走 Ninja。当前不部署。 |
| 将 Ninja 的 UA3F 出站换成 HTTP | 不能 | 中间 loopback 仍存在；普通 HTTP 的 C9 还未证明。 |
| 在 PC 入站前仅截取“已知 DIRECT”HTTP | 原理上可以 | 需要独立、持续正确的选择机制，不能用目标 IP／80 端口代替 Ninja 决策。当前没有这项生产能力的证据。 |
| 让 Ninja 判断后，再把其 DIRECT socket 导入 UA3F | 通常不能 | 仍有 Ninja 自身 TCP 生命周期和到 UA3F 的连接；仅改握手不满足缩短目标。 |

没有当前现成入口同时满足“删掉 loopback 段、连续改写 UA、C9 三路、WAN TTL64、外国 HTTP 仍走固定香港”全部条件。若后续单独立项，应先定义 Ninja 决策如何无歧义地交给透明入口，再解决并存 listener、选择规则生命周期和完整验收；这需要新的策略或实现，不能作为当前接收缓冲试验的即时后备变更。

本次新增文件仅为本报告。未修改主线配置、源码、测试数据或其他报告。
