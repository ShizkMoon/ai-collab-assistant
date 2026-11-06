# research —— 八家 harness 源码级研究稿（2026-11）

> 本目录是早期执行侧研究的研究底座：**8 份单家研究稿 + 1 份横向合成**。
> 八份单家稿口径一致 —— `0 出处 → 1 定位与体感 → 2 架构 → 3 核心机制 → 4 UI → 5 值得抄 → 6 不抄 → 7 出处`；
> 结论要么给 `file:line`（源码级）、要么给官方文档 URL / 包内证据，凡推断处一律标 **需复核**。
>
> 所服务的工作台规范与 PRD 已随批 3 删除，本目录保留为历史研究记录。实现与测试仓：`C:\Repos\agent-local-runtime`。

## 采集方法

| 手段 | 用在哪几家 | 口径 |
|---|---|---|
| **源码级**（浅克隆 + `file:line`） | DSH、OpenCode、Codex、T3、OMP、Misaka、Cindy | `git clone --depth 1` 到 `C:\Users\Administrator\ego\research\<name>`，commit 哈希写在各稿 §0；结论逐条回源码核，行号可复核 |
| **包内证据**（无源码时的替代） | Claude Code | 无公开源码：`npm pack @anthropic-ai/claude-code@2.1.318` 解包，标【包内】；官方文档标【文档】；CHANGELOG 标【日志】——三层证据分开记，不混用 |
| **免费检索渠道**（ExaMCP） | 八家的仓库/文档定位 | 检索阶段用 ExaMCP 免费额度找对仓库与官方文档（该阶段不落稿）；**所有写进稿子的结论仍以源码或官方文档为准**，二手博客不作为证据 |
| **日期** | 全部 | 2026-11-03 / 2026-11-04；每份稿 §0 有 clone 时间与 commit，可据此复核"当时的绝对事实" |

## 索引（9 份，点开即读）

| # | 文件 | 覆盖 | 采集方法 | 日期 |
|---|---|---|---|---|
| 1 | [deepseek-harness.md](deepseek-harness.md) | DSH 会话/工具/审批/UI/扩展 | 源码级 + 本机 asar 同构证据 | 2026-11-04 |
| 2 | [opencode.md](opencode.md) | OpenCode 服务端/TUI/权限/插件 | 源码级（`d852834`） | 2026-11-04 |
| 3 | [claude-code.md](claude-code.md) | Claude Code 文档 + 包内证据 | npm 包内 + 官方文档 + CHANGELOG | 2026-11-04 |
| 4 | [codex.md](codex.md) | Codex exec 协议/双轴审批/hooks | 源码级（`93b4e5b`） | 2026-11-04 |
| 5 | [t3code.md](t3code.md) | T3 Code 事件溯源/多 provider | 源码级（`e68e19d`） | 2026-11-03 |
| 6 | [oh-my-pi.md](oh-my-pi.md) | OMP 审批解析器/纠偏/原语边界 | 源码级（`ff0a986`） | 2026-11-03 |
| 7 | [misaka-agent.md](misaka-agent.md) | Misaka DAG 研究图/波次屏障 | 源码级（`43f0c1f`, v0.19.23） | 2026-11-03 |
| 8 | [cindy.md](cindy.md) | Cindy 拦截式审批/Orca 会话制 | 源码级（main tarball，无 commit） | 2026-11-04 |
| 9 | [ux-synthesis.md](ux-synthesis.md) | 七家界面横向合成 + U 验收清单 | 前 8 份的 §4/§5 二次合成 + 2 张真机截图 | 2026-11-04 |

> 9 份稿子正文末尾各有一节「落点」，写的是这篇调研对现行设计到底起了什么作用：哪几条进了设计（锚到具体文档章节）、哪几条搁置及原因、对「执行侧自建还是复用」的判断、以及版本时效与复查时点。上表记的是「当时查到什么」，落点节记的是「现在还算不算数」。

## 每家最强 3 条结论

### 1. DeepSeek Harness（[deepseek-harness.md](deepseek-harness.md)）—— 我们每天跑在它上面

1. **审批裁决是闭集且 fail-closed**：`allowed-once | rejected | cancelled | unavailable`，应答者缺失/抛错一律归一成 `unavailable`（不是"拒绝"）。"没人答 / 被撤回 / 人拒了"在审计里必须可分（→ M1、S19）。
2. **审计对与可见性分离**：`asked` 与 `decided` 用同一个 id 配对，并带一个"只进日志、不进 prompt"的 surface 位——同一事件流既喂模型又喂审计（→ M12、S26）。
3. **溢写与诚实截断**：大结果落盘 + locator + retrievalHint，工具结果自带 `truncated/total/offset`，不完整就不显示统计；另有 **step 级工具准入**与**会话格式版本化 + 相邻迁移**（→ M8、S20）。

> 证据锚点：§3 核心机制（①–⑩ 逐条对应任务书）、§5 A 清单（机制 + 为什么 + 落点 + 成本）、§7 一手出处。

### 2. OpenCode（[opencode.md](opencode.md)）—— 权限模型最完整的一家

1. **资源级规则集 + deny 先行**：`Rule{action, resource, effect}` 数组 last-match-wins，求值前先对所有 resource 做 deny 预检（`core/src/permission.ts:94-104,176-189`）——我们原来的 `deny` 只到工具名，表达不了"允许 `git *`、拒绝 `rm *`"（→ M2）。
2. **工具输出截断契约**：2000 行 / 50KiB，超限保留头部 + 全文落 `tool-output/` + marker 带行范围与绝对路径；shell 另用**尾部截断**（`core/src/tool-output.ts:20-24,84-124`）（→ M8）。
3. **崩溃 claim + 续跑预算**：turn 开始写 claim，启动扫描，`resume_attempts += 1`，>10 → `failed("resume exhausted")`（`core/src/session/execution.ts:73-143`）；配套**工具状态机四态 + 流式投影**（按 `call_id` 折叠，`schema/session-event.ts:335-570`）（→ M13、M14）。

> 证据锚点：§5 A1（规则集）/A5（截断契约）/A9（续跑预算）/A7（分组与 verbosity 投影）；§7 出处含 `d852834`。

### 3. Claude Code（[claude-code.md](claude-code.md)）—— 无源码，靠包内 + 文档 + CHANGELOG 三层证据

1. **子代理与任务板分家**（2.1.318 起）：子代理是 `Agent`（后台默认、可命名、`SendMessage` 寻址、`isolation: worktree|remote`）；`Task*` 变成**共享任务板**（`blocks/blockedBy/owner/deleted`）——子代理要"命名 + 可寻址 + 隔离"三件套（→ M10）。
2. **权限六档 + 两个硬约束**：新增 `dontAsk`（会问即拒）用于无人值守；`critical paths` 硬拒（`rm/rmdir` 命中根/家/工作目录，**任何档与 `PreToolUse:allow` 都无权放行**）——这是唯一挡得住 `rm -rf` 且不被 grant 绕过的机制（→ M3）。
3. **44 个工具面里多数是产品功能，不是 harness 机制**：能抄的是权限/恢复/子代理语义，工具本身不值得复刻（这条直接决定了我们只抄 M1–M15）。

> 证据锚点：§1.3 逐条「确认/修正/新增」、§4 UI 的三个具体结论、§7 出处（npm 包内路径 + 文档 URL）。

### 4. Codex（[codex.md](codex.md)）—— 事件模型与双轴审批

1. **`guardian` 自动审批评审子系统**：`risk × user_authorization` 双维 + 人话 `rationale` + **遇压缩即作废**（`IncompatibleCompaction`）+ 被拒后可用 `ApproveGuardianDeniedAction` 推翻——advisor/reviewer 的"零新进程"蓝本（→ M11）。
2. **hooks 实际 14 个事件**（v2 写的 11 个少了 `Interrupt / PreModelRequest / PostModelRequest`）：hook 清单与策略映射必须按 14 事件重排。
3. **`untrusted` 是内部策略档而非退役档**，`on-failure` 只是 `on-request` 的 serde 别名——复核口径要以 serde 定义为准，不看文档措辞。

> 证据锚点：§3 核心机制（审批两轴 / guardian / hooks）、§6 不抄（granular 子档我们用不上）、§7 出处含 `93b4e5b`。

### 5. T3 Code（[t3code.md](t3code.md)）—— 事件溯源控制面

1. **`seq + commandId` + process-bound effect 不重放**：pid 死 → `orphaned`，不再二次 spawn（→ M5、S21）。
2. **回复三态 `queue / steer / restart`**，且 **ack = 已准入，不是已完成**（→ M9、S22）。
3. **快照三件套 `latest_seq / snapshot_seq / pruned_below`**：增量投影的基线，配合事件裁剪才不会"重放失控"（→ M5）。

> 证据锚点：§3 核心机制、§5 A1–A10、§7 出处含 `e68e19d`；多 provider 运行时进 R3 再议。

### 6. Oh My Pi（[oh-my-pi.md](oh-my-pi.md)）—— 运行时纠偏

1. **审批是解析器，不是白名单**：`tier × tool policy × user policy`；`restricted_paths`（必问）与 `deny_paths`（必拒）必须分开，grant 记 tier——工具名白名单在扩展/MCP 场景必漏（→ M2）。
2. **loop guard 用跨轮 canonical hash**，不是单调用计数（单调用计数挡不住"换个参数再来一次"）。
3. **三个原语的边界**：`live-steering`（真插话需 RPC）、`advisor-watchdog`（只读旁观）、`checkpoint/wait`（等待原语）——分别对应我们的 M9、M11、M13。

> 证据锚点：§3 核心机制、§5 A1–A12、§7 出处含 `ff0a986`；对照基线为 pi 1.5.0。

### 7. Misaka-Agent（[misaka-agent.md](misaka-agent.md)）—— DAG 研究图

1. **波次屏障 + 层间 reconciliation（同问合并）**："多 agent"真正的难点是**层间收敛**，不是画图（→ M10、M11）。
2. **持久 phase + 每阶段幂等重建**：崩溃后按 phase 重建而不是从头重跑（→ M13）。
3. **driver 租约替代 pid 检查**：进程存在 ≠ 任务活着，租约过期才算死（→ M5）。

> 证据锚点：§3 核心机制、§4 panel 三层信息架构、§5 A1–A10、§7 出处含 `43f0c1f`（v0.19.23）。

### 8. Cindy（[cindy.md](cindy.md)）—— 拦截式审批 + Orca 团队会话

1. **`send` 与 `steer` 语义分离**，权限门顺序固定为 `deny → rules → grant → approve`；顺序错了会"为注定失败的调用弹窗"（→ M1、M2）。
2. **`auto` 档 = 第二模型评审一个 gate-req，评审失败即 deny**（fail-closed 的另一种形态）（→ M1）。
3. **忙碌不丢消息 + 派发幂等 token**；Orca 的团队会话制是"多 agent 会话"而非"多 agent 进程"（→ M9、M10）。

> 证据锚点：§3 核心机制、§5 A1–A10、§7 出处（main 分支 tarball，无 commit 哈希，见该稿 §0 的说明）。

### 9. UX 横向合成（[ux-synthesis.md](ux-synthesis.md)）—— 不是第九家，是八家的界面收敛

1. **C1–C12 共识模式**：至少 3 家独立做过的交互模式（结论块常驻、工具卡可折叠、审批卡三动作、等待态一行……）。
2. **D1–D12 分歧取舍**：逐条写"各家怎么做 / 我们选哪个 / 为什么"，是我们和别家不一样的地方的**唯一辩护地**。
3. **P1–P20 修订 + U01–U29 验收清单**：P 是工作台 UI 规范的硬改动条目，U 是可逐条核的验收项（U22 性能未达标，已转 S26；U04/U07/U29 有实测后的口径修订）。规范本身已随批 3 删除，P/U 编号保留在 `ux-synthesis.md` 作历史记录。

> 证据锚点：§1 对照矩阵、§2 共识、§3 分歧、§4 修订、§6 验收清单、§7 未覆盖与需复核。

## 怎么用这批稿子

- **要改机制**：先看 PRD §1.4 的 M1–M15 表（谁有 / 落点 / 成本 / 进哪片），再回对应研究稿的 §5 看"为什么"和"成本坑"。
- **要改界面**：看 `ux-synthesis.md` §2/§3/§4，再用 §6 的 U 清单做验收（工作台 UI 规范与工作台本身均已废止，这批条目只作历史参考）。
- **要复核事实**：每份稿 §7 都有 clone 路径 / commit / URL；行号以那个 commit 为准，不要对着最新 HEAD 核。

## 已知未覆盖（诚实的边界）

- **Codex / Claude Code / Cindy 的键盘与主题**只覆盖到「有 keybinding / 有 spinnerVerbs / 未见」，逐键表与颜色值需复核。
- **T3 Code 的 diff 视图**只覆盖 checkpoint/rollback 语义，未覆盖 diff 组件呈现方式。
- **OpenCode TUI 视觉细节**由研究稿自陈未读，只采结构结论；**DSH 的 diff 呈现**未覆盖。
- 八家均**未覆盖**：MCP 工具目录预算、远程/多机执行、沙箱实现细节（这些 R4 再研）。
