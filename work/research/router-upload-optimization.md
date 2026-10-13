# 上传拥塞的实际对照与当前决定

核对时间：2026-10-13，Asia/Shanghai。主代理已执行两轮限量随机数据上传；本支线只读取结果、重新计算字节／速率／原始 ping，并关联已有路径观测，没有增加请求、SSH 或修改生产配置。当前两份主文档保持不变。

**本轮未出现支持新增上传 SQM 的排队证据，维持当前无上传整形状态。** 两轮 POST 均完整成功，第二轮的单连接与四个并发请求已按端口确认经过 HK02；第一轮没有链路观测。它们是相同透明生产策略下的两次有界样本，不能写成国内 DIRECT 与香港代理的速度对照，也不能证明两个校园账号均已满载。

## 字节、时长与完成情况

每轮包含 1×100 KiB 协议探针、1×32 MiB 单连接、4×20 MiB 并发，随机 body 在本地生成。单请求连接超时 3 秒、总超时 20 秒、无重试，响应限制 4 KiB；没有读取或上传私密文件。电脑 curl 使用 `--noproxy '*'`，只证明未使用电脑显式代理，路由器透明路径由另行观测解释。

12 个 POST 全部退出码 0、HTTP 200、TLS 校验结果 0，size_upload 与各 body 精确相同，响应字节均为 0。每轮完成 117,542,912 字节，合计 **235,085,824 字节，即 224 MiB＋200 KiB**，低于 256 MiB；本轮预算已使用完毕，不再追加负载。

| 批次 | 32 MiB 单连接：完整墙钟时间／速率 | 4×20 MiB 并发：完整批次时间／速率 | 路径证据 |
| --- | --- | --- | --- |
| 第一轮，01:00 开始 | 5.062 秒／53.03 Mbps | 12.125 秒／55.35 Mbps | 没有对应核心连接观测，不能标为国内直连 |
| 第二轮，01:03 开始 | 4.875 秒／55.06 Mbps | 11.281 秒／59.49 Mbps | 单连接及四个并发请求均匹配 HK02；100 KiB 探针未被抓到 |

速率重新以完整 payload 字节数×8÷批次墙钟时间计算；并发分母是整个批次完成时间，不平均四个请求的单独速度，也未扣除 TLS／首字节。两轮的差异不能归因于生产参数调整，不能作为稳定日常上传速率或账号限速值。HTTP 200＋发送字节相符证明本次客户端发送与成功响应，不属于远端持久存储校验。

安全摘要和源文件 SHA-256 位于 [router-upload-summary.json](../deploy/router-upload-summary.json)。两份原始结果为 [第一轮](../deploy/upload/20261013T010004-transparent-20261013/result.json) 和 [第二轮](../deploy/upload/20261013T010317-observed-20261013/result.json)。摘要不保存公网源 IP、认证、订阅或完整节点身份。

## 原始 ping 的复核

脚本各启动一个独立 ping.exe 进程，目标为网关 192.168.31.1 和国内公网 223.5.5.5，idle 15 秒、recovery 8 秒。原始文本为 cp936；本支线从原始中文／英文时间行重新计算，各阶段统计与 result.json 一致，没有使用既有多目标 IcmpSendEcho 的损包统计。

| 目标与批次 | idle：median／P95，回复数 | concurrent：median／P95，回复数 | recovery：median／P95，回复数 |
| --- | --- | --- | --- |
| 公网，第一轮 | 10／27 ms，15 | 9／17 ms，12 | 9／42 ms，8 |
| 公网，第二轮 | 10／48 ms，15 | 10／18 ms，11 | 10／13 ms，8 |
| 网关，第一轮 | 1／4 ms，15 | 1／19 ms，12 | 4／44 ms，共 8（精确 RTT 7；<1 ms 1） |
| 网关，第二轮 | 1／54 ms，15 | 1／9 ms，11 | 1／18 ms，8 |

表中 exact median／P95 排除 <1 ms 的上界值；第一轮网关 recovery 共 8 个回复，其中 7 个提供精确 RTT，另 1 个只给 <1 ms。各窗口没有超时／不可达失败行。由于每个阶段仅约 5～15 个回复，P95 接近最大值，不能据此证明长期稳定或长期损包率。

两轮公网 median 均约 9～10 ms，并发 P95 均低于 idle P95，没有“上传开始后持续升高、停止后恢复”的可复核模式。第一轮 recovery 的孤立高值也不是上传时排队证据。网关有零星较高样本，不能单凭其最大值定位公网瓶颈。

**国内公网 ICMP 不经过 HK02 代理隧道。** 此结果仅观察该 ICMP 路径在上传期间的变化，不能证明远端代理路径的满载延迟。第二轮未额外执行通过同一 HK02 的持续小请求延迟对照，也未进行 QUIC／UDP、其它上传源或长时间负载验证。

## 路径与两出口覆盖

[既有路径观测](../deploy/router-upload-path-observation.json) 的窗口为约 40.75 秒，包含 idle、上传、recovery 和背景流量。第二轮 result 的 local_port 与 sink_connections.source_port 逐项匹配，且观测时间落在对应请求的实际运行区间内；一条 32 MiB 与四条 20 MiB 请求均出现 HK02 chains。100 KiB 探针持续约 0.2 秒，没有在采样中出现，不能倒推其链也已独立验收。

该窗口物理 `wan` 的 TX 增量为 **137,364,810 字节**，macvlan `eswan2` 为 **713,913 字节**。`eswan2` 还会经过底层 `wan`，两计数不能相加，也不能作为两账号上传均满载的证据。应用 payload 是本次有效吞吐的主证据；接口计数用于说明观察窗口主要由物理 `wan` 承接，未证明第二逻辑出口承担足够负载。

读取的 root qdisc 为 noqueue，采样没有显示该观察点的软件 backlog／drops；这不能说明运营商、校园网或远端不存在队列。四个客户端请求不保证四条代理外层连接，也不保证普通 MWAN／UA3F 轮换覆盖；本轮未修改既有 mark 或路由策略。

目前无法从此 sink 区分校园账号、跨境线路、HK02、隧道复用或 Cloudflare 服务端各自的容量边界。因此 **53～59 Mbps 的样本不是已确认的本地上行容量，更不是双出口饱和速率**。

## 官方端点与协议边界

使用 `POST https://speed.cloudflare.com/__up?bytes=N`，发送 N 字节原始 body。Cloudflare 官方客户端采用该协议，默认上传规格包含 100 KB、1 MB、10 MB、25 MB、50 MB（十进制）。核对上游 SHA 为 `323da2ea5697ab4953f2c90c931125ac35d019d8`。[官方 README](https://github.com/cloudflare/speedtest/blob/323da2ea5697ab4953f2c90c931125ac35d019d8/README.md)、[请求实现](https://github.com/cloudflare/speedtest/blob/323da2ea5697ab4953f2c90c931125ac35d019d8/src/engines/BandwidthEngine/BandwidthEngine.ts)、[默认测试](https://github.com/cloudflare/speedtest/blob/323da2ea5697ab4953f2c90c931125ac35d019d8/src/config/defaultConfig.ts)

这些公开文件未公布该测速端点的硬性字节、QPS／并发配额或 SLA。50 MB 是默认请求规格，不是已证实服务硬上限；普通 Cloudflare 客户站点套餐的上传限制不能套用。两轮现场 HTTP 200 只确认本次协议及可达性，不保证后续不限流或它能饱和国内 DIRECT 路径。此次使用 HTTP/1.1，不安装测速软件、不提交 `/__results`。

## 无 SQM 决定及以后复核条件

现有下行 HTB＋fq_codel／IFB 和半量 AQL 已撤回；本轮没有新增上传 qdisc、IFB、持久 SQM 服务或限速规则。上传样本未显示新增整形的收益依据，继续保留原队列。无排队证据与未验证双出口满载同时成立，不能将结论扩大成“所有上传都没有 bufferbloat”。

以后只有在实际业务反复出现上传引发延迟，且对应逻辑出口的负载和路径已明确时，才另开有界对照。若那时需要整形，本拓扑应先核对现有 qdisc／卸载与现场分类计数。Linux 6.18 的 `macvlan_queue_xmit()` 把 skb 转交 lowerdev，再进入 `dev_queue_xmit_accel()`；不能在 wan／eswan2 各叠相同 shaper 而忽略重复约束。[对应版本 macvlan 源码](https://github.com/torvalds/linux/blob/v6.18/drivers/net/macvlan.c)

可审查方向仍是物理 wan 上一个根整形器，按当前两出口 NAT 后源 IPv4 分独立类、各附 fq_codel，并保留明确定义的通行类；source-IP 分类不占用 MWAN／UA3F mark，无需 IFB。它没有在本轮安装、验证命中或证明收益；动态 DHCP 分类与回退须由既有生命周期管理，不能把旧 IP 或本轮上传速率直接写成持久参数。
