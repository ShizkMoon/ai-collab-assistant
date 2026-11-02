# 多端显示仲裁：内容优先级与刷新预算分配

> 状态：设计中 · 上位文档：[总体架构设计](architecture-north-star.md)、[统一渲染管线](render-pipeline.md)、[墨水屏硬件选型](eink-display-modules.md)
>
> [统一渲染管线](render-pipeline.md)负责将数据渲染为 PNG 位图，[墨水屏交互设计](eink-modules-ux.md)定义了各显示端的版面与摆放点位；本文补充**多端显示仲裁器（Display Arbiter）**，解决多条待展示内容同时竞争同一显示端时的优先级裁决与每日刷新预算控制。

## 1. 设计目标

早期方案通过 `devices.toml` 将每块屏幕与固定版面静态绑定，当"出门携物清单"与"周末采购清单"同时生效时只能手动修改配置。

引入**显示仲裁器**后，墨水屏、WLED 状态灯、热敏打印机、手机推送与桌面小组件均统一建模为**显示端（Output Surface）**；每类待展示信息通过**内容声明（Content Spec）**定义优先级、有效期与适配终端，由仲裁器动态计算当前各显示端应展示的内容并判断是否需要触发物理刷新。

## 2. 三层数据模型

| 层级 | 概念定义 | 配置文件与维护方 |
|---|---|---|
| **显示端（Surface）** | 物理或软件输出终端：声明分辨率、位深、刷新耗时与功耗、可视距离及每日刷新预算 | `surfaces/*.toml`，新设备接入时配置一次 |
| **槽位（Slot）** | 显示端版面中的固定分栏或区块，声明允许放置的内容类别（`class`）、字数容量与最低优先级门槛（`floor`） | 随 `surfaces/*.toml` 一并声明 |
| **内容声明（Content Spec）** | 待展示的信息单元：声明基础优先级、有效期（`ttl_s`）、新鲜度半衰期（`tau_s`）、独占组（`group`）与数据源查询命令 | `content/*.toml`，随各项能力定义维护 |

显示仲裁器本身不维护独立的业务数据源：所有待展示数据均实时查询自 Taskwarrior 任务库与 Home Assistant 状态；仲裁器仅缓存各显示端上一帧的哈希值（`last_frame_hash`）与当日累计刷新次数。

## 3. 显示端配置示例（`surfaces/*.toml`）

```toml
# surfaces/desk-t5.toml
id = "desk-t5"
kind = "eink"                 # eink | lcd | led | paper | software | push
resolution = [960, 540]
size_inch = 4.7
color = "gray4"               # bw | gray4 | bwr | bwy | full
dwell = "always-on"
read_distance_m = 0.5
disturb = "none"
rank = 50                     # 独占内容分配顺序，数值越小优先级越高

refresh = { latency_s = 2.0, partial = true, full_every = 20, energy_mj = 800 }
budget = { refreshes_per_day = 40, wake_window = ["07:00", "23:30"] }

[[slots]]
id = "headline"
class = ["now", "next"]
capacity = { lines = 1, chars = 24, min_font_pt = 24 }
floor = 0.8

[[slots]]
id = "agenda"
class = ["today"]
capacity = { lines = 3, chars = 28 }
floor = 0.4

[[slots]]
id = "footer"
class = ["ambient"]
capacity = { lines = 1, chars = 40 }
floor = 0.0
```

```toml
# surfaces/door-esl.toml
id = "door-esl"
kind = "eink"
resolution = [296, 128]
size_inch = 2.9
color = "bw"
dwell = "glance"
read_distance_m = 2.0
disturb = "none"
rank = 10                     # 门口屏优先获取出门相关独占内容
refresh = { latency_s = 3.0, partial = false, full_every = 0, energy_mj = 60 }
budget = { refreshes_per_day = 6, wake_window = ["06:30", "23:00"] }
channel = "oepl"              # 推送至 OEPL AP 队列，在标签下次唤醒时下发

[[slots]]
id = "only"
class = ["depart", "chore"]
capacity = { lines = 5, chars = 20 }
floor = 0.5
```

其余显示端采用相同结构声明：`bed-esl`（床头 2.13" 电子价签，`rank = 20`，每日刷新预算 2 次）、`tsv`（桌面 8" LCD 主控台，`output = "html"`）、`wled`（状态灯带，`kind = "led"`）、`printer`（热敏小票机，`kind = "paper"`，`idempotent = false`）、`plasma`（桌面小组件）以及 `phone-push`（手机推送）。

## 4. 内容声明示例（`content/*.toml`）

```toml
# content/departure-checklist.toml
id = "departure-checklist"
class = ["depart"]
priority = 0.95
ttl_s = 1200                  # 出门场景触发后 20 分钟自动过期
tau_s = 600                   # 新鲜度衰减半衰期
group = "depart"              # 独占组：同一 group 的内容同一时刻只投放到一个显示端
source = "ev export +status:pending +depart --json"
render = "checklist"
provenance = "event_ids"      # 要求查询结果必须包含任务 ID 来源，否则不下发
affinity = ["door-esl", "phone-push"]
```

```toml
# content/today-three.toml
id = "today-three"
class = ["today"]
priority = 0.6
ttl_s = 3600
tau_s = 14400
group = "today"
source = "ev ls --today --limit 3"
render = "agenda3"
provenance = "event_ids"
affinity = ["desk-t5", "tsv"]
```

```toml
# content/tomorrow-first.toml
id = "tomorrow-first"
class = ["next"]
priority = 0.7
ttl_s = 43200
tau_s = 43200
group = "next"
source = "ev next --after 明天00:00 --limit 1"
render = "headline"
provenance = "event_ids"
affinity = ["bed-esl", "desk-t5"]
```

优先级数值分档规范：

| 优先级区间 | 紧急程度 | 典型内容示例 | 是否豁免每日刷新预算 |
|---|---|---|---|
| `0.95–1.0` | 需立即处理 | 水浸告警、门磁异常、出门前 10 分钟携物清单 | **豁免**，无视刷新次数上限立即下发 |
| `0.70–0.95` | 当日重要事项 | 明日首项待办、今日三项核心待办、订阅扣费到期 | 否 |
| `0.40–0.70` | 常规日常信息 | 日历日程、天气预报、耗材余量提醒 | 否 |
| `0.10–0.40` | 环境背景状态 | 主机监控摘要、绿植土壤湿度 | 否 |
| `< 0.10` | 静态装饰内容 | 静态壁纸、格言 | 否 |

## 5. 显示仲裁算法

```python
def arbitrate(surfaces, contents, now, state):
    jobs, taken_groups = [], {}

    for s in sorted(surfaces, key=lambda x: x.rank):
        if not in_window(now, s.budget.wake_window):
            continue
        if state.refreshes_today[s.id] >= s.budget.refreshes_per_day:
            continue                      # 达到当日刷新上限的显示端跳过常规更新

        scored = []
        for c in contents:
            if c.expired(now):
                continue
            slot = s.best_slot(c)         # 检查类别匹配与字数容量
            if slot is None or c.priority < slot.floor:
                continue
            if c.group in taken_groups and not c.priority >= 0.95:
                continue                  # 该独占组已被更高优先级的显示端占用
            if not c.has_provenance():
                continue                  # 无可追溯任务 ID 的数据不予上屏
            score = (c.priority
                     * freshness(c, now)                 # exp(-age / tau)
                     * (1.0 if s.id in c.affinity else 0.6))
            scored.append((score, c, slot))

        chosen, filled = [], set()
        for score, c, slot in sorted(scored, key=lambda x: -x[0]):
            if slot.id in filled:
                continue                  # 每个槽位仅放置得分最高的一条内容
            chosen.append(c)
            filled.add(slot.id)
            if c.priority >= 0.95 or c.group not in taken_groups:
                taken_groups.setdefault(c.group, s.id)

        if not chosen:
            continue
        frame = render(s.layout, chosen)  # 确定性渲染生成图像帧
        if frame.hash == state.last_hash[s.id]:
            continue                      # 图像内容未发生变化，跳过物理下发

        partials = state.partials[s.id]
        mode = "full" if (not s.refresh.partial or partials >= s.refresh.full_every) else "partial"
        jobs.append(Job(surface=s, frame=frame, mode=mode,
                        event_ids=union(c.provenance for c in chosen)))
        state.partials[s.id] = 0 if mode == "full" else partials + 1
        state.refreshes_today[s.id] += 1

    return jobs
```

核心防打扰与省电机制：

1. **强制来源校验（`provenance`）**：所有上屏数据必须关联具体的任务 UUID 或有效的 HA 状态查询，禁止展示无法追溯来源的占位数字。
2. **独占组去重（`group`）**：同一 `group` 的内容在桌面 T5 墨水屏与 ThinkSmart View 之间只投放一处，避免同一张桌面上两块屏幕显示完全重复的信息。
3. **两级哈希比对省电**：
   - **数据级比对**：对查询返回的 JSON 规范化后计算 `sha256`，数据未变则直接跳过 Chromium 渲染；
   - **图像帧级比对**：对生成的 PNG 字节流计算 `sha256`，若与 `last_hash` 一致（例如任务新增了一条不在屏幕展示范围内的内部注解），则不下发刷新且不消耗当日刷新预算。

## 6. 墨水屏功耗与刷新策略约束

| 硬件特性 | 工程设计推论 |
|---|---|
| 2.9" ESL 单次全刷耗时 2–3s，单次刷屏耗电约 $10^{-2}\text{ mAh}$ 量级 | 纽扣电池（CR2450 约 620mAh）每天刷屏 6–10 次仅耗电约 0.1mAh，正常低频刷屏并非续航瓶颈 |
| ESL 纽扣电池的主要耗电项是 **射频周期唤醒监听（Check-in）** | 优化重点是保持合理的 AP Check-in 间隔（40–60s），不要为了追求秒级响应而缩短广播唤醒周期 |
| 拆机 ESL 价签大多仅支持全屏刷新，不支持局部刷新 | 投放到 ESL 的内容应限制为低频变化信息（出门清单、采购清单、明日首项待办），高频变动内容交由桌面 T5 或 TSV 展示 |
| LilyGo T5 4.7" 使用 Wi-Fi 拉取，单次 Wi-Fi 连接握手耗电高于刷屏本身 | T5 在书桌固定点位优先使用 USB 常电供电；若用电池供电则必须配合 ESP32 Deep Sleep 定时唤醒拉取，禁止常连轮询 |
| 画面底部的更新时间若取"当前渲染时刻"，会导致每次重渲 PNG 哈希均变化 | **画面底部时间戳统一显示"底层数据最后变更时刻"**，数据未变则时间戳不变，从而保证帧级哈希去重生效 |

## 7. 各显示端默认分配表

| 显示端 | 默认优先展示内容 | 刷新策略 | 所属独占组 |
|---|---|---|---|
| **门口 2.9" ESL** | 出门携物清单（钥匙/校园卡/雨伞 + 当日课程需带物品） | 出门场景触发，每日 ≤ 6 次 | `depart` |
| **桌面 T5 4.7" 墨水屏** | 今日三项核心待办 + 当前运行中的 Orca 任务 + 天气 | 任务状态变更或每 15 分钟检查，每日 ≤ 40 次 | `today` / `now` |
| **床头 2.13" ESL** | 明日首项待办 + 晨间闹钟时间 + 睡前检查项 | 每晚 22:30 刷新一次 | `next` |
| **ThinkSmart View 主控台** | Home Assistant 控制面板、待确认交互卡片、多候选比选预览 | 实时 HTML 视图，夜间随入睡场景自动息屏 | 全局交互视图 |
| **WLED 状态灯带** | 熄灭=无待办 / 琥珀色=有待确认卡片 / 红色=紧急告警或故障 | 状态变化时即时切换 | `status` |
| **热敏小票机** | 纸质出门清单、周末采购清单 | 仅在 NFC 触碰或语音显式要求时打印 | `depart` / `chore` |
| **桌面小组件（Rainmeter / WebView2 面板）** | 待处理任务总数 + 最近一项截止倒计时 | 每 30 秒读取本地任务库 | `status` |
| **手机推送（`ntfy`）** | 高优告警、需人工确认卡片、离宿期间的重要通知 | 按通知模式门控即时发送 | `now` |
