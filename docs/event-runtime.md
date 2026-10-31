# 事件运行时与派发器

> 状态：设计中 · 上位文档：[总体架构设计](architecture-north-star.md)、[事件与任务规格](event-spec.md)
>
> 本文定义九态状态机的流转规则、派发器守护进程（`evd`）的模块结构、幂等重放机制以及运行监控方式。

## 0. 核心架构约束

| 约束项 | 具体规定 | 设计原因 |
|---|---|---|
| 单一状态存储 | 任务状态、线索（`thread`）、依赖、重试计数全部使用 Taskwarrior 字段表达，不引入第二个状态数据库 | 避免多数据库之间的状态同步开销 |
| 派发器唯一写回 | 状态流转统一由常驻守护进程 `evd` 执行；Taskwarrior Hook 仅负责向 Spool 目录追加事件文件，不在 Hook 内回调 `task` 命令 | Taskwarrior Hook 在 `task` 进程内同步执行，若在 Hook 内再次调用 `task` 会导致数据库锁死锁 |
| 执行器幂等可重入 | 每次派发生成确定性幂等键 `ev_id`，重复调用不得产生重复副作用 | 保障进程崩溃恢复、手动重放与 Hook 重复触发时的安全性 |

## 1. 规则表

### 1.1 配置格式

```toml
# rules/20-home.toml
version = 1
[defaults]
lane_parallel = 4          # 全局最大并发数
lease         = "30m"      # 默认执行租约时长，执行器可续期
gate_file     = "~/.local/state/aica/ev/gates.json"

[[rule]]
name  = "alert.critical"
order = 10                 # 跨文件按 order 升序；同文件内按定义顺序
match = { kind = "home.*.*", severity = "critical" }
to    = "me"
push  = { channel = ["ntfy:critical", "im"], bypass_dnd = true }
stop  = true

[[rule]]
name  = "home.rule"
order = 200
match = { kind = "home.*.*", reversible = "true" }
to    = "ha:script"
exec  = { script = "script.{obj}_{verb}" }   # {obj}/{verb} 提取自 kind 三段名

[[rule]]
name  = "video.make"
order = 300
match = { kind = "work.video.make", source = ["me", "cron", "ha"] }
to    = "agent:orca"
exec  = { skill = "hyperframes", lane = "batch" }
lease = "90m"

[[rule]]
name  = "feed.rollup"
order = 400
match = { kind = "info.feed.item", thread = "feed:*" }
aggregate = { by = "thread", window = "6h", mode = "rollup", emit = "info.feed.digest" }
to    = "agent:orca"
exec  = { skill = "agent-reach" }

[[rule]]
name  = "no.match"
order = 9999
match = { kind = "**" }
to    = "triage"           # 归入待分类队列，在每日早报中汇总
```

### 1.2 匹配谓词

| 谓词 | 匹配语义 | 实现方式 |
|---|---|---|
| `kind` | 点分三段命名；`*` 匹配单段，`**` 匹配任意多段 | `fnmatch` 转正则表达式并预编译 |
| `source` / `tag` / `thread` | 列表表示逻辑或（OR）；`thread` 支持通配符 `*` | 直接读取对应 UDA 字段 |
| `severity` | `info` / `warn` / `critical` | 读取 UDA `severity` |
| `reversible` | 标识操作是否可逆，决定能否自动执行 | 读取 UDA `reversible` |
| `lane` | `interactive`（交互） / `batch`（批处理） | 读取 UDA `lane` |
| `when` | 单行 Python 表达式，可访问 `payload`、`mode`、`egress` 三个变量 | 规则文件属于本地受控配置，直接通过 `eval` 求值 |
| `needs` | 执行前置依赖（如特定网络出口），未满足时转入 `parked` 并订阅对应 `system.*` 事件 | 见 [网络与设备组网 §5](network-fabric.md#5-出口策略如何被-agent-感知) |
| `gate` | 支持 `cooldown`、`rate`、`window` 限流策略，被抑制时记录 `sys.gate.suppressed` | 见 §1.5 |

为保持规则表直观易读，不支持正文正则匹配、多层嵌套布尔树或规则继承。

### 1.3 匹配顺序与终止条件

- 加载顺序：按文件名字典序（`00-` 至 `90-`）加载，文件内部按出现顺序排列；`order` 字段用于跨文件排序。
- 默认首个命中的规则生效并终止后续匹配；仅当显式设置 `stop = false` 时继续向下匹配（常用于派发执行的同时附加一条通知）。
- 未命中任何业务规则时由兜底规则路由至 `to = "triage"`，生成 `meta.triage.pending` 任务并在早报中汇总；人工确认分类后可作为候选规则提交至 [提案库](proposals/README.md)。
- 每次派发在运行记录中保存规则文件的 `sha256` 摘要，便于排障时定位当时生效的规则版本。

### 1.4 `thread` 聚合与串行控制

| 配置项 | 行为说明 |
|---|---|
| `aggregate.window` | 将时间窗口内同一 `thread` 的多条任务合并为一条父任务，子任务通过 `parent` 指向父任务 |
| `mode = "rollup"` | 窗口结束时生成一条指定 `emit` 类型的汇总任务，正文为各子任务的标题列表 |
| `mode = "inline"` | 不新建父任务，直接向该 `thread` 最新一条任务追加注解 |
| `serial = true`（默认） | 同一 `thread` 内部严格串行：前一条任务进入 `done` 或 `dropped` 前不派发下一条 |

聚合窗口的到期唤醒时间直接写入父任务的 `wait:` 字段，复用 Taskwarrior 原生延迟唤醒机制，不单独维护外部计时器。

### 1.5 流量门控（Gate）

```json
// ~/.local/state/aica/ev/gates.json（由 flock 文件锁保护，每小时清理过期项）
{"home.plug.power": {"hits": [1761987654, 1761991200], "suppressed": 3, "until": null}}
```

| 门控项 | 触发规则 |
|---|---|
| `cooldown = "6h"` | 最近一次放行后 6 小时内的后续触发直接抑制 |
| `rate = "3/1h"` | 滑动时间窗口内触发次数超限时抑制 |
| `window = "23:00-07:00"` | 在允许时间窗之外到达的任务转入 `parked` 状态，等待窗口开启 |
| 抑制记录 | 被抑制时写入一条聚合计数任务 `sys.gate.suppressed`（`wait:1h`），不发送即时推送 |
| 计数存储原因 | 若通过 `task completed end.after:` 查询历史计数，每次需全表扫描；使用独立 JSON 文件可将限流判断保持在 O(1) |

门控逻辑在守护进程 `evd` 内部执行，不在 Taskwarrior Hook 同步路径上运行。

## 2. 状态机

### 2.1 九种状态定义

| 状态 | Taskwarrior 字段表达 | 进入条件 | 离开条件 | 写入方 |
|---|---|---|---|---|
| `new` | `status:pending`，无 `start` | `ev add` 或外部采集写入 | `evd` 认领派发 | 任意入口 |
| `doing` | `pending` + `start` | `evd` 执行 `task <id> start`（兼作租约起点） | 执行器返回结果，或超时被标为 `stalled` | `evd` |
| `waiting` | `status:waiting` + `wait:` | 执行器返回 `waiting`、人工选择延后、或处于聚合窗口内 | 到期后由 Taskwarrior 自动转回 `pending` | 任意 |
| `blocked` | `pending` + `depends:<uuid>` | 拆分子任务（`split`）或存在前置任务依赖 | 前置任务完成后自动解除阻塞 | `evd` |
| `escalated` | `pending` + `+me`（可选 `priority:H`） | 执行器返回 `me`，或规则配置 `to = "me"` | 人工点击卡片 `[执行] / [延后] / [忽略]` | 人工 / 卡片 |
| `failed` | `pending` + `+failed` + `uda.attempts` | 执行器返回 `failed` 或超时重派 | 重试成功后移除 `+failed` 标签 | `evd` |
| `stalled` | `doing` + `+stalled` | 看门狗检测到 `start.age > 2 × lease` | 人工或自动重置回 `new` | 看门狗 |
| `spec` | `pending` + `+spec` + `wait:<ttl>` | 预生成草稿或待补充规格说明 | 人工采纳转 `done`；放弃或到期转 `dropped` | 执行器 / 人工 |
| `parked` | `waiting` + `wait:<远未来>` + `+parked` | 通知模式静音、前置环境依赖（`needs`）未满足、或规则连续失败熔断 | 手动恢复，或收到对应的 `system.*` 恢复事件自动解除 | `evd` |

任务的终态对应 Taskwarrior 原生的 `completed`（即 `done`）与 `deleted`（即 `dropped`）。

```
new ──► doing ──► done
 │        │ └──► failed ──(retry)──► new
 │        └──► stalled ──► new
 ├──► waiting ──(到期)──► new
 ├──► blocked ──(依赖完成)──► new
 ├──► parked ──(条件恢复)──► new
 ├──► escalated ──[执行]──► doing / [延后]──► waiting / [忽略]──► dropped
 └──► spec ──(采纳)──► done / (过期或放弃)──► dropped
```

### 2.2 状态映射设计说明

- **`blocked` 复用原生 `depends`**：Taskwarrior 原生会将存在未完成依赖的任务排除在 `next` 视图之外，前置任务完成后自动解除阻塞，并可直接通过 `task +BLOCKED` 查询。
- **`escalated` 使用 `+me` 标签表达**：等待人工处理的任务本质上仍属于 `pending` 状态，使用标签表达可直接复用 Taskwarrior 内置的报表、同步和过滤能力。
- **`spec` 附带过期时间（TTL）**：预生成的草稿或待确认规格若在 TTL 内无人处理则自动清理，避免任务库堆积陈旧草稿（与 [总体架构设计 §2](architecture-north-star.md#2-核心数据流) 的草稿层对应）。

## 3. 派发器守护进程（`evd`）

### 3.1 模块划分

```
~/.local/lib/ev/            # 约 700 行 Python 3.12，仅依赖标准库
  hook.py       60   on-add / on-modify：将变更写入 Spool 目录并原样回显
  rules.py     120   加载 TOML、预编译通配符、规则匹配、聚合窗口处理
  gates.py      50   cooldown / rate / window 限流控制
  daemon.py    220   Spool 消费循环、并发通道（Lane）调度、租约管理、写回 Taskwarrior
  executors.py 180   orca / ha / cli / n8n / notify / me / triage 执行器适配
  status.py    120   ev status 与 ev doctor 终端状态输出
  __main__.py   80   CLI 入口
```

派发器以单进程 `evd.service`（工作站上的 `systemd` 用户服务，`Restart=always`）运行。任务库与 `evd` 均部署在工作站本地：工作站休眠期间外部任务在 N100 入口暂存排队，N100 离线也仅影响远端入口，不影响工作站本地任务流转（见 [网络与设备组网 §4](network-fabric.md#4-失效阶梯)）。进程间队列直接采用本地 Spool 目录配合 `flock` 文件锁实现。

### 3.2 Hook 规范

```sh
#!/bin/sh
# ~/.config/task/hooks/on-add.ev.sh：为 Taskwarrior Hook 增加 3 秒超时保护
exec timeout 3s ev hook on-add
```

```python
# on-modify 必须将修改后的第二行 JSON 原样写回 stdout，否则 Taskwarrior 会报错回滚
def on_modify():
    orig, mod = sys.stdin.readline(), sys.stdin.readline()
    spool.append("modify", orig, mod)      # 单次 O_APPEND 追加写入，耗时 < 1ms
    sys.stdout.write(mod)
```

| 约束项 | 具体要求 |
|---|---|
| 执行耗时上限 | p99 < 5ms，确保日常执行 `task add` 无体感延迟 |
| Hook 内禁止的操作 | 禁止回调 `task` 命令（会触发锁死锁）、禁止发起网络请求、禁止调用模型或拉起耗时子进程 |
| 异常处理策略 | 超时或异常时一律原样输出输入 JSON（Fail-open），错误信息追加记录至 `~/.local/state/aica/ev/hook.err` |

### 3.3 幂等控制与事件重放

每次任务派发依次落盘三份记录：

| 记录阶段 | 存储位置 | 写入时机 |
|---|---|---|
| 待处理输入 | `spool/<ev_id>.json`（原始任务 JSON + 命中规则名 + 规则文件哈希） | 守护进程消费前 |
| 执行器输出 | `runs/<ev_id>.json`（返回状态、执行摘要、退出码、stderr 尾部 4KB） | 执行器返回后，**先于** Taskwarrior 写回 |
| 任务库归档 | Taskwarrior 任务注解 `ev:<ev_id>` | 状态写回任务库时 |

- **确定性幂等键**：`ev_id = uuid5(task.uuid, rule.name, attempt)`，同一任务在同一规则下的同一次尝试始终生成相同的 ID。
- **手动重放**：执行 `ev replay --since 2h --rule video.make` 时，自动跳过 `runs/` 目录中已存在结果或任务库中已有对应 `ev:<ev_id>` 注解的任务。
- **崩溃恢复处理**：若 `spool/` 中存在记录而 `runs/` 中无结果，说明崩溃前可能已触发执行；为避免高耗时任务（如 20 分钟的视频渲染）重复执行，默认不自动重跑，由 `ev doctor` 列出交由人工裁决。
- **执行器侧幂等**：Orca 使用固定 Worktree 名称去重，CLI 工具添加 `--if-not-exists` 参数，Home Assistant 调用幂等的 `scene.turn_on` 服务。

### 3.4 执行器输入输出协议

```text
输入: Taskwarrior 导出的单条任务 JSON + 环境变量 {EV_ID, RULE, LANE, ATTEMPT}
输出: 标准输出单行 JSON
```

```json
{"status":"done",   "summary":"成片 3:41 已导出至 /data/aica/out/vlog-1101.mp4","attach":["…"]}
{"status":"waiting","summary":"等待 22:30 后确认配乐","wake":"2026-11-01T22:30+08:00"}
{"status":"me",     "summary":"需本人完成实名认证","card":{"执行":"","延后":"6h","忽略":""}}
{"status":"blocked","summary":"等待前置构建任务完成","blocked_by":["3f1c…"]}
{"status":"failed", "summary":"ffmpeg 退出码 1","retry":"15m"}
{"status":"split",  "summary":"拆分为视频渲染与配乐生成两个子任务","children":[{"kind":"work.music.compose","subject":"生成配乐"}]}
{"status":"spec",   "summary":"已生成初稿，等待审阅确认","ttl":"24h"}
```

当返回 `failed` 时，`evd` 自动追加失败原因注解并更新 `attempts += 1` 与 `+failed` 标签；当 `attempts >= 3` 时自动升级为 `escalated`（`+me`）交由人工处理。

### 3.5 长耗时异步任务

- 路由至 `to = "agent:orca"` 的任务采用**异步投递模式**：`evd` 创建 Orca Run 并将 `run_id` 写入任务注解后立即返回，任务状态保持为 `doing`。
- Worker 执行完毕后主动调用 `ev done <id> "<执行摘要>"` 或 `ev fail` 写回状态，`evd` 无需轮询 Orca。
- **租约监控**：任务处于 `doing` 状态的时长超过 `2 × lease` 时，看门狗为其添加 `+stalled` 标签并发出告警，不强行中断可能仍在运行的 Worker。
- **动态续租**：执行器可输出 `{"status":"doing","lease_next":"20m"}` 延长租约，`evd` 收到后刷新租约时间戳。

## 4. 并发控制与顺序保证

| 场景 | 实现机制 |
|---|---|
| 同 `thread` 内部串行 | 维护 `thread → asyncio.Lock` 映射表；`evd` 派发前先获取对应 `thread` 锁，不同 `thread` 之间完全并行 |
| 跨 `thread` 并发配额 | 全局并发上限 `lane_parallel`（默认 4），其中批处理通道（`batch` lane）独立配额（默认 2） |
| Taskwarrior 文件锁竞争 | Taskwarrior 3 写入时锁定数据目录；所有写操作统一经过 `tw()` 包装函数，配合 `flock` 与最多 4 次指数退避重试 |
| 人工直接执行 `task` 命令 | 允许人工直接操作 CLI；`on-modify` Hook 将变更写入 Spool，`evd` 读取后同步内部状态而不覆盖人工修改 |
| 乱序事件处理 | 同一 `thread` 内的任务按创建时间 `entry` 排序；若外部信号携带时间戳 `signal.t`，丢弃晚到的旧状态信号 |

```python
def tw(*args, tries=4):
    for i in range(tries):
        with flock(WLOCK):
            p = subprocess.run(["task", *args], capture_output=True, text=True, timeout=30)
        if "lock" not in (p.stdout + p.stderr).lower():
            return p
        time.sleep(0.15 * 2**i + random.random() * 0.1)
    raise TWFail(p.stderr[-400:])
```

## 5. 运行状态监控与看门狗

系统不额外维护常驻的 Watchdog Agent 会话（对比 [Super-agent 参考架构 §6](super-agent-architecture.md#6-watchdog)），而是通过 `systemd.timer` 定期运行无状态检查脚本，将异常情况作为 `system.*` 任务写入任务库。

### 5.1 `ev status` 终端概览

```
QUEUE      spool 12 / 最老 3.4m
LANES      interactive 2/4   batch 1/2
RUNNING    #12f3 video.make   doing  41m/90m        ← 超过租约标红提示
ESCALATED  3 件（2 件 >24h）   最早: #b21 域名续费
WAITING    17 件，最近唤醒 21:00
FAULTS     video.make 1h 内失败 3 次（已熔断）
SOURCES    ha 42s ago  n8n 6m  mail 3d(超时!)  rss 11m
GATES      home.plug.power 已抑制 4 条，至 22:10
```

状态面板直接聚合 Taskwarrior 自定义报表与 Spool 目录计数。对应的 `.taskrc` 配置如下：

```ini
uda.kind.type=string
uda.source.type=string
uda.thread.type=string
uda.parent.type=string
uda.payload.type=string
uda.severity.type=string
uda.reversible.type=string
uda.attempts.type=numeric
uda.lane.type=string
report.evboard.columns=id,status,start.age,kind,thread,priority,due.countdown,description
report.evboard.labels=ID,St,Age,Kind,Thread,Pri,Due,Subject
report.evboard.filter=status:pending or status:waiting
report.evboard.sort=urgency-,due+
report.faults.columns=id,kind,uda.attempts,modified.age,description
report.faults.filter=+failed or +stalled
report.faults.sort=modified-
```

### 5.2 看门狗巡检项（`ev-watchdog.timer`，每 5 分钟执行）

| 检查项 | 判定阈值 | 触发动作 |
|---|---|---|
| 任务执行超时 | `start.age > 2 × lease` | 添加 `+stalled` 标签并创建 `system.task.stalled` 任务 |
| 规则连续失败 | 同一 `kind` 1 小时内失败 ≥ 3 次 | 将该规则临时熔断（后续任务转入 `parked`）并创建 `system.exec.flapping` |
| 事件源静默 | 超过数据源声明的 `max_silence` 未收到新任务 | 创建 `system.source.silent` 告警任务 |
| Spool 队列积压 | 待消费文件 > 50 且最早文件驻留 > 10 分钟 | 创建 `system.ev.backlog` |
| 门控长期抑制 | 同一门控规则连续抑制达 24 小时 | 创建 `system.ev.gate_stuck` |
| 工作站离线唤醒 | `tailscale ping ws` 失败 > 10 分钟且批处理队列非空 | 发送 WoL 唤醒包，最多重试 3 次 |
| 磁盘空间不足 | 根分区可用空间 < 10% | 创建 `system.disk.low` |
| 备份复制滞后 | Litestream 同步延迟 > 10 分钟 | 创建 `system.ledger.stale` |

### 5.3 状态灯指示规则

| 灯光状态 | 触发条件 |
|---|---|
| 熄灭 | 无待处理任务 |
| 绿色呼吸 | 仅有 `doing` 任务正在后台执行 |
| 琥珀色常亮 | 存在 `escalated` 待确认任务，且无 `critical` 级别事项 |
| 红色常亮 | 存在 `severity:critical` 的紧急任务 |
| 红色闪烁 | 存在未处理的 `failed` 或 `stalled` 故障任务 |

手机与手表桌面组件仅展示单个数字：`escalated` 与 `critical` 任务的合计数量。

## 6. 开源复用与自建边界

| 功能需求 | 选用方案 | 自建或取舍说明 |
|---|---|---|
| 任务存储、依赖、周期与同步 | Taskwarrior 3 | 直接复用 |
| 本地事件队列 | 文件系统 Spool 目录 + `flock` | 单机单用户场景无需引入 Redis 或 NATS |
| 并发控制 | Python `asyncio` + 按 `thread` 加锁 | 并发上限为 4，无需引入 Celery / Prefect |
| 状态观测 | Taskwarrior 自定义报表 + `systemd.timer` | 命令行可查，无需单独为任务队列维护监控大盘 |
| 状态机表达 | Taskwarrior 原生 `status`、`tags` 与 `depends` | 保持单一数据源 |
| **自建部分** | 规则匹配、幂等控制与执行器适配层（`ev` / `evd`） | 需对接本机 Orca、Home Assistant 与自定义 CLI，整体约 700 行 Python |
