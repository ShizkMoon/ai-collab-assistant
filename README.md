# AX6000 校园网部署与性能记录

本仓库保存 Redmi AX6000（RB06，stock 分区）校园网部署、调优、源码调研、完整实验批次及恢复验证记录。当前记录截至 **2026 年 10 月 27 日**，时区为 UTC+8。入口文档描述最新采用状态；阶段报告和原始证据保留当时的条件、失败与恢复结果。

**2026-10-30 起 Ninja 已回滚到路由器。** 按用户要求恢复 OpenClash `0.48.002`、Ninja Connector 2 `1.1.0-r4` 与固定核心 `ab32ad2d`（`/etc/openclash/core/clash_meta`，SHA256 `3398a44c…d35375b`），LAN 透明代理已生效：本机不设代理访问 `ipinfo.io` 出口 `188.253.112.163`（HK）。启动前把旧生产选项里指向已卸载 UA3F（`127.0.0.1:1080`）与 smartdns（`127.0.0.1:6054/6055`）的引用改掉，否则 DNS 与「全球直连」TCP 包装会全部失败。四路认证、四条 WAN、四出口 TTL64 保持；overlay 回到 73%（可用 15.7 MB）。核心更新入口已加守卫。**本次未重启路由器**，冷启动未验证，吞吐未复测。2026-10-27 的移出记录仍保留在 [代理迁移记录](work/deploy/local-proxy-migration/README.md)，本次回滚见 [Ninja 回滚记录](work/deploy/ninja-rollback-20261030/README.md)。当前运行 OpenWrt SNAPSHOT `r37185-f29dfe25ba`／Linux `6.18.55`，不能将本设备记录直接用于其他固件或设备。

## 当前采用状态

| 项目 | 记录结果与边界 | 主要入口 |
| --- | --- | --- |
| 四路校园认证与分流 | 四个认证实例与四条 WAN（`wan`／`wan2`／`wan3`／`wan4`）当前全部 online，独立 DHCP 地址与 MWAN 新连接分配已读回；第四路与清理后的冷启动仍未验收。 | [使用说明](outputs/ax6000-mainline/使用说明.md)、[代理迁移记录](work/deploy/local-proxy-migration/README.md) |
| TTL 与代理 | 四出口 IPv4 TTL64 规则保留并读回。路由器运行 OpenClash `0.48.002` + Connector `1.1.0-r4` + 固定核心 `ab32ad2d`，`enabled` 已设但未做整机重启；UA3F 与 smartdns 仍未安装，旧选项已改指向公共 DNS。本机 Ninja 仍在 `127.0.0.1:7890` 运行，两者并存未验证出口差异。 | [使用说明](outputs/ax6000-mainline/使用说明.md)、[Ninja 回滚记录](work/deploy/ninja-rollback-20261030/README.md) |
| WED | 运行参数 `Y`、实际挂接及启动文件 `mt7915e wed_enable=1` 已读回。历史保留验收确认三认证、电脑访问与原队列保持；当前四认证与代理移出后的 WED 冷启动未验证，也未在保留验收中重测吞吐。 | [最终保留验收](work/deploy/wireless-repair/wed-retained-acceptance.json)、[实际恢复验证](work/deploy/wireless-repair/wed-restore-entry-verified.json) |
| CAKE、BBR 与 DNS | `codex-cake` 当前 disabled，未加载 CAKE qdisc；历史 650 Mbit 下载队列配置保留。本机新 TCP 默认 BBRv1；dnsmasq 经 OpenClash `7874` 转发，`no-resolv` 已生效。历史 DoH 与队列结论只对应旧配置。 | [队列与传输采用结果](work/deploy/next/adoption-results.md)、[整体研究](outputs/ax6000-mainline/路由器调优与校园网方案调研.md) |
| 性能 | 关闭自有 CAKE 的受控批次证明路由器多连接三路聚合收益；新增第四路后尚未重做同条件聚合验收。电脑公网完整路径稳定 900 Mbps 尚未达到。 | [完整聚合批次](work/deploy/aggregation/controlled-cases.json)、[结果摘要](work/deploy/aggregation/result-summary.json) |
| TCP 接收压力 | 历史 UA3F 外层 socket drops 与内核接收压力已观察；UA3F 已卸载，这些计数只保留为旧路径证据。缓冲限额试验完整 A1／B 为 814.71／812.00 Mbps，未见收益；A2 正文不完整。 | [内核源码解释](work/deploy/wireless-repair/tcp-receive-drop-source-review.md)、[试验摘要](work/deploy/wireless-repair/owned-buffer-cases-summary.json)、[完整采样](work/deploy/wireless-repair/owned-buffer-cases.json) |
| UA-Mask | 历史比较结论保留；UA3F 已卸载，当前没有替换对象。 | [UA-Mask 评估](work/deploy/wireless-repair/ua-mask-assessment.md) |

## 阅读与证据导航

- 日常管理：[使用说明](outputs/ax6000-mainline/使用说明.md)。
- 调研、采用理由与未验证范围：[路由器调优与校园网方案调研](outputs/ax6000-mainline/路由器调优与校园网方案调研.md)。
- 历史汇总：[部署验证](outputs/ax6000-mainline/部署验证.json)。该文件包含多个阶段，不能将整个对象当作同一时刻的完整状态。
- 认证源码与部署：[ESurfing 源码问题](work/deploy/esurfing/SOURCE-BUGS.md)、[netifd 部署](work/deploy/esurfing/NETIFD-DEPLOYMENT.md)、[三路来源审阅](work/deploy/esurfing/three-channel-source-review.md)。
- DNS 与传输候选：`work/deploy/frontier/`；CAKE、BBR 与未采用机制：`work/deploy/next/`。
- 单／双／三出口、电脑和无线对照：`work/deploy/aggregation/`。
- 固定外层路径、WED、TCP 接收压力、CPU 与 UA-Mask：`work/deploy/wireless-repair/`。
- 代理迁移、路由器卸载与浏览器代理验证：[代理迁移记录](work/deploy/local-proxy-migration/README.md)。
- 2026-10-30 回滚到路由器：[Ninja 回滚记录](work/deploy/ninja-rollback-20261030/README.md)。
- 组件维护与恢复：[集成及恢复说明](work/deploy/maintenance/integration-and-recovery.md)、[恢复说明](outputs/ax6000-recovery/恢复说明.md)。
- 导出范围与校验：[文件清单](archive-manifest.json)、[归档验证](docs/archive-verification.json)、[仅在本地保留的材料](docs/local-only-materials.md)。

## 保存范围

首次导入包含 **743 份记录文件**：543 份 JSON、75 份 Markdown、97 份 nft 规则记录、10 份 PowerShell 文件和 18 份文本记录。保留完整批次、停止门槛、失败及恢复证据；较大的 JSON 不在 README 中展开。保留原 `outputs/` 与 `work/` 目录层级，文档中的本机链接已改为仓库相对链接。2026-10-27 新增的代理迁移记录不在首次导入清单内。

认证凭据、私有订阅、代理密码、SSH 密钥、原始私有配置、固件二进制及设备私有恢复包不进入仓库。JSON 中的敏感值以 `[REDACTED]` 替代，非敏感状态、数字、哈希和验证边界保留。上游源码的本地缓存未整包导入；研究文档中的固定版本与公开来源链接用于追溯。

`archive-manifest.json` 逐项记录原文件及导出文件的大小、SHA256 与脱敏次数。导出副本经过脱敏、链接改写和文本换行规范化，导出哈希可能与原文件不同；原工作区文件保持原样。`docs/archive-verification.json` 记录本次文件、JSON、链接及哈希检查范围。

本仓库是记录存档，不能单独代替设备完整恢复备份。恢复文档里的私有包及部分脚本仍需在原本地资料中查找。历史上验证过的双通道软件重启或无线重建，也不能替代当前四路、WED 和新队列的冷启动验证。

后续更新应直接修订当前说明及相应结论，并保留新实验的原始证据和条件。先检查私有材料与链接，再提交；推送按用户授权执行。仓库内的脚本和规则用于追溯，运行前仍须核对目标设备、版本、范围与恢复入口。
