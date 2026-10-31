# AX6000 WED 在线前提独立审阅

主线的新实际 DT 读回足以排除下一次 WED attach 中因 Ethernet DMA device 切换而关闭 GMAC 的分支。结论限定于已固定的 stock RB06、OpenWrt `f29dfe25baaa5c03f2b52f49dfdc12ed99abe8df`、Linux 6.18.55 和当前运行 DT。detach 的条件不同，仍须确认当前没有已 attach 的 WED；独立恢复 helper 的实际到期恢复也须先验收。仅有 `wed_enable=N`、WO 文件存在、工具存在或 debugfs 目录存在，均不能补齐这两项。

仅启用 WED、保持实际 flow offload 为零时，源码支持软件 TTL／UA3F／WAN 与 IFB qdisc 路径继续存在。审阅没有发现 WED attach 自动新建跳过这些策略的硬件流，但发现原报告需要补充的 RX PPE 检查入口、detach 状态条件和 station 计数口径变化。实际策略保持及性能收益仍由主线运行读回判定。

本次只读取本地资料和固定上游源码，只写本文。没有 SSH、测速、无线重建、设备配置、Windows 网络操作、认证操作或文件上传。

## 固定来源与检查范围

- Linux tag `v6.18.55` 通过 GitHub tag API 解析为 commit `725bd2f3c81d54edccb66fead01d4c0c222e2231`。本文 Linux 链接使用此 commit，而非当前 master。
- OpenWrt commit `f29dfe25baaa5c03f2b52f49dfdc12ed99abe8df`；mt76 commit `467ae2e3f190baf737e15e318906da0dc7d0ab91`。
- 主线实际证据：[wed-live-preflight.json](wed-live-preflight.json) 的 `ethernet_device`、`dma_properties` 与 `dma_chain`；配置来源为 `work/ax6000/mainline-review/config.buildinfo`。后者是 OpenWrt 构建配置，不能称为运行内核 `.config` 的逐项读回。
- 用 Agent Reach 的 GitHub／`gh` 后端读取固定文件，并以内存 archive 检查固定 OpenWrt 的 generic backport-6.18 176 个、hack-6.18 65 个、pending-6.18 211 个及 mediatek patches-6.18 140 个补丁，共 592 个。匹配范围包含 `dma_default_coherent|ARCH_DMA_DEFAULT_COHERENT|OF_DMA_DEFAULT_COHERENT|drivers/of/address.c|kernel/dma/mapping.c|arch/arm64/(Kconfig|mm/dma-mapping.c)`，及所有修改 `mtk_eth_soc.c`、`mtk_wed.c`、`mt7986a.dtsi` 的 patch。没有改动 DMA 默认值、OF 判定或 WED attach／detach 的 DMA 切换条件；`737-09` 仅以 setter 声明为上下文，改的是 MAC 地址 probe defer。

## ARM64 默认值已经能确定

Linux [arch/arm64/Kconfig:55–56](https://github.com/gregkh/linux/blob/725bd2f3c81d54edccb66fead01d4c0c222e2231/arch/arm64/Kconfig#L55) 无条件选择 `ARCH_HAS_SYNC_DMA_FOR_DEVICE` 与 `ARCH_HAS_SYNC_DMA_FOR_CPU`。因此 [include/linux/dma-map-ops.h:233–242](https://github.com/gregkh/linux/blob/725bd2f3c81d54edccb66fead01d4c0c222e2231/include/linux/dma-map-ops.h#L233) 使用外部变量 `dma_default_coherent`，不会进入无 sync 实现时的 `#define dma_default_coherent true` 分支。

[kernel/dma/mapping.c:24–28](https://github.com/gregkh/linux/blob/725bd2f3c81d54edccb66fead01d4c0c222e2231/kernel/dma/mapping.c#L24) 将其初始化为 `IS_ENABLED(CONFIG_ARCH_DMA_DEFAULT_COHERENT)`。[kernel/dma/Kconfig:80–86](https://github.com/gregkh/linux/blob/725bd2f3c81d54edccb66fead01d4c0c222e2231/kernel/dma/Kconfig#L80) 的该选项是无 prompt、无 default 的隐藏 bool；ARM64 没有选择它。固定 OpenWrt [filogic/config-6.18:25](https://github.com/openwrt/openwrt/blob/f29dfe25baaa5c03f2b52f49dfdc12ed99abe8df/target/linux/mediatek/filogic/config-6.18#L25) 选择 ARM64，其 target 配置、generic 配置及上述补丁都未改变此选项。已读取的 ARM64 setup／init／dma-mapping 实现也没有平台启动时将此全局默认改为 true 的分支。

所以这一固定标准构建的默认值为 **false**。`/proc/config.gz` 不可用不影响这条固定源码结论，但若镜像、kernel build identity 或补丁基线发生变化，就须重新核对。`CONFIG_OF_DMA_DEFAULT_COHERENT` 是 generic 配置中残留的旧名称，不能替代本版实际读取的 `CONFIG_ARCH_DMA_DEFAULT_COHERENT`。

`dma_set_mask_and_coherent()` 中的 coherent 指一致性分配的地址 mask，不会把 `dma_default_coherent` 或设备 DT 改为 true；不能从该函数调用推断 Ethernet coherent。[ARM64 dma-mapping.c:43–54](https://github.com/gregkh/linux/blob/725bd2f3c81d54edccb66fead01d4c0c222e2231/arch/arm64/mm/dma-mapping.c#L43) 另将已经计算出的 coherent 参数写入设备 `dev->dma_coherent`。

## OF 的实际父链与最小 live preflight

[drivers/of/address.c:1021–1036](https://github.com/gregkh/linux/blob/725bd2f3c81d54edccb66fead01d4c0c222e2231/drivers/of/address.c#L1021) 从传入节点开始，对每个节点先检查 `dma-coherent`，存在就返回 true；随后检查 `dma-noncoherent`，存在就返回 false。同一节点两个属性都存在时 coherent 先胜出，最近一层的首次命中结束，不能把所有层属性简单 OR。属性是布尔存在性判断，零字节属性也为 true；不能按 `cat` 有无文本判定。

下一层由 [address.c:606–633](https://github.com/gregkh/linux/blob/725bd2f3c81d54edccb66fead01d4c0c222e2231/drivers/of/address.c#L606) 决定：

1. 在当前节点 `interconnect-names` 字符串列表中匹配 `dma-mem`。
2. 若匹配，按相同 index 解析 `interconnects`，使用提供者 `#interconnect-cells`；解析成功就跳到所引用的 provider 节点。
3. 没有匹配或解析失败，才回到物理 DT 父节点。
4. 到链尾没有命中 coherent／noncoherent 属性，返回本平台的 `dma_default_coherent`。

`dma-ranges`、`ranges`、`status` 和 `compatible` 不决定这条 bool 返回值；`compatible` 用于确认读的是实际目标节点。若发现 dma-mem 引用，最小核验必须读 binary cells、相应 `phandle`／`linux,phandle`、provider 的 `#interconnect-cells` 和后续 DMA 父链。不要只遍历物理目录祖先。

主线 `wed-live-preflight.json` 已读回：

| 项目 | 实际值及判定 |
| --- | --- |
| 绑定 Ethernet device | `/sys/devices/platform/soc/15100000.ethernet` |
| 对应 of_node | `/sys/firmware/devicetree/base/soc/ethernet@15100000` |
| Ethernet compatible | `mediatek,mt7986-eth` |
| 物理父节点 | `/soc`，`simple-bus` |
| 根节点 compatible | `xiaomi,redmi-router-ax6000-stock`、`mediatek,mt7986a` |
| 三层属性 | 均无 `dma-coherent`、`dma-noncoherent`、`interconnect-names`、`interconnects`；无跳转，父链就是 Ethernet → soc → root |

结合 false 默认值，可确定 `of_dma_is_coherent(eth->dev->of_node) == false`。固定源 DTS 无属性只是交叉依据；决定当前条件的是上表运行 DT，不是源 DTS 或别的 AX6000 型号。

## attach 与 detach 必须分开判断

[mtk_wed.c:2433–2435](https://github.com/gregkh/linux/blob/725bd2f3c81d54edccb66fead01d4c0c222e2231/drivers/net/ethernet/mediatek/mtk_wed.c#L2433) 的 attach 条件为 `eth->dma_dev == eth->dev && of_dma_is_coherent(eth->dev->of_node)`。当前后半条件为 false，故本次 attach 不调用 `mtk_eth_set_dma_device()`，不论前半条件值如何。

[mtk_eth_soc.c:5032–5058](https://github.com/gregkh/linux/blob/725bd2f3c81d54edccb66fead01d4c0c222e2231/drivers/net/ethernet/mediatek/mtk_eth_soc.c#L5032) 的 setter 在 RTNL 锁下将全部 UP 的 GMAC 放入列表，执行 `netif_close_many()`，切换 `eth->dma_dev`，再逐项 `dev_open()`。原报告提出的风险是真实代码行为，当前证据排除的是这个特定 attach 分支。

[mtk_wed.c:1157–1159](https://github.com/gregkh/linux/blob/725bd2f3c81d54edccb66fead01d4c0c222e2231/drivers/net/ethernet/mediatek/mtk_wed.c#L1157) 的 detach **不再检查 OF**，而在最后一个 WED detach 且 `eth->dma_dev != eth->dev` 时反向切换。固定 Ethernet probe 初始值 [mtk_eth_soc.c:5125–5126](https://github.com/gregkh/linux/blob/725bd2f3c81d54edccb66fead01d4c0c222e2231/drivers/net/ethernet/mediatek/mtk_eth_soc.c#L5125) 为两者相同；固定实现中改变该指针的 setter 由 WED attach／detach 调用。若当前没有旧 WED attach，本次 false 条件 attach 不改指针，回退 detach 也不会因本次 attach 进入该切换分支。

最小新增只读证据应为：成功打开并读取当前已暴露的 `/sys/kernel/debug/wed0/txinfo`、`wed1/txinfo` 至 EOF，记录 exit code、读取长度和内容；可用 `rxinfo` 交叉核对。固定 [mtk_wed_debugfs.c:145–151](https://github.com/gregkh/linux/blob/725bd2f3c81d54edccb66fead01d4c0c222e2231/drivers/net/ethernet/mediatek/mtk_wed_debugfs.c#L145) 只有在 `hw->wed_dev` 非 NULL 时输出寄存器，NULL 时正常成功返回空内容；[rxinfo:260–273](https://github.com/gregkh/linux/blob/725bd2f3c81d54edccb66fead01d4c0c222e2231/drivers/net/ethernet/mediatek/mtk_wed_debugfs.c#L260) 同理。

- 两个节点成功读到 EOF 且空：支持当前两块 WED 均未 attach。结合固定 probe／setter 代码，可闭合正常状态下的 detach 条件论证。
- 任一输出非空：当前已有 WED attach；不得把参数 N 当作未 attach，须先解释现状和恢复条件。
- 文件不存在、未挂载 debugfs、权限错误、读失败或版本不匹配：状态未知。不要为此在线装内核模块、写 debug registers 或试 attach；维持否决，直到获得其他等价只读证据。

debugfs `wed0`／`wed1` 目录在 WED hardware 注册时就创建，见 [mtk_wed.c:2865](https://github.com/gregkh/linux/blob/725bd2f3c81d54edccb66fead01d4c0c222e2231/drivers/net/ethernet/mediatek/mtk_wed.c#L2865) 和 [mtk_wed_debugfs.c:614–627](https://github.com/gregkh/linux/blob/725bd2f3c81d54edccb66fead01d4c0c222e2231/drivers/net/ethernet/mediatek/mtk_wed_debugfs.c#L614)，所以目录存在本身不证明 attach。反过来，成功非空 seq 输出只证明 `wed_dev` 当前存在，仍不证明正文通过 WED、WO 启动完成、RX／TX ring 活跃或测速改善。

## 软件策略链的复核与原报告遗漏

软件 RX 仍在 [mt76/dma.c:1069–1090](https://github.com/openwrt/mt76/blob/467ae2e3f190baf737e15e318906da0dc7d0ab91/dma.c#L1069) 构建 skb 并调用驱动 `rx_skb`；[mt7915/mac.c:1084–1087](https://github.com/openwrt/mt76/blob/467ae2e3f190baf737e15e318906da0dc7d0ab91/mt7915/mac.c#L1084) 正常包进入 `mt76_rx()`；[mac80211.c:1545–1582](https://github.com/openwrt/mt76/blob/467ae2e3f190baf737e15e318906da0dc7d0ab91/mac80211.c#L1545) 经过 `ieee80211_rx_list()` 后进入 `netif_receive_skb_list()` 或 `napi_gro_receive()`。WED active 的区别包括 [mac80211.c:1595–1602](https://github.com/openwrt/mt76/blob/467ae2e3f190baf737e15e318906da0dc7d0ab91/mac80211.c#L1595) 跳过 mt76 软件 RX reorder，不能把它描述成只有 TX DMA 改动。

原报告应补以下边界：

1. **RX 自带 PPE 检查入口。** [mt7915/mac.c:246–259](https://github.com/openwrt/mt76/blob/467ae2e3f190baf737e15e318906da0dc7d0ab91/mt7915/mac.c#L246) 在 WED RX queue 且 `MT_DMA_INFO_PPE_VLD` 时调用 `mtk_wed_device_ppe_check()`；[mtk_wed.c:1959–1974](https://github.com/gregkh/linux/blob/725bd2f3c81d54edccb66fead01d4c0c222e2231/drivers/net/ethernet/mediatek/mtk_wed.c#L1959) 对 HIT_UNBIND_RATE_REACHED 调用 `mtk_ppe_check_skb()`。这是关联已注册 flow 的入口，不是 attach 自动创建 flow。[mtk_ppe.c:755–811](https://github.com/gregkh/linux/blob/725bd2f3c81d54edccb66fead01d4c0c222e2231/drivers/net/ethernet/mediatek/mtk_ppe.c#L755) 需要已有 L3 list entry 或 L2 rhashtable entry；固定 OpenWrt [736-03 patch](https://github.com/openwrt/openwrt/blob/f29dfe25baaa5c03f2b52f49dfdc12ed99abe8df/target/linux/generic/pending-6.18/736-03-net-ethernet-mtk_eth_soc-improve-keeping-track-of-of.patch) 改 tracking 但保留这项前提。故必须审阅实际 nft／TC／PPE writer，而不能只核对 UCI。
2. **station 计数口径发生变化。** [mt7915/main.c:1223–1241](https://github.com/openwrt/mt76/blob/467ae2e3f190baf737e15e318906da0dc7d0ab91/mt7915/main.c#L1223) 在 WED active 时使用驱动／WA／WO 的 tx／rx 计数；[mt7915/mac.c:914–930](https://github.com/openwrt/mt76/blob/467ae2e3f190baf737e15e318906da0dc7d0ab91/mt7915/mac.c#L914) 的 TX-free 重试／失败累加分支仅在 WED 未 active 时执行。不能直接把前后累计 bytes、retries 或 failed 当成同口径指标；驱动重建也会重置部分计数。用相同正文 byte 数、实际 socket 路径、CPU 同窗 delta 和各阶段独立计数判断。
3. **AQL 保留的是软件 TXQ 路径。** 固定 [mt76/tx.c:411](https://github.com/openwrt/mt76/blob/467ae2e3f190baf737e15e318906da0dc7d0ab91/tx.c#L411) 仍调用 `ieee80211_tx_dequeue()`；[mac80211.c:452](https://github.com/openwrt/mt76/blob/467ae2e3f190baf737e15e318906da0dc7d0ab91/mac80211.c#L452) 声明 AQL。已重新解读本地 backports 7.2 archive，其 SHA256 与固定 [OpenWrt Makefile:13–22](https://github.com/openwrt/openwrt/blob/f29dfe25baaa5c03f2b52f49dfdc12ed99abe8df/package/kernel/mac80211/Makefile#L13) 相同：`6ec76a4cb0988b5382b2fc5053610a56ada90b8ef6a5a4f2807cd433badb9454`。包中 `net/mac80211/tx.c:3894、4218–4247` 检查 pending airtime，没有 WED 条件关闭它，但另有全局 `aql_disable` 条件。仅有 `aql_txq_limit` 数值不证明 AQL 此刻在限制队列；需读 global disable、station pending 与实际软件发送。当前两个 PHY 的 5000／12000 和 BC/MC 50000 值必须按新 PHY 身份恢复。
4. **长期 qdisc 存在不等于正文被整形。** WLAN 重建可重建 netdev 及其局部 TC hook；WAN／IFB 没被本次代码主动移除，但仍须 readback qdisc、redirect target、`in_hw`、正文 bytes／packets 增量。TTL 64 必须验证三个出口的实际规则计数，UA3F 必须验证 owned socket 和真实 chain；硬件 flow 能力 flag、offload 参数为零或文件字节未变都不是这些行为的验收。

固定 [mtk_ppe_offload.c:483–500](https://github.com/gregkh/linux/blob/725bd2f3c81d54edccb66fead01d4c0c222e2231/drivers/net/ethernet/mediatek/mtk_ppe_offload.c#L483) 把 flow 注册、`mtk_wed_flow_add()` 与 PPE entry 建立连接，WED attach 本身不调用该注册链。在没有这些实际卸载流的范围内，软件 skb 进入本机 Ninja／UA3F socket 和网络栈，现有软件出口 TTL 与 qdisc 可以保留。这是机制判断；本机运行验收尚未由本审阅完成。

## 允许／否决的精确范围

当前可允许主线继续做只读状态闭合和独立 helper 验证。新的运行 DT 已排除特定 attach GMAC close 分支；仍不能写成“WED 切换保证认证绝不受影响”。WED 引入 WO、ring／IRQ、重置及内存初始化，错误仍可能影响运行设备；源码条件分析不证明设备绝无异常。

开始任何 WLAN 重建前，应具备以下具体证据：

- 当前两块 WED seq 文件成功读回，闭合旧 attach／detach 状态；未出现本次之外的实际 offload rule 或 writer。
- 使用真实已存在的 `setsid` 或 `start-stop-daemon` 拉起独立本地恢复 helper，stdin/stdout/stderr 与 SSH 通道脱离，保存 PID、starttime、session／parent、lock 和唯一试验标记；先让它在保持当前 N 状态下正向到期执行同一幂等恢复入口，并实际确认完成标记、无线仍可连接、三认证 PID／starttime 和三出口状态保持。二进制存在、fork 返回值或计划文件写出都不证明 helper 活着或能恢复。
- 原模块参数与持久 modules 文件、两个 radio 状态、PHY／BSS 实际身份、AQL 所有原值、实际 steering affinity／queue mask 已保存，恢复入口对部分失败状态也能继续，并有严格时限。不允许 helper 因无线重建时失败而调用认证 restart。
- 如“电脑始终无线接路由器”包含任何时刻 association 不断，则需重新 probe 的 WED 候选不符合；若约束是始终使用无线为连接路径，则试验仍会有已知短暂 WLAN 重建，不能报告成无中断热开关，也不能切到有线掩盖恢复失败。

截至本文，独立 helper 的到期恢复和两块 WED seq 内容尚未纳入已读取的 `wed-live-preflight.json`，因此本审阅 **不批准直接在线 attach**。缺口限定于这些证据，不再把 ARM64 默认 DMA 一致性列为未知。主线补齐后可在自身授权范围内决定有限 A/B；只有真实 WED attach／WO／ring 行为、完整多连接正文结果、TTL／UA3F／CAKE 与三认证保持同时读回，才可决定长期保留。

Agent Reach 本次 `check-update` 返回本机 v1.5.0 已是最新；没有安装或升级。
