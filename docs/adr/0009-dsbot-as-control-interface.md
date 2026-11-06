# ADR 0009：交互层改用 DS-Bot 作为控制界面，`ar` 收敛为控制面 API

交互层不再以自建生成式 UI 工作台为主界面。主控制界面由 **DS-Bot**（DSH 多角色插件）承担：对话与结构化卡片、Web / Desktop / IM 多端、角色分工、会话记忆与定时任务。自建部分收敛为**控制面**——`ar` CLI 的对外子命令集（建、查、说、读、订阅）与 `runs/` 运行目录。执行者以成熟 CLI Agent（Codex / Claude Code）为主力，Pi 退为本地 GUI 自动化与端侧执行器。

**取代范围**：本条取代 [ADR 0008](0008-local-agent-runtime.md) 中「交互层同时调整」一段及其决策依据第 4 条（自建生成式 UI 工作台）。**不取代** ADR 0008 的执行层结论——自建 `agent:local` 运行时、`runs/<root_id>/` 信封协议、`events.jsonl` 对齐 Obelisk、`ar` 作为命令行入口，全部继续有效。

**决策依据**：

- 工作台是自建清单里最贵、复用率最低的一块：R2 切片 S16–S28 加 R3 追加、172 个测试、独立 Go 外壳（[agent:local 运行时设计 §11](../agent-local-runtime.md#11-v3-落地状态2026-11-04-真机)）。Run 树、diff、审批三动作、预算拦截、fork 逐条都要独占实现；而 DS-Bot 已提供这些交互所依赖的宿主原语：多端访问、多角色、结构化卡片、会话记忆、定时任务（[DS-Bot 入口 §1](../ds-bot-entry.md#1-组件功能定位)）。
- 控制面的契约必须自有、前端必须可替换。DS-Bot 与 DSH 版本强耦合（[DS-Bot 入口 §2](../ds-bot-entry.md#2-功能缺口与配套补充方案)），若把 Run 语义一并交给它，升级风险会从「前端坏」升级为「状态坏」。语义留在 `runs/`，前端就只是投影：换 DS-Bot、换 DSH 客户端插件、换手机端都不动数据面。契约见 [控制面契约](../control-plane-api.md)。
- 执行者换成熟 CLI Agent，换取工具实现与模型能力的现成供给。三家启动器已在 `C:\Repos\agent-local-runtime\src\daemon.ts:483-522` 落地：pi 带完整参数面（会话目录、`--tools` 白名单、扩展挂载、profile 提示词），claude 与 codex 为最小非交互面。代价是工具面不可裁剪，用「派发点审批 + `spec` 声明 tier」补偿（[控制面契约 §4](../control-plane-api.md#4-卡片语义与审批)）。
- 事实基线：本机 `codex` 与 `claude` 尚未安装（`Get-Command` 返回 MISSING），本次回调是**契约先行**——适配器面先定，实测在安装后按清单补（[worker 适配器](../worker-adapters.md)）。

**架构影响**：

- **交互层**：DS-Bot 为主界面；生成式工作台保留为可选旁路，代码留在 `C:\Repos\agent-local-runtime\workbench`，不再作为 v3 目标继续扩展。
- **控制面**：`ar` 命令面冻结为对外契约，新增 `list`（活 Run 摘要）与 `watch`（事件订阅）两条，见 [控制面契约 §2](../control-plane-api.md#2-命令面冻结)。
- **跨机**：DS-Bot 容器 → Tailscale SSH → 受限入口脚本 → `ar`，与 [DS-Bot 入口 §6](../ds-bot-entry.md#6-跨机调用工作站边界) 一致，对外只暴露四项受控操作，收敛为契约表。
- **执行层**：`spec.agent` 取值 `pi` / `claude` / `codex` / `dsh`，另加 `pi-edge`（端侧，零编排工具）。

**代价与回退**：

- **聊天流不擅长表达 Run 树、diff、fork**：这三项降级为「运行目录 + 按需旁栏」，不再有常驻图形视图。回退路径为恢复 `workbench` 外壳并重新路由，ADR 0008 正文保留不改。
- **DS-Bot 继承 DSH 的 rc 节奏**：安装脚本需同时锁定 DS-Bot 与 DSH 镜像标签，升级前在测试环境验证入口链路（[§2](../ds-bot-entry.md#2-功能缺口与配套补充方案) 已记）。
- **审批责任前移到派发点**：执行期不再设人工闸门，因此 `spec` 的 tier 与 `deny` 声明必须正确；声明错了只剩整节点 abort。
- **执行者异构的归一化成本**：Codex 与 Claude Code 的流格式不同，差异必须由 `src/transcribe.ts` 单点吸收，不允许扩散到 UI 与控制面。

**考虑过的替代方案：Multica**

`multica-ai/multica`（Go，Multica License＝Apache 2.0＋附加条件，自托管对自用免费）与本决策的架构高度同构：服务端记录与协调，本机 daemon 发现已安装的 AI coding 工具并注册为 runtime，把 issue 派给 agent 生成 run，由 runtime 认领后调用本地 CLI 执行。工具矩阵支持 28 家，含 Claude Code / Codex / DSH / Pi。

**不采纳为主运行时**，四条：

- **工作单元是 issue**（project / git 形状）。非代码域（墨水屏、Home Assistant、财务、创作管线）无对应物 `kind → 执行器` 的路由位置，套进去只能把路由写进 agent 指令（提示词约束），与本仓「档 3：不可构造」冲突。
- **run 记录在服务端**，与「`runs/` 文件是唯一权威」直接冲突；`kn` 召回要为此新增一个数据源。
- **无信封级约束**：`accept` 验收判据、`budget.depth_left`、parent / depends 分离在 issue/run 模型里没有位置。
- **双 daemon 争目录**：它的 `waiting_local_directory` 目录锁与 `ar daemon` 在同一批 worktree 上是互斥的，两套并存必然互相等待。

**保留的两种用法**（前提：同一目录只由一个 daemon 派发）：

1. **只读探针**：用 `multica issue runs` 等 CLI 读代码域状态，喂给 DS-Bot 卡片，不产生第二权威。
2. **`agent:multica` 适配器**：把整个节点外包给 Multica，轮询 run 状态回写 `result.json`——与 `claude` / `codex` 适配器同级，不改变信封协议。

**不做的用法**：用 Multica CLI 取代 `ar` 做通用编排。那是另一套状态权威，等于推翻本 ADR 与 ADR 0008 的执行层结论。

本 ADR 不否定 [ADR 0003](0003-loop-local-entry-remote.md)（入口与编排循环分离、循环留工作站）、[ADR 0007](0007-deferred-resident-node.md)（常驻节点延后）与 [ADR 0001](0001-taskwarrior-as-event-store.md)（任务库权威）。
