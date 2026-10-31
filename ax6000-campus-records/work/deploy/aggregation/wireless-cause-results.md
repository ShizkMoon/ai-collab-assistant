# 无线电脑与路由器本机速度差异的原因判断

**当前不能把电脑低速判为学校检测到共享后限速。** 已确认的影响是实际 CDN／目标路径变化，以及部分完整电脑批次的单核／softirq 压力。防检测采用的软件代理路径存在本地成本，但尚未分离其独立损失；本机 UA3F 超过 900 Mbps 也不覆盖无线转发和资源竞争。

| 判断对象 | 当前结论 | 证据和范围 |
| --- | --- | --- |
| 学校检测后主动限速 | 没有直接证据 | 没有检测命中或限速通知；没有同端点、仅改变特征的对照。不能由 PC 慢、本机快直接推出该原因 |
| UA3F 自身固定上限为两三百 Mbps | 本机固定目标不支持此说 | 本机 UA3F 902.30 Mbps，紧邻裸三路 908.67 Mbps；约 7 秒完整批次，未证明持续无线 900 |
| 完整无线代理路径的处理压力 | 部分批次有强信号 | PC 352.73 Mbps 组 CPU2 平均 busy 96.4%、softirq 89.9%；PC 169.60 组没有核心≥90%，不能解释所有慢样本 |
| 实际来源／到来源的路径不同 | 已确认是重要对照变量 | 固定快端点本机裸三路 921.67／908.67；另一端点裸三路 146.25 且 CPU 平均 18.2%；不能把全部差值算给无线 |
| 无线空口是唯一根因 | 未确认 | 当前纯 LAN 567～605，历史 LAN 869～886；包含服务器和 TCP 处理，既不能称硬件上限，也不能用 PHY 2402 替代正文速度 |
| 日常 CAKE 650 限制持续应用 900 | 确定的当前配置条件 | 快本机数据是在临时停用 CAKE 时取得；原队列已经恢复。当前公网 PC 162～353 又远低于该队列的大包净正文上界 |

路由器本机测试的主要路径是 curl→UA3F→WAN；无线电脑还要经 Wi-Fi→OpenClash→loopback TCP→UA3F→WAN，再经过返回方向的多个处理段。两者的 CPU 工作和实际源站都必须一致后才能分摊差额。本机 UA3F 比裸三路只慢约 0.7%，整机平均 busy 却从约 33.7% 增到 57.5%；它显示代理工作消耗资源，不能把全部差额叫作 UA 字段替换开销。当前独立 TTL64 在内核 postrouting，HTTP UA 改写在请求层；关闭 WED、flow offload 与 socket sockmap 是不同机制。

当前 RAM→无线 LAN 三组整机 busy 为 19.3%／23.1%／26.5%，平均最忙核为 42.6%／52.6%／50.4%。这个没有经过学校公网的路径已经高于此前 PC 公网速度，证明无线链路不是两三百 Mbps 的固有上限。它仍不证明当前纯无线具有稳定 900 的余量。

最近 PC 213.50 Mbps 窗口全局 TCP RetransSegs 增加 17,469，其他 PC 窗口为 39～202；它混合路由器本地多个 TCP 段和背景流量，不能全部算成 Wi-Fi 丢包。所有聚合窗口 softnet dropped 增量为 0；高 softirq 是处理时间信号，不能直接等同丢包。RPS 按流哈希分配 CPU，跨核通知也有成本，不保证每条流均分到全部核心。[Linux 收发扩展文档](https://docs.kernel.org/6.18/networking/scaling.html)

无线数字 SOCKS 小预检已实际执行：12 条各 8 MiB、每条主动限为 1 MiB/s，96 MiB 正文全部完整；Windows 地址确认属于 WLAN，邻居 IP、AP station MAC 和授权状态匹配。全部自有源端口的核心链含 UA3FLocal，核心 metadata 同时显示指定数字 IP 和下载域名，但采样没有该数字 IP 的 UA3F 外连，因此真实 outer 没有固定。这与 redir-host 填域名后下游再次解析的候选机制相符，私有核心的具体分支未确认；保存运行配置没有 sniffer 段，不能直接称为 Host 嗅探。程序在预检处停止，没有关闭 CAKE，也没有运行新吞吐对照。98.46 Mbps 是人为限速的预检结果，不能当作电脑性能。[原始预检](wireless-fixed-cases.json)、[代理路径审阅](wireless-proxy-path-review.md)。

后续定位全程保留无线、现有位置、信道、认证、UA3F 和 TTL。先取得并核对真正固定 Internet 外层端点的测量路径，再比较本机 UA3F、本机 OpenClash→UA3F 和无线电脑的完整路径，同时记录每核、进程、分腿 TCP 重传及 station 增量。核心 destinationIP 或 curl 参数都不能单独作为固定外层的证明；没有已确认的每连接禁止重解析开关，不猜参数或全局清缓存。不要求改用有线，也不以关闭防检测为前提。900 目标还需调整公共整形预算，在最终无线电脑路径取得重复持续正文窗口。

本轮实际只执行 12×8 MiB 的限速预检及只读验收，没有 CAKE 停用、认证或核心重启、卸载改动、全局 DNS 改动、固件改动或新大下载对照。Windows 绑定 IP 属于 WLAN，邻居行与 AP station MAC 一致。收尾 diagnostic_state_preserved=true：配置文件摘要、三个认证 PID、UA3F／核心 PID、三路 online、双向 650／unlimited 队列与业务 HEALTHY 均保持，国内／代理请求 200／204。原 gdpu DNS 失败从先前验收保留，本轮未重测。

证据：[原性能报告](results.md)、[本轮限速预检](wireless-fixed-cases.json)、[本轮只读验收](wireless-final-acceptance.json)、[样本重算](wireless-sample-analysis.md)、[防检测分层](wireless-antidetection-analysis.md)、[代理入口审阅](wireless-proxy-path-review.md)。本轮没有证明唯一根因、学校未使用任何识别技术或无线稳定 900 Mbps。
