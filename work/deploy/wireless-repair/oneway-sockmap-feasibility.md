# UA3F 单向下载 sockmap 的源码可行性

数据方向可用现有 BPF 程序表达：只配置 RConn cookie → LConn cookie，上传侧没有 peer 项，仍由 ProcessLR 读取、解析并改写连续 HTTP 请求。但固定 v3.7.0 没有完整的单向安装与结束协调；不能把此方案作为一个可立即部署的开关。尤其 RConn EOF 不能证明下载字节已离开目标 sockmap backlog，直接沿用 CopyRL 的 CloseWrite 会有截断风险。

只读固定 UA3F v3.7.0 annotated tag `6cc2b01433beff96b5e65df587b765904fa9b510` 指向的提交 `e464514ab313e3afe308881d7e5732a5baf41ce2`，及 Linux `v6.18.55` 原始源码。通过 Agent Reach 的 GitHub／gh API 路由读取，没有 SSH、测速、生产 patch、二进制或共享配置修改。本文只保存这份报告。当前吞吐、CPU 与 Windows rwnd 数据是主任务提供的背景，本文没有独立运行验证，也不据此断言唯一根因或预测提速。

## 精确 map 与方向

| 对象 | 单向下载的内容 |
| --- | --- |
| sockhash | `lc:uint64 → LFD:uint32`，`rc:uint64 → RFD:uint32`；两端均须加入。 |
| peer | 只含 `rc:uint64 → lc:uint64`；绝不添加 `lc → rc`。 |
| R 接收 | verdict 获取 rc，查到 lc，调用 `bpf_sk_redirect_hash(skb,sockhash,&lc,0)`，选择 L 的发送路径。 |
| L 接收 | verdict 获取 lc，查不到 peer，返回 SK_PASS；ProcessLR 仍得到上传请求并逐次改 UA。 |

`flags=0` 是目标 egress。改成 BPF_F_INGRESS 会把响应放入 L 的接收路径，混入上传解析，不能采用。现有 stream_parser 返回 skb 长度，不识别 HTTP；连续请求的改写依赖保留 ProcessLR，而非 BPF 协议判断。

来源：[现有 BPF 程序](https://github.com/SunBK201/UA3F/blob/e464514ab313e3afe308881d7e5732a5baf41ce2/internal/bpf/sockmap/sockmap.c)、[Linux sockmap 文档](https://github.com/gregkh/linux/blob/v6.18.55/Documentation/bpf/map_sockmap.rst)。

## 最小数据路径改动

可实现的最小实验改动是新增 `Sockmap.AddDownload()`，复用现有 C 程序。为避免 R 先进入 parser 而 peer 尚未准备，顺序必须是：取得并缓存两端 FD/cookie → 插入 L sockhash → 插入 `peer[rc]=lc` → 最后插入 R sockhash。失败逐项恢复已安装项；不得用 Add() 后再删除 peer[lc]，因为中间窗口已经双向转发上传。

ConnLink 应新增 `None/Download/Both` 模式与独立 RL done/error 状态；不能让一个 Offloaded bool 同时表示双向复制完成。成功安装 Download 后，后续首次非 HTTP 分支的 TryOffload 不能升级成 Both；上传仍走用户态。Delete 应使用安装时缓存的 cookie，避免关闭 FD 后重新取 cookie 失败而留下 peer 项。

初始 HTTP 安装必须在第一份请求写入 R 之前，而且在启动普通 CopyRL 前。当前 GLOBAL 入口已经先启动 `go CopyRL()`，再进入 ProcessLR；不能在请求已发出、响应正在复制时插入单向映射。安全的窄实验可以只选择已确认的明文 HTTP、无 MitM、无响应改写的目标：延后该分支 RL 启动，在 HTTP 分类成功且第一份 Request.Write 前一次性安装；失败才启动原 CopyRL。ProcessLR 的所有早退／defer flush 分支都须先启动其原 RL fallback。不能对任意 server-first 协议延迟 RL，否则等待服务端 greeting 的客户端会被饿死。

已经运行的 CopyRL 不具备取消、暂停和排空协议，不能靠 deadline 打断后马上切换；原 defer 会调用 CloseRL，关掉 R 读端及 L 写端。需要冷连接安装，或另外实现明确的停机屏障。这也是本轮不制作生产补丁的理由。

来源：[Sockmap.Add](https://github.com/SunBK201/UA3F/blob/e464514ab313e3afe308881d7e5732a5baf41ce2/internal/bpf/sockmap/sockmap_linux.go)、[GLOBAL 与连续请求](https://github.com/SunBK201/UA3F/blob/e464514ab313e3afe308881d7e5732a5baf41ce2/internal/server/base/server.go)、[CopyRL 与 CloseRL](https://github.com/SunBK201/UA3F/blob/e464514ab313e3afe308881d7e5732a5baf41ce2/internal/common/connlink.go)。

## FIN 与关闭：当前不满足的条件

Linux `sk_psock_skb_redirect()` 将 skb 排入目标 psock 的 ingress_skb，并调 delayed_work；backlog 在目标不可写时 EAGAIN 并延后重试。因此 redirect 接受、R 接收 EOF、L 已接受全部字节三者不等价。Linux `tcp_bpf_recvmsg_parser()` 有 FIN／EOF 接收处理，但没有把另一条 L TCP 的半关闭同步完成给 UA3F。`sock_map_close()` 会停止 psock 并取消其 work；这不是排空成功确认。

成功 offload 后不能继续让普通 io.CopyBuffer 作为下载正文的另一消费者。可新增仅使用普通 R.Read 的控制 goroutine 等待 EOF／错误；若意外读出正文，必须标为安装契约失败，不能无条件写给 L 后继续混合内核转发，以免乱序。该控制 goroutine 也不能在收到 EOF 后立刻 CloseWrite(L)：仍缺少目标 backlog 排空屏障。

完整生命周期至少需要：LR 完成只关闭 R 写端，保留下载；R EOF 后确认所有重定向正文已被 L 接受，才能关闭 L 写端；两方向协调完成后才删除 maps、释放 FD。当前 ServeConnLink 返回时直接 defer DeleteOffload，不等待 CopyRL，因此原生命周期不能原样搬进单向方案。TryOffload 注释提到 OffloadDone，但固定 ConnLink 没有该字段，实际成功路径仍启动两向复制；注释不是完成机制。

当前 BPF maps 没有转发字节计数、完成事件或 backlog 排空读回。要形成生产候选，必须补一个能证明 L 已接受全部重定向字节的机制并验证 FIN／RST／背压；单凭 R EOF、sockhash 删除成功、TCP send queue 暂时为零或固定延时均不足。若只能完成 rc→lc 映射而不能提供此屏障，否决生产部署，保留原下载 splice 路径。

来源：[异步 backlog 与 EAGAIN](https://github.com/gregkh/linux/blob/v6.18.55/net/core/skmsg.c)、[接收 FIN](https://github.com/gregkh/linux/blob/v6.18.55/net/ipv4/tcp_bpf.c)、[map 删除与关闭](https://github.com/gregkh/linux/blob/v6.18.55/net/core/sock_map.c)、[TryOffload 实现](https://github.com/SunBK201/UA3F/blob/e464514ab313e3afe308881d7e5732a5baf41ce2/internal/server/base/server_linux.go)。

## 通过或否决的依据

后备实验须验证同一连接至少两份 HTTP 请求都改成目标 UA；下载正文完整、保序，无重复或漏字节；客户端先半关闭仍能收完；服务端 FIN、RST 和慢客户端背压不截断；完成后 peer/sockhash 与 goroutine 均清理。原三路、香港规则、外层 SO_MARK 与 TTL 保持原合同。BPF load/attach 成功、kernel 版本或短窗吞吐不能替代这些验收。

任一条件不满足，或者安装时已有 R 用户态缓存、无法停止原复制、缺少关闭屏障、路径需要响应改写／MitM，则否决该连接的 offload。本文确认单向数据路径有明确最小实现，但确认当前固定上游缺少完整生产生命周期；没有给出可立即部署的源码补丁，也没有把 Buffer 或算法参数当作已确认原因。