# 路线图

> 每一步做完都能马上用上；不设验收条款，自己用一周觉得有用就进下一步。

| 阶段 | 内容 | 主要复用 | 能用上的标志 |
|---|---|---|---|
| **P0** | Taskwarrior + `ev` 封装 + 每日 digest + KRunner 入口 + Plasma 小组件 | Taskwarrior、plasma-manager | 自己每天在用 |
| **P1** | 入口 Agent 做选择题 + 卡片交互 + KDE Connect + ntfy + 状态灯 + 早报 / 晚报 | DS-Bot / AstrBot、LiteLLM、ollama、WLED | 手机上说一句话就能派活 |
| **P2** | 第一批能力：视频、作曲、长文写作、订阅早报、`info.recall`、`work.nixos.update`、记账 | Remotion、ACE-Step、RSSHub、double-entry-generator | 写作工作室和视频工作室跑通 |
| **P3** | 硬件：Wake-on-LAN、UPS、NFC、毫米波、墨水屏分工、热敏打印 | HA、ESPHome、NUT、OpenEPaperLink | 场景能自动触发 |
| **P4** | 周报 / 年度回顾、`meta.capability.propose`、场景录制、偏好学习、N100 兜底分类器 | SetFit、Khoj | 系统开始提出新能力的建议 |

## P0 怎么开始

1. 在 flake 里加上 `taskwarrior3`，配置 UDA：`kind`、`source`、`thread`、`parent`、`payload`。
2. 写 `ev` 封装（[事件规格 §3](event-spec.md)）。
3. 先登记 5 类事项：`work.code.task`、`life.maintain.*`、`life.schedule.*`、`info.feed.digest`、`meta.review.weekly`。
4. 用 systemd timer 每天生成 digest，推送到手机。
5. 做一个 KRunner 插件和一个 Plasma 小组件，显示待处理数量。

用一周后再看：如果觉得记账麻烦，就减少事项类别；如果觉得有用，就进入 P1。
