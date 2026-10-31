# 路由器 Ninja 核心更新核对与执行条件

本轮确认目标仅为路由器 ARM64 UPX Ninja 核心。发布方公开裸核心最新仍是 `ab32ad2d`，与主代理提供的当前版本相同；截图中的 `NinjaV2 1.0.6` 是另一组客户端发布。当前推荐是核对设备实际版本与完整 SHA256：两者与下面的官方附件一致就保留现有核心，本轮没有可升级到的更高裸核心，不为版本号较大而重复替换或安装另一客户端。[裸核心最新发布](https://github.com/kachetong1314/mihomo-ninja/releases/tag/ab32ad2d)、[截图对应发布](https://github.com/kachetong1314/ninja/releases/tag/1.0.6)。

本支线通过 agent-reach 的 GitHub／gh API 及发布页只读核对公开资料，只写本计划和 [release-safe.json](release-safe.json)。没有 SSH、二进制下载、解包、安装、设备配置读取或生产变更。Windows Clash Verge、Android、NinjaDesktop／Lite 不在本轮更新目标内。固定香港 02、当前 source 和 Ninja 协议保持。

## 当前确切候选

| 字段 | 发布方公开值 |
| --- | --- |
| 仓库 | `kachetong1314/mihomo-ninja` |
| tag | `ab32ad2d` |
| ARM64 附件 | `ninja-arm64-upx` |
| 字节数 | 18,749,664 |
| SHA256 | `3398a44cca5db17710491ec3bb474c3c1cd4a30a3f849eb063dcfd2abd35375b` |
| 下载入口 | [固定 tag 的 ARM64 UPX](https://github.com/kachetong1314/mihomo-ninja/releases/download/ab32ad2d/ninja-arm64-upx) |
| release 时间 | GitHub API `2026-09-26T17:33:07Z` |
| release 说明 | 发布方称同步上游 `5019cc09`，并继续优化 Ninja 的 TLS 握手 |
| 本轮设备验收 | 由主代理读回；本支线没有执行 |

这个 SHA 来自 GitHub release asset digest，支持文件与该发布方附件一致，不证明协议运行、许可有效或源码与二进制可复现。`ninja-linux-arm64` 为另一份未压缩附件，57,213,054 字节；本轮不把它替换进空间有限的固定 UPX 部署。[附件元数据 API](https://api.github.com/repos/kachetong1314/mihomo-ninja/releases/latest)。

## 截图的 24 项分别是什么

发布页显示 24 项；API 的上传附件有 22 件，另有 GitHub 自动生成的 `Source code (zip)` 和 `Source code (tar.gz)`。下面列出全部 24 项。22 件的完整 digest、下载 URL 和精确字节数已保存在 `release-safe.json`；两个自动压缩包在 release API 中没有 asset digest。该 tag 的公开树仅含 README，源码压缩链接不是 Ninja 核心实现。[展开附件页](https://github.com/kachetong1314/ninja/releases/expanded_assets/1.0.6)、[该 tag 的公开树](https://api.github.com/repos/kachetong1314/ninja/git/trees/1.0.6?recursive=1)。

| 序号 | 附件 | 字节数 | 与本轮的关系 |
| --- | --- | ---: | --- |
| 1 | [NinjaClient-3.1.4.apk](https://github.com/kachetong1314/ninja/releases/download/1.0.6/NinjaClient-3.1.4.apk) | 92248471 | 发布方安装包；不作为本轮核心更新 |
| 2 | [NinjaClientTV-3.1.4-arm64-v8a.apk](https://github.com/kachetong1314/ninja/releases/download/1.0.6/NinjaClientTV-3.1.4-arm64-v8a.apk) | 86956088 | 发布方安装包；不作为本轮核心更新 |
| 3 | [NinjaClientTV-3.1.4-armeabi-v7a.apk](https://github.com/kachetong1314/ninja/releases/download/1.0.6/NinjaClientTV-3.1.4-armeabi-v7a.apk) | 81964322 | 发布方安装包；不作为本轮核心更新 |
| 4 | [NinjaDesktop-1.0.6-linux-amd64.deb](https://github.com/kachetong1314/ninja/releases/download/1.0.6/NinjaDesktop-1.0.6-linux-amd64.deb) | 132822396 | 发布方安装包；不作为本轮核心更新 |
| 5 | [NinjaDesktop-1.0.6-linux-arm64.deb](https://github.com/kachetong1314/ninja/releases/download/1.0.6/NinjaDesktop-1.0.6-linux-arm64.deb) | 123620676 | 发布方安装包；不作为本轮核心更新 |
| 6 | [NinjaDesktop-1.0.6-mac-arm64.dmg](https://github.com/kachetong1314/ninja/releases/download/1.0.6/NinjaDesktop-1.0.6-mac-arm64.dmg) | 157833236 | 发布方安装包；不作为本轮核心更新 |
| 7 | [NinjaDesktop-1.0.6-mac-x64.dmg](https://github.com/kachetong1314/ninja/releases/download/1.0.6/NinjaDesktop-1.0.6-mac-x64.dmg) | 169640606 | 发布方安装包；不作为本轮核心更新 |
| 8 | [NinjaDesktop-1.0.6-win-arm64.exe](https://github.com/kachetong1314/ninja/releases/download/1.0.6/NinjaDesktop-1.0.6-win-arm64.exe) | 140059720 | 发布方安装包；不作为本轮核心更新 |
| 9 | [NinjaDesktop-1.0.6-win-x64.exe](https://github.com/kachetong1314/ninja/releases/download/1.0.6/NinjaDesktop-1.0.6-win-x64.exe) | 150220768 | 发布方安装包；不作为本轮核心更新 |
| 10 | [ninjadesktop-lite-1.0.6-all-aarch64.apk](https://github.com/kachetong1314/ninja/releases/download/1.0.6/ninjadesktop-lite-1.0.6-all-aarch64.apk) | 39124973 | 发布方安装包；不作为本轮核心更新 |
| 11 | [ninjadesktop-lite-1.0.6-all-armv7.apk](https://github.com/kachetong1314/ninja/releases/download/1.0.6/ninjadesktop-lite-1.0.6-all-armv7.apk) | 39660388 | 发布方安装包；不作为本轮核心更新 |
| 12 | [NinjaDesktop-Lite-1.0.6-darwin-arm64.dmg](https://github.com/kachetong1314/ninja/releases/download/1.0.6/NinjaDesktop-Lite-1.0.6-darwin-arm64.dmg) | 99198157 | 发布方安装包；不作为本轮核心更新 |
| 13 | [NinjaDesktop-Lite-1.0.6-darwin-x64.dmg](https://github.com/kachetong1314/ninja/releases/download/1.0.6/NinjaDesktop-Lite-1.0.6-darwin-x64.dmg) | 107878099 | 发布方安装包；不作为本轮核心更新 |
| 14 | [NinjaDesktop-Lite-1.0.6-win7-x64-setup.exe](https://github.com/kachetong1314/ninja/releases/download/1.0.6/NinjaDesktop-Lite-1.0.6-win7-x64-setup.exe) | 56538841 | 发布方安装包；不作为本轮核心更新 |
| 15 | [NinjaDesktop-Lite-1.0.6-windows-arm64-setup.exe](https://github.com/kachetong1314/ninja/releases/download/1.0.6/NinjaDesktop-Lite-1.0.6-windows-arm64-setup.exe) | 48681946 | 发布方安装包；不作为本轮核心更新 |
| 16 | [NinjaDesktop-Lite-1.0.6-windows-x64-setup.exe](https://github.com/kachetong1314/ninja/releases/download/1.0.6/NinjaDesktop-Lite-1.0.6-windows-x64-setup.exe) | 52491745 | 发布方安装包；不作为本轮核心更新 |
| 17 | [ninjadesktop-lite-1.0.6-x86_64.apk](https://github.com/kachetong1314/ninja/releases/download/1.0.6/ninjadesktop-lite-1.0.6-x86_64.apk) | 41743281 | 发布方安装包；不作为本轮核心更新 |
| 18 | [ninjadesktop-lite_1.0.6_all-aarch64.ipk](https://github.com/kachetong1314/ninja/releases/download/1.0.6/ninjadesktop-lite_1.0.6_all-aarch64.ipk) | 38331999 | 发布方安装包；不作为本轮核心更新 |
| 19 | [ninjadesktop-lite_1.0.6_all-armv7.ipk](https://github.com/kachetong1314/ninja/releases/download/1.0.6/ninjadesktop-lite_1.0.6_all-armv7.ipk) | 38900573 | 发布方安装包；不作为本轮核心更新 |
| 20 | [ninjadesktop-lite_1.0.6_amd64.deb](https://github.com/kachetong1314/ninja/releases/download/1.0.6/ninjadesktop-lite_1.0.6_amd64.deb) | 37649296 | 发布方安装包；不作为本轮核心更新 |
| 21 | [ninjadesktop-lite_1.0.6_arm64.deb](https://github.com/kachetong1314/ninja/releases/download/1.0.6/ninjadesktop-lite_1.0.6_arm64.deb) | 33935436 | 发布方安装包；不作为本轮核心更新 |
| 22 | [ninjadesktop-lite_1.0.6_x86_64.ipk](https://github.com/kachetong1314/ninja/releases/download/1.0.6/ninjadesktop-lite_1.0.6_x86_64.ipk) | 40940750 | 发布方安装包；不作为本轮核心更新 |
| 23 | [Source code (zip)](https://api.github.com/repos/kachetong1314/ninja/zipball/1.0.6) | API 未提供 | GitHub 自动仓库压缩包，仅 README |
| 24 | [Source code (tar.gz)](https://api.github.com/repos/kachetong1314/ninja/tarball/1.0.6) | API 未提供 | GitHub 自动仓库压缩包，仅 README |

## 客户端版本、裸核心与上游不能互换

`ninja` 仓库说明将 Ninja 2.0 描述为修改 Mihomo／Leaf 的核心与多平台客户端方案，并把 Ninja Core 入口明确指向 `mihomo-ninja/releases`。因此 `1.0.6` 不能当作裸核心 tag。其 release body 为空，公开树没有 build manifest 或协议实现，本轮没有解包客户端；不能确认这些客户端是否包含同一个 core、其内嵌 core 的 build／SHA，也不能推出它们的运行时配置可以直接搬给 OpenClash。[客户端仓库说明](https://github.com/kachetong1314/ninja/blob/main/README.md)。

`mihomo-ninja` 的 README 主张与 Mihomo pin 兼容、可替换使用 Mihomo 核心的客户端。这是发布方兼容主张；公开仓库仅 README，没有可审阅的 Ninja 实现或机器可读配置 schema。裸核心最新稳定发布仍为 `ab32ad2d`。日期较后的 `verge2.5.3` 是 prerelease 客户端集合，只有 macOS／Windows Clash Verge Ninja 与 Android CMFA 三件，没有新 ARM64 UPX；不能当作路由器核心升级。[核心 README](https://github.com/kachetong1314/mihomo-ninja/blob/main/README.md)、[客户端 prerelease](https://github.com/kachetong1314/mihomo-ninja/releases/tag/verge2.5.3)。

上游 MetaCubeX/Mihomo 当前 latest 为 `v1.19.32`。Ninja release 声明的上游提交为 `5019cc090ed7cafb76643f964a76b1e97aee2985`，两者不是同一个版本坐标。上游更新不证明 Ninja 发布方已同步，也不证明公版二进制支持当前 `ninja` 节点；本轮不替换成公版 Mihomo，不迁移协议或 source。[上游发布](https://github.com/MetaCubeX/mihomo/releases/tag/v1.19.32)、[声明的上游提交](https://github.com/MetaCubeX/mihomo/commit/5019cc090ed7cafb76643f964a76b1e97aee2985)。

## 配置、许可与恢复边界

两仓库 GitHub API 的 license 字段均未给出许可证，客户端 README 又有商业授权说明；这些信息不能代替当前账号／服务的许可验收，也不能推断当前使用权失效。本轮保留既有许可相关文件、权限、属主和恢复约定，不输出值，不主动触发重新注册或更换客户端授权流程。[核心仓库元数据](https://api.github.com/repos/kachetong1314/mihomo-ninja)、[客户端商业授权说明](https://github.com/kachetong1314/ninja/blob/main/README.md)。

同一 tag 与同一 digest 的二进制没有新增 schema 变更；如果设备确实匹配它，当前已验收配置可以保留。如果设备 SHA 不匹配，不只凭版本字符串就覆盖：先确认是另一公开附件、旧版或未知修改，保存可恢复的当前二进制与配置后再决定。未来新 Ninja tag 必须重新做原配置、生成配置和实际出站验收，不能把 README 的兼容主张当成功证据。

ARM64 UPX 需要目标 CPU、Linux 执行和内存条件；API 名称不是 ELF 或运行验收。升级候选应先在 RAM 暂存目录检查 digest、ELF64／AArch64、可执行权限、`-v` 和当前配置的 `-t`。当前已运行的同文件不必为此停服务重测。不得为检查而解压到 overlay 或通过 Connector helper 自动下载较大的完整核心。

## 主代理的最小执行入口

1. 先读回运行中核心 PID、实际可执行文件路径、`-v` 和该文件完整 SHA256；核官方固定 tag 的 UPX digest。保持认证三路、UA3F、DNS、香港 02 和 source。若 tag 与 SHA 均一致，记录“已是当前最新核心”，结束更新核对；无需停 OpenClash、重启路由器或替换同文件。
2. 只有实际文件不匹配或未来出现新的裸 ARM64 UPX，才进入候选验证。用已授权的本地恢复位置保存旧核心、生产 options、overwrite／订阅事务、许可及当前规则相关文件；读回权限／属主和空间预算。恢复材料不写入公开计划或上传公共站点。
3. 下载明确 tag 的 `ninja-arm64-upx`，在 RAM 暂存后核发布方 digest，再做 `-v`、原 source 与生成候选 `-t`。两类配置测试都不输出私有节点／凭据；它们通过仍需真实香港 02 出站验收。
4. 确认 overlay 能承受同目录 `.new` 峰值后，仅短暂停 OpenClash；原子替换实际核心文件，同步固定 SHA 的维护记录和适用 preflight。原两路／第三路认证服务和 UA3F 不重启；不用 OpenClash／Connector 一键更新，不安装新 APK，不做整机或 network restart。
5. 启动后读回 PID／可执行路径／版本／SHA、固定节点与许可状态，验证本轮国内白名单 DoH、国外 DNS／出站、家庭 PAC 与广告规则；校园既有 SERVFAIL 按原边界报告，不能为了核心更新改 DNS。核三路认证 PID／心跳与 MWAN online。短时结果不代表冷启动、长时保活或吞吐改善。
6. 若新核心不运行、配置不兼容、许可或固定节点出站失败，停止该核心并恢复已保存的旧二进制及其已知关联状态，再读回旧 SHA 与业务。回退只覆盖本次明确改动，不恢复整个网络、不清空现有 conntrack，也不自动换公版核心自修复。

以上是候选更新契约。当前公共发布信息没有更高裸核心，因此本轮实际应停在第 1 步，除非主代理现场发现当前文件与官方附件不同。Agent Reach 本轮 `check-update` 回报 v1.5.0 已是最新；未更新任何工具。
