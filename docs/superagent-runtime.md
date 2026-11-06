# 以 dsh-superagent 作执行侧运行时

> 状态：设计中（未实施）· 上位文档：[总体架构设计](architecture-north-star.md) · 相关：[系统拓扑](system-topology.md)、[多 Agent 运行时](multi-agent-runtime.md)
>
> 本文记录一个待决策选项：把 `dsh-superagent`（官方研究室原型）的运行时当作执行侧候选，补充 DSH 内的编排与执行链路。按 2026-11-06 口径，编排与交互由 DSH 承担（会话内领导模式；工作区级 SuperAgent），执行由 DSH subagent / teammate 完成，`ar` 只提供控制面接口。事实部分已于 2026-11-06 核对源码，结论部分尚未验证。

## 0. 结论摘要

- `dsh-superagent` **不是 GitHub 专用**，它是多 Source 运行时；GitHub 与 Feishu 只是两个 Source 实现，共用同一套引擎。
- 它已经具备本系统设计里还没实现的部分：持久任务状态库（自带 sqlite store）、投递 outbox（幂等 + 重试 + 永久失败判定）、健康检查、准入政策、面板。缺的是与任务库的对接。
- 建议的第一步不是改造它，而是**写一个 `task` Source**：轮询任务库中的待办任务，转成 Trigger，其余交给它的任务、评估、执行、回复链路。任务权威仍留在 Taskwarrior。
- 它与 `ar` 不在同一层，也不是替代关系：`ar` 是控制面 CLI（0.1.0，未部署），superagent 是执行侧候选运行时。一个自带状态库与面板、跟随上游成本高；一个只有命令面、缺 UI 与审批。是否采用需要单独评估。

## 1. 已核实的事实（2026-11-06）

源码位置：`C:\Users\Administrator\agent-src\plugins\dsh-superagent-prototype`（以原生文件为准），本机以 `link:` 方式装进 desktop profile。

### 1.1 多 Source 结构

`sources/` 目录下是两套完整实现加一套共享设施：

| 文件 | 作用 |
|---|---|
| `github.ts`（35KB）+ `github-trigger.ts` / `github-read.ts` / `github-channel.ts` / `github-pull.ts` | GitHub Source |
| `feishu.ts`（13KB）+ `feishu-loops.ts` / `feishu-read.ts` / `feishu-trigger.ts` / `feishu-channel.ts` / `feishu-image.ts` | Feishu Source |
| `kind.ts`（8KB） | SourceKind 插件契约 |
| `registry.ts` / `host.ts` / `poll.ts` | 注册、宿主上下文、轮询工具 |

结论：GitHub 的耦合被限制在 `github*.ts` 内，引擎不认识 GitHub。

### 1.2 SourceKind 契约

一个 Source 要实现的是（见 `src/sources/kind.ts` 与 [008 Cookbook](C:\Users\Administrator\agent-src\plugins\dsh-superagent-prototype\docs\008-cookbook.md)）：

- `kind` / `title` / `description`：稳定标识与本地化文案；
- `schema` + `fields`：配置校验与由配置自动生成的设置表单；
- `health`：健康条目，`error` 会让状态脚本退出码 2 并触发人工通知；
- `facts`：设置页展示的派生值；
- Trigger 翻译函数：把外部消息变成带稳定 id 的 Trigger；
- `scope`：接收范围判定，返回 `listened` / `observed` / `row`；
- `channel`：回复通道，`send` 必须幂等，返回 `sent` 或 `gone`；
- `threadContext`：给评估层读取线程上下文；
- `policy`：谁能发起工作的名单与准入表行；
- `environment`：执行阶段的变量。

外加一个轮询循环（等待 `ctx.ready`、跟随开关、游标只在 `receive` 之后推进、逐条错误隔离、可中止）。注册方式是一行 `ctx.orchestrator.sources.register(kind)`，外部插件包同样可以注册。

### 1.3 已有的运行机制

- **引擎**：`Engine.receive` 返回 `stored` / `filtered` / `duplicate`，重复投递靠稳定 id 去重；无授权的事件会被过滤并记录原因。
- **投递**：Outbox 失败后 5 秒重试、指数退避到 300 秒；`gone` 表示永久不可达，保留为 dropped 不再重试。
- **评估**：`orchestrator_eval` 读取线程上下文后判断是否值得开工，产出 Mandate。
- **存储**：自带 Store（sqlite），并有 `migration.ts`（46KB）说明存储格式在演进。
- **面板**：Sources / Eval / 任务（`Tickets`）/ Records / Threads 等页面。
- **Setup**：`SETUP_FIELDS` 只认 GitHub 与 Feishu 字段，新 Source 需手动配置或补向导。

## 2. 与现有设计的映射

| dsh-superagent | 本系统 | 说明 |
|---|---|---|
| Source | 输入端口（`sources.toml`） | 一条通道一个 kind |
| Trigger | 事件 | 去重靠稳定 id |
| Thread | 线索 | 对应 [输入端口与输出路由](output-routing.md) 的线索上下文 |
| Ticket（原型侧任务状态机） | 任务 | **权威仍在 Taskwarrior**，需要映射 |
| Mandate | 派发授权 | 内含政策判定结果 |
| Session / Worker | Worker 会话 | 隔离目录内执行 |
| Channel / Outbox | 投递路由 | 幂等、重试、去重 |
| Eval | 分诊 | 决定是否值得开工、值得说话 |
| Source Policy / admission | 准入表 | 谁能发起工作 |

它对应的是本系统执行域里的编排与执行：按 2026-11-06 口径，两者都在 DSH 内——会话内领导模式负责单会话编排，工作区级 SuperAgent 负责跨任务编排，执行交给 DSH subagent / teammate；`ar` 只提供控制面接口，不承担派发。它额外带了任务状态机与面板。

## 3. 换一个 Source 的得与失

| 直接得到 | 仍需自己补 |
|---|---|
| 事件翻译、稳定 id、去重 | 政策与准入表（谁能发起工作） |
| 线程归属与上下文读取 | 执行环境变量与 prepare 命令 |
| 审批、健康检查、面板任务视图 | Setup 向导字段（只认 GitHub / Feishu） |
| Outbox 重试与幂等发送 | PR 类 thread 绑定（不要可省） |
| 任务状态机与评估调度 | 跨设备任务权威（Taskwarrior） |

## 4. 接入方案：`task` Source

目标是让任务库成为唯一入口，superagent 只当执行侧。

- **读取**：轮询 `task export`，取 `status:pending` 且带特定标签（如 `+agent`）的任务；游标用 `modified` 时间戳，按 `poll.ts` 的 `cursorAt` 惯例回退 5 秒以容纳迟到写入。
- **翻译**：Trigger id 用任务 UUID；Thread 用项目或域名；actor 为本机操作者；不带 `addressed` 时按准入表放行。
- **范围**：只接收目标标签的任务，其余作为 filtered 落库，便于面板解释。
- **回复**：`channel.send` 写回任务注解（`task annotate`），幂等键用消息 id；任务关闭时返回 `sent` 并同步 `task done`，任务已不存在返回 `gone`。
- **线程上下文**：读取该任务的历史注解，作为评估输入。
- **环境**：导出 `DSH_SUPERAGENT_TASK_UUID` 等变量给执行阶段。

这条路线不需要改引擎，也不需要写任务库桥插件——只需要一个 Source 与一份配置。

## 5. 与 `ar`（控制面 CLI）的关系

| 维度 | `ar`（控制面 CLI，未部署） | dsh-superagent（本选项） |
|---|---|---|
| 状态权威 | Taskwarrior + `runs/` | 自带 sqlite store |
| 面板与审批 | 依赖 DSH 原生会话 | 自带面板与准入表 |
| 跨端 | 靠任务库与 git | 靠它自己的 store，需另做同步 |
| 可恢复 | `runs/<root_id>/` 信封 | 任务 + 会话绑定 |
| 迁移成本 | 自建，可控 | 跟随上游，`migration.ts` 会变 |
| 成熟度 | 0.1.0 CLI 已发布（19 个动词，无 `list` / `watch`），控制面未部署 | research prototype，README 自称非生产可用 |

两种都成立。判别点在于：**如果接受"任务库仍是权威、superagent 只是执行侧"，它可以与 DSH 内的编排并行、影子运行**；如果要把 superagent 的 store 升为第二权威，就必须先解决跨端与备份（[状态归属表](architecture-north-star.md#9-状态归属表)不允许同类事实两处维护）。

## 6. 风险与约束

1. **双状态机对账**：原型侧 Ticket 状态与任务九态需要一张映射表，且必须单向权威（任务库优先），否则迟早分叉。
2. **研究原型**：代码风格不统一、可能有 bug；改动会被上游版本推着走。
3. **Setup 一段式体验缺失**：新 Source 不会自动出现在向导弹里。
4. **面板是第二套 UI**：与「交互层回到 DSH 原生会话」的结论并不冲突，但要注意别让两套界面各自维护状态。

## 7. 下一步

1. 写只读 `task` Source，只接收、不写回，验证 Trigger 翻译与去重。
2. 打开写回（`task annotate`），影子运行 7 天，与人工在任务库上的处置结果对照。
3. 依据对照结果评估是否采用 superagent 作执行侧；层级归属已定在 DSH，任务库权威不变。
