# LAN 测量控制器与发送端只读审阅

这轮 110.19 Mbps 结果是被 30 秒发送 deadline 截断后的部分字节平均，不能作为完整 LAN 容量结果。源码没有固定 110 Mbps 限速；12 个接收线程的启动差距仅 1.2 ms。此前 860.09、889.53、938.34 Mbps 三组完整读回，证明同一实现曾在短窗口达到这些应用层吞吐，但不能证明每次运行都稳定。

只读范围是 `lan_raw_probe.py`、`wireless_sender.go`、三个非私密 `lan-raw-*.json` 结果和本机 Go 标准库。没有 SSH、测速、设备操作、私密文件读取或目标源码编辑。主线文件仍由主代理修改。

审阅开始时 SHA256：

- `lan_raw_probe.py`：`984E0C206F0ED755FEEF40C4E0F1F251DA24E4D7082815676A59786176EC32A3`。
- `wireless_sender.go`：`D194F86F9ED0C0955A84B2EEE5EB7B467A68D6AB9704E770E0441539EA6EEC04`。

交付前复核到主线已修改这两个文件，当前 SHA256 分别为 `E3C443458140A1D472D646D59D4C3CE457CBEB9C67708B7D8C930A832D6EC4EE` 与 `85593455BDDAC14F8978D50BD7D0817DBE90648B88BFA31E70E4AE529EDB8040`。当前 Go deadline 已改为 120 秒，客户端数据空闲 timeout 为 125 秒；Go 新增 TCP_INFO 采样、可选 congestion 和最多 512 MiB 请求，控制器仍默认每流 64 MiB。旧结果不会因这些源码修改变成完整结果。下面明确区分旧测试机制与当前剩余问题；没有验证新二进制运行效果。

## 当前剩余问题

### P2：指定 congestion 未验证设置成功

当前 `wireless_sender.go:68` 调用 `SetsockoptString(TCP_CONGESTION, requested)`，但忽略返回错误，也未读取实际算法。控制器 `28–35` 行只记录请求值。若设置失败，连接继续使用原算法，标签仍显示指定的 BBR/CUBIC，实验结论会错误归因。

最小候选：记录设置错误，读取实际 TCP_CONGESTION 值；不一致时使该 case 失败。TCP_INFO 的 pacing、cwnd 等统计不能替代算法名称读回。该项已同步主代理。

新采样 `samples` 在独立 goroutine 追加，主线程通过 finished channel 等待其结束后再追加末样本，按当前可见代码没有并发切片写冲突。与原始版相比，Go seconds 现在还包含等待采样 goroutine 结束与最后一次 TCP_INFO 读取；可记录 copy elapsed 与采样收尾 elapsed 两个值，避免合并成纯发送时长。

## 原测试机制与当前适用边界

### 旧测试版：绝对 30 秒 deadline 截断低速比较

`wireless_sender.go:38` 在认证之前调用 `SetDeadline(now+30s)`，同时限制读与写。这个 deadline 不会随数据进展刷新。每条连接固定发送 64 MiB；12 条同时运行，总量为 805,306,368 B。在 30 秒内接收完整总量，至少需要 214.75 Mbps 平均吞吐。若总吞吐维持约 110 Mbps，该组必然不完整；连接和认证所用时间还会缩短数据期。

`lan-raw-restored.json` 证实全部 12 条发送记录的 `seconds` 在 29.9985～30.0000 秒附近，全部 `complete=false`。客户端总量与发送记录总量同为 506,843,672 B。Python 的 `all_complete` 判断与最后的断言正确拒绝该组；记录中的 `payload_mbps=110.19` 应标为超时失败中的已收字节平均。

当前主线 `wireless_sender.go:61` 已把绝对时限增至 120 秒，默认 12×64 MiB 在 110 Mbps 时约 58.6 秒，具备完成时间余量，但修改本身不构成提速。若采用新增的每流 512 MiB，12 流在 120 秒内完整发送仍需至少 429.50 Mbps；在 110 Mbps 时约 468.5 秒，需要重新核对总时限。认证和数据时限仍可分开，保持自动退出边界；绝对 deadline 不能标为空闲超时。

### P2：接收异常会丢失部分传输和失败阶段

当前 `lan_raw_probe.py:60–71`（原测试版 `54–65`） 只处理 EOF，不捕获 `socket.timeout`、连接重置或其他 socket 异常。只要任一线程抛异常，`executor.map()` 在 当前 `97` 行抛出，当前 case 不会执行 `103–111` 行的结果保存，部分字节、错误阶段和其它连接结果会从主结果中缺失。`finally` 仍清理服务，但不能恢复这些诊断字段。

最小候选：每条连接都返回包括已收字节、异常类、异常文本、连接成功时间、请求发送完成时间、首字节时间和结束时间的结构化记录；汇总必须保存失败 case 后再判失败。连接失败与已开始的数据期中断分开记录，错误文本不得包含 token。

### P2：发送与接收记录不能逐请求配对

Go `request` 与 `result` 没有请求 ID；当前 `wireless_sender.go:75`（原版 `48`） 按完成顺序把记录写入累计数组。Python 使用 `id=index`，但未把 ID 发给发送端。`server_records` 在三个 baseline case 中累计到 36 条。不能按数组位置把发送时间配到某条 Python 接收流，也不能用全数组的最小或最大秒数代替当前 case。

最小候选：传入不敏感的 case ID 和 stream ID，并在 Go 结果保留这两个字段及 remote IP/port。记录 accepted、authenticated、copy start、copy end、result write end、close 前的时间，以及 copy 错误与 timeout 分类。时间比较优先用同一端单调时钟的时长；两台机器的绝对时钟未经校准不能直接相减。

### P3：失败时的客户端 elapsed 包含额外等待，发送计时不是收端容量

原测试版发送端 `46–47` 行仅计 `io.CopyN()`；Python 原 `55` 行在建连接之前计时，原 `63` 行在连接关闭后结束。当前 Python 对应 `61` 与 `69` 行，仍覆盖这些阶段。源端排队写完、客户端读完、EOF 到达是不同事件。正常完整读回以客户端总字节和完整接收窗为准。

失败组客户端总窗是 36.7976 秒，最长 Go copy 约 30.0000 秒。现有记录缺少连接、认证和 EOF 阶段，无法定位约 6.8 秒的差异。Go 原 `48` 行、当前 `75` 行在 `c.Close()` 前持有记录锁并写结果文件；因此不完整连接等待 EOF 时，可能包含日志写入与关闭排队时间。源码只证明这些阶段位于计时范围内，不能证明它们造成了这 6.8 秒。

不要从源端 `seconds=0` 推容量，也不要用源端单流时长相加算同时传输的容量。零时长、缺少时间或不完整计数只能作为缺失或失败数据。

## 已核对且不能直接归因的部分

| 项目 | 源码与结果判断 | 不能得出的结论 |
| --- | --- | --- |
| 并发含义 | `executor.map(receive, range(12))` 始终执行 12×64 MiB；`max_workers` 控制同时运行的连接数。`parallel=1` 是顺序执行 12 次，不是只发送一条 64 MiB。 | 不能把每组总量按 parallel 倍数再乘一次。 |
| 计速时钟 | `time.perf_counter()` 是控制器计时入口，当前 `94–98` 行包住线程池创建、连接、接收与线程池收尾。monitor join 和 after snapshot 位于 elapsed 结束之后。 | 不能把 110.19 Mbps 直接归因于 after snapshot 被计入吞吐分母。 |
| 接收循环 | `recv(min(1MiB, remaining))` 只指定单次最多读取量，无 sleep 和人为字节速率。数据可以部分返回，循环累加正确，EOF 会保留已收字节。 | 1 MiB 参数不是 TCP 接收窗口；不能据此声称窗口已足够或被固定为 1 MiB。 |
| 线程启动 | 失败组 12 条 `started_monotonic` 相差约 1.2 ms。 | 不支持线程启动本身造成约 6.8 秒的差异。 |
| 默认 socket 缓冲 | Python 未设置或记录 `SO_RCVBUF`；Go 只在发送前读取 `SO_SNDBUF`，本轮为 130,560 B，没有强制设置它。 | 初始默认值不能证明传输期的实际窗口、自动调节、背压或固定吞吐上限。 |
| CPU 采样 | `before` 到 `after` 包括测量外边缘；monitor 每次要等待 1 秒，再执行 snapshot，并非固定 1 Hz。恢复组 snapshot 耗时 0.66～5.26 秒，baseline 约 0.45 秒。 | 低 CPU 不能单独证明接收限制或无线问题；也不能把每份 CPU 采样当成精确 1 秒的数据期。 |
| CPU 窗口 | 恢复组样本 midpoint 窗 38.3373 秒，接收窗 36.7976 秒；差约 1.54 秒。样本内 `/proc/stat` 在远端命令开头读取，Windows CPU 在 snapshot 末尾读取，midpoint 是估计。 | 这约 4%的窗差能影响百分比，但没有数量级证据能解释全部性能下降。 |
| 发送文件 | 每条请求独立 `os.Open()`，原版从文件起点发送固定 64 MiB；当前每流的 fd 独立，对同一 fd 每轮 seek 回起点并发送 64 MiB，以复用已有有界文件。文件在前置阶段创建，计时内没有重复生成文件或跨流共享 seek。 | 不能把同时读文件解释为同一文件偏移竞争。 |

## Go sendfile 的版本核对

本机 `go version` 与 `go version -m wireless-sender-arm64` 均为 Go 1.27.1；该二进制记录的目标是 `linux/arm64`、`CGO_ENABLED=0`。直接阅读同版本本机标准库：

- `src/io/io.go:363`：`CopyN()` 调用 `Copy(dst, LimitReader(src,n))`。
- `src/io/io.go:407`：LimitedReader 没有 WriteTo，目标 TCPConn 实现 ReaderFrom，因此进入目标的 ReadFrom。
- `src/net/tcpsock_posix.go:47`：先尝试 splice，再尝试 sendFile，未处理时才走 genericReadFrom。
- `src/net/sendfile.go:24`：解开 LimitedReader，拿到底层文件的 syscall.Conn，再调用 poll.SendFile。
- `src/internal/poll/sendfile_unix.go:98`：遇到 EAGAIN 等待目标可写；prepareWrite/waitWrite 仍遵守 socket deadline。
- `src/internal/poll/sendfile_unix.go:135`：Linux 路径使用 syscall.Sendfile。

因此源码具备 file→TCP 的原生 sendfile 条件，bufio.Reader 只读认证请求，不包装出站 writer。不能仅因使用 `io.CopyN` 就说降成 32 KiB 用户态循环。未在设备上观测 syscall，本文不能证明每次运行实际采用 sendfile；不安装新工具、不改二进制来填补这个证据。

## 主线可以验证的候选顺序

1. 先读回当前 congestion 设置结果，再修测量完整性：按每流字节核对数据总时限、错误分类与每请求 ID。当前 deadline 的源码修改已见，运行效果未验。重新验收固定 12×64 MiB 全部完整、服务清理成功。超时结果保留为失败。
2. 增加阶段时间和 1 秒字节进展，分别显示连接/认证/首字节、数据期、EOF/关闭。用同一端的单调时长定位这轮多出的等待，不靠源端容量猜测。
3. 客户端首次保持 socket 默认行为，只读取实际 `SO_RCVBUF`。使用一个预分配 bytearray 加 `recv_into()`，减少 recv 的重复 bytes 分配，同时记录调用次数、最大空窗与总字节。这个候选不改系统 TCP 设置，也没有已验证的提速效果。
4. 如仍需排除接收窗口，主线可做独立 A/B：显式 socket 接收缓冲值与默认值各自读回，记录吞吐、完整性及阶段耗时。显式 SO_RCVBUF 可能改变自动调节行为；不要同时改变系统 autotuning、发送缓冲和 Wi-Fi 参数。
5. 为排除监控竞争，以相同目标与连接规模分别运行轻量仅计字节窗和现有 monitor 窗，保留前后 radio/CPU 读回。先确认监控差异，再判断其影响；当前源码和结果不证明监控是根因。

候选由主代理执行。本文没有把测量框架修复当作网络性能修复，也没有把短时 938.34 Mbps 当作稳定容量。