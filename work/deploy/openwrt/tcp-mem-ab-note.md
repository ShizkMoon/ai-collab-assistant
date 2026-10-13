# TCP 内存预算的单变量 A/B 核查

2026-10-12；本支线未连接设备。依据主代理提供的同批下载差分和 Linux 官方 `v6.18` 文档、源码。设备实际为 6.18 系列补丁版本，这里核对基础版本语义，未声称检查了该设备完整厂商构建。

**本次提高 `tcp_mem` 减少了裁剪计数，吞吐下降；运行值已恢复原值，不持久化。** 同样的 16 条独立连接、每条 64 MiB、完整 1 GiB 下载中，前 A 为 547.69 Mbps，B 为 470.74 Mbps，恢复后 A 为 547.30 Mbps。B 比前 A 低约 14.1%，恢复后 A 与前 A 相差约 0.07%。A/B 两次返回状态全部为 206，恢复后 A 同样完成全部字节。回退对照支持在这套当前负载下保留原值；这三个短窗仍不能排除服务器/CDN、Wi-Fi 和测试时序变化，不能证明扩大预算必然降低性能。计数下降不能称为测速瓶颈已修复。本分支已结束，不再提出其他参数或追加测速。

| 同窗差分或采样指标 | A：原值 | B：32 / 64 / 96 MiB |
| --- | --- | --- |
| 总吞吐 | 547.69 Mbps | 470.74 Mbps |
| `TCPMemoryPressures` | 16 次 | 1 次 |
| `TCPMemoryPressuresChrono` | 330 ms | 320 ms |
| `PruneCalled` | 2,114 | 93 |
| `TCPOFODrop` | 1,972 | 30 |
| TCP `mem` 采样峰值 | 本支线未收到该值 | 49.93 MiB |
| `MemAvailable` 采样最低值 | 本支线未收到该值 | 122.75 MiB |

进入压力的次数下降，累计压力时长近似，说明次数不能单独代表压力影响。全局计数还包含后台和多个代理 socket，不能隔离微软下载，也不能直接量化速度损失。B 最低可用内存未显示这次短窗耗尽，但不能证明长期运行和其他负载的预算充分。

`tcp_mem` 三值为 `min / pressure / max`，单位是内存页：低于 min 退出压力；高于 pressure 开始节制协议内存；max 用于限制所有 TCP socket 的队列分配。它不预分配整片内存。协议分配器仍有发送进度等特殊例外，所以 max 也不是系统所有网络内存的严格总量上界。[官方文档](https://github.com/torvalds/linux/blob/v6.18/Documentation/networking/ip-sysctl.rst)、[socket 分配实现](https://github.com/torvalds/linux/blob/v6.18/net/core/sock.c)。

换算按 4096 字节内存页列出；不凭 ARM64 推定 PAGE_SIZE，设备实际页大小以主代理读回为准：

| 已比较的值 | min / pressure / max | 与旧最大值相比 |
| --- | --- | --- |
| 原值 `5727 7638 11454` | 22.37 / 29.84 / 44.74 MiB | 基线 |
| B 运行值 `8192 16384 24576` | 32 / 64 / 96 MiB | 队列分配余量增加约 51.26 MiB |

提高上限会与 Ninja / UA3F 用户态缓冲、DNS、slab 和其他系统需求竞争。B 的 TCP `mem` 采样峰值 49.93 MiB 低于 64 MiB 压力阈值，同时出现 1 次压力事件并不矛盾：低频采样可能漏掉毫秒级峰值，压力持续到低于 32 MiB 才退出；累计时长还取决于采样窗口内是否已经退出。现有数据支持描述本次队列裁剪减少，未提供保留更大预算的体验收益。

`tcp_rmem[2]` / `tcp_wmem[2]` 是每 socket 自动调节上限，单位字节；与 `tcp_mem` 的总预算不是同一个参数。`tcp_moderate_rcvbuf=1` 才能进行接收自动调节；应用显式 `SO_RCVBUF` 会锁住接收缓冲并绕开该自动调节上限。当前约 3.73 MiB 的每 socket 最大值不必同时提高。多个独立连接及代理双端累计实际内存能撞到全局压力阈值，单个 socket 没达到其最大值也不矛盾。[官方 rmem / wmem 文档](https://github.com/torvalds/linux/blob/v6.18/Documentation/networking/ip-sysctl.rst)。

`TCPMemoryPressures` 记录进入全局 TCP 压力的次数；`TCPMemoryPressuresChrono` 在退出时累加毫秒，不是 CPU 耗时，跨越采样尾部仍未退出的压力时长可能尚未计入。[计数实现](https://github.com/torvalds/linux/blob/v6.18/net/ipv4/tcp.c)。`TCPOFODrop`、`TCPRcvQDrop`、`PruneCalled`、`OfoPruned` 与接收内存调度/队列裁剪相关，但可能同时来自单 socket 缓冲和用户态读取速度，不能保证只增 `tcp_mem` 就全部消失。[接收实现](https://github.com/torvalds/linux/blob/v6.18/net/ipv4/tcp_input.c)。

本机 OC / UA3F 会终止并重新建立 TCP，因此这些设置影响本机代理 socket；普通不终止连接的 NAT 转发并不是同一种路径。保持 core rmem/wmem、backlog、算法、代理规则、IRQ 和 Wi-Fi 设置不变。softnet 各 CPU dropped=0 没有支持提高 backlog 的证据。

读取数据时保持以下边界：

- `/proc/net/sockstat` 的 TCP `mem` 页数峰值和下载停止后回落；该项是协议记账，不是整个网络子系统内存。
- 同窗 MemAvailable 最低值、slab / SUnreclaim、Ninja / UA3F RSS、内存 PSI（若存在）、OOM 或 allocation failure 日志；低频采样可能漏毫秒级峰值，须报告采样间隔。
- 全部连接字节数与返回状态、总吞吐与 LAN / 公网负载延迟；同时比较压力次数/时长、OFO / RcvQDrop、裁剪、重传及超时的差分。
- 当前 B 只有裁剪计数改善，吞吐没有改善；负载延迟尚无本支线可核实的比较值。结论为保留已恢复的原值。
- OOM、系统内存压力、服务失效和空闲时回落关系到是否可安全保留参数。本次没有理由继续扩大总预算或同时改每 socket 上限、backlog 等参数。
