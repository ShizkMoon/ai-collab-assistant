# Worker 非交互契约：pi / Claude Code / Codex

> 状态：设计中 · 上位文档：[agent:local 运行时设计](agent-local-runtime.md) §3（`agent` 字段）、[多 Agent 运行时](multi-agent-runtime.md)（信封与节点树） · 关联：[ADR 0008](adr/0008-local-agent-runtime.md)、[开源复用清单](open-source-reuse.md)
>
> 实测基线：2026-11-04，本机 Windows 工作站。**pi 1.5.0 已安装并实测**（`C:\Users\Administrator\AppData\Roaming\npm\pi.ps1`，以原生文件为准）；`ar` 已装于 `C:\Users\Administrator\.local\bin\ar.cmd`（以原生文件为准）。**codex 与 claude 本机未安装**（`Get-Command` = MISSING），其结论以官方文档与上游源码为据并标「待实测」。
>
> 本文只回答一件事：同一个信封把 `spec.json` 交给三种 Worker 时，**命令、事件、审批、失败**四件事各自长什么样，以及在差异存在的前提下如何保持 `runs/` 目录的可观测性与可审计性。

## 1. 一句话结论

三家的非交互能力都够用，差异不在「能不能跑」，而在**事件粒度**与**审批可观测性**：pi 的事件最细且可被我们自己的扩展补齐（可写 `gate` / `approve_ask` / `approve_decide`），Claude Code 有最完整的原生权限模型与 hook 面（`PreToolUse` / `PermissionRequest` / `PermissionDenied` / `PreCompact` 等），Codex 有唯一可机器校验的结构化输出（`--output-schema`）和唯一显式的「被拒」信号（`command_execution.status=declined`）。因此三家的定位应当按**谁负责产出、谁负责约束**来分，而不是按强弱排座次：**pi 是默认执行者，Claude Code 是重代码任务与交叉评审，Codex 是需要机器可校验产物的节点**。

## 2. 三家能力对照

### 2.1 对照表

| 维度 | pi（1.5.0，本机实测） | Claude Code（官方文档） | Codex CLI（上游源码） |
|---|---|---|---|
| **进程模型** | 单进程 CLI，`-p` 非交互；一个节点一个进程（[agent-local-runtime §2](agent-local-runtime.md)） | 单进程 CLI，`-p`/--print；另有 Agent SDK（Python/TS）可替代进程 | 单进程 CLI，`codex exec`；另有 app-server / MCP 模式 |
| **非交互入口** | `pi -p --mode json|text|rpc` | `claude -p "query"` | `codex exec [OPTIONS] [PROMPT]` |
| **结构化输出** | `--mode json`（会话事件流，非「结果 schema」） | `--output-format json`（单条 result，含 `total_cost_usd` 与分模型成本）；`stream-json` 为逐条事件 | `--json`（JSONL 线程事件）+ **`--output-schema <FILE>`**（按 JSON Schema 约束最终 agent_message） |
| **会话续接** | `--session-id <id>` + `--session-dir <dir>`；`--no-session` 临时；`--fork` / `--continue` / `--resume` | `--session-id <uuid>`、`--resume <id>`、`--continue/-c`；**`-c` 明确跳过 `claude -p` 创建的会话** | `codex exec resume <SESSION_ID>`、`resume --last`；`exec fork <id>` 分叉 |
| **会话 id 来源** | 调用方指定（daemon 固定 `--session-id aica`） | 调用方指定，或从 `system/init` 事件读 `session_id` | 从首条事件 `thread.started.thread_id` 读 |
| **工具面收窄** | `--tools/-t` 白名单、`--exclude-tools/-xt` 黑名单、`--no-tools`、`--no-builtin-tools` | `--tools`（限制可用内建工具，`""` 为全禁）、`--disallowedTools`（deny 规则，裸名即移除） | 沙箱策略 + `--ignore-user-config` / `--ignore-rules`；**无逐工具白名单** |
| **审批 / 权限** | 无原生逐调用审批；`--approve/-a` 仅管项目本地文件信任。逐调用闸门由扩展（我们的 `aica-pi/extensions/gate.ts`）实现 | 原生六档 `--permission-mode`：`default`/`acceptEdits`/`plan`/`auto`/`dontAsk`/`bypassPermissions`（`manual` 为 default 别名）+ hook `PermissionRequest` | `-s/--sandbox` 三档（`read-only`/`workspace-write`/`danger-full-access`）、`--approve-for-me`（自动审批评审）、`--dangerously-bypass-approvals-and-sandbox`（别名 `--yolo`） |
| **approval 细粒度** | 全靠扩展（tier × tool × target，见 `envelope.ts` 的 `GateGrant`） | hook 层可拿到工具名与入参，可做外部裁决 | `-c approval_policy=…` 配置项；具体枚举待实测 |
| **模型指定** | `--provider <name>` + `--model provider/id:thinking`、`--thinking <level>` | `--model`、`--effort`；provider 走 `ANTHROPIC_BASE_URL` / `ANTHROPIC_AUTH_TOKEN` / `ANTHROPIC_API_KEY` | `-m/--model`、`--profile/-p`（叠加 `$CODEX_HOME/<name>.config.toml`）、`--oss` + `--local-provider`（lmstudio/ollama）、`-c key=value` |
| **退出码** | 实测：正常结束 0；详见 §6（异常与服务退出需按 `result.json` 判定） | 文档口径：成功 0、失败非 0；坏 flag 在 run 前写 stderr 退出；run 内失败（如缺鉴权）会作为 result 打到 stdout。**具体码值未文档化，待实测** | **待实测** |
| **Windows** | 已在 Windows 10 上实测运行（`pi.ps1` 经 PowerShell） | 要求 Windows 10 1809+；推荐装 Git for Windows 以启用 Bash 工具，否则改用 PowerShell 作为 shell 工具 | **待实测**（历史版本在 Windows 上依赖 WSL，需按当前版本核对） |
| **启动开销** | 本机实测 CLI 极轻（`pi --version` 秒回） | 有 `--bare`：跳过 hooks / skills / 自定义命令 / plugins / MCP / 自动记忆 / CLAUDE.md，官方推荐脚本场景使用 | 有 `--ephemeral`（不落会话）、`--strict-config`、`--ignore-user-config` 降低环境差异 |

来源：
- Claude Code：[CLI reference](https://code.claude.com/docs/en/cli-reference)、[Run Claude Code programmatically](https://code.claude.com/docs/en/headless)、[Hooks reference](https://code.claude.com/docs/en/hooks)、[Environment variables](https://code.claude.com/docs/en/env-vars)、[Setup](https://code.claude.com/docs/en/setup)
- Codex：[codex-rs/exec/src/cli.rs](https://github.com/openai/codex/blob/main/codex-rs/exec/src/cli.rs)（`exec` 子命令与 `--json`/`--output-schema`/`resume`）、[codex-rs/utils/cli/src/shared_options.rs](https://github.com/openai/codex/blob/main/codex-rs/utils/cli/src/shared_options.rs)（`--sandbox`/`--approve-for-me`/`-C`/`--profile`）、[sandbox_mode_cli_arg.rs](https://github.com/openai/codex/blob/main/codex-rs/utils/cli/src/sandbox_mode_cli_arg.rs)（三档枚举）、[exec_events.rs](https://github.com/openai/codex/blob/main/codex-rs/exec/src/exec_events.rs)（JSONL 事件 schema）
- 官方站点 `developers.openai.com/codex/cli` 当前对本机抓取返回 403，故 Codex 一栏以上游源码为准；源码即实现，强于文档，但**版本会漂，引用需带 commit**（后文路径均为 `main` 分支，待锁定版本后补 commit hash）

### 2.2 现状差距（先看这一节）

现有启动器实现见 `C:\Repos\agent-local-runtime\src\daemon.ts:481-519`（以原生文件为准）。pi 分支已经把会话、工具面、profile、扩展、skills 全接上了；**claude 与 codex 分支目前只传了最小参数**：

| `agent` | 当前实际命令 | 缺什么 |
|---|---|---|
| `pi` | `node <pi> -p --mode json --session-dir <node>/session --session-id aica --no-extensions --no-context-files --no-skills --no-prompt-templates --no-mcp --model <m> --append-system-prompt <profile.md> --tools <allowlist> -e events.ts -e tools.ts -e gate.ts …` | 基本完备 |
| `claude` | `claude -p <goal> --output-format json` | 无 `--session-id`（**不能续接**）、无 `--tools`（**工具面全开**）、无 `--permission-mode`、无 `--bare`、无 `--append-system-prompt`、无 `--max-turns` |
| `codex` | `codex exec <goal> --json` | 无 `-s`（沙箱取默认）、无 `-C`、无 `--ignore-user-config`、无 `--output-schema`、无 resume 路径 |

结论：这两家在真机上**即使装好也还不满足节点契约**——续接、工具面收窄、审批档位三项全缺。本节即「装上之后第一件要改的事」清单。

## 3. 事件流 → `events.jsonl` 映射

### 3.1 闭集与现状

`kind` 闭集见 `C:\Repos\agent-local-runtime\src\envelope.ts:79`（以原生文件为准）：
`tool_call` / `tool_execution` / `agent_message` / `file_edit` / `message` / `checkpoint` / `spawn` / `exit` / `gate`，另有转写器与扩展追加的 `turn` / `turn_end` / `agent_end` / `agent_delta` / `tool_update` / `retry` / `compaction` / `abort` / `approve_ask` / `approve_decide` / `todo` / `loop` / `_raw`。

转写器 `C:\Repos\agent-local-runtime\src\transcribe.ts`（以原生文件为准）目前**只解析 pi 的 `--mode json` stdout**；`message_update` / `tool_execution_update` 被显式跳过（`SKIP` 集合），未识别行落 `_raw`。也就是说：**claude / codex 的 stdout 现在会整体落成 `_raw`**，UI 与 `kn` 召回对其不可见。

### 3.2 字段级映射

| `events.jsonl` kind | pi（现有实现） | Claude Code（`--output-format stream-json`） | Codex（`--json`） |
|---|---|---|---|
| `turn` | `turn_start` → `{i}` | `system/init`（会话元数据） | `turn.started` |
| `agent_message` | `message_end`(role=assistant) 摘要 | `assistant` 消息中的 text 块 | `item.completed` + `type=agent_message.text` |
| `message` | `message_end` 全文摘要 | 同上（原文可更长，需截断策略） | 同上 |
| `tool_call` | `tool_execution_start` → `{call_id, tool, args: 前 80 字}` | `tool_use` 块（含 `id`/`name`/`input`） | `item.started` + `type=command_execution`（**只有 command 串，无结构化入参**） |
| `tool_execution` | `tool_execution_end` → 结果前 300 字 | `tool_result` 块 | `item.completed` + `command_execution{aggregated_output, exit_code, status}` |
| `file_edit` | 由 `aica-pi/extensions/events.ts` 写（工具级） | **无原生事件**，只能从 `Edit`/`Write` 的 `tool_use` 入参推断（「推断」） | `item.completed` + `file_change{changes:[{path,kind}], status}` |
| `checkpoint` | `aica-pi` 扩展写 | 无（`--rewind` 相关能力待实测） | 无 |
| `todo` | 扩展写 | 无原生（task 工具事件待实测） | `item.*` + `type=todo_list` |
| `gate` / `approve_ask` / `approve_decide` | `gate.ts` 写（决策闭集） | 需用 `PermissionRequest` / `PermissionDenied` hook 在外侧落盘 | **无审批事件**，只有 `command_execution.status=declined` 这一个终点信号 |
| `turn_end` | `turn_end` → `{i, tokens, durationMs}` + `usage.json` turn 账本 | `result` 的 `usage`；turn 级需从 `stream-json` 的逐条消息累加（推断） | `turn.completed.usage{input_tokens, cached_input_tokens, cache_write_input_tokens, output_tokens, reasoning_output_tokens}` |
| `agent_end` | `agent_end{willRetry, aborted}` | 进程退出 + `result.subtype` | `turn.failed` / `error` |
| `_raw` | 解析失败行 | 未接入前整体 | 未接入前整体 |

### 3.3 明确会丢的信息

1. **审批的「提问侧」全丢（claude/codex）**。pi 能写 `approve_ask`（谁问、问什么、什么 tier）；Claude Code 只有在配置了 `PermissionRequest` hook 时才有等价物；Codex 只有 `declined` 这个**终态**——没有「什么时候问的、问的哪个工具、给了什么理由」。UI 上无法还原「这一轮在等什么」。
2. **工具入参的结构化程度不等价**。pi 的 `args` 是结构化对象截断；Codex 的 `command_execution` 只有拼好的命令串，非 shell 类工具（MCP / web_search）才带独立字段；Claude 的 `tool_use.input` 最完整。
3. **token 账本只有 Codex 与 pi 能对齐到 turn**。Claude 的 `-p --output-format json` 只给整轮总量（含 `total_cost_usd`），要 turn 级必须走 `stream-json` 并自行累加。
4. **delta 流不等价**。`agent_delta` 目前只对 pi 成立；claude 的部分消息需要额外开关（待实测），codex 的 `item.updated` 是离散更新而非流式 token。
5. **checkpoint 只有 pi**。另外两家的 rewind/fork 若要进 `runs/`，只能由 daemon 在节点目录做文件级快照（与现有 `fork` 路由同源）。

### 3.4 落地约束

- 转写器按 `agent` 分派三套 parser，**共用同一个 `EventRecord` 形状**，未知事件一律 `_raw`（已有兜底语义，不得静默丢弃）。
- 新增 kind 前先更新 `GLOSSARY.md` 与 [事件规格](event-spec.md)（仓库约定）；本文不新增 kind，映射只用现有闭集 + `_raw`。
- `events.jsonl` 是 UI 与 `kn` 的唯一数据面（[agent-local-runtime §4](agent-local-runtime.md)），**「某家拿不到的事件」必须在文档里写明，不许用空数组冒充「发生了但没有输出」**。

## 4. 审批语义差异与「只在派发点审批」

### 4.1 三家默认行为不同，这是最大的坑

| | 未显式配置时的默认 | 对无人值守 Worker 的后果 |
|---|---|---|
| pi | 无逐调用审批（闸门取决于是否加载 `gate.ts`） | 不加载扩展 = **无审批**，工具面由 `--tools` 决定 |
| Claude Code | `-p` 运行在未设置模式时，自 v2.1.302 起以 **Manual** 启动：需要审批的调用**直接被拒**除非 hook 或 `--permission-prompt-tool` 批准 | 天然 fail-closed，但**表现为「工具调用失败」**，若转写器不区分就会记成普通失败 → 见 §6 |
| Codex | 沙箱与 approval policy 取配置文件默认 | 结果依赖 `$CODEX_HOME/config.toml` 与 profile，**同一命令在不同机器上语义可以不同** → 必须显式 `-s` + `--strict-config`/配置基线 |

### 4.2 落地规则（建议直接写进 `aica-pi` 与 daemon）

1. **审批只在派发点发生**。`spec.json` 必须声明 `tier`（`read` / `write` / `exec`，与 `envelope.ts` 的 `ApprovalTier` 同源）；**未声明 = 拒绝派发**，不回落到 `read`。这与「约束来自能力不存在」一致：`tier` 决定 worker 拿到什么工具面，而不是运行时再拦。
2. **tier → 参数映射**（三家的表达方式不同，效果要对齐）：

   | tier | pi | Claude Code | Codex |
   |---|---|---|---|
   | `read` | `--tools` 只留只读集 + `--no-builtin-tools` 收紧 | `--tools "Read,Grep,Glob"`（或 `--permission-mode plan` 做纯规划） | `-s read-only` |
   | `write` | `--tools` 含编辑类 + `gate.ts` 记 grant | `--permission-mode acceptEdits` + `--disallowedTools` 覆盖危险 Bash | `-s workspace-write` + `approval_policy` 关闭交互 |
   | `exec` | `--tools` 含 exec + gate 逐调用 | `--permission-mode dontAsk`（无人值守）/ 明确不接受时拒派 | `-s danger-full-access`（仅在已外部隔离时） |

3. **`deny` 是硬拒，不参与重试**。三家的表达：pi 用 `gate.ts` 的直接拒绝（决策闭集 `rejected`）；Claude 用 `--disallowedTools` 的 deny 规则（裸名移除上下文；`Bash(rm *)` 只拒匹配调用）；Codex 靠沙箱边界（`read-only` 下写操作必然失败）。**同一份 `deny` 清单要在三家上分别落地**——目前它只存在于 `aica-pi` 的 gate 配置里。
4. **拒绝 ≠ 失败**。转写器必须把以下三种信号归一成 `gate` / `approve_decide` 语义，而不是 `exit` + 失败：
   - Codex：`command_execution.status = declined`（`false` 与 `failed` 分开，见 [exec_events.rs](https://github.com/openai/codex/blob/main/codex-rs/exec/src/exec_events.rs) 的 `CommandExecutionStatus`）；
   - Claude：`PermissionDenied` hook / result 中的拒绝文本（推断其可达性，待实测）；
   - pi：`gate.ts` 的 `rejected` / `unavailable`。
5. **fail-closed 的端点**：审批超时（默认 2min，[prd-workbench-v3](prd-workbench-v3.md) M1）一律按 `unavailable` 记，节点结局 `reason` 取「审批不可用」，不得重试成 `allowed`。

## 5. 失败与重试策略

| 失败类型 | 判定依据 | 动作 |
|---|---|---|
| 拉起失败 | spawn 返回 ENOENT（本机 `claude`/`codex` 未安装即为此类） | 不重试；`result.json` 写 `status=failed`、`reason="worker 不可用"`，并在 `exit` 事件里带 `code` |
| 传输/解析失败 | 有输出但无任何可识别事件 | 重试 1 次；仍是 `_raw` 则标 `reason="事件不可解析"` |
| 会话续接失败 | `--session-id` 指向不存在的会话 / `--resume` 目标缺失 | 降级为新建会话重跑（**pi**：同 id 会创建；**claude**：`--resume` 需存在 id，且 `-c` 不认 `-p` 建的会话，故续接必须显式传 `--session-id`/`--resume <id>`） |
| 被拒（审批） | 见 §4.2-4 | 不重试；升级到编排者，节点 `status=waiting` |
| 预算超限 | turn 级 tokens 超 `budget.tokens`（pi 已有 `usage.json` + `onTurn` 拦截） | 不重试；`reason="budget exceeded"` |
| 进程非零退出但产出了 `result.json` | 文件存在且 schema 合法 | 以 `result.json` 为准（进程退出码不可靠，尤其 claude 把 run 内失败写 stdout） |
| 超时 | 节点墙钟超 `budget.minutes` | 杀进程树，重试 1 次，第二次仍超时判失败 |

三条通用纪律：
- **重跑必须幂等**：`result.json` 原子写（tmp + rename），`events.jsonl` 追加，不覆盖历史；已有 `TurnUsage.attempt` 字段可直接复用为 attempt 序号。
- **退出码不是唯一真相**：claude 文档明说 run 内失败（如缺鉴权）会「作为 result 打印到 stdout」，此时退出码语义待实测；因此一律「有 result 读 result，无 result 看 exit 事件 + 最后一条 `_raw`」。
- **重试要换手**：同一节点连续两次失败后，第二次重试应改写 `agent` 字段换一家（例如 `pi` → `claude`），并把换手记进 `retry` 事件；这是「Worker 可替换」原则在失败路径上的用法。

## 6. 路由建议

按**成本 / 能力 / 可观测性**三维度，不建议按「模型强弱」排序：

| 节点类型 | 首选 | 理由 |
|---|---|---|
| 日常多步任务、GUI 自动化、需要审批闸门的写操作 | **pi** | 事件最细（`agent_delta`/`tool_update`/`gate` 全套）、会话挂节点目录可续接、工具面可裁到「能力不存在」、成本最低、可嵌 `pi-agent-core` 做编排者 |
| 长代码任务、大仓重构、需要 plan mode 的探索 | **Claude Code** | 原生六档权限 + 成体系的 hook（`PermissionRequest` / `PermissionDenied` / `PreCompact`）+ `--tools` 收窄，是最接近「可约束的通用 Worker」的一家；代价是启动开销与环境发现（用 `--bare` 收敛） |
| 要机器可校验产物的节点（JSON/报表/结构化抽取） | **Codex** | 唯一有 `--output-schema` 的一家；`turn.completed.usage` 的 token 账本最细（含 reasoning / cache write）；沙箱三档是硬边界 |
| 跨厂商交叉评审、二次意见 | **claude** 与 **codex** 互评，pi 汇总 | 不同实现给出不同错误，比同家自评有价值 |
| 端侧 / 受限设备 | **pi**（`--no-mcp --no-extensions` 精简 profile） | 单进程、可离线（`--offline`）、无重型运行时依赖 |
| 高频小节点（几十次/小时） | **pi** | 另两家每次启动成本与事件粒度都不划算；且 `claude -p` 默认 Manual 会让小任务频繁卡在「需要审批」 |

成本口径提醒：claude 在 `-p` 下 `ANTHROPIC_API_KEY` 存在时**始终优先于订阅**（[env-vars](https://code.claude.com/docs/en/env-vars)），若走 LiteLLM 网关要显式设 `ANTHROPIC_BASE_URL` 并接受「按 key 计费」；codex 的 provider 可通过 `--profile` + `-c` 覆盖，两家都能接 [模型路由器](model-fleet.md)，但**计费口径不同，路由表里要按 agent 分开记**。

## 7. 待实测清单（本机装好 codex / claude 后逐条验证）

**通用**
- [ ] `Get-Command codex, claude` 均存在；`codex --version` / `claude --version` 记录版本号（本文所有 Codex 源码引用需补 commit hash）
- [ ] 两者在 Windows PowerShell 下不经 WSL 直接可跑；codex 是否需要 WSL 在此确认

**Claude Code**
- [ ] `claude -p "say ok" --output-format json` → 记录退出码、`result`/`usage`/`total_cost_usd` 字段
- [ ] `--session-id <uuid>` 建会话 → 第二轮 `--resume <uuid>` 是否继承上下文（验证「节点级续接」）
- [ ] `-c` 对 `-p` 创建的会话是否真的跳过（文档口径需实证）
- [ ] `--tools ""` 与 `--tools "Read"` 的实际可用工具面；`--disallowedTools "Bash(rm *)"` 是否只拒匹配调用
- [ ] `--permission-mode dontAsk` 与 Manual 默认下，需要审批的调用分别如何表现（事件里是否出现 `PermissionDenied`）
- [ ] `--bare` 后启动耗时与是否仍加载 `~/.claude` 的 hooks
- [ ] `--output-format stream-json` 的事件序列与 `system/init` 字段（`session_id`/`model`/`tools`）
- [ ] 失败退出码：坏 flag、缺鉴权、工具全被拒，三种场景各自的退出码

**Codex**
- [ ] `codex exec "say ok" --json` → 首事件是否为 `thread.started{thread_id}`；`turn.completed.usage` 字段完整度
- [ ] `codex exec resume <thread_id> "继续"` 是否继承上下文；`--last` 语义
- [ ] `-s read-only` 下写文件的实际失败表现（是 `command_execution.status=failed` 还是模型侧被拒）
- [ ] `-s workspace-write` + `-c approval_policy=never` 的无人值守是否真正不阻塞
- [ ] `--output-schema schema.json` 的产物形状与 schema 违例时的表现
- [ ] `--ephemeral` / `--ignore-user-config` / `--skip-git-repo-check` 组合下的确定性
- [ ] 退出码语义（成功 / 模型拒答 / 沙箱拦截 / 网络失败）
- [ ] Windows 原生与 WSL 两种跑法的差异

**pi（已装，补齐回归基线）**
- [ ] `pi -p --mode json` 在 `--no-extensions` 下的 `_raw` 比例（确认转写器覆盖度）
- [ ] `--mode rpc` 的可用性（`steer` 真插话的前置，见 [agent-local-runtime §11.4](agent-local-runtime.md)）

---

> 索引登记（`README.md` 与[文档地图](architecture-north-star.md#11-文档地图)）由 Lead 统一补齐；本文新增概念仅 `tier → 参数映射` 一张表，未引入新术语，`GLOSSARY.md` 无需改动。
