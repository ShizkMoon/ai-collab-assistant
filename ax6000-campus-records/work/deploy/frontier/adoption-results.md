# AX6000 当前采用结果与维护边界

当前已在现有 Ninja 核心中采用国内站点白名单 DoH：只新增 9 个后缀的解析策略，不改全局 DNS、校园条件解析、国外 fallback 或代理节点 bootstrap。候选与生产常用业务已完成对应验证；新增校园域名样本仍为 SERVFAIL，原策略隔离对照同样复现，不能将校园 DNS 写为通过。第三条不同账号的手机通道已完成认证、三次自然心跳和多轮独立出口访问，原两路 PID 保持；MWAN 三个成员均 online，三路分配规则已读回，并观测到属于当前 UA3F 的第三路实际外连。CAKE 的有界 A1 基线已完成，但结果为 inconclusive，本轮没有安装 CAKE。

最终验收的 `accepted_changed_scope=true`，本地健康状态为 `HEALTHY`；由于既有校园样本仍失败，完整验收保持 `passed=false`。这三个状态分别对应本轮改动范围、本地健康与完整验收，不能相互替代。[最终验收](final-acceptance.json)。

本次继续保留固定 Ninja 核心、香港 02、UA3F、现有 Wi-Fi 与原两条认证通道，在其上新增第三账号。用户要求尽量不整机重启或长时间断网，允许必要的短暂切换；当前材料不包含刷机、bootloader 迁移或整机重启动作。

## 12 项注释的当前对应结论

编号严格对应用户的 12 项注释；独立文档不嵌入应用 annotation directive，主代理最终回复再逐项对应。

| 编号 | 用户选择 | 当前采用结果与条件 |
| --- | --- | --- |
| 1 | 国内 DoH 可以仅国内 | 已采用 9 个明确后缀的白名单 policy。其余 DNS 字段保持原值；不是全国内／全网加密。隔离验证 9／9 与生产常用业务已通过，校园新增样本仍失败且原策略复现。 |
| 2 | Uptime Kuma 不必要 | 不安装、不新增电脑侧监控服务。现有本地健康守护继续按已部署范围使用。 |
| 3 | Tailscale 没有需求 | 不安装、不新增远程组网；本轮不扩展远程管理需求。 |
| 4 | luci-app-statistics／collectd 不需要 | 不安装、不新增 RRD 历史或闪存写入。现有按需观测已足以支持本轮评估。 |
| 5 | CAKE／SQM 需要评估 | 三路政策 online 时已完成有界 A1：768 MiB、16 流、11.078 秒，载荷约 581.55 Mbps。稳态仅 9.078 秒，16 条下载内层连接标记为 6／5／5，但未记录对应固定源的外层 ESTABLISHED，完整三路同源排队条件不足，整体为 inconclusive。本轮不安装 CAKE，保留原队列；该基线与旧 HTB＋fq_codel 都不算 CAKE 收益。 |
| 6 | L4S／DualPI2 有用可采用 | 固定内核／iproute2 源码与匹配 ABI 包可行，但真实端点、ECT(1)／CE／反馈和 Prague 条件未满足。现在不安装裸 DualPI2，不将普通 ECN 或 CUBIC 的 AQM 改善称为 L4S 收益。 |
| 7 | DoH3／DoQ 有用可采用 | 已做固定核心、独立缓存和空 fallback 的 8 次有界查询。DoH3 DIRECT 的 2 次 DNS 回答有效，但实际 H3 未确认；固定 HK02 的 DoH3 与两路径 DoQ 均为 SERVFAIL。追加固定 IP 观测仅见 UDP 443 尝试，无 TCP 回退，2 次 DNS 仍失败。本轮未采用，不替换生产 fallback，不把 UDP 发包或 DIRECT 应答当固定香港路径通过。 |
| 8 | HTTP/3＋ECH 有用可采用 | 新 Edge 测试标签页的指定 Cloudflare 连接实际为 HTTP/2／h2、TLS 1.3，服务端报告 `server_sni=encrypted`，因此该连接 ECH 已证实，HTTP/3 未使用。未改浏览器设置，不外推所有站点、所有连接或 DNS 来源。 |
| 9 | MPTCP／OpenMPTCProuter 有用可采用 | 机制评估完成；应用与远端协商、不同出口 MP_JOIN 子流和相应瓶颈均未证明，本轮不改核心／进程环境，不采购 VPS，不引入 OMR。内核开关和普通多连接分流不当作 MPTCP 已使用。 |
| 10 | BBR／BBRv3／AccECN 有用可采用 | 机制评估完成；当前仅 reno／cubic 可选，保留 cubic 与 `tcp_ecn=2`。缺少业务端条件、实际协商／反馈和相关瓶颈证据，本轮不换内核、不切核心、不改全局 ECN；Linux 版本号不代表已有 BBRv3。 |
| 11 | 只支持 Ninja、固定香港 02、不切换 | 已按原约束保持固定核心、现有 Ninja 协议和香港 02 单成员选择；DNS、第三账号及前沿评估不以改协议或换节点为前提。 |
| 12 | ImageBuilder 理论上好，可以考虑 | 已完成本地维护准备与包／补丁分层；本轮不下载、不构建、不刷机。保持 stock，固定构建与 ABI，先做无凭据 manifest；ASU 不自动重建本地补丁，回滚尚未验证。 |

第 5 项已在三路状态下完成有界 baseline；未满足安装前的同路径排队证据条件，本轮停在 A1，不进入 CAKE 的 B／A2。第 7 项已完成短时查询与单个公开端点的小范围传输观测，没有成功 H3 握手或协议性能收益结论。其他未采用项目不为补齐实验结果而改变当前生产架构。

## 国内 DoH：已采用的范围

新增后缀为 `baidu.com`、`bilibili.com`、`jd.com`、`qq.com`、`taobao.com`、`tmall.com`、`alipay.com`、`weibo.com`、`163.com`。这些后缀通过现有核心的 nameserver-policy 使用阿里 `https://dns.alidns.com/dns-query` 与 DNSPod `https://doh.pub/dns-query`。本轮只采用明确白名单，不把国内所有域名批量切换到加密上游。

持久定义位于 production options 的 `dns_nameserver_policy`，沿用 custom overwrite。源订阅不变；hook 连续应用两轮后结果一致；候选通过当前固定核心的语法／配置校验。订阅事务会用相同 hook 对新源生成 projected 候选，因此新增 policy 具备随订阅重新生成的路径。本轮没有扩改公共订阅 helper。

为排除普通上游和旧缓存替代，临时核心使用独立缓存，并将普通 nameserver 与 fallback 置为不可达；9 个白名单真实域名均取得 rcode 0 与有效 A／CNAME 答案，9／9 通过。此结果支持白名单 policy 在这次测试路径有效；它不是长期速度排名或完整网络抓包。

生产读回确认只增加 DNS policy，原源订阅、核心 SHA256、许可元数据、固定香港节点、两个认证 PID 和 UA3F PID 均保持。生产常用国内请求为 HTTP 200，国外请求为 HTTP 204；百度／哔哩哔哩／京东、Google、家庭 PAC 标识、广告 NXDOMAIN 和国外 HTTPS RR 查询均取得对应预期回答。国外 `crypto.cloudflare.com` 的 type 65 回答只能证明 HTTPS RR 在该查询中保留，不能代替浏览器 ECH 握手或 HTTP/3 业务验收。

global nameserver、default-nameserver 和 proxy-server-nameserver 仍保留 `223.5.5.5`／`119.29.29.29`，国外 fallback 与 fallback-filter 保持原值。DoH 保护路由器到解析器的白名单查询传输，LAN 普通 53、未列入白名单的国内解析和启动解析并未全部加密。本轮未证明 DoH 可提高下载速率。

校园新增样本 `www.gdpu.edu.cn` 在生产核心返回 SERVFAIL；原策略、隔离缓存的临时核心对同域也返回 SERVFAIL，对 `www.189.cn` 则返回有效答案。这个对照支持“该失败可以在原策略复现”，不能证明服务器长期故障、学校全域不可用，或取得了严格历史改动前同窗样本。当前验收文件整体 `passed=false`，不得改写为所有 DNS 通过。

证据：[候选和幂等验证](dns-candidate.json)、[隔离解析验证](dns-trial.json)、[生产应用](dns-applied.json)、[生产验收及校园失败](dns-acceptance.json)、[原校园策略对照](dns-campus-baseline.json)。

## DoH3／DoQ：本轮查询完成，未采用

固定 `ab32ad2d` 核心分别在独立回环临时实例中测试 DoH3／DoQ 的 DIRECT 与 HK02 路径，每个协议／路径查询两个公开域名，合计 8 次。临时配置通过 core test，新进程与独立缓存、单一 upstream、空 fallback 均已记录；生产 DNS 设置、认证／UA3F PID 和核心保持不变。

`https://cloudflare-dns.com/dns-query#h3=true` 的 DIRECT 轮次取得 2／2 有效 DNS 回答，但记录中没有对应 QUIC resolver 连接，`actual_protocol_confirmed=false`。因此只能说强制参数的临时配置取得答案，不能将该定制核心的实际 HTTP/3 传输写为通过。使用固定 HK02 组的 DoH3 两次均为 SERVFAIL；`quic://unfiltered.adguard-dns.com:853` 的 DIRECT 与 HK02 轮次均为 SERVFAIL。失败原因与端点普遍可用性尚未定位，不能推断所有 DoQ 或所有 QUIC 均不可用。

后续将 upstream 固定为 `https://1.1.1.1/dns-query#h3=true`，用新缓存查询另外两个公开域名，并仅观测这个公开端点的 443 端口。结果记录 30 行 UDP 443 发包、0 行 TCP 443，两个 DNS 回答仍为 SERVFAIL。这支持本轮向该端点尝试了 UDP 传输，且观测中没有 TCP 回退；没有成功响应或 H3 握手，不能称为 DoH3 已可用。固定 IP 轮次与前轮 `cloudflare-dns.com` 的两个有效回答也不是同一个 endpoint，不能用本轮 UDP 发包证明前轮的实际协议。[公开端点传输观测](doh3-wire-result.json)。

上述结果不足以替换现有生产 DoH，且没有同路径重复性能对照。本轮保持国内白名单的普通 DoH 和原国外 fallback，不改 Ninja 协议、节点或浏览器配置。[临时协议查询结果](encrypted-transport-results.json)、[精确方案与证明条件](encrypted-transport-plan.md)。

## HTTP/3／ECH 与传输机制：按实际路径收束

主代理在新的 Edge 测试标签页访问 `https://crypto.cloudflare.com/cdn-cgi/trace`，没有修改浏览器全局 flags、Secure DNS、PAC、代理、扩展或注册表。服务端 trace 为 `http/2`、TLS 1.3、`server_sni=encrypted`，导航协议为 `h2`，服务端报告所在地 HK。该指定连接的 ECH 有实际服务端证据，HTTP/3 没有使用；这不证明其他网站同样支持 ECH，也不证明浏览器全部 DNS 经过路由器。HTTPS type 65 保留是必要链路条件之一，不能代替这个实际服务端报告。[浏览器脱敏结果](browser-encrypted-transport.txt)。

MPTCP、OpenMPTCProuter、BBR／BBRv3、AccECN、L4S／DualPI2 的机制与当前入口已经完成只读核查。本轮没有现存瓶颈与这些机制相关的证据，也未证明当前 Ninja／UA3F 真实 socket、远端和反馈具备对应业务条件。因此保留当前核心、固定香港节点、CUBIC、`tcp_ecn=2` 与现有普通分流；不通过全局 ECN、环境变量、换内核、购 VPS 或切换代理协议制造前沿能力。

`net.mptcp.enabled=1` 只允许应用创建 MPTCP socket；两／三路普通连接分别选路不等于 MPTCP 多子流。BBR 影响本机 TCP 发送端，不能改变纯转发 PC 或远端下载发送者的算法。AccECN 提高拥塞反馈精度，不自动创建 AQM 或 L4S；DualPI2 可用模块也不代表已有 Prague 端点与正确 ECT(1) 分类。本轮这些项目的结论是“机制与实现条件明确，未采用”，不是性能已经通过。[传输机制核查](transport-feasibility.md)、[队列与 L4S 条件](queue-evaluation-plan.md)。

## CAKE：有界基线完成，未安装

三路 MWAN online 后，在不改队列的 A1 轮次完成 16 条流、合计 768 MiB 的公开 Range 下载，每条流均完成其预定范围。载荷窗口为 11.078 秒，有效载荷约 581.55 Mbps，剔除边界后的稳态为 9.078 秒。这是本次指定源、路径和短时负载的实测，不能当作校园总带宽、三条独立限速之和、日常稳定速率或与原双通道的收益对照。

整体判定为 `inconclusive`：稳态不足两个完整 5 秒窗口；原匹配器用 PC 端口寻找下载连接，而 UA3F 的实际外层连接不能直接沿用这组端口，因而未完成严格的三路同源覆盖和对应延迟证明。后续仅离线分析已有记录，确认 16 条下载客户端的透明代理内层 ESTABLISHED 连接带有三组标记，分布为主路 6 条、第二路 5 条、第三路 5 条；同一固定下载源没有外层 ESTABLISHED 记录，已有外层 TIME_WAIT 计数很小且出现于负载前。这个材料支持内层 mark 分配，不证明三路实际承载本轮 768 MiB 下载；观测缺口也不能反向证明第三路没有流量。[已有大样本的离线连接分析](three-download-flow-evidence.json)。

短时 TTFB 同时包含新连接、代理与源站响应，不能只凭负载时升高就归因于本机队列，也不能从这个短窗推出长期不存在排队。后续 3 MiB 小样本用于核对当前 UA3F 第三实际外连，没有改变队列，也不补成缺少的 CAKE 同路径持续负载证据。

本轮按预定条件停在 A1，没有安装 CAKE、创建临时聚合队列或进入 B／A2，继续使用原队列。旧 HTB＋fq_codel 的性能成本仍是其独立历史结果，不替代这次 CAKE 判断。[有界 A1 原始结果及汇总](queue-baseline-a1-final3.json)、[预定范围与判定条件](queue-evaluation-plan.md)。

## 第三个不同账号：当前接入边界

本轮用户要求在现有两条通道上，增加另一个账号的手机第三通道。它与此前同一账号的 Linux／macOS／iOS／Windows 第三候选不是同一个试验，不能继承旧失败为必然失败，也不能把预检查或接口创建当认证成功。

接入沿用现有 netifd 出口隔离、动态 DHCP、独立源地址／策略路由／mark 和生命周期，保留原两路工作。初始认证、对应同一 PID 的三次自然心跳及多轮绑定源地址的独立外网请求已经通过；MWAN 三个成员均已 online。这个结果支持在原双通道上增加独立账号手机第三通道，并保持当前短时接入。多通道同时在线仍不能自动证明单连接相加、第三份独立带宽、所有业务均经过三路或长期稳定。接入期间没有整机重启或 Wi-Fi 重建。

主代理现场记录已确认：第三账号手机在 21:19:36 完成 AUTH，21:19:44 取得首个真实心跳，服务端给出的间隔为 850 秒；同一 PID 在 21:33:55、21:48:05 取得第二、第三次自然心跳。未缩短服务端间隔，也未通过重认证制造后续成功。三条源地址绑定出口多轮取得 HTTP 204；原账号 1／2 的 PID 7620／7679 保持，第三 PID 为 9375。这支持第三账号独立认证、两个完整自然心跳间隔和短时三路外网可达。[第三路与原两路观测](three-observation.json)、[包含第三次自然心跳的最终验收](final-acceptance.json)。

21:36 的 MWAN 读回为三条接口 online，`balanced` 与 `ua3f_bal` 各含 33% 的三个成员；UA3F 使用 `inc mod 3`，普通 balanced 使用 `random mod 3`。随后只将 `wan3.auto` 设为 1，没有整机重启或 network restart，冷启动持久化未测试。[MWAN 在线与政策读回](three-mwan-online.json)、[第三路启动配置持久化](three-persistence.json)。

为核对进程归属，追加的短样本只有 3 个请求、合计 3 MiB，每请求限速 128 KiB／秒；三个 HTTP 206 均完成预定的 1 MiB 范围。通过当前 UA3F PID 4940 的 socket inode 与 conntrack TCP 元组，现场匹配出 4 条已有或当时的外层 ESTABLISHED：主路 3 条、第三路 1 条。第三条实际外连带 `0x03000000` mark，reply destination 为第三出口地址，记录的反向 conntrack 计数为 444085 字节。这些是内核连接计数，不能直接当某条 curl 的应用载荷。

这个证据支持属于当前 UA3F 的第三路实际外连存在。样本未将每条 curl 逐一对应到透明代理外层连接，也未同时观测到第二出口，因此 `all_three_exits_observed=false`；三个请求完成不等于三个出口分别完成下载。当前可以写第三通道已认证、保活、三路政策已接入且当前 UA3F 有第三实际外连，不能写三路共同承载完整 768 MiB 下载、三路同时业务覆盖、长期稳定或吞吐收益。[小样本与 UA3F 外连归属](three-small-flow-acceptance.json)。本文不保存账号、口令、会话、订阅、节点身份或私有 URL。

## ImageBuilder：只做维护准备

现有系统为 RB06 stock、OpenWrt SNAPSHOT `r37185-f29dfe25ba`、Linux `6.18.55`；公开下载站本次已是 `r37224-0ad1348fb2`。公开最新构建与设备旧构建不能混为相同环境。目标始终是 `mediatek/filogic`、`aarch64_cortex-a53`、`xiaomi_redmi-router-ax6000-stock`；已有 OpenWrt 后续升级镜像对应 stock 的 `squashfs-sysupgrade.bin`。

ImageBuilder 可以把确定的软件包和本地文件压入 SquashFS，减少后装软件对 overlay 的占用，但不创造新闪存。rootfs_size 参数不能视为扩大 stock MTD 边界；ubootmod 是另一套分区和启动布局，本轮不迁移。镜像尺寸、固定核心能否容纳、刷后实际空间和运行行为都要真实构建及单独验收，不能预先保证释放多少 MiB。

安全 world 中存在第三方 APK checksum 选择、旧 kernel／base-files／libc 版本 pin，以及 dnsmasq／dnsmasq-full 的交叠选择，不能原样拼成新构建的包清单。准备材料已经按 profile 默认集合、上游功能、Ruby／Lua 运行依赖、第三方客户端和可选 CAKE 分层。全部 kmod 需要选定目标构建与 ABI 配套，不能以版本前缀相同就混装滚动 feed。

ASU 可以按包选择组装镜像，当前接口也支持显式额外仓库和首次启动脚本，但不会自动提取设备任意修改文件。固定 UPX Ninja 核心、更新拒绝入口、许可恢复、订阅事务及 LuCI controller、MWAN3 本地补丁、认证 netifd／hotplug、UA3F、adblock 和本地健康守护都要有单独的本地维护配方与恢复契约。私有配置不提交给公共 ASU。已有备份与隔离展开尚未证明权限／属主／业务恢复，不能称为整机回滚已验证。

本轮不下载 ImageBuilder、不构建、不刷机，也不为容量收益安排整机重启。进一步准备只产出固定 revision／profile／包／SHA256／补丁／无凭据 FILES manifest。[详细维护准备](imagebuilder-readiness.md)保留完整清单与来源。

## 主文档原位更新入口

以下位置是此轮只读核对的原文位置；实际编辑前应按标题和段落内容重新定位，行号可能随主代理编辑变化。主说明、研究和 JSON 仍由主代理单独维护。

| 文档位置 | 应替换的旧结论 |
| --- | --- |
| 使用说明“当前配置”的 DNS 行，当前第 33 行 | 全国内解析仍为明文的概括，应细分 9 个白名单后缀 DoH、其余全局／bootstrap 明文及原国外 fallback。 |
| 使用说明第 64、155 行及调研“两路认证”末尾 | 旧同账号第三候选与本轮不同账号手机第三通道分开描述。本轮已完成认证、三次自然心跳、三源可达和 MWAN 规则接入；小样本支持当前 UA3F 的第三实际外连，但没有三出口同时业务覆盖或大下载外层证据。保留长期稳定、吞吐收益与冷启动未验收的边界。 |
| 使用说明第 157–161 行与调研“DNS、校园解析与广告过滤”第 217–232 行 | 替换“本轮未改生产 DNS／候选可供下一轮”的时态，加入白名单范围、隔离 9／9、生产业务和校园 SERVFAIL 对照；保留其余明文、bootstrap、国外策略与计时范围限制。 |
| 使用说明第 173 行，调研第 355、363 行 | “加密 DNS 生产切换未完成”改为白名单采用已完成、全网加密和更广应用仍未验证；校园失败不遗漏。 |
| 调研第 310 行、使用说明第 135 行 | 原 HTB＋fq_codel 试验不能称 CAKE 已部署。本轮有界 A1 为 inconclusive，未安装 CAKE；IFB 模块是否仍装按实际状态核对。 |
| 调研“存储方案”第 330 行 | stock 自定义固件可减少后装占用；增加包／本地补丁分层、旧 SNAPSHOT ABI 和 ASU 不自动重建补丁的边界，保留尚未构建／刷机／恢复。 |

用户排除的管理密码、访客网络、DHCP 固定租约、Kuma、Tailscale 和 collectd 按既定选择不再推荐；也不将换代理协议作为前沿优化前提。
