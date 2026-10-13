# 固定路径 CPU／TCP 限制与最小接收缓冲候选

**下一项有区分力的候选是：保持 BBR，仅对本次自有下载的 UA3F 外层接收 socket，临时把 `SO_RCVBUF` 请求值设为 1 MiB，并读回实际值。** 这是限制三段 TCP 的接收缓冲膨胀、减少总协议内存压力的单项辨别对照，还不是已验证的提速修复。当前证据不支持继续放大 Windows 窗口、增大全局 backlog、保留 CUBIC，或直接把全部差额归到无线 IRQ／UA 改写。

本报告只读本目录 `fixed-path-diag6-cases.json`、`fixed-path-cubic-cases.json`、`tcp-segments-diag6-summary.json`、采样／汇总源码及已有相关分析；另外核对已有 `../openwrt/tcp-mem-ab-note.md`，避免重复失败的全局预算试验。没有连接设备、运行设备脚本、创建新测速、安装或修改线上配置。唯一新增文件是本报告。主线已告知 BBR 和原运行配置已恢复；本报告不把这一消息当作独立设备读回。

## 完整数据与 CPU 证据

各组都是 12 × 64 MiB，768 MiB 完整正文，真实 UA3F 外层均为 `171.108.211.12:80`，三个出口均有 4 条新外层连接及接收增量。此前主线提供的 6 GiB／52 秒纯 LAN 994.91 Mbps 是另外一组容量证据，不与本表短窗当作同一测量。

| 组别 | 正文 Mbps | 全机 busy | softirq | 最忙核平均 busy | 核峰值 busy |
| --- | ---: | ---: | ---: | ---: | ---: |
| BBR，无线 A1 | 761.62 | 80.3% | 29.8% | CPU3，85.3% | 97.0% |
| BBR，本机 UA3F | 911.24 | 66.2% | 14.8% | CPU0，69.1% | 82.6% |
| BBR，无线 A2 | 802.15 | 80.5% | 29.5% | CPU3，85.8% | 93.7% |
| CUBIC，无线 A1 | 800.30 | 76.4% | 27.3% | CPU3，83.0% | 91.7% |
| CUBIC，本机 UA3F | 907.39 | 60.3% | 13.1% | CPU0，63.7% | 83.0% |
| CUBIC，无线 A2 | 719.38 | 78.8% | 27.6% | CPU3，86.0% | 92.8% |

BBR 无线 A1 的数据中段，全机 busy 为 87.8%～90.0%，CPU3 为 94.4%～97.0%；A2 中段全机为 85.8%～88.0%，CPU3 为 93.5%～93.7%。BBR 各核 softirq 平均 A1／A2：CPU0 7.1%／7.3%，CPU1 46.9%／44.3%，CPU2 41.4%／40.3%，CPU3 23.4%／25.3%。CPU3 的系统态同时为 58.8%／57.6%，不是单纯 softirq 独占。

`analyze_cpu_cost.py` 按首末 `/proc/PID/stat` 差分、以 USER_HZ=100 换算，得到下列占一个 CPU 的时间比；它们不是四核平均比，也不单独分配到某个 CPU。

| 组别 | UA3F 用户态／系统态 | Ninja 用户态／系统态 |
| --- | ---: | ---: |
| BBR，无线 A1 | 3.21%／32.28% | 8.62%／27.86% |
| BBR，本机 UA3F | 6.98%／41.04% | 11.83%／12.66% |
| BBR，无线 A2 | 3.40%／33.26% | 9.14%／25.07% |
| CUBIC，无线 A1 | 5.63%／34.00% | 7.39%／23.56% |
| CUBIC，本机 UA3F | 9.21%／40.01% | 2.36%／2.01% |
| CUBIC，无线 A2 | 4.13%／34.12% | 5.93%／21.83% |

采样窗口 8.45～9.44 秒，比 7.07～8.96 秒正文窗口更长。`fast_snapshot.py` 只保存 UA3F／Ninja 的 `/proc/PID/stat`，未保存 mt76／NAPI 各任务或各线程 affinity。本表因此不能把某核系统态全部归给 Ninja、UA3F、TX worker 或 NAPI，也不能声称未采样的任务 CPU 为零。本机组仍有 Ninja 后台工作，进程差额不是纯复制成本。高系统态和 softirq 是并行证据，下面的接收压力提供了更具体的候选。

## 接收丢弃和同窗内存压力

原 `tcp-segments-diag6-summary.json` 没有列出 `INET_DIAG_SKMEMINFO` 的 `drops_packets`。`tcp_diag_linux.go` 按第 9 个 uint32 解析该字段，字段顺序与缓存的结构一致。以下只取新 `socket_cookie`，同一 cookie 使用首次和末次可见快照；关闭之前或采样之前的变化可能漏掉，所以它是观测区间差分，不是完整生命周期最终计数。

| UA3F 的 CDN 接收端 | 首次 drops 合计 | 末次 drops 合计 | 已观察增长 | 单 socket rmem 峰值 | 实际 rcvbuf 范围 |
| --- | ---: | ---: | ---: | ---: | ---: |
| BBR，无线 A1，12 个 | 2,471 | 27,925 | 25,454 | 2,558,976 B | 3,608,099～3,910,688 B |
| BBR，本机，12 个 | 1 | 1 | 0 | 2,061,056 B | 3,910,688 B |
| BBR，无线 A2，12 个 | 0 | 30,209 | 30,209 | 3,072,256 B | 3,664,328～3,910,688 B |
| CUBIC，无线 A1，12 个 | 2,425 | 34,608 | 32,183 | 3,890,688 B | 3,910,688 B |
| CUBIC，本机，12 个 | 0 | 0 | 0 | 1,697,280 B | 3,400,167～3,910,688 B |
| CUBIC，无线 A2，12 个 | 3,432 | 60,719 | 57,287 | 3,512,064 B | 3,910,688 B |

BBR 无线外层接收的 `rcv_space` A1 为 324,264～1,321,128 B，A2 为 446,040～1,449,984 B；`rcv_ssthresh` 都曾降到 5,840 B，`rcv_wnd` 都曾降到 5,888 B。相邻本机组 `rcv_ssthresh` 为 1,266,507～1,327,543 B，`rcv_wnd` 为 784,128～1,323,392 B。CUBIC 仍有 `rcv_ssthresh=5,840 B`，无线 A1 窗口最低 768 B。接收吞吐差异伴随接收阈值和窗口收缩，不能只拿最大 rcvbuf 认定缓冲充分。

外层 BBR backlog 的已采样峰值均为 0；CUBIC A1 为 121,856 B。BBR 外层单 socket recv queue 峰值 A1／A2 为 161,424／451,704 B；本机为 511,176 B。rmem 是 skb 内存记账，recv queue 是排队字节，两者不是同一量，也不能把偶尔采样的低 queue 当作毫秒级峰值不存在。

| 全局 TCP 计数的首末同窗差分 | BBR 无线 A1 | BBR 本机 | BBR 无线 A2 | CUBIC 无线 A1 | CUBIC 本机 | CUBIC 无线 A2 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `TCPBacklogDrop` | 0 | 0 | 0 | 0 | 0 | 0 |
| `TCPRcvQDrop` | 55 | 0 | 37 | 45 | 0 | 65 |
| `PruneCalled` | 1,131 | 7 | 1,196 | 1,285 | 0 | 2,666 |
| `OfoPruned` | 51 | 0 | 58 | 71 | 0 | 104 |
| `TCPOFODrop` | 1,028 | 0 | 1,115 | 1,165 | 0 | 2,500 |
| `TCPMemoryPressures` | 10 | 0 | 11 | 12 | 0 | 21 |
| `TCPMemoryPressuresChrono` | 280 ms | 0 | 150 ms | 220 ms | 0 | 550 ms |

各组 softnet 每核 dropped 增长均为 0，time_squeeze 在 CPU2 增长 12～36；本机也有增长，没有支持扩大 `netdev_max_backlog`。BBR 无线 `MemAvailable` 已采样最低 A1 为 78,708 KiB，A2 为 76,204 KiB；本机为 118,836 KiB。CUBIC 无线最低为 69,712／70,836 KiB，本机为 125,432 KiB。不是系统完全耗尽内存，却与全局 TCP 预算压力同窗。

全局计数包含后台连接，不能全部归给这 12 条下载；自有新外层 cookie 的 drops 增长则把大量丢弃定位到 UA3F 的接收 socket。sk drops 不能直接当作物理网线丢包率，更不能直接除以正文包数。外层 `bytes_retrans=0` 只说明路由器本地 TCP 发送方向没有记录重传；下载发送端是 CDN，不能据此宣布 CDN→UA3F 下载方向无丢包。

## 三段 TCP 的方向必须分清

UA3F 的外层是 CDN→UA3F；UA3F 的 `127.0.0.1:1080` socket 是 loopback 下载发送端；Ninja 的 `127.0.0.1:ephemeral→1080` 才是 loopback 下载接收端；Ninja→Windows 又是一条独立 TCP。

原汇总 loopback 的 rcvbuf=131,072 B 是 UA3F 接收上行 HTTP 请求所用的缓冲，不能拿它说明 Ninja 接收下载正文只有 128 KiB。对已观察正文超过 1 MiB 的 12 条 BBR loopback 接收端重新取样：

| BBR 接收端 | 首次→末次 drops／增长 | 单 socket rmem 峰值 | rcvbuf 范围 | recv queue 峰值 | rcv_space 范围 | rcv_ssthresh 范围 | rcv_wnd 范围 |
| --- | --- | ---: | --- | ---: | --- | --- | --- |
| 无线 A1，Ninja loopback RX | 70→143／73 | 3,909,520 B | 1,057,425～3,910,688 B | 3,758,344 B | 334,176～1,229,088 B | 261,932～3,783,433 B | 640～3,773,312 B |
| 本机，helper loopback RX | 0→5／5 | 707,064 B | 343,437～3,910,688 B | 666,560 B | 107,616～1,020,936 B | 256,894～3,770,910 B | 256,896～3,771,008 B |
| 无线 A2，Ninja loopback RX | 1→49／48 | 1,067,880 B | 1,258,376～3,910,688 B | 1,025,184 B | 341,256～1,274,400 B | 261,932～3,782,062 B | 523,904～3,773,312 B |

这些 loopback RX 的已采样 backlog 峰值均为 0。CUBIC 无线 A2 的 loopback RX 还有 rmem=3,901,392 B／rcvbuf=3,910,688 B、recv queue=3,721,248 B、rcv_wnd=0 的观测。无线链后段背压能向前传递；扩大外层接收缓冲有可能增加持有时间和总内存，未必提高消费速度。

Ninja→Windows 发送端 BBR A2 的 rwnd limited 为 0.0368%、sndbuf limited 为 0.1842%，没有已观察发送重传／RTO；A1 为 0.8818%／0.1796%，有 3,611,082 B、2,549 段发送重传和 4 RTO。不能把 A2 的零重传扩大到全部样本。Windows 接收端本机 socket 内存未直接采集；Ninja listener 的 rcvbuf=131,072 B 是 HTTP 请求方向，也不是 Windows 下载接收缓冲。

## 唯一下一候选：仅自有 outer 的固定 1 MiB SO_RCVBUF 请求

先用主线已有 helper 路线确认 `pidfd_getfd` 的最小可用性；报告没有要求安装工具、绕过 ptrace／seccomp 限制或扩大系统权限。若可用，候选边界如下：

1. 只选择本次自有 12 条 UA3F outer：固定 owner PID 和 starttime、新 cookie／inode、peer `171.108.211.12:80`、这轮指定连接建立窗口及已验证三出口。`pidfd_getfd` 之后再次读取 socket cookie、local／peer tuple，防止 fd 复用。如果无法确定属于本次请求，不设值。不能操作香港、认证或其他后台 socket。
2. 尽量在 SOCKS CONNECT 已成功、HTTP GET 尚未发送时加一道主线自有门闩，完成 12 个 socket 的识别和设置，再统一释放正文请求。候选 `setsockopt(SOL_SOCKET,SO_RCVBUF,1,048,576)`；Linux 通常双倍记账，必须逐 socket 读回 `getsockopt` 和 INET_DIAG，预期 `rcvbuf=2,097,152 B`。不能仅看 syscall 成功。
3. 这一值低于当前已增长到约 3.73 MiB 的实际 rcvbuf，目的在于减少接收总量竞争。目标 900 Mbps／12 流、outer RTT 约 17 ms，对应每流 BDP 约 159,375 B；2 MiB 记账预算有明显余量，但 skb 开销、乱序和瞬时流量不均使这个估算不能保证窗口充分。因此作为一次有边界的辨别对照，不能先持久部署。
4. 不在已持有超过 2 MiB rmem 的运行中途突然降低限额；既有已通告窗口可能不能立即收缩，瞬时裁剪会污染对照。若不能在正文前设置，就暂不执行这项小缓冲候选。不同时改 `TCP_WINDOW_CLAMP`、`SO_RCVLOWAT`、tcp_mem、tcp_rmem、send buffer、算法、steering、IRQ 或 AQL。
5. duplicated fd 必须只读必要属性、设这一项并 `close`；不 `read` 消费正文、不 `shutdown`、不改变共享 file status flags。dup 关闭不会自动恢复 SO_RCVBUF；应用显式设置会锁住 autotune，写回旧数值也不能宣称恢复自动调节。正确回退是主线终止并确认本次 12 条测试 socket 已全部退出，下一组全新 socket 沿原程序和默认配置重建；不能靠服务重启回退。
6. 在原 BBR、固定 outer、相同 12×64 MiB 及完整字节条件下，记录设置前后、新 socket 全部实际值，按 cookie 采 drops 初末增量、rcv_wnd／ssthresh、rmem／队列、全局 Prune／OFO／RcvQDrop／pressure、MemAvailable 及正文吞吐。所有设值要在开始计时前完成，避免 attach 或门闩等待计入正文速度。

保留门槛是正文全部成功，吞吐收益超过相邻原态波动，接收压力同时减轻，且三认证、UA=FFF、TTL64、固定香港与原业务读回均正常；只有计数改善不能叫提速。若吞吐不增或下降、受限窗口恶化、新重传／超时增加或 MemAvailable 明显异常，立即结束自有 socket 并恢复默认新连接。一次成功还不能证明长时稳定 900。

可执行的停止阈值应在主线脚本中明确：任一请求不完整、socket 识别或 2,097,152 B 读回失败即不开始正文；`MemAvailable` 连续两次采样低于 64 MiB，或新 allocation failure／OOM／认证 PID 变化即停止。这是本次临时试验的保守操作阈值，不是内核进入 TCP 压力的判据。完整原态已见最低约 74.4 MiB，因此候选不应把更低可用内存当作可接受收益。若 12 流中的 outer 广告窗口反复低于 64 KiB，同时吞吐下降或 drops 增长高于邻近原态，应结束这项候选；只以单次瞬时窗口低值不能认定失败，因为当前原态本身已有更低瞬时值。

选择缩小而不是增大接收缓冲的依据是现有 outer 已达约 3.73 MiB、loopback 也可达同一限额，同窗出现全局 TCP 内存压力；不是单条外网 socket 一直撞上小默认缓冲。已有 `tcp-mem-ab-note.md` 显示把全局预算从约 22.37／29.84／44.74 MiB 增到 32／64／96 MiB 减少裁剪，却使完整正文由 547.69 降到 470.74 Mbps，恢复后 547.30 Mbps。这是另一套较早 16 流负载，不能直接替代本轮，但足以否决“只增预算必然修复”的重复动作。

若 1 MiB 请求反而显著增大 outer 丢弃或降低速度，说明这个限制不足或前级缓冲不是首个可减少成本的位置；恢复新连接后，应由主线依据同窗数据再判断，不直接扩到 4 MiB 请求／8 MiB 记账。当前没有支持 8 MiB 接收预算的结果。

## 不支持的归因与部署

- CUBIC 无线两组 800.30／719.38 Mbps，没有稳定改善；较低平均 CPU 不能代替吞吐收益。
- outer 接收 socket 报告的算法是路由器该 socket 的本地发送算法，不能据此证明 CDN 的下载发送端也切成 CUBIC。本次算法对照最直接改变的是路由器的 loopback 和 WLAN 下载发送腿。
- Windows 下载窗口不是当前首选原因：BBR A2 发送端几乎没有 rwnd／sndbuf 受限，纯 LAN 已有接近千兆的完整长窗证据；不会因此新增 RSS 注册表键或关自动调节。
- softnet dropped 和 TCPBacklogDrop 增量都为 0，不支持增大 netdev backlog。
- CPU 峰值与实际接收内存压力同窗，但未取得各线程热点、syscall 字节或 stack profiling，不能把全部系统态算作 UA 改写、memcpy、NAPI 或 IRQ。
- 已有 UA3F 与固定上游 Ninja 源码都有 splice 路径；普通包装可拆。没有运行证据支持新增 YAML 零拷贝开关、关闭统计或替换核心。
- 直接双向 sockmap 会影响 HTTP 后续 UA 处理；单向 sockmap 仍需 EOF、背压和生命周期屏障。它不是本次低影响修复开关。
- WED 需要重建无线设备，且存在 Ethernet DMA／认证约束的运行前提，不是这项 receive-buffer 对照的附带动作。

本报告把候选收敛到自有外层接收内存，仍保留“后段消费／调度导致前段背压”和“总协议内存预算导致裁剪”两种可能。运行对照的作用是区分并寻找可保留收益，不提前宣布唯一根因。
