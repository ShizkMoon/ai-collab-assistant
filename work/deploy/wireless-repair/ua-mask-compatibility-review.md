# UA-Mask 与 AX6000 当前链路的兼容性审阅

结论：指定主线提交与 v0.4.3 发布版都不适合直接替换当前 UA3F SOCKS5 服务。它们可以改写被 IPv4 REDIRECT 接管的明文 HTTP，但没有当前入口所需的 SOCKS5 协议，也没有 UA3F 出站 `SO_MARK=0xc9` 的契约。启用默认服务还会在 Ninja 规则判断前接管 LAN TCP。现有证据不足以支持“更适合本机性能修复”或“同参数替换后仍保留全部业务”的判断。

本次使用 Agent Reach 的 GitHub/gh 后端，仅下载和阅读公开固定源码；未登录设备、安装、运行二进制、改变规则或发送测试流量。源码缓存位于 `C:/Users/Shizuku/.agent-reach/research/ua-mask-firewall-83846d3`，主线和发布版分别存于 `main/`、`v0.4.3/`。报告同时沿用主代理的新鲜只读现场证据，不把源码推断当作运行结果。

## 核对对象与当前合同

| 对象 | 固定值或证据 |
| --- | --- |
| UA-Mask 主线 | `83846d3780b1e30f87816310ae75d95798a5bd4d` |
| v0.4.3 tag | `1e5a5ce38fc207136ba21a3f82a6a3e892a3c572`，发布于 2025-11-21 |
| 两者关系 | 主线领先 tag 两个提交：`5ba9694f36e68f4ee97836af90c9ad98aa9a65e1` 核心分层与配置重构；`83846d3…` 发布构建工作流。主线 `VERSION` 仍为 `0.4.3`，版本文字不足以识别具体实现 |
| 当前 OpenWrt | AX6000 RB06、`r37185-f29dfe25ba`、Linux 6.18.55 |
| 当前入口 | PC → Ninja SOCKS/Redir → 需要 UA 处理的分支 → `UA3FLocal`，SOCKS5 `127.0.0.1:1080`、`udp=false` → WAN |
| 当前 Ninja 状态 | `router_self_proxy=0`、`china_ip_route=0`；919 条 UA3F 规则全部有 `NETWORK,TCP` 条件；外网 HTTP 仍由 Ninja 决定是否走固定香港节点 |
| 当前进程 | UA3F 与 Ninja 实际 GID 都是 65534；三个认证 PID 为 7620／7679／9375，读回仍运行 |
| 当前出口 | UA3F 外层 C9 专用策略按新连接 round-robin；MWAN 高位 mask 为 `0x3f000000`，保留低位 C9；wan／eswan2／eswan3 的 nft IPv4 TTL64 规则都存在 |
| 当前性能环境 | WED=Y，已实际挂接并保存启动参数；下载 CAKE 仍为 650 Mbit；临时 host／buffer trial 已关；[保留验收](wed-retained-acceptance.json) |

现场来源：[ua-mask-current-context.json](ua-mask-current-context.json)。三路策略来源：[three-channel-review.md](../frontier/three-channel-review.md)、[adoption-results.md](../frontier/adoption-results.md)。固定上游关系可在 [compare](https://github.com/Zesuy/UA-Mask/compare/1e5a5ce38fc207136ba21a3f82a6a3e892a3c572...83846d3780b1e30f87816310ae75d95798a5bd4d)、[主线 VERSION](https://github.com/Zesuy/UA-Mask/blob/83846d3780b1e30f87816310ae75d95798a5bd4d/VERSION)、[v0.4.3 发布](https://github.com/Zesuy/UA-Mask/releases/tag/v0.4.3)复核。

## 入口、回环和真实规则顺序

主线运行装配只创建 `ingress.NewRedirect(cfg.Listen)`，没有按配置选择 SOCKS5、HTTP 代理或 TPROXY 的分支。REDIRECT 监听硬编码为 `0.0.0.0:<port>`，从 `SOL_IP/SO_ORIGINAL_DST` 读取 IPv4 原始目标；模型中也只有 `IngressKindRedirect`。文件名 `tproxy_linux.go`、CLI 帮助或 package description 使用 TPROXY 文字，不改变这个实际实现。[运行装配 app.go:157–162](https://github.com/Zesuy/UA-Mask/blob/83846d3780b1e30f87816310ae75d95798a5bd4d/core/internal/app/app.go#L157-L162)、[redirect.go:45–67、103](https://github.com/Zesuy/UA-Mask/blob/83846d3780b1e30f87816310ae75d95798a5bd4d/core/internal/ingress/redirect.go#L45-L67)、[IPv4 原始目标读取](https://github.com/Zesuy/UA-Mask/blob/83846d3780b1e30f87816310ae75d95798a5bd4d/core/internal/ingress/original_dst_linux.go#L23-L43)、[入口模型](https://github.com/Zesuy/UA-Mask/blob/83846d3780b1e30f87816310ae75d95798a5bd4d/core/internal/model/types.go#L15-L25)。

因此，把 Ninja 的 SOCKS5 节点端口改成 UA-Mask 端口，或让 UA-Mask 占据 1080，都不能完成 SOCKS5 协商和目标传递。普通本地 TCP 连接没有 REDIRECT 所需的原始外网目标；这也不是 HTTP CONNECT 代理入口。IPv6、UDP、QUIC 不是这套 ingress／nft 规则覆盖的路径。

| UA-Mask nft 部分 | 优先级与精确条件 | 对本机的含义 |
| --- | --- | --- |
| `UAmask_prerouting_before` | `type nat hook prerouting priority dstnat - 1`，即常规 dstnat 前一档；匹配配置 iifname 与 `ip protocol tcp`，再排除目的 IP、端口；最后 REDIRECT 到配置端口 | 默认 iif 是 br-lan，范围覆盖 LAN IPv4 TCP，未读取 Ninja 的域名、策略组、香港节点或 DIRECT 决策 |
| PREROUTING 动态绕过 | 在 REDIRECT 前匹配 `ip daddr . tcp dport @UAmask_bypass_set return` | 跳过本条 UA-Mask 链后，后面的正常规则仍可继续；并不表示绕过全部防火墙或自动走香港 |
| `UAmask_output_after` | 仅 `proxy_host=1` 时生成；`type nat hook output priority -100` | 名称中的 after 不代表位于本机全部 OUTPUT 规则之后 |
| OUTPUT 自回避 | IPv4 TCP，排除配置 IP／端口，并要求 `meta skgid != { bypass_gid, 65534 }` 才 REDIRECT；默认 bypass_gid=65533 | 当前 UA3F 与 Ninja 的实际 GID=65534，因此两个进程的出站都被排除，不能靠此链接在 Ninja 的 DIRECT socket 后完成 UA 处理 |
| 默认豁免 | 端口 22、443；地址 `172.16/12`、`192.168/16`、`127/8`、`169.254/16`；`proxy_host=0` | 保留回环连接不会把 SOCKS 链移交给 UA-Mask；默认地址名单没有 `10/8`、`100.64/10` 或本校园专用网段 |

规则来源：[主线 init:75–81、118–159](https://github.com/Zesuy/UA-Mask/blob/83846d3780b1e30f87816310ae75d95798a5bd4d/openwrt/root/etc/init.d/UAmask#L75-L159)、[默认 UCI](https://github.com/Zesuy/UA-Mask/blob/83846d3780b1e30f87816310ae75d95798a5bd4d/openwrt/root/etc/config/UAmask#L4-L15)。常规 dstnat 的数值为 -100，因此 UA-Mask 的 PREROUTING 为 -101；本机保存的 OpenClash 实现把 LAN TCP 跳转挂到 fw4 `dstnat`，见 [installed-openclash.init:1532](../../../docs/local-only-materials.md)。保存脚本反映接入实现，未来试验仍须读回实际 nft 规则顺序。

默认 UA-Mask 在 Ninja 接收到该 TCP 之前完成 REDIRECT，随后自身拨原始目标。外国明文 HTTP 也可能沿这个直连新 socket 出去，固定香港选择因而失去决策机会。只限 `tcp dport 80` 仍不能等价保留 Ninja 的域名／IP／例外规则。若关闭 LAN 接管再打开 proxy_host，当前 GID 65534 又会同时豁免 Ninja 与 UA3F，UA-Mask 很可能不处理原先需要它处理的目标流。删除这个 GID 豁免也没有得到“只接管 Ninja 已选 DIRECT”这一合同，并可能接管 Ninja 外层 TCP；不能以此作为修复。

本机目前 `china_ip_route=0`。按教程改成绕过中国大陆，会把 IP 旁路搬到 Ninja 决策之前，改变 919 条 TCP 包装规则所表达的业务范围。保持当前 Ninja 决策与执行该教程配置是两个不同方案。

## C9、三路认证与 TTL64

主线 `session/manager.go:126–130` 新建 `net.Dialer` 时只设 Timeout 和 KeepAlive，然后 `DialContext("tcp", accepted.Target.Address)`。没有设置 `Control`、`ControlContext`、`SO_MARK`、`SO_BINDTODEVICE`、源地址或上游代理。发布版 `src/server.go:100–104` 同样如此。接管前旧连接的 mark、GID、conntrack WAN 选择不会自动变成这个新 socket 的 C9 契约。[主线拨号](https://github.com/Zesuy/UA-Mask/blob/83846d3780b1e30f87816310ae75d95798a5bd4d/core/internal/session/manager.go#L126-L142)、[tag 拨号](https://github.com/Zesuy/UA-Mask/blob/1e5a5ce38fc207136ba21a3f82a6a3e892a3c572/src/server.go#L96-L110)。

主线配置只包含端口、超时、keepalive 等监听参数；没有可用的 fwmark、绑定地址或 SOCKS5 字段。JSON 解码还拒绝未知字段，不能靠添加一个未实现的 `mark` 配置获得功能。[config.go:21–28](https://github.com/Zesuy/UA-Mask/blob/83846d3780b1e30f87816310ae75d95798a5bd4d/core/internal/config/config.go#L21-L28)、[file.go:22–27、76–85](https://github.com/Zesuy/UA-Mask/blob/83846d3780b1e30f87816310ae75d95798a5bd4d/core/internal/config/file.go#L22-L27)。

当前 UA3F C9 专用分流靠低位 C9 命中，普通 balanced 用 random，新 UA3F 连接用 inc round-robin。一个无 C9 的 UA-Mask socket 即使偶然还能被普通策略分到三个出口，也不证明保留 `ua3f_bal` 的 round-robin。不得把三个 WAN 累计计数都增长或网页可访问当作这项合同通过。

认证规则在独立 `ip esurfing_route` 的 route OUTPUT -160 设置专用高位 mark，MWAN 保存／恢复只修改其 mask；它们与 UA-Mask -100 的 NAT OUTPUT 是不同阶段。proxy_host=0 时 UA-Mask 不接管认证自身 OUTPUT。proxy_host=1 时 UA-Mask 默认 GID 排除名单只含 65533／65534，没有三个认证专用 GID 65201／65202／65203；且默认 IP 排除不包含全部校园地址。符合条件的认证 TCP 可被重定向并由 UA-Mask 重拨，失去原进程的 GID pin。是否实际命中取决于认证端点与协议，源码足以否决未经端点范围审阅的全面 OUTPUT 试验；本报告没有断言三个现有会话已经受影响。[认证规则](../frontier/three-netifd-route.nft)、[UA-Mask OUTPUT 条件](https://github.com/Zesuy/UA-Mask/blob/83846d3780b1e30f87816310ae75d95798a5bd4d/openwrt/root/etc/init.d/UAmask#L145-L159)。

UA-Mask 本身没有 nft TTL、TC TTL 或 flowtable 设置。普通新建本机 socket 经实际选中的 WAN 发出时，原 nft POSTROUTING TTL64 可以继续作用；前提是三个原规则仍在，而且实际走正常软件 hook。源码没有保证安装／停止脚本重载 fw4 后全部自定义规则仍正确。保留现有 TTL include，继续关闭系统 flow offload；UA-Mask 的 target 绕过不等于系统 flowtable。当前 TTL 合同来自 [three-90-ua3f-wan-ttl.nft](../frontier/three-90-ua3f-wan-ttl.nft)和新鲜现场读回。

## 明文 HTTP 改写与“卸载”的边界

UA-Mask 能循环解析被接管连接上的明文 HTTP 请求，用 `Header.Set("User-Agent", …)` 改写，再 `request.Write()` 重发。默认是关键词模式；未命中关键词、普通精确 whitelist 或没有 UA 的请求会保留原值。若要保持“所有已有 UA 都改为 FFF”，必须明确选择 `all`、完整替换、空 whitelist，而不能只使用默认 keywords。没有 UA 的请求仍会跳过，不自动补一个 UA。[请求处理](https://github.com/Zesuy/UA-Mask/blob/83846d3780b1e30f87816310ae75d95798a5bd4d/core/internal/session/manager.go#L248-L330)、[改写入口](https://github.com/Zesuy/UA-Mask/blob/83846d3780b1e30f87816310ae75d95798a5bd4d/core/internal/rewrite/request_rewriter.go#L23-L63)、[改写条件顺序](https://github.com/Zesuy/UA-Mask/blob/83846d3780b1e30f87816310ae75d95798a5bd4d/core/internal/rewrite/engine.go#L24-L102)。

它有两种命名为 offload 的对象，不能合并为一个已实现的快路：

- **目标绕过**：目标以 `IPv4 地址＋TCP 端口` 为 key；非 HTTP 观察达到默认 5 次、延迟默认 60 秒且不在 HTTP 冷却期时，向 `inet fw4 UAmask_bypass_set` 添加元素。默认非 HTTP timeout 为 8 小时，HTTP 冷却 1 小时；Firewall UA whitelist 命中也能立即添加默认 24 小时元素。nft PREROUTING／OUTPUT 对这个 key 执行 return，使之后的新连接跳过 UA-Mask。[state key 与观察](https://github.com/Zesuy/UA-Mask/blob/83846d3780b1e30f87816310ae75d95798a5bd4d/core/internal/state/store.go#L192-L234)、[target 策略](https://github.com/Zesuy/UA-Mask/blob/83846d3780b1e30f87816310ae75d95798a5bd4d/core/internal/policy/evaluator.go#L86-L118)、[元素写入](https://github.com/Zesuy/UA-Mask/blob/83846d3780b1e30f87816310ae75d95798a5bd4d/core/internal/firewall/applier.go#L46-L60)。
- **单连接 offload**：实际运行装配注入 `NoopFlowOffloader`；该实现直接返回 nil。当前 session policy 对非 HTTP 和 HTTP 都返回 `SignalNoAction`。这些接口和统计事件不能证明 socket BPF、PPE、WED 或现有连接迁移已实现。[app.go:147–153](https://github.com/Zesuy/UA-Mask/blob/83846d3780b1e30f87816310ae75d95798a5bd4d/core/internal/app/app.go#L147-L153)、[空实现](https://github.com/Zesuy/UA-Mask/blob/83846d3780b1e30f87816310ae75d95798a5bd4d/core/internal/offload/target.go#L43-L45)、[session policy](https://github.com/Zesuy/UA-Mask/blob/83846d3780b1e30f87816310ae75d95798a5bd4d/core/internal/policy/evaluator.go#L22-L61)。

目标绕过集合不含客户端、Host、URL、Ninja 策略组或本次连接的 HTTP 状态。同一个地址＋端口上的其他客户端和以后 HTTP 连接也会命中；安装绕过之后，未再经过应用的请求不会产生 HTTP 冷却观察。main 的 HTTP 冷却／完成回执改善决策状态，不会把全目标集合变成逐 HTTP 请求的安全旁路。需要持续改写 HTTP 的本机试验应关闭非 HTTP target bypass、清空 firewall UA whitelist，并禁用 drop-on-match；不能用略过必要 UA 处理换来的吞吐宣称性能修复。

当前下载返回方向的主线代码是 `io.Copy(clientTCP, upstreamTCP)`，两侧保留真实 TCPConn；客户端方向解析 HTTP，非 HTTP 回退后才使用 `io.Copy`。这给直接 TCP copy 的优化路径提供了条件，但没有 AX6000 的运行吞吐或 CPU 证据，也没有 SOCKS5／C9 接入。不能从这一实现差异推出超过 UA3F 或达到 900 Mbps。[双向转发](https://github.com/Zesuy/UA-Mask/blob/83846d3780b1e30f87816310ae75d95798a5bd4d/core/internal/session/manager.go#L161-L176)、[回退](https://github.com/Zesuy/UA-Mask/blob/83846d3780b1e30f87816310ae75d95798a5bd4d/core/internal/session/manager.go#L394-L401)。

## init 和发布版的实际差异

默认 UCI 的 enabled 为 0。显式启动服务后，init 总会调用 `set_firewall`；`enable_firewall_set=0` 只取消动态集合能力，不取消 NAT 接管。主线还会创建私有 JSON、执行 `-check-config`、注册 procd respawn，然后添加 fw4 include、`uci commit firewall`、删除同名旧链并 `fw4 reload`；停止服务也修改 firewall UCI 并重载 fw4。它不是只启动一个无副作用 listener 的包装。[主线 start／stop](https://github.com/Zesuy/UA-Mask/blob/83846d3780b1e30f87816310ae75d95798a5bd4d/openwrt/root/etc/init.d/UAmask#L497-L539)、[include 与 reload](https://github.com/Zesuy/UA-Mask/blob/83846d3780b1e30f87816310ae75d95798a5bd4d/openwrt/root/etc/init.d/UAmask#L167-L176)、[停止时清理](https://github.com/Zesuy/UA-Mask/blob/83846d3780b1e30f87816310ae75d95798a5bd4d/openwrt/root/etc/init.d/UAmask#L41-L56)。

`fw4 reload` 的失败输出被丢弃，脚本随后仍记录 applied。集合创建失败时局部关闭规则的动态绕过，而 core JSON 已在前面生成。因此“服务 started／日志 applied”或核心 config check 通过，都不能替代实际 nft hooks、set 与外层 socket 读回。这是需要验证的启动合同，不是本次已发生的设备故障。[集合错误分支](https://github.com/Zesuy/UA-Mask/blob/83846d3780b1e30f87816310ae75d95798a5bd4d/openwrt/root/etc/init.d/UAmask#L118-L124)、[启动顺序](https://github.com/Zesuy/UA-Mask/blob/83846d3780b1e30f87816310ae75d95798a5bd4d/openwrt/root/etc/init.d/UAmask#L509-L531)。

本地逐函数比较得到：main 与 tag 的 `set_firewall_nft()`、`unset_firewall_nft()`、`set_firewall_ipt()`、`setup_group()` 内容完全相同；默认 UCI 文件也完全相同。主线主要把启动参数转换为 schema_version=1 JSON，增加 config 验证、受控 GC 与分层 session／policy／state／事件／退出生命周期。tag 使用旧 CLI flags 和合并的 FirewallSetManager，但同样是 IPv4 REDIRECT、普通无 C9 拨号和 IP＋端口绕过集合。改选发布版不会消除上述拓扑缺口。[tag nft 规则](https://github.com/Zesuy/UA-Mask/blob/1e5a5ce38fc207136ba21a3f82a6a3e892a3c572/files/UAmask.init#L124-L173)、[tag 目标决策](https://github.com/Zesuy/UA-Mask/blob/1e5a5ce38fc207136ba21a3f82a6a3e892a3c572/src/manager.go#L377-L397)。

两版包还都声明与 `ua3f-tproxy`、`ua3f-tproxy-ipt` 冲突。这只是包层面的冲突声明，不证明当前 SOCKS5 包兼容；实际包名需单独核对。未下载或安装 release asset；tag 源码和 release 资产同版本文字也不等于已验证二进制与源码一致。[主线 package:35–43](https://github.com/Zesuy/UA-Mask/blob/83846d3780b1e30f87816310ae75d95798a5bd4d/openwrt/package/Makefile#L35-L43)、[tag package:24–32](https://github.com/Zesuy/UA-Mask/blob/1e5a5ce38fc207136ba21a3f82a6a3e892a3c572/Makefile#L24-L32)。

## 最小安全试验形状与停止条件

**未经修改的 stock UA-Mask 没有已经满足全部本机合同的试验形状。** 本轮不安装、不改生产入口或持久规则。下一步若决定开发候选，应先在隔离 Linux 网络命名空间／虚拟网络验证 REDIRECT 原始目标、HTTP keepalive 和半关闭转发；验证用合成端点和独立规则，不触及校园认证。它只能验证 UA-Mask 自身，不证明 Ninja 兼容或本机性能。

能保持当前业务决策的后续候选应具备以下结构，而不是直接执行官方 init：

```text
无线 PC 的独立 canary 请求 → 现有 Ninja 规则决策
  ├─ 香港／其他代理：继续原 Ninja 节点
  ├─ 校园／认证：继续原固定直连及专用 pin
  └─ 原本需 UA 的 TCP 分支：候选本地 SOCKS5 ingress
       → UA-Mask HTTP engine → 明确 SO_MARK=C9 的新 socket
       → 原 ua3f_bal／三个 WAN → 原 nft POSTROUTING TTL64
```

这要求新增并验证真正 SOCKS5 ingress、可限定回环的监听、拨号前设置 C9 并检查失败；可把 UA-Mask 的改写与直接 TCP 返回 copy 思路用于候选实现。或者设计只接管“Ninja 已选 DIRECT”的 OUTPUT handoff，但前提是闭源 Ninja 能明确区分这类 socket、候选出站能设置 C9、原始目标不丢失、自回避可靠；当前源码和现场 GID 不能满足这个前提。后一方案不是靠删 GID 65534 豁免即可完成。

候选首先使用独立端口与可回退的 canary 路由，不占据生产 1080；禁用 stock init 的全面 PREROUTING／OUTPUT、target bypass、Firewall UA whitelist 和 drop-on-match，继续关闭系统 flow offload。生产 UA3F 以及三个认证实例保持原状。启用前须有主代理已验证的到期回退入口；本报告不生成可直接执行的 nft 改动。

进入设备 canary 的必要读回包括：当前 Ninja 固定香港选择与原规则数量；UA3F／Ninja／候选与认证 GID；候选新 socket `SO_MARK=0xc9`；新连接 conntrack 的 `0x010000c9／0x020000c9／0x030000c9`、实际 dev/src 与 RR 顺序；三个原认证会话仍在；实际出口 TTL64；同一 keepalive socket 的至少两次明文 HTTP UA 改写和完整正文；半关闭后完整收完且清理正确。任一项目缺失或改变就回退，不能继续按性能成功记账。

吞吐比较必须保留 Ninja 决策、UA、C9、TTL、相同整形和无线条件，使用同源、同并发、完整正文、相同运行窗口。当前仍有 650 Mbit 下载整形，性能验收要说明其作用接口和范围；若覆盖被测下载，900 Mbps 目标与这个同条件生产配置不相容。改变整形后的另一个样本不能称为同条件优胜；本次没有性能 A/B 结果。

## 阅读范围与验证边界

已阅读主线 OpenWrt init／默认 UCI／package、firewall executor／applier、redirect ingress／IPv4 original_dst、runtime 装配、listen／JSON 配置、session、rewrite、policy、state、offload coordinator／target；已阅读 tag init／UCI／package 及旧 `src` 的 config、main、manager、server、handler、tproxy。关键否定搜索式为 `SO_MARK|SO_BINDTODEVICE|routing.mark|fwmark|Dial|Control|socks|SOCKS|TPROXY|IP_TRANSPARENT|flowtable|ct mark|meta mark|ttl|esurfing`，范围是缓存的运行模块与 OpenWrt root。实际 socket 建立位置已经逐行核对；没有找到支持 C9 或 SOCKS5 的配置实现。README 兼容宣传不作为证据。

本报告只确立源码兼容条件和候选形状。没有编译、端到端功能验证、实际包级 TTL／mark 验证、CPU 评测或达到 900 Mbps 的证据。Agent Reach v1.5.0 的 check-update 本次返回已是最新版本。
