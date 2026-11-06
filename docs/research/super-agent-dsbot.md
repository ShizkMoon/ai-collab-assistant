# Super-agent 机制在 DS-Bot + ar + Codex/CC 上的落点

> 复核对象：[Super-agent 架构参考（外部文献笔记）](../super-agent-architecture.md) 全文 129 行，重点为 §2–§7 的机制陈述与 §9 的现有取舍表。外部原文为 DeepSeek 产品部《Super-agent 设计探索：迈向更自主的 Agent 系统》（2026-10，本地 HTML 存档，以原生文件为准，见 [super-agent-architecture.md:3](../super-agent-architecture.md#L3)）。
> 复核动因：交互层回调到 DS-Bot、执行者改用 Codex / Claude Code、Pi 退为本地与端侧执行器之后（ADR 0009，Lead 在写，本文不引其条文），[§9 取舍表](../super-agent-architecture.md#L111) 需要在**新组合**上重判一次。本文不复述原文，只做机制级落点判定。
> 证据等级：**[X]** 外部文献原文可查（给 `super-agent-architecture.md` 行号）；**[D]** 本仓文档可查；**[T]** 本文推断，需实测。
> 只读范围：本文不修改任何其他文件。

---

## 0 一句话结论

十个机制里**四个直接坐实**（两级过滤、Inline/Spill/链式召回、全双工 start/stop、按信道输出密度）、**四个需改造**（强制隔离的强制点不在 DS-Bot 而在受限入口脚本与规则表；Thread 直通要拆成「串行」与「订阅」两件事；预执行要收紧到确定事件触发；看门狗要挂 `events.jsonl` 判据）、**两个不采纳**（Batching——事件率比原文生效门限低一个数量级；存算分离原形——按本仓反向部署的变体处理）。

---

## 1 事实基线

### 1.1 原文实验数据能不能直接引用

原文的负载是「模拟群聊 + GitHub CI 事件流，单轮约 300 条消息（含约 20 个真实工作请求），重复 5 轮」[X: [95](../super-agent-architecture.md#L95)]。它是**团队级事件密度**。本系统的入口事件率是单人量级：早晚报、十几条 IM、若干 CI 与 Home Assistant 事件，日总量在数十条级别 [T]。

这条差异决定了两件事：

- 百分比收益（Router 决策 -30%、缓存 token -37% [X: [99](../super-agent-architecture.md#L99)]）**不能当预期值**，只能当方向；
- 依赖事件密度的机制（Batching）在我们就等于零收益，判定见 §2。

唯一可以直接搬的结论是定性的那条：**仅靠提示词让单 Session 模型自行决定「是否委派子代理」不稳定，必须在架构层强制隔离** [X: [102](../super-agent-architecture.md#L102)]。这条与本仓「档 3：不可构造」[D: [multi-agent-runtime.md:142](../multi-agent-runtime.md#L142)] 完全同向，是本文全部判定的共同前提。

### 1.2 回调后三个面的落点契约

| 面 | 谁承担 | 持有什么 | 不许做什么 |
|---|---|---|---|
| **水面（交互）** | DS-Bot：Chief 主入口 + 专项角色 | 会话、会话记忆、卡片、IM 绑定 | 不执行耗时任务、不持有 Run 状态 |
| **序点（控制）** | `evd` + `ar` CLI | 任务库、`runs/` 信封、`thread` 锁、`ev_id` 幂等 | 不做会话、不在派发链路上做开放式语义判断 |
| **执行（Worker）** | Codex / Claude Code（主力），Pi（本地与端侧） | 自己节点的目录或 worktree、`events.jsonl` | 不直连用户、不写兄弟节点、不自行派发 |

依据：[system-topology.md:33](../system-topology.md#L33)（三层职责）、[multi-agent-runtime.md:114](../multi-agent-runtime.md#L114)（目录即权限边界）、[agent-local-runtime.md:34](../agent-local-runtime.md#L34)（工具面随 `spec.json` 裁剪）。

---

## 2 逐条对照

| 机制 | 原文要求 | 我们的落点（DS-Bot / ar / Worker） | 判定 | 理由 |
|---|---|---|---|---|
| **Router / Worker 强制隔离** | Router 不执行耗时任务、甚至不挂 Bash；Worker 不直连用户；仅靠提示词不稳定 [X: [26](../super-agent-architecture.md#L26)–[27](../super-agent-architecture.md#L27), [102](../super-agent-architecture.md#L102)] | DS-Bot 只出 `ev add` 与 `ar` 的四项子命令；`evd` 规则表决定 `to`；Worker 只写自己节点 | **需改造** | 强制点不能在 DS-Bot 的提示词里。它挂了插件、MCP、Skill [D: [ds-bot-entry.md:19](../ds-bot-entry.md#L21)]，天然能自己干。强制点只能落在**受限入口脚本的四项子命令** [D: [ds-bot-entry.md:61](../ds-bot-entry.md#L63)] 与规则表 [D: [architecture.md:84](../architecture.md#L84)] |
| **Batching** | 积压事件合并注入，靠 prefill 并行摊薄单条决策耗时；事件率 1→40 条/分时 Batch 1.0→2.8 [X: [29](../super-agent-architecture.md#L29), [100](../super-agent-architecture.md#L100)] | 无对应物；已有的是**事件级聚合**（`aggregate.window` 按 thread 6h rollup）[D: [event-runtime.md:91](../event-runtime.md#L91)] | **不采纳** | 事件率低于生效门限一个数量级，Batch 恒为 1，收益为 0；而引入攒批会增加「该派不派」的错误面与延迟。真正需要合并的场景（订阅早报、feed）已由聚合窗口覆盖 |
| **两级过滤 Fast/Slow** | 确定性规则初筛 + 模型语义判断 [X: [40](../super-agent-architecture.md#L40)–[42](../super-agent-architecture.md#L42)] | Fast：`sources/<id>.toml` 的信任级别 + `evd` 规则表；Slow：Chief 从能力目录选 `kind` | **坐实** | 与本仓现有分层同构。补一条硬约束：`decide()` 低置信度**不猜**，落 `meta.triage.pending` [D: [architecture.md:84](../architecture.md#L84)]，否则 Slow Path 就是变相的开放式判断 |
| **Thread 直通与订阅** | Worker 订阅 thread 后，后续事件程序直投、不经 Router；输出仍走 Router 统一收口 [X: [47](../super-agent-architecture.md#L47)–[49](../super-agent-architecture.md#L49)] | 现有 `thread` 是**串行锁**（同 thread 严格排队，派发前取锁）[D: [event-runtime.md:94](../event-runtime.md#L94), [:249](../event-runtime.md#L249)]；订阅面不存在 | **需改造** | 两者语义相反：原文让事件**绕过** Router 更快到达 Worker，我们让事件**排队**等前一个结束。详见 §3 问题③ |
| **Inline / Spill / 链式召回** | 热信息内联、低频外溢留 ID 与摘要、相邻一跳对象 ID 注入形成引用图 [X: [55](../super-agent-architecture.md#L55)–[57](../super-agent-architecture.md#L57)] | Inline：`already_known`；Spill：`artifacts/` + `art://` 引用 + `result.json` 摘要行；链式：`thread`/`parent`/节点 ID | **坐实，补一个字段** | 三档都在，但「相邻一跳 ID」现在是隐含的。`spec.json` 应显式带 `recall`：`[thread_id, parent_id, 兄弟节点 result 摘要 ID]`，否则模型要靠猜去 `ar read` |
| **预执行** | 意图概率高时后台预耗算力备草稿，确认即交付、不用即静默丢弃 [X: [61](../super-agent-architecture.md#L61)–[64](../super-agent-architecture.md#L64)] | 任务库 `spec` 状态 + `wait:<ttl>` 24h 过期 [D: [event-spec.md:43](../event-spec.md#L43)] | **需改造（收紧）** | 缺少「意图概率」的触发面。原文是持续预嗅，我们只能由**确定事件**触发（会议邀约、邮件、CI 失败）才生成草稿；持续预嗅需要常驻监听，收益未见、成本确定 |
| **全双工 start/stop** | 耗时操作拆 `start()`/`stop()`，立即返回已启动；后台完成作为新事件回投会话 [X: [70](../super-agent-architecture.md#L70)] | `ar` 投递即返回；Worker 完成调 `ev done`；`ar check --wait` 等 `worker_done`/`escalation`/`question` [D: [system-topology.md:59](../system-topology.md#L59)] | **坐实，缺推送面** | 「回投会话」这一半现在是**拉**不是**推**。DS-Bot 要的是 push，`check --wait` 是长轮询兜底。补 `ar watch`（见 §4） |
| **按信道区分输出密度** | IM 低打扰、单次 ≤100 词、只在需决策或验收时通知；PR/邮件/文档高密度结构化 [X: [72](../super-agent-architecture.md#L72)–[77](../super-agent-architecture.md#L77)] | IM：一句话摘要 + `[执行][延后][忽略]` 三按钮 [D: [ds-bot-entry.md:69](../ds-bot-entry.md#L71)]；大产物留工作站只回路径 [D: [system-topology.md:61](../system-topology.md#L61)] | **坐实** | 落点已有。补一条：密度应由 `spec.json` 的 `delivery` 字段**程序化**决定，不能靠提示词叮嘱 Worker「写短点」 |
| **存算分离与 BYOM** | Loop 无状态、状态外置；用户机器只放轻量执行守护进程，支持多机统一接入 [X: [81](../super-agent-architecture.md#L81)–[82](../super-agent-architecture.md#L82)] | **反向**：状态、执行环境、凭据全在工作站 [D: [adr/0003:3](../adr/0003-loop-local-entry-remote.md#L3)]；远端只做搬运 [D: [system-topology.md:36](../system-topology.md#L36)] | **变体，不采纳原形** | 回调后形态变了但结论不变：**模型算力去了厂商，状态与执行环境仍搬不走**（未提交代码、私有凭据、GPU、桌面会话）。BYOM 的「机」在本仓就是工作站一台，不做多机池（[ADR 0007](../adr/0007-deferred-resident-node.md) 已延后） |
| **Watchdog** | 独立定时会话，重点查**是否取得实质进展、是否陷入无效重试、是否偏离目标**，可用自然语言询问故障 [X: [86](../super-agent-architecture.md#L86)–[89](../super-agent-architecture.md#L89)] | 任务计划程序 + `ev-watchdog` + `hc check`；计时判据 `2 × lease` [D: [event-spec.md:42](../event-spec.md#L42)] | **需改造（现在便宜了）** | 我们只有计时判据，没有进程性判据。`events.jsonl` 落盘后可零 token 判「同参失败 N 次」「M 分钟无新事件」[D: [agent-local-runtime.md:113](../agent-local-runtime.md#L113)]。原文的「自然语言问 Watchdog」**不采纳**：要常驻会话，token 成本确定、收益未见 |

---

## 3 三个必答题

### 3.1 DS-Bot 的多角色 + `message_bot` 转发 + handoff，能否承担 Router

**能承担 Router 的「水面」那一半，不能承担「序点」那一半。**

能的部分有据可查：多角色即职责分离（Chief 主入口 + 专项角色，各自绑定提示词与模型）；`message_bot` 转发与 Handoff 交接即派发与移交；交互卡片（确认按钮、选项列表、进度条、表格、短表单）即输出面 [D: [ds-bot-entry.md:15](../ds-bot-entry.md#L17)–[20](../ds-bot-entry.md#L22)]。这三样恰好是原文 Router 的对外职责 [X: [26](../super-agent-architecture.md#L26)]。

缺三样，且都是机制级的：

1. **没有程序化的「不执行」约束。** Router 的关键约束是「不挂 Bash、不执行耗时任务」[X: [26](../super-agent-architecture.md#L26)]。DS-Bot 是插件宿主，可挂 DSH 插件、MCP Server、Skill、GitHub Connector [D: [ds-bot-entry.md:19](../ds-bot-entry.md#L21)]——它**天然能**自己干。靠提示词约束就是档 0，违反 [multi-agent-runtime.md:146](../multi-agent-runtime.md#L146) 的取向。强制点必须放在**受限入口脚本只暴露四项子命令**（建任务、查状态、读输出、发跟进）[D: [ds-bot-entry.md:61](../ds-bot-entry.md#L63)] 和规则表 `to` 上。**允许 DS-Bot 直接 SSH 到工作站跑任意命令，本文所有判定作废。**
2. **没有全局并发序点。** 多角色 = 多会话，各自独立、互相不知道对方在派发什么 [T]。真正的序点在 `evd`：`thread` 锁保证同 thread 串行、`lane_parallel` 管跨 thread 并发 [D: [event-runtime.md:249](../event-runtime.md#L249)–[250](../event-runtime.md#L250)]。DS-Bot 只能是序点的**调用方**，不能是序点本身。
3. **Handoff 不是派发。** 角色间交接是「谁接着跟用户聊」，不是「谁对这个节点负责」。它不带 `accept` 验收条件、不带 `budget.depth_left`、没有祖先升级路径 [D: [multi-agent-runtime.md:179](../multi-agent-runtime.md#L179)]。把 handoff 当派发，等于丢掉「没有可执行验收条件的节点在派发时被拒」这条档 2 拦截 [D: [multi-agent-runtime.md:148](../multi-agent-runtime.md#L148)]。

**结论**：DS-Bot = Router 的自然语言半边；程序化半边（派发、幂等、串行、升级）留在 `evd`/`ar`。两者不是主从，是分工。

### 3.2 DS-Bot 与 `ar` 的状态边界：conversation 归谁，run 归谁

**conversation 归 DS-Bot，run 归 `runs/`，任务归任务库；冲突时以 `runs/` 为准。**

这条本仓已有明文：前端展示的任务状态直接读 `runs/` 与 Taskwarrior，不在前端维护独立副本 [D: [system-topology.md:69](../system-topology.md#L70)]；入口只缓存 `root_id`、节点路径与最新摘要 [D: [system-topology.md:73](../system-topology.md#L74)]。

判定冲突优先级的三条铁律：

1. **DS-Bot 侧只存指针与摘要**（`root_id` + 节点路径 + 一句话摘要）。不存节点状态、不存进度百分比。
2. **任何「这个任务现在怎么样」的查询都走 `ar check`**，不读 DS-Bot 的会话记忆 [D: [agent-local-runtime.md:58](../agent-local-runtime.md#L58)]——`ar` 只回答三件事：Run 长什么样、派一个节点、替我对它说话。
3. **DS-Bot 记忆只放称呼、活跃项目与近期摘要**，跨周期偏好统一走 `kn recall` [D: [ds-bot-entry.md:70](../ds-bot-entry.md#L72)]。群组记忆与共享 Markdown 一旦存了任务状态，就成了第二份需要同步的权威。

这是原文「计算与状态分离」[X: [81](../super-agent-architecture.md#L81)] 在本仓的变形，一句话记：**会话可丢，run 不可丢。** DS-Bot 整机重建后能从 `runs/` 恢复跟踪，反之不成立。

### 3.3 原文的 Thread 直通/订阅，对应 `ar` 的什么

**不对应 `thread` 字段，也不对应父子节点；需要新增一个订阅面。** 而且现有 `thread` 的语义与原文**相反**。

先看原文到底要什么：Worker 创建并订阅某 Thread 后，后续同 Thread 事件**由程序直接路由给该 Worker，不再经过 Router**；事件超出范围时 Worker 退订或交回；**输出仍由 Worker 汇报给 Router 统一回复** [X: [47](../super-agent-architecture.md#L47)–[49](../super-agent-architecture.md#L49)]。它的收益是 Router 决策次数 -30%、缓存读取 token -37% [X: [99](../super-agent-architecture.md#L99)]。

再看我们手里有什么：

| 候选 | 是不是 | 依据 |
|---|---|---|
| `thread` 字段 | **不是同一件事**。我们是串行边界：同 `thread` 内严格排队，前一条 `done` 前不派发下一条 | [event-spec.md:23](../event-spec.md#L23)、[event-runtime.md:94](../event-runtime.md#L94) |
| 父子节点 `parent` | **不是**。`parent` 是归属（谁汇总、向谁升级），与「事件往哪投」无关 | [multi-agent-runtime.md:43](../multi-agent-runtime.md#L43) |
| 订阅面 | **缺，需要新增** | 见 §4 增量 1 |

所以正确的映射是：**拆成两件事**——① 同 thread 串行（已有，坐实，原文没讲这条）；② 事件订阅直通（没有，需新增 `ar watch`）。

而不做的后果要分两半说，因为原文的收益在我们这里**只有一半拿得到**：

1. **拿得到**：每条同 thread 事件不必再过 Chief 的语义判断，直接落 `ar orchestration reply` [D: [system-topology.md:59](../system-topology.md#L59)]，即原文的「决策次数下降」。
2. **拿不到**：原文的 -37% 缓存收益依赖 Worker **长期存活**（会话一直在，缓存前缀一直在）。我们是「一个节点一个进程」[D: [agent-local-runtime.md:22](../agent-local-runtime.md#L22)]，进程退出即退订，下一个事件要重建进程、重建上下文——直通省了 Router 判断，省不了上下文重建。**把原文百分比当预期是错的。**
3. **不做的代价**：每条消息都要过 Chief，Chief 的会话上下文随消息线性增长；且 `ar check --wait` 是长轮询，多 Run 并行时轮询次数 × Run 数，DS-Bot 侧难以维持多个长连接（其长连接稳定性本身还是待实测项 [D: [ds-bot-entry.md:83](../ds-bot-entry.md#L85)]）。

---

## 4 对我们的增量

1. **新增 `ar watch <run|thread>` 订阅面**（增量最大）。语义：对 `events.jsonl` 的增量推送（SSE 或长轮询），订阅方是 DS-Bot。`ar` 现有三件事（`check`/`dispatch`/`reply`）[D: [agent-local-runtime.md:58](../agent-local-runtime.md#L58)] 都是拉，DS-Bot 的卡片是推，中间缺这一跳。副作用是把 system-topology 的受限入口脚本从四项扩到五项（`watch`）。
2. **`spec.json` 增 `recall` 字段**：`[thread_id, parent_id, 兄弟节点 result 摘要 ID]`，把原文「链式召回相邻一跳」[X: [57](../super-agent-architecture.md#L57)] 从隐含约定变成显式字段，减少 Worker 盲目 `ar read`。
3. **`spec.json` 增 `delivery` 字段**：`im-brief` / `doc-full` 两档，按信道输出密度 [X: [74](../super-agent-architecture.md#L74)–[77](../super-agent-architecture.md#L77)] 由程序决定，不由提示词决定。
4. **强制隔离写进入口脚本而不是提示词**：四项（+ `watch`）子命令白名单即档 2 拦截；DS-Bot 的任何角色都不配置直连工作站的 SSH 免提权通道 [D: [system-topology.md:53](../system-topology.md#L53)]。
5. **看门狗挂 `events.jsonl` 判据**：同参失败 N 次、M 分钟无新事件 → 标疑似死循环，仍走任务计划程序的无状态脚本，不建常驻 Watchdog 会话 [D: [agent-local-runtime.md:113](../agent-local-runtime.md#L113)]。
6. **[§9 取舍表](../super-agent-architecture.md#L111) 两处措辞应改**：Thread 一行（[:119](../super-agent-architecture.md#L119)）的「简化采纳：同 thread 内串行，不引入多对多订阅总线」把两件事压成了一件，应拆为「串行（已实现）/ 订阅（待建）」；Watchdog 一行（[:125](../super-agent-architecture.md#L125)）应补 `events.jsonl` 判据并注明收益前提。**这两处修改落在 §9 原文，由 Lead 决定，本文只提出。**

---

## 5 未解决问题

1. **一条 IM 消息被多角色同时看到时的幂等归属。** `ev_id = uuid5(task.uuid, rule.name, attempt)` [D: [event-spec.md:74](../event-spec.md#L74)] 只能保证「同一次规则触发不重复副作用」，不能保证「同一条消息只被一个角色认领」。群聊场景下（AstrBot / `@xmanrui/dsh-im`）这个判定缺失 [T]。
2. **凭据隔离面迁移了，但没评估。** 原文警告「明文凭据进入模型上下文即可能泄露」[X: [109](../super-agent-architecture.md#L109)]；我们原本靠 DPAPI + CLI 封装规避 [D: [super-agent-architecture.md:127](../super-agent-architecture.md#L127)]。执行者换成 Codex / Claude Code 后，凭据虽然仍不进模型上下文，但会进**厂商 CLI 的进程环境**（`~/.codex`、`~/.claude`、环境变量）。风险形态从「上下文泄露」变成「进程环境可读」，未评估。
3. **订阅与串行的优先级冲突。** 同 `thread` 的新事件进来时，是直投正在运行的 Worker（破坏串行）还是排队（等于没有直通）？可行的折中是「直投只对 `interactive` lane 且 Worker 支持 steer 时成立」——而 steer 目前不存在，回复只有「下一轮生效」与「打断重来」[D: [agent-local-runtime.md:159](../agent-local-runtime.md#L159)]。所以 `ar watch` 首发只能是**通知面**，不是**注入面**，这一条要在验收口径里写死，否则会做成半个 steer。
4. **预执行的意图概率没有数据来源。** `spec` 草稿的采纳率是否统计、在哪统计，未见约定 [X: [61](../super-agent-architecture.md#L61)]、[D: [super-agent-architecture.md:121](../super-agent-architecture.md#L121)]。没有采纳率就无法判断「按需采用」该扩还是该收。
5. **DS-Bot 与 DSH 版本强耦合 vs 长连接。** `ar watch` 要做成长连接，而 DS-Bot 已记「与 DSH 版本强耦合，升级前需在测试环境验证入口链路」[D: [ds-bot-entry.md:30](../ds-bot-entry.md#L32)]。断线重连后的**事件去重**语义未定义（客户端从哪个 `seq` 续订）。
