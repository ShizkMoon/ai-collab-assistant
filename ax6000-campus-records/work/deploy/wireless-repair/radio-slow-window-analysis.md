# AX6000 慢窗：survey 口径与当前根因边界

当前证据支持两个不同问题：旧 LAN 慢窗中，OBSS 接收占用明显升高；当前固定 CDN 的无线 PC 路径则增加了路由器处理成本。同一 WLAN 后来已完整传送 6 GiB、持续 51.80 秒达到 994.91 Mbps，因此不能再把 110 Mbps 慢窗或旧 uhttpd 结果当作无线固定上限。本文只分析已保存数据与固定源码，没有 SSH、扫描、测速或设备修改。

## 固定对象与计数公式

对象为 Redmi AX6000 stock layout，OpenWrt r37185-f29dfe25ba、Linux 6.18.55，mt76 提交 `467ae2e3f190baf737e15e318906da0dc7d0ab91`，无线核心是 backports 7.2-r5。固定 OpenWrt 的 [mt76 Makefile](https://github.com/openwrt/openwrt/blob/f29dfe25baaa5c03f2b52f49dfdc12ed99abe8df/package/kernel/mt76/Makefile#L9) 和 [mac80211 Makefile](https://github.com/openwrt/openwrt/blob/f29dfe25baaa5c03f2b52f49dfdc12ed99abe8df/package/kernel/mac80211/Makefile#L13) 分别确定这两个版本。本地 `backports-7.2.tar.zst` 的 SHA256 为 `6ec76a4cb0988b5382b2fc5053610a56ada90b8ef6a5a4f2807cd433badb9454`，与固定构建文件一致。

`mt7915e` 是驱动模块名，不意味着设备硅片是 PCIe MT7915。该机板级 [DTS](https://github.com/openwrt/openwrt/blob/f29dfe25baaa5c03f2b52f49dfdc12ed99abe8df/target/linux/mediatek/dts/mt7986a-xiaomi-redmi-router-ax6000.dtsi#L277) 启用 MT7986 的集成 WMAC；驱动的 [SoC probe](https://github.com/openwrt/mt76/blob/467ae2e3f190baf737e15e318906da0dc7d0ab91/mt7915/soc.c#L1242) 为此使用 AXI 初始化。不能把源码中 `is_mt7915()` 的旧芯片特例直接当成本机路径。

固定 [mcu.c:3196–3265](https://github.com/openwrt/mt76/blob/467ae2e3f190baf737e15e318906da0dc7d0ab91/mt7915/mcu.c#L3196) 按 `phy->band_idx` 向固件读 MIB，并累计：

| iw 字段 | 固定源码的含义 |
| --- | --- |
| channel active time | 驱动以 boottime 计算的活动时长，源计数单位为微秒，iw 输出毫秒 |
| channel BSS receive time | MIB_RX_TIME，即固件归入本 BSS 的接收时长 |
| channel receive time | MIB_RX_TIME ＋ MIB_OBSS_AIRTIME |
| channel transmit time | MIB_TX_TIME；只有旧 MT7915 芯片分支额外减去估算 TX backoff |
| channel busy time | NON_WIFI_TIME ＋ TX_TIME ＋ RX_TIME ＋ OBSS_AIRTIME |

据此，同一未重建的计数窗中，可以计算 `OBSS = Δreceive − ΔBSS_receive`，以及 `non-Wi-Fi = Δbusy − Δtransmit − Δreceive`。后者小余量会受取整、采样时刻与固件计数口径影响，不能直接叫作可精确识别的电磁干扰。

[mac80211.c:1016、1144–1202](https://github.com/openwrt/mt76/blob/467ae2e3f190baf737e15e318906da0dc7d0ab91/mac80211.c#L1016) 把当前 `chandef.chan` 对应的 `chan_state` 映射到 survey 的频点，并把累积微秒除以 1000。MCU 查询只有 band，没有 20 MHz 子信道或 BSSID 选择器。因此，5180 MHz 的 `[in use]` 行代表以主信道记账的该 PHY 测量，不能当作独立覆盖 HE160 八个 20 MHz 子信道的 CCA 结果。5200 MHz 的历史 193 ms 以及其他频点的 0，不能证明当前副信道无占用。其他本地 BSS 或客户端也可能参与同一 PHY 的统计；BSS receive 不能被等同于仅此 PC 的 station rx duration。

## 同窗数据

以下比例均由首末 radio/survey 的计数差除以 `Δactive` 得到，不使用开机以来累计总量。计数窗会覆盖启动、收尾及采样开销，略长于正文传送时间。

| 已保存案例 | 正文 Mbps／完整 | 路由器平均 CPU | 计数窗秒 | TX | RX | 本 BSS RX | 推导 OBSS |
| --- | --- | --- | --- | --- | --- | --- | --- |
| LAN baseline，12 并发 | 938.34／是 | 39.3% | 7.58 | 44.16% | 25.74% | 7.77% | 17.96% |
| LAN restored，旧异常窗 | 110.19／否 | 7.6% | 38.21 | 6.56% | 42.77% | 1.06% | 41.71% |
| LAN default long，12 并发 | 994.91／是 | 42.9% | 52.29 | 53.08% | 15.54% | 9.68% | 5.86% |
| 固定 CDN，PC A1 | 768.15／是 | 75.2% | 9.32 | 42.90% | 17.92% | 9.65% | 8.27% |
| 固定 CDN，本机 UA3F | 915.12／是 | 62.8% | 9.19 | 4.69% | 19.68% | 2.37% | 17.31% |
| 固定 CDN，PC A2 | 787.80／是 | 81.1% | 9.52 | 43.23% | 16.96% | 9.18% | 7.78% |
| steering=2，PC A1 | 632.82／是 | 66.7% | 11.91 | 37.80% | 18.42% | 7.98% | 10.44% |
| steering=2，PC A2 | 689.05／是 | 71.9% | 10.33 | 42.89% | 16.75% | 8.39% | 8.35% |

来源分别为本目录 `lan-raw-baseline.json`、`lan-raw-restored.json`、`lan-raw-info-default-long.json`、`fixed-path-current-cases.json`、`fixed-path-steering2-cases.json`。恢复后 788.11 Mbps 的正文完整，但 `fixed-path-steering2-restored-cases.json` 明确记录 `fixed_outer_valid=false`；在主线修正或补齐验证之前，只能报告吞吐恢复，不能把它当作完整固定 outer 的 A/B/A 闭环。

旧慢窗的重试与失败计数差为 1184／1185，station TX packet 差为 349312；描述性比值约 0.34%。同期 MCS11、NSS2、HE160、2401.9 Mbps 与约 −37～−38 dBm 保持。低重试不排除竞争：其他 BSS 先占用信道时，本机可以等待而无需大量重发。但这也不能证明 OBSS 已造成 89% 的吞吐损失；还有约半数活动时间未记为 busy，本机发送只有 6.56%，应用、socket、TCP、队列或省电暂停同样可使 TX 空闲。

重试／失败字段属于驱动及固件统计，AMPDU/AMSDU、控制帧和计数单位也可能不同，以上比值不是经过独立验证的空口逐包丢失概率。最后一次 PHY rate 是最近报告的速率，不能替代整窗实际使用的 PPDU 带宽、速率分布或等待时间。

目前固定 CDN 的 PC A1/A2 中，推导 OBSS 约 8%，无线 TX 约 43%，路由器四核均更忙。steering=2 的 PC A2 在 OBSS 8.35%、TX 42.89% 下仍只有 689.05 Mbps，接近 A2 原态的空口比例却更慢。现有结果不支持仅凭 survey 将当前差额归于干扰；它优先支持附加代理／TCP／调度成本候选。总 CPU 75～81% 与最忙核峰值约 95% 是同窗压力证据，还需轻量 NETLINK 的 socket 受限状态和任务 CPU 分配确认具体瓶颈。

## 不重载无线的下一步观察

由主线唯一设备负责人复用已有低成本采样器；本支线不连接设备。每次只伴随一次已经必要的有界下载，不另开全量扫描或同时测速。

1. 每 1 秒记录各核 CPU、mt76 TX worker／TX NAPI／RX NAPI／核心代理／UA3F 的 CPU 增量，及真正 owned inode 的两腿 TCP_INFO。socket 必须按进程、源端口和 inode 对应，不能把外网腿与 WLAN 本地腿混为一个 cwnd。
2. 每 2 秒读取当前 PHY survey、PC station 与同 PHY 已有其他 station。计算 OBSS 与各 station 字节／airtime 差；先用 `iw dev` 和已有 hostapd station 列表识别同 PHY 的其他 BSS，不发起主动扫描。所有本地 station 接收都低但 OBSS 高，仅支持“外 BSS 分类接收增加”，并不识别具体邻居或副信道。
3. 同时读当前 global `aql_pending`、PC 的 `stations/<MAC>/aql` 和 `airtime`、已有 TXQ 统计。`aql_txq_limit` 的静态数值不是队列饱和证据。backports 7.2 的 `net/mac80211/debugfs_sta.c:241–269` 直接显示每 AC pending 与 low/high；`tx.c:4218–4247` 依据 pending、total threshold、low/high 决定是否允许 dequeue。
4. 省电候选使用 PC station debugfs `flags`、`driver_buffered_tids`、已有 `agg_status` 与断流时序；`authorized=yes`、`inactive time=0` 和 DTIM 2 都不能单独排除 PS。backports 7.2 `tx.c:468–471、3129–3133` 检查 `WLAN_STA_PS_STA/PS_DRIVER/PS_DELIVER`。只读取，不在本轮改 DTIM、TWT、SMPS 或 Windows 电源策略。

判断应有可观察的区别：软件 TXQ 有 backlog、AQL pending 持续到上限而 PHY TX 低，才支持 AQL／完成反馈候选；软件队列空、代理发往 PC 的 socket 显示 app limited，才继续追用户态发送；同窗 rwnd/sndbuf limited 才试单 socket buffer；OBSS 升高且 CPU／队列／TCP 原态相近、吞吐同步下降，才把空口竞争提升为当前主因。省电标志与暂停同步变化，才开展可回退的单项客户端试验。

本机已能在原 WLAN 完整运行约 995 Mbps，现阶段不需要换信道、HE80/160 来证明基本无线容量。WED 若作为下一候选，必须按 `wed-candidate-analysis.md` 的设备重建及认证边界单独评估。

本文使用 Agent Reach 的 GitHub／gh 后端取得固定原始源码，并只读本地经过原始构建哈希核对的 backports archive。没有新增或更新设备配置。
