# AX6000 校园网部署与性能记录

本仓库保存 Redmi AX6000（RB06，stock 分区）校园网部署、调优、源码调研、完整实验批次及恢复验证记录。当前记录截至 **2026 年 10 月 14 日**，时区为 UTC+8。入口文档描述最新采用状态；阶段报告和原始证据保留当时的条件、失败与恢复结果。

**WED 已保留；UA-Mask 尚未替换生产 UA3F；电脑完整公网路径稳定 900 Mbps 尚未验证。** 这些判断的范围见下表和对应证据。当前运行的是 OpenWrt SNAPSHOT `r37185-f29dfe25ba`／Linux `6.18.55`，不能将本设备记录直接用于其他固件或设备。

## 当前采用状态

| 项目 | 记录结果与边界 | 主要入口 |
| --- | --- | --- |
| 三路校园认证与分流 | 三个认证实例、独立 DHCP 地址及 MWAN 新连接分配已验收；当前三路与新队列的冷启动仍未验收。 | [三路采用结果](work/deploy/frontier/adoption-results.md)、[聚合结果](work/deploy/aggregation/results.md) |
| UA3F、Ninja 与 TTL | UA3F `3.7.0` 本地 SOCKS5、固定香港 02 节点、三出口 IPv4 TTL64 保持；没有替换生产代理。 | [使用说明](outputs/ax6000-mainline/使用说明.md) |
| WED | 运行参数 `Y`、实际挂接及启动文件 `mt7915e wed_enable=1` 已读回。保留验收确认三认证、电脑访问与原队列保持；未做 WED 冷启动，也未在保留验收中重测吞吐。 | [最终保留验收](work/deploy/wireless-repair/wed-retained-acceptance.json)、[实际恢复验证](work/deploy/wireless-repair/wed-restore-entry-verified.json) |
| CAKE、BBR 与 DNS | 日常下载 CAKE 为 650 Mbit，上传为 unlimited；本机新 TCP 默认 BBRv1，国内九个后缀采用 DoH。相关失败和未采用机制仍保留；没有证明普遍提速或满载延迟收益。 | [队列与传输采用结果](work/deploy/next/adoption-results.md)、[整体研究](outputs/ax6000-mainline/路由器调优与校园网方案调研.md) |
| 性能 | 关闭自有 CAKE 的受控批次证明路由器多连接三路聚合收益；电脑公网完整路径稳定 900 Mbps 尚未达到。日常 650 Mbit 下载队列与经该队列的持续 900 Mbps 不兼容。 | [完整聚合批次](work/deploy/aggregation/controlled-cases.json)、[结果摘要](work/deploy/aggregation/result-summary.json) |
| TCP 接收压力 | 自有 UA3F 外层 socket drops 与内核接收压力已观察；计数不等于物理线路丢包率，不能认定为唯一瓶颈。缓冲限额试验完整 A1／B 为 814.71／812.00 Mbps，未见收益；A2 正文不完整。 | [内核源码解释](work/deploy/wireless-repair/tcp-receive-drop-source-review.md)、[试验摘要](work/deploy/wireless-repair/owned-buffer-cases-summary.json)、[完整采样](work/deploy/wireless-repair/owned-buffer-cases.json) |
| UA-Mask | 已比较固定版本源码、接入条件与公开性能主张；当前资料不足以证明可直接替换 UA3F 或提升本机完整路径性能。 | [UA-Mask 评估](work/deploy/wireless-repair/ua-mask-assessment.md) |

## 阅读与证据导航

- 日常管理：[使用说明](outputs/ax6000-mainline/使用说明.md)。
- 调研、采用理由与未验证范围：[路由器调优与校园网方案调研](outputs/ax6000-mainline/路由器调优与校园网方案调研.md)。
- 历史汇总：[部署验证](outputs/ax6000-mainline/部署验证.json)。该文件包含多个阶段，不能将整个对象当作同一时刻的完整状态。
- 认证源码与部署：[ESurfing 源码问题](work/deploy/esurfing/SOURCE-BUGS.md)、[netifd 部署](work/deploy/esurfing/NETIFD-DEPLOYMENT.md)、[三路来源审阅](work/deploy/esurfing/three-channel-source-review.md)。
- DNS 与传输候选：`work/deploy/frontier/`；CAKE、BBR 与未采用机制：`work/deploy/next/`。
- 单／双／三出口、电脑和无线对照：`work/deploy/aggregation/`。
- 固定外层路径、WED、TCP 接收压力、CPU 与 UA-Mask：`work/deploy/wireless-repair/`。
- 组件维护与恢复：[集成及恢复说明](work/deploy/maintenance/integration-and-recovery.md)、[恢复说明](outputs/ax6000-recovery/恢复说明.md)。
- 导出范围与校验：[文件清单](archive-manifest.json)、[归档验证](docs/archive-verification.json)、[仅在本地保留的材料](docs/local-only-materials.md)。

## 保存范围

首次导入包含 **743 份记录文件**：543 份 JSON、75 份 Markdown、97 份 nft 规则记录、10 份 PowerShell 文件和 18 份文本记录。保留完整批次、停止门槛、失败及恢复证据；较大的 JSON 不在 README 中展开。保留原 `outputs/` 与 `work/` 目录层级，文档中的本机链接已改为仓库相对链接。

认证凭据、私有订阅、代理密码、SSH 密钥、原始私有配置、固件二进制及设备私有恢复包不进入仓库。JSON 中的敏感值以 `[REDACTED]` 替代，非敏感状态、数字、哈希和验证边界保留。上游源码的本地缓存未整包导入；研究文档中的固定版本与公开来源链接用于追溯。

`archive-manifest.json` 逐项记录原文件及导出文件的大小、SHA256 与脱敏次数。导出副本经过脱敏、链接改写和文本换行规范化，导出哈希可能与原文件不同；原工作区文件保持原样。`docs/archive-verification.json` 记录本次文件、JSON、链接及哈希检查范围。

本仓库是记录存档，不能单独代替设备完整恢复备份。恢复文档里的私有包及部分脚本仍需在原本地资料中查找。历史上验证过的双通道软件重启或无线重建，也不能替代当前三路、WED 和新队列的冷启动验证。

后续更新应直接修订当前说明及相应结论，并保留新实验的原始证据和条件。先检查私有材料与链接，再提交；推送按用户授权执行。仓库内的脚本和规则用于追溯，运行前仍须核对目标设备、版本、范围与恢复入口。
