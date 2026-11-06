# ADR 0011：编排与交互交给 DSH，`ar` 收敛为控制面 CLI

> 状态：已接受（2026-11-06）· 取代 [ADR 0001](0001-taskwarrior-as-event-store.md)、[ADR 0003](0003-loop-local-entry-remote.md)、[ADR 0007](0007-deferred-resident-node.md)、[ADR 0008](0008-local-agent-runtime.md) 中与本决策冲突的条款，范围见 §3 · 旧 ADR 正文不改

## 1. 背景

2026-11-06 对本机 DSH 安装、本仓设计文档与 `C:\Repos\agent-local-runtime` 的代码做了三方比对。比对暴露的问题不是某处细节写错，而是自建的那一层与 DSH 已经提供的能力大面积重合：Worker 适配由 `dsh-subagent-claude-code` 与 `dsh-subagent-codex` 覆盖，审批由 `dsh-user-approval` 配合 `dsh-permission-presets` 覆盖，前端由 `dsh-client-ui-*` 覆盖，任务 DAG 由 `dsh-experimental-agent-team` 覆盖。这四块，正是仓库里那套自建运行时、自建派发器与生成式 UI 工作台打算解决的问题——而那套东西现在已经废止。

文档这一侧写的是一个完整系统，代码这一侧是另一回事。`ar` 只有 19 个子命令，没有 `list` 与 `watch`；`runs/` 运行目录与 `events.jsonl` 停在纸面；`evd` 派发器在 `C:\Repos\agent-local-runtime` 里零实现，只剩三处引用。继续按文档推进，等于用自写代码复刻 DSH 已有、且随 DSH 版本一起演进的能力，同时长期维护一份必然落后的状态副本。

## 2. 决策

**其一，编排与交互归 DSH。** 会话内的编排形态是 leader preset（「领导模式」）：默认把活拆成几件、分别外包给子智能体，自己只留提问、计划、委派与核对。工作区与实例级的编排由 SuperAgent 承担。理由很直接：上一节那四个一方包已经落在 DSH 里，自建一份只会多出一层需要同步的中间层。

**其二，执行归 DSH 的 subagent 与 teammate。** 自建 Worker 适配层——自己拼 `claude` / `codex` 命令行、再把 stdout 解析成结构化结果——废止。DSH 的适配是协议级的，转写由适配器负责；自建一套转写，两家 CLI 的输出会整体落进 `_raw`，结构化字段全部拿不到。

**其三，任务库仍是 Taskwarrior 3.5.0。** 读写由人或 Agent 通过 `ev` / `task` 手动完成。当前没有任何进程自动消费任务库，这句按现状写，不按目标态写。

**其四，`ar` 从运行时降级为控制面 CLI。** 版本 0.1.0，19 个子命令：`run-create`、`dispatch`、`node-create`、`resume`、`spawn`、`check`、`reply`、`gate`、`done`、`fail`、`wait`、`event`、`events`、`fork`、`abort`、`propose`、`cmd`、`daemon`、`version`，没有 `list` 与 `watch`。`runs/<root_id>/` 信封协议与 `events.jsonl` 属设计中，未部署——`%LOCALAPPDATA%\aica\state\runs` 不存在。`ar daemon` 走 `daemon.pid` 加 `runs/index.jsonl` 的文件队列，不监听 TCP。

**其五，`evd` 派发器废止。** `C:\Repos\agent-local-runtime` 内零实现，仅被 `package.json:4`、`src/cli.ts:2`、`src/runs.ts:610` 引用。本 ADR 不把它写成「保留为目标态」的东西：没有实现，没有部署，没有排期。

**其六，workbench、DS-Bot 主界面与 4399 端口一并废止。** 生成式 UI 工作台、把 DS-Bot 当作主界面、workbench 桥用的 4399 端口，三者在 ADR 0010 之后已无客户端，不再列为待建项。

## 3. 取代范围

本 ADR 取代 ADR 0001 中「复杂任务的中间执行过程交由 Orca 管理」的条款，取代 ADR 0003 全篇「DS-Bot 作为常驻入口宿主」的前提，取代 ADR 0007 中引用 ADR 0003 的 N100 与 DS-Bot 前提，取代 ADR 0008 的「自建 `agent:local` 运行时 + 生成式 UI 工作台」结论。

ADR 0002（付款、删除、对外发布三处确认点）、ADR 0004（草稿层 TTL）、ADR 0005（提案影子晋升）、ADR 0006（工作站改用 Windows）与 ADR 0010（交互层回到 DSH 原生会话）不予取代。0010 与本 ADR 同向，但它处理的是交互层的去留，本 ADR 处理的是编排与执行层归谁，两者不重叠。

被取代的旧 ADR 正文不改，冲突之处以本文为准。

## 4. 后果

S0 闭环重定义为四步，全部发生在会话内：`ev add` 建任务，leader 把任务派给子智能体，子智能体执行，`ev done` 带执行摘要写回任务库。派发由模型在会话里完成，不经过常驻进程；任务库只被读和写，不被自动消费。

不自建派发器。`evd` 既没有实现也没有部署计划，任何依赖「派发器常驻消费任务库」的设计都要重写；ADR 0007 里「工作站休眠时消息进云端等待队列，醒来后由派发器消费」一类描述，只有在不指 `evd` 时成立。

跨机任务图仍缺。`ds-harness-remote` 已提供 12 个 `remote_*` 工具，跨机远程操作是现成的；缺的是把任务节点跨机串成一张图、并在图上做派发与回收，这一块没有方案，属未确认。

丢掉的是四条线：自建 Worker 适配层、生成式 UI 工作台、DS-Bot 入口、`evd` 派发器，都不再投入。保留的是 `ar` 命令面、`runs/` 权威与 `events.jsonl` 数据面的设计，以及 Taskwarrior 任务库本身。

文档面尚未同步：`README.md`、`GLOSSARY.md`、`docs/system-topology.md` 仍在描述自建运行时与派发器。本 ADR 只定决策，改文档是后续批次的事。

## 5. 后续动作

批 1 改总体架构六处：`docs/architecture-north-star.md`、`docs/architecture.md`、`docs/system-topology.md`、`GLOSSARY.md`、`README.md`、`AGENTS.md`。这六处决定读者第一眼看到的是哪套系统，先改。

批 2 改执行侧六篇：自建运行时、控制面、事件面与 Worker 适配四类文档，把「设计中」「未部署」按实况标清，把已废止的机制从主叙述里摘掉。

批 3 删已废专题：工作台（`docs/workbench-ui.md`、`docs/prd-workbench-v3.md`）、DS-Bot 入口（`docs/ds-bot-entry.md`）、SuperAgent 与 DS-Bot 的合流研究（`docs/research/super-agent-dsbot.md`）等，避免留下指向空文档的链接。已执行：四篇删除，删除前的原文留在提交 `41fa2a1` 的历史里；仓库内正文与索引中的指向链接一并清理（改为事实陈述或整条移除）；ADR 0009 / 0010 正文中指向 `ds-bot-entry.md` 的链接随之失效，按「ADR 正文不改」的约定保留断链。
