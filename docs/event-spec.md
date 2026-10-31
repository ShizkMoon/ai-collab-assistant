# 事件规格

> 状态：设计中（P0 未实现）· 上位文档：[架构总览](architecture.md)

账用 **Taskwarrior 3**，不自建存储。本文只规定字段、状态和分派约定。

## 1. 字段

| 字段 | Taskwarrior 对应 | 含义 |
|---|---|---|
| `id` | `uuid` | 事项 id |
| `ts` | `entry` | 创建时间 |
| `source` | UDA `source` | 来源：`me` / `ha` / `cron` / `github` / `phone` / `email` / `rss` … |
| `kind` | UDA `kind` | `<域>.<对象>.<动作>`，如 `work.video.make`，取值见 [能力目录](capabilities.md) |
| `subject` | `description` | 这件事是关于什么 |
| `state` | `status` + `start` | 见 §2 |
| `summary` | 结束时的注解 | 一句话结论 |
| `payload` | UDA `payload` | 原始内容的路径，可以为空 |
| `thread`（可选） | UDA `thread` | 把同一件事的多条事项串起来 |
| `parent`（可选） | `depends` / UDA `parent` | 由哪条事项派生出来 |

域：`work` / `life` / `home` / `info` / `media` / `meta`。

## 2. 状态

| 状态 | Taskwarrior | 说明 |
|---|---|---|
| `new` | `pending` | 刚入账 |
| `doing` | `pending` + `start` | 有人或 Agent 正在处理 |
| `waiting` | `waiting`（`wait:<时间>`） | 到点自动回到 `new`。提醒、延后处理、间隔重复、周期维护都用它 |
| `done` | `completed` + 注解 | 用一句话结束 |
| `dropped` | `deleted` | 放弃 |

周期性事项（滤芯、续费）直接用 Taskwarrior 的 `recur`。

## 3. CLI

`ev` 是 `task` 的一层薄封装，只负责填好 UDA：

```
ev add "<一句话>" [--kind ...] [--wake 明早9点]   # task add ... kind:... wait:...
ev ls                                            # task next
ev done <id> "<一句话>"                          # task <id> annotate ... && task <id> done
ev wait <id> <时间>                              # task <id> modify wait:...
ev digest [today|week]                           # task completed end.after:...
```

Taskwarrior 自带的报表、过滤和同步都可以直接用。

## 4. 分派器（唯一自建）

- 在 `on-add` / `on-modify` hook 里读取 `kind`，按 [规则表](architecture.md#4-规则一张顺序匹配的表) 找到执行者，然后调用它。
- 执行者约定：

```text
输入 : 事项 JSON（Taskwarrior export 格式）
输出 : { "status": "done|waiting|me", "summary": "一句话", "wake": "<仅 waiting>" }
```

- 由分派器把输出写回 Taskwarrior：完成就 annotate + done，等待就 modify wait，需要你本人处理就打上 `+me` 标签并推送卡片。
- 长任务交给 Orca，分派器不阻塞等待；Orca 完成后调用 `ev done` 回写。

## 5. 来源接入

| 来源 | 接入方式 |
|---|---|
| 你说的话 | DS-Bot / AstrBot → 入口 Agent 选出 `kind` → `ev add` |
| 设备 | HA automation → 调用 `ev add`（只在需要处理时） |
| 定时 | systemd timer 或 Taskwarrior `recur` |
| GitHub / 飞书 / webhook | N100 上的 n8n → `ev add` |
| 邮件 / RSS | n8n（IMAP、RSS 节点）→ 摘要 → `ev add` |
| 手机 | KDE Connect 分享 / HA companion → `ev add` |

## 6. 备份

`taskchampion.sqlite3` 用 Litestream 持续复制到 N100，或者每天复制一份。这是唯一的可靠性要求。
