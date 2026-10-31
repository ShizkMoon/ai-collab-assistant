# CAKE 与 L4S 的有界评估方案

本支线只读取已有文件、官方资料和上游源码，没有 SSH、网络负载、安装或设备修改。主代理是唯一设备操作者。用户已授权评估 CAKE；L4S／DualPI2 只有形成实际收益证据才采用。本文件中的阈值是本轮操作判据，不是标准规定或已验证效果。

## 当前结论与必须保留的条件

先等主代理确定最终保留两路还是三路认证，再复核同路径满载延迟，决定是否临时试 CAKE。没有持续排队证据时保持 `noqueue`。本轮保持最终认证状态、DHCP、MWAN、Ninja 核心与协议、UA3F、逐包 TTL、HE160、RPS、ECN、MPTCP 和关闭的 offload／WED。不添加 autorate，不同时调整上传与下载，不在物理 `wan` 和任何 `eswan` macvlan 叠多个独立整形器。用户要求避免整机重启与长时间断网；原队列 A1 不改设备设置，不需要重启。

设备基线由主代理提供：RB06 stock，OpenWrt SNAPSHOT `r37185-f29dfe25ba`，Linux `6.18.55`；两个 DHCP 逻辑出口共用物理 `wan`，第二出口是 `eswan2` macvlan。当前两 WAN 为 `noqueue`，TCP `reno cubic`／`cubic`，`tcp_ecn=2`。当前空间与认证状态在操作前由主代理重新读回；本支线不把旧截图当现场值。

## 已有证据的适用范围

| 证据 | 已证明的结果 | 不能据此判断的事项 |
| --- | --- | --- |
| `loaded-latency-wan-1g-a1.json` | 16×64 MiB 完整下载，536.58 Mbps；总体 CPU 44.8%，最高整窗每核 60.3%。 | 多目标 `IcmpSendEcho` 的旧损包数字不可靠；整窗 CPU 平均不能排除瞬时单核饱和。 |
| `loaded-latency-wan-1g-sqm520-b.json` | 物理 WAN ingress→单 IFB，HTB 520 Mbps＋fq_codel；489.07 Mbps，总体 CPU 74.7%，cpu2 88.2%／softirq 64.0%。 | 旧自定义 ICMP 的延迟变化不是稳定收益验收；不能把 HTB 结果等同 CAKE。 |
| `loaded-latency-wan-1g-a2-native.json` | 撤回后 612.86 Mbps，总体 CPU 51.3%，最高整窗每核 60.7%；原生 ping 的公网 load median 为 14 ms、idle 为 9 ms，14 个 load 回复全成功。 | 原生样本少，P95 近最大值；这组结果没有证明严重下行 bufferbloat，也不是稳定日常速率。 |
| `microsoft-throughput-queue-a1/b/a2.json` | 吞吐 462.00／499.29／529.53 Mbps。 | B 是 32 个 32 MiB 请求、并行 16，A 是 16 个 64 MiB；不能把请求布局变化当纯队列 A/B。 |
| `router-upload-optimization.md` 与两个 `upload/*/result.json` | 12 个 POST 完整成功；单连接约 53～55 Mbps，并发约 55～59 Mbps；第二轮 1＋4 个请求匹配 HK02。原生公网 ICMP 未随上传持续升高。 | 未证明本地上传容量、双账号饱和或 HK02 内延迟；物理 WAN 与 macvlan 字节不能相加。 |
| `sqm-package-current.json`／`sqm-ifb-install.json` | 当时 `tc-full 6.18.0-r2` 和 `kmod-ifb 6.18.55-r1` 已安装，IFB 创建成功；试验停止记录恢复 `noqueue`。 | `sqm-cake-plan.json` 只有安装计划式输出，未显示执行 hook；不能当 CAKE 已安装证据。 |

旧 `trial_downlink_sqm.py` 可以参考保护与回退方式，但它硬编码 HTB＋fq_codel，不能直接作为 CAKE 开关。旧 `loaded_latency.py` 不适合直接复用验收：它硬编码 1 GiB、70 秒，并混合旧 IcmpSendEcho 与只识别英文的原生 ping。新观测应复用 `upload_probe.py` 的每目标独立 ping、Windows OEM 编码、中文／英文时间与失败行解析，并保留原始文本。`<1 ms` 是上界，不伪造为 0.5 ms 精确值。

## 已交付的原队列 A1 脚本

`work/deploy/frontier/queue_baseline.py` 只实现原队列 A1，不实现安装、队列修改或 B／A2。负责人在最终通道数与认证健康确定后从这台 Windows 电脑执行。它通过现有 `root/router.py` 做只读 SSH 观测；没有上传远端脚本、远端临时文件或凭据字面量。没有执行本机或路由器的真实验收；当前已完成 AST 解析、帮助入口与本地合成数据 self-check，后者网络请求和 router 调用均为 0。

```powershell
# 先在本地复核解析与边界；此命令没有网络或设备调用。
& 'C:/Users/Shizuku/scoop/persist/uv/tools/versions/agent-reach/Scripts/python.exe' -B 'C:/Users/Shizuku/Documents/Codex/2026-10-12/za/work/deploy/frontier/queue_baseline.py' --self-check

# 最终通道数为 3 时；保留 2 路则改为 --expected-wans 2。
& 'C:/Users/Shizuku/scoop/persist/uv/tools/versions/agent-reach/Scripts/python.exe' -B 'C:/Users/Shizuku/Documents/Codex/2026-10-12/za/work/deploy/frontier/queue_baseline.py' --label a1-final3 --expected-wans 3
```

未指定 `--server-ip` 时，脚本先做一个 1 KiB Range 请求，只有 HTTP 206、Content-Range、实际字节与固定请求相符才继续，并把首次 remote IPv4 固定到全部后续请求。可用 `--server-ip` 指定负责人已确认的 IPv4；不得因旧 IP 样本成功就默认仍有效。预检失败时只保存 `inconclusive`，不寻找新源、不重试、不开始 768 MiB 负载。

负载为 16×48 MiB，HTTP/1.1、`Connection: close`、30 秒每请求总超时、最多额外 3 秒进程清理、无重试／无重定向，payload 丢弃。前后分别观察 15 秒 idle 与 10 秒 recovery。同源延迟探针每秒至多一次、每次 1 KiB、最多 64 次；含预检最大额外 65 KiB，均使用新连接及相同 Range 校验。电脑原生 ping 各用独立进程、默认 1 Hz，保留原始 OEM 编码文本；不使用有争议的多目标 IcmpSendEcho。

每秒观测逐核 CPU／softirq、UA3F／Ninja 进程 CPU、softnet、qdisc、接口 RX、内存、boot ID、DHCP 与同源 conntrack。慢读不会密集补采，实际采样间隔和边界均留存。只安全识别 `wan`／`eswanN` 的 2～3 个 DHCP 出口，并要求设备与地址唯一。覆盖证据必须同时匹配下载的客户端 local_port、同源 conntrack 出口地址与对应 RX 增量至少 1 MiB；同源小探针和背景连接不冒充覆盖。透明代理改变外层端口时，缺少映射证据就报告不足。物理 WAN 包含 macvlan，单独保存计数；主出口只提供差额近似值，不把物理 WAN 与 macvlan 相加。

保护会停止脚本自身的 curl：DHCP／出口、boot ID 或原队列变化，连续三次设备读回失败，可用内存低于 64 MiB，或者最高每核 CPU ≥95% 持续三个近 1 秒观察窗。没有任何设备设置恢复命令；脚本只清理自己的 curl／ping 进程，保存原始 JSON。新的 label 对应新的结果文件，拒绝覆盖既有证据。

简短 stdout 仅给阶段与结果。完整记录写在 `work/deploy/frontier/queue-baseline-<label>.json`，不输出凭据；本地 JSON 含当前网络地址和公开响应头，仍只作为本地证据。`candidate_bufferbloat` 仅表示两桶同源 TTFB 持续增加至少 10 ms、恢复至 idle＋5 ms、采样与覆盖充分且没有明显 CPU 限制候选；并不等于已确认 CAKE 收益。`no_clear_bufferbloat_signal_in_this_sample` 只适用这个短窗口。缺少有效窗口、源／原生 ping 样本、任一活动出口覆盖、发生传输／观察失败，或延迟与 CPU 饱和同时出现，统一输出 `inconclusive`，退出码 2，不扩大量。保护终止若 curl 来不及输出字节指标，总字节是 reported 下界；硬上限由每请求 max-filesize 与无重试控制，不由 reported 数字倒推。

## 最小同路径下载对照

1. **只读保护与低流量路径探针。** 读回认证、DHCP、qdisc／ingress filter／IFB、内核 ABI、CAKE 模块、核心和 UCI 指纹。存在不属于本次试验的 ingress／根 qdisc／同名 IFB 时停止，不覆盖。保存完整原值与可独立执行的清理脚本；不靠“失败后再想办法恢复”。确认同一电脑、同一 HE160 连接、现有 Microsoft 下载 host、相同固定远端 IP、HTTP/1.1、相同 Range 布局、现有 DIRECT 链和两逻辑出口覆盖。
2. **A1：原队列。** 15 秒 idle；16 个并发、每个 48 MiB，合计上限 768 MiB；每请求 30 秒总超时、5 秒连接超时、无重试，丢弃 payload；完成后 10 秒 recovery。每阶段传输成功必须 HTTP 206、完整 Range 字节相符。持续每目标独立 1 Hz 原生 ping：网关与国内公网；另以同一下载远端的低流量响应测同路业务延迟，路径／chain 必须读回。公网 DNS IP 的 ICMP 只能代表其 DIRECT 路径，不能替代准确下载远端。若远端不响应 ICMP，可用小 Range 请求且限制每秒至多 1 次、单次 1 KiB、全试验最多 160 次；只在端点已确认遵守 Range 后使用，所有阶段采用相同建连方式。
3. **每秒同步采集。** `/proc/stat` 每核 busy／softirq 差值、UA3F／Ninja 进程 CPU、`softnet_stat` 的 dropped／time_squeeze、物理 WAN 与 macvlan RX delta、qdisc backlog／drops／marks／overlimits、可用内存与 Wi-Fi retry delta。相同采集脚本贯穿所有阶段；不采满量包、不改变 mark。流量覆盖以现场分类计数或匹配端口的 conntrack 为准；`eswan2` 和 `wan` 不相加。
4. **先按 A1 决定是否进入 B。** 把 load 首尾各 1 秒排除后，剩余有效稳态负载至少 10 秒，分两个完整的 5 秒桶看 median；小样本 P95 只展示。若同路径 load median 比本轮 idle 高至少 10 ms，且连续两个可用桶升高、停止后恢复至 idle median＋5 ms 内，才作为明确排队候选。单个高值、吞吐低、CPU 高都不是独立 bufferbloat 证据。768 MiB 在 600 Mbps 左右可能不足以产生这两个完整桶；此时如无更强的持续症状，只报告短窗口结果。若窗口不够、流量未覆盖两出口或端点受限，结论为范围不足，保持原队列，不自动扩大量。
5. **B：一个聚合下载 CAKE。** 仅 A1 通过上述门槛后，由主代理在物理 WAN ingress 重定向至一个新 IFB；IFB 根为 CAKE，不在 `eswan2` 再装第二控制器。初始速率为本轮 A1 稳态有效吞吐的约 90%，不用旧 612.86 Mbps 或 PHY 速率。候选最小选项为 `bandwidth R besteffort flows nonat ingress`，保留默认 ECN／split-gso，不引入 DSCP 改写、ack-filter 或 autorate；代理外层流的公平性不能写成内层设备公平性。必须通过 IFB／filter 包字节增长证明两逻辑出口确实进入该聚合点，不能只从命令成功推定 macvlan 覆盖。负载、远端、连接数、Range、观察方式与 A1 完全相同。
6. **A2：撤回并读回。** 清除仅本次新增 ingress／IFB，确认回到原队列及原策略，再重复同一有界负载。若 A1 与 A2 的稳态吞吐差超过 15%，或出口流量占比差超过 15 个百分点、远端／链／Wi-Fi 状态变化，这次 CAKE 比较无确定因果结论；不要择优展示其中一组。

A1－B－A2 最大下载 payload 为 2.25 GiB，三个 load 窗口；A1 未出现候选排队时只消耗 A1 的上限。它是短时功能实验，不承诺长期稳定；全部限额由主代理记录并遵守，不追加第一个失败请求的重试。

## 区分 CPU 与排队，及可选的唯一诊断补充

| 同窗模式 | 解释与动作 |
| --- | --- |
| 公网／同源业务延迟持续升高，网关稳定；每核有余量；结束后恢复 | 支持上游队列候选，可做 B；仍需 CAKE 的速率、backlog 与延迟共同证据。 |
| 网关和公网同时恶化；某核连续 ≥3 个 1 秒窗 busy ≥90%，并伴 softirq、time_squeeze 或处理进程占用高 | CPU／本地处理是候选，不能把所有变化归因上游队列。B 本身增加 CPU 的风险较高。 |
| B 的最高每核 busy ≥90% 持续 ≥3 秒，吞吐下降而同源延迟没有改善 | 临时 CAKE 不通过，立即撤回；这不能证明运营商没有队列。 |
| B 看起来有改善，但只因处理字节下降，CPU 也明显下降 | 最多加一个 **C**：恢复原队列，在客户端用每连接 `--limit-rate` 约束总流量至 B 的实测稳态 payload 速率，其他输入完全相同；不在路由器添加控制器。每秒实际 WAN／应用吞吐与 B 需在 ±10% 内，否则 C 无效。C 与 B 的延迟和 CPU 接近，说明降低负载已足以解释变化；B 仍明显优于 C，且 CPU 未饱和、队列命中准确，才增加 CAKE 算法收益依据。 |

C 是歧义出现后的诊断，最大再增加 768 MiB；全组最高 3 GiB。客户端节流不能保证与路由器整形有相同到达突发形状，所以 C 只是排除明显“降低负载即改善”的混杂，不能完全分离所有排队与 CPU 因果。若需要重复才能稳定判断，当前组先结束并写“不确定”，不自动继续循环。

**临时保持候选的门槛：** B 相比相邻有效 A 的同源 load median 增量至少降低 30%，且绝对降低至少 5 ms；网关 median 不增加超过 2 ms；吞吐至少保留有效 A 的 85%；无新增真实超时、认证／DNS／DIRECT／代理／UDP／UA3F／TTL 异常；每核保持余量，qdisc 的覆盖和整形速率被实际计数支持。缺少任何关键证据即恢复原队列。一次通过只支持短时可用，持久化前仍须功能读回与原值回退；不把它写成长期效果。

**即时停止并回退：** 认证或接口重建；主链／出口偏离；出现新且持续的业务失败；任一核 ≥95% 连续 3 秒且同步延迟恶化；MemAvailable <64 MiB；队列流量不命中、异常 runaway backlog、下载端点忽略 Range，或达到任何字节／时长上限。原有瞬时背景尖峰先按同窗证据判断，避免单个离群值引发全局改动。

## 上传：先修正路径测量，只有出现症状才试单个 egress CAKE

既有 53～59 Mbps HK02 样本不是两出口饱和上传容量。先保持原 egress，采用原 sink、相同 HK02／协议／端点；随机数据仅从本地新生成，4×20 MiB、20 秒请求超时、无重试，idle 15 秒、recovery 10 秒。并行记录同一 HK02 的小请求响应时间／链／外层出口及每秒 CPU；国内 ICMP 仍只作外部对照。单组最多 80 MiB，加低流量探针后仍记录实际字节。

若同代理路径延迟没有持续升高，上传到此结束，不装 qdisc。若确实升高而 CPU 有余量，先明确负载所在逻辑出口与上游瓶颈；仅一个代理外层出口的结果不外推为双认证满载。在物理 `wan` 上单个根 CAKE 作聚合 egress 试验，`eswan2` 保留原队列，初始速率来自本次有效基线；不按旧 59 Mbps 把全部上行永久限速。A1－B－A2 三轮 payload 最多 240 MiB，小请求探针总额 <16 MiB，总计 ≤256 MiB。动态 DHCP／出口重建即撤回。若无法覆盖或理解共享瓶颈，就保留原队列；不盲目给两个出口各设独立控制器。

聚合整形适用范围是已识别的共同瓶颈；若实际限制来自每账号的独立 policer，聚合 CAKE 未必能约束各账号内部排队。此情况需要另外设计分类，不在本最小实验里顺带添加。任何代理复用的外层带宽和 RTT 不等同内层每设备结果。

## 固定版本 DualPI2 可行性与端点门槛

已按主代理允许的网络只读范围核对：

- 固定 OpenWrt `f29dfe25baaa5c03f2b52f49dfdc12ed99abe8df` 的 `netsupport.mk` 有 `kmod-sched-dualpi2`，依赖 `kmod-sched-core`、排除 Linux 6.12；Linux v6.18 有 `sch_dualpi2.c`。
- 同提交 iproute2 是 `6.18.0-r2`；iproute2 v6.18.0 有 `tc/q_dualpi2.c` 与手册。历史 `sqm-package-current.json` 读回过该版本 `tc-full`。实际二进制解析与模块能力由主代理以后做无负载帮助／读回确认，不由源码替代。
- 精确 ABI 仓库 `6.18.55-1-b218d80d146ac6c85db4989df73b5de9` 本次 HTTP 200，列出 `kmod-sched-dualpi2-6.18.55-r1.apk`（7.9 KB）与 `kmod-sched-cake-6.18.55-r1.apk`（18.1 KB）。这是文件可得性，不是签名、完整依赖、安装、模块加载或运行验证；安装前需要内核 ABI 与签名读回，不能用滚动最新 kmod 顶替。

**当前不安装裸 DualPI2 模块。** 先有可控制或可实证的 L4S 发送端、准确拥塞反馈、端到端 ECT(1)／CE／反馈保留和经过本机队列的真实业务。在本实验保持 Ninja 协议及核心不变的条件下，没有证据说明既有外层隧道使用 Prague 兼容拥塞控制；内层应用声称支持 L4S、使用 QUIC，或 `tcp_ecn=2` 都不能证明外层可用。CAKE 与 DualPI2 都需要队列／瓶颈定位，DualPI2 本身不是带宽整形器，需要正确的上层 shaper。

采用前必须用 L-queue／C-queue 计数和端点遥测证明两类真实流量分类，不把全部 ECN 流量改进 L-queue；保留 `l4s_ect`，不凭猜测改成 `any_ect`。Linux／iproute2 源码明确：DCTCP 和 BBRv3 不满足完整 Prague 公网要求，只能在相应数据中心语境使用。即使两端普通 CUBIC 能运行于 C-queue，也不能把普通 AQM 效果报告成 L4S 收益。没有真实端点就交付“源码与包可行，业务条件未满足”，保持现状。

## 一手资料

- [固定 OpenWrt 队列模块](https://github.com/openwrt/openwrt/blob/f29dfe25baaa5c03f2b52f49dfdc12ed99abe8df/package/kernel/linux/modules/netsupport.mk)
- [固定 OpenWrt iproute2](https://github.com/openwrt/openwrt/blob/f29dfe25baaa5c03f2b52f49dfdc12ed99abe8df/package/network/utils/iproute2/Makefile)
- [iproute2 v6.18.0 DualPI2 解析](https://github.com/iproute2/iproute2/blob/v6.18.0/tc/q_dualpi2.c) 与 [手册](https://github.com/iproute2/iproute2/blob/v6.18.0/man/man8/tc-dualpi2.8)
- [Linux v6.18 DualPI2](https://github.com/torvalds/linux/blob/v6.18/net/sched/sch_dualpi2.c)
- [精确 ABI 仓库](https://downloads.openwrt.org/snapshots/targets/mediatek/filogic/kmods/6.18.55-1-b218d80d146ac6c85db4989df73b5de9/)
- [RFC 9330：L4S 架构](https://datatracker.ietf.org/doc/rfc9330/)、[RFC 9331：协议与 Prague 条件](https://datatracker.ietf.org/doc/rfc9331/)、[RFC 9332：双队列耦合 AQM](https://datatracker.ietf.org/doc/rfc9332/)
- [Linux v6.18 macvlan 下层发送](https://github.com/torvalds/linux/blob/v6.18/drivers/net/macvlan.c)、[Linux flowtable](https://docs.kernel.org/6.18/networking/nf_flowtable.html)

这些链接支持机制与版本判断；本机收益仍由上述同路径受控对照决定。
