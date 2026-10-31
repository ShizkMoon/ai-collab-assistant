# 当前 Edge 的 HTTP/3 与 ECH 启用方案

建议保留当前 DNS、家庭 PAC 和固定 Ninja／香港 02，只确认并允许 Edge 协商 QUIC 与 ECH。Microsoft 的受支持策略为 `QuicAllowed=1` 和 `EncryptedClientHelloEnabled=1`；两项未设置时本来就允许相应默认路径。若当前策略与命令行没有禁用，不能把新写两个值描述为从“完全关闭”变成“每站强制开启”。用户所说全局按当前 Windows 用户的 Edge、全部站点可协商理解，不扩展到 Chrome、其他浏览器、所有 Windows 用户或路由器传输协议。

本支线只读官方资料及指定安全证据，未控制浏览器、修改注册表、SSH 或执行业务探针。当前 Edge 155 是主代理提供的目标版本；实际完整版本、现有策略和运行参数由主代理在目标浏览器核对。Microsoft 本轮页面的政策支持下限均低于 155，但识别和有效状态仍须以 `edge://policy` 为准。

## 受支持策略与最小写入范围

Windows 必填策略路径是 `SOFTWARE\Policies\Microsoft\Edge`，可按用户配置落在 `HKCU`；现有设备级、域策略或云策略可能优先，因此写入后要读实际生效来源和错误。以下策略均不支持 Recommended，均非每个 profile 独立。

| 策略名称 | 类型与值 | 官方默认／作用 | 刷新与本轮处理 |
| --- | --- | --- | --- |
| `QuicAllowed` | `REG_DWORD`，`1` | 未设置／1 允许 QUIC，0 阻止；Windows ≥77 | 不支持动态刷新，需整个 Edge 重启；确认或钉为 1，保留原值用于恢复 |
| `EncryptedClientHelloEnabled` | `REG_DWORD`，`1` | 未设置／1 跟随 ECH 默认 rollout，0 禁用；仍依赖服务器和 HTTPS RR；Windows ≥108 | 动态刷新；确认或钉为 1，不强迫所有站点成功 |
| `AdditionalDnsQueryTypesEnabled` | `REG_DWORD`，`1` | 未设置／1 允许普通 DNS 查询 HTTPS type 65 等，0 只允许 A／AAAA；Secure DNS 不受此项限制；Windows ≥140 | 动态刷新；仅若当前 0 阻碍 ECH 才按本轮能力范围改为 1，其余情况下保留 |
| `BuiltInDnsClientEnabled` | `REG_DWORD`，`1` | 未设置／1 使用内置解析器，仍用系统 DNS；不负责选择 DoH 服务器；Windows ≥77 | 动态刷新；只核对，不因 ECH 自动追加 |
| `DnsOverHttpsMode` | `REG_SZ`：`off`／`automatic`／`secure` | automatic 优先可用 DoH，失败允许普通 DNS；secure 无普通 DNS 回退，解析失败；Windows ≥83 | 只核对并保留现有值，本轮不自动改 |
| `DnsOverHttpsTemplates` | `REG_SZ`，URI 模板，多值以空格分隔 | secure 要求非空；automatic 未设模板时尝试同运营商的内置升级映射；有 `dns` 变量用 GET，否则 POST | 只核对并保留；不写公共解析器代替路由器 |

来源：[QUIC 策略](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/QuicAllowed)、[ECH 策略](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/EncryptedClientHelloEnabled)、[额外 DNS 类型](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/AdditionalDnsQueryTypesEnabled)、[内置 DNS 客户端](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/BuiltInDnsClientEnabled)、[DoH 模式](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/DnsOverHttpsMode)、[DoH 模板](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/DnsOverHttpsTemplates)。HKCU 用于当前用户，不意味着绕过受管理浏览器的 DNS 检查；最终是否适用由目标 Edge 读回。[Windows 策略部署与读回](https://learn.microsoft.com/en-us/deployedge/configure-microsoft-edge)

## DNS 条件与当前路由器的关系

ECH 要取得站点提供的 ECHConfig，常用路径是 HTTPS DNS RR（type 65），并要求浏览器和服务器均支持。Secure DNS 能保护查询传输，但“所有现代 Edge 的 ECH 都必须换成公共 DoH”不成立：Edge ≥140 官方策略允许普通 DNS 查询额外类型，当前 Chromium 也保留了普通 DNS 的 HTTPS RR 路径。普通 DNS 得到 ECH 配置不等于 DNS 已加密，更不等于所有站点支持 ECH。

当前文档与安全证据表明，LAN DNS 经过 dnsmasq 53→OpenClash 7874；`baidu.com`、`bilibili.com`、`jd.com`、`qq.com`、`taobao.com`、`tmall.com`、`alipay.com`、`weibo.com`、`163.com` 九个后缀使用阿里／DNSPod DoH；全局 nameserver 和 bootstrap、原校园 policy、国外 Cloudflare fallback 保持。广告域名在 53 路径由 adblock-fast／HaGeZi Light 过滤。此前 `crypto.cloudflare.com` 的 HTTPS RR 已保留，而指定 Edge 连接的 `server_sni=encrypted`、TLS 1.3 与 h2 是实际 ECH 证据。[采用结果](../frontier/adoption-results.md)、[浏览器安全摘要](../frontier/browser-encrypted-transport.txt)

在 Edge 填公共 `DnsOverHttpsTemplates` 或改自定义公共 Secure DNS，会将浏览器查询绕过路由器 53／7874，不能再保证九后缀策略、局域网名字和 DNS 广告过滤仍参与。ECH 隐藏 SNI 后，透明代理的域名识别更需要核对原 DNS 映射与规则；不得靠换全局 DoH 造成解析和分流变化，再把连接成功写成无副作用。本轮不加路由器本地 DoH 服务，也不把 `http://192.168.31.1:53` 或 `:7874` 当合格 DoH URI。

另一个实际副作用需在写前后核对：Microsoft 说明受管理设备未配置 DoH 模式时可能不发 DoH。Chromium 的 `ShouldDisableDohForManaged()` 会检查 Windows domain join 和平台 policy provider；`HasMachineLevelPolicies()` 的 provider 检查不是简单按 HKCU／HKLM 分开。新加本地 Edge policy 可能让既有用户选定 DoH 被管理条件关停，因此不能保证“只写两项就绝对不影响 DNS”。若原值未禁用且当前能力已可用，保留默认也能完成允许协商的目标；若明确钉策略，应先记录原 DNS 状态，写后重验 ECH、广告和正常域名，出现行为变化就精确恢复本轮新增值，不能自动补公共 DoH。

源码核查固定到 Chromium `8bed8f48c814090c12abc14ac80ab8dafc7f7a6f`（本轮取得的 upstream HEAD），仅解释机制，不声称与 Edge 155 的私有分支逐字相同：[DNS task](https://github.com/chromium/chromium/blob/8bed8f48c814090c12abc14ac80ab8dafc7f7a6f/net/dns/host_resolver_dns_task.cc)、[DNS client](https://github.com/chromium/chromium/blob/8bed8f48c814090c12abc14ac80ab8dafc7f7a6f/net/dns/dns_client.cc)、[Secure DNS 配置](https://github.com/chromium/chromium/blob/8bed8f48c814090c12abc14ac80ab8dafc7f7a6f/chrome/browser/net/stub_resolver_config_reader.cc)、[平台 policy 判断](https://github.com/chromium/chromium/blob/8bed8f48c814090c12abc14ac80ab8dafc7f7a6f/chrome/browser/policy/chrome_browser_policy_connector.cc)。

## HTTP/3、ECH 与代理的边界

HTTP/3 是 Edge 到网站服务端的 HTTP 应用层协议，底层为 QUIC／UDP；与 Ninja 隧道传输名称不同。`QuicAllowed=1` 只让浏览器尝试：服务器须支持并通过 Alt-Svc／HTTPS RR 等发布，浏览器、UDP 路径、路由器接管和固定香港节点都要相容。普通未强制协议模式保留 HTTP/2 或 HTTP/1.1 的 HTTPS 路径；Chromium 主连接与替代 QUIC 连接有竞速／失败恢复机制，但 UDP 被丢弃仍可能增加等待，不能承诺所有错误都无延迟。不能使用 `--origin-to-force-quic-on=*` 或只允许 H3 的试验参数来完成日常启用。[QUIC 概述](https://www.chromium.org/quic/)、[HTTP 连接竞速源码](https://github.com/chromium/chromium/blob/8bed8f48c814090c12abc14ac80ab8dafc7f7a6f/net/http/http_stream_factory_job_controller.cc)、[Cloudflare HTTP/3](https://developers.cloudflare.com/speed/optimization/protocol/http3/)

ECH 的启用策略保留条件协商，服务器拒绝时 Chromium 有认证后的 retry config 路径；不存在“任意握手错误都降级成功”的保证。证书错误或网络错误仍可能失败。不能降低 TLS 校验，也不为避免失败关闭 HTTPS。[ECH 实现](https://github.com/chromium/chromium/blob/8bed8f48c814090c12abc14ac80ab8dafc7f7a6f/net/socket/ssl_connect_job.cc)、[Cloudflare ECH 条件](https://developers.cloudflare.com/ssl/edge-certificates/ech/)

当前家庭 PAC 返回 DIRECT，Edge 在自身网络栈看来直接连接目标，随后由路由器 Redir-Host／规则模式透明处理 TCP 与 UDP。这有利于保留普通 QUIC 和 HTTPS RR 路径，但不是校园物理直出或绕过 Ninja。外出 PAC、固定本机 HTTP/SOCKS 代理则不同：Chromium SOCKS5 的浏览器 URL 代理只运送 TCP，不能转发 UDP；现有 SSL connect job 也注明带 ECHConfig 的 DNS 覆盖只支持 DIRECT。不得为了 HTTP/3 将 PAC 改固定代理或将返回值改为实验 QUIC proxy。[Chromium 代理文档](https://github.com/chromium/chromium/blob/8bed8f48c814090c12abc14ac80ab8dafc7f7a6f/net/docs/proxy.md)

固定香港路径的前轮 DoH3／DoQ 失败，不能外推成全部网站 H3 不可能；此前有效 DIRECT DNS 回答也未证实实际 H3。本轮仍须用目标 Edge 真实网页协议验收，不更换 Ninja 核心、节点、UDP 接管或 fallback 来凑成功。[前轮查询边界](../frontier/adoption-results.md)

## 主代理的核对与交付方法

1. 在当前 Edge 读取 `edge://version` 的完整版本和命令行，仅保存相关 QUIC／ECH／DNS flags；读取 `edge://policy`，核对上述六项的有效值、作用域、来源、状态与冲突。读取当前 Secure DNS 设置以及家庭 PAC 对测试域名的实际 DIRECT 结果。不要导出含全部浏览历史的完整命令行或 profile。
2. 在 HKCU 和 HKLM 的 `SOFTWARE\Policies\Microsoft\Edge` 只读六个值，记录值是否原本存在、类型与原值；保留精确恢复资料。DoH 模板如含私人端点，应在工作结果里脱敏。只查当前 policy，不覆盖整分支，不改变 Chrome 分支、Windows 系统 DNS 或其他浏览器。
3. 若现有 0 或禁止 flags 有实际阻碍，主代理按用户授权调整已确认的相应项；若默认已允许，可以如实交付当前能力已启用。若选择钉为 1，仅写最小受支持 policy。刷新 `edge://policy` 后，ECH 需新连接，QUIC 需整个 Edge 正常关闭并重开；不得强杀含未保存状态的浏览器进程。重启未完成时只能说写入已完成、当前运行待激活。
4. 用新测试连接访问一个国内正常站点、一个现有需代理站点和指定 Cloudflare trace。记录导航／响应的实际 `protocol`，以及服务端 `http`、TLS、`server_sni`。当前 CDP schema 的 `Network.responseReceived.response.securityDetails.encryptedClientHello` 可作客户端补证；先确认目标 Edge schema 有该字段。h3 才是 HTTP/3 业务证据，`encryptedClientHello=true` 或 `server_sni=encrypted` 才是该连接 ECH 证据；flag 为 Enabled、Alt-Svc 存在或 UDP 443 发包不够。[CDP Network schema](https://github.com/ChromeDevTools/devtools-protocol/blob/master/pdl/domains/Network.pdl)
5. 另在浏览器实际解析路径核对家庭标识和广告域名，不能只用 Windows `Resolve-DnsName` 代替 Edge DNS 验收。若读回仍为 h2 且正常，报告 QUIC 允许、此连接未使用 H3，保留自动回退；若 ECH 前后均通过，报告原有能力被保留。不要无限追加探针或使用强迫协议 flags。
6. 交付明确区分已存 policy、目标 Edge 已识别、重启后运行生效、具体 H3／ECH 连接、DNS／广告／PAC 行为。遇新故障，只恢复本轮改动的原值或删除本轮原本不存在的单项，再核对原业务；不删除整个 Edge policy 分支。

本方案的可观察目标是 Edge 对支持的站点允许协商，并继续保留可靠的 HTTPS 回退、家庭 DNS 和代理路径。它不承诺所有站点都是 H3＋ECH，也没有公网下载提速证据。
