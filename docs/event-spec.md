# 事件规格（实现契约）

> 状态：设计中 · 层级：L1 的技术契约 · 设计与取舍见 [架构总览](architecture.md)

架构总览回答"为什么、是什么"，本文回答"长什么样、怎么校验"。任何实现对不上本文 §9 的校验清单，就不算这套制度的一部分。

## 0. 读法

本文所有条目分两类，不许混：

- **必须（MUST）**：违反即实现不合格。
- **建议（SHOULD）**：偏离需在实现处写明理由。

## 1. 命名

### 1.1 两个域，别混

| 字段 | 回答 | 谁定 | 用途 |
|---|---|---|---|
| `source` | 从哪条管道进来 | 传输层 | 信任等级、配额、预过滤 |
| `kind` | 归谁管 | 策略层 | 规则匹配、记录去向 |

两者可以不同：B 站评论从 `platform` 进来，归 `work` 管。**判定只看 `kind`，信任与配额只看 `source`**。

`source` 取值封闭：`home` / `system` / `person` / `agent` / `platform` / `sched`。新增须改本文。信任等级由 `source` 派生，映射表见 §1.3。

`kind` 的域封闭：`home` / `system` / `work` / `study` / `life` / `meta`。

### 1.2 kind 语法

`<域>.<对象>[.<子对象>].<信号>`，3–4 段。

- 字符集 `[a-z0-9_]`，点分隔，总长 ≤ 64。
- 对象用单数名词：`disk`、`bedroom`、`class`、`book`。
- 信号是**被观测到的事实**，不是命令：`exceeded`、`opened`、`requested`、`received`。
- 参数一律进 payload，不进 kind。

| 好 | 坏 | 原因 |
|---|---|---|
| `home.bedroom.motion` | `home.bedroom.motion_threshold_3` | 参数混进类型 |
| `system.disk.pressure` | `disk_full` | 缺域，且是结论不是事实 |
| `study.class.upcoming` | `Study.Class.Upcoming` | 大小写不统一 |
| `work.repo.ci_failed` | `work.ci` | 信号缺失 |

### 1.3 来源到信任的映射

| `source` | `trust` | 说明 |
|---|---|---|
| `system` | `trusted` | 本机定时、systemd |
| `person` | `trusted` | 本人在本机或已认证入口发起；手机未认证时按 `untrusted` |
| `sched` | `trusted` | 由本人创建的定时 |
| `home` | `untrusted` | 自家传感器也可能被伪造/误报；只影响是否放行写动作 |
| `agent` | `untrusted` | worker 产出不能自证；它要写世界，同样走确认 |
| `platform` | `untrusted` | 外部平台、邮件、群聊 |

只有两档是有意的。中间档（`local` / `external`）在实践里没有产生过不同行为——都需要人确认，只是说法不同。规则只能**下调**，不能上调。

### 1.4 演进

- 新 kind 必须先在规则包里 `[[kind]]` 声明，否则入账为 `meta.kind.unknown`（仍然入账，不丢）。
- 停用的 kind 标 `deprecated`，保留 90 天。
- **改名 = 新 kind + 映射表**。禁止原地改语义——账里已有的事实不能变义。

## 2. 信封校验

| 字段 | 必填 | 由谁写 | 校验 |
|---|---|---|---|
| `id` | 是 | `eventd` | UUIDv7，不可复用 |
| `ts` | 是 | 源 | 允许偏差 ±24h，超出记 `clock_skew` |
| `ingest_ts` | 是 | `eventd` | 单调不减；相等时按写入序 |
| `source` / `kind` | 是 | 源 | 符合 §1 |
| `subject` | 是 | 源 | 非空字符串 |
| `severity` | 是 | 规则（最终值） | 源可建议，不可定 |
| `trust` | 是 | 由 `source` 派生 | `trusted` / `untrusted`，见 §1.3、§3 |
| `payload_ref` / `payload_hash` | 是 | 源 | 文件存在且哈希一致 |
| `dedupe_key` + `bucket` | 是 | 源或 `eventd` | 唯一约束 |
| `state` | 是 | **仅 `eventd`** | 见 [架构总览 §10](architecture.md) |
| `thread_id` / `parent_id` | 否 | 源 | 指向已存在事件 |
| `urgency` | 是 | 规则 | `immediate` / `timed` / `digest` / `silent`；决定递送 |
| `valid_until` | `timed` 类必填 | 源或规则 | 过期转 `expired`，不计入逾期 |
| `deadline` / `timeout` | 由规则填 | 规则 | 缺省见 §5.3 |

三条硬约束：

1. **只有 `eventd` 能写 `state`**。处置方提交的是"状态变更请求 + 回执"，由账记录后落定（不核对内容）。这是不变量 4 的执行机制，不是风格。
2. **`ingest_ts` 是唯一权威时间**。所有计龄、SLA、排序都用它；`ts` 只做展示。
3. **不可修改**。录错了不改原行，追加 `meta.event.corrected`（payload 指向原 `id` 与更正内容），原事件保持原样。

## 3. 输入信任（一条闸门，不是流程）

只有一个用途：**外部来的内容不能直接触发对世界的写操作**。

| 等级 | 来源 | 能做什么 |
|---|---|---|
| `trusted` | 本机脚本、systemd、自建 cron、已认证的本人入口 | 全部动作 |
| `untrusted` | 平台消息、邮件、群聊、网页抓取、第三方 agent | 只能只读与提醒；写动作必须转给人 |

两条执行规则：

- 派发前查一次，不满足即 `escalated`。这是唯一位置，不散落到各 handler 内部。
- 规则**不能**把 `untrusted` 提升。要可信，走"人确认后转 `trusted` 事件"，不是给平台贴标签。

刻意没有的东西：按动作类别 × 信任分的权限矩阵、能力与信任的运行时交集、每次调用的重校验。这些不提升安全性（闸门只有一道，多查几遍还是查同一件事），只增加调用成本。

## 4. 规则规格

### 4.1 文件

`$AGENT_DATA/policy/rules/<域>.toml`，一个域一个文件。加载时全量 lint，任一失败拒绝启动。

### 4.2 结构

```toml
[[kind]]                     # 声明本包收哪些 kind
pattern = "home.*.*"
note = "宿舍传感器"

[[rule]]
id        = "disk-pressure"                    # 全局唯一，稳定不改
match     = { kind = "system.disk.pressure" }
when      = { field = "used_pct", op = "ge", value = 90,
              hysteresis = 3, cooldown = "6h", edge = "rising" }
action    = "notify"                            # notify | dispatch | confirm | drop
handler   = "human"                             # rule | agent | human
channel   = ["digest"]
deadline  = "24h"
timeout   = "1h"
emit      = false                               # 默认不派生事件
reason    = ""                                  # action=drop 时必填
```

### 4.3 谓词白名单

只允许这些，且有界：

| 类别 | 谓词 | 说明 |
|---|---|---|
| 比较 | `eq ne gt ge lt le in matches prefix exists` | 对 payload 字段做类型化比较 |
| 边沿 | `edge` + `hysteresis` + `cooldown` | 电平量必须带这三项 |
| 时间 | `window = "07:00-23:00"`、`weekday = "mon-fri"` | 用本机时区 |
| 频次 | `rate = { count = 5, per = "1h" }` | 超出即降级为摘要 |
| 聚合 | `for = "10m"` | 条件需持续满足 |

禁止：任意脚本、外部调用、网络、模型。**规则是纯函数**，同样的 `(kind, payload 快照, 规则包版本)` 必须得到同样结果。

### 4.4 求值与冲突

1. 按具体度排序：`rule_id` 显式 > `kind` 精确 > `kind` 通配 > 域默认 > 全局兜底。
2. 同具体度两条命中 → **拒绝启动**（fail closed）。
3. lint 必须报告：shadow（永远不命中）、unreachable（被更具体规则全覆盖）、unbounded（`cooldown` 或 `rate` 缺失的阈值规则）。

## 5. 处理器契约

### 5.1 调用

```text
stdin  : { "event": <信封>, "brief": <简报或 null>, "attempt": 1,
           "idempotency_key": "<event.id>" }
stdout : { "status": "done|deferred|escalated|rejected",
           "summary": "<一句话>",
           "refs": [ <回执引用，可选> ],
           "wake_at": "<仅 deferred>" ,
           "reason": "<仅 escalated/rejected>" }
```

环境：**不注入任何凭据**；只给 `PATH`、`$AGENT_DATA` 与任务工作目录。需要凭据时走本地 broker（见 [助理系统架构](assistant-system.md)），处理器拿到的是一次性句柄。

### 5.2 退出码

| 码 | 含义 | 映射 |
|---|---|---|
| 0 | 完成 | 记回执，置 `resolved`（不校验内容） |
| 10 | 条件未到 | 转 `deferred`，必须给 `wake_at` |
| 20 | 需要人 | 转 `escalated` |
| 30 | 拒绝执行（越权/不适用） | 转 `escalated`，记原因 |
| 其他 | 失败 | 重试至 `attempt` 上限，然后 `escalated` |

超时与退出码分开：超时由 `eventd` 判，不依赖处理器自觉。

### 5.3 时限

升级阶梯（每一级都必须能停机，不做连续追赶）：

| 级别 | 何时 | 动作 | 谁看到 |
|---|---|---|---|
| L1 | 首次超时 | 转 `deferred`，写 `wake_at` | 无人 |
| L2 | `deadline` 到达 | 进 digest | 晨间/夜间摘要 |
| L3 | 未落定 72h | 强制 `escalated`，即时通知 | 即时通道 |
| L4 | 逾期且同类 ≥ 3 条 | 合并为一条 `meta.pattern.stalled` | 即时通道，附规则候选 |

L4 的存在是为了让人不必逐条处理——同一类事反复卡住时，问题通常在规则，不在事件。

| handler | `timeout` 缺省 | 依据 |
|---|---|---|
| `rule` | 60s | 确定性动作应瞬时 |
| `agent` | 30min（长任务由规则显式放宽） | 超时后转 deferred 而不是杀 |
| `human` | 不设 | 由 `deadline` 计龄，72h 强制升级 |

## 6. 执行记录（不是校验）

这一节存在的理由要说清楚：**执行抽象层不做正确性校验**。

理由有三条：

1. **成本线性，收益为零**。校验越多，每个 handler 的实现负担越重，而机器能查的只有形式（有没有 artifact、退出码是不是 0），形式对了结果可能仍然错。
2. **它教坏执行者**。一旦 `resolved` 需要证据，agent 会生产能过检查的证据，而不是正确的结果。这是 Goodhart 定律，而且是设计者亲手设的激励。
3. **正确性只有人知道**。"这个修复对不对"不在任何 schema 里。能自动化的是**存在性与可追溯性**，不是对错。

所以这里定义的是**记录**，不是门禁。记录永远接受，永不阻塞。

### 6.1 一条记录

`resolve` 时随 `summary` 附一张**回执**（receipt）：

```json
{ "summary": "修复了 CI 失败：依赖版本冲突",
  "refs": [                      // 可选，但强烈建议
    { "kind": "commit",   "value": "a1b2c3d" },
    { "kind": "command",  "value": "cargo test", "exit": 0 },
    { "kind": "path",     "value": "/path/to/report.md" },
    { "kind": "message",  "value": "im:1234567" }
  ] }
```

校验只有三条，全部是**语法**：

| 检查 | 目的 |
|---|---|
| `summary` 非空 | 人和将来的自己能看懂 |
| `refs.kind` 在枚举内 | 保证可被检索与展示 |
| 有值的路径存在 | 防止记录指向不存在的东西 |

不做的事：不重跑命令、不比对哈希、不判断 `refs` 是否足以证明结论、不因 `refs` 缺失而拒绝。**`refs` 为空也接受**，只是这条记录在回看时价值低，由周报统计出来给人看。

### 6.2 为什么仍然要有 `refs`

不是为了校验，是为了**三个月后还能回答"当时凭什么这么判断"**。这是账的意义（[架构总览 §0](architecture.md) 的"发生过但没人记得"），而不是对执行者的审查。

区别体现在：`refs` 偏好"指向外部可查的东西"（提交、消息 id、PR、文件），而不是"机器能验的东西"。前者对人的复盘有用，后者只对门禁有用。

### 6.3 已删除的机制

这一版刻意删掉，不再出现：

| 删掉 | 原因 |
|---|---|
| `checker` 重跑与 `ev verify` | 重跑一次命令证明不了结果对，只证明命令能跑 |
| 每个 handler 的最低证据表 | 把"该交什么"变成填空题，诱导凑数 |
| 证据类型必须齐全才允许 `resolved` | 阻塞真实工作，换不来正确性 |
| 能力 × 信任的运行时交集 | 闸门只有一道（§3），重复检查不增加安全 |
| 证据进周报的"合规率" | 合规率是可刷新的指标，没有信息量 |

留下的只有：**人可以不写，写了就得是真的**。真实性靠两件事——`kind` 枚举限制了能写什么，路径存在性挡住了明显的假引用。其余交给人的判断。

### 6.4 源心跳（这条保留）

事件系统只能对收到的事件反应，对"该来没来"没有反应。这是唯一值得在基座层强制的定时检查：

每个 `source`（以及每个 device 类 `subject`）声明 `max_silence`。`ev-watch` 定期查 `MAX(ingest_ts) GROUP BY source`，超时产出 `system.source.silent`。

| source | `max_silence` 建议 |
|---|---|
| `system` | 1h |
| `home` | 6h |
| `platform` | 24h |
| `person` | 不设（人可以不说话） |
| `sched` | 最近一次调度时刻 + 2h |
| `agent` | 不设（无任务时本来就没有） |

它属于基座：检查的是"管道是否还通"，不是"结果是否对"。这两者的区别就是本轮修改的全部内容。

## 7. 账本 schema

```sql
PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;

CREATE TABLE events (
  id           TEXT PRIMARY KEY,
  ts           TEXT NOT NULL,
  ingest_ts    TEXT NOT NULL,
  source       TEXT NOT NULL,
  kind         TEXT NOT NULL,
  subject      TEXT NOT NULL,
  severity     TEXT NOT NULL CHECK (severity IN ('info','notice','action','critical')),
  trust        TEXT NOT NULL CHECK (trust IN ('trusted','untrusted')),
  domain       TEXT NOT NULL,
  payload_ref  TEXT NOT NULL,
  payload_hash TEXT NOT NULL,
  dedupe_key   TEXT NOT NULL,
  bucket       TEXT NOT NULL,
  edge         TEXT CHECK (edge IN ('rising','falling','sample')),
  corr_id      TEXT,
  thread_id    TEXT REFERENCES events(id),
  parent_id    TEXT REFERENCES events(id),
  state        TEXT NOT NULL,
  urgency      TEXT NOT NULL DEFAULT 'digest'
               CHECK (urgency IN ('immediate','timed','digest','silent')),
  valid_until  TEXT,
  deadline     TEXT,
  rule_id      TEXT,
  task_ref     TEXT,
  spec         INTEGER NOT NULL DEFAULT 0,
  UNIQUE (dedupe_key, bucket)
);

CREATE TABLE samples (            -- 采样与事实分开，不参与判定
  subject TEXT NOT NULL, metric TEXT NOT NULL,
  ts TEXT NOT NULL, value REAL NOT NULL,
  PRIMARY KEY (subject, metric, ts)
) WITHOUT ROWID;

CREATE TABLE receipts (           -- 执行者留下的引用，不做门禁
  event_id TEXT NOT NULL REFERENCES events(id),
  seq      INTEGER NOT NULL,
  kind     TEXT NOT NULL,          -- commit|command|path|message|url
  value    TEXT NOT NULL,
  exit     INTEGER,                -- 仅 command
  PRIMARY KEY (event_id, seq)
);

CREATE TABLE transitions (        -- 谁、何时、为什么改了状态
  event_id TEXT NOT NULL REFERENCES events(id),
  at TEXT NOT NULL, from_state TEXT, to_state TEXT NOT NULL,
  actor TEXT NOT NULL, reason TEXT
);

CREATE INDEX idx_events_state_deadline ON events(state, deadline);
CREATE INDEX idx_events_valid_until    ON events(valid_until) WHERE valid_until IS NOT NULL;
CREATE INDEX idx_events_kind_ingest    ON events(kind, ingest_ts);
CREATE INDEX idx_events_thread         ON events(thread_id, ingest_ts);
```

保留：账本行永久；payload 90 天；`samples` 30 天；`transitions` 永久（审计）。

## 8. CLI 与 P0 验收

| 命令 | 用途 | P0 |
|---|---|---|
| `ev add -k kind -s subject --payload f.json` | 手工记一条事件 | ✅ |
| `ev list --state triaged --since 24h` | 看未处理 | ✅ |
| `ev show <id>` | 详情 + 回执 + 变更历史 | ✅ |
| `ev close <id> --summary "..." [--ref ...]` | 落定并留回执 | ✅ |
| `ev defer <id> --until` / `ev ack` | 延后 / 已读 | ✅ |
| `ev digest --day` | 生成当日摘要文本 | ✅ |
| `ev report --week` | 周报与规则候选 | P4 |
| `ev rules lint` | 规则包校验 | P1 |
| `ev replay <id>` | 从 payload 重放一次判定 | P1 |

P0 验收（一周内可做完）：

1. 无 `summary` 的 `close` 被拒；`refs` 为空仍接受。
2. `ev list` 能列出所有未落定且按 deadline 排序。
3. 连续记 7 天，`ev digest` 每天能给出"逾期 / 今日 / 昨日落定"三段。
4. 账本可被 `sqlite3` 直接打开，无需服务。

## 9. 基座校验

只列**基座不变量**——每一行都是"结构上不可能出错"，而不是"提醒执行者别做错"。执行层的正确性不在这一节，也不在任何一节。

| # | 校验 | 用哪条不变量解释 |
|---|---|---|
| 1 | 账只由 `eventd` 写；处理器只能提交变更请求 | 唯一写入者 |
| 2 | 同一 `dedupe_key + bucket` 重复投递，账里仍只有一条 | 幂等 |
| 3 | 未命中规则的事件保留为 `triaged`，`rule_id` 为空，且可列出 | 不静默丢 |
| 4 | 同一事件重放两次判定，结果与 `rule_id` 完全一致 | 判定是纯函数 |
| 5 | 所有 `deferred` 都有 `wake_at`；到期未处理必然 `escalated` | 不留悬挂状态 |
| 6 | 规则包 lint 失败时服务不启动 | fail closed |
| 7 | 处理器环境里没有凭据 | 泄露面 |
| 8 | 任一呈现面拿到的视图可追溯到 `event_id`，且不写回账 | 单一事实源 |
| 9 | `irreversible` 事件不能走直通，也不能由 `untrusted` 源触发 | 一条闸门 |
| 10 | `timed` 事件缺 `valid_until` 时入账失败；过期进入 `expired` | 账不积垃圾 |

删掉的两条（原 5、13）分别是"缺证据被拒"和"同类超时合并出现"。前者是执行层门禁，本轮移除；后者是摘要的呈现效果，属于观测，不属于基座。

## 未决项

- `samples` 是否需要按设备分表，取决于 P3 实测写入量。
- `transitions` 是否要记录 payload 摘要快照，以便复盘"当时看到的是什么"。
- `refs` 的 `kind` 枚举是否够用：目前 `commit|command|path|message|url`，缺"外部工单号"之类时再扩展。
