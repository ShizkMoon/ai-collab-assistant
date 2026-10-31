# 架构总览

> 状态：设计中（S0 未实现）· 设计取向见 [设计原则](principles.md)：功能优先、开源复用

## 0. 核心流程

**自然语言输入或外部事件触发 → 入口解析意图并匹配 `kind` → 派发器按规则路由给执行器 → 执行器完成后写回一句话执行摘要并通知用户。** 能力、硬件设备与显示端均可按需增删替换。

## 1. 五层架构与三类确认点

| 层级 | 核心职责 | 包含内容 | 演进特征 | 专题文档 |
|---|---|---|---|---|
| **能力层** | 声明系统能处理哪些事务 | 视频制作、配乐生成、长文写作、账单整理、家居场景等 | 开放集合，按需扩充 | [能力目录](capabilities.md) |
| **状态层** | 追踪任务所处阶段 | 九种状态：`new` / `doing` / `waiting` / `blocked` / `escalated` / `failed` / `stalled` / `spec` / `parked` | 封闭状态机 | [事件与任务规格](event-spec.md) |
| **执行层** | 具体调用什么工具完成任务 | Orca Worker、CLI 工具、HA 服务调用、浏览器与 GUI 自动化 | 底层实现可随时替换 | [系统拓扑](system-topology.md)、[本机工具链选型](local-toolchain.md) |
| **设施层** | 算力、网络与硬件运行环境 | 工作站、N100、AX6000、手机、墨水屏、各类传感器 | 物理设备 + NixOS 声明式管理 | [工作站配置](workstation-nixos.md)、[智能家居技术栈](home-automation-stack.md) |
| **知识层** | 检索历史任务与个人文档 | 任务记录、笔记、会话记录、命令历史的混合检索库 | 可从源数据重建 | [知识库与记忆分层](knowledge-memory.md) |

**人工确认点**固定为三类：**付款、删除、对外发布**（[ADR 0002](adr/0002-three-confirmation-points.md)）。其余操作默认直接执行；可逆操作配备默认 5 分钟的撤销窗口，窗口期内可一键回退。

状态机采用九态模型（`new` / `doing` / `waiting` / `blocked` / `escalated` / `failed` / `stalled` / `spec` / `parked`），与 Taskwarrior 字段的具体映射见 [事件与任务规格 §2](event-spec.md#2-任务状态) 和 [事件运行时与派发器 §2](event-runtime.md#2-状态机)。完整闭环设计见 [总体架构设计](architecture-north-star.md)。

## 2. 意图分类与结构化路由

```
自然语言输入 ──[入口 Agent：意图分类]──> kind + 参数 ──> 状态流转 ──> 执行器 ──> 执行摘要 ──[出口：自然语言回复]──> 用户
机器事件（HA / 定时 / CI / Webhook）────> kind + 参数（直接映射，不经语言模型）
```

- **受限意图分类**：入口 Agent 从 [能力目录](capabilities.md) 的候选集中选择匹配的 `kind`，提取结构化参数并输出置信度。高置信度直接派发执行，中等置信度向用户追问确认，低置信度归入待分类队列（`meta.triage.pending`）。
- **统一分类接口** `decide(state, schema) → {字段: 概率}`，底层推理后端可按需切换：
  - 工作站 GPU：本地常驻 7–9B 模型（vLLM / Ollama）配合受限解码（XGrammar / GBNF）；
  - N100 CPU：中文小型 Embedding 模型 + SetFit 少样本分类器，在工作站休眠或离线时提供兜底分类；
  - 云端 API：DeepSeek / Qwen，处理长上下文或复杂长尾输入。
  - 三类后端统一通过 [LiteLLM](open-source-reuse.md#3-模型与推理) 网关调用，由网关管理路由与故障回退。
- **任务记录即训练样本**：用户每次在卡片上确认或修正分类结果，都会作为带标签样本存入本地库，用于定期更新分类器与置信度阈值。
- **调用开销**：机器事件按确定性规则直接映射，不调用模型；自然语言输入每条仅在入口分类一次，主要算力消耗集中在后续 Worker 执行阶段。

## 3. 状态存储：复用 Taskwarrior 与 Home Assistant

| 数据类别 | 存储组件 | 选型原因 |
|---|---|---|
| 任务状态与生命周期 | **Taskwarrior 3**（`taskchampion.sqlite3`） | 原生支持延迟唤醒（`wait`）、截止时间（`due`）、周期任务（`recur`）、注解、自定义字段（UDA）、Hook 与多端同步 |
| 传感器高频状态与原始事件 | **Home Assistant Recorder** | 温湿度、功率等高频时序数据留在 HA，仅需跟进处理的事件才转化为 Taskwarrior 任务 |
| Agent 执行上下文与过程 | **Orca**（Run / Task） | 管理 Worker 的代码分支、终端会话与中间产物 |

核心自建组件是一个轻量级**派发器（`evd`）**：Taskwarrior Hook 仅负责将变更事件追加写入本地 Spool 目录（耗时 < 5ms，异常直接放行），由常驻守护进程异步读取并按规则表派发给对应执行器。详细字段定义见 [事件与任务规格](event-spec.md)，运行机制见 [事件运行时与派发器](event-runtime.md)。

## 4. 规则表：按序匹配的路由配置

```toml
[[rule]]
name  = "video.make"
order = 50
match = { kind = "work.video.*" }
to    = "agent:orca"         # 派发给 Orca Worker

[[rule]]
name  = "home.device"
order = 20
match = { kind = "home.action.*" }
to    = "ha:script"          # 直接调用 Home Assistant 脚本

[[rule]]
name  = "critical.push"
order = 10
match = { severity = "critical" }
to    = "me"
push  = { channel = ["ntfy:critical"], bypass_dnd = true }
stop  = true

[[rule]]
name  = "doc.renew"
order = 60
match = { kind = "life.doc.renew" }
to    = "notify"             # 到期提醒
```

规则按 `order` 升序匹配，首个命中即生效；未命中任何规则的任务归入待分类队列（`meta.triage.pending`），在每日早报中汇总提示。规则同时支持 `aggregate`（聚合）、`cooldown`（冷却时间）、`rate`（频率限制）与 `window`（执行时间窗）四类流量控制，完整语法见 [事件运行时与派发器 §1](event-runtime.md#1-规则表)。

设备级本地闭环与安全兜底逻辑直接使用 **Home Assistant Automation** 实现，不在派发器规则表中重复维护。

## 5. 执行器列表

| 执行器标识 | 适用场景 | 底层复用工具 |
|---|---|---|
| `agent:orca` | 多步复杂任务：代码开发、文档编写、视频剪辑、长文写作 | Orca + Devin / Codex / Claude Code Worker |
| `ha:*` | 智能家居设备控制、HA 脚本调用 | Home Assistant REST / 服务调用 |
| `cli:*` | 单次确定性命令执行 | 现成 CLI 工具（`ffmpeg`、`calibre`、`double-entry-generator` 等） |
| `n8n:*` | 外部 SaaS 与 Webhook 编排 | n8n 工作流（Webhook、IMAP 邮件、RSS） |
| `notify` | 纯消息提醒 | ntfy / KDE Connect / IM |
| `me` | 需人工确认或亲自处理的事项 | 交互卡片：`[执行] [延后] [忽略]` |
| `render` | 触发显示端画面刷新 | [多端显示仲裁](surface-arbiter.md) |
| `orca:run` | 带任务说明模板的长期异步任务 | Orca Run，返回产物路径与执行摘要 |

各执行器统一输出七种返回状态：`done`、`waiting`、`me`、`blocked`、`failed`、`split`、`spec`，由派发器映射为任务库中的九种状态。耗时任务采用异步投递加租约机制，不阻塞派发器主循环。

## 6. 显示端分配

所有显示端展示的内容均从任务库与 Home Assistant 状态只读派生：

| 显示端 | 展示内容 | 底层实现 |
|---|---|---|
| 状态指示灯 | 熄灭=无待办，琥珀色=有待确认事项，红色=高优告警或故障 | WLED |
| 墨水屏（门口 / 桌面 / 床头） | 出门清单 / 今日待办 / 明日首项任务 | OpenEPaperLink / LilyGo T5，见 [统一渲染管线](render-pipeline.md) |
| Plasma 桌面组件、KRunner | 待处理任务计数、快捷录入任务 | KDE Plasma、`plasma-manager` |
| ThinkSmart View | 桌面触控面板与语音入口 | HA Dashboard / Kiosk 浏览器，见 [桌面主控台](thinksmart-view-console.md) |
| 手机 / 手表 | 待确认计数与即时推送 | KDE Connect、ntfy、HA Companion |
| IM 客户端 | 交互确认卡片、每日早报与晚报 | DS-Bot / AstrBot |
| 热敏打印机 | 纸质当日清单、采购清单 | `python-escpos` |

**首屏原则**：任何显示端的第一屏只展示当前亟需处理的事项。

各显示端展示的具体内容由 [显示仲裁器](surface-arbiter.md) 根据优先级、新鲜度、独占组与每日刷新预算动态分配。

## 7. 知识检索与周期复盘

- **知识检索**：通过 `info.recall`（底层 CLI 为 `kn`）检索任务记录、笔记、历史会话与命令历史，数据统一存储在 `~/knowledge/kb.sqlite`（SQLite FTS5 + jieba 分词 + `sqlite-vec` 向量索引）。具体实现见 [知识库与记忆分层](knowledge-memory.md)。
- **周报统计**：汇总本周完成任务、耗时分布、高频重复事项（作为新规则或新能力的提案线索）以及各能力的返工次数。
- **年度总结**：年末基于全年任务记录与创作产物自动汇总生成。

## 8. 通知模式

系统提供工作、生活、专注、勿扰、外出、出差六种通知模式，并与 KDE Plasma Activities 双向联动。通知模式仅调整推送的时机与渠道，详见 [Personal Agent 设计](personal-agent.md)。

## 9. 实施阶段

实施顺序见 [总体架构设计 §13](architecture-north-star.md#13-实施阶段)，历史版本见 [路线图](roadmap.md)。
