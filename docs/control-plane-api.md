# 控制面契约：前端 ↔ `ar`

> 状态：设计中 · 上位文档：[ADR 0009](adr/0009-dsbot-as-control-interface.md)、[ADR 0010](adr/0010-retire-dsbot-native-ui.md) · 关联：[`agent:local` 运行时设计](agent-local-runtime.md)、[多 Agent 运行时](multi-agent-runtime.md)、[Worker 适配器](worker-adapters.md)
>
> 2026-11-06 [ADR 0010](adr/0010-retire-dsbot-native-ui.md) 撤回 ADR 0009：DS-Bot 已移除，客户端改为 DSH 原生会话或任意前端。下文动词表、事件面、卡片语义与状态权威逐条不变；凡写「DS-Bot」处一律读作「客户端」，凡写「DS-Bot 入口」处的部署前提均已失效。
>
> 本文只定义两件事：客户端能用什么命令驱动 `ar`，以及它能看到什么事件。Run 语义（信封、节点树、预算、升级）不在此重复，见 [多 Agent 运行时](multi-agent-runtime.md) 与 [`agent:local` 运行时设计](agent-local-runtime.md)。

## 0. 一句话

**客户端是控制面的调用方，不是控制面。** 它发命令、看事件、回决定，不持有任何 Run 状态。

## 1. 三条通道

| 通道 | 场景 | 实现 | 约束 |
|---|---|---|---|
| 本机直调 | 工作站桌面上的 DS-Bot Desktop | 直接执行 `ar` | 无额外约束，沿用本机权限 |
| 受限入口脚本 | DS-Bot 容器或任意远端 | Tailscale SSH → `%USERPROFILE%\.local\bin\` 下封装脚本 → `ar` | 只暴露 §2 的受控动词子集 |
| 事件订阅 | 任意通道 | `ar watch`（SSE / 长轮询），或直接读 `events.jsonl` | 只读，不改变 Run 状态 |

跨机通道沿用 [系统拓扑 §3](system-topology.md#3-跨机通信通道) 的原则：工作站主动拉取、云端不推送执行请求。

## 2. 命令面（冻结）

已有实现见 `C:\Repos\agent-local-runtime\src\cli.ts`（以原生文件为准）；下表是对外契约，内部子命令可增，本表不轻改。

| 动词 | `ar` 子命令 | 输入 | 输出 | 幂等键 |
|---|---|---|---|---|
| 建 Run | `run-create` | 目标 + `accept` + `budget` + `agent` | `root_id` + 根节点路径 | `ev_id` |
| 加节点 | `node-create` / `spawn` | 父节点 + `spec` 增量 | 节点路径 | `ev_id` |
| 派发 | `dispatch` | evd stdin 任务 JSON | ack | `ev_id` |
| 查 | `check` / `wait` | `root_id` | 节点路径 | 七态返回码 + 一句话摘要 | 只读 |
| 说 | `reply` | 升级/提问 ID + 文本 | ack | 消息 ID |
| 裁决 | `gate` | 闸门 ID + 决定 | ack | 闸门 ID |
| 读 | `events` / `read` | 节点路径 + `since seq` | 事件页 + `result.json` 引用 | 只读 |
| **列** | `list`（新增） | 过滤条件（状态 / `agent` / 时间） | 活 Run 摘要数组 | 只读 |
| **订阅** | `watch`（新增） | `root_id` 或全局 + `since seq` | SSE 帧流 | 只读 |
| 收口 | `done` / `fail` / `abort` | 节点路径 + 摘要 | ack | `ev_id` |
| 分叉 | `fork` | 源节点路径 | 新 `root_id` | `ev_id` |
| 提案 | `propose` | 提案文件 | 应用 / 拒绝 | slug |

**为什么必须加 `list` 与 `watch`**：控制面没有活列表就退化成聊天记录。三个 Run 并行时，一条 append-only 的消息流无法回答「现在有哪些 run 在跑、各自卡在哪」。这两个是控制面成为控制面的最低门槛，不是可选优化。

**受限入口脚本只放五个动词**：`create`、`check`、`read`、`reply`、`list`。`gate` 与 `fork` 需要额外授权，不在默认暴露面内。

## 3. 事件面

`events.jsonl` 的 `kind` 闭集（定义见 `C:\Repos\agent-local-runtime\src\envelope.ts:79`）：

`tool_call` · `tool_execution` · `agent_message` · `file_edit` · `message` · `checkpoint` · `spawn` · `exit` · `gate`

`watch` 的 SSE 帧为 `{seq, kind, data}`，`seq` 单调递增（S21 已实现），断线按 `since seq` 重放，不重复推送。前端**不得**解析 `stdout.log`——那是崩溃排查用的，不是数据面。

**`watch` 是通知面，不是注入面。** 它只把 `events.jsonl` 的增量推给订阅方，不提供向运行中的 Worker 插话的能力：回复仍只有「下一轮生效（`queue`）」与「打断重来（`interrupt`）」两态，真 steer 需要 pi RPC，尚未实现。把 `watch` 做成半个 steer，比不做更贵。

**输出密度由信封决定，不由提示词决定**：

- `spec.delivery = im-brief`：一句话摘要 + 三按钮，供 IM 与卡片面；
- `spec.delivery = doc-full`：结构化全文 + 产物路径，供文档与 PR 交付。

Worker 侧不写「请简洁」，因为那是提示词约束，改不动就无法审计；两档由派发方在 `spec` 里声明。

## 4. 卡片语义与审批

| 卡片 | 触发事件 | 允许动作 | 回传命令 |
|---|---|---|---|
| 进度卡 | `message` / `tool_execution` | 无（只看） | — |
| 审批卡 | `gate` | 允许一次 / 本会话允许 / 拒绝并说明原因 | `gate --decision` |
| 提问卡 | `message(ask)` | 自由文本 | `reply` |
| 完成卡 | `exit` + `result.json` | [执行] [延后] [忽略] | `ev done` |
| 失败卡 | `exit code≠0` / `fail` | [重试] [看日志] [放弃] | `node-create` / `read` / `abort` |

两条硬规则：

- **fail-closed**：`gate` 超时（默认 2 分钟）视为拒绝；UI 不可达时同样视为拒绝，不允许「没回就等于同意」。
- **只在派发点审批**：执行期不设人工闸门。风险在 `spec` 里以 tier（`read` / `write` / `exec`）与 `deny` 路径声明，配置错误的代价是整节点 abort，不是运行中被绕过。这条是为异构 Worker（工具面不可裁剪）付的对价，见 [Worker 适配器 §4](worker-adapters.md)。

## 5. 状态权威

| 对象 | 权威位置 | DS-Bot 的角色 |
|---|---|---|
| Run / 节点状态 | `runs/<root_id>/`（`spec.json` / `result.json` / `events.jsonl` / `index.jsonl`） | 只缓存 `root_id` + 最新摘要行，重连按 `seq` 续读 |
| 对话（conversation） | DS-Bot 自身会话 | 全权持有，**永不下沉到 `runs/`** |
| 任务状态 | Taskwarrior 任务库 | 通过 `ev` 写入，不直接改库 |

**冲突时以 `runs/` 为准**；DS-Bot 的缓存可以整份丢弃，运行目录不能。

## 6. 明确不做

- 不在 DS-Bot 侧维护 Run 树、节点索引或状态机副本。
- 不把 `POST /api/bot` 当通用 webhook 用（[DS-Bot 入口 §3](ds-bot-entry.md#3-即时通讯im接入路径) 已记它并非面向外部的通用接口）。
- 不让 DS-Bot 的角色直接 spawn Worker 进程——派发起源于 `runs/` 上的派发意图，由 `ar daemon` 执行。
- 不在控制面做成本次之外的第二个调度器：ready 集、串行边界、租约都在 `evd`。

**一条红线**：不给 DS-Bot 的任何角色配置直连工作站执行任意命令的通道。它挂了插件、MCP 与 Skill，天然具备自己动手的能力；一旦放开 SSH 直连，「Router 不执行耗时任务」就只剩提示词约定，[Super-agent 机制复核](research/super-agent-dsbot.md) 的全部判定随之失效。强制点只能是受限入口脚本的子命令白名单与规则表 `to`。
