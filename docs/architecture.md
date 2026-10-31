# 架构总览

> 状态：设计中（P0 未实现）· 取向见 [设计原则](principles.md)：功能优先、复用优先

## 0. 一句话

**你说一句话或者发生一件事 → 系统听懂 → 找到对应能力 → 交给合适的执行者 → 做完用一句话告诉你 → 记进账。** 能力可以随时增加、替换和组合，设备和显示面也可以随时接入。

## 1. 四层 + 三个确认点

| 层 | 回答的问题 | 内容 | 特点 | 文档 |
|---|---|---|---|---|
| **能力层** | 做什么 | 制作视频、作曲、写长文、整理账单、回家场景…… | 开放集合，持续增加 | [能力目录](capabilities.md) |
| **流转层** | 进行到哪一步了 | 接收 → 处理中 → 等待 → 完成 / 放弃 | 封闭集合，就是一个小状态机 | [事件规格](event-spec.md) |
| **执行层** | 怎么做 | worker Agent、CLI、HA 服务调用、浏览器、GUI 自动化 | 工具可以随时替换 | [系统拓扑](system-topology.md)、[本机工具链](local-toolchain.md) |
| **设施层** | 在哪里跑 | 工作站、N100、AX6000、手机、墨水屏、传感器 | 物理设备 + NixOS | [工作站](workstation-nixos.md)、[智能家居](home-automation-stack.md) |

**确认点**只有三类：**付款、删除、对外发布**。其余动作直接执行；可以撤销的动作配一个撤销窗口（默认 5 分钟，期间一键撤回）。

## 2. 粘合：两端用语义，中间用约定

```
你的话 ──[入口 Agent：做选择题]──> kind + 参数 ──> 流转 ──> 执行 ──> 一句话结果 ──[出口 Agent：说人话]──> 你
机器事件（HA / 定时 / CI / webhook）─────────────> kind + 参数（不经过模型）
```

- **入口只做选择**：入口 Agent 从 [能力目录](capabilities.md) 里挑一个 `kind`，填好参数，给出置信度。置信度高就直接做，中等就问你一句，低就进"待归类"。
- **统一决策接口** `decide(state, schema) → {字段: 概率}`，后端可替换：
  - 工作站 GPU：本地 7–9B 模型（ollama / vLLM），也可以接 Jev 这类结构化决策模型；
  - N100：中文 embedding 小模型 + 近邻分类，工作站离线时兜底；
  - 云端：DeepSeek / Qwen，处理长尾。
  - 三者统一经 [LiteLLM](open-source-reuse.md#模型与推理) 网关出去，路由和回退都在网关里配置。
- **账就是训练数据**：你每次确认或改正一个归类，都是一条带标签的样本，阈值和本地分类器会越来越准。
- **成本**：机器事件不经过模型；你说的话每条只翻译一次。成本大头在 worker 执行，判断部分几乎可以忽略。

## 3. 账：复用 Taskwarrior + Home Assistant

| 数据 | 放在哪里 | 为什么 |
|---|---|---|
| 要处理的事项 | **Taskwarrior 3**（`taskchampion.sqlite3`） | 现成提供 `wait`（到点再出现）、`due`、周期任务、注解、自定义字段（UDA）、hooks、多端同步 |
| 设备的原始事件和状态 | **Home Assistant recorder** | 传感器高频数据留在 HA，只有需要处理的事情才进 Taskwarrior |
| 任务执行过程 | Orca（Run / Task） | worker 的会话和产物 |

唯一需要自建的是一个**很薄的分派器**：Taskwarrior 的 hook 读取 `kind`，按规则表决定交给谁。字段和状态的映射见 [事件规格](event-spec.md)。

## 4. 规则：一张顺序匹配的表

```toml
[[rule]]
match = { kind = "work.video.*" }
to = "agent:orca"            # 交给 Orca worker

[[rule]]
match = { kind = "home.scene.*" }
to = "ha:script"             # 直接调用 HA 脚本

[[rule]]
match = { kind = "life.maintain.*" }
to = "notify"                # 到点提醒
```

从上往下匹配，先命中先生效；都没命中就进"待归类"，在早报里提一句。**家居自动化直接用 HA 的 automation**，不在这里重复实现。

## 5. 执行者

| 执行者 | 用在哪 | 复用 |
|---|---|---|
| `agent:orca` | 多步任务：代码、文档、视频、写作 | Orca + Devin / Codex worker |
| `ha:*` | 家居场景、设备控制 | Home Assistant 服务调用 |
| `cli:*` | 一次性动作 | 现成 CLI（ffmpeg、calibre、double-entry-generator……） |
| `n8n:*` | 第三方 SaaS 串联 | n8n 工作流（webhook、邮件、RSS） |
| `notify` | 只提醒 | ntfy / KDE Connect / IM |
| `me` | 需要你本人处理 | 卡片：`[做] [晚点] [不要]` |

## 6. 呈现面：全部从账派生

| 显示面 | 内容 | 复用 |
|---|---|---|
| 状态灯 | 不亮表示没事，黄色表示有事等你，红色表示有紧急事项 | WLED |
| 墨水屏（门口 / 桌面 / 床头） | 出门清单 / 今日事项 / 明天第一件事 | OpenEPaperLink，见 [渲染管线](render-pipeline.md) |
| Plasma 小组件、KRunner | 待处理数量、一句话入账 | Plasma、plasma-manager |
| ThinkSmart View | 家庭面板 | HA dashboard，见 [主控台](thinksmart-view-console.md) |
| 手机 / 手表 | 一个数字 + 推送 | KDE Connect、ntfy、HA companion |
| IM | 卡片交互、早报和晚报 | DS-Bot / AstrBot |
| 热敏小票 | 当日清单 | python-escpos |

**首屏契约**：任何呈现面的第一屏只回答"现在有哪几件事不能不管"。

## 7. 召回与反哺

- **召回**：用 `info.recall` 回答"我上次是怎么弄的"，检索范围包括账、笔记、聊天记录和命令历史，复用 SQLite FTS5 / sqlite-vec 或 Khoj。
- **周报**：本周完成了什么、哪类事最耗时、哪些事反复出现（建议把它们变成规则或新能力）、每个能力的返工次数。
- **年度回顾**：从账里自动生成。

## 8. Bot 模式

模式包括工作、生活、专注、勿扰、外出、出差，与 Plasma Activities 双向联动。模式只改变"什么时候、用什么渠道打扰你"。详见 [Personal Agent](personal-agent.md)。

## 9. 分阶段

见 [路线图](roadmap.md)。
