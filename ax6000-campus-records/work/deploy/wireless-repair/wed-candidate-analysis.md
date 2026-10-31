# AX6000 WED 候选：软件策略保留、在线边界与精确回退

WED 可以成为本机减少无线 DMA／完成处理成本的独立候选，无须同时开启软件或硬件 flow offload。固定源码支持：在没有 PPE／TC／flowtable 硬件流的情况下，既有 UA3F、本机 nft TTL 64 与 WAN／IFB CAKE 仍可走软件路径；软件下行的 AQL 也没有因 WED 参数自动关闭。它不能承诺解决核心代理＋UA3F 的全部 CPU 开销，也不能承诺达到 900 Mbps。

从当前 N 到真正活跃的 Y，必须重新 probe 无线设备。单写 sysfs Y 或普通 wifi reload 不会 attach WED。`wifi down → rmmod mt7915e → modprobe mt7915e wed_enable=1 → wifi up` 是具体可用候选流程，会中断该驱动的两频无线。若“在线安全”要求 WLAN 不断，则本候选不符合。若允许短暂 WLAN 重建但认证不能重启，必须先核对下述 Ethernet DMA 一致性条件和本机恢复能力；本次分析不能替代这个实时读回。

本文没有 SSH、设备修改、试启用、认证操作或固件更新，只提供供主线决定的步骤和退出策略。

## 固定版本与实际硬件

- OpenWrt `r37185-f29dfe25ba`，构建提交 `f29dfe25baaa5c03f2b52f49dfdc12ed99abe8df`。
- Linux 6.18.55，由固定 [kernel-6.18](https://github.com/openwrt/openwrt/blob/f29dfe25baaa5c03f2b52f49dfdc12ed99abe8df/target/linux/generic/kernel-6.18) 确定，不引用当前 master 代替。
- mt76 `467ae2e3f190baf737e15e318906da0dc7d0ab91`，见固定 [mt76 Makefile](https://github.com/openwrt/openwrt/blob/f29dfe25baaa5c03f2b52f49dfdc12ed99abe8df/package/kernel/mt76/Makefile#L9)。
- mac80211 backports 7.2-r5，见固定 [Makefile](https://github.com/openwrt/openwrt/blob/f29dfe25baaa5c03f2b52f49dfdc12ed99abe8df/package/kernel/mac80211/Makefile#L13)。本地 archive 的 SHA256 与其 `PKG_HASH` 一致：`6ec76a4cb0988b5382b2fc5053610a56ada90b8ef6a5a4f2807cd433badb9454`。
- Redmi AX6000 stock 是 MT7986 集成 WMAC、使用 `mt7915e` 模块。固定 [板级 DTS](https://github.com/openwrt/openwrt/blob/f29dfe25baaa5c03f2b52f49dfdc12ed99abe8df/target/linux/mediatek/dts/mt7986a-xiaomi-redmi-router-ax6000.dtsi#L277) 和 [SoC probe](https://github.com/openwrt/mt76/blob/467ae2e3f190baf737e15e318906da0dc7d0ab91/mt7915/soc.c#L1242) 对应 AXI `mt798x-wmac`。不要采用 PCIe 卡的 unbind 路径或把模块名当作旧 MT7915 芯片型号。

Linux 原始部分以 [稳定版 v6.18.55](https://github.com/gregkh/linux/tree/v6.18.55) 为基准，并检查固定 OpenWrt mediatek 6.18 patch 路径；其中 940–946 处理 WO 保留内存／cpuboot／ILM／DLM 的节点兼容。这些与正确 DTS／WO firmware 可用性有关，不能用泛称“Linux 支持 WED”跳过本机初始化验收。

## WED 活跃改变什么

[mt7915/mmio.c:16–18、633–734](https://github.com/openwrt/mt76/blob/467ae2e3f190baf737e15e318906da0dc7d0ab91/mt7915/mmio.c#L633) 中，`wed_enable` 默认 false、可写，但仅在初始化函数内判断。成功 attach 后才把无线 IRQ 与 `dma_dev` 改为 WED；attach 失败还可返回 0 回落普通驱动。因此 `wed_enable=Y` 既不证明 attach，也不证明正文由 WED DMA 处理。

活跃时 [mt7915/dma.c](https://github.com/openwrt/mt76/blob/467ae2e3f190baf737e15e318906da0dc7d0ab91/mt7915/dma.c#L11) 将 TX ring、TX-free 和有 RX 能力的 RX ring 接入 WED；[mac80211.c:1595](https://github.com/openwrt/mt76/blob/467ae2e3f190baf737e15e318906da0dc7d0ab91/mac80211.c#L1595) 改变软件 RX reorder 分支；[init.c:412](https://github.com/openwrt/mt76/blob/467ae2e3f190baf737e15e318906da0dc7d0ab91/mt7915/init.c#L412) 声明 `NETIF_F_HW_TC`；[main.c:1815](https://github.com/openwrt/mt76/blob/467ae2e3f190baf737e15e318906da0dc7d0ab91/mt7915/main.c#L1815) 提供 `DEV_PATH_MTK_WDMA` 给卸载路径。因此准确说法是“先接入 WED 的无线 DMA／WO 数据路径并提供卸载能力”，不能把它简化为只改一个 DMA 开关。

接入和注册 flow 是分开的。[Linux mtk_wed.c:2624–2671](https://github.com/gregkh/linux/blob/v6.18.55/drivers/net/ethernet/mediatek/mtk_wed.c#L2624) 通过 `mtk_wed_flow_add/remove()` 计数实际卸载流并调用 mt76 的 enable/disable callback；[mt76/wed.c:86、170、188](https://github.com/openwrt/mt76/blob/467ae2e3f190baf737e15e318906da0dc7d0ab91/wed.c#L86) 对 token 配额、DMA 和 TC 分别处理。`NETIF_F_HW_TC` 可用不等于某条流已成功硬件卸载。

## TTL、UA3F、CAKE 和 AQL 的具体边界

| 机制 | 本机仅 WED、无实际卸载流时 | 需要验证的字段／行为 |
| --- | --- | --- |
| nft 出口 TTL 64 | WED 不创建修改 TTL 的规则，也不自动改 nft hook；既有软件出口包仍应经过 postrouting | 三出口对应 TTL 规则的真实计数增量；有条件时用自有包的出口抓取读回 TTL，不能只看规则存在 |
| UA3F 与核心 SOCKS 链 | WED 不改本机 TCP listener、用户态 HTTP UA 重写、UA3F `SO_MARK` 或策略路由 | 自有 core connection 仍为 UA3FLocal；UA3F owned socket inode／固定 outer／三个出口；独立 UA 小请求保持正确 |
| WAN egress／IFB CAKE | 软件栈中的包仍经过已有 qdisc；不因 WED 参数自动消失 | `tc -s qdisc`／IFB 与 redirect 真实正文增量、shaper 启用状态、队列延迟；速度验收暂停后按主线快照恢复，不能永久放开 |
| mac80211 AQL | 这版软件 TXQ 路径继续声明并检查 AQL，没有 WED 自动禁用分支 | 新 PHY／station 的 `aql_txq_limit`、`aql_pending`／station aql；原有定制值可能随驱动重建丢失，需准确恢复 |
| PPE／TC／flowtable | WED 提供可用接口；是否产生硬流取决于另行配置和成功注册 | UCI software/hardware offload 仍 disabled；nft ruleset 不出现新 flow add；conntrack 不出现 OFFLOAD/HW_OFFLOAD；没有独立 TC `in_hw` 硬流或第三方 PPE writer |

“可保留”是源码机制判断，还不是本机运行验收。即使 UCI offload=0，其他 TC flow rule 或第三方加速程序仍可能生成卸载流；需要核对实际 ruleset、TC 和 conntrack。不要为方便试 WED 开启任何 flow offload，也不要直接写 PPE/WED debug registers。

软件发送的 AQL 证据来自固定 [mt76 mac80211.c:450–452](https://github.com/openwrt/mt76/blob/467ae2e3f190baf737e15e318906da0dc7d0ab91/mac80211.c#L450)，无条件声明 `NL80211_EXT_FEATURE_AQL`；[tx.c:411](https://github.com/openwrt/mt76/blob/467ae2e3f190baf737e15e318906da0dc7d0ab91/tx.c#L411) 从 `ieee80211_tx_dequeue()` 取 skb。哈希已核对的 backports 7.2 `net/mac80211/tx.c:3894、4218–4247` 执行 pending airtime 检查，没有按 WED active 关闭的分支。若之后启用硬件 forwarding flow，绕过软件 TXQ 的包就不能靠软件 AQL 限制；该情况必须另行评估，不能把软件路径的保留结论推广过去。

本机 UA3F 和 SOCKS 流终止于路由器本地 socket；仅 DMA 接入不会把用户态解析和复制改成直通。纯 LAN 已 994.91 Mbps／平均 CPU 42.9%，本机 UA3F 915.12 Mbps／62.8%，PC 全路径 768.15／787.80 Mbps／75.2～81.1%。WED 所能减掉的仅是其中无线相关部分，不能预估其节约足够跨到 900。

## 认证约束下必须先核对的 Ethernet 条件

[Linux mtk_wed.c:2433–2435](https://github.com/gregkh/linux/blob/v6.18.55/drivers/net/ethernet/mediatek/mtk_wed.c#L2433) 的 attach 路径具有条件分支：当 `eth->dma_dev == eth->dev` 且 `of_dma_is_coherent(eth->dev->of_node)` 为 true 时，调用 `mtk_eth_set_dma_device()`。

[mtk_eth_soc.c:5032–5058](https://github.com/gregkh/linux/blob/v6.18.55/drivers/net/ethernet/mediatek/mtk_eth_soc.c#L5032) 对全部当前 UP 的 GMAC netdev 执行 `netif_close_many()`，切换 DMA device 后逐个 `dev_open()`。detach 的 [mtk_wed.c:1157–1159](https://github.com/gregkh/linux/blob/v6.18.55/drivers/net/ethernet/mediatek/mtk_wed.c#L1157) 在相应条件下反向切换。所以，手工不调用认证 restart 也不等于 Ethernet 永远不会被驱动暂时关闭；认证客户端可能对链路事件自行反应。

固定 Linux [MT7986 DTS](https://github.com/gregkh/linux/blob/v6.18.55/arch/arm64/boot/dts/mediatek/mt7986a.dtsi#L524) 的 Ethernet 节点以及本机固定板级 DTS 没有显式 `dma-coherent`。这降低该分支触发的可能性，但还没有证明运行 DT、DMA parent 属性和平台默认值相同。[of_dma_is_coherent()](https://github.com/gregkh/linux/blob/v6.18.55/drivers/of/address.c#L1021) 会沿 DMA parent 找 `dma-coherent`／`dma-noncoherent`，最后使用 `dma_default_coherent`；只看 Ethernet 节点下某一个文件不存在不够。

主线应先只读实际 Ethernet `of_node`，核对其 DMA parent 属性与平台默认；记录三认证 PID、starttime、WAN carrier／operstate／地址／策略路由和认证成功状态。若无法确定该 coherent 分支不会触发，而本次硬约束是认证不能重启，就不做在线 WED 试验。不能通过卸载 Ethernet 模块、停 netifd／network 或强制 reset 绕开这一限制。

## 试验前只读前提与快照

由主线唯一负责人执行，本报告不执行。所需条件应在关闭 WLAN 前完成：

1. 当前 `/sys/module/mt7915e/parameters/wed_enable` 是 N，实际设备／driver 为 `mt798x-wmac`。保存 mt7915e 全部已使用模块参数、模块加载来源及其原始持久配置字节；只做命令行一次性参数，不编辑 `/etc/modules.d`、modprobe 配置或 UCI。
2. 确认 `rmmod`／`modprobe` 及当前模块文件均在本机，`modprobe` 支持参数，目标 ABI 是正在运行的 6.18.55。只重载 `mt7915e`，不卸载 `mt76`、`mac80211`、Ethernet／DSA 等共享基础模块，不安装滚动 kmod。
3. 保存两个 radio 的启用状态及稳定设备路径；保存原 PHY、BSS、station、AQL 值，所有网络队列 RPS/XPS/flow_cnt、相关 NAPI／TX worker affinity、有效 IRQ affinity、UCI steering、相关 hotplug 行为、CAKE 与 IFB 状态。旧 PID、PHY 编号和 IRQ 数字重建后可能变化，恢复需以设备路径／队列／comm 名称重新匹配。
4. 确认设备需要的 WO firmware 在本机。Linux6.18.55 的 [mtk_wed_mcu.c:327–345](https://github.com/gregkh/linux/blob/v6.18.55/drivers/net/ethernet/mediatek/mtk_wed_mcu.c#L327) 对 MT7986 WED v2 选择 `mediatek/mt7986_wo_0.bin` 或 `_1.bin`；路径见 [mtk_wed_wo.h](https://github.com/gregkh/linux/blob/v6.18.55/drivers/net/ethernet/mediatek/mtk_wed_wo.h#L91)。文件存在仍不证明 firmware 能启动。
5. 完成 coherent 分支核对、无实际 offload 流核对。给 UA3F、TTL、三个认证与 DNS／国内／代理 HTTPS 留一个短小基线，停止其他自有大流量 helper。
6. WLAN 是当前 PC 的管理通道，关闭后该 SSH 会断。必须在路由器本地启动已写好、可重复执行、脱离 SSH 生命周期的试验脚本和独立回退计时器，并用 PID/starttime/日志读回其已运行；不能把恢复命令放在原 SSH 后半段。

计时器应始终在最多 120 秒后还原 N，本轮是临时试验；得到正向结果后也先恢复。可采用独立 `nohup` 本地 helper，每 5 秒检查期限和日志，过期运行同一回退函数。回退 helper 与试验 helper 必须用同一互斥锁串行操作模块；不能两个进程同时 rmmod/modprobe。计时器启动失败或未读回时，不关闭 WLAN。实际脚本应由主线在已有操作封装中生成并检查，不依赖未经核对的服务守护机制。

## 启用顺序与验收

以下是已核对源码后的顺序，正式执行时要带入快照中的其他原始模块参数及原有 radio 启用范围；不是可盲贴的全网重启脚本。

```sh
# 路由器本地、已脱离 WLAN SSH 的唯一操作进程
wifi down
rmmod mt7915e
# 确认 /sys/module/mt7915e 已不存在后才继续
modprobe mt7915e wed_enable=1
# 原先有其他非默认模块参数时，原值同时传入
wifi up
```

`rmmod` 失败则不继续 modprobe，不使用 `-f`。模块加载返回值、sysfs 参数和 WLAN 重新出现均需记录；普通 `wifi up` 使用现有配置，不能修改原来 disabled 的 radio 去扩大试验范围。`mt7915/mmio.c:965–1003` 的模块注册／注销包含 SoC platform driver；`soc.c:1247` 的新 probe 才重新读参数并 attach。

理论上也能用正确 platform driver 的 unbind/bind 重新 probe，而非 rmmod/modprobe，但它同样重建硬件和两频 WLAN；当前未建立该机的恢复路径，不作为优先在线操作。普通 wifi reload 只重建接口时不满足这一 probe 条件。

恢复 WLAN 后先做小请求；不立即大流量压测。真实 WED 成功至少需对应的 attach 日志、WO firmware 初始化成功、当前 driver/PHY 正常，并在自有短流窗中读到 WED DMA/ring/MIB 增量。Linux [mtk_wed_debugfs.c:617–627](https://github.com/gregkh/linux/blob/v6.18.55/drivers/net/ethernet/mediatek/mtk_wed_debugfs.c#L617) 给出 `/sys/kernel/debug/wed0/txinfo`、`rxinfo`，可能另有 wed1；目录在硬件注册时就能出现，存在本身不证明 attach。只读这些字段，不写 `regidx/regval`。结合 `mt7915/main.c:1223` 的 WED station 统计分支，不能只用同一个 station 累计字节证明路径。

主线随后准确恢复新 PHY／任务的原 AQL 和 steering/affinity 状态，避免把模块重建后的默认分配混成第二个变量。认证 PID/starttime 任一变化、WAN link/address 异常、WO timeout、无线无法重连、UA3F／TTL 小预检失败或管理失联，立即触发回退，不再跑吞吐。

只有小预检正常，才复用固定 CDN／owned outer／12 并发短窗采样，记录正文完成与 CPU；先一轮≤15 秒，然后还原。更低 CPU 但更低吞吐不能视为收益。与 AQL、CAKE、RPS、IRQ、Windows SMPS 或更多 buffer 一起改动不能归因 WED。

## 精确回退与失败分支

回退目标是原模块参数和 radio 状态，不只是把可写参数写回 N。活跃设备不会因为 `echo N` 自动 detach。实际 detach 来自 [mt76 dma.c:1226](https://github.com/openwrt/mt76/blob/467ae2e3f190baf737e15e318906da0dc7d0ab91/dma.c#L1195) 的设备 DMA cleanup。

```sh
# 同一互斥锁下，由本地操作进程或独立计时器执行
wifi down
# 仅当模块仍加载时执行；失败必须记录并终止强制操作
rmmod mt7915e
# 确认模块已不存在
modprobe mt7915e wed_enable=0
# 其余参数恢复快照原值
wifi up
```

| 失败位置 | 回退行为 |
| --- | --- |
| 初次 rmmod 失败，模块仍是原设备 N | 停止试启用，按原 radio 状态恢复 wifi；不更改参数掩盖真实状态 |
| rmmod 成功，Y load 失败／模块不存在 | 直接以原参数、`wed_enable=0` 加载，再恢复 wifi；不重启认证或 network |
| Y load 返回成功但 WED attach／WO 失败 | 仍按完整 down/remove/load N/up 回退；不因参数 Y 误报成功 |
| Y 设备在运行，回退 rmmod 失败 | 停自有流量、保留日志并报告无法安全卸载；不 force、不卸载共享模块、不用网络重启顶替。不将 sysfs N 宣称为已回退 |
| N load／无线重建失败 | 记录失败并停止自动扩大操作；本报告没有承诺所有驱动故障都可无认证中断恢复 |

回到 N 后，重新按稳定硬件路径识别新 PHY/BSS，并读回／恢复两个 radio 的原状态、所有有关 AQL 原值、对应新任务的 affinity、队列 mask 与 hotplug 结果；旧已退出 PID 不可复用。再核对 TTL nft、UA3F PID/chain、认证 PID/starttime、三出口地址及 routes、CAKE/IFB、DNS／国内／代理 HTTPS。文件配置字节及 UCI 未变也要确认。

以上都通过才将 rollback 记为完成，再关闭计时器并仅删除本试验 helper／标记文件。不能只运行官方 steering=1 作为回退，因为原状态来自实际任务和队列快照；WED attach/detach 的 Ethernet 条件也需要纳入回退前提。

当前可作出的决定是：WED 兼容保留既有软件策略，值得作为单项候选；它不是无中断热开关。若主线无法在运行 DT 上排除 Ethernet DMA 切换分支，或尚未建立独立本地恢复进程，则在“不能重启认证”的约束下不应在线试。补齐这些前提之后，可以在允许短暂 WLAN 重建的窗口临时 A/B，再以真实计数与正文决定是否长期采用。

本文通过 Agent Reach 的 GitHub／gh 后端读取固定原始来源，未以通用 WED wiki、当前 master 或第三方优化脚本替代此版本。没有改设备或持久配置。
