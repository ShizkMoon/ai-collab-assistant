# UA3F 下行复制与无线 900 Mbps 目标的机制判断

**当前 UA3F TCP 下行已经具备 Linux splice 路径，源码没有“两三百 Mbps 固定上限”或所有连接串行复制的证据。现在不应部署扩缓冲、重复新增 splice 或直接开启 sockmap 的补丁。** 优先固定真实 CDN 外层、确认无线 raw 容量，并处理已观测的每核／softirq 压力；只有完整代理链仍慢且复制方式有运行证据后，才进入 UA3F 实现调整。

本支线只读保存的安全性能结果、UA3F／Go／Linux 原始源码，没有 SSH、生产修改、认证、凭据读取或新测速。最终只交付本报告，没有保留候选补丁、新 UA3F 二进制或测试框架。

## 固定源码与当前包边界

通过 Agent Reach 的 GitHub／gh API 路由重新读取 UA3F `v3.7.0`。该 annotated tag 对象是 `6cc2b01433beff96b5e65df587b765904fa9b510`，指向提交 `e464514ab313e3afe308881d7e5732a5baf41ce2`。保存的 ARM64 安装包二进制 `work/deploy/ua3f/package-usr__bin__ua3f` 经 `go version -m` 读回 Go `1.26.1`、linux／arm64、GOARM64=v8.0；模块显示 devel，没有可以直接认定相同源码的 vcs revision。故 Go 复制判断采用固定 `go1.26.1` 源码，UA3F 采用已确认 release 源码；设备当前二进制是否仍与保存包相同由主代理读回，不能仅凭包名证明。

Linux 稳定源码按 `gregkh/linux v6.18.55` 核对 `tcp_splice_read()`；这说明该版本实现支持 TCP→pipe，不证明 OpenWrt 的全部配置、patch、trace 能力或实际每次调用已走同一路径。不为这项分析安装 Ubuntu、换内核或更新工具链。

## 实际下行路径

| 固定函数／位置 | 已核实行为 | 影响 |
| --- | --- | --- |
| `internal/server/socks5/socks5.go:213–239`，`handleConnect()` | 已接受 TCP 客户端，`base.Connect()` 建目标 TCP，再形成 ConnLink | LConn 和 RConn 的正常 SOCKS TCP 分支均为 `*net.TCPConn` |
| `internal/server/base/tcp_linux.go:18–34`，`Connect()` | 目标 TCP 设置 `SO_MARK=0xc9`，沿现有 MWAN 选择出口 | 复制实现无需修改 mark、三出口策略、认证或外层源地址 |
| `internal/server/base/server.go:72–79`，GLOBAL 分支 | `go CopyRL()` 负责下载；同连接的 `ProcessLR()` 解析和改写请求 | 双向分别执行，多个连接也分别由 goroutine 处理；不能称全局串行 |
| `internal/common/connlink.go:104–119`，`CopyRL()` | `io.CopyBuffer(LConn,RConn,one)`，结束后关闭相应读端／写端 | 不解析下载正文、不逐包改 UA；保留半关闭语义 |
| `src/io/io.go`，`copyBuffer()` | 优先 source WriterTo，其次 destination ReaderFrom；存在接口时忽略传入 buf | `one=make([]byte,1)` 不等于正文按 1 字节 Read／Write |
| `src/net/tcpsock.go` 与 `tcpsock_posix.go`，`TCPConn.WriteTo()`／`writeTo()`／`genericWriteTo()`／`ReadFrom()` | TCP source 的 WriteTo 经隐藏接口的 genericWriteTo，调用 TCP destination 的 ReadFrom，再到 spliceFrom | TCP→TCP 有默认内核 splice 路径；只是查看 writeTo 的 spliceTo 支持 UnixConn 会漏掉后面的 ReaderFrom 路径 |
| `src/net/splice_linux.go`，`spliceFrom()` | 支持 `*TCPConn` 和隐藏 WriteTo 的 TCP wrapper，调用 `poll.Splice()` | 内核可以绕过用户态正文复制；无需重新写一套 splice |
| `src/internal/poll/splice_linux.go`，`Splice()` | pipe 池，最多请求 1 MiB；先 socket→pipe，再 pipe→socket，非阻塞 EAGAIN 接 Go poll；pipe 容量扩大失败仍可用 | 每流有顺序和回压，这是正常 TCP 保序；并不把全部连接串行化 |

Go 的 pipe 创建／支持失败可能回退普通复制；初始 `EINVAL` 不消费数据时可安全回退。完整 TCP→TCP 的一般回退也会进入内部 `io.Copy` 的默认缓冲，不能因 UA3F 外层参数 one 就断言全部回退路径是 1 字节。TLS wrapper、其他 net.Conn 类型以及响应重写分支会改变可用接口，必须按实际连接判断。

源码：[SOCKS5](https://github.com/SunBK201/UA3F/blob/e464514ab313e3afe308881d7e5732a5baf41ce2/internal/server/socks5/socks5.go)、[GLOBAL 与请求处理](https://github.com/SunBK201/UA3F/blob/e464514ab313e3afe308881d7e5732a5baf41ce2/internal/server/base/server.go)、[CopyRL](https://github.com/SunBK201/UA3F/blob/e464514ab313e3afe308881d7e5732a5baf41ce2/internal/common/connlink.go#L104-L119)、[SO_MARK](https://github.com/SunBK201/UA3F/blob/e464514ab313e3afe308881d7e5732a5baf41ce2/internal/server/base/tcp_linux.go#L18-L34)、[Go CopyBuffer](https://github.com/golang/go/blob/go1.26.1/src/io/io.go)、[Go TCP 方法](https://github.com/golang/go/blob/go1.26.1/src/net/tcpsock_posix.go)、[Go genericWriteTo](https://github.com/golang/go/blob/go1.26.1/src/net/net.go)、[splice 类型选择](https://github.com/golang/go/blob/go1.26.1/src/net/splice_linux.go)、[pipe 与非阻塞实现](https://github.com/golang/go/blob/go1.26.1/src/internal/poll/splice_linux.go)、[Linux 6.18.55 TCP splice](https://github.com/gregkh/linux/blob/v6.18.55/net/ipv4/tcp.c)。

## sockmap 不能作为当前 HTTP 的低风险开关

`ServeConnLink()` 只在 DIRECT 模式或 GLOBAL 首次嗅探不是 HTTP 时调用 `TryOffload()`；明文 HTTP 持续由 `ProcessLR()` 解析并改写每个后续 Request。简单启用 `Config.BPFOffload` 不会把正在下载的 HTTP 请求链全部转换为 sockmap。将整条 HTTP 连接交给双向 sockmap 会让后续客户端 Request 绕过用户态 UA 重写，破坏现有契约。

固定 `sockmap.c:24–44` 的 stream parser 返回 skb 长度，verdict 以 socket cookie→peer cookie 做 `bpf_sk_redirect_hash(...,0)`，双向 peer map 由 `Sockmap.Add()` 配置。它与 TC L3 字段解析、WED、软件 flowtable 是不同机制；已有 TC parse_l2 缺陷不能直接推导 sockmap 相同缺陷。反过来，内核版本够新也不能证明目标已支持/加载 sockhash、所需 BPF attach 与正确生命周期。

若后续要做仅 R→L 的 HTTP 下载 sockmap，须新设计单向 peer、处理已接收未读字节、切换时序、CopyRL goroutine 的退出／等待、EOF／FIN、map 删除和错误回退；不得顺便绕过 ProcessLR。当前 `TryOffload()` 注释提到 OffloadDone，但固定 ConnLink 结构没有该字段，实际调用者仍继续普通 copy，说明不能靠注释当作已完成的交接协议。没有本机运行证据前，不把这条路线列为直接可部署修复。

全局 `Config.BPFOffload`（socket sockmap）与 `L3Rewrite.BPFOffload`（TC L3）是两个字段；保存 init 的 `UA3F_L3_REWRITE_BPF_OFFLOAD` 只负责后者，不是前者的同义开关。保持现有 nft postrouting TTL≥10→64，覆盖 wan／eswan2／eswan3，不打开 TC TTL，不开启会旁路现有 TTL 的 flow offload。

源码：[TryOffload 与清理](https://github.com/SunBK201/UA3F/blob/e464514ab313e3afe308881d7e5732a5baf41ce2/internal/server/base/server_linux.go)、[sockmap attach 与双向 map](https://github.com/SunBK201/UA3F/blob/e464514ab313e3afe308881d7e5732a5baf41ce2/internal/bpf/sockmap/sockmap_linux.go)、[BPF verdict](https://github.com/SunBK201/UA3F/blob/e464514ab313e3afe308881d7e5732a5baf41ce2/internal/bpf/sockmap/sockmap.c)、[配置字段](https://github.com/SunBK201/UA3F/blob/e464514ab313e3afe308881d7e5732a5baf41ce2/internal/config/config.go)、[Linux helper 语义](https://github.com/gregkh/linux/blob/v6.18.55/include/uapi/linux/bpf.h)。

## 现有数字支持什么

保存结果的本机 UA3F 12 流、768 MiB、7.14 秒为 902.30 Mbps，紧邻裸三路 908.67 Mbps，固定真实外层 `171.108.211.12`。整机 busy 57.5% 对裸组 33.7%，显示额外代理／TCP／调度工作，但不能将 23.8 个百分点全部算作 UA 字段替换或纯 memcpy。

无线 PC 352.73 Mbps 组 CPU2 busy 96.4%、softirq 89.9%，与单纯 UA3F 用户态解析满 CPU 的证据不同；它提示 Wi-Fi、loopback、TCP、本地入站、RPS 与多个代理 leg 共同处理的局部压力。另一个 PC 169.60 Mbps 组未出现平均单核≥90%，另一 CDN 裸三路也只有 146.25 Mbps，因此高 softirq 不能解释全部慢样本。当前 LAN 567～605 与历史 869～886 也不支持无线固定硬上限。保存性能材料见 [UA3F 固定端点](../aggregation/ua3f-layer-cases.json)、[原因判断](../aggregation/wireless-cause-results.md)、[防检测分层](../aggregation/wireless-antidetection-analysis.md)。

## 最小行动与无线路径验收

1. 先保持 UA 重写、nft TTL64、SO_MARK0xc9、三路认证、核心与无线位置，取得真实同 CDN 的无线完整路径。PC 指定数字目标或核心 metadata 不够，须由 UA3F socket inode→外层 tuple→SNAT／三出口与接收字节证明；不能用不同来源差值判复制开销。900 目标还需要主代理按授权核对当前 CAKE 650 Mbps 的预算，不能拿临时去整形的 router 快样本承诺日常无线速度。
2. 按主代理现有探针先确认无线 raw／LAN 容量和 packet steering。每核 `/proc/stat`、softirq／interrupt 增量、UA3F／核心各线程、station 字节／重试、TCP 分腿重传必须同窗采样。RPS／RFS 通过流哈希及消费 CPU 分配，跨核通知有成本；不假定写全核 mask 就必然均分。[Linux 6.18 scaling](https://docs.kernel.org/6.18/networking/scaling.html)
3. 只有真实同端点的完整代理链仍慢时，针对自有有限预检连接观察 UA3F `splice` 与 read/write 系统调用。可用设备已有的轻量追踪能力做短窗计数；若仅有 strace，attach 可能明显扰动，不能把其测速值当正常吞吐，也不为本报告安装全套追踪框架。pipe fd 的存在或读完日志仅能作线索，成功 splice 的字节／返回值才能证明实际路径。短预检后停止追踪，再运行无追踪的有限正文对照。
4. 若现有下行已经 splice，则暂不改 UA3F；低风险候选是主代理已在定位的 steering／线程竞争与真实外层固定。若证明 wrapper 或 pipe 失败造成持续 read/write，再对该实际分支提出接口保留／缓冲候选。64 KiB 用户态 read/write 可以作以后仅下行的辨别对照，但默认已有 splice、buffer pool 和不同内核处理成本，无法预先断言更快，本轮不部署。
5. 任一修复必须在无线 PC 的真实同源、相同总并发、完整正文窗口复测；同时核 UA=FFF、三个已选择出口的 TTL64／mark、三认证与原业务、延迟和内存。只有真实无线 PC 重复接近目标才报告达成 900；编译通过、router 本机 900 或理论 zero-copy 都不能替代。

本轮结论是排除一个会误导部署的源码解释，并给出后续条件。尚未证明实际每条连接都使用 splice、唯一 CPU 根因、学校检测限速或无线稳定 900；本报告没有改动目标设备。
