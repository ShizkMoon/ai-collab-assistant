# DS-Bot 入口层选型

> 新架构说明：DS-Bot 负责入口翻译（从能力目录里选出 `kind`）和出口表达；需要覆盖更多 IM 平台时可以换用或并用 AstrBot（见 [开源复用地图](open-source-reuse.md)）。事件层的接法以 [事件规格 §5](event-spec.md) 为准。

> 结论：入口层实现从 Hermes 切到 DS-Bot。入口层的职责不变，Orca 仍是唯一任务账，所有设备相关任务仍走“下发即监督”。
>
> 核对基线：2026-10-28，DS-Bot `main` 提交 `4a7b550`，`ds-bot` 包版本 `0.2.3`。插件文档验证 DSH `0.2.1-rc.2`，Dockerfile 默认仍用 DSH `0.2.0-rc.2`。这是早期预览版，功能和保存数据格式仍可能变化。

## 为什么可以换

DS-Bot 不是另一个独立的 agent runtime，而是 [DeepSeek Harness（DSH）](https://github.com/deepseek-ai/deepseek-harness) 的 Bot 团队插件：可作为 DSH Web / DSH Desktop 的插件运行，另有自带 DSH 的桌面应用和 Docker Web 部署。它把 DSH 的 Session、模型、工具、MCP 和 skills 包装成长期存在的 Bot、Main Bot 与群聊。

它是 Apache-2.0 的独立社区项目，不是 DeepSeek 官方产品；选它意味着接受其维护节奏和早期预览风险。

这正好覆盖入口层真正需要的东西：

| 入口层需要 | DS-Bot 提供 | 判断 |
| --- | --- | --- |
| 任何设备可达 | Web UI；Docker 可常驻在 NAS/Linux 服务器；桌面应用可本地运行 | 可用，手机走浏览器，不是原生 App |
| 人格化交互 | 每个 Bot 有名字、角色、instructions、模型、外观；首个 Main Bot 叫 Chief | 可用 |
| 长期记忆 | Bot 私有记忆、群聊记忆、团队共享记忆，均为 Markdown | 可用，但只存摘要与偏好，不复制 Orca 状态 |
| 任务理解与路由 | Main Bot、群聊、`@` 指定成员、Bot 间 `message_bot`、handoff、定时任务 | 可用 |
| 扩展能力 | DSH 插件；Capabilities 支持 MCP server、skill、pack；GitHub connector | 可用，但兼容范围是 DSH 生态 |
| 富交互呈现 | 聊天卡片、表格、进度、选项、确认、短表单；可交互 widget | 可用，适合任务状态与审批 |
| 凭证隔离 | Secrets 卡片、`$DSH_SECRET_*`、出口脱敏、每 Bot 权限预设 | 可用，Docker 版仍需额外收紧网络与挂载 |

“插件兼容更优秀”要限定在 DSH 生态内。DS-Bot 直接使用 DSH 插件、模型、Session、MCP 和 skills；它不是 Hermes 插件宿主。现有 Hermes 插件不能原样搬过来，需要改成 DSH 插件、MCP server 或 skill。

## 不能直接照搬的地方

| 边界 | 事实 | 对架构的影响 |
| --- | --- | --- |
| 没有自带 IM 通道 | DS-Bot 的 Connectors 只有 GitHub；没有 Telegram/微信/Slack 之类入站桥 | 原 Hermes 的 IM 路径不再默认存在；需要另装 DSH IM 插件，DS-Bot 本身不提供公共 IM API |
| 没有手机系统推送 | 现有文档覆盖 Web/Desktop 会话提醒，未提供移动端推送服务 | “异常才打扰”的最终通知通道要另定；不能把 DS-Bot 当推送网关 |
| Docker 版是全权限沙箱 | 镜像设置 `DSH_PERMISSION_MODE=danger-full-access`、approval `never`，容器就是边界 | 只挂载允许 Bot 改的目录；不要把工作站家目录、Docker socket 或生产凭据挂进去 |
| Bot 浏览器只在桌面形态 | Docker/DSH Web 没有 Bot browser 和 `read_browser` | 云端入口层不要依赖浏览器自动化；需要浏览器时仍派给本机 worker |
| 版本早期且绑定 DSH | `0.2.3` 为早期预览；插件文档验证 `DSH 0.2.1-rc.2`，Dockerfile 默认 `DSH 0.2.0-rc.2` | DS-Bot 与 DSH 一起锁版本；升级前先跑通编排链路 |
| 容器默认没有 SSH 客户端 | Dockerfile 安装了 bash、git、curl 等，但没有 `openssh-client` | 要让 DS-Bot 经 SSH 调 Orca，需要自建镜像层或在宿主侧提供受控桥接 |

## IM 接入

DS-Bot 原生只有 Web/Desktop，没有外部 IM 接口。它给浏览器用的 `POST /api/bot` 是内部客户端通道，不是公开 API；外部 IM 要么走 DSH 的 Session/插件层，要么自己写桥接。

DSH 官方核心也不捆绑 IM。官方扩展点是 `ctx.webhookRuntime`，实验包 `@deepseek-ai/dsh-webhook` + `@deepseek-ai/dsh-webhook-github` 只带 GitHub 适配器；它创建普通 Workspace Session，不创建 DS-Bot Bot 或群聊。

社区插件里已有 DS-Bot 专用绑定：

- `@xmanrui/dsh-im` 5.7.0 的“绑定bot”页签把“IM 账号 + 私聊”绑定到 DS-Bot 稳定 Bot ID，再解析到当前 Session。它的 DS-Bot 绑定页覆盖微信、飞书、钉钉、企业微信、QQ、Slack、Telegram、Discord、WhatsApp、iMessage 等私聊渠道。
- 它的 `package.json` 把 DSH `0.2.0-rc.2` / `0.2.1-rc.2` 列入兼容表，`profiles` 只声明 `web`；DS-Bot Docker 默认 `0.2.0-rc.2`，版本线能对上，但仍要实测 DS-Bot 0.2.3 的绑定。
- 绑定只支持私聊，不支持 DS-Bot 群聊、频道、话题或线程。群聊仍用 DS-Bot Web/Desktop。
- 这套绑定通过 DS-Bot 的 `/api/bot` 读取 `state`、回答 `ask_user`，属于版本耦合；插件设计文档写的适配基线是 DS Bot 0.1.7，当前 DS-Bot 是 0.2.3，必须做真实收发、提问和审批回归。
- 主 README 没有把“绑定bot”列为主推功能，按隐藏/实验能力看待，不要假设它和 DS-Bot 新版本永远同步。

其他 DSH IM 网关，例如 `dsh-im-gateway`、`dsh-telegram-channel`、`@addozhang/dsh-discord`，主要绑定 DSH Session，不知道 DS-Bot 的 Bot/群聊语义；适合“手机遥控一个 DSH 会话”，不适合直接复刻 DS-Bot 团队入口。

选择建议：只装一个 IM 网关。要 DS-Bot Bot 私聊，优先试 `@xmanrui/dsh-im`；群聊继续用 DS-Bot Web/Desktop。若必须 IM 群聊，需要自己写桥接或等插件支持。IM 网关等于远程控制入口，只开私聊、配置白名单、使用独立 bot token 和最小权限；不要把它接到 Docker 的全权限入口上还开放群聊。

## 桌面端与服务器

### Linux / Wayland

DS-Bot Desktop 的 Linux 包是 x64 AppImage 和 deb，Electron 版本为 `44.7.0`。从 Electron 38 起，Linux 默认使用 `--ozone-platform=auto`：在 `XDG_SESSION_TYPE=wayland` 的会话里直接走原生 Wayland；DS-Bot 没有强制 X11 的参数。

2026-10-29 在 Hyprland/Wayland、1.5x 分数缩放下实测 DS-Bot `0.2.3` AppImage：窗口正常启动，Chromium 日志明确出现 `ui/ozone/platform/wayland` 和 `wayland_screen.cc`，不是 XWayland。

实际使用注意：

- NixOS 上 AppImage 可能缺 `libfuse.so.2`，用 `--appimage-extract-and-run` 或改装 deb；这是 FUSE 运行时问题，不是 Wayland 兼容问题。
- 我的测试命令带有 `--appimage-extract-and-run --no-sandbox`，仅用于临时目录验证；日常优先用 deb，或给 AppImage 配好 FUSE 2，不要长期关闭 sandbox。
- 托盘依赖桌面环境。GNOME/KDE 需要托盘扩展；没有托盘时，DS-Bot 会把关闭窗口改成询问是否退出，这是应用自己的回退路径。
- 如果遇到某显卡/合成器兼容问题，可以临时用 `--ozone-platform=x11` 退回 XWayland；这条回退路径本次未实测。

### 服务器配置

Grok Bot 和 Muse 是托管型产品，公开材料没有给出可直接照抄的 CPU/RAM 规格。Muse 官方明确说每个用户有一台持久、隔离的 Linux 云电脑，带完整浏览器和存储/CPU/内存；Grok Bot 也是托管的个人 agent。因此“对标”应当对标它们的**每 agent 独立运行环境和浏览器**，而不是猜一个相同大小的 VPS。

DS-Bot 本身没有公布最低系统要求，下面是按 DSH Web、DS-Bot、IM 网关、AgentReach、浏览器和 Orca 接入估算的工程建议，不是官方规格。单容器可以跑完整形态，但 2C4G 不够；4C8G 是下限，4C16G 是更稳的个人档：

| 场景 | vCPU | RAM | 磁盘 | 说明 |
| --- | --- | --- | --- | --- |
| 试用 / 单 Bot | 2 | 4 GB | 40 GB SSD | 只跑 Docker + DSH Web + 1-2 个 Bot，模型走 API |
| 入口 / 1-5 Bot + IM | 4 | 8 GB | 80-160 GB NVMe | 只做入口、IM 和轻量工具；不跑常驻浏览器 |
| **单容器完整档（省钱）** | **4** | **8 GB** | **100-200 GB NVMe** | DS-Bot + IM/邮件 + AgentReach + 一个浏览器；限制并发 |
| **单容器舒适档** | **4-6** | **16 GB** | **200 GB+ NVMe** | 推荐个人长期用；浏览器和 AgentReach 有余量 |
| 多容器 / 高并发 | 8-12 | 32 GB | 500 GB+ NVMe | 3-5 个隔离 agent 或并发浏览器/语音 |
| 本地模型 | 另算 | 另算 | 另算 | 4C8G 不适合跑本地大模型，GPU 规格单独评估 |

单容器内部按进程估算，心里有个账：

| 进程 | 内存预算 | 说明 |
| --- | --- | --- |
| DSH Web + DS-Bot | 2-3 GB | Bot 会话、团队状态、Web UI |
| AgentReach / CloakBrowser | 2-4 GB | 专用 Chromium；并发越高越吃内存 |
| 通用 Playwright/Chromium | 1-3 GB | 按需启动，和 AgentReach 同时跑要留余量 |
| IM/邮件插件 | 1-2 GB | Node 进程、消息缓存、IMAP/SMTP |
| Xvfb/noVNC（登录用） | 0.5-1 GB | 只在需要人工登录/验证码时开 |
| OS + 余量 | 1-2 GB | 避免 OOM 和页面缓存互相挤 |

单容器 4C8G 能跑，但要把 AgentReach/浏览器并发压到 1-2 条，并给 Chromium 配 `shm-size=1g`；4C16G 才是比较舒服的个人长期档。只有同时跑多个 Bot、AgentReach、通用浏览器和语音时，才需要 8C16G 以上。

成本上，云服务器 4C8G/100GB NVMe 通常比 8C16G 便宜一半左右；如果长期 24 小时开，家用 16GB 小主机（N100/N305 或二手 M720q 一类）一次性成本通常低于一年高配云主机，功耗也低。家里网络用 Tailscale 回连即可，不必公网 IP。云主机更适合“必须异地稳定”或家里网络不可靠的情况。

更直接的结论：**入口层不值得为云主机付钱**。DS-Bot Desktop 就跑在要操作的那台电脑上，本地 shell、文件、Bot 浏览器全都在手边，月成本为零。云主机买到的只有“家里断网时仍然在线”，而它恰恰碰不到你的电脑。真正需要 24 小时在线时，家用小主机比云主机便宜一个量级。

常驻宿主已定为接在 AX6000 后面的 N100（单口/双口，16GB），只承担入口，不做路由。校园网认证、多出口与代理仍留在 AX6000；N100 不碰 NAT，断电不影响全屋联网。拓扑与三条硬约束见 [AX6000 校园网路由](ax6000-router.md)。

部署约束：

- 用 x86_64 Linux（Ubuntu 24.04 LTS 或 Debian 12），Docker 24+ / Compose 2.24+；DS-Bot 预构建镜像只发布 `linux/amd64`，ARM NAS 需要自行构建且上游未验证。
- `/data` 和 `/workspace` 放 NVMe，并做快照备份；会话、记忆、附件和工作区都在这里。
- 网络延迟对模型 API 的影响大于带宽；20-50 Mbps 更稳，入口走 Tailscale + HTTPS，不直接暴露 13080。
- 单容器里所有 Bot 共享一个 DSH 进程和网络命名空间，隔离度不等同于 Grok Bot/Muse 的“每 agent 一台云电脑”。这是便利性换来的取舍；只要保持非 root、浏览器独立 profile、无宿主根目录挂载，个人单用户风险可控。
- IM 网关会增加 Node 进程和消息缓存，按 +1-2 GB 预留；`@xmanrui/dsh-im` 的邮箱通道目前是实验功能，走 IMAP/SMTP（出站 993/465/587），不自己搭完整 MTA。
- AgentReach 共用一套专用 Chromium，默认无头、闲置 10 分钟关闭；同一平台最多 2 条、所有平台合计 4 条并发。它必须保留登录态，浏览器 profile 要单独持久化和备份。
- AgentReach 依赖平台风控，云服务器 IP 可能被小红书/Boss 等平台拦截。优先把 AgentReach 放在住宅网络/工作站，或给它配独立出口代理；不要假设 8C16G 的机房 IP 就能稳定跑所有平台。
- AgentReach 的登录会打开浏览器。纯 headless 服务器需要 noVNC/远程桌面让用户本人完成登录或验证码；不要把密码交给 Bot，也不要用自动登录脚本绕过平台验证。
- DS-Bot 自带的 Bot browser 只在 Desktop/桌面应用里，Docker/DSH Web 没有 `read_browser`。服务器上的通用浏览器自动化要单独装 Playwright/Chromium 或 DSH 浏览器插件；可以放在同一个容器里，但不能直接复用 DS-Bot 的 Bot browser。
- 浏览器、邮件和网页内容都是不可信输入。单容器也至少做到：非 root 运行、浏览器独立 profile、无宿主根目录、无 Docker socket；邮件只接受白名单发件人，附件放隔离目录，自动回复要有 Message-ID 去重和循环保护。
- 如果要在服务器上执行代码/终端，把工作目录限制在 `/workspace`，不要挂宿主根目录；破坏性操作仍需显式确认。需要更强隔离时，再把浏览器或 worker 拆出去，不影响入口层设计。

## 它能操控哪台电脑

判断只有一条：**Bot 只能操作它自己进程所在的那台机器、那个容器。** 它没有内置的“远程控制某台电脑”能力。

| 跑在哪 | 能碰到什么 | 能做什么 |
| --- | --- | --- |
| 本机 DS-Bot Desktop | 你这台电脑 | `bash`/`pwsh` 执行命令、读写工作目录、DS-Bot Bot 浏览器（独立 Chromium profile、可导入 Cookie）、浏览器插件 `refs`/`script`/`task`、MCP 与 skill |
| 本机 DSH Web + 插件 | 你这台电脑 | 同上，但没有 Bot browser 和 `read_browser` |
| 服务器 Docker | 那个容器 | 容器内 shell、文件、网络（镜像默认 `danger-full-access` + approval `never`）；没有 Bot browser；**默认碰不到你的电脑** |

所以“在服务器上跑”不会让它能操控你的电脑。要跨机，只有三条明确搭出来的路：

1. **容器 → 本机 SSH**：给容器一把只允许执行薄包装脚本的 key，脚本只暴露“建任务、查状态、读输出、发跟进”四个动作。这是文档里的默认方案。
2. **本机 → 服务器反向调用**：本机跑一个小 MCP server 或 HTTP 桥，经 Tailscale 暴露，服务器上的 Bot 调它。适合家里没有公网入口的情况。
3. **经 Orca 中转**：服务器只写 Run/Dispatch，真正执行始终落在本机 worker，服务器拿不到 shell。

另有一点要说清：DS-Bot 的“操控电脑”是 shell + 文件 + 一个自己的浏览器，不是接管你正在用的桌面。它看不到你的其它窗口，也不会用你已登录的 Chrome，除非你显式导入 Cookie。真要点击原生窗口，得另接 GUI 自动化（`computer-use` 一类），那是另一个扩展。

风险也在这里：Docker 版是全权限、永不询问，一旦把 SSH 通到工作站，网页/邮件里的提示注入就等于在你电脑上执行代码。所以那条通道必须是白名单脚本，不能是裸 shell。

## 接入契约

DS-Bot 只做入口，不替代 Orca：

- **唯一任务账仍是 Orca**：Run、Task、Dispatch、worktree、终端和 worker 生命周期都留在本机 Orca。DS-Bot 只保存 Run ID、Dispatch ID、worktree id 和最近摘要。
- **设备任务仍走 SSH**：DS-Bot 通过薄入口脚本调用本机 `orca` CLI；不把裸 shell 暴露给 Bot，也不让 Bot 直接操作工作站文件。
- **入口侧做信息与通信任务**：搜索、调研、写作、规划、翻译、日程、邮件和 IM 可以由 DS-Bot 直接处理；浏览器 worker 可以做受控网页操作，购买、发送、删除等写动作要显式确认；视频、音乐、游戏、代码、运维等依赖本机设备或文件的任务仍下发 Orca。
- **Chief 是协调者**：一个 Main Bot 负责理解和分派；群聊可以按角色拆成员，但成员之间不能互相替代 Orca 的 Dispatch 监督。
- **卡片是视图**：DS-Bot 的任务卡片、进度和审批读 Orca 的状态，操作经薄入口回写；DS-Bot 不产生第二份任务状态。
- **记忆只存入口侧事实**：用户偏好、称呼、常用项目、最近摘要可以进 DS-Bot 记忆；任务进度、worker 输出和工件位置不进。
- **能力只做加法**：MCP、skill、pack 用来补入口侧能力；不要给入口 Bot 挂载本机 agent 的 API key 或高权限宿主目录。

## 与事件层的关系

DS-Bot 在事件模型里有两种身份，必须分开：

| 身份 | 行为 | 边界 |
|---|---|---|
| **事件源** | 用户在 IM/Web 说的话、DSH 定时任务、插件收到的平台消息 → 转成 `person.*` / `platform.*` 事件提交给 `eventd` | 不直接判断、不直接派发 |
| **呈现面** | 读账的派生视图，回写 ack / defer / confirm | 不产生第二事实源 |

具体的接入点：

- **入账**：DS-Bot 收到的消息经 `POST /e`（tailnet）或 spool 提交，`trust = untrusted`（平台来的）或 `trusted`（本人账号确认的）。它在入口侧**不做规则判断**——判断在 `eventd`，这样手机和桌面看到的是同一套结论。
- **派发**：DS-Bot 不再自己决定"交给 Orca 还是自己办"，而是把事件交出去，由规则决定。这条看起来是让渡权力，实际是消除入口与规则的第二种判断——之前入口侧 "需要设备就下发" 的判据，现在只存在于规则包里。
- **回写**：DS-Bot 的确认卡片、审批按钮对应 `confirm` 动作，回写为该事件的结论（渠道 + 消息 id），不是"点了按钮"。
- **能力上限**：入口 Bot 的 `最高可触发` 是 `revertible`。任何 `irreversible` 动作都必须在工作站侧由人确认，不能在手机上一次点击完成——这条与 [助理系统架构](assistant-system.md) 的信任分级一致。

保留的旧约定不变：Orca 仍是唯一任务账，DS-Bot 不持有本机 agent 的凭证。新增的只是"谁来判断"——判断归账，不归入口。

## 部署形态

先本机，后容器。日常形态就是工作站上的 DS-Bot Desktop：零租金、能直接碰本机 shell 和文件、有 Bot 浏览器，已验证 Wayland 可用。手机要用时，加 Tailscale，再把 DSH Web 绑到 tailnet 或装 `@xmanrui/dsh-im`。只有“电脑关机/断网时也必须在线”才需要第二台机器，而且优先选家里的 16GB 小主机，不是云主机。

确需常驻时，用 Docker 版做单容器入口：

1. 在 NAS、云主机或家用小主机上运行 DS-Bot 容器，加入 Tailscale。
2. 持久卷只放 `/data`、`/workspace` 和浏览器 profile（如 `/home/agent/.agent-reach`）；不要挂宿主根目录、Docker socket 或生产凭据目录。
3. 在同一镜像里补 `openssh-client`、AgentReach、Playwright/Chromium、字体、Xvfb/noVNC；用一个 s6/supervisord 管 DSH 和 noVNC，AgentReach 由 Bot 按需启动；容器用非 root 运行，给 Chromium `shm-size=1g` 和明确的内存/CPU 上限。
4. 装 `@xmanrui/dsh-im` 时同时配 IM 和邮箱：用独立邮箱和授权码/OAuth，不开主邮箱；发件人白名单必填，附件进隔离目录，自动回复按 Message-ID 去重。
5. 需要用户登录平台或过验证码时，开 noVNC/远程桌面；不要让 Bot 持有密码，也不要用脚本绕过平台验证。
6. 用 Tailscale 或反向代理提供 HTTPS，配置 `DSH_TRUSTED_HOST`，首次登录用日志里的 launch token；不要把 13080 直接暴露到公网。
7. 自建镜像时给容器一份只允许调用本机薄入口的 SSH key；SSH 侧仍然只暴露四类动作：创建任务、查询状态、读取输出、发送跟进。
8. 用 `show_view` 或普通 Markdown 卡片展示任务状态；需要手机系统通知时，另接通知桥，不把它塞进 DS-Bot 的职责。

桌面应用适合需要 Bot 浏览器、Cookie 导入和本机窗口的场景；Docker 适合 24 小时在线的入口。两者不要同时写同一份 `~/.dsh` 数据，除非明确接受其中一方只读。

## 迁移步骤

1. **先保留 Hermes**：在 DS-Bot 的编排链路跑通前，不拆旧入口；Orca 和 worker 不受影响。
2. **起 DS-Bot 容器**：按 [Docker 部署](https://github.com/Fei2411/DS-Bot/blob/4a7b550/docker/README.md) 配好数据卷、trusted host 和 HTTPS。
3. **配 Chief**：设置模型、角色、instructions 和团队记忆；先只做问答与任务简报，不接设备操作。
4. **接薄入口**：补 SSH 客户端、密钥和 `orca` 包装脚本，先跑只读命令（`orca orchestration check`、`worker-list`），再跑建 Run 与派发。
5. **切文档与链接**：把仓库里的 Hermes 引用改为 DS-Bot，保留“入口层/编排层/执行层”的职责划分。
6. **留回退**：DS-Bot 的数据与 Orca 分离；出问题时停容器，继续用 Hermes 或直接在本机 Orca 操作。旧入口至少保留一个稳定周期。

## 尚未验证

- 手机浏览器上的长会话、附件上传和 widget 交互体验。
- 从容器内通过 SSH 调 Orca 的完整链路、超时和断线重连。
- IM 插件与 DS-Bot 0.2.3 的实际兼容性，以及移动端系统推送。
- 多用户访问与权限隔离；DS-Bot 当前更像单用户/可信网络工具。
- DS-Bot 升级与 DSH 版本升级的兼容窗口。

## 来源

- [DS-Bot 项目说明](https://github.com/Fei2411/DS-Bot/blob/4a7b550/README.md)
- [DS-Bot 插件文档](https://github.com/Fei2411/DS-Bot/blob/4a7b550/ds-bot/README.md)
- [DS-Bot 设计愿景](https://github.com/Fei2411/DS-Bot/blob/4a7b550/docs/vision.md)
- [DS-Bot Docker 部署](https://github.com/Fei2411/DS-Bot/blob/4a7b550/docker/README.md)
- [DS-Bot 安全模型](https://github.com/Fei2411/DS-Bot/blob/4a7b550/SECURITY_MODEL.md)
- [DS-Bot package.json](https://github.com/Fei2411/DS-Bot/blob/4a7b550/ds-bot/package.json)
- [DS-Bot Linux 桌面说明](https://github.com/Fei2411/DS-Bot/blob/4a7b550/app/README.md)
- [DS-Bot Linux 打包配置](https://github.com/Fei2411/DS-Bot/blob/4a7b550/app/electron-builder.yml)
- [DS-Bot v0.2.3 release](https://github.com/Fei2411/DS-Bot/releases/tag/v0.2.3)
- [AgentReach](https://github.com/Panniantong/Agent-Reach)
- [Electron 44.7.0 breaking changes](https://github.com/electron/electron/blob/v44.7.0/docs/breaking-changes.md)
- [Electron command-line switches](https://github.com/electron/electron/blob/v44.7.0/docs/api/command-line-switches.md)
- [Muse 官方产品页](https://muse.ai/)
- [Grok Bot 官方产品页](https://x.ai/bot)
- [`@xmanrui/dsh-im` 项目说明](https://github.com/xmanrui/dsh-im/blob/e278ac7/README.md)
- [`@xmanrui/dsh-im` package.json](https://github.com/xmanrui/dsh-im/blob/e278ac7/package.json)
- [`@xmanrui/dsh-im` 邮箱协议](https://github.com/xmanrui/dsh-im/blob/e278ac7/docs/agent-mail-protocol.md)
- [`@xmanrui/dsh-im` 的 DS-Bot 绑定方案](https://github.com/xmanrui/dsh-im/blob/e278ac7/docs/%E6%96%B9%E6%A1%88/DSBot%E7%A7%81%E8%81%8A%E7%BB%91%E5%AE%9A%E8%AE%BE%E7%BD%AE%E6%96%B9%E6%A1%88.md)
- [DSH webhook 扩展点](https://github.com/deepseek-ai/deepseek-harness/blob/f3803c96/docs/architecture.md)
- [DSH GitHub webhook 实验包](https://github.com/deepseek-ai/deepseek-harness/blob/f3803c96/docs/user/guide/github-review.md)
- [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)
