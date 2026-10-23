# Personal Agent 设计

本文定义"个人 agent 系统"这一产品的形态：它不是一个 agent，而是一套**让多个 agent 长期稳定替你工作的制度**。参考本人 AIWORKSTATION 项目的架构方法（contracts/ADR/体验先行/不造轮子），但不照搬其 Rust Core + PostgreSQL 的重量级中心——我们的常驻中心是 Orca + 文档仓库，已够用。

## 与 AIWORKSTATION 的对照取舍

| AIWS 模式 | 借鉴 | 我们的取舍 |
|---|---|---|
| 边缘采集 → 常驻中心 → 工作台 | ✅ 三层职责骨架 | 边缘=设备/传感器，中心=工作站 Orca，工作台=Notion/墨水屏/Hermes |
| contracts/*.json 机器契约 | ✅ 思想：能力显式登记 | 轻量化：能力清单进 docs 表格 + skills/，不单开 schema 仓 |
| ADR 决策记录 | ✅ 直接沿用 | 本仓 docs 即 ADR，不再分目录 |
| 体验先行（a-day/a-week/a-month） | ✅ 先约定体验再反推功能 | 本文 §2 先做体验约定 |
| Coding 与 AIWS 独立失效 | ✅ 层间可替换原则 | Hermes/Orca/worker 任一停摆不拖垮其他层 |
| Rust Core + PG 中心 | ❌ 过重 | Orca Run/Task 已是任务账；不另造 Core |

## 体验约定（先约定，再反推）

1. **说了就有交代**：用户每个请求要么得到结果，要么得到明确的卡点说明——没有"已发出，无下文"。
2. **不必盯着**：派出去的任务自动监控到落定，完成自动来报；用户随时可以问"到哪了"。
3. **跨设备无感**：手机（Hermes）、电脑、墨水屏看板看到同一本任务账。
4. **越用越懂你**：每次任务落定产出任务记录，反哺路由与规则（AGENTS.md 演进）。
5. **可回退、可替换**：任何一个 agent/平台换掉，制度不变。
6. **隐私默认本地**：原始材料（聊天记录、文件、凭据）不出本机，云端只过任务简报与摘要。

## 系统分层（三层 + 记录层）

```
入口层   Hermes(云端,任何设备可达)        → 理解、路由、人格化交互、长期记忆
编排层   Orca(本机,唯一事实源)            → Run/Task/Dispatch/worker 生命周期
执行层   workers(Devin/Codex/re-toolkit 等) → 只做被派发的具体任务
─────────────────────────────────────────────
记录层   本仓 docs + AGENTS.md + 任务记录    → 制度、决策、复盘;与各层解耦
```

关键不变量：**编排层是唯一任务账**。Hermes 死了任务还在跑；worker 死了 Dispatch 还在账上可重派；本机重启后 Orca 可接管。这与 workstation flake 的"声明层是事实源"是同一思想——任务账是声明，终端状态是运行时。

## 能力登记（轻量契约层）

worker 能力显式登记，路由时按表选，不靠记忆：

| 能力件 | 形态 | 注册位置 | 覆盖域 |
|---|---|---|---|
| Devin/Codex worker | Orca Dispatch | orca-cli | 代码、文档、调研、长任务 |
| re-toolkit | nix 包 → MCP stdio | mcp_config.json | 固件/二进制/设备逆向（只读） |
| rea | npx MCP | mcp_config.json | 单二进制深度逆向 |
| agent-reach | skill | ~/.agents/skills | 全网信息路由 |
| cli-anything-* | skill | ~/.config/devin/skills | GUI 软件 harness(Calibre 等） |
| computer-use / orca-cli / orchestration | skill | 同上 | 桌面控制/编排协议 |

新增能力 = 三选一挂点：**标准工具 → nixpkgs-shizuku 包；agent 契约 → skill；运行时集成 → MCP 注册**。三者的取舍见 README 维护约定——这是"别的工具类同理"的落地规则。

## 任务生命周期（制度核心）

```
简报(brief)→ 路由 → Dispatch → 监控到落定 → 回答 + 任务记录
   ↑                                              ↓
   └────────── 反哺 AGENTS.md / 路由表 ←──────────┘
```

- **简报是最小下发单元**（目标/上下文/验收），不是逐条指令——已在 system-topology.md 固化。
- **落定才允许报**：worker_done 或证实的退出；超时/失联是检查点，不是终态。
- **任务记录是链路一部分**：实际路径、卡点根因、可复用做法——回流记录层，用于优化路由和 AGENTS.md。
- **worker 终端即放即清**：落定后 `worker-release`（已写入全局 AGENTS.md）。

## 记忆与知识分层

| 层 | 位置 | 性质 |
|---|---|---|
| 制度记忆 | 本仓 + `/data/Agent/AGENTS.md`（多 CLI 软链真源） | 跨会话、跨 agent 生效 |
| 项目记忆 | 各仓 AGENTS.md + README | 仓库作用域 |
| 任务记忆 | Orca Run/Task + 归档任务记录 | 生命周期=任务 |
| 人格记忆 | Hermes 侧（云端） | 偏好/习惯/关系，只摘要不下发 |

原则沿用：单一真源、作用域分层、可回退（见 principles.md）。

## 与宿舍全智能的衔接

Personal Agent 是"制度"，宿舍全智能是它最大的应用域：传感器事件进编排层 → 路由到执行（HA 动作/墨水屏渲染/agent 处理）→ 账落记录层。详见 [dorm-smart.md](dorm-smart.md)。
