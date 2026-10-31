# 日常事务管理

> 状态：设计中 · 所属域：`life` · 上位文档：[总体架构设计 §7 定时与周期节奏](architecture-north-star.md#7-定时与周期节奏)、[能力目录](capabilities.md)
>
> 本文定义 `life.*` 域下的日常事务、财务记账、健康作息、物品库存与课程学习管理。职责边界：**物理设备的运行与控制归入 `home.*` 域**（见 [宿舍智能家居方案](dorm-smart.md)），**个人日程、财务、健康与学习事务归入 `life.*` 域**。

## 1. `life.*` 能力清单

按触发周期与数据结构，将日常事务细分为以下 14 项能力：

| `kind` | 功能说明 | 触发来源 | 执行器 | Taskwarrior 关键字段 | 底层复用工具 |
|---|---|---|---|---|---|
| `life.schedule.*` | 日程安排与提醒 | CalDAV 日历同步 / 自然语言录入 | `cli:khal` | `due`、`project:life.cal` | Radicale CalDAV + `khal` |
| `life.sleep.winddown` | 晚间睡前清单：明日首项待办、闹钟核对、设备充电、床头屏刷新 | 每日 22:30 定时 / 语音触发 | `render` + `notify` | `recur:daily`、`project:life.sleep`、`+winddown` | Taskwarrior `recur` + [统一渲染管线](render-pipeline.md) |
| `life.sleep.review` | 周度作息统计：入睡与起床时间分布、目标偏差分析 | 每周日 21:00 定时 | `cli:sleepstat`（约 50 行脚本） | `recur:weekly`、结果写入任务注解 | Home Assistant Recorder 历史 API |
| `life.meal.plan` | 周度食谱规划、采购清单生成与食材余量核对 | 每周日 20:00 定时 | `cli:mealie` | `recur:weekly`、`due:周一`、`project:life.meal` | Mealie |
| `life.fit.session` | 每日训练计划提醒与完成打卡 | 每日 07:00 定时 / 手动触发 | `notify` + `me` | `recur`、`tags:fit_<部位>`、`priority` | Taskwarrior `recur` + `plan.md` |
| `life.health.med` | 日常用药提醒与药品余量预警 | 每日定时 / 库存低于阈值 | `notify` | `recur:daily`、`due`、`tags:med` | Taskwarrior `recur` + `life.stuff.inventory` |
| `life.health.checkup` | 年度体检、复诊与疫苗接种提醒 | `recur:1y` / 手动登记 | `me` | `recur:1y`、`wait:-30d`、`tags:health` | Taskwarrior `recur` |
| `life.doc.renew` | 身份证件、校园卡、租约、学籍注册到期提醒 | `recur` / 手动登记 | `me` | `recur:1y`、`due`、`wait:-60d`、`tags:doc` | Taskwarrior `recur` |
| `life.sub.audit` | 订阅服务盘点、扣费日预告、涨价检测与试用到期提醒 | 每月 1 日定时 | `cli:beancount` + `me` | `project:life.sub`、`recur:monthly`、`due:<扣费日>` | `subscriptions.toml` + Beancount + Fava |
| `life.social.keep` | 亲友生日提醒、人情往来记录与定期联络提示 | CardDAV `BDAY` 字段 → `recur:1y` | `notify` + `me` | `recur:1y`、`wait:-14d`、`tags:person_<名>` | Radicale CardDAV + `vdirsyncer` |
| `life.stuff.inventory` | 日常耗材余量、电子设备保修期与借出物品登记 | 手动更新 / 保修到期前 30 天 | `cli:inv` | `project:life.stuff`、`recur`、`due` | `inventory.toml`（超过 100 件后迁移至 HomeBox） |
| `life.study.plan` | 学习通课程作业、通知拉取与考试倒计时 | 每日 12:30 与 20:00 定时 | `cli:xxt` → `ev add` | `due:<截止时间>`、`project:study/<课程>`、`priority` | `xuexitong-cli`（`xxt hw --all-courses`） |
| `life.finance.budget` | 月度预算核算与分类超支提醒 | 每周日 + 每月末定时 | `cli:beancount` | `recur:monthly`、`project:life.fin` | Beancount + `fava-envelope` |
| `life.finance.ledger` | 支付宝/微信账单导入、复式记账转换与月度报表 | 手动触发 / 每月定时 | `cli:double-entry-generator` | `project:life.fin` | `double-entry-generator` + Beancount + Fava |

此外保留 `life.maintain.home` 用于宿舍清洁、滤芯更换等周期性家务维护。

### 1.1 能力配置示例

```toml
# capabilities/life.sub.audit.toml
kind = "life.sub.audit"
desc = "周期性订阅对账：扣费日预告、价格变动检测与试用到期提醒"
examples = ["这个月订阅花了多少", "哪些订阅快到期了"]
not = ["记一笔日常消费", "帮我直接退订这个服务"]
needs = ["cli:beancount", "workstation"]
provider = "sub-audit"
autonomy = "L1"
```

## 2. 字段与存储约定

在 [事件与任务规格](event-spec.md) 基础上，日常事务域遵循三条数据约定：

1. **层级化 `project` 命名**：使用 `life.sleep`、`life.meal`、`life.fit`、`life.health`、`life.fin`、`life.stuff`、`study/<课程>`，便于直接通过 `task project:life summary` 输出各子类的完成统计。
2. **高频生理采样数据不进任务库**：睡眠时长、体重、步数、心率等连续采样数据保存在 Home Assistant Recorder 或独立的统计数据库中；仅当产生需要人工跟进的事项（如连续熬夜提醒、体检预约）时才写入 Taskwarrior。
3. **善用 `recur` 与 `wait` 控制可见时机**：生日、设备保修、证件换发等事项采用 `recur:1y wait:-14d due:+14d`，使其在到期前 14 天才进入待办视图；`due` 字段仅用于具有刚性截止时间的事项（如作业提交、账单扣费日）。

## 3. 订阅服务的单一数据源：`subscriptions.toml`

为避免在记账软件、日历与待办列表中重复维护订阅信息，所有周期性订阅统一在 `data/subscriptions.toml` 中声明，Beancount 的定期交易模板与 Taskwarrior 的扣费提醒均由该文件自动生成：

```toml
# data/subscriptions.toml
[[sub]]
name = "B站大会员"
amount = 148.00
currency = "CNY"
account = "Assets:Alipay"
category = "Expenses:Subscription:Entertainment"
cycle = "yearly"
next_charge = 2027-03-12
trial_until = ""          # 为空表示非试用期
cancel_url = "https://..."

[[sub]]
name = "云服务器"
amount = 60.00
currency = "CNY"
account = "Assets:Alipay"
category = "Expenses:Subscription:Infra"
cycle = "monthly"
next_charge = 2026-12-01
```

同步脚本执行两项操作：一是生成 `subscriptions.beancount` 周期账目定义；二是为每个即将到期的条目创建 `ev add "订阅扣费预告：<name> <amount>" --kind life.sub.audit --due <next_charge> --wait -3d`。对账时若发现实际账单扣款金额与 `subscriptions.toml` 偏差超过 5%，自动创建一条带 `+me` 的涨价核对任务。

同类结构化配置还包括：`inventory.toml`（物品与耗材清单）、`plan.md`（训练计划）以及 Radicale CardDAV（联系人与生日信息）。

## 4. 日常定时调度表

| 触发时刻 | 自动生成的任务 | 对应 `kind` | 投递终端 |
|---|---|---|---|
| 工作日 06:40 | 晨间唤醒场景（见 [自动化场景](ritual-scenes.md)） | `meta.scene.morning` | 桌面 T5 墨水屏 + 手机 |
| 每日 07:00 | 当日训练计划与晨间用药提醒 | `life.fit.session` / `life.health.med` | 手机推送 |
| 每日 08:00 | 每日早报 + 今日三项核心待办 | `info.feed.digest` | IM |
| 每日 12:30 / 20:00 | 学习通课程作业与通知扫描 | `life.study.plan` | 任务库（带 `due` 截止时间） |
| 每日 18:00 | 每日晚报 + 明日日程预览 | `meta.review.daily` | IM |
| 每日 20:30 | 当日未分类账单流水记账提醒 | `life.finance.ledger` | 手机推送 |
| 每日 22:30 | 睡前准备清单 + 刷新床头墨水屏 | `life.sleep.winddown` | 床头 ESL 墨水屏 |
| 每周六 10:00 | 宿舍周度清洁清单 | `meta.scene.cleanup` | 任务库 + 门口 ESL |
| 每周日 20:00 | 下周食谱规划与采购清单 | `life.meal.plan` | 任务库 + 门口 ESL |
| 每周日 21:00 | 周度复盘、下周计划与作息统计周报 | `meta.review.weekly` / `life.sleep.review` | IM + 桌面 T5 |
| 每周一 08:00 | 本周即将扣费的订阅预告 | `life.sub.audit` | 手机推送 |
| 每月 1 日 | 上月财务月结与预算执行率报表 | `life.finance.budget` | IM |
| 每月 15 日 | 日常耗材余量盘点 | `life.stuff.inventory` | 任务库 |
| 每季首日 | 换季衣物与设备维护清单 | `meta.scene.season` | 任务库 |
| 生日前 14 天 | 亲友生日与礼物准备提醒 | `life.social.keep` | 手机推送 |
| 到期前 30–60 天 | 证件换发与设备保修到期提醒 | `life.doc.renew` / `life.stuff.inventory` | 任务库 |
| 每年 1 月 | 年度总结与全年订阅费用复盘 | `meta.review.yearly` | IM |

调度约束：

- **定时任务只负责录入任务，不绕过任务库直接发通知**：所有定时触发器统一调用 `ev add` 创建任务，再由派发器按当前通知模式投递，确保所有提醒在任务库中留有记录。
- **断网期间失败可重试**：如 `xxt` 因校园网断开拉取失败，任务转入 `waiting` 状态等待网络恢复后重试，不静默丢弃。

## 5. 分步实施计划

| 阶段 | 落地内容 | 前置依赖 | 验收标准 |
|---|---|---|---|
| 第一步 | `life.study.plan`、`life.doc.renew`、`life.sub.audit` | 本机 `ev` CLI + `xxt` + `subscriptions.toml` | 学习通新作业与证件/订阅到期自动进入任务库 |
| 第二步 | `life.social.keep`、`life.sleep.winddown` | Radicale CardDAV + 床头墨水屏 | 亲友生日提前两周提醒，每晚自动刷新明日首项待办 |
| 第三步 | `life.meal.plan`、`life.finance.budget` | Mealie、Beancount + Fava | 自动生成周末采购清单与月度分类账单报表 |
| 第四步 | 其余辅助能力 | 按需接入 | 按日常实际使用频率逐步启用 |
