# 当前双出口的 DNS 目标与收益判断

核对时间：2026-10-12，Asia/Shanghai。使用 agent-reach 的 GitHub／gh API 路由与官方网页后备读取。范围为现有非私密 DNS 结果、生命周期审查、当前使用说明，以及 Mihomo、Ninja、阿里、腾讯、Cloudflare 的官方资料。本支线没有连接设备、测速、认证、读取订阅或修改生产配置。已读取主代理提供的 21:32:20 脱敏设备快照 `work/deploy/network-layers-current.json`；仅相应配置字段可以作为本时点设备事实，外部协议可达性仍待小范围探测。

## 建议结论

**保持 dnsmasq 53 → OC／Ninja 7874 的现有单向入口，先检查实际生效的上游、缓存、启动依赖和客户端绕过情况，再比较一项上游或传输方式。** 国内直连保留电信／国内公共 DNS 的选址；校园认证和校内域名单独走已验证的校园解析路径；代理域名的解析出口应与代理访问路径匹配。先用现有核心能力完成这些分工，无需为 DoH／DoT 另装 SmartDNS、AdGuard Home 或切换 fake-ip。

**DoH／DoT 可提高路由器到解析器这段传输的保密性和抗篡改能力，但不保证解析更快、CDN 更近、下载更快或校园会话更多。** 是否采用加密 DNS，应分别报告安全收益、可达性和实际访问代价，不能把一次 DNS RTT 变小写成全网提速。

## 现有证据和时间边界

- 21:32 快照确认：nameserver、default-nameserver 与 proxy-server-nameserver 均为明文 223.5.5.5＋119.29.29.29；国外 fallback 已使用 `https://1.1.1.1/dns-query` 并附指定策略。`respect-rules=false`，未设 direct-nameserver／follow-policy，核心为 Redir-Host／ipv6=false。因此当前已经有部分国外加密解析，但国内常规查询、上游和节点 bootstrap 未全加密。已有独立节点解析路径，当前没有 direct 分支覆盖 policy 的配置矛盾。
- `+.189.cn` 使用 202.96.128.86，`+.gdpu.edu.cn` 使用 10.50.11.15＋202.96.128.86；dnsmasq 唯一上游为 127.0.0.1#7874，noresolv=1、cache=0。SmartDNS 停用、HaGeZi 广告过滤和两认证分流由当前交付说明及主代理验证记录支持；本支线未独立调用设备。
- `work/deploy/dns-performance/actual-dns-findings.md` 的旧短窗中，校园 DNS 对四个公共域名的八次 A 查询全部约 2 秒超时；不能推导为校园认证域名或所有时段失效。公共电信上游与 SmartDNS 返回相同 IP 集合，未主动选址时没有已证实速度收益；主动选址增加约 10～20 ms 等待。计时只有约 10 ms 分辨率，不能使用其中 1.25 ms 等粗粒度平均值证明毫秒性能。
- 该短窗没有证明选中的 CDN IP 带来正常 HTTPS／首字节收益，因此不足以把 SmartDNS 恢复为全网生产上游。
- `work/deploy/ninja/dns-lifecycle-audit.md` 内“单 WAN／服务暂时关闭”是早期验收阶段，不是当前双认证状态；其 stock OpenClash DNS 所有权、正常 stop 回退、异常终止和 watchdog 重写等分析仍可作为代码边界。当前生产行为须由主代理读回。

## 几种优化分别改变什么

| 项目 | 可以改变的部分 | 不能据此保证的部分 |
| --- | --- | --- |
| UDP／TCP 53 改成 DoH／DoT | DNS 传输加密、证书验证、端口、握手和连接复用 | 答案更近、下载更快；路由器上游加密也不会把 LAN 的 53 自动变成加密 DNS |
| 换递归解析器 | 公共缓存命中、上游路线、部分域名的 CDN 回答 | 解析 RTT 最小的服务器返回的应用节点就最快 |
| 缓存 | 相同记录再次查询时减少上游请求和等待 | 第一次查询同样加速、过期记录永远正确、吞吐提高；热缓存不能与冷查询混比 |
| 主动挑 IP | 在当次 DNS 给出的地址集合中选一个响应快的地址 | 该地址下载带宽最大、两出口都适合、代理出口同样适合 |
| DNS 分流 | 校园、国内直连、代理和节点启动解析使用各自合适路径 | DNS 返回结果本身已证明后续连接按预期出口走 |
| fake-ip | 改变域名与连接识别方式、保留域名信息 | 是当前链路的速度升级；它会改变既有 DNS、规则和应用兼容边界 |

DNS 选址可能依据递归服务器出口，也可能使用 ECS 给出的客户端网段。[DNSPod 的线路识别说明](https://docs.dnspod.cn/dns/custom-line/)明确区分有 ECS 与无 ECS 的识别。阿里公共 DNS 与 DNSPod 产品页说明支持 ECS；Cloudflare 则明确不向生产权威查询发送 ECS，调试域名例外。因此，国内 CDN 与外国代理域名不能仅按同一张 DNS 延迟排行榜选上游。[阿里官方](https://www.alidns.com/)、[DNSPod 官方](https://www.dnspod.cn/products/publicdns)、[Cloudflare ECS 说明](https://developers.cloudflare.com/1.1.1.1/faq/#does-1111-send-edns-client-subnet-header)

这是选址原理和待测影响，不意味着 Cloudflare 对所有国内域名都慢。双 WAN 也不要写死某个学校私网 IP 或旧公网 IP 作为 ECS；当前两个出口是否被 CDN 归为同一地区／线路，需要实际答案与连接证据。默认无需额外手工注入 ECS。

## 官方端点与兼容边界

| 服务 | 普通解析 | 加密候选 | 当前适合的定位 |
| --- | --- | --- | --- |
| 阿里公共 DNS | 223.5.5.5／223.6.6.6 | https://dns.alidns.com/dns-query；DoT 主机 dns.alidns.com | 国内直连候选，先与同供应商 53 查询比较；官方入口支持 DoH／DoT与 ECS |
| 腾讯 Public DNS 免费版 | 119.29.29.29 | https://doh.pub/dns-query；DoT 主机 dot.pub | 国内直连候选；官方说明单域名 20 QPS、免费版无 SLA，不以服务宣传代替本校可达性 |
| Cloudflare | 1.1.1.1／1.0.0.1 | https://cloudflare-dns.com/dns-query；DoT 主机 one.one.one.one | 保留为既有代理解析候选；不未经本地对照就替代全部国内上游 |

端点依据：[阿里公共 DNS](https://www.alidns.com/)、[腾讯免费版设备接入](https://cloud.tencent.com/document/product/302/110786)、[Cloudflare DoT](https://developers.cloudflare.com/1.1.1.1/encryption/dns-over-tls/)、[Cloudflare DoH](https://developers.cloudflare.com/1.1.1.1/encryption/dns-over-https/)。DoT 使用 TLS／853，DoH 使用 HTTPS／443。[加密传输说明](https://developers.cloudflare.com/1.1.1.1/encryption/)

阿里帮助中心另有面向账户的 HTTPDNS、专属接入地址和计费说明，不把它们当作家庭公共 DNS 必需的注册／付费步骤。本文没有接入付费服务。

Mihomo 文档固定提交为 `c47fd7212afc3f0e6afe9c7cb18591ba55e5e79b`，2026-10-03。Ninja 官方 README 固定提交为 `1f076ddcd3de0dc00f52931cb9052e21e6abc3a6`，声明与 Mihomo 兼容；当前本机交付记录为 Ninja `ab32ad2d`。这个声明不能代替该固定二进制对具体 DNS 字段、DoT／DoH 连接和证书验证的运行验收。[Ninja README](https://github.com/kachetong1314/mihomo-ninja/blob/1f076ddcd3de0dc00f52931cb9052e21e6abc3a6/README.md)

## 目标路径与启动依赖

```text
家庭客户端 53
  → dnsmasq：DHCP、本地域名／家庭 PAC 标识、广告过滤
  → OC／Ninja 7874：主 DNS 缓存与解析策略
     ├ 校园／认证域名 → 已验证校园上游，控制流量保持认证豁免
     ├ 国内 DIRECT 域名 → 电信／已验证阿里或腾讯上游，国内出口
     └ 代理域名 → 已验证加密上游，指定代理解析路径

独立启动解析：DNS 上游域名 + 代理节点域名
  → 不依赖上述代理已建立，也不回送 dnsmasq 53 或 OC 7874
```

Mihomo 的 `default-nameserver` 专门解析 DNS 上游的域名，要求 IP 形式，可使用加密解析。`proxy-server-nameserver` 专门解析代理节点域名；打开 `respect-rules` 或指定上游经代理查询时，必须把节点解析独立配置，避免先解析节点才能建代理、先建代理才能解析节点的相互依赖。[固定 DNS 文档第 131～159 行](https://github.com/MetaCubeX/Meta-Docs/blob/c47fd7212afc3f0e6afe9c7cb18591ba55e5e79b/docs/config/dns/index.md#L131-L159)、[指定代理／接口第 235～241 行](https://github.com/MetaCubeX/Meta-Docs/blob/c47fd7212afc3f0e6afe9c7cb18591ba55e5e79b/docs/config/dns/index.md#L235-L241)

如果配置 `direct-nameserver`，它会为 DIRECT 出口重新解析；`direct-nameserver-follow-policy` 默认 false，可能绕开前面指定的校园／国内域名策略。当前目标是单一、可解释的直连解析来源：优先不额外建立一个相互竞争的 direct 分支；确需保留时必须核对 follow-policy 和目标核心行为，不能只检查 nameserver-policy。[固定文档第 161～167 行](https://github.com/MetaCubeX/Meta-Docs/blob/c47fd7212afc3f0e6afe9c7cb18591ba55e5e79b/docs/config/dns/index.md#L161-L167)、[解析流程](https://github.com/MetaCubeX/Meta-Docs/blob/c47fd7212afc3f0e6afe9c7cb18591ba55e5e79b/docs/config/dns/diagram.md)

缓存主要由核心承担；OpenClash forwarding 模式会把 dnsmasq 缓存设为 0，不另叠大缓存、预取、长期过期答案或随意抬高 TTL。保持广告 NXDOMAIN、本地家庭标识与 allowlist 的正确性。加密 DNS 需正常证书验证与可用时钟，不采用 skip-cert-verify 解决握手失败；首轮不同时开启 prefer-h3／QUIC 或修改 IPv6／AAAA 策略。

OpenClash 正常 stop 会恢复 dnsmasq；强制杀核心、异常中断或启动先后不保证立即恢复，watchdog 又会重写 dnsmasq 上游。因此不在运行中手工给 dnsmasq 追加一个公共 fallback 就宣称具备容错；应由现有生命周期负责有序回退，并以 LAN 新 DNS＋HTTPS 验收。源订阅可能仍有 direct／proxy-policy／其它 policy 字段，主代理应私密展开所有 resolver，仅公开回指数量、字段名与结论。

## 客户端绕过入口

普通 53 重定向不自动接管浏览器自带 DoH、Android 私人 DNS／853、VPN 或应用的 HTTPDNS。它们可能跳过 dnsmasq 的广告过滤，也可能用与实际连接不一致的地区答案。需要分别读取用户正在使用的客户端设置和查询实际路径，不能根据路由器 DNS 正常就声称所有应用已受统一过滤。[腾讯设备 DoT 接入](https://cloud.tencent.com/document/product/302/110786)、[Cloudflare 浏览器 DoH](https://developers.cloudflare.com/1.1.1.1/encryption/dns-over-https/)

家庭 PAC 用系统解析家庭专用域名。Windows 系统 DNS 或 VPN 若改成只访问外部解析器，可能影响该标识；浏览器自带 DoH 与 PAC 求值是否共用解析器需要按具体应用核实，不能一概写成它必然破坏 PAC。不默认全网封 853、封已知 DoH IP 或做 TLS MITM，也不为家庭统一入口删除外出配置。

## 最小有界对照

先保持两认证 PID、出口规则、UA3F、无线、代理节点选择不变，不把 DNS 修改与认证重连／代理重启／无线调参放在同一轮。以下是主代理的候选验收设计，本文未执行。

1. **查生效路径。** 读回核心版本与全部 DNS 字段的脱敏结构、53／7874 监听、dnsmasq 运行配置、DNS 相关 nft 规则和实际 LAN 查询。检查 default／proxy bootstrap、direct follow-policy、本机回指、上游实际出口、广告 NXDOMAIN 与家庭标识。配置通过 `-t` 只是语法／兼容检查，不代表 DNS 可达。
2. **当前只做少量公开协议探测。** 不部署新 DNS、不改生产字段。固定两个实际国内域名，在同一已确认直连出口，对阿里／腾讯的 DoH 各查一次，并在已有可靠工具支持时对各自 DoT 各查一次，最多 8 次加密查询；每次 3 秒上限，另复用或最多增加 4 次同供应商明文基线。验证必须包含真实 DNS 响应、rcode、CNAME／A／TTL 和证书校验，不能只以端口可连接或 HTTPS 页面 200 为成功。记录新连接／复用与出口，上游缓存未知。先回答可达性和明显代价；没有适用的 DoT 工具时报告未验，不为本轮安装新组件。
3. **冷／热分开。** 本地候选缓存未命中与相同记录的重复命中分别记录，不能用随机不存在子域名代替真实 CDN 域名。nslookup 的旧约 10 ms 计时只能识别明显超时差异；毫秒细差应使用已有更高分辨率工具，不为这一点安装完整新工具链。
4. **答案不同才追加 CDN 对照。** 后续确需验证时，先固定一个出口、最多两个域名、每域最多两个当次答案 IP、两轮反序，共最多 8 个 HEAD；每次 5 秒，固定 hostname／SNI／URL，保留证书校验。分别记录 connect、TLS、首字节、HTTP 语义与实际 IP。仅 HEAD 语义不适用时换相同数量的小 Range，最多 1 KiB 目标、64 KiB 响应上限。确认该域名及请求确实走 DIRECT；关闭 curl 显式代理不足以绕过透明代理。代理域名不把本地 `--resolve` 结果当作远端代理实际解析。当前无需自动追加此阶段，更不扩展到两出口下载对照。
5. **选用规则。** 成功率和正常业务语义不能下降；国内／校园／PAC／广告功能保持，节点启动不新增代理依赖；DNS 加额外等待与实际 HTTPS 首字节合计确有连续两轮明显收益时，才把该结果作为限定候选。答案相同、TLS 与业务时间无稳定差异时，速度收益记为未证实；如用户仍希望启用加密，可按隐私收益选择，并明确额外耗时。两轮只筛明显差异，不证明全天稳定性能。

该对照总量很小，不下载大文件、不寻找公网极限，不改生产认证。没有已验证的协议工具或独立入口时，先完成结构修正／架构结论，不把未执行写成通过。
