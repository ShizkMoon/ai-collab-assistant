# DS-Bot 入口

> 状态：选型已定，未部署 · 角色：入口和出口（见 [架构总览 §2](architecture.md)）
>
> 结论：入口从 Hermes 换成 DS-Bot。DS-Bot 负责**听懂你的话**（从 [能力目录](capabilities.md) 里选出 `kind` 并入账）和**把结果说清楚**；任务执行仍由 Orca 管理。需要接入更多 IM 平台（特别是群聊）时，加上 AstrBot。
>
> 核对基线：2026-10-28，DS-Bot `main` 提交 `4a7b550`，`ds-bot` 包版本 `0.2.3`；插件文档验证的是 DSH `0.2.1-rc.2`，Dockerfile 默认用 DSH `0.2.0-rc.2`。目前是早期预览版。

## 1. 它是什么

DS-Bot 是 [DeepSeek Harness（DSH）](https://github.com/deepseek-ai/deepseek-harness) 的 Bot 团队插件，运行在 DSH Web / Desktop 里，也有 Docker 版。它是 Apache-2.0 许可的社区项目，不是 DeepSeek 官方产品。

| 入口需要 | DS-Bot 提供 |
| --- | --- |
| 任何设备都能用 | Web UI（手机用浏览器）、Docker 常驻、桌面应用 |
| 人格化交互 | 每个 Bot 有名字、角色、instructions、模型；主 Bot 叫 Chief |
| 长期记忆 | Bot 私有记忆、群聊记忆、团队共享记忆（Markdown） |
| 理解和分派 | Main Bot、群聊、`@` 成员、`message_bot`、handoff、定时任务 |
| 扩展 | DSH 插件，以及 MCP server、skill、pack、GitHub connector |
| 卡片交互 | 卡片、表格、进度、选项、确认、短表单、widget |

现有的 Hermes 插件不能直接搬过来，要改写成 DSH 插件、MCP 或 skill。

## 2. 它缺的部分，以及用什么补

| 缺口 | 补法（复用优先） |
| --- | --- |
| 没有自带 IM 通道 | 私聊用 `@xmanrui/dsh-im`；群聊和更多平台用 **AstrBot**（QQ、企业微信、飞书、钉钉、公众号、Telegram） |
| 没有手机系统推送 | ntfy / KDE Connect / HA companion |
| Docker 版里没有 Bot 浏览器 | 需要浏览器的任务派给本机 worker |
| 容器里没有 SSH 客户端 | 自建镜像层补上 `openssh-client` |
| 版本早期，绑定 DSH | DS-Bot 和 DSH 一起锁定版本，升级前先跑一遍入口链路 |

## 3. IM 接入

- DS-Bot 原生只有 Web / Desktop。`POST /api/bot` 是内部通道，不是公开 API。
- `@xmanrui/dsh-im` 5.7.0 的"绑定bot"页可以把 IM 私聊绑到 DS-Bot 的 Bot 上，覆盖微信、飞书、钉钉、企业微信、QQ、Slack 等。但它只支持私聊，而且和 DS-Bot 版本强绑定，属于实验能力，需要实测。
- 其他 DSH IM 网关（`dsh-im-gateway`、`dsh-telegram-channel`、`@addozhang/dsh-discord`）只能绑 DSH Session，不理解 DS-Bot 的 Bot 语义。
- **建议**：私聊先试 `@xmanrui/dsh-im`；需要群聊或更多平台时，在 N100 上加一个 AstrBot，让它直接调用 `ev add` 和 Orca 薄入口，不必自己写桥接。

## 4. 桌面端

### Linux / Wayland（以 Hyprland 实测；Plasma 6 同样是 Wayland 会话）

DS-Bot Desktop 的 Linux 包是 x64 AppImage 和 deb，Electron 版本为 `44.7.0`。从 Electron 38 起，Linux 默认使用 `--ozone-platform=auto`：在 `XDG_SESSION_TYPE=wayland` 的会话里直接走原生 Wayland；DS-Bot 没有强制 X11 的参数。

2026-10-29 在 Hyprland/Wayland、1.5x 分数缩放下实测 DS-Bot `0.2.3` AppImage：窗口正常启动，Chromium 日志明确出现 `ui/ozone/platform/wayland` 和 `wayland_screen.cc`，不是 XWayland。

实际使用注意：

- NixOS 上 AppImage 可能缺 `libfuse.so.2`，用 `--appimage-extract-and-run` 或改装 deb；这是 FUSE 运行时问题，不是 Wayland 兼容问题。
- 我的测试命令带有 `--appimage-extract-and-run --no-sandbox`，仅用于临时目录验证；日常优先用 deb，或给 AppImage 配好 FUSE 2，不要长期关闭 sandbox。
- 托盘依赖桌面环境。GNOME/KDE 需要托盘扩展；没有托盘时，DS-Bot 会把关闭窗口改成询问是否退出，这是应用自己的回退路径。
- 如果遇到某显卡/合成器兼容问题，可以临时用 `--ozone-platform=x11` 退回 XWayland；这条回退路径本次未实测。

- 在 Plasma 下，托盘由系统自带支持。

## 5. 部署

常驻宿主定为接在 AX6000 后面的 **N100**（16GB），只承担入口，不做路由。DS-Bot 本身没有公布系统要求；按 DSH Web + DS-Bot + IM 网关 + AgentReach + 一个浏览器估算，**4C8G 能跑，16GB 比较舒服**。不需要买云主机。

- 在 N100 的 NixOS 上用 `virtualisation.oci-containers` 运行 DS-Bot 容器（只发布了 `linux/amd64` 镜像），并加入 Tailscale。
- 持久化 `/data`、`/workspace` 和浏览器 profile；HTTPS 通过 Tailscale 提供，配置 `DSH_TRUSTED_HOST`，不要把 13080 端口直接暴露出去。
- AgentReach 共用一个 Chromium（`shm-size=1g`），登录态要持久化。遇到平台登录或验证码时，用 noVNC 由你本人完成。
- 日常在电脑前也可以直接用 DS-Bot Desktop，它能直接操作本机 shell、文件和 Bot 浏览器。Desktop 和 Docker 不要同时写同一份 `~/.dsh`。

## 6. 它能操控哪台电脑

**Bot 只能操作自己进程所在的那台机器或那个容器。** 要跨机器，走已经定好的路线：容器通过 SSH 调用本机的薄入口脚本（创建任务、查状态、读输出、发跟进四个动作），由它调用 `orca` CLI，真正的执行落在本机 worker 上。

## 7. 和账的接法

| 动作 | 做法 |
| --- | --- |
| 入账 | 你说的话 → Chief 从能力目录里选出 `kind` → `ev add`（置信度中等时先问你一句） |
| 派发 | 由规则表决定；`agent:orca` 类走 SSH 薄入口 |
| 回报 | Orca 完成后调用 `ev done`，DS-Bot 读到后用一句话回报，配卡片 `[做] [晚点] [不要]` |
| 记忆 | DS-Bot 只存偏好、称呼、常用项目和最近摘要，任务进度以账和 Orca 为准 |

## 8. 迁移步骤

1. 在 DS-Bot 链路跑通之前保留 Hermes。
2. 在 N100 上启动 DS-Bot 容器，配置数据卷、trusted host 和 HTTPS。
3. 配置 Chief：模型（经 LiteLLM）、角色和能力目录提示词。先只做问答和入账。
4. 接上薄入口：先跑只读命令（`orca orchestration check`、`worker-list`），再跑建 Run 和派发。
5. 需要时再加 IM（`@xmanrui/dsh-im` 或 AstrBot）。
6. 出问题就停掉容器，退回 Hermes 或直接在本机用 Orca。

## 9. 还没验证的

- 手机浏览器上的长会话、附件上传和 widget 体验。
- 从容器通过 SSH 调用 Orca 的完整链路。
- IM 插件与 DS-Bot 0.2.3 的实际兼容性；AstrBot 与 DS-Bot 并用时由谁回复。
- DS-Bot 和 DSH 升级的兼容窗口。

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
- [AstrBot](https://github.com/AstrBotDevs/AstrBot)
