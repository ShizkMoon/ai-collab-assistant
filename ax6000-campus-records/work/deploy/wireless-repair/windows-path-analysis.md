# Windows BE200 与 TCP 接收路径分析

当前证据支持保留 Windows TCP 接收窗口自动调节和 RSC，并把 BE200 的 No SMPS 作为后续单项对照候选。Throughput Booster 只改善客户端上传，不适合用来修复本轮下载。当前 WLAN 驱动没有可用的 RSS 控制，不能套用有线网卡的 RSS 队列、CPU affinity 或注册表方案。本文只整理已有只读结果与官方来源，没有修改 Windows、驱动或路由器。

## 已知状态与证据边界

| 对象 | 已有只读结果 | 可以得出的结论 |
| --- | --- | --- |
| 无线网卡 | Intel Wi-Fi 7 BE200 320MHz，驱动 24.60.0.3 | 这是本机已安装版本；本次没有核对其是否为最新版本，也没有升级 |
| 无线链路 | 已保存样本为 5 GHz、802.11ax、收发 PHY 2402 Mbps；RSSI 约 −37～−39 dBm | 当时有足够的协商速率余量；PHY 与信号不能证明正文下载达到 900 Mbps |
| Windows TCP 自动调节 | `normal` | 当前没有“自动调节关闭”的证据；保留此值 |
| Windows TCP heuristics | `disabled` | 已关闭自动调节启发式限制；无需再次执行相同设置 |
| WLAN RSC | IPv4 / IPv6 的 Enabled、Supported、Operational 均为 true，FailureReason 为 NoFailure | 当前没有 RSC 未启用或报告失效的证据；保留，不能仅凭此认定实际测试流量全部发生合并 |
| WLAN RSS | 已有只读发现为不支持 / 无可用配置 | 本机此驱动组合不能按有线 RSS 调节；这不等于所有 BE200 型号、驱动和系统都永久不支持 RSS |
| BE200 高级属性 | No SMPS、Throughput Booster 等候选需要以当前驱动实际公开的名称和值为准 | 当前文档不补写未保存的属性原值，也不推定注册表数值映射 |

TCP、RSC、RSS 和驱动版本沿用本任务主线已经取得的只读结果。本文件没有再次查询设备；这些字段的完整原始输出应随主线结果保留。无线样本可直接回看 [fixed-path-cases.json](fixed-path-cases.json)、[fixed-path-steering-cases.json](fixed-path-steering-cases.json) 中的 `windows_wireless_before`。文件中的 SSID、MAC、GUID 等设备标识无需复制进结论文档。

## Windows TCP：先核对真实连接，不重复开启已有功能

Microsoft 将 TCP 接收窗口自动调节的 Normal 列为默认级别，用来让接收窗口适应连接需求。当前已经是 Normal，因此没有依据切换 Experimental、固定大接收窗口或套用旧式注册表优化。该来源属于 Windows Server 的机制说明；本文仅用于解释 TCP 窗口，不把服务器网卡调优清单当作 BE200 配置标准。[Microsoft：TCP receive window autotuning](https://learn.microsoft.com/en-us/windows-server/networking/technologies/network-subsystem/net-sub-performance-tuning-nics#tcp-receive-window-autotuning)

窗口是否限制某条下载，要看该连接的实际 RTT、接收窗口和发送端是否 rwnd-limited。所需窗口约等于目标字节速率 × RTT。例如 900 Mbps 对应 112.5 MB/s，RTT 为 1 ms 时约需 112.5 kB，5 ms 时约需 562.5 kB；这只是带宽时延积计算，不是本机测得的窗口。若路由器上的代理终止 PC 的 TCP，再建立远端连接，PC 接收窗口约束的是 PC ↔ 路由器连接；远端 outer TCP 的接收、发送与拥塞控制属于路由器。不能把远端 RTT 直接套进 Windows 内层连接，也不能用 Windows 的接收设置解释 Linux outer socket 的全部行为。

后续只读验收可以按实际目标 IP / 端口定位连接，再用发送端 `ss -tinm` / TCP_INFO 中可取得的 rwnd、cwnd、重传、app-limited 或 buffer-limited 信号判断。`Get-NetTCPConnection` 可以确认连接状态、地址、端口、进程和 AppliedSetting；它本身不提供每条连接的完整 cwnd / 接收窗口证据。不同 TCP 模板可能覆盖不同连接，不能只看全局 `netsh` 就认定每条下载都使用同一个模板。[Microsoft：Get-NetTCPConnection](https://learn.microsoft.com/en-us/powershell/module/nettcpip/get-nettcpconnection)

## RSC 与 RSS：保留已工作的接收合并，避免不存在的队列配置

RSC 把接收的多个 segment 合并后交给协议栈，可减少处理开销。当前 IPv4 / IPv6 均为 Operational 且 NoFailure，应保留现状。只有同窗测量显示接收 CPU / DPC 异常并能重复关联 RSC，才值得在另一个单项窗口做关闭后恢复的对照；本轮没有这种证据，也不应为了测速先关闭卸载、防火墙或 WFP 过滤器。[Microsoft：Get-NetAdapterRsc](https://learn.microsoft.com/en-us/powershell/module/netadapter/get-netadapterrsc)

RSS 分散接收处理需要 NIC 和 miniport 驱动的相应能力；它与 RSC 是不同机制。当前 WLAN 的 RSS 不支持结果不能通过全局 `rss=enabled` 或伪造注册表键变成硬件多队列。不要对本机 WLAN 执行 `Set-NetAdapterRss`、增加 RSS 队列、指定 RSS CPU 或借用 Ethernet 的 affinity。若后续真实测试出现 Windows 单核持续满载，应先保存 CPU / DPC / 进程同窗证据，检查驱动公开能力，再判断是否需要驱动维护；没有证据时不升级或重装。[Microsoft：Introduction to Receive Side Scaling](https://learn.microsoft.com/en-us/windows-hardware/drivers/network/introduction-to-receive-side-scaling)

## BE200 高级设置的具体候选

Intel 的高级属性说明给出三个与本轮相关的机制：No SMPS 保持所有接收天线工作；Dynamic / Static SMPS 会限制接收天线活动；Throughput Booster 通过客户端发包突发改善上传；U-APSD 在部分 AP 互操作场景下可能降低 RX 吞吐。Intel 给出的 No SMPS 低吞吐绕行说明主要涉及部分旧 AP，不能直接证明当前 AX6000 有同一问题。[Intel：Advanced Wireless Adapter Settings](https://www.intel.com/content/www/us/en/support/articles/000005585/wireless/legacy-intel-wireless-products.html)

| 设置 | 本轮处理 | 理由与验收 |
| --- | --- | --- |
| MIMO Power Save Mode → No SMPS | 优先的客户端单项候选；先读回原值。原值已是 No SMPS 时跳过 | 对照是否有更高、可重复的 LAN 完整正文吞吐，同时看 AP station TX bitrate / 重试增量；只改这一项并恢复原值。不能把高 PHY 自动归因于 No SMPS |
| Throughput Booster / Throughput Enhancement | 下载任务保留 Disabled；不作为下载修复 | Intel 明确限定收益为客户端 → AP 的上传。若当前意外启用，可作为另一项独立对照；不与 No SMPS 同时改 |
| U-APSD Support | 若当前 Disabled，保留；只有当前 Enabled 才列为后续独立候选 | 官方说明存在部分 AP 的 RX 互操作问题，但尚未证明本机遇到该问题。先保存原值，再单项关闭与恢复 |
| 5 GHz Channel Width | 保留 Auto | AP 决定实际宽度。BE200 标称 320 MHz 不意味着当前 5 GHz / 802.11ax AP 支持 320 MHz；不能在客户端强行选择来获取 900 Mbps |
| 802.11n/ac/ax 模式、发射功率、漫游 | 沿用当前正常模式，核对相应默认值；不与上述候选一起改 | 当前已经协商 802.11ax。发射功率主要作用于客户端发射；固定位置的下载不支持先改漫游、开启 Booster 或叠加模式变更 |

Intel 的 802.11ax 参照值为 5 GHz 宽度 Auto、漫游 Medium、Booster Disabled、发射功率 Highest、无线模式 802.11ax。该页面是 802.11ax 的默认 / 恢复参照，不是为本机 BE200、Windows 版本和 AX6000 组合完成的性能认证。实际驱动可能提供更新的模式枚举，保留已协商正常的配置。[Intel：Recommended Settings for 802.11ax Connectivity](https://www.intel.com/content/www/us/en/support/articles/000057574/wireless.html)

## 后续单项对照的执行条件

本支线只交付候选；设备设置仍由主线唯一负责人顺序操作。修改高级属性可能重启 WLAN、短暂断连，因此不能在主线下载或其他设备变更同时运行时修改。先核对当前高级属性及可选值，按驱动公开的 DisplayName、RegistryKeyword、ValidDisplayValues / ValidRegistryValues 保存原值；不要从另一张 Intel 网卡猜测 No SMPS 的数值，也不要直接写未知注册表路径。[Microsoft：Get-NetAdapterAdvancedProperty](https://learn.microsoft.com/en-us/powershell/module/netadapter/get-netadapteradvancedproperty)

下面是 Windows PowerShell 的只读复核示例，本文没有执行。实际网卡名称应先与本机对应；当前已有名称为 `WLAN`。

```powershell
Get-NetAdapterAdvancedProperty -Name 'WLAN' -AllProperties |
    Where-Object RegistryKeyword -Match 'MIMO|SMPS|UAPSD|Throughput|Power' |
    Format-List DisplayName,DisplayValue,RegistryKeyword,RegistryValue,ValidDisplayValues,ValidRegistryValues

Get-NetAdapterRsc -Name 'WLAN' | Format-List *
Get-NetAdapterStatistics -Name 'WLAN' | Format-List *
Get-NetTCPSetting | Select-Object SettingName,AutoTuningLevelLocal
netsh interface tcp show global
netsh interface tcp show heuristics
```

先复用当前固定发送器和完整正文的纯 LAN 测试，保持位置、电源状态、5 GHz AP、频宽、源文件、总字节、并发和路由器状态一致，做原值 A → 单个候选 B → 原值 A。每次读取完整正文，并记录耗时、每秒速率、CPU / DPC、网卡错误与丢弃增量、AP 速率及重试增量。网卡累计错误 / 丢弃数不能直接当成本轮丢包率。[Microsoft：Get-NetAdapterStatistics](https://learn.microsoft.com/en-us/powershell/module/netadapter/get-netadapterstatistics)

只有 B 的提升超过前后 A 的自然波动，并且没有明显重传、延迟或连接退化，才支持保留候选。若 B 退化、断连、正文不完整，恢复保存的原值并结束该项；不要继续叠加另一组设置。No SMPS 的收益还应在后续正式下载中复现，才能称为客户端路径改善。

公网 900 Mbps 验收另需遵守 [wifi-path-analysis.md](wifi-path-analysis.md) 中的真实 outer、固定端点、并发、CPU 与限速控制。当前 650 Mbit 下载 CAKE 必须由主线按既定窗口临时处理并恢复；客户端调整无法跨过这项限速。LAN sender、PHY 2402、RSC Operational 或一次峰值均不能代替无线 PC 的连续 30 秒完整正文 900 Mbps 验收。

本文使用 Agent Reach 的网页读取通道取得 Intel / Microsoft 原始页面；只引用实际取得的正文。没有新增软件、修改系统设置或执行压测。
