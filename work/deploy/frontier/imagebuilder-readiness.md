# AX6000 ImageBuilder 维护准备与 DNS hook 契约

结论：可以准备本地 ImageBuilder 配方，把固定常用软件放入 SquashFS，减少后装软件对 overlay 的占用。当前尚不具备“拿 ASU 默认保留包直接刷入”的条件：Ninja 固定核心、订阅事务、许可恢复、双认证及 MWAN3 代码补丁都需要明确的本地恢复方案。此文件是可审阅准备材料，没有下载 ImageBuilder、构建固件、调用 ASU、SSH、修改设备或恢复私有配置。

## 已核对的设备与版本边界

- 任务给定设备为 Redmi AX6000 RB06，stock layout，OpenWrt SNAPSHOT，Linux 6.18.55。安装日志中的相关 kmod 确为 6.18.55-r1。
- 最近本地容量记录为 `/dev/ubi0_1`，overlay 总计 63076 KiB、可用 14204 KiB；MemAvailable 为 201264 KiB。此为已保存记录，不代表当前实时状态。
- 本次公开下载站 `profiles.json` 与 `version.buildinfo` 一致为 `r37224-0ad1348fb2`，target 为 `mediatek/filogic`，包架构为 `aarch64_cortex-a53`。这证明当前公开产物的版本，不能证明它与设备上的旧 SNAPSHOT 完全相同。
- 正确 profile 为 `xiaomi_redmi-router-ax6000-stock`，supported device 为 `xiaomi,redmi-router-ax6000-stock`。已有 OpenWrt 后续升级对应 `openwrt-mediatek-filogic-xiaomi_redmi-router-ax6000-stock-squashfs-sysupgrade.bin`。`ubootmod` 的 `.itb`、preloader、FIP 和恢复镜像是另一套 profile，本准备不涉及它们。
- ImageBuilder 使用某次已发布 kernel 和匹配包集合组装镜像，不重新编译内核。全部 kmod 必须来自选定目标构建及其 ABI；“都是 6.18”或“都是 SNAPSHOT”不足以判断兼容。
- stock 分区不会因添加包、指定 `rootfs_size_mb` 或把软件放入压缩只读层而扩大。压缩收益、镜像能否容纳固定核心、刷后 overlay 可用量，都要由真实候选镜像和分区约束确定，不能预先承诺释放多少空间。

公开证据：[当前目标 metadata](https://downloads.openwrt.org/snapshots/targets/mediatek/filogic/profiles.json)、[当前 revision](https://downloads.openwrt.org/snapshots/targets/mediatek/filogic/version.buildinfo)、[设备定义](https://github.com/openwrt/openwrt/blob/d66966e4803b868bdaed4b82bd79dd1916dff24e/target/linux/mediatek/image/filogic.mk)、[stock 与 U-Boot 布局说明](https://openwrt.org/toh/xiaomi/redmi_ax6000)、[SNAPSHOT 的 kmod 版本约束](https://openwrt.org/releases/snapshot)。

## 包清单分层

这份清单给出需要保留的顶层功能，尚不是可直接执行的完整 `PACKAGES` 参数。随后已收到 `frontier/state-before.json` 的安全 world 清单。它包括 APK checksum 约束、旧 kernel／base-files／libc 版本 pin，以及同时存在的 dnsmasq／dnsmasq-full 选择，不能直接拼成跨构建 `PACKAGES`。需按目标包元数据解析真实已安装包、直接选择与自动依赖，再形成增量配方。

| 层 | 配方与保留内容 | 处理方法 |
| --- | --- | --- |
| 设备及系统默认 | stock profile 的默认包和 `kmod-leds-ws2812b`、`kmod-mt7915e`、`kmod-mt7986-firmware`、`mt7986-wo-firmware` | 保留所选构建的 profile 默认集合，先做增量配方。不要用不完整绝对列表删默认驱动、netifd、fw4、APK、证书或无线认证组件。 |
| 已使用的上游功能 | LuCI 当前所用组件、`dnsmasq-full`、`bash`、`curl`、`ip-full`、`tc-full`、`kmod-macvlan`、`kmod-nf-tproxy`、`kmod-nft-tproxy`、`kmod-tun`、`kmod-nf-conntrack-netlink`、`kmod-sched-core`、`kmod-sched-bpf`、`kmod-ifb`、`adblock-fast` 及现有对应 LuCI 包 | 日志证实其中多数已安装；adblock-fast 由现有脚本及备份清单证实使用。最终按 live safe world 名单选顶层包，由同一构建解析依赖。使用 `dnsmasq-full` 时在增量配方明确替换默认 `dnsmasq`，避免冲突。不要顺带更换当前 wpad 变体。 |
| Ruby／Lua 运行依赖 | `ruby`、`ruby-yaml`、`ruby-psych`、`ruby-digest`，以及现有 `luci-compat`、`luci-lua-runtime` 和所需模块 | 生产 overwrite、许可恢复、容量守护和订阅事务依赖 Ruby。不能以“精简”为由删除。`ruby-psych` 的间接依赖等应由选定构建的包元数据解析。Lua 组件按当前插件及本地健康探针需求保留。 |
| 需明确来源的包／二进制 | 已安装 `luci-app-openclash` 0.48.002、`luci-app-ninjaconnector2` 1.1.0-r4；本地导入的 `mwan3` 3.6.12-r1；`esurfingclient`、`luci-app-esurfingclient`、`ua3f` 和固定 UPX Ninja 核心 | OpenClash 和 Connector 来自本地 APK；MWAN3 来自本地 25.12 架构 APK，之后另有本地代码补丁。安全 world 证实后三个客户端包名，均带 APK checksum 约束，不能假定目标构建有相同产物。不能假定远端 ASU 能从设备复制这些文件。需要逐项记录源码／许可证、版本、APK／二进制 SHA256、架构及与目标用户态依赖。固定核心不得由插件安装入口自动替换。 |
| 仅在 CAKE 评估通过后纳入 | `kmod-sched-cake`，需要持久 SQM 管理时再考虑 `sqm-scripts`、`luci-app-sqm`；`tc-full` 与 `kmod-ifb` 已属于现有准备 | 现在不启用整形，不因配方准备自动新增。上游 `kmod-sched-cake` 明确依赖 `kmod-sched-core`。具体网卡、速率、开销和 offload 协作由真实双通道验收决定。 |

安全 world 还明确选择 `luci-ssl`、`luci-i18n-base-zh-cn`、`openssh-sftp-server`、`tcpdump-mini`、`smartdns`、`unzip` 和 `wpad-basic-mbedtls`。默认先保留，smartdns 是否实际启用须核对后再决定是否移除，不能仅由包名判定当前 DNS 正在使用它。不要纳入本次用户排除的 Kuma、Tailscale、collectd，也不通过更换 Ninja／代理协议来精简固件。不同版本的共享库名称会变化，日志中的 `libruby4.0` 等不应直接硬编码成跨版本长期要求。

本地证据入口：`base-dependencies-install.json`、`proxy-dependencies-install.json`、`openclash-install.json`、`mwan-installed.json`、`sqm-ifb-install.json`、`root/install_core.py`、`root/install_ua3f_roundrobin.py`、`root/finalize_subscription_maintenance.py`，均位于此工作目录的 `work/deploy` 下。

## ASU 不能自动重建的现有内容

ASU 核心能力是按包名生成定制镜像。当前服务 schema 也支持显式 repositories 和首次启动 defaults，这不等于会扫描并打包设备上的任意修改文件。普通“保留配置”由本机 sysupgrade 备份机制处理，能否备份某文件、是否正确恢复、恢复后代码是否适配新版本，是独立检查。

需要单独维护的内容至少包括：

1. `/etc/openclash/core/clash_meta` 固定核心及 SHA256，OpenClash／Connector 的核心更新拒绝入口，原 vendor helper 的恢复副本。
2. `/etc/init.d/openclash` 的许可恢复调用；`restore-ninja-license.rb`；custom overwrite 和 `ninja-production-options.yaml`；订阅源与生成配置的私有恢复材料。
3. `/usr/share/openclash/openclash.sh` 的固定 Ninja 订阅入口、共享 flock inode 防护；Connector 的 LuCI controller、`ninja_sub.sh` 事务 wrapper；订阅 Ruby helper、capacity module 和选项。
4. `/lib/mwan3/mwan3.sh`、`/lib/mwan3/mwan3-create-iface-route.uc`、`/usr/sbin/mwan3track` 的已部署本地修改；esurfingclient／UA3F 的 init、netifd guard、route hotplug 与 nft 规则。
5. adblock-fast 的本地代码调整、离线列表和路径；无线 steering 的 reload/hotplug；`local-health-recovery` init、probe 和执行文件及开机链接。

`/etc/sysupgrade.conf` 已有新增包含条目不等于恢复验收。本地隔离展开记录明确为 `production_restore_performed=false` 且未恢复权限／属主／运行行为。不能把备份内存在固定核心称为“可直接回滚”。跨版本恢复旧 `/etc/init.d`、`/usr/share` 或 `/lib` 文件可能覆盖新包的生命周期代码，应按新版本源码重新验证补丁契约，或将这些调整整理为本地维护包，再通过本地 ImageBuilder 固定纳入。

本次不提交 ASU 请求，不发送首次启动脚本、订阅、认证账号、配置备份或私有 URL。可继续只准备不带凭据的 manifest、补丁文件和本地配方。ASU 能力边界见 [官方项目](https://github.com/openwrt/asu)、[BuildRequest schema](https://github.com/openwrt/asu/blob/main/asu/build_request.py)、[sysupgrade 备份实现](https://github.com/openwrt/openwrt/blob/main/package/base-files/files/sbin/sysupgrade)。

## 国内 DNS 的持久层与更新契约

现有 `root/maintenance-production-overwrite.sh` 明确只修改 OpenClash 传入的生成配置，保留订阅源。第 153–165 行按以下顺序工作：设置 `redir-host`；合并 `dns_nameserver_policy`；合并 `dns_overrides`；最后按非空 `dns_proxy_server_nameserver` 设置代理节点的 bootstrap。

因此新国内 DoH 的持久定义应写入本地 `ninja-production-options.yaml`，由现有 custom overwrite 生成。校园 exact／suffix policy 留在 `dns_nameserver_policy`；默认 nameserver、fallback、direct-nameserver 等完整字段按主代理给出的安全结构放在 `dns_overrides`。不要改服务端订阅源，也不要仅改 `/etc/openclash/Ninja.yaml`，后者会在重启／更新时重新生成。

两个具体覆盖风险需要处理：

- `dns_overrides` 的 `nameserver-policy` 若存在，会通过 Hash merge 覆盖先前完整 policy，因此应保留单一 policy 所属层，或在 hook 中显式深合并；默认字段的简单 merge 不等于递归 merge。
- `dns_proxy_server_nameserver` 最后执行，会覆盖 `dns_overrides` 中同名字段；国内／国外 DoH 的 bootstrap 归属必须明确。DoH URL 的路由标记、bootstrap、fallback-filter 和校园条件解析都属于待核对的实际契约，不能仅见 `https://` 就判定已正确分流。

订阅事务的容量版 helper 第 254–258 行检查固定选择契约并 fingerprint hook、production options、license restore 和事务 options；第 277–284 行对新源建立 projected 候选，调用同一 hook、恢复许可，然后 core test。正式更新前第 287 行重新核对这些文件未变。这个路径能让新 DNS 策略随订阅重新生成，且并发修改会拒绝提交。

已读安全 DNS 结构：global nameserver、default-nameserver 和 proxy-server-nameserver 均为现有两项明文 bootstrap；国外 fallback 是带固定代理组路由的 DoH；policy 仅有 `+.189.cn` 与 `+.gdpu.edu.cn` 校园／认证相关项。主代理已选择只新增 12–20 个已确认国内后缀的 DoH policy，不替换以上全局字段。现 options 的 dns_overrides 不含 nameserver-policy，因此这次追加会被既有 merge 正确继承。

本轮可以采用独立 validate helper，无需修改公共订阅事务：比较候选与旧生成 DNS，排除 nameserver-policy 后 deep equality；policy key 集合必须恰为旧 key 与新增 key 的并集；旧每项 key/value 均严格相等；新增每项值与 production options 完全一致。名单不能覆盖校园／认证项或国外 fallback-filter 的域。另读回 HK02 单成员、许可、UA3F TCP 规则及其他规则不变，做一次真实重新生成及有限查询。当前事务 fingerprint 与 projected hook 路径已经保护本次 policy 的继承。

当前 generated validation 只强制 `mode=rule`、DNS `enhanced-mode=redir-host` 和许可／节点结构；通用 nslookup 或缓存命中仅能证明解析成功，不能证明请求到达指定 DoH，也不能证明普通 DNS 上游没有漏发。后续确有维护需要时，可以在 validate_generated 增加“production options 中声明的 DNS policy 与生成配置一致”的 subset equality，保护订阅源变动和 hook 行为，但本轮不必扩大公共 helper 的影响范围。

## 进入实际构建前的可审阅结果

下一步应先得到一份固定 revision／target／profile、顶层包名、需移除默认包、第三方来源与 SHA256、本地补丁及无凭据 FILES 的 manifest；另将私有恢复材料保留在本地受保护目录。选择当前公开 SNAPSHOT 是一次目标版本变更，选择相同旧 revision 则必须找齐其匹配 ImageBuilder／package／kmod 产物，两者不能混装。

只有候选真实构建后才能报告镜像尺寸、manifest、可验证 profile 元数据、校验和、目标分区适用性及预期占用。构建成功不证明可联网或可恢复。实际刷机前仍需验证当前 stock 恢复入口与原有恢复材料，保留已验证固件版本和配置／runtime 成对备份；备份无法代替坏固件时的串口／TFTP 等独立入口。本次未迁移 bootloader、未更改分区、未测试恢复，也不把设备两个 vendor slot 推断为可用自动 A/B 回滚。
