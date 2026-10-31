# UA-Mask 的性能证据与版本边界

公开资料不足以证明：把本机现有 UA3F 换成 UA-Mask，就能在保留三路认证、完整明文 HTTP UA 改写、TTL 与 HK 代理路径的条件下，让无线 PC 完整多连接下载稳定超过 900 Mbps。UA-Mask 的缩短转发路径、减少匹配开销和目标级绕过可以作为技术候选；其中最醒目的 CPU 降幅主要来自让流量绕过 UA-Mask，不能直接用于承诺本任务的完整改写吞吐。

本机背景由主线提供：AX6000 / MT7986＋BE200，当前完整 PC 下载约 768～821 Mbps，路由器约 911～923 Mbps，纯 LAN 6 GiB 约 995 Mbps。本支线没有重新测量这些数字，也没有登录路由器、安装 UA-Mask、运行程序或基准。本机结果与下述公开作者数字分开判断。

## 固定版本和发行状态

| 对象 | 本次 GitHub 只读核对结果 | 适用范围 |
| --- | --- | --- |
| main | `83846d3780b1e30f87816310ae75d95798a5bd4d`，提交日期为 2026-08-02 | 本文架构判断固定到此 SHA；仓库 push 时间还包含 PR 分支，不能用 push 时间代替 main 提交 |
| 最新公开 release | v0.4.3，2025-11-21 11:38:43 UTC 发布；标签指向 `1e5a5ce38fc207136ba21a3f82a6a3e892a3c572` | 旧 `src/` 结构，包含该年代的修复；不是 2026 年重构后的 main |
| v0.4.3 aarch64 Cortex-A53 IPK | `UAmask_0.4.3-1_aarch64_cortex-a53.ipk`，2025-11-21 上传 | release 提供此架构包不等于当前 AX6000 固件、依赖、规则与三认证兼容已验证 |
| v0.4.3 aarch64 Cortex-A53 APK | `UAmask-0.4.3-r1_aarch64_cortex-a53.apk`，2025-11-22 15:54:02 UTC 上传，GitHub digest 为 `sha256:8b590c44ed10fcf4b87b0a3607feec2ed9447b1ce7cd9a17f95420222077a6e0` | 本次只读元数据，未下载或核验包内部二进制；不能把文件名、架构名、digest 当作当前系统安装和运行验收 |
| main 的 `VERSION` | 仍为 `0.4.3` | 仅看版本字符串无法区分旧发行源码与新 main；后续产物需同时绑定 commit 与构建元数据 |

来源：[固定 main 提交](https://github.com/Zesuy/UA-Mask/commit/83846d3780b1e30f87816310ae75d95798a5bd4d)、[v0.4.3 release](https://github.com/Zesuy/UA-Mask/releases/tag/v0.4.3)、[v0.4.3 tag API](https://api.github.com/repos/Zesuy/UA-Mask/git/ref/tags/v0.4.3)、[main 的 VERSION](https://github.com/Zesuy/UA-Mask/blob/83846d3780b1e30f87816310ae75d95798a5bd4d/VERSION)。资产时间和 digest 来自 [release API](https://api.github.com/repos/Zesuy/UA-Mask/releases/latest)，缓存保存了完整返回。

main 相对 v0.4.3 标签增加 **2 个提交、93 个变更文件**：先合并 [PR #22](https://github.com/Zesuy/UA-Mask/pull/22)，把重叠的 proxy / firewall 处理改为统一的 session、events、state、policy、offload 管线；再合并 [PR #23](https://github.com/Zesuy/UA-Mask/pull/23)，加入固定 SDK、构建元数据和发行流程。旧标签没有 `docs/architecture.md` 或 `.github/workflows/`，Go 代码在 `src/`；新 main 则迁移为 `core/` 与 `openwrt/`。[固定版本比较](https://github.com/Zesuy/UA-Mask/compare/1e5a5ce38fc207136ba21a3f82a6a3e892a3c572...83846d3780b1e30f87816310ae75d95798a5bd4d)

现存 release 的资产时间早于这次重构，公开 release 列表也没有更新的 release；因此应把旧发行包与新 main 作为不同候选评估。本次未解包旧 APK，不能提供它与某一源码提交完全一致的二进制证明。新 main 的发行流程规定手工 workflow 只生成 canary artifact，标签才发布 release，并要求 commit / SDK / SHA256 元数据；这些是新流程的能力，不能追认旧 v0.4.3 包具备同样的构建追踪。[固定发行 workflow](https://github.com/Zesuy/UA-Mask/blob/83846d3780b1e30f87816310ae75d95798a5bd4d/.github/workflows/release.yml)、[OpenWrt 构建说明](https://github.com/Zesuy/UA-Mask/blob/83846d3780b1e30f87816310ae75d95798a5bd4d/openwrt/README.md)

## 主要性能主张分别证明了什么

| 公开内容 | 证据类型与缺失条件 | 对本机的含义 |
| --- | --- | --- |
| README：P2P、Steam、加密代理等重流量开启卸载后可降低 80% 以上 CPU | 作者宣称；未附设备、版本、负载、CPU 采样口径、前后原始记录和重复误差。描述的核心机制是绕过处理 | 不能推出本机全部 HTTP 仍经 UA 改写时也有同样降幅；CPU 相对降幅也不是吞吐倍率 |
| README：原文称 `mt7920` 上 iperf3 上行约 97 Mbps、下行约 78 Mbps，HTTP hey 接近 | 作者报告；没有板型、内核、二进制 SHA、拓扑、命令、并发、正文规模、时长与结果文件。保留原文设备拼写，不推定其实际芯片 | 不是 MT7986＋BE200 实测，不能按 CPU 档次或架构比值外推到 900 Mbps；iperf3 与完整 HTTP 下载的行为也不同 |
| README：90% 以上 UA 缓存命中、低 GC、Redirect 开销低 | 作者主张或实现方向；没有同设备 CPU / 分配 / GC / 吞吐对照 | 支持继续检查热路径机制，尚不足以确定本机当前差额来自 UA 层 |
| 教程演进：旧链经 OpenClash → SOCKS5 → UA3F，后来缩短路径并引入 set 绕过 | 作者解释的历史方案差异，改变了转发路径及是否经过处理 | 与本机现有透明 UA3F 路径不同，不能把去掉旧 SOCKS5／Clash 链的收益算成替换本机 UA3F 的收益 |

对应正文：[README 的卸载主张，第 40～46 行](https://github.com/Zesuy/UA-Mask/blob/83846d3780b1e30f87816310ae75d95798a5bd4d/README.md#L40-L46)、[特性，第 64～70 行](https://github.com/Zesuy/UA-Mask/blob/83846d3780b1e30f87816310ae75d95798a5bd4d/README.md#L64-L70)、[硬路由数字，第 118～120 行](https://github.com/Zesuy/UA-Mask/blob/83846d3780b1e30f87816310ae75d95798a5bd4d/README.md#L118-L120)、[教程演进，第 435～452 行](https://github.com/Zesuy/UA-Mask/blob/83846d3780b1e30f87816310ae75d95798a5bd4d/docs/tutorial.md#L435-L452)。这些核心数字在旧 v0.4.3 README 中已经存在，不能解释为新 main 重构后的最新性能验收。[旧版 README](https://github.com/Zesuy/UA-Mask/blob/1e5a5ce38fc207136ba21a3f82a6a3e892a3c572/README.md)

本次还实际查看教程的 `before-bad.png`、`after-spark-1.png`、`ipset-love.png` 和 `structure-all.png`。它们是手绘流量路径示意图：前图标出 400 Mbps 与两个 50% CPU，卸载图标出 1000 Mbps、10% CPU、90% 流量绕过。没有硬件、时间轴、测量命令或原始日志，按作者示意处理，不能列作可复现同设备基准。[前图](https://github.com/Zesuy/UA-Mask/blob/83846d3780b1e30f87816310ae75d95798a5bd4d/docs/img/before-bad.png)、[卸载图](https://github.com/Zesuy/UA-Mask/blob/83846d3780b1e30f87816310ae75d95798a5bd4d/docs/img/ipset-love.png)

## 卸载的 UA 条件与本任务约束

教程明确说明，目标 `IP:Port` 被加入 set 后，在超时内会绕过 UA-Mask，可能泄露真实 UA；严格环境建议关闭卸载与 UA 防火墙关键词白名单。这比 README 的概括性安全宣传更具体，应作为评估边界。[教程，第 186～223 行](https://github.com/Zesuy/UA-Mask/blob/83846d3780b1e30f87816310ae75d95798a5bd4d/docs/tutorial.md#L186-L223)

固定 main 的架构说明进一步确认：`NoopFlowOffloader` 是空实现，实际生效的是目标级 `IP:Port` offload。一次会话产生信号，防火墙执行器更新目标集合；它没有证明只让已改完 UA 的正文流量在同一连接上安全切换为内核转发。教程描述的关键收益在于后续新连接直接放行，或命中后断开再连接。[架构，第 477～528 行](https://github.com/Zesuy/UA-Mask/blob/83846d3780b1e30f87816310ae75d95798a5bd4d/docs/architecture.md#L477-L528)

据此推断，本机的首项有效性能比较应保持被测明文 HTTP 不进入绕过集合，并在真实出口核对请求 UA；否则测到 900 Mbps 也不能满足“完整下载且保留 UA 改写”的目标。若未来评估非 HTTP 卸载，目标级集合在共享 IP / 端口上的影响必须另验，不能从某条连接分类正确推出所有后续连接也无需改写。三认证、TTL 和 HK 出口保留还需要现有链的实际读回；UA-Mask 的作者数字没有覆盖这些条件。

## 社区报告、提交和功能验证

本次读取全部 16 个公开 issue 正文、28 条 issue 评论、6 个 discussion 正文、5 条顶层 discussion 评论和 2 条回复；另外读取 3 个 PR。REST 采用分页读取，GraphQL 的 discussion / comment / reply 分页均确认没有下一页。可读文本中没有找到 AX6000 / MT7986＋BE200、完整改写明文 HTTP 的前后吞吐基准。

| 记录 | 实际内容 | 可得结论 |
| --- | --- | --- |
| [Issue #3 的用户评论](https://github.com/Zesuy/UA-Mask/issues/3#issuecomment-3446860707)，2025-10-25 | 用户说相比通过 Clash 的方案，速度与 UA 命中明显改善；无硬件、速率、源、并发或测量记录 | 这是独立用户的主观对比，有价值但无法量化，且发生在旧版本年代 |
| [Issue #21](https://github.com/Zesuy/UA-Mask/issues/21)，2026-03-17 | 用户报告 Medium 下 500 连接用满后代理及头像加载异常；没有设备、版本或吞吐测试 | 是连接容量／可靠性信号，不是 main 已复现的缺陷或同设备速率对照 |
| [Issue #16](https://github.com/Zesuy/UA-Mask/issues/16) 与 [Discussion #15](https://github.com/Zesuy/UA-Mask/discussions/15) | ShellCrash / PassWall2 共存请求，以及 OpenClash 本机流量处理与检测异常报告 | 默认安装不自动证明本机代理、mark、hook 优先级和认证路径正确 |
| [Issue #2](https://github.com/Zesuy/UA-Mask/issues/2#issuecomment-3443337496)、[Issue #3](https://github.com/Zesuy/UA-Mask/issues/3#issuecomment-3446871129)、[Issue #4](https://github.com/Zesuy/UA-Mask/issues/4#issuecomment-3448685773) | 作者确认并修正早期 keep-alive 请求遗漏、目标缓存导致 UA 泄露、HTTP body 解析错误 | 说明性能捷径必须与完整请求行为一起验证；不能说这些早期问题仍存在于固定 main |
| [v0.4.3 release](https://github.com/Zesuy/UA-Mask/releases/tag/v0.4.3)／[Discussion #12](https://github.com/Zesuy/UA-Mask/discussions/12) | 作者报告移除旧路径的硬编码 5 分钟超时 | 是稳定性修复，未提供 900 Mbps 证明；release 与对应 discussion 是同源内容，不能算两份独立证据 |
| [2025-10-19 提交](https://github.com/Zesuy/UA-Mask/commit/3c8a36857d2d9be8f4b3ebc082ad840861a4c7e3) | 提交信息说流式处理测试降低约 5% 占用，diff 是实现修改，没有测试条件或结果文件 | 作者旧提交的非可复现报告，不适合作为当前 main 收益预测；后续还修复了相关请求行为 |
| [已合并 PR #22](https://github.com/Zesuy/UA-Mask/pull/22) | 声明完成 race / stress、确定性场景与 OpenWrt 23.05.5 x86/64 两 VM 的 HTTP 改写、非 HTTP offload、重启和关闭验证；另有维护者实体 x86/64 功能报告 | 提高对功能与生命周期的信心，不能转换成 ARM 无线吞吐；PR 正文中的本地报告未由本次研究复跑 |
| [main 的 Core CI](https://github.com/Zesuy/UA-Mask/actions/runs/30730160356) | API 显示该固定 SHA 的 push run completed / success | 是公开检查状态，不是本机集成或性能基准；本次没有下载全部 CI artifact 或审计每项执行日志 |
| [PR #25](https://github.com/Zesuy/UA-Mask/pull/25) | 仍 open / 未合并，主要为 Playwright / QEMU LuCI 产品检查，声明未使用实体路由器 | 不计入固定 main 的功能或本机性能证据 |

## 能支持的决定与剩余不确定性

现在可以确认 UA-Mask 有可读、已重构的 main，旧发行包也有 Cortex-A53 APK；公开设计提供直接 Redirect、UA 结果缓存及目标集合绕过。公开证据支持把“固定 main、关闭被测 HTTP 绕过、保留本机实际防检测与出口约束”列作后续候选评估条件。尚不能支持“安装最新 release 就能超过 900 Mbps”或“CPU 必降 80%”。

如果主线后续确实比较，需要固定源码 SHA／产物 SHA、相同真实外层端点、总字节、连接数、限速与并发状态，保存完整正文、逐秒吞吐、各核／进程 CPU、重传、真实 UA 和出口规则计数。旧 release 与新 main 应分别标明，不能只写 v0.4.3。该段是根据证据缺口提出的验收条件，本支线没有执行测试、建议放宽 UA / TTL 条件或新增安装步骤。

“未找到”限定于本次取得的仓库树、main 全部 127 条历史提交元数据、重点性能提交 diff、上述正文与评论；搜索式包括 `80%|97|78|吞吐|速度|速率|性能|CPU|Mbps|AX6000|MT7986|MT7920|MT7620|iperf|对照|对比|测试|benchmark|UA3F`。两份固定树返回 `truncated=false`；main 15 个 `_test.go` 文件的存在不能证明性能 suite，本次也没有全读所有测试实现。正文中的全部外部图片附件、论坛转载、下载包内二进制与未公开测试没有全面核验，不能断言项目作者从未做过更完整测试。

原始公开资料缓存：`C:/Users/Shizuku/.agent-reach/research/ua-mask-evidence-83846d3/`，包括 ref、tag、release、固定树、比较、文档、全部 issue / discussion / 评论、历史提交、重点 diff、PR 与 CI 状态，以及四张实际查看的仓库图。访问使用 Agent Reach 的 GitHub／gh 只读后端；没有外部写入、设备访问、安装或 benchmark。Agent Reach 的 check-update 返回本机 v1.5.0 已是最新，未更新工具。
