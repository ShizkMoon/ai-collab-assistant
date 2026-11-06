# 事件与任务规格：字段、状态与 CLI

> 状态：未部署 · 上位文档：[架构总览](architecture.md)、[事件运行时与派发](event-runtime.md)
>
> 本文规定任务的数据结构、状态映射与 `ev` 命令行工具接口。规则匹配、派发执行路径、并发与幂等机制见 [事件运行时与派发](event-runtime.md)。

任务库底层直接复用 **Taskwarrior 3**（`taskchampion.sqlite3`），作为全系统任务状态的唯一数据源，所有显示端与报表均从该库派生。

## 1. 任务字段定义

| 字段名 | Taskwarrior 对应项 | 含义说明 |
|---|---|---|
| `id` | `uuid` | 任务唯一标识 |
| `ts` | `entry` | 创建时间 |
| `source` | UDA `source` | 触发来源：`me` / `ha` / `cron` / `github` / `phone` / `email` / `rss` / `net` / `nut` / `local` |
| `kind` | UDA `kind` | `<域>.<对象>.<动作>`（如 `work.video.make`），全集定义见 [能力目录](capabilities.md) |
| `subject` | `description` | 任务标题或简述 |
| `state` | `status` + `start` + tags | 九种状态之一，见 §2 |
| `summary` | 完成时的注解（annotation） | 一句话执行摘要 |
| `payload` | UDA `payload` | 原始输入文件路径或结构化 JSON 参数（可为空） |
| `parent_uuid`（可选） | UDA `parent_uuid`（CLI 写作 `--parent`） | 归属节点：派生该子任务的父任务 UUID，决定汇总与升级方向。TW3 的 `parent` 是内置属性、不能作 UDA，故字段名加 `_uuid` 后缀；**不使用原生 `parent` 表达归属**，原因见 [多 Agent 运行时 §3](multi-agent-runtime.md#3-两棵树不要合并) |
| `depends`（可选） | 原生 `depends` | 执行依赖：开始执行前必须完成的节点，可以有多个；语义是父依赖子，与归属分开存放 |
| `thread`（可选） | UDA `thread` | 串联同一主题下多条任务的线索 ID（同 `thread` 内默认串行） |
| `severity`（可选） | UDA `severity` | `info` / `warn` / `critical`，控制推送渠道与免打扰穿透 |
| `lifetime`（可选） | UDA `lifetime` | `ephemeral` / `durable`，决定草稿是否设置过期清理时间（TTL） |
| `reversible`（可选） | UDA `reversible` | 标识操作是否可逆，决定是否提供 5 分钟撤销窗口 |
| `attempts` | UDA `attempts` | 失败重试次数，由派发方维护，执行器只读 |
| `lane`（可选） | UDA `lane` | `interactive`（交互） / `batch`（夜间批处理），决定调度队列 |

顶级域名包括：`work`、`life`、`home`、`info`、`media`、`meta`、`net`、`system`。其中 `system.*` 由看门狗、UPS（NUT）、路由器热插拔脚本等系统自检机制产生，不进入日常早晚报，仅在持续异常时升级推送。

## 2. 任务状态

| 状态名 | Taskwarrior 内部表示 | 写入方 | 状态说明 |
|---|---|---|---|
| `new` | `pending`（无 `start`） | 任务录入入口 | 新创建的任务，等待派发 |
| `doing` | `pending` + `start` | 派发方 | 执行器正在处理中 |
| `waiting` | `waiting`（`wait:<时间>`） | 执行器 / 人工 | 到期后自动转回 `new`，用于定时提醒、延后处理、间隔重复与聚合窗口 |
| `blocked` | `pending` + 未完成的 `depends` | 派发方 | 等待前置子任务或依赖任务完成 |
| `escalated` | `pending` + `+me`（及可选 `severity:critical`） | 派发方 / 执行器 | 需要人工确认或亲自处理，已发送交互卡片 |
| `failed` | `pending` + `+failed` + `attempts:N` | 派发方 | 执行失败，等待重试或超限后升级给人工 |
| `stalled` | `pending` + `start` + `+stalled` | 看门狗 | 执行时长超过 `2 × lease` 且无续租信号 |
| `spec` | `pending` + `+spec` + `wait:<ttl>` | 执行器 | 预生成的草稿或待补充规格说明，采纳则完成，过期自动清理 |
| `parked` | `waiting` + `+parked` | 派发方 / 执行器 | 前置环境条件未满足（如 `net.github` 不可达或处于静音时段），等待条件恢复 |

任务的终态为 `completed`（对应 `done`）与 `deleted`（对应 `dropped`）。完整状态流转图见 [事件运行时与派发 §2](event-runtime.md#2-状态机)。派发方指会话内的 DSH Agent（领导模式）或人工；任务库当前没有自动消费进程。

## 3. `ev` CLI 接口

`ev` 是对 `task` 命令的轻量级封装，负责填充 UDA 字段并格式化输出：

```
ev add "<任务描述>" [--kind ...] [--wake 明早9点] [--source ...] [--thread ...]
ev ls                                            # 调用 task next，按 lane 与 severity 排序
ev next [--after <时间>] [--limit N]             # 供显示端查询待办
ev done <id> "<执行摘要>"
ev wait <id> <时间>
ev reopen <id>                                   # 标记返工（供置信度校准与规则优化使用）
ev block <id> --on <uuid>
ev park <id> --needs net.github
ev status                                        # 输出 8 行运行状态概览
ev digest [today|week]
ev hook on-add|on-modify                         # 仅追加写入 Spool 队列，异常直接放行
```

Taskwarrior 原生的报表、过滤条件与同步子命令均可直接混用。

## 4. 派发接口规范

派发与任务库、执行器之间遵循三条基础约定（实现细节见 [事件运行时与派发 §3](event-runtime.md#3-派发执行路径)）：

1. **Hook 仅写队列，异步匹配规则**：`on-add` 与 `on-modify` Hook 在 5ms 内将变更写入本地 Spool 目录并立即返回（Fail-open），规则匹配与执行器调用都在会话内完成，由会话内 Agent 或人工发起。
2. **执行器统一输出七种状态**：`done`、`waiting`、`me`、`blocked`、`failed`、`split`、`spec`，由派发方转换为任务库中的九种状态。
3. **确定性幂等键**：`ev_id = uuid5(task.uuid, rule.name, attempt)`，确保同一任务的同一次规则触发不会产生重复副作用。该公式是设计值，不是实测值。

七种完成码是执行器输出层的枚举，九态是任务库状态层的枚举，两者是两层枚举，中间由派发方做映射（如 `me` → `escalated`、`split` → `blocked`、`done` → 终态 `completed`）。

## 5. 触发源接入方式

| 触发源 | 接入链路 | `source` 字段取值 |
|---|---|---|
| 自然语言输入 | DSH 会话 / AstrBot → 入口意图分类选出 `kind` → `ev add` | `me` |
| 智能家居设备 | Home Assistant Automation → 仅在需要跟进时调用 `ev add` | `ha` |
| 定时调度 | 任务计划程序或 Taskwarrior `recur` | 任务计划程序 |
| GitHub / 飞书 / Webhook | 云端等待队列接收后写入事件表，工作站拉取并调用 `ev add` | `github` / `webhook` |
| 邮件 / RSS | n8n（IMAP、RSS 节点）提取摘要后调用 `ev add` | `email` / `rss` |
| 手机端分享 | Phone Link / 微信文件传输 / HA Companion → `ev add` | `phone` |
| 网络出口变化 | AX6000 `hotplug` 脚本触发 `ev add --kind system.net.egress` | `net` |
| UPS 电源事件 | NUT 触发 `ev add --kind system.power.*` | `nut` |
| Agent 任务回调 | `agent:local` Run 完成后调用 `ev done` | `local` |

## 6. 任务库备份

`taskchampion.sqlite3` 通过 Litestream 持续增量复制到云服务器 `orca-pool`，同时每小时执行一次 `sqlite3 .backup` 本地快照。Litestream 要求 SQLite 处于 WAL 模式，Taskwarrior 3 在本机是否保持常驻 WAL 以实测为准；若不满足则以每小时 `.backup` 加 Restic 同步作为主备份方案（全量备份与月度恢复演练见 [系统运维 §9](platform-ops.md#9-备份与恢复演练)）。
