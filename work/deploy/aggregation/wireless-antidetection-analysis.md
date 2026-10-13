# 无线 PC 与本地防检测处理：现有证据和最小辨别方案

用户要求 PC 保持无线连接。本分析不把改用有线、关闭认证、关闭 UA3F / TTL 或开启未经验证的卸载作为测试前提。只读已有完整测量与保存源码；没有 SSH、设备操作或生产修改。

## 当前判断

三路聚合确实有收益，选定快端点的路由器本机路径能超过 900 Mbps。无线 PC 的 162～353 Mbps 目前由不同 CDN、完整代理链、本地 CPU / softirq 和无线处理共同影响，尚未唯一定位。现有证据不支持“学校识别了无线 PC，所以固定限速”，也不支持“无线网卡只能到两三百 Mbps”。必须区分学校服务端的策略限制与为了保持当前防检测路径而产生的本地处理成本。

| 现有完整结果 | 可排除或支持的范围 | 剩余限制 |
| --- | --- | --- |
| 同端点 `171.108.211.12`，裸单 / 双 / 三 / 单 330.89 / 611.24 / 921.67 / 348.43 Mbps | 固定总 12 并发且真实出口为 12、6/6、4/4/4、12，证明本次聚合有用；不是三份地址的名义相加 | 768 MiB 约 7～19 秒；不证明全天或所有来源 |
| 本机 UA3F 902.30，紧接裸三路 908.67 Mbps | 同数字 SOCKS 目标、同源、同 12 并发 / 768 MiB；排除“UA3F、TTL、关闭卸载把所有路径普遍压在 162～353 Mbps”的解释 | 本机 UA3F 不含无线、OpenClash 入站及它们的 CPU 竞争；约 7 秒不证明持续 900 |
| 本机 UA3F 整机平均 busy 57.5%，裸重复 33.7% | 吞吐接近时，本地代理路径出现更多 CPU 工作的信号 | 时间仍有差异，不能将 23.8 个百分点全部归为 UA 字段替换，或把 CPU 百分比换算成确定的限速幅度 |
| PC 352.73 Mbps 组 CPU2 平均 busy 96.4%、softirq 89.9%；最新 PC 213.50 Mbps 组整机平均 67.6%，瞬时单核最高 98.7% | 完整 PC 路径存在局部处理压力信号；整机平均不满不能排除单核瓶颈 | 未取足够线程 / 中断关联，不能唯一指向 UA3F、Clash、无线驱动或 RPS |
| 另一实际 CDN `111.2.112.12` 裸三路 146.25 Mbps，整机平均 busy 18.2% | 学校之外的源站 / 网络路径差异可以在 CPU 有余量时产生低速；PC 内层 resolve 不固定 outer 是重大混杂 | 不能区分该 CDN、路由、对源 IP 的服务器策略或校园链路策略 |
| 当前 RAM HTTP → 无线 PC 完整 512 MiB：567.06 / 600.71 / 605.33 Mbps | 当前无线 LAN 路径已有高于 PC 公网下载的能力；学校公网识别不是这个纯 LAN 样本低于 900 的必要原因 | 包含 uhttpd、本机 TCP 和无线；1 / 2 并发约 7 秒，不是无线硬上限。历史默认 AQL 的 868.70 / 886.32 Mbps 也证明状态会变化 |

以上原结果分别位于 `controlled-cases.json`、`ua3f-layer-cases.json`、`endpoint-controlled-cases.json`、`pc-actual-cases.json`、`lan-current.json`；均在本目录。`results.md` 汇总了全部完整批次，失败或截断预检没有作为完整覆盖证据。

从 `lan-current.json` 的 before / after `/proc/stat` 重新计算：三个 LAN 批次整机平均 busy 19.3 / 23.1 / 26.5%，平均最忙核 42.6 / 52.6 / 50.4%。这些平均值未显示整机或单核持续满载，但缺少 uhttpd 线程采样、1 秒核负载及无线重试增量，不能排除短暂 CPU、驱动排队或服务器限制。

## 防检测措施分别在哪里

| 措施 | 实际层与作用 | 本地成本和比较边界 |
| --- | --- | --- |
| UA3F SOCKS5 重建 TCP | SOCKS 请求 → 路由器新建目标 TCP，设置 SO_MARK `0xc9`，再转发应用字节。选定上游连接使用路由器 TCP 栈 | 有额外 TCP leg、socket、缓冲、调度和转发工作。PC 再经过 OpenClash 时还有额外本地 leg；路由器本机 UA3F 测试只覆盖其中一段。SO_MARK 是路由选择，不是 HTTP UA 重写 |
| 明文 HTTP UA 改写 | GLOBAL 模式解析客户端 HTTP Request，对可改写 UA 执行动作，再写入既有上游连接 | 解析 / 写入 / 日志会消耗 CPU，但不能把所有下载正文描述为“逐包做 UA 替换”。GLOBAL 模式的下行走 CopyRL；具体内核拷贝 / splice 路径需要进一步实现与运行证据。HTTP 快样本不能外推 TLS、QUIC 或所有应用 |
| 独立 nft TTL64 | inet postrouting priority mangle；三个指定出口、IPv4 TTL≥10 改为 64，保留低 TTL 诊断 | 内核规则匹配和字段改写；当前不是把所有包送进 UA3F NFQUEUE 做 TTL。裸 router 与本机 UA3F 都保留此出口规则，因此它不是现有快 / 慢样本间被单独切换的变量。未量化它的独立成本 |
| 关闭软件 / 硬件 flow offload | 保留普通 netfilter / forwarding 路径，避免当前 postrouting TTL 被 fast path 绕过 | 可能增加转发处理，但本地终止再创建的代理 TCP 不是普通端到端 FORWARD 流，不能假定开启 flowtable 就会加速 UA3F / Clash。router local 快样本没有充分覆盖无线 LAN 转发成本 |
| 关闭 WED | 保持既有无线卸载兼容基线；WED 与软件 flowtable、PPE 硬件卸载、UA3F L3 TC、socket sockmap 都是不同机制 | 可能增加无线数据处理成本；本机下载不使用无线，所以 >900 不能排除关闭 WED 与无线 / CPU 竞争有关。当前没有保持字段覆盖的 WED 对照，不能承诺打开即提速 |

源码位置：[socks5.go:213](../../../docs/local-only-materials.md) 是先 Connect 后 ServeConnLink；[tcp_linux.go:17](../../../docs/local-only-materials.md) 是 mark / Dial；[server.go:67](../../../docs/local-only-materials.md) 是 GLOBAL / RULE 的复制分支，第 232～270 行是 HTTP 解析和 Request.Write。

UA 动作位于 `work/research/sharing/ua3f/internal__rewrite__global.go` 第 24～72、122～126 行；独立三出口 TTL 规则位于 `../frontier/three-90-ua3f-wan-ttl.nft` 第 3～7 行。`work/research/phase2/ua3f-integration.md` 第 78～80 行区分各类卸载及 flowtable 覆盖风险；`work/research/network-layers-antidetection.md` 是较早的机制和字段覆盖报告，不能用其中两出口旧快照代替当前三出口状态。设备当前开关应由唯一操作方读回，本报告没有新实机读回。

UA3F 的 socket sockmap 另有 `work/research/sharing/ua3f/internal__server__base__server_linux.go`，TryOffload 在 Sockmap 为 nil 时返回 false。源码具备能力并不说明当前开启，也不代表 HTTP 改写可被任意卸载保留。本轮不把它作为可直接打开的提速选项。

## 保留无线和防检测的最小辨别测试

每组只运行自有流量，保持认证 PID、UA3F UA 设置、三出口 TTL、当前 offload / WED 状态和无线连接不变。根代理若测试 900 目标，可临时停下载 CAKE 并在 finally / 独立回退定时器恢复 650Mbit；不能在当前公共 650 上限下把达不到 900 解释成检测。除明确的双负载实验外，每组顺序运行。

1. **先复用纯无线 LAN 参照。** 同一 PC、位置、频段与时间窗口，用独占 RAM 文件 / 已有 uhttpd 方法，以 2 条与 12 条相同总字节测试一次，≤768 MiB / 30 秒；读取 uhttpd 与客户端 CPU、每核 1 秒 busy / softirq、PC/AP 重试与失败的增量、发送持续时间和有效正文。不使用 PHY 2,402 Mbps 或累计重试总数代替本轮有效容量。若并发变化改善明显，先检查本地源服务 / 调度；如果 LAN 仍低，能定位到纯 LAN 路径，但不能直接归罪无线硬件。
2. **单独量化 OpenClash 增量。** 在路由器本机先做数字目标 UA3F 小预检，再通过当前 OpenClash 已有入站和 UA3FLocal 分支做同端点小预检。仅在真实 UA3F outer 都固定为同一数字 IP、HTTP Host 保留、相同三路分配时，才对同源 / 总 12 并发做≤768 MiB / 30 秒的临近 A/B/A；认证和 UA3F / TTL 全程保留。代理认证复用现有安全调用，不打印凭据。若 sniffer / DNS metadata 再次改变 outer，则该组不成立，不用不同 CDN 的差额指认 OpenClash。即便此组很快，也不能排除它与无线发送同时工作时竞争。
3. **只有前两步仍无法定位时，做一次有界资源竞争实验。** 先测 RAM→无线 PC；再在相同 RAM→无线负载期间，加入路由器本机→UA3F→已验证快端点的自有下载，限 256 MiB / 15 秒，总组≤30 秒。保持所有防检测措施，不让公网正文进入 PC；比较纯 LAN 的有效速度与每核 / softirq / 进程增量。若本地无线正文同步下降而处理压力增长，证明共享资源竞争可以造成降速，学校不需要识别该 LAN 流量。若不下降，只排除这个测试负载下的竞争，不证明 PC 完整链没有瓶颈。连续 3 秒单核≥95%、管理 / 业务异常就结束自有负载并恢复队列，不追求压死路由器。

PC 完整链的复核必须通过 UA3F inode → TCP outer → conntrack / SNAT 读回真实端点和三路字节；内层 `--resolve` 和 PC local_port 仍不能代替它。尽量紧邻固定快端点的本机 UA3F 结果，保留相同并发和正文区间。若不能固定 PC outer，应报告“当前 CDN 与本地链路共同受限”，而不是宣布学校检测、关闭防检测或再加账号。

这些测试能定位本地服务、OpenClash 增量和共享 CPU / 无线资源竞争，不能独立证明学校使用了何种识别策略。只有在本地资源有余量、真实端点 / 时间 / 出口匹配、反复呈现稳定策略边界，并有学校规则、提示或其他直接证据时，才能提高学校限速假设的可信度；现有结果尚未满足。

## 交付限制

所有公网快结果是短完整批次，不是无线 PC 稳定 900。无线必须保留，原有“有线参照”建议不适用于这次用户要求。下一步是上述有边界的无线分层，不能因一次 PHY 或 LAN 数字宣布硬上限，也不能以 router UA3F 快就否定所有本地防检测路径成本。
