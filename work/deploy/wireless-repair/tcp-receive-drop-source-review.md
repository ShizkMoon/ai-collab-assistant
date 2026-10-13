# UA3F 外层接收丢弃：来源与本机证据

当前证据支持“无线电脑完整代理链出现 TCP 接收内存压力与背压”，仍未确定唯一瓶颈。UA3F 外层 socket 的丢弃增长是真实观测；它不能直接解释为物理线路丢包率，也不足以认定 UA3F 有特定代码缺陷。

## 对应内核的含义

本机为 Linux 6.18.55，以下使用对应 tag；固定 commit 为 `725bd2f3c81d54edccb66fead01d4c0c222e2231`。网页搜索与 Agent Reach 的 GitHub／gh 后端用于原始来源核对，没有把旧版本 UA3F 用户投诉当作本机原因。

| 观测项 | 对应源码含义 | 不能据此认定 |
| --- | --- | --- |
| socket `drops` | `tcp_drop_reason()` 更新 socket 丢弃统计；内存不足、旧数据、窗口外数据和部分乱序重复／合并均可进入该路径 | 全部是缓冲耗尽，或可直接除以正文包数得到线路丢包率 |
| `PruneCalled` | TCP 尝试减少该 socket 的接收内存占用；会尝试压缩队列，必要时裁剪乱序队列 | 每次尝试都已经丢包 |
| `TCPOFODrop` | 乱序数据接收内存调度失败后丢弃 | 所有网络乱序都是线路故障 |
| `TCPRcvQDrop` | 顺序接收路径内存调度失败，且已有接收队列及有效载荷时丢弃；同文件另有 receive-queue 注入分支 | 独立于其他计数的总损失率 |
| `TCPMemoryPressures` | TCP 从非压力状态进入压力状态的次数 | 系统 OOM 次数、内存耗尽次数或丢包数 |

对应原始来源：[Linux 6.18.55 TCP 接收实现](https://github.com/gregkh/linux/blob/725bd2f3c81d54edccb66fead01d4c0c222e2231/net/ipv4/tcp_input.c)、[TCP 压力状态计数](https://github.com/gregkh/linux/blob/725bd2f3c81d54edccb66fead01d4c0c222e2231/net/ipv4/tcp.c)、[官方 prune 说明](https://docs.kernel.org/6.18/networking/snmp_counter.html#prune)。

`tcp_mem` 按页规定所有 TCP socket 的内存预算，`tcp_rmem[2]` 是单 socket 自动调节的上限，两者不是同一个限制。TCP 能在系统仍有可用内存时进入其协议预算压力。`rmem` 按 skb 的 `truesize` 记账，包含数据以外的开销；不能把它与排队的正文 byte 数直接等同。[官方 tcp_mem 与自动调节说明](https://docs.kernel.org/6.18/networking/ip-sysctl.html#tcp-mem)、[socket 内存记账实现](https://github.com/gregkh/linux/blob/725bd2f3c81d54edccb66fead01d4c0c222e2231/include/net/sock.h)。

## 本机对应关系

固定同一真实外层地址、12 条完整下载连接的 BBR 对照中，无线电脑两轮 UA3F 外层 socket 的 drops 分别增长 25,454／30,209，相邻路由器本机组为 0。电脑组同窗全局 `PruneCalled` 为 1,131／1,196、`TCPOFODrop` 为 1,028／1,115、`TCPRcvQDrop` 为 55／37、`TCPMemoryPressures` 为 10／11；接收窗口最低 5,888 B，接收阈值最低 5,840 B。全局计数仍包含后台连接，不能把每次增量逐个归入这 12 条 socket。

下载方向为：CDN → UA3F → loopback 上的 Ninja 接收端 → Windows。Ninja 的 loopback 接收队列曾达到 3,758,344 B，窗口降到 640 B。后段消费变慢可以向前传递背压，这是结合机制与现场数据的推断；没有单线程／逐函数运行追踪，仍不能把首个受限位置定为 UA3F、Ninja 或无线驱动中的某一个。[完整同窗审阅](cpu-repair-review.md)。

各组 `TCPBacklogDrop` 与每核 softnet dropped 增量均为 0，因此当前没有支持扩大 `netdev_max_backlog` 的证据；这不排除其他位置或其他时段的丢包。外层本地 `bytes_retrans=0` 是路由器发送方向，不能证明 CDN 下载发送方向没有重传。

已完成的外层接收缓冲限额对照为默认 814.71 Mbps、限额 812.00 Mbps，均完整收到 768 MiB；drops 为 21,092／22,727，没有收益。最后的默认复测因可用内存触发停止门槛，正文不完整，不能作为有效 A/B/A 比较。更早增加全局 TCP 内存预算也曾减少裁剪而降低吞吐，故不持久扩大缓冲。[限额结果](owned-buffer-cases-summary.json)。

公开 UA3F issue 搜索命中 [v0.2.0 performance issue](https://github.com/SunBK201/UA3F/issues/3)，但对象为 2023 年 MT7621A／v0.2.0，与本机 MT7986／v3.7.0 不同；没有找到能够直接解释本机这些计数的上游已确认缺陷。报告没有因此升级、替换代理或改动内存参数。
