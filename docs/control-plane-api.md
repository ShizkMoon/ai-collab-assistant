# 控制面契约：客户端 ↔ `ar`

> 状态：设计中、未部署 · 关联：[`ar` 控制面 CLI 与运行目录](agent-local-runtime.md)、[多 Agent 运行时](multi-agent-runtime.md)、[Worker 适配器](worker-adapters.md)
>
> 2026-11-06 交互层回到 DSH 原生会话，客户端是 DSH 会话或手机端。下文动词表、事件面、卡片语义与状态权威逐条不变。
>
> 本文只定义两件事：客户端能用什么命令驱动 `ar`，以及它能看到什么事件。Run 语义（信封、节点树、预算、升级）不在此重复，见 [多 Agent 运行时](multi-agent-runtime.md) 与 [`ar` 控制面 CLI 与运行目录](agent-local-runtime.md)。

## 0. 一句话

**客户端是控制面的调用方，不是控制面。** 它发命令、看事件、回决定，不持有任何 Run 状态。命令面只到 `ar`，执行落在 DSH subagent / teammate。

## 1. 三条通道

| 通道 | 场景 | 实现 | 约束 |
|---|---|---|---|
| 本机直调 | 工作站上的 DSH 会话 | 直接执行 `ar` | 无额外约束，沿用本机权限 |
| 受限入口脚本 | 手机端或任意远端 | Tailscale SSH → `%USERPROFILE%\.local\bin\` 下封装脚本 → `ar` | 只暴露 §2 的受控动词子集 |
| 事件订阅 | 任意通道 | `ar events` 按 `since seq` 取页，或直接读 `events.jsonl` | 只读，不改变 Run 状态 |

跨机通道沿用 [系统拓扑 §3](system-topology.md#3-跨机通信通道) 的原则：工作站主动拉取、云端不推送执行请求。

## 2. 命令面（冻结）

已有实现见 `C:\Repos\agent-local-runtime\src\cli.ts`（以原生文件为准）；下表是对外契约，内部子命令可增，本表不轻改。`ar` 0.1.0 共 19 个动词。

| 动词 | `ar` 子命令 | 输入 | 输出 | 幂等键 | 状态 |
|---|---|---|---|---|---|
| 建 Run | `run-create` | 目标 + `accept` + `budget` + `agent` | `root_id` + 根节点路径 | `ev_id` | 命令已存在 |
| 加节点 | `node-create` / `spawn` | 父节点 + `spec` 增量 | 节点路径 | `ev_id` | 命令已存在 |
| 派发 | `dispatch` | 任务引用（命令面） | ack | `ev_id` | 命令已存在 · 参数语义设计中 |
| 查 | `check` / `wait` | `root_id` | 七态返回码 + 一句话摘要 | 只读 | 命令已存在 |
| 续跑 | `resume` | 节点路径 | ack | `ev_id` | 命令已存在 |
| 说 | `reply` | 升级/提问 ID + 文本 | ack | 消息 ID | 命令已存在 |
| 裁决 | `gate` | 闸门 ID + 决定 | ack | 闸门 ID | 命令已存在 |
| 读 | `event` / `events` | 节点路径 + `since seq` | 事件页 + `result.json` 引用 | 只读 | 命令已存在 |
| 收口 | `done` / `fail` / `abort` | 节点路径 + 摘要 | ack | `ev_id` | 命令已存在 |
| 分叉 | `fork` | 源节点路径 | 新 `root_id` | `ev_id` | 命令已存在 |
| 提案 | `propose` | 提案文件 | 应用 / 拒绝 | slug | 命令已存在 |
| 列 | `list` | 过滤条件（状态 / `agent` / 时间） | 活 Run 摘要数组 | 只读 | 计划中 · 设计中，未实现 |
| 订阅 | `watch` | `root_id` 或全局 + `since seq` | SSE 帧流 | 只读 | 计划中 · 设计中，未实现 |
| 内部 | `cmd` / `daemon` / `version` | 内部实现 | — | 不进契约 | 命令已存在 |

> 状态列含义：**命令已存在**指 `ar` 0.1.0 有该子命令（`ar --help` 可见）；运行目录协议与事件面设计中、未部署，整条链路尚未在实机跑通。

**`list` 与 `watch` 是契约里保留的动词**：`list` 列任务，`watch` 订阅事件。当前 `ar` 0.1.0 尚未实现这两个动词，客户端只能用 `check` 与 `events`（按 `since seq` 分页）轮询；实现后由这两个动词提供列任务与订阅事件的入口。

**受限入口脚本只放四个动词**：`run-create`、`check`、`event` / `events`、`reply`。`gate` 与 `fork` 需要额外授权，不在默认暴露面内。

## 3. 事件面

`events.jsonl` 的 `kind` 闭集（定义见 `C:\Repos\agent-local-runtime\src\envelope.ts:79`）：

`tool_call` · `tool_execution` · `agent_message` · `file_edit` · `message` · `checkpoint` · `spawn` · `exit` · `gate`

事件页为 `{seq, kind, data}`，`seq` 单调递增（设计约束；事件面整体未部署），断线按 `since seq` 重放，不重复推送。客户端**不得**解析 `stdout.log`——那是崩溃排查用的，不是数据面。

**事件面是通知面，不是注入面。** 它只把 `events.jsonl` 的增量交给订阅方，不提供向运行中的执行单元插话的能力：回复仍只有「下一轮生效（`queue`）」与「打断重来（`interrupt`）」两态，真 steer 需要 pi RPC，尚未实现。把事件面做成半个 steer，比不做更贵。

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
| 失败卡 | `exit code≠0` / `fail` | [重试] [看日志] [放弃] | `node-create` / `events` / `abort` |

两条硬规则：

- **fail-closed**：`gate` 超时（默认 2 分钟）视为拒绝；客户端不可达时同样视为拒绝，不允许「没回就等于同意」。
- **只在派发点审批**：执行期不设人工闸门。风险在 `spec` 里以 tier（`read` / `write` / `exec`）与 `deny` 路径声明，配置错误的代价是整节点 abort，不是运行中被绕过。这条是为异构执行单元（工具面不可裁剪）付的对价，见 [Worker 适配器 §4](worker-adapters.md)。

## 5. 状态权威

| 对象 | 权威位置 | 客户端（DSH 会话 / 手机端）的角色 |
|---|---|---|
| Run / 节点状态 | `runs/<root_id>/`（`spec.json` / `result.json` / `events.jsonl` / `index.jsonl`） | 只缓存 `root_id` + 最新摘要行，重连按 `seq` 续读 |
| 对话（conversation） | 客户端自身会话 | 全权持有，**永不下沉到 `runs/`** |
| 任务状态 | Taskwarrior 任务库 | 通过 `ev` 写入，不直接改库 |

**冲突时以 `runs/` 为准**；客户端的缓存可以整份丢弃，运行目录不能。

## 6. 明确不做

- 不在客户端侧维护 Run 树、节点索引或状态机副本。
- 不让客户端的任何角色直接 spawn 执行单元——派发起源于 `runs/` 上的派发意图，由 `ar daemon` 执行（设计中、未部署）。
- 不在控制面做第二个调度器：ready 集、串行边界、租约属运行目录协议的一部分，由执行方持有（设计中、未部署）。

**一条红线**：不给客户端的任何角色配置直连工作站执行任意命令的通道。客户端挂了插件、MCP 与 Skill，天然具备自己动手的能力；一旦放开 SSH 直连，「编排不执行耗时任务」就只剩提示词约定，领导模式与 SuperAgent 的分工随之失效。强制点只能是受限入口脚本的子命令白名单与规则表 `to`。
