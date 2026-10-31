# DS-Bot 入口部署与接入

> 状态：选型已定，待部署 · 角色：常驻对话入口与结果通知出口（见 [架构总览 §2](architecture.md#2-意图分类与结构化路由)）
>
> 选型结论：采用 DS-Bot 替代早期规划的 Hermes 作为常驻入口。DS-Bot 负责**解析自然语言意图**（从 [能力目录](capabilities.md) 匹配 `kind` 并录入任务库）以及**向用户反馈执行结果与交互卡片**；底层重度任务仍由工作站上的 Orca 编排执行。需要接入更多即时通讯平台（尤其是群聊）时，配合部署 AstrBot。
>
> 版本核对基线（2026-10-28）：DS-Bot `main` 分支提交 `4a7b550`，`ds-bot` 包版本 `0.2.3`，配套 DeepSeek Harness（DSH）版本 `0.2.0-rc.2` / `0.2.1-rc.2`。

## 1. 组件功能定位

DS-Bot 是运行在 [DeepSeek Harness（DSH）](https://github.com/deepseek-ai/deepseek-harness) Web / Desktop 及容器环境中的多角色插件（Apache-2.0 开源许可，社区维护项目）。

| 入口需求 | DS-Bot 对应能力 |
| --- | --- |
| 多端随时访问 | 提供响应式 Web UI（手机浏览器可直接访问）、Docker 容器化常驻与 Linux 桌面客户端 |
| 角色与提示词配置 | 支持配置多个独立角色（主入口角色为 Chief），各自绑定提示词与模型 |
| 会话记忆 | 内置私有记忆、群组记忆与共享 Markdown 记忆文件 |
| 意图路由与协作 | 支持主 Bot 分发、`@` 提及调用、`message_bot` 转发、Handoff 交接与定时任务 |
| 能力扩展 | 支持挂载 DSH 插件、MCP Server、Skill 与 GitHub Connector |
| 结构化交互卡片 | 原生支持确认按钮、选项列表、进度条、表格与短表单卡片 |

## 2. 功能缺口与配套补充方案

| 存在缺口 | 补充方案（优先复用现成组件） |
| --- | --- |
| 原生仅提供 Web / Desktop 界面，无内置 IM 通道 | 私聊接入 `@xmanrui/dsh-im` 插件；群聊与更多平台（QQ、飞书、企业微信、Telegram 等）配合部署 **AstrBot** |
| 无原生移动端系统级推送 | 接入自托管 **ntfy**、KDE Connect 与 Home Assistant Companion |
| Docker 容器版不含本地桌面浏览器 | 需要操控桌面浏览器的任务直接派发给工作站本地 Worker 执行 |
| 官方基础镜像未预装 SSH 客户端 | 在自定义容器镜像层中安装 `openssh-client` |
| 处于早期迭代期，与 DSH 版本强耦合 | 在 NixOS 配置中同时锁定 DS-Bot 与 DSH 镜像标签，升级前先在测试环境验证入口链路 |

## 3. 即时通讯（IM）接入路径

- DS-Bot 原生提供 Web 与 Desktop 界面，内部接口 `POST /api/bot` 并非面向外部平台的通用 Webhook。
- `@xmanrui/dsh-im`（v5.7.0）支持将微信、飞书、钉钉、企业微信、QQ、Slack 等平台的**私聊会话**绑定至 DS-Bot 的指定角色上，但不支持群聊，且与 DS-Bot 版本绑定较紧，部署时需实测验证。
- 其他通用 DSH IM 网关（如 `dsh-im-gateway`、`dsh-telegram-channel`、`@addozhang/dsh-discord`）仅能绑定普通 DSH Session，无法直接映射 DS-Bot 的多角色语义。
- **实施方案**：私聊优先测试 `@xmanrui/dsh-im`；需要群聊或更稳定的多平台接入时，在 N100 上并行部署 AstrBot，让 AstrBot 直接调用 `ev add` 与工作站受限入口脚本。

## 4. Linux 桌面端实测（Wayland）

DS-Bot Desktop 提供 Linux `x86_64` AppImage 与 `.deb` 软件包，内置 Electron 版本为 `44.7.0`。自 Electron 38 起，Linux 下默认启用 `--ozone-platform=auto`，在 `XDG_SESSION_TYPE=wayland` 会话（Hyprland 或 KDE Plasma 6 Wayland）中默认使用原生 Wayland 渲染。

2026-10-29 本机 Wayland（1.5x 分数缩放）实测 DS-Bot `0.2.3` AppImage：窗口正常启动，Chromium 日志确认运行于 `ui/ozone/platform/wayland` 原生模式。

NixOS 环境使用注意事项：

- NixOS 下直接运行 AppImage 可能缺少 `libfuse.so.2`，可通过 `--appimage-extract-and-run` 启动、配置 `programs.appimage.enable = true` 或直接解包 `.deb` 运行；日常使用不要长期添加 `--no-sandbox` 参数。
- 系统托盘：KDE Plasma 6 原生支持 StatusNotifierItem 托盘图标；在无托盘扩展的窗口管理器下，关闭窗口会自动退化为弹窗询问是否退出进程。
- 若遇到特定显卡驱动下的 Wayland 渲染异常，可添加 `--ozone-platform=x11` 临时回退至 XWayland。

## 5. N100 容器化常驻部署

常驻入口部署在 AX6000 局域网下的 **N100 迷你主机**（16GB 内存）上。DSH Web + DS-Bot + IM 网关 + `agent-reach` + 无头 Chromium 合计常驻内存约 2–4GB，16GB 内存留有充足余量。

- 在 N100 的 NixOS 配置中通过 `virtualisation.oci-containers` 运行 DS-Bot 容器（官方提供 `linux/amd64` 镜像），并将主机接入 Tailscale。
- 持久化挂载 `/data`、`/workspace` 与浏览器 Profile 目录；通过 `tailscale serve` 提供 HTTPS 访问并配置 `DSH_TRUSTED_HOST`，不向局域网或公网裸露 `13080` 端口。
- `agent-reach` 共用容器内的 Chromium 实例（配置 `--shm-size=1g`）并持久化 Cookie；首次扫码登录或触发验证码时通过局域网 noVNC 手动完成。
- 在工作站桌面使用 DS-Bot Desktop 时，避免与 N100 容器同时读写同一份 `~/.dsh` 目录。

## 6. 跨机调用工作站边界

DS-Bot 容器仅能直接操作容器自身环境。当任务需要工作站算力或本地文件时，容器通过 Tailscale SSH 调用工作站 `~/.local/bin/` 下的受限入口脚本（仅开放创建任务、查询状态、读取输出、发送跟进四项子命令），由该脚本调用工作站本机 `orca` CLI 派发 Worker。

## 7. 与任务库和知识库的对接

| 交互环节 | 对接方式 |
| --- | --- |
| 任务录入 | 用户发送消息 → Chief 角色从能力目录匹配 `kind` → 调用 `ev add`（置信度中等时先发卡片追问） |
| 任务派发 | 由工作站派发器 `evd` 按规则表路由；`agent:orca` 类任务通过受限入口脚本建 Run 派发 |
| 结果通知 | Orca Worker 完成后调用 `ev done`，DS-Bot 读取一句话执行摘要并推送交互卡片 `[执行] [延后] [忽略]` |
| 记忆协同 | DS-Bot 本地仅保留称呼、活跃项目与近期会话摘要；跨周期的偏好与历史做法统一通过 `kn recall` 检索工作站上的 `~/knowledge/kb.sqlite`（见 [知识库与记忆分层 §7](knowledge-memory.md#7-记忆分层与生命周期)），避免维护两套独立的长期记忆源 |

## 8. 部署与切换步骤

1. 在 N100 上启动 DS-Bot 容器，完成持久化卷挂载、`DSH_TRUSTED_HOST` 与 Tailscale HTTPS 配置。
2. 配置主入口角色 Chief：接入 LiteLLM 网关，加载能力目录提示词，先验证纯问答与 `ev add` 任务录入。
3. 配置容器至工作站的受限 SSH 密钥与入口脚本：先验证只读查询（`orca orchestration check`、`worker-list`），再验证创建 Run 与派发 Worker。
4. 按需接入 IM 插件（`@xmanrui/dsh-im` 或 AstrBot）。
5. 若容器或插件升级出现兼容问题，可随时停止容器并回退至工作站本地直接调用 Orca CLI。

## 9. 待实测验证项

- 手机浏览器访问 DS-Bot Web 时的长连接稳定性、附件上传与交互卡片体验。
- N100 容器经 Tailscale SSH 调用工作站 Orca CLI 的端到端延迟与断线重连表现。
- `@xmanrui/dsh-im` 与 DS-Bot `0.2.3` 的实际兼容性，以及 AstrBot 与 DS-Bot 并行时的消息路由分工。

## 参考资料

- [DS-Bot 仓库 README](https://github.com/Fei2411/DS-Bot/blob/4a7b550/README.md) · [插件说明](https://github.com/Fei2411/DS-Bot/blob/4a7b550/ds-bot/README.md) · [设计文档](https://github.com/Fei2411/DS-Bot/blob/4a7b550/docs/vision.md)
- [DS-Bot Docker 部署指南](https://github.com/Fei2411/DS-Bot/blob/4a7b550/docker/README.md) · [安全模型说明](https://github.com/Fei2411/DS-Bot/blob/4a7b550/SECURITY_MODEL.md)
- [DS-Bot Linux 桌面端说明](https://github.com/Fei2411/DS-Bot/blob/4a7b550/app/README.md) · [v0.2.3 Release](https://github.com/Fei2411/DS-Bot/releases/tag/v0.2.3)
- [DeepSeek Harness (DSH)](https://github.com/deepseek-ai/deepseek-harness) · [DSH 架构文档](https://github.com/deepseek-ai/deepseek-harness/blob/f3803c96/docs/architecture.md)
- [`@xmanrui/dsh-im` 仓库](https://github.com/xmanrui/dsh-im/blob/e278ac7/README.md) · [DS-Bot 私聊绑定方案](https://github.com/xmanrui/dsh-im/blob/e278ac7/docs/%E6%96%B9%E6%A1%88/DSBot%E7%A7%81%E8%81%8A%E7%BB%91%E5%AE%9A%E8%AE%BE%E7%BD%AE%E6%96%B9%E6%A1%88.md)
- [AstrBot](https://github.com/AstrBotDevs/AstrBot) · [Agent-Reach](https://github.com/Panniantong/Agent-Reach)
- [Electron 44.7.0 命令行参数文档](https://github.com/electron/electron/blob/v44.7.0/docs/api/command-line-switches.md)
