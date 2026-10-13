# RB06 小 overlay 下的 DNS 与广告过滤取舍

核对时间：2026-10-12。使用 agent-reach 的 GitHub CLI 与网页通道；Exa 此次达到免费限额，改用网页搜索和官方正文。设备状态来自主代理本轮读回，本支线没有 SSH、没有读取私密配置、没有安装软件或下载完整大列表，只写本文件。

## 结论与实施顺序

当前优先保留 `客户端 → dnsmasq:53（adblock-fast）→ OpenClash:7874 → 按域名选择上游`。比现状更有价值的改进，是补齐实际漏拦的少量域名、做好误拦回退，再在空间预算允许时把 HaGeZi Light 单独换成 Normal。增加 AdGuard Home 或 mosdns，会引入本机尚未证明有收益的新解析路径；当前 overlay 剩余约 9.4 MiB，不适合同时部署它们。

可以按三个范围选择：

1. **现在可做，空间增加很小：** 保留 Light；针对用户实际访问中残留的广告，确认域名独立于正当内容后追加少量规则。浏览器内容广告、占位和同域广告交给兼容的浏览器过滤扩展。核对全链请求是否经过 dnsmasq，比安装新 DNS 程序更直接。
2. **需要更广的全网域名覆盖：** 先解决持久空间余量，再让 HaGeZi Normal 替换 Light；不要把二者并用。切换只改变列表，保持 DNS 上游、代理路径和缓存策略不变，便于判断收益和误拦。Normal 是候选升级，不能由域名数量推断广告减少比例。
3. **确实需要每设备日志、独立策略或 CNAME 响应检查：** 存储扩展完成后再评估 AdGuard Home，或放到已有且长期在线的另一台设备。让它替换一个过滤入口；不要为获得管理页再串起 AdGuard Home、mosdns、SmartDNS 三套流水线。

“overlay 充足”还要覆盖更新与恢复。剩余 9.4 MiB 能容纳一些规则文件，不等于可以放心增加核心程序、保留多份更新文件和连续写查询日志。约 219 MiB 的可用内存也不能补足持久存储。Ninja UPX 核心当前约 18.75 MB，后续核心更新峰值必须另计；本报告不把一个固定百分比当作通用安全线。

## 当前状态与已验证范围

主代理提供：RB06 原厂分区，overlay 约 61.6 MiB，已用约 49 MiB，剩余约 9.4 MiB；可用内存约 219 MiB。SmartDNS 46.1 已安装且禁用。adblock-fast 1.2.4-r4 当前为固定版本 HaGeZi Light，55,349 个域名，源文件约 1.1 MiB、持久缓存约 411 KiB。国内 DNS 为 `223.5.5.5` / `119.29.29.29`；境外 DoH 经 Ninja；校园 DNS `10.50.11.15` 等保留限定策略。

上轮 SmartDNS 的 DNS 与 HTTPS 短窗 A/B 没有一致收益，因此保持禁用有依据。该样本不能证明 SmartDNS 对所有时间、地点或域名都无用，也不能把本轮升级名单当作已经验收的改进。本报告没有对 Normal、OISD、AdGuard Home 或 mosdns 做设备运行测试。

## 规则列表：优先单一主列表

下表是本轮公开元数据快照；与设备已安装的 55,349 条旧快照区分。MiB 按 1,048,576 字节计算。源文件大小不等于 dnsmasq 内存，也不等于生成缓存或闪存实际分配。

| 候选 | 本轮域名数 | 获取的源格式与文件字节 | 相比现状的实际取舍 |
| --- | ---: | ---: | --- |
| HaGeZi Light | 55,914 | `wildcard/light-onlydomains.txt`，1,170,118 字节，约 1.12 MiB | 当前低开销基线，适合优先保证正常访问；更新同级列表是维护，不算强度升级。 |
| HaGeZi Normal | 157,755 | `wildcard/multi-onlydomains.txt`，3,140,302 字节，约 3.00 MiB | 范围更广；原始源比当前固定 Light 多约 1.89 MiB，另有未知的生成缓存增量及 RAM 增量。适合作为单一替换候选。 |
| OISD small | 56,309 | 官方 ABP 格式，1,265,139 字节，约 1.21 MiB；只读前 2 KiB | 主要面向广告，体积与 Light 接近，可作另一个主列表候选；不是已证实更强。 |
| OISD big | 237,389 | 官方 ABP 格式，5,451,307 字节，约 5.20 MiB；只读前 2 KiB | 增加恶意域名等范围，源体积明显更大，当前 9.4 MiB 余量不适合再叠加。 |

HaGeZi 上游将前五个 Multi 等级设计为包含关系，应只选一个；Light 是 Normal 的精简版本。上游把 Normal 定位为更全面、低误拦风险的方案，但这仍是维护者定位，不是本机使用验收。两者均未覆盖从 Pro 开始的部分错误报告服务。今天元数据固定到提交 `ca2fc960e6d8bb279937fe8258dc591f17676bde`，本轮仅获取 README 和 GitHub 文件大小，没有下载完整 Normal。[HaGeZi README](https://github.com/hagezi/dns-blocklists/blob/ca2fc960e6d8bb279937fe8258dc591f17676bde/README.md)、[Light 源](https://github.com/hagezi/dns-blocklists/blob/ca2fc960e6d8bb279937fe8258dc591f17676bde/wildcard/light-onlydomains.txt)、[Normal 源](https://github.com/hagezi/dns-blocklists/blob/ca2fc960e6d8bb279937fe8258dc591f17676bde/wildcard/multi-onlydomains.txt)。

OISD small / big 快照版本 `202610121005`。OISD 以保持网站功能为取舍方向，并非“不会误拦”的保证；FAQ 明列视频网站、奖励视频和部分服务的例外需求。small 主要广告，big 包含更多安全与跟踪域名；big 包含 small。OISD 已停止传统 hosts / 无通配域名格式，直接使用兼容 ABP 或 dnsmasq 格式，不能把整份 ABP 原样交给只接受纯域名的解析器。[OISD 下载说明](https://oisd.nl/downloads)、[OISD FAQ](https://oisd.nl/faq)、[small 实际端点](https://small.oisd.nl/)、[big 实际端点](https://big.oisd.nl/)。

**建议：Normal 和 OISD small 二选一作为后续替换试验；本轮优先 Normal 的原因是沿用已有 HaGeZi 体系，切换变量少。** 不建议 Light + Normal、small + big，也不建议从多个大聚合列表的并集开始。新列表更多，可能只增加已重合域名和误拦，不能自动提高对同域内容广告的能力。

## 程序：新增功能与新增成本

| 方案 | 新增能力 | 公开体积或依赖证据 | 当前建议 |
| --- | --- | --- | --- |
| 保留 dnsmasq + OpenClash + adblock-fast | 已有 DHCP、本地域名、域名阻断和代理 DNS 分流 | 不新增 DNS 核心；按单一列表增长预算 | 首选，先修请求覆盖与少量规则。 |
| SmartDNS 46.1 | 多上游应答、按延迟选地址、限定域名规则 | 已安装；之前官方 APK 逻辑安装大小 396,556 字节，不含新增依赖 | 保持禁用；具体域名出现可重复 CDN 问题后再限定试验。 |
| AdGuard Home 0.107.79-r1 | 查询日志、客户端策略、丰富过滤语法、CNAME 响应检查及可视化管理 | 官方 ARM64 APK 11,395,810 字节，元数据 `installed_size=34,130,157`（32.55 MiB），依赖 `ca-bundle`、`libc` | 当前 overlay 放不下有余量的部署；先扩展存储或另机运行。 |
| mosdns v5.3.4 | 可编排的解析流水线、应答检查、缓存与备用路径 | 上游 ARM64 ZIP 6,591,859 字节；sbwml 25.12 ARM64 组合包压缩 9,693,443 字节；这两者都不是安装大小 | 没有明确未满足需求时不加。精简核心可不使用 geodata，但须单独核实实际安装预算。 |

AdGuard Home 体积来自 OpenWrt 当前官方 snapshot `aarch64_cortex-a53/packages/adguardhome-0.107.79-r1.apk`：本轮 HTTP Range 只读取 65,536 字节并解析 APK 头部元数据，未下载或执行核心。逻辑安装大小尚未包含过滤源、查询日志、统计与升级峰值。[官方 APK](https://downloads.openwrt.org/snapshots/packages/aarch64_cortex-a53/packages/adguardhome-0.107.79-r1.apk)、[OpenWrt Makefile](https://github.com/openwrt/packages/blob/master/net/adguardhome/Makefile)、[上游 v0.107.79](https://github.com/AdguardTeam/AdGuardHome/releases/tag/v0.107.79)。

AdGuard Home 的收益主要是管理和过滤语义，而不是承诺 DNS 更快。官方配置允许每客户端策略、过滤列表、查询日志和统计目录；即使扩展后采用，也应限制日志并单独核对增长。把它放在 dnsmasq 后面，会让其看到的请求来源主要是路由器，不能再宣称完整保留每设备识别。若确需设备策略，应重新设计入口及本地 DNS / PTR 条件转发。[当前 AdGuard Home 配置文档](https://adguard-dns.io/kb/adguard-home/configuration/)、[DNS 过滤语法](https://adguard-dns.io/kb/general/dns-filtering-syntax/)。

mosdns 本身不是必须配一个巨大地理库的程序；可以用少量明确域名和地址条件。常见 sbwml LuCI 方案则直接依赖 `v2ray-geoip`、`v2ray-geosite`、`geo2txt`。上游 Loyalsoldier 当日完整 `geoip.dat` 16,583,067 字节、`geosite.dat` 11,125,082 字节只是完整库的体积示例，**不等同该 LuCI 最终安装体积**；社区默认 `geoip-only-cn-private` 会不同。无论使用哪种库，都不应默认再存一份完整地理数据。现有 OC 已能域名分流，重建一条 mosdns 链不能由功能存在推断本机更快。[mosdns v5.3.4](https://github.com/IrineSistiana/mosdns/releases/tag/v5.3.4)、[sbwml v5.3.4-r14](https://github.com/sbwml/luci-app-mosdns/releases/tag/v5.3.4-r14)、[LuCI 依赖](https://github.com/sbwml/luci-app-mosdns/blob/master/luci-app-mosdns/Makefile)、[对应完整库发布](https://github.com/Loyalsoldier/v2ray-rules-dat/releases/tag/202610112207)。

mosdns 的 lazy cache 可以提高命中率，但上游明确指出可能影响 DNS 频繁更新的 DDNS 和 CDN；其缓存 dump 是额外磁盘行为。当前不采用全局长最小 TTL、长过期缓存或默认落盘缓存来制造“解析快”的结果。[mosdns v5 插件说明](https://irine-sistiana.gitbook.io/mosdns-wiki/mosdns-v5/ru-he-pei-zhi-mosdns/ke-zhi-xing-cha-jian)。

SmartDNS 的 IP 探测使用 ping / TCP 建连，不能代表 TLS、首字节或下载速度；代理域名的探测出口与访问出口也可能不同。官方建议对转发域名考虑关闭探测。当前 A/B 没有一致应用层收益，保持现 DNS 路径比全局开启优选更有依据。[SmartDNS 测速说明](https://pymumu.github.io/smartdns/config/check-speed-mode/)。

## 怎样改善广告过滤而不扩大误拦

采用小范围验收：固定当前列表快照，记录正常网站和实际残留广告；新增规则前确认广告域名与登录、支付、视频、校内认证等正当内容独立。名单更新后先验证最常用功能，不用在线广告测试分数替代真实使用。

当广告请求仍能通过，先分清三种情况：

- **普通客户端 DNS 没经过 53：** 客户端自带 DoH、缓存或应用内解析可能绕过 dnsmasq；只加新 DNS 程序不会解决路径问题。用真实查询与连接证据确认，不盲目阻断所有加密 DNS 服务。
- **DNS 阻断入口未覆盖核心内部解析：** OpenClash 的节点解析、核心内部查询不必经过前置 dnsmasq。对于已确认漏拦且内核能看到域名的连接，可考虑少量高优先级 `DOMAIN` / `DOMAIN-SUFFIX` `REJECT` 规则；先保留校园认证和必要 Ninja 服务的豁免。私有 Ninja 内核须通过配置测试和实际命中确认，不凭 Mihomo 文档直接断言兼容。
- **广告与正常内容共享域名，或需要隐藏页面元素：** 更大 DNS 名单会同时阻断正常内容。浏览器内容过滤具备 URL 和页面规则，能补上这类缺口，且不增加路由 overlay；MV3 浏览器可评估官方 uBO Lite，其他浏览器按当前支持情况选择。[uBO Lite 官方说明](https://github.com/uBlockOrigin/uBOL-home)。

OISD 与 AdGuard Home 官方都说明，DNS 阻断不能可靠处理 YouTube 等同域广告和页面占位。换成 AdGuard Home 并不会自动突破这个层级限制。[AdGuard Home 已知限制](https://github.com/AdguardTeam/AdGuardHome#comparison-limitations)。

白名单需要最小范围：为已确认的登录、付款、校园认证、节点 / API / 订阅域名设例外，避免整个平台顶级域名全部放行。规则启停与例外修改后注意客户端、dnsmasq、OC 的负缓存；使用正常 TTL，并通过实际重新查询判断变化，不把缓存未过期误判为规则仍错误。

## DNS 链保持单向

当前建议链是：

```text
客户端 53
  → dnsmasq：本地名称 / DHCP / 单一广告列表
  → OpenClash 7874
       ├─ 校园限定域名 → 校园 DNS，经认证直连路径
       ├─ 国内直连域名 → 当前国内 DNS
       └─ 境外域名 → 当前指定 DoH，经 Ninja
```

不能把 OC 的默认上游、DIRECT 上游或节点 bootstrap 改回 `127.0.0.1:53`，也不能让 SmartDNS / mosdns 的默认上游递归回 53 / 7874；否则会形成 `53→7874→53`，或 `7874→新组件→7874`。校园认证与节点 bootstrap 应能在代理尚未启动时完成必要解析。

Mihomo 文档把 `proxy-server-nameserver`、`default-nameserver` 与 DIRECT 上游区分；`direct-nameserver-follow-policy` 默认 false。要新增限定策略，必须核验当前内核中的实际行为，不能以客户端查询返回符合预期就认定核心 DIRECT 解析也一致。[Mihomo DNS 文档](https://wiki.metacubex.one/config/dns/)。

已有 adblock-fast `force_dns=0`、单一 dnsmasq 后端保持不变。后续若选择 AGH 做主入口，应该替换前置过滤位置并移除重复过滤后端；若 DNS redirect 直接把客户端 53 送到 OC，就绕过了当前 dnsmasq 广告阻断，必须重新验收。AAAA / HTTPS type65 不因安装新程序而一律屏蔽，ECS、DoH HTTP/3 和 serve-expired 也按明确需求单独决定。

## overlay 的具体边界

- 只保留一个当前主列表、一个恢复所需的持久缓存；工作目录、下载归档、旧列表和规则转换临时文件由主代理核对归属后清理，不能在本报告中直接删设备文件。
- 当前 `file://` 源文件是长期启动或重新生成所需输入，不能为省 1.1 MiB 就删除它。若改为只留压缩持久缓存，必须先证明断网重启、损坏恢复和后续更新仍完整成立；缓存存在不等于源已不需要。
- Normal 候选源约 3.00 MiB，只是比旧 Light 源多约 1.89 MiB；它的缓存大小没有测量。本轮不按列表行数线性外推 RAM，也不把 411 KiB 旧缓存直接作为 Normal 预算。
- 下载和校验先在 RAM 工作目录完成，只在校验通过后替换已知持久源；保留恢复值在电脑交付材料中。RAM 临时文件仍计入可用内存，临时源放 RAM 也不能取代断电后的持久恢复。
- 不新增落盘 DNS 查询日志、默认完整 geodata 或多个列表镜像。SmartDNS 已禁用的核心逻辑体积约 0.38 MiB，卸掉它只能获得有限空间，不能解决 32.55 MiB AdGuard Home 的需求；现有共享依赖不可连带删除。

## 博客阅读的作用与限制

[MAENE《使用 OpenWRT 搭建内网 DNS 服务器》](https://www.cnblogs.com/MAENESA/p/19045621)（2025-08-18）给出 AGH→mosdns→SmartDNS / 代理 DNS 的复杂拓扑，目标包括每客户端规则、日志和细分路由。它能说明为什么有人需要多层，但不能证明本 RB06 更快或更省空间。文中给出的 TTL、type65、日志、IPv6 和缓存选择与版本相关，不直接复制；其建议关闭 AGH 广告过滤也不能当作普遍结论。

主代理若开展实际试验，建议一次只改一个变量：先对 Normal 或 OISD small 做名单替换，再观察正常访问、误拦、实际广告请求、服务 RSS 与 overlay 增量。只要原访问恢复机制不完整，或效果仅是域名数更多，就不把试验转为长期方案。
