# OpenClash / Ninja 固定版本部署材料

供主代理审阅和执行。本代理只下载并检查公开文件；未连接路由器，未执行 ARM64 核心，未读取订阅或任何凭据。所有文件均位于本目录。

## 已校验文件

| 文件 | 字节数 | 来源 |
| --- | ---: | --- |
| luci-app-openclash-0.48.002.apk | 10,702,048 | https://github.com/vernesong/OpenClash/releases/download/v0.48.002/luci-app-openclash-0.48.002.apk |
| luci-app-ninjaconnector2-1.1.0-r4.apk | 11,156 | https://github.com/kachetong1314/ninja/releases/download/0.1.13/luci-app-ninjaconnector2-1.1.0-r4.apk |
| ninja-arm64-upx | 18,749,664 | https://github.com/kachetong1314/mihomo-ninja/releases/download/ab32ad2d/ninja-arm64-upx |

SHA256SUMS 中三项均与官方 GitHub asset digest 一致。Connector 相同 digest 亦发布在 https://github.com/kachetong1314/mihomo-ninja/releases/download/verge2.5.2/luci-app-ninjaconnector2-1.1.0-r4.apk 。SHA 对应发布方文件一致性，不证明闭源内核功能或可信性。

Ninja 静态检查：ELF magic 7f454c46，ELF64，小端，ET_EXEC，e_machine=183（AArch64），entry=0x6f2093c，UPX! 标记 offset 236。没有执行或解压 UPX。运行兼容、版本、配置测试需在目标 ARM64 路由器另验。

## APK 元数据与依赖

inspect_apk.py 只读取 ADB metadata，并按每个选定载荷文件的内置 SHA256 校验后提取文本脚本。字段定义来自 alpinelinux/apk-tools 官方 src/adb.[ch]、src/apk_adb.[ch]，副本在本目录。解析结果保存为 *.apk.metadata.json。

OpenClash APK：name=luci-app-openclash，version=0.48.002，arch=noarch，installed-size=28,863,438 字节，336 个文件，逐文件逻辑长度之和也为 28,863,438。依赖：bash、ca-bundle、curl、dnsmasq-full、ip-full、kmod-tun、libc、luci-compat、ruby、ruby-yaml、unzip。提供 luci-app-openclash-any。

Connector APK：name=luci-app-ninjaconnector2，version=1.1.0-r4，arch=noarch，installed-size=33,356 字节，10 个文件。依赖：ca-bundle、curl、jsonfilter、luci-app-openclash、luci-base、luci-compat。

fw4 另需按当前 feed / 6.18.55 内核 ABI 核对 kmod-nft-tproxy、kmod-inet-diag。它们只在 OpenClash Makefile 的构建选择中，未进入本 APK runtime depends。dnsmasq-full 必须支持 nftset。不能强制安装 ABI 不匹配的 kmod。dnsmasq 与 dnsmasq-full 的替换由主代理先 dry-run、保留原配置并顺序处理 DHCP/DNS 连续性。

两个 APK 均存在 ADB 签名块；本机未验证路由器是否信任对应公钥。需要 allow-untrusted 时应限定这些已核 SHA 的本地 APK，不把系统信任校验永久关闭。不要为常规安装使用 force-overwrite/clean-protected，除非已核实实际冲突和保留策略。

## 安装及配置顺序

1. 保留当前 UCI、DHCP/DNS、firewall 和服务状态，核对空间、APK feed、内核 ABI；先模拟依赖安装。不得在依赖不完整时启动 OpenClash。
2. 将本目录三份文件传到路由器 /tmp 的专用暂存目录，再在路由器用 SHA256SUMS 重新校验。APK 下载包不应长期占 overlay。
3. 先安装匹配当前内核的依赖，再安装 OpenClash 和 Connector 本地 APK。每步读回包版本/实际依赖。OpenClash 初始 UCI 为 enable=0、small_flash_memory=0、smart_enable=0。其 uci-defaults 创建 core 目录、设置架构，并会调整 uhttpd 请求/超时配置、重启 uhttpd；Web 可能短暂重连。Connector postinst 建 UCI、设 0600、清 LuCI 缓存，不自动下载核心或订阅。
4. 保持 OpenClash disabled；把已校验 UPX 核心以 clash_meta.new 放入 /etc/openclash/core，chmod 0755，目标端复核 SHA。先执行 -v 验证 CPU/UPX/内核可运行，再将已保留的旧文件与新文件原子切换。不要先启动服务触发公版核心下载。
5. 明确设置 small_flash_memory=0、smart_enable=0、core_type=Meta，清除不适用的 oix_token（只影响新安装配置；已有用户值先保留）。核心单副本固定放 /etc/openclash/core/clash_meta。无需长期 .bak 核心副本；旧核心备份留本机的已授权私密备份位置，更新时按真实空间预算决定。
6. 订阅仅由主代理保存到私密配置文件或 Connector UCI（0600），禁止写入报告、命令行可见参数或普通日志。先以固定内核检查原配置，再检查 OpenClash 生成配置。首阶段 Redir-Host 非 TUN、规则模式、router_self_proxy=0、enable_redirect_dns=1；DNS 和校园绕行由主代理统一配置。
7. 安装下述防覆盖措施，再启用；依次验收实际核心 PID/版本/文件 SHA、DNS、防回环、代理出站、校园认证/心跳与正常退出还原。冷启动需按主任务的在线窗口验收，不能用静态检查替代。

## 防覆盖策略

没有发现 OpenClash 原生的“永不替换私有核心”开关。关闭订阅自动更新不等于关闭核心更新。一键更新调用 openclash_core.sh Meta；Smart/Oix 选择、核心缺失、UI 手动上传，以及插件升级均可能影响固定核心或保护脚本。

当前执行范围采用以下可恢复的两处更新入口保护，两个候选脚本已经准备，逐个 bash -n 通过，尚未在路由器安装或执行。先不改 init；由主代理在首次启动前后、重启后核对核心 SHA：

- 将实际 /usr/share/openclash/openclash_core.sh 备份到本机，并用 core-update-blocked.sh 替换。它失败退出，阻止原版核心下载。当前 APK 原脚本 SHA256=66d7130b23947a23d255ed2d57f2da0bb3feabbae1fd88af4f81d3de746e6189。
- 将 /usr/share/ninjaconnector2/ninja_kernel.sh 保存为同目录 ninja_kernel.vendor.sh，再用 connector-kernel-guard.sh 替换入口。它只拒绝 install，保留架构/路径/版本读取。原脚本 SHA256=670c41df8694fa22dd01a1310ef77663be125306ea45803931df8f3d9ff223db。Connector 原 helper 固定选完整 ninja-linux-arm64，不能让它覆盖 UPX 为 57 MB 版本。
- 不启用插件自动升级，也不使用“一键更新”。日后插件或 Connector 更新会覆盖这些包管理文件，必须停止服务、核 SHA、重装保护并做启动验收。普通 APK 版本记录不能被当作不可绕过的安全锁。

这些措施阻止常规更新入口，不能对抗管理员手动覆写保护。OpenClash“一键更新”在核心脚本失败后仍可继续更新插件，并可能覆盖保护入口，因此不能用它测试 guard。手动上传核心也会绕过更新入口。发生错配时保持停用、读回实际 SHA，恢复已核验版本；不要自动下载“最新版本”自修复。

另备 ninja-preflight.sh（bash -n 通过）作为可选增强，当前不安装、不修改 init。它检查固定核心 SHA、持久目录、Meta/Smart/Oix 选择且不输出订阅或 UCI 值。如以后明确采用，调用位置应在 /etc/init.d/openclash 的 start_service() 中 enable 检查通过后、procd_running 与改写配置之前，失败则 return；需要保留原 init，确保插入点恰为 1，并重新 sh -n。当前 APK init SHA256=f664f3a47a27bc38ff92e26d88fd90c6414d68162d0f4538eadde6f72a01fc44。

人工 Ninja 更新顺序：停 OpenClash；下载明确 tag 的官方 UPX，核 digest 和 ELF；先在 /tmp 完成 -v、配置测试；核 overlay 空间；备份旧核心到本机；写目标同目录 .new、再次校验并原子切换；同步版本记录（如启用 preflight 则同步其期望 SHA）；验证服务与网络；成功后清受控暂存。不能同时保留两份不必要的大核心并继续写数据库。

## 已知边界

APK 文件 10.7 MB，展开逻辑内容 28.9 MB；UPX 核心 18.75 MB。UBIFS 有透明压缩，实际空间不能仅用展开字节数相加断言。依赖、数据库、overlay metadata、更新峰值和启动 RAM 必须以目标端读回为准。Ninja 闭源，UPX 可运行和 Mihomo 兼容性尚未验证；原配置/生成配置检查通过也不证明认证、代理出站或实际客户端流量成功。
