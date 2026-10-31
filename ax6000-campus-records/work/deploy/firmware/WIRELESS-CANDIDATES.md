# AX6000 无线候选与验收

当前优先保留已经工作的 stock OpenWrt、2.4 GHz HE20、5 GHz HE80 和现有代理／双出口结构。在这个基线上，实际有区分度的无线候选是另一个合法的 80 MHz 频块，以及同一低频主信道的 HE160。没有依据为这台设备套用大量高级参数，也没有依据把 300～400 Mbps 公网速率归因于无线。

本文是离线研究和操作交接，未连接路由器、修改配置、安装软件或运行测速。设备状态来自主代理交接和已保存的任务证据；最终执行与设备读回由主代理负责。

## 本次基线

| 项目 | 已知状态 | 结论范围 |
| --- | --- | --- |
| 系统 | Redmi AX6000 RB06；stock OpenWrt SNAPSHOT `r37185-f29dfe25ba`；Linux `6.18.55` | 不建议为无线调参改刷 ubootmod 或换商业驱动 |
| 驱动 | mt76 `2026-10-08`，源码 `467ae2e3f190baf737e15e318906da0dc7d0ab91`；mac80211 backports `7.2-r5` | 必须以这版源代码和实际能力为准 |
| 无线 | CN；2.4 GHz 信道 1／HE20；5 GHz 信道 36／HE80 | 现有 5 GHz 80 MHz 频块为 36～48 |
| 当前 PC | Intel BE200；约 −38 dBm；HE MCS 11、NSS 2；收发 PHY 1200.9 Mbps | PHY 是协商物理速率，不能直接换算为应用吞吐 |
| 局域网短测 | 路由器 RAM 中 64 MiB 文件经现有 5 GHz Wi-Fi 到 PC：763.23、695.39、713.97 Mbps，每轮约 0.70～0.77 秒 | 已说明当前无线链路能超过 300～400 Mbps；测试太短，不能证明长期吞吐、上行或满载延迟 |
| CPU 分配 | WAN `rx-0/rps_cpus=0`；两个 Wi-Fi AP 接口均为 `2`；4 个 CPU | Wi-Fi 已有 RPS 分配，不能说完全没有 steering |
| 既有网络契约 | OpenClash／Ninja、UA3F 本地 SOCKS、mwan3-nft 高位标记、明确 WAN 的 nft TTL 64 | 无线候选应保持这些契约；吞吐改动必须一并验收 |

局域网数据来源是 `work/deploy/wifi-lan-baseline.json`，RPS 与协商状态来源是 `work/deploy/tuning-current.json`。这两份文件是本轮任务证据，不是数日稳定性的记录。

## 可比较的三组配置

每轮只选择一组。保留完整无线配置备份，确认实际 5 GHz section 名称后再修改；以下 `radio1` 来自本轮已知配置，不能用于其他设备。切换会使 5 GHz 客户端暂时断开，HE160 还涉及 CAC。

| 组别 | 仅改变的内容 | 目的和预期 | 保留条件 |
| --- | --- | --- | --- |
| A：当前基线 | `channel=36`、`htmode=HE80` | 36～48 的 80 MHz 频块；继续作为回退状态 | 已工作的基线 |
| B：高频 HE80 | `channel=149`、`htmode=HE80` | 使用 149～161 的另一个 80 MHz 频块。如果 36～48 持续繁忙，这组可能受益 | 设备 CN regulatory 能力允许；相同位置、相同客户端的有效吞吐或满载延迟有可重复改善，且所有现有客户端正常连接 |
| C：低频 HE160 | `channel=36`、`htmode=HE160` | 使用 36～64 的 160 MHz 频块；支持 160 MHz 的 2 流客户端理论 PHY 可由约 1201 增至约 2402 Mbps，实际值需读回 | 实际协商达到 160 MHz，完成 CAC，既有设备兼容，短时及持续传输有收益；无频繁雷达换台或重连 |

同一个 80 MHz 频块内，把主信道从 36 换到 40／44／48，不等于避开该频块的干扰。不能只比较可见 AP 数量；应该比较相同时间窗的 channel busy／channel time 增量，并检查传输时的重试与延迟。

本轮同版 `wireless-regdb-2026.09.03` 的 CN 段为：5150～5250 MHz 最大 80 MHz、AUTO-BW；5250～5350 MHz 最大 80 MHz、AUTO-BW、DFS；5725～5850 MHz 最大 80 MHz。低频 HE160 横跨前两个规则，涉及 DFS；149～161 只作为 HE80 候选，不能强行设为 HE160。设备实际 `iw phy`／`iw reg` 是执行前的最终依据。[同版 regdb 原文](https://www.kernel.org/pub/software/network/wireless-regdb/wireless-regdb-2026.09.03.tar.xz)、[固定 OpenWrt regdb 配方](https://github.com/openwrt/openwrt/blob/f29dfe25baaa5c03f2b52f49dfdc12ed99abe8df/package/firmware/wireless-regdb/Makefile)

mt7915 驱动目录同时服务多种芯片。当前源码对原始 MT7915 有 160 MHz 半 NSS 分支，其他芯片走 `nss_160=nss`；不能把 RT3200／MT7915 的“160 MHz 减为 2 流”讨论直接套到 MT7986 AX6000。仍应从本机能力和客户端实际协商验证。[固定 mt76 HE 能力实现](https://github.com/openwrt/mt76/blob/467ae2e3f190baf737e15e318906da0dc7d0ab91/mt7915/init.c#L1065)

千兆 WAN 和有线 LAN 对单条有线路径有上限；HE160 不能让千兆口突破其容量。当前公网瓶颈若在校园认证额度、测速源、远端节点或代理 CPU，HE160 可能只增加局域网无线余量。

## 保持默认的参数

固定 wifi-scripts schema 已默认启用 HE 单用户／多用户 beamforming、BSS color 和 TWT responder；生成 hostapd 配置时会按 PHY 能力裁剪。UCI 中未显式填写不等于未启用；实际生成配置和关联能力必须读回。无需再写一串 `he_su_beamformer=1`、`he_mu_beamformer=1` 并宣称新增优化。固定 schema 没有通用 `he_dl_ofdma`／`he_ul_ofdma` 用户开关，不能引用 MTK 商业驱动的私有选项。[固定无线 schema](https://github.com/openwrt/openwrt/blob/f29dfe25baaa5c03f2b52f49dfdc12ed99abe8df/package/network/config/wifi-scripts/files-ucode/usr/share/schema/wireless.wifi-device.json)、[固定能力裁剪实现](https://github.com/openwrt/openwrt/blob/f29dfe25baaa5c03f2b52f49dfdc12ed99abe8df/package/network/config/wifi-scripts/files-ucode/usr/share/ucode/wifi/hostapd.uc#L386)

保留 WMM、beacon 100、DTIM 2、自动能力检测、默认 AQL／airtime 以及当前 WPA2+3。TWT 主要服务设备省电和调度，不是固定 PC 的增速保证；不把 `he_twt_required` 改为强制。`legacy_rates` 在这版已经默认 false，不能把“禁用 11b”算作新改进。不开激进的基本速率、RSSI 踢人、RTS 阈值、EDCA／TXOP、OBSS-PD 或最大功率覆盖。[固定接口 schema](https://github.com/openwrt/openwrt/blob/f29dfe25baaa5c03f2b52f49dfdc12ed99abe8df/package/network/config/wifi-scripts/files-ucode/usr/share/schema/wireless.wifi-iface.json)、[官方无线配置说明](https://openwrt.org/docs/guide-user/network/wifi/basic)

## Packet steering 的实际边界

这版 `/etc/init.d/packet_steering` 把 UCI 原值传入通用 `packet-steering.uc`。固定源码只有参数 `0` 设置禁用、参数 `2` 设置所有 CPU；未填写与参数 `1` 都走默认分配。固定 OpenWrt Git tree 只有 bcm4908／bcm53xx 的平台覆盖脚本，没有 mediatek 专用覆盖。因此，当前未填写 `network.@globals[0].packet_steering` 不能被描述为关闭；现有 Wi-Fi RPS mask 也与已有分配一致。[固定 steering 实现](https://github.com/openwrt/openwrt/blob/f29dfe25baaa5c03f2b52f49dfdc12ed99abe8df/package/network/config/netifd/files/usr/libexec/network/packet-steering.uc#L16)

仅当相同负载下有单核 softirq／NAPI 热点且其他核空闲，才考虑把 `packet_steering=2` 作为另一个独立候选。RPS 按流哈希选择 CPU，不会把单个连接的每个包均匀拆给所有核；它还增加跨核通知和缓存成本。需要读回 NAPI 线程亲和性、RPS mask、各核负载和有效吞吐，再决定保留。不要叠加手工 IRQ 掩码、第三方 affinity 脚本和 irqbalance。[Linux RSS／RPS 原理](https://docs.kernel.org/6.18/networking/scaling.html)

## 不应直接启用的加速

软件与硬件 flowtable 都会在命中后绕过经典 IP 转发路径和 ingress 之后的 netfilter hooks。现有 nft postrouting TTL 64 因此可能只作用于未被 offload 的包；多 WAN 标记、故障恢复及计数也需要一起检查。不能只看吞吐增加或勾选框生效。OpenClash／UA3F 终止 TCP 并重新建立本机连接，这些连接不属于相同的普通转发加速路径。[Linux 6.18 flowtable 路径](https://docs.kernel.org/6.18/networking/nf_flowtable.html)

WED 进一步把无线流量交给 PPE，可能减轻 CPU，但有 AQL／流量控制和上述网络契约的代价。当前不建议为目标速率直接开启 WED、硬件 offload 或重新启用已退役的 TC TTL。只有流量路径、真实瓶颈和 TTL／双出口行为均已明确，才单独制定候选。[OpenWrt WED 说明](https://openwrt.org/docs/guide-user/network/wifi/wed)

## 最小验收顺序

1. 主代理运行同目录 `wireless-readback.sh`，取得运行信道／宽度、regulatory 能力、survey、station 增量前值和 CPU 分配。脚本只读，不读取无线密码、认证凭据或代理配置。
2. 固定 PC、摆放位置和本地传输服务；先用 A 组进行至少 10～20 秒的有效数据传输，同时记录到路由器的空闲／满载延迟和各核负载。原 64 MiB 亚秒短测可作参照，但不代替这一步。可使用 RAM 文件循环；汇总应包含实际完成字节、HTTP 状态、总壁钟时间和失败请求。
3. 若 36～48 的同窗 busy 高，先比较 B；若主要目标是增加该 PC 的无线容量且支持 160 MHz，则比较 C。每次只改信道或宽度，期间不同时更改功率、steering、WED 或代理参数。
4. 切换后读回实际 channel／width、HE MCS／NSS，检查 CAC／DFS 日志、其他已连接设备、重新连接和睡眠恢复。对 B／C 重复同一测试，再回 A 做一次对照，避免把校园或后台负载变化当作参数效果。
5. 无线保留候选还必须通过当前 DNS、双出口 HTTPS、直连与代理 TCP／UDP、TTL 抓包和服务恢复的必要检查。只有这条实际路径通过，才称为生产配置；不以一个最高速率数值替代整个验收。

上游曾有 MT7986 设备在特定客户端和 160 MHz 条件下出现间歇延迟与低速的原始报告，但该报告使用 2024 年版本，不能直接证明当前 2026 年驱动仍有同一缺陷。它只支持保留兼容性和持续负载检查，而不支持预先否定 HE160。[原始 mt76 问题报告 #877](https://github.com/openwrt/mt76/issues/877)

本轮 GitHub 原文通过 Agent Reach 的 `gh` 后端读取；官方无线 wiki 通过其 Jina Reader 路径成功取得正文。Exa 一个查询触发免费 MCP 额度限制，另一个返回内容；后续采用官方源码与原始问题报告，未新增 API key 或修改网络设置。
