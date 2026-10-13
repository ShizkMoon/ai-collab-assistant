# Ninja → UA3F TCP 复制路径核对

固定版本 Mihomo 的普通 SOCKS5 转发已有 Linux `splice` 路径。`BufferedConn`、代理连接外壳和流量统计包装都提供拆包接口；缓存排空后，它们不会自动把全部数据锁在 32 KiB 用户态读写中。没有找到可部署的 YAML “开启零拷贝”或 TCP 读写缓冲大小字段。

这份核对使用 Mihomo 提交 `5019cc090ed7cafb76643f964a76b1e97aee2985` 及其 `go.mod` 固定的 `github.com/metacubex/sing v0.5.7`。Ninja 的公开标签只包含 README，不能逐行核对私有核心改动。因此源码具备 splice 与当前生产 Ninja 实际执行 splice 是两项证据；后者仍需在运行中确认。没有修改生产设备、二进制、认证、共享配置或测速进程。

## 双向复制的路径

1. `tunnel/tunnel.go:615` 把出站连接包为 `tcpTracker`，随后 `624` 行调用 `handleSocket()`。
2. `tunnel/connection.go` 的 `handleSocket()` 调用 `common/net/sing.go` 的 `Relay()`。这两个方向均调用 sing `bufio.Copy()`，旧的 `common/net/relay.go` 只保留注释，不能当作当前实现。
3. sing `common/bufio/copy.go:21` 的 `Copy()` 先调用 `UnwrapCountReader()` 与 `UnwrapCountWriter()`。它会递归拆开允许替换的包装，同时保留流量计数回调。
4. 若读侧还有缓存，`Copy()` 先发送缓存，再重新循环拆包。当最终两端都实现 `syscall.Conn` 时，调用 `copyDirect()`，再进入 Linux `splice()`。
5. Linux `splice()` 建非阻塞 pipe，尝试把 pipe 调整到 1 MiB，并使用两次 splice 在 socket 与 pipe 之间搬运。它仍调用计数回调；零拷贝不会失去连接统计。

源码：[Mihomo Relay](https://github.com/MetaCubeX/mihomo/blob/5019cc090ed7cafb76643f964a76b1e97aee2985/common/net/sing.go)、[sing Copy](https://github.com/MetaCubeX/sing/blob/v0.5.7/common/bufio/copy.go)、[Linux splice](https://github.com/MetaCubeX/sing/blob/v0.5.7/common/bufio/splice_linux.go)。

## 本路径中的包装

| 对象 | 已核对行为 | 对长期复制的判断 |
| --- | --- | --- |
| 入站 SOCKS `BufferedConn` | `ReadCached()` 发出已缓存字节；缓存为空后 `ReaderReplaceable()` 返回 true，写侧始终可替换。 | 首部或 peek 缓存不会永久阻止拆到原生 socket。 |
| 出站 `adapter/outbound/base.go` 的 `conn` | `Upstream()` 返回底层 ExtendedConn；读写可替换均返回 true。 | 代理链外壳可拆。 |
| `tcpTracker` | 实现 `UnwrapReader()` 与 `UnwrapWriter()`，返回原连接和计数回调。 | 保留统计的同时可拆；关闭统计不是有依据的加速候选。 |
| sing `ExtendedConnWrapper` | 读写可替换为底层 reader、writer，再递归拆到原始连接。 | 普通 TCP 包装可拆。 |
| 明文 SOCKS5 出站 | `socks5.go:72` 拨服务器，`64` 行完成 SOCKS5 握手，返回原连接；`NewConn()` 对 `syscall.Conn` 跳过 deadline 包装。 | 普通 TCP → 本机明文 UA3F SOCKS 具备 splice 条件。 |
| TFO 包装 | 未完成拨号前不可替换；`tfoConn` 在 `Conn != nil` 后读写可替换。SOCKS 握手会先写入并完成拨号。 | TFO 没有源码依据被判定为永久降级；无需为了零拷贝盲关 TFO。 |
| TLS、加密、协议转换或不可替换包装 | 最终对象可能没有 `syscall.Conn`，或者不能安全拆开。 | 此类路径退入扩展读写；不能为速度拆除需要的加密或 UA 处理。 |

来源：[BufferedConn](https://github.com/MetaCubeX/mihomo/blob/5019cc090ed7cafb76643f964a76b1e97aee2985/common/net/bufconn.go#L74-L106)、[代理连接外壳](https://github.com/MetaCubeX/mihomo/blob/5019cc090ed7cafb76643f964a76b1e97aee2985/adapter/outbound/base.go#L225-L284)、[统计拆包](https://github.com/MetaCubeX/mihomo/blob/5019cc090ed7cafb76643f964a76b1e97aee2985/tunnel/statistic/tracker.go#L72-L107)、[TFO 包装](https://github.com/MetaCubeX/mihomo/blob/5019cc090ed7cafb76643f964a76b1e97aee2985/component/dialer/tfo.go)。

## 退回用户态读写的条件

`Copy()` 拆包后任一端不能提供 `syscall.Conn`，就跳过 `copyDirect()`。Linux splice 读返回 `EINVAL` 或 `ENOSYS` 时，源码会返回 `handled=false`，继续进入扩展读写。普通构建的 sing `buf.BufferSize` 是 32 KiB；带 `with_low_memory` 的构建是 16 KiB。此值是编译选择，不能用新加 YAML 缓冲字段修改。

pipe 的 `F_SETPIPE_SZ` 返回值在源码中被忽略。调整到 1 MiB 失败不代表 splice 没有运行，但可能使实际 pipe 容量较小。没有核对当前内核的 pipe 限制，也没有证明 pipe 容量造成此次速度差距。`Pipe2` 失败或 splice 写错误会结束复制，并非所有错误都会安全退回读写。

来源：[普通缓冲常量](https://github.com/MetaCubeX/sing/blob/v0.5.7/common/buf/buffer_standard.go)、[低内存缓冲常量](https://github.com/MetaCubeX/sing/blob/v0.5.7/common/buf/buffer_low_memory.go)、[直接复制与回退入口](https://github.com/MetaCubeX/sing/blob/v0.5.7/common/bufio/copy_direct.go)。

## 配置与 mark 的边界

固定版本 `config/config.go` 的 `RawExperimental` 只有 `fingerprints`、`quic-go-disable-gso`、`quic-go-disable-ecn` 和 `dialer-ip4p-convert`。没有 splice 开关。前两项 QUIC 行为开关不会改变这条 TCP SOCKS 路径。

`BasicOption` 只有 TFO、MPTCP、网卡、routing mark、IP 偏好、dialer proxy 等通用字段，没有 TCP `read-buffer-size` 或 `write-buffer-size`。已读 `component/dialer/dialer.go`、`control.go` 和 `options.go` 未设置 SOCKS TCP socket 的读写缓冲大小。因此不能添加看似可解析、实则不改变本路径的缓冲字段。

`component/dialer/mark_linux.go` 的 mark 控制在连接到非 global-unicast 地址时直接跳过；到 `127.0.0.1` 的 UA3F SOCKS 腿不会依靠这一控制附加 WAN mark。mark 是路由选择依据，不能作为 splice 开关。改变全局 mark 或 UA3F 外层标记可能破坏三路与香港路由，当前没有加速依据。

## 可采用的下一项

本次源码阅读没有找到应立即部署的新复制配置。保留当前普通明文 loopback SOCKS 与完整 UA3F 链，是已有源码支持的低风险状态。若运行配置显示 UA3FLocal 新增了 `tls: true`、额外协议封装或 `dialer-proxy`，应先核对实际用途和 socket 类型；仅在确认属于误配置且本机 SOCKS 服务本来明文时恢复原连接类型。不能把“tls:false”作为通用加速方案，也不能移除香港出口所需的协议层。

下一项应由唯一设备负责人做短时读回：检查当前内核、`fs.pipe-max-size`、`fs.pipe-user-pages-soft` 与 `fs.pipe-user-pages-hard`，以及本机已有的 syscall 观测能力。在固定目标、完整字节与代理健康已通过的同一短测窗口内，确认 Ninja 到 UA3FLocal 的数据期实际是否调用 splice。优先复用已有诊断工具；不为本轮自动安装 strace 或增加二进制。

若 splice 正常运行，应停止围绕 32 KiB 缓冲或关闭统计试改，继续定位调度、IRQ、loopback 多腿、TCP 窗口或当前私有包装的真实成本。若观察到大流量期仅 read/write，再定位具体不可拆包装或 EINVAL/ENOSYS，不能只凭 743～790 Mbps 推断零拷贝失败。

未找到的范围：在上述固定版本缓存对 `Relay|Copy|CopyBuffer|BufferedConn|Experimental|experimental|ReadBuffer|WriteBuffer|SetReadBuffer|SetWriteBuffer|Replaceable|Upstream|Unwrap|Mark` 做限定 `rg` 查询，并读取命中函数及 sing 直接复制、Linux splice、网络拆包和缓冲常量文件。结论只覆盖这些源码与字段，不覆盖 Ninja 未公开的实现。