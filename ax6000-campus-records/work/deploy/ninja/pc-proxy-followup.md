# 本机代理与家庭／外出切换

## 当前结果

本机 Clash Verge 为 `2.5.2`，运行中的 Ninja 内核为 `ab32ad2d`。TUN 关闭，系统代理启用 PAC。主代理已备份并应用家庭 DNS 标识 PAC，重开 GUI 后，本分支独立读回实际 `/commands/pac`，确认与候选及磁盘逐字一致。WinINET 的 `ProxyEnable=0` 只表示手动代理关闭；`AutoConfigURL` 仍指向回环地址 `127.0.0.1:33331/commands/pac`，PAC 仍参与支持该机制的应用。

Windows 原生按实际配置 URL 求值，微软下载、Steam CDN／商店／社区、百度、GitHub、Google 共 `7` 个域名现在均返回 `DIRECT`，交给家庭路由器后续分流。内核版本、TUN 状态、`14` 组名称与类型、Selector 选择、`3,528` 条规则，以及用户级环境代理都与修改前一致，`11` 项运行验收全部通过。证据：`home-pac-runtime-acceptance.json`。这证明运行中的 PAC 已采用家庭规则，不代表所有运行应用都已丢弃旧 PAC／环境缓存。

修改前，微软下载域名 `dl.delivery.mp.microsoft.com` 先进入本机 `127.0.0.1:7897`，规则 `DOMAIN-KEYWORD,microsoft` 命中 `Ⓜ️ 微软服务`。实际控制 API 显示该组选择 `🎯 全球直连`，最终为 `DIRECT`。因此原状态没有证据说明该下载被本机送到远端 Ninja；存在本机转发这一层。用户的 `40 MB/s` 约为 `320 Mbps`，不能只凭这个速度断定节点限速或双 WAN 失效。

微软云通知连接已读到同一规则和链：`DIRECT → 🎯 全球直连 → Ⓜ️ 微软服务`。这证明当前组选择，不能替代指定下载任务的完整吞吐对照。

修改前的原 PAC 已在 Windows 原生 `WinHttpGetProxyForUrl` 求值：微软下载、百度、GitHub、Steam 商店均返回本机 `127.0.0.1:7897`；Steam CDN 返回 `DIRECT`。本机有 `3,528` 条运行规则，包含旧调整中的 `10` 条 Steam CDN `DIRECT`。提取后的 profile 项没有独立 `prepend` 键，实际规则已经合并到运行配置开头，不能据 `prepend=[]` 判断旧调整消失。

用户级和当前进程的 `HTTP_PROXY`、`HTTPS_PROXY` 都指向本机 `7897`。WinHTTP 全局代理为 Direct。限定检查 `Code`、`Code - Insiders`、`Cursor` 的用户设置，`.npmrc`、全局 Git 的 proxy 键，以及三个常见 aria2 路径，没有发现独立代理设置。这只是明确列出的路径，不代表已审计所有软件。Codex 与 Agent Reach 初始化环境仍可使新子进程使用本机代理。

证据：`pc-proxy-before-home-pac.sanitized.json`、`pc-proxy-structure.sanitized.json`、`pc-proxy-rules.sanitized.json`、`app-proxy.sanitized.json`。只读提取脚本的 Node PAC fixture 故意模拟 `192.168.1.2` 外出网段；实际家庭运行决策以 `home-pac-runtime-acceptance.json` 的原生求值为准。读取脚本只输出配置开关、端口、组与规则，不输出订阅地址、许可、密码或 token。

## 可应用的 PAC 候选

`home-away-sentinel.candidate.pac` 在原 `FindProxyForURL` 开头增加条件：本机 IPv4 属于 `192.168.31.1～254`，并且家庭专用 DNS 名 `ax6000-home31.lan` 解析为 `192.168.31.1`。两个条件满足时返回 `DIRECT`，由家庭路由器处理后续分流；其他状态沿用完整原 PAC。主代理已添加该 DNS 记录并应用此 PAC，本分支按 Windows 系统默认 DNS 独立读回正确地址，再验证实际 PAC handler 和系统配置 URL。

`home-away-subnet.candidate.pac` 只判断 `192.168.31.0/24`，适合做机制验证。它在另一个使用相同网段的网络也会返回 `DIRECT`，因此优先采用带家庭 DNS 标识的候选。

本机多网卡可能使 `myIpAddress()` 返回另一个适配器的地址，某些 PAC 实现也可能返回 IPv6。候选遇到未知地址、回环地址、IPv6、异常或不存在家庭 DNS 标识时保留原 PAC。这会表现为仍经过本机代理，不能保证所有程序自动切换。家庭 DNS 标识是避免意外网段重合的辅助条件，不是认证协议；用户自定义 DoH 也可能看不到该记录。

Node VM 对原 PAC、网段候选和 DNS 标识候选完成 `288` 个变更断言，覆盖家庭 IPv4、其他网段、网段边界、回环、IPv6、无地址、DNS 标识存在／缺失。全部通过。该层是脚本行为检查。

Windows 原生 PAC 求值进一步确认：当前家庭网络中，网段候选五个样本全部返回 `DIRECT`；DNS 标识部署前，标识候选保留原 PAC。标识部署并独立读回后，标识候选五个样本也全部返回 `DIRECT`。临时服务只绑定回环地址，用完已停止，系统代理没有修改。证据：`home-away-pac-validation.json`、`home-away-pac-winhttp-validation.json`。离开家庭网络尚未进行真实现场测试。

## 应用方式与上游边界

Clash Verge `v2.5.2` 的 PAC 服务每次请求读取已提交的内存配置，不逐次读 `verge.yaml`。GUI 的系统代理设置保存 `pac_file_content` 时，会调用 `patch_verge_config`，更新草稿、应用、保存文件，并刷新系统代理；仅改 PAC 内容不触发内核重启。通过 GUI 保存后，应读回 `http://127.0.0.1:33331/commands/pac` 并再次执行 Windows 原生求值。直接在运行期间改 YAML 不能证明内存 PAC 已刷新。退出 GUI 后修改再重开可使它重新读文件，但会短暂中断本机代理。

源码：[PAC handler](https://github.com/clash-verge-rev/clash-verge-rev/blob/v2.5.2/src-tauri/src/utils/server.rs)、[设置更新与保存](https://github.com/clash-verge-rev/clash-verge-rev/blob/v2.5.2/src-tauri/src/feat/config.rs)、[系统代理设置界面](https://github.com/clash-verge-rev/clash-verge-rev/blob/v2.5.2/src/components/setting/mods/sysproxy-viewer.tsx)。对应本地副本以 `upstream-v2.5.2-` 开头。

没有找到当前 `v2.5.2` GUI 已支持 SSID 自动开关代理的证据。相关 [SSID Strategy #1231](https://github.com/clash-verge-rev/clash-verge-rev/issues/1231) 关闭时只链接内核设计讨论；[基于 Wi-Fi 名称的开关策略 #1338](https://github.com/clash-verge-rev/clash-verge-rev/issues/1338) 与较新的 [特定网络自动挂起 #8220](https://github.com/clash-verge-rev/clash-verge-rev/issues/8220) 也不能作为已实现证据。不要据 issue closed 推断安装中的 Ninja GUI具备此功能。

Windows 原生验证按 [WinHttpGetProxyForUrl](https://learn.microsoft.com/en-us/windows/win32/api/winhttp/nf-winhttp-winhttpgetproxyforurl) 执行。PAC 函数和 IPv6 实现差异参考 [MDN PAC 文档](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/Proxy_servers_and_tunneling/Proxy_Auto-Configuration_PAC_file)。

## 环境代理与应用

PAC 只影响遵从系统 PAC 的应用。固定写入 `127.0.0.1:7897` 的应用、CLI 环境代理、手机 VPN 不随 PAC 自动切换。不能只关系统代理就宣布“大部分软件都绕过本机代理”。

`Invoke-HomeAwayCli.candidate.ps1` 为可恢复的单次 CLI 调用方式：`Home` 只在调用及子进程期间移除 `HTTP_PROXY`、`HTTPS_PROXY`、`ALL_PROXY`，`Away` 重新读取用户级值；执行结束恢复原进程环境。它不写用户注册表，不修改用户级环境，也不重启运行程序。验证用无网络子进程输出代理变量是否存在：Home 三项均 false，Away HTTP(S) 为 true，原进程值精确恢复。证据：`home-away-cli-validation.json`。

已运行应用仍持有启动时环境。若它们需要家庭无本机转发，应在家庭模式下重新启动对应应用，或使用其明确的直连配置；不要删除用户级环境代理而破坏外出 CLI。手机需要按实际系统与客户端确定家庭 Wi-Fi 策略，目前没有控制该设备的证据。

## 给路由器的最小规则补充

`router-download-rules.candidate.yaml` 提取本机已验证存在的 `10` 条 Steam CDN 规则，并增加 `DOMAIN,dl.delivery.mp.microsoft.com,DIRECT`。保留原匹配类型：`steamcontent.com` 为 `DOMAIN-SUFFIX`，其余 `9` 条 Steam CDN 为 `DOMAIN`。只复制域名规则，不复制 Windows 进程规则。生产覆写把 `DIRECT` 转入既有 UA3F TCP 分支时，应保持该契约；本文件没有改动路由器。

不把全部 `microsoft.com` 或 Microsoft 服务改为 `DIRECT`，以免同时改变 Copilot、登录、地区内容等业务。微软下载其他域名若确实出现，可按实际日志和请求补充具体域名，优先确认是更新／下载端点。

## Edge 并行下载的实际范围

用户确认使用 Edge 内置下载器，已在 `edge://flags` 开启并行下载。本机只读取 `Local State` 的 `browser.enabled_labs_experiments`，确认保存项包含 `enable-parallel-downloading@1`；Edge EXE 版本为 `155.0.4283.45`。没有读取浏览记录或下载历史，没有修改浏览器配置。证据：`edge-labs.sanitized.json`。

按 Chromium 同主版本上游 `155.0.8059.9` 的实现，默认 `request_count=3`，含原始请求，通常再创建至多 `2` 个新切片请求。默认最小切片为 `1,365,333` 字节，只有预计剩余下载时间大于 `2` 秒时才为新下载分叉；切片不足时请求数还会减少。参数可被 Finch 覆盖，开启 flag 不等于把下载改成任意数量线程。[默认参数与切片计算](https://github.com/chromium/chromium/blob/155.0.8059.9/components/download/internal/common/parallel_download_utils.cc)、[创建额外请求](https://github.com/chromium/chromium/blob/155.0.8059.9/components/download/internal/common/parallel_download_job.cc)

工厂会检查强 ETag 或满足强校验条件的 Last-Modified、已知正内容长度、允许／未知 Range 支持、文件大小或已存切片、HTTP(S) GET，以及下载恢复状态。某些内存下载、需要按顺序加密的下载、由 Service Worker 产生的下载和显式任意 Range 下载不能采用这套并行任务。当前 `155` 源码还允许受独立 feature 控制的 HTTP/2、QUIC 并行请求，两个 feature 默认启用；不要据源码中残留的“HTTP/1.1”注释认定它永远只支持该协议。[触发条件](https://github.com/chromium/chromium/blob/155.0.8059.9/components/download/internal/common/download_job_factory.cc)、[协议开关](https://github.com/chromium/chromium/blob/155.0.8059.9/components/download/public/common/download_features.cc)

对用户同一 `dl.delivery.mp.microsoft.com` ESD 源只执行了一次 HEAD：返回 `HTTP/1.1 200`，内容长度 `6,326,574,815` 字节，有 `Accept-Ranges: bytes`、强 ETag 和 Last-Modified。它具备主要响应条件；这个 HEAD 来自 curl，仍不能代替 Edge 的实际下载协议、分叉数和连接观测。证据：`edge-download-source-headers.json`。

并行请求数量与 WAN 连接数量不同。HTTP/2 或 QUIC 可以把多个请求复用到同一传输连接，按连接处理的 MWAN 不会拆分其中的应用流；具体是否复用需现场观测。用户当前是 HTTP URL，HEAD 为 HTTP/1.1，所以不能把 HTTP/2／QUIC 复用当作这次下载已确认的根因。[HTTP/2 多路复用](https://www.rfc-editor.org/rfc/rfc9113.html#section-5)、[QUIC 流](https://www.rfc-editor.org/rfc/rfc9000.html#section-2)

即使只有 `3` 条独立 TCP 请求，MWAN 按连接选择出口，也不能保证下载字节恰好各半。请求可能不均匀分配，来源的单连接速率、CDN负载、切片完成时间和两 WAN 的实际限速会影响总速率。因此“Edge 开了并行下载”不能作为“两 WAN 应当稳定达到 700 Mbps”的验收。主分支使用 `8` 路 curl 的结果适合验证独立连接的分摊与吞吐，不等同于 Edge 默认下载行为。上述机制来自公开 Chromium，同主版本仍不是 Edge 私有分支、Finch 参数或本次运行行为的完整证明。

## Android Ninja 的家庭／外出切换边界

用户确认手机为 Android，客户端名称为 Ninja。官方目前同时有一键 `Ninja Client` 和 `Clash Ninja for Android` 两条产品路径，不能只据“Ninja”名称判断具体功能。

一键客户端官方帮助说明登录、等待 API 就绪、一键加速及设置中的专业模式；发布仓库确有 `NinjaClient-3.1.3.apk`。旧 Clash Ninja 官方帮助说明导入 Clash Ninja 订阅、启动服务时允许 VPN、选择节点。两篇已读正文都没有确认按 SSID 自动启停 VPN、家庭 Wi-Fi 免代理或自动网络策略。公开仓库的当前代码树未提供 Android 客户端实现可核对。[Ninja Client 官方帮助](https://world.crisp.help/zh/article/ninja-client-windowsmacoslinuxandroid-t904y4/)、[Clash Ninja Android 官方帮助](https://world.crisp.help/zh/article/clash-ninja-for-android-1fmr5oz/)、[手机 3.1.3 发布](https://github.com/kachetong1314/ninja/releases/tag/1.0.3)

检索范围为官方 Ninja 帮助的 Android 分类、全平台分类、一键客户端页、Clash Ninja Android 页，以及 `kachetong1314/ninja` 中的 `SSID`、`WiFi`、`Android` issue 搜索和当前发布资料。`SSID` issue 搜索为空，WiFi 结果为 macOS 权限问题，Android 结果主要为旧 TV 客户端问题。没有把“未找到证据”写成“该功能一定不存在”。

在没有手机实例、应用版本和设置读回的情况下，只能给明确的操作方向：连接家庭路由 Wi-Fi 时手动停止 Ninja 的 VPN 接管，离开后再开启客户端。若 Android 开启了始终开启 VPN／阻止无 VPN 连接，停客户端是否允许正常直连还取决于该系统设置，需在手机上核对。这里没有配置或验证手机，也不把公版 Clash Meta for Android 的网络策略当作 Ninja Client 已有能力。

## 未完成的现场证明

本分支完成了只读配置核验、当前代理组选择、脚本候选、Windows PAC 实际求值、家庭 DNS 标识部署后的独立读回、实际 GUI PAC 应用后的独立验收、单次 CLI 环境恢复、Edge 保存开关／上游机制，以及 Android Ninja 官方能力边界查询。尚未证明 Edge 本次真实下载的分叉数／传输连接数、手机自动切换、真实外出网络切换、所有应用代理覆盖或下载改善。应用与路由器写操作由主代理统一执行。
