# 认证以外的代理层复核

当前 OpenClash／Ninja 已经完成可用链路和软件重启后的主要验收，日常 TCP、指定 UDP、DNS 与广告过滤都有实际请求证据。它还不能称为所有协议、所有终端入口和故障场景均已完善。现在最值得补的是更新事务、依赖服务故障回退、真实应用入口验收；没有证据支持追加一套通用大规则、自动清空全部连接或直接升级核心。

本次只读本地脱敏记录与官方资料，没有 SSH、校园认证、测速、访问用户订阅 URL 或修改运行配置。运行事实以下列本轮已留存验收为依据；本分支没有重新探测设备。官方资料核对时间为 2026 年 10 月 12 日北京时间。Ninja 协议实现闭源，公版 Mihomo 的源码用于解释兼容字段，不能证明 Ninja 内部传输实现。

主代理于 21:32:20 补回当前脱敏设备快照，随后补回核心 API 与广告过滤状态：核心 API 为 `ab32ad2d`，OpenClash PID 6234；规则模式、Redir-Host、IPv6 关闭、UDP 接管启用、路由器自身代理关闭。当前生成配置为 50 个代理条目、14 个分组、4,415 条规则，其中 919 条为 UA3F TCP 条件规则。主 select 当前指向 URLTest 自动组，该组当前选中的适配器在 API 中报告为 Shadowsocks；这里仅记录 API 类型，不据此认定私有 Ninja 协议等同公版 Shadowsocks。直连相关分组当前均为 DIRECT。`auto_update=0`，adblock-fast 报告阻断 55,349 个域名；缺少推荐工具只是 warning，没有因此安装软件。当前状态与先前重启后的业务验收相符，但这一只读快照本身不是新的业务／节点故障切换试验。证据为 `work/deploy/network-layers-current.json` 和 `network-layers-runtime-addendum.json`。

当前 DNS 所有上游字段没有指向自身 53／7874；正常的 dnsmasq 53→OpenClash 7874 不计为上游自回指。国内 nameserver、default-nameserver 和节点 bootstrap 均仍为 `223.5.5.5`、`119.29.29.29` 的明文 DNS；校园策略保留专用 resolver，fallback 为 `1.1.1.1` DoH 并指定策略组。该明确分工用于独立启动解析，不能描述为全程加密 DNS，也没有已证实问题要求统一改成 DoH。

服务入口方面，当前 controller 监听 `0.0.0.0:9090` 且 secret 已设置，mixed 代理认证已设置。主代理读回 input_wan 的 reject，并补读 OpenClash WAN input 明确拒绝 7874／7890／7891／7892／7893／7895／9090。现有防火墙规则提供边界控制；没有进行外网端口扫描，不能把监听所有接口简单写成公网可达，也不能把规则读回写成外网可达性实测。

## 实际链路及已经验证的能力

| 流量／入口 | 当前路径 | 已有运行证据 | 实际限制 |
| --- | --- | --- | --- |
| Windows 遵从系统 PAC 的应用 | 家庭 IPv4＋家庭 DNS 标识满足后 PAC 返回 DIRECT → 路由器按规则处理 | `ninja/home-pac-runtime-acceptance.json`：实际 PAC handler／磁盘／候选相同，7 个域名原生求值均为 DIRECT，11 项检查通过 | DIRECT 只是跳过 Windows 本机代理；家庭路由器仍可选 Ninja。应用缓存、固定代理和 VPN 不随 PAC 改变；真实外出切换未验证 |
| 国内选定 TCP 与下载域名 | OpenClash Redir-Host → NETWORK,TCP 条件规则 → 回环 UA3F SOCKS → 实际 WAN | 最新使用说明记录国内 HTTPS 200、HTTP UA 为 FFF、软件重启和防火墙重载后成功；专用 UA3F 新连接曾实际两出口各 4 条 | UA3F SOCKS 节点 UDP 关闭；HTTPS 加密内容不做 UA 改写。一条连接仍固定单出口；下载规则没有把全部 Microsoft 或 Steam 服务合并 |
| 代理 TCP | LAN → OpenClash 原订阅分组 → Ninja 外层 → MWAN 选择实际 WAN | 软件重启后代理 generate_204 成功；当前固定 Ninja 核心已有真实运行／配置校验 | 应用请求数量不等于 Ninja 外层连接数；闭源协议共享传输、会话池与失效检测没有公开实现可验证 |
| UDP | LAN UDP TPROXY → OpenClash；低位 0x162 在接管阶段保留；核心新建的外层再选 WAN | `followup-lan-udp-after-reboot.json`：阿里 NTP 48 字节、Google／Cloudflare STUN 各 32 字节，均为匹配请求的有效回包；早期 `lan-udp-core-paths.json` 记录 DIRECT／代理路径 | 已验收的是这些新 UDP 请求，不是所有 UDP 应用。没有 HTTP/3／QUIC 建连、持续传输、MTU 和连接迁移验收 |
| 普通设备 DNS | dnsmasq LAN 53 → 广告名单 → 未命中查询转 OpenClash 7874 → 国内／校园／国外解析策略 | 最新重启后正常域名、家庭 DNS 标识与业务请求成功；已在名单的 doubleclick 域名 NXDOMAIN；55,349 域名加载 | 应用 DoH／DoQ 可绕过 LAN 53；核心自身节点解析不必经过广告入口；同域广告不靠域名即可精确过滤 |
| 节点与 DNS bootstrap | 独立公共 `proxy-server-nameserver` 解析节点；DNS 服务器域名由 `default-nameserver` 解析；裸 DNS 53 的 MWAN default 规则先于 balance | 生产文档记录最终配置自回指检查通过；两条短名称 DNS 规则实际生成；软件重启后 DNS 与代理恢复 | 国外 DoH 经 Ninja 组本身依赖该代理可用；这是访问依赖，不是 53／7874 端口回环。只检查新增 DNS 字段不足，所有继承字段也要复核 |

源订阅摘要为 49 个 Ninja 代理、14 个分组、3,514 条规则，没有 rule-provider，规则内没有 GEOSITE。生产 hook 保留源分组与原规则顺序，只前置校园／本地保护、指定下载规则和选定国内 TCP 的 UA3F 包装。当前 11 条下载域名的 DOMAIN／DOMAIN-SUFFIX 匹配范围已经明确，不能按规则数量判断覆盖正确，也不能因此扩成“所有微软服务直连”。`ninja-rule-summary.json` 的 `direct_rule_types={}` 仅表示源规则没有直接写 `DIRECT`，不表示没有直连路径：原规则会先命中可选择 DIRECT 的策略组。Mihomo 规则自上而下匹配，无 UDP 能力的代理可能继续匹配后续规则，因此 NETWORK,TCP 条件比只把 SOCKS 的 udp 设为 false 更能保持原 UDP 行为。[规则定义](https://wiki.metacubex.one/config/rules/)、[固定上游逻辑匹配实现](https://github.com/MetaCubeX/mihomo/blob/5019cc090ed7cafb76643f964a76b1e97aee2985/rules/logic/logic.go)

## 现存的确定缺口与未完成验收

**更新链尚未闭合。** Connector 1.1.0-r4 的订阅 helper 已有锁、HTTP 200、基本 YAML 检查、备份和原子替换，但没有固定 Ninja 核心 `-t`、Ninja 类型检查和条件 OpenClash 重启，也没有原生 scheduler。现有 `connector-configured.json` 明确为 `automatic_updates_enabled=false`。因此“订阅保存成功／点击下载成功”不等于新的运行配置已生成、许可注释保留、代理实际成功。源规则和 GEOIP 数据仍会随时间变旧；这需要受控维护，而不是安装没有引用的 GEOSITE 或第二套规则。当前关闭自动更新是明确取舍，不能把不存在的日常更新能力写成已实现。

**核心 DNS 与 UA3F 都是当前链路的实际依赖。** OpenClash 固定版本在核心 API ready 后才改 dnsmasq 上游，并在有序 stop 中恢复。它的 ready 不验证解析结果；dnsmasq 被持久设置为唯一 `127.0.0.1#7874`，核心非正常退出后可能暂时没有可用上游。watchdog 会恢复这项独占上游，并按约 60 秒周期检查；运行时直接追加公共 DNS 容错会被重置，也会改变原解析语义。UA3F 消失时，NETWORK,TCP 包装没有自动绕过保证；已有 `enable_ua3f_tcp=false` 可用于受控取消包装，但不是 SOCKS 健康自动回退。当前软件重启成功证明一次完整恢复，不证明核心崩溃和依赖进程异常时无中断。[OpenClash 0.48.002 固定 init](https://github.com/vernesong/OpenClash/blob/e553e82e01c697aefbe1555261a503f425e00ccd/luci-app-openclash/root/etc/init.d/openclash)、[固定 watchdog](https://github.com/vernesong/OpenClash/blob/e553e82e01c697aefbe1555261a503f425e00ccd/luci-app-openclash/root/usr/share/openclash/openclash_watchdog.sh)

**WAN 健康切换与代理节点回退不是同一种功能。** 两次仅阻断第二 WAN 健康探针的试验，第一次 Ninja 新请求 12 秒内超时，第二次在 WAN2 offline 后立即取得 204；第二次没有调用清连接 API。现有证据没有稳定复现故障或证明清连接改善，所以不应加“每次 offline 自动重启核心”。Mihomo `DELETE /connections` 关闭被统计的应用连接，不能据此保证清除私有 Ninja 的所有共享传输。21:32 后的核心 API 已确认主 select 当前指向 URLTest 自动组，自动节点选择已经在使用；现有资料没有受控节点失效、自动改选后实际业务恢复的验收。因此当前没有必要为启用自动选择再改分组，也不能把已选自动组写成故障切换已验证。[API 语义](https://wiki.metacubex.one/api/#connections)、[手动选择](https://wiki.metacubex.one/config/proxy-groups/select/)、[自动选择](https://wiki.metacubex.one/config/proxy-groups/url-test/)

**本机代理入口只完成了 PAC 一类。** 固定写 `127.0.0.1:7897` 的应用和 HTTP_PROXY／HTTPS_PROXY 不遵从 PAC，可能让流量先经过 Windows Ninja 再通过路由器；这不自动证明串联了两个远端代理。修改前的微软下载实际本机链为 DIRECT，经本机一次转发，没有证据是远端节点限速。`Invoke-HomeAwayCli.ps1` 已交付并验证任务范围环境恢复，可供家中 CLI 临时绕过；它不改变已经运行的应用、自带代理或手机 VPN。Android 当前没有版本／设置读回与自动切换验收，实际外出也未测。PAC handler 在 Clash Verge 2.5.2 读取提交后的内存配置，不能以运行中仅改 YAML 代替实际刷新与原生求值。[固定 PAC handler](https://github.com/clash-verge-rev/clash-verge-rev/blob/v2.5.2/src-tauri/src/utils/server.rs)

**QUIC 与公网 IPv6 是独立空白。** 当前 UDP/443 未全局阻断，UDP 代理启用，不能由 NTP／STUN 成功推断 QUIC 已完整通过。HTTP/3 要有真实协议建连与应用响应证据；UDP 传输、长连接、MTU 不由 TCP 测速覆盖。最新生产记录没有公网 IPv6 默认路由，因此当前主要验收为 IPv4，未来 IPv6 需要单独核对 DNS、透明接管和出口；现在没有已证实 IPv6 漏流，也无需为此新建一套管线。

## 最多三个值得完善的动作

1. **补齐受控订阅更新事务。** 复用固定核心与现有 custom hook，提供一个从受限 UCI 读取 URL 的手动维护入口：锁 → HTTPS 候选 → Ninja 类型与 `-t` → 内容变化检测 → 源文件备份／原子替换 → 必要时重新生成并重启 → DNS／实际代理请求读回；失败保留或恢复旧的有效源和运行配置。URL 不放命令参数、cron 或普通日志。先完成一次手动验收，定时频率仅按用户明确更新意图决定；不把内核更新并入订阅更新。这也让源规则、许可和节点变更有可审核的维护路径。
2. **把依赖故障回退变成可观察的操作。** 保留已验收主链，完善有序降级与恢复步骤：UA3F 故障先受控取消自己的 TCP 包装；需要退出 OpenClash 时先 stop/watchdog 退出，再核 dnsmasq 上游、53／7874、自定义路由残留，并从 LAN 验新 DNS＋新 HTTPS。之后在明确维护窗口只验证一个依赖故障及恢复，记录影响范围和耗时。只有稳定复现且有明确恢复效果后才考虑窄范围自动化，不为一次超时添加全局清连接或重启。
3. **补一次真实终端与协议路径验收。** 选择用户常用的一条固定代理 CLI／应用，家中按现有 Home 包装或其单次直连设置运行，核对它确实跳过本机 7897且路由器仍正确分流；保留外出原环境。再在已有授权设备上完成实际家中／外出切换和一个真实 HTTP/3 请求，记录当前入口、协议、策略及回包；Android VPN 由手机实际设置核对。它能区分“PAC 已配置”与“用户这条路径已切换”，也能避免把 TCP／STUN 验收扩写成全部 QUIC 与手机覆盖。

以上三项是后续范围建议，本次没有实施。当前已经选择 URLTest 自动组，无须为了“完善”重新建立分组；自动组故障切换仍按实际业务验收判断。SmartDNS 的先前对照没有一致收益，继续停用合理；没有可定位的新解析问题时不增加 mosdns／AdGuard Home。

## 版本和固定官方来源

- OpenClash：0.48.002，源码固定 `e553e82e01c697aefbe1555261a503f425e00ccd`；本轮通过 gh 重新读取 init 与 watchdog 的关键流程。插件改写 hook 返回码未作为独立启动门禁，许可恢复位置与现有保护仍须随插件变化核对。[固定版本发布](https://github.com/vernesong/OpenClash/releases/tag/v0.48.002)
- Ninja：核心发布 `ab32ad2d`，发布说明称同步上游 `5019cc09`，本轮 gh 解析其完整上游 SHA 为 `5019cc090ed7cafb76643f964a76b1e97aee2985`。已重新读取该 SHA 的 DNS 配置结构、逻辑规则和 SOCKS 实现；此映射来自发布方说明，不是私有二进制与公版代码逐行等价证明。[Ninja 固定发布](https://github.com/kachetong1314/mihomo-ninja/releases/tag/ab32ad2d)、[对应公版 DNS 配置实现](https://github.com/MetaCubeX/mihomo/blob/5019cc090ed7cafb76643f964a76b1e97aee2985/config/config.go)
- Connector：1.1.0-r4 APK，对应 Ninja 仓库发布 0.1.13。helper 行为来自本轮已下载包的 `ninjaconnector-subscription.sh`，并再次限定检索 download／lock／HTTP／atomic replace／restart 代码；没有访问保存的 URL。[Connector 固定发布](https://github.com/kachetong1314/ninja/releases/tag/0.1.13)
- 官方 OpenWrt 帮助页更新于 2026 年 8 月 27 日，确认 Connector 2 为原版 OpenClash 提供 Ninja 能力、下载订阅后仍需切换 OpenClash 并启动；本机不因帮助页写“最新”而升级已验证版本。[Ninja 官方 OpenWrt 帮助](https://world.crisp.help/zh/article/openwrt-ubh9oi/)
- DNS 当前官方说明用于核对术语：`default-nameserver` 解析 DNS 服务端域名，`proxy-server-nameserver` 解析节点域名；指定经代理 DNS 需要独立节点解析以打破依赖。当前文档还可能包含比固定二进制更新的功能，本文没有因此启用新字段。[Mihomo DNS](https://wiki.metacubex.one/config/dns/)

本地证据范围：`outputs/ax6000-mainline/使用说明.md`、`路由器调优与校园网方案调研.md`；`work/deploy/ninja/dns-lifecycle-audit.md`、`production-hook-notes.md`、`connector-subscription-hooks.md`、`pc-proxy-followup.md`、`failover-boundary.md`；`work/deploy/ninja-subscription-summary.json`、`ninja-rule-summary.json`、`connector-configured.json`、`followup-lan-udp-after-reboot.json`、`ninja/home-pac-runtime-acceptance.json`、`network-layers-current.json`、`network-layers-runtime-addendum.json`。早期 candidate、隔离审计和当前生产成功按各自时点区分，没有把候选建议当作已经安装的能力。
