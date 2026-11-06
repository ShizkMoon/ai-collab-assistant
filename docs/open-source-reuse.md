# 开源复用清单

> 选型原则：优先直接复用成熟开源项目；功能接近的通过薄封装接入；仅在无现成方案时才自建（见 [设计原则](principles.md)）。本表记录选型方案，本机实际安装状态以 `upctl` 状态与各专题文档的实测基线为准。

## 1. 基础骨架与运维

| 功能需求 | 选用开源项目 | 说明 |
|---|---|---|
| 任务库与周期调度 | **Taskwarrior 3** | 底层存储为 SQLite（`taskchampion.sqlite3`），原生支持 Hook、UDA、`wait`、`recur` 与多端同步 |
| 智能家居与传感器接入 | **Home Assistant** + Mosquitto + Zigbee2MQTT + ESPHome | 部署方式随常驻节点一并延后（[ADR 0007](adr/0007-deferred-resident-node.md)），配置方案见 [智能家居技术栈](home-automation-stack.md) |
| 米家设备接入 | 小米官方集成 `ha_xiaomi_home` | 接入存量米家设备 |
| 外部 SaaS 与 Webhook 串联 | **n8n** | 提供 IMAP 邮件、RSS、GitHub、飞书等连接器；常驻节点落地后再部署 |
| 系统级定时任务 | **任务计划程序**（任务 XML）+ Taskwarrior `recur` | 无需额外引入调度框架；任务 XML 纳入 `%ProgramData%\aica\tasks\` |
| 任务库增量备份 | **Litestream** + 每小时 `sqlite3 .backup` | 持续复制 SQLite WAL 日志至云服务器 |
| 全量数据备份 | **Restic**（本地 + 云服务器 + 异地加密） | 配合每月 1 日自动恢复演练，见 [系统运维 §9](platform-ops.md#9-备份与恢复演练) |
| 跨设备虚拟局域网 | **Tailscale**（Mesh + Subnet Router + Exit Node + `tailscale serve`） | 免公网 IP 与端口转发，自动签发 HTTPS 证书，见 [网络与设备组网](network-fabric.md) |
| 监控与日志收集 | **Uptime Kuma**、**Prometheus + node_exporter**、**Grafana**、**Loki + Alloy** | 见 [系统运维 §5–§6](platform-ops.md#5-监控与可观测性) |
| 单机 + 云端部署 | PowerShell 安装脚本 + `upctl` | 工作站为执行节点，云服务器只跑等待队列；Windows 侧不再使用 Ansible |
| 桌面配置与快捷键 | **PowerToys** + 导出的 `.reg` / AutoHotkey 脚本 | Windows 无声明式桌面配置，改为「导出配置 + 安装脚本导入」，纳入 `%ProgramData%\aica\managed.list` |

## 2. 交互入口与消息推送

| 功能需求 | 选用开源项目 | 说明 |
|---|---|---|
| 对话与卡片入口 | **DSH 原生会话**（DeepSeek Harness）；多平台群聊配合 **AstrBot** | AstrBot（AGPL-3.0）支持 QQ、企业微信、飞书、钉钉、公众号、Telegram 及 MCP 插件 |
| 手机与桌面互联 | **Phone Link** | 通知同步、短信与通话记录；文件分享仍走 IM 或 Tailscale 直传 |
| 手机消息推送 | **ntfy**（自托管） / Home Assistant Companion | 支持按告警级别设置免打扰穿透 |
| 桌面快捷录入 | **PowerToys Run** 插件 | `Alt+Space` 呼出直接录入任务 |
| 语音识别与合成 | **FunASR / SenseVoice**（语音转写）、**CosyVoice**（语音合成） | 中文识别准确，支持本地离线运行 |

## 3. 模型路由与知识检索

| 功能需求 | 选用开源项目 | 说明 |
|---|---|---|
| 统一模型网关 | **LiteLLM** | 提供 OpenAI 兼容接口，统一管理多后端路由、故障回退与 Token 成本统计 |
| 工作站本地推理 | **vLLM** / **Ollama** | 运行 Qwen 7–14B 与 Embedding 模型 |
| 结构化受限解码 | vLLM `guided_choice` / `guided_json`（XGrammar）、Ollama `format`（GBNF）、`outlines` | 统一封装为 `decide()` 接口，见 [模型路由与本地推理 §6](model-fleet.md#6-受限解码分类接口decidestate-schema) |
| 云端 CPU 兜底分类 | `sentence-transformers` + `bge-small-zh` + **SetFit** | 工作站休眠时在云服务器 CPU 上运行，仅输出预测 `kind` |
| 本地知识检索 | **SQLite FTS5 + `jieba` + `sqlite-vec`**（封装为 `kn` CLI） | 单文件三路混合召回与 RRF 融合，见 [知识库与记忆分层](knowledge-memory.md) |
| Agent 会话历史检索 | **Obelisk**（待验证） | 开源 coding agent session 检索，直接支持 Pi / Claude Code / Codex 会话格式（对话、工具调用、子 agent、工作流），SQLite FTS5 + agent 主动查询；`events.jsonl` 对齐其 schema 即接入，见 [`ar` 控制面 CLI 与运行目录 §4](agent-local-runtime.md#4-数据面唯一新增eventsjsonl) |
| 生成式 UI 产物 | **answer-me-with-html**（待验证） | Agent 写 Markdown 稿（~600 token）→ CLI 算版面/配色/坐标 → 整页自包含 HTML（无 CDN 离线可开，页内评论/决策回流 agent）；支持 Pi/Claude Code/Codex 等 |
| 代码与多步任务编排 | **DSH 内置编排与执行**（会话内领导模式、工作区级 SuperAgent；执行走 subagent / teammate），辅以 `ar` 控制面 CLI（0.1.0，19 个动词）与 `runs/` 信封协议 | 编排由 DSH 会话承担，执行由 subagent / teammate 承担；`ar` 只提供控制面契约与运行目录协议，不做编排也不做执行（[ADR 0011](adr/0011-dsh-orchestration.md)）；交互界面为 DSH 原生会话（[ADR 0010](adr/0010-retire-dsbot-native-ui.md)） |
| 代码与多步任务编排（替代方案，已评估） | **Multica**（`multica-ai/multica`，Multica License / Apache 2.0 + 条件） | 自托管、daemon 发现本机 CLI 注册为 runtime、issue → run → 本地执行，支持 28 个工具（含 Claude Code / Codex / DSH / Pi）。**不采纳为主运行时**：工作单元是 issue（project/git 形状）、run 记录在服务端、无信封级 `accept` 判据，且其 daemon 与 `ar daemon` 会争同一目录（`waiting_local_directory` 目录锁）。可选用法与判据见 [ADR 0009](adr/0009-dsbot-as-control-interface.md) |
| GUI 桌面软件控制 | `CLI-Anything` 封装 → `agent-desktop`（UIA 无障碍树 + ref 语义动作）→ 视觉点击（Jev + AutoHotkey v2 / `SendInput`） | 见 [系统拓扑 §7](system-topology.md#7-gui-自动化分级策略) |
| 外部平台只读抓取 | **`agent-reach`**（已安装） | 聚合 `yt-dlp`、`bili-cli`、`twitter-cli`、`rdt-cli` 等工具 |
| 需要登录态的网页操作 | **ego(lite)** + `ego-browser` Skill | 独立 Chromium，Agent 在隔离 Space 内操作并沿用本机登录态；接口为页面内 JS（Snapshot + `click` / `fill`），不抢用户标签页与焦点，见 [本机工具链选型 §2.8](local-toolchain.md#28-浏览器与网页自动化egolite) |

## 4. 领域能力 Provider

| 领域 | 选用开源或成熟工具 |
|---|---|
| 视频制作 | Remotion、HyperFrames、Multiplane、`ffmpeg`、`auto-editor`、`PySceneDetect`、DaVinci Resolve、Kdenlive（MLT） |
| 音乐与乐谱 | ACE-Step 1.5（Apache-2.0）、REAPER（ReaScript）、MuseScore CLI、LilyPond、FluidSynth |
| 图像与设计 | ComfyUI、ArtCraft `photocraft-cli`、Krita、ImageMagick |
| 信息订阅 | RSSHub + Miniflux / FreshRSS |
| 价格监控 | `changedetection.io` |
| 复式记账与预算 | `double-entry-generator`（支付宝/微信账单转换）+ **Beancount** + **Fava** + `fava-envelope` |
| 间隔重复复习 | **Anki** + AnkiConnect（FSRS 算法） |
| 日历与通讯录 | **Radicale**（CalDAV / CardDAV）+ `vdirsyncer` + `khal` |
| 食谱与采购清单 | **Mealie** |
| 个人媒体库 | **Immich**（照片）/ **Calibre**（电子书）/ **`beets` + Navidrome**（音乐）/ **Jellyfin**（影视） |
| 墨水屏驱动与网关 | **OpenEPaperLink**（电子价签）、**epdiy**（并口裸屏直驱） |
| 状态指示灯 | **WLED** |
| 热敏小票打印 | `python-escpos` |
| 电源与远程唤醒 | **NUT**（Network UPS Tools）、`wakeonlan` |

## 5. 自建胶水层清单

仅以下粘合本机私有流程的轻量模块由自己编写：

| 自建模块 | 自建原因 | 代码规模 |
|---|---|---|
| `ev` CLI + Hook + 派发执行路径 | 将 Taskwarrior UDA 字段与个人路由规则表、`agent:local` 执行器取值、Home Assistant 对接 | 约 700 行 Python，见 [事件运行时与派发 §3](event-runtime.md#3-派发执行路径) |
| `ar` 控制面 CLI（0.1.0，19 个动词） | 只提供运行目录协议与命令面；编排由 DSH 会话承担，执行由 subagent / teammate 承担，`ar` 不承担这两件事 | 0.1.0；对外命令面即控制面契约，见 [控制面契约](control-plane-api.md) 与 [ADR 0011](adr/0011-dsh-orchestration.md) |
| 生成式 UI 工作台（可选旁路） | 消费 `runs/` 运行目录渲染 Run 树、diff 预览与升级卡片；第三方控制面均绑定各自 runtime，无法消费本仓信封协议 | 已按 [ADR 0009](adr/0009-dsbot-as-control-interface.md) 降为可选旁路；[ADR 0010](adr/0010-retire-dsbot-native-ui.md) 撤回 DS-Bot 后交互层回到 DSH 原生会话，工作台仍不恢复为主界面；[ADR 0011](adr/0011-dsh-orchestration.md) 其六已将 workbench 废止，不再列为待建项 |
| 能力与场景 TOML 配置集 | 声明个人使用的能力目录、触发示例与跨设备场景 | 声明式配置文件 + 提示词模板 |
| 显示端 HTML 渲染模板 + **显示仲裁器** | 跨墨水屏、状态灯、桌面组件的动态优先级分配与帧哈希去重 | 渲染模板 + 约 400 行 Python，见 [多端显示仲裁](surface-arbiter.md) |
| `kn` 知识库检索与数据源适配器 | 将 Taskwarrior、`agent:local` 运行目录、学习通（`xxt`）、`biliup` 接入同一个 SQLite + `sqlite-vec` 索引库 | 核心 SQL + 约 600 行适配器，见 [知识库与记忆分层](knowledge-memory.md) |
| 语义缓存、温度缩放校准与 GPU 文件锁 | 针对个人任务反馈样本的轻量级校准与单卡显存互斥锁 | 分别约 40 / 30 / 20 行，见 [模型路由与本地推理 §3–§7](model-fleet.md) |
| PrefixSpan 规则挖掘与影子测试对比器 | 基于 Taskwarrior 历史记录挖掘高频序列并对比新旧 Provider 产物 | 约 150 行 Python + 定时器，见 [系统运维 §1–§4](platform-ops.md) |
| `hc` 健康检查脚本 | 按表执行本地健康检查，实现"连续 2 次失败才推送告警"的防抖逻辑 | 约 120 行 Python |
