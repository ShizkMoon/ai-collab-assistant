# 自有 outer 接收缓冲 helper 与 GET 门闩只读审阅

结论：所读 `owned_rcvbuf_linux.go` 的 cookie、TCP_INFO ABI、身份核对与 SOCKOPT 顺序没有发现阻断性错误。helper 不读取 socket 数据、不 shutdown、不改变共享 fd flags；设置影响的是同一原 socket 的接收缓冲，关闭 duplicate fd 不会撤销设置。原值 A2 必须使用新连接，现有接收器采用了这个做法。

首次审阅发现的两处门控缺口已经由主代理修正，并已只读核对当前源码：`verify()` 强制 `SO_MARK==0xc9`；`download()` 在 `release.wait(20)` 超时后设置 abort、关闭 socket 并返回失败，不能自行放行 GET。当前没有发现阻断 B 组的静态问题。该报告不是生产运行结果；没有编译、登录设备或运行流量。

## helper 的已核对行为

| 检查项 | 所读位置与结论 |
| --- | --- |
| PID 身份 | `comm=ua3f` 与 `/proc/PID/stat` starttime 比较；stat 去掉 comm 后从 field 3 开始，索引 19 对应 field 22，正确。`pidfd_open` 后、设置前再次核对 starttime。 |
| fd 所有者与复用 | 复制前核对 `/proc/PID/fd/FD` 为清单 inode；`pidfd_getfd` 后对 duplicate 做 Fstat，并核对 inode、cookie、local／peer tuple。原 FD 号复用不能仅靠原 fd 号蒙混通过。 |
| cookie ABI | diag 用 `payload[48:52]` 高 32 位加 `payload[44:48]` 低 32 位格式化为 16 位十六进制。helper 用 ParseUint 得到同一个 uint64，再与 `SO_COOKIE` 返回的 NativeEndian uint64 比较，正确。 |
| TCP_INFO ABI | `tcpi_bytes_received` 的字节偏移为 128，长度至少 136 才读 8 字节。`b[0]==1` 对应 ESTABLISHED。这里与已有 diag 解析器一致。SYN／ACK 不作为正文累加，`bytes_received=0` 与 GET 前门闩相容。 |
| 目标范围 | 必须是 IPv4、清单 tuple、固定 `171.108.211.12:80`，且 TCP_INFO 接收字节为 0。helper 最多接受 12 个 target；接收器进一步要求恰好 12 个新增 cookie 和三路出口。 |
| 设置顺序 | 全部 target 完成 verify 后才进入 SET 循环，避免身份核对失败时先改变前几条连接。SET 请求为 1,048,576 B，GET readback 必须为 2,097,152 B；内核实际 cap 不匹配时停止。 |
| duplicate 生命周期 | fd 操作只有 Fstat、getsockopt、getsockname／getpeername、setsockopt 与 defer Close；没有 recv/read、shutdown、fcntl、setsockopt SO_MARK 或修改阻塞状态。关闭 duplicate 仅释放这个引用。 |
| 中途失败 | SET 循环可能已经改变前几条自有 socket 再失败，这是允许的局部状态；主控必须关闭本轮全部原始测试连接。不能“写回 Before”来恢复接收缓冲自动调节锁。 |

SO_RCVBUF 的请求数值与内核报告数值使用不同口径：Linux 的 readback 包含翻倍后的记账额度。本轮 B 的 1 MiB 请求是固定 2 MiB socket 额度。原态 CONNECT 后可报告 131,072 B，正文过程中会自动增长；本试验比较的是自动增长与固定额度的整体行为，不是两个相同起始缓冲的纯上限差异。因果解释必须保留这个条件。

## 门控修正与剩余日志问题

1. 当前 `verify()` 完成 `GetsockoptInt(SO_MARK)` 后，遇到错误立即返回；若 `v.Mark != 0xc9`，立即拒绝。它位于全部身份核验阶段、任何 SET 之前，符合 C9 门控要求。
2. 当前 GET 门闩检查 `release.wait(20)`，返回 false 后设置 abort、关闭 socket，并返回包含 `size_download` 与时间字段的失败记录。不能进入 `sendall(GET)`，符合失败即停止要求。
3. 剩余低优先级问题是另一条 `if abort.is_set()` 早退记录仍缺 `size_download` 与时间字段，也未在该分支自行 close。主控 finally 会关闭原始连接，因此不会扩大变更；但其他流因一次失败提前返回时，主线程可能在统计中抛 KeyError，掩盖最初失败原因。建议返回同样完整的失败字段并关闭 socket。不影响正常 A／B／A2 的门控与计时。

两处关键修正及一处日志建议均不需要变更生产配置。上述“已修正”只表示源码读回，运行与 binary 是否一致由主代理的编译、上传和真实验收确认。

## 接收器的门控、计时与回退

`prepare()` 使用 before／ready cookie 差，筛选 UA3F 拥有、固定 CDN:80 的新增 outer，并要求数量为 COUNT、接收正文为 0、recv queue 为 0。它还要求路由覆盖三个认证出口，Ninja 的自有连接为 Socks5、目的地址固定、链包含 UA3FLocal。随后从 UA3F fd 清单建立 manifest，调用 helper，并在 GET 前使用 INET_DIAG 再读回 cap。这个顺序符合“SOCKS CONNECT 已建立、GET 尚未发送”的试验设计。

前后的核心 PID、认证 PID／starttime／running、网络／无线／firewall／Ninja 配置 hash、WAN IPv4 地址与 BBR 都进入 contract 比较。cap 动作只影响 helper 的自有 socket。`run_case()` finally 关闭全部 Windows 原始连接、停止 monitor、拍 after，并检查目标 cookie 已退出 ESTABLISHED 观察集；下一 case 使用不同源端口重新建立连接。它没有用回写旧 SO_RCVBUF 的方式恢复自动调节，因此 A2 的恢复方法正确。

计时从主线程放行门闩前开始，结束取各流完成正文接收时间的最大值。12 个流必须各自收到精确的 206、Content-Range、Content-Length、identity 正文与 EOF；不完整流或 monitor 错误会使本轮失败。64 MiB × 12 的完整正文合计 768 MiB。门闩前的连接、manifest、读回和 contract 时间不计入下载时长。外层 fixed-path 还用对应 inode 的 reply bytes 增长大于 1 MiB 验收。

monitor 连续两次发现 MemAvailable 小于 64 MiB，或核心 PID 变化时设置 abort。这是操作保护阈值，不能解释为内核 TCP 内存压力阈值。CAKE 的停止／恢复及 300 秒回退 watchdog 属于主代理控制范围；finally 启动原服务并比较 qdisc 字符串。若 watchdog 提前恢复 CAKE 或任何恢复命令失败，应把受影响测速判为无效，并由主代理单独读回，不能仅凭末态相等证明中途没有队列变化。

本轮 A／B／A2 使用同一个 Python 接收器、SOCKS 握手和正文计时，应优先比较这三组之间的结果。它与历史 curl／其他接收器的绝对速度差还包含客户端实现差异，不能全部归因于 SO_RCVBUF。

## 审阅范围与限制

只读 `owned_rcvbuf_linux.go`、`owned_buffer_trial.py` 及 `tcp_diag_linux.go` 对应 cookie／TCP_INFO 解析。没有读取凭据输出，没有导入或运行接收器，没有操作设备。两个关键门控问题已回传并读回修正，剩余日志建议也已回传；本次新增文件仅为这份独立审阅报告，未修改主线文件。
