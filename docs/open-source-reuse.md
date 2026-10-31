# 开源复用地图

> 规则：先复用；接近的包一层薄封装；没有先例才自建（见 [设计原则](principles.md)）。本表记的是选型意图，实际装了什么以本机 flake 为准。

## 1. 骨架

| 需要 | 复用 | 备注 |
|---|---|---|
| 事项账 | **Taskwarrior 3** | 存储在 SQLite（`taskchampion.sqlite3`），支持 hooks、UDA、`wait`、`recur`，可多端同步 |
| 设备事件、家居自动化 | **Home Assistant** + Mosquitto + Zigbee2MQTT + ESPHome | 已在 [智能家居](home-automation-stack.md) 中定型，NixOS 有原生模块 |
| 小米设备 | 小米官方 HA 集成 `ha_xiaomi_home` | |
| SaaS 和 webhook 串联 | **n8n**（N100） | 包括 IMAP、RSS、GitHub、飞书等节点；NixOS 有 `services.n8n`；许可为 Sustainable Use，个人使用没问题 |
| 定时 | systemd timer / Taskwarrior `recur` | |
| 账备份 | Litestream（SQLite 持续复制）或每日 `sqlite3 .backup` | |
| 系统部署 | NixOS flake + colmena / deploy-rs | 两台主机共用一个 flake |
| 桌面配置 | plasma-manager（home-manager 模块） | 覆盖面板、小组件、KRunner、快捷键 |

## 2. 入口与通知

| 需要 | 复用 | 备注 |
|---|---|---|
| IM 入口 | **DS-Bot**（现有）；需要更多平台时用 **AstrBot** | AstrBot：AGPL-3.0，支持 QQ、企业微信、飞书、钉钉、公众号、Telegram，带 MCP 和插件 |
| 手机连接 | KDE Connect | 通知、短信、剪贴板、远程命令、分享 |
| 推送 | ntfy（自托管）/ HA companion | |
| 桌面入口 | KRunner 插件 | 一句话直接入账 |
| 语音 | FunASR / SenseVoice（转写）、CosyVoice（合成） | 中文效果好，本地运行 |

## 3. 模型与推理

| 需要 | 复用 | 备注 |
|---|---|---|
| 统一模型网关 | **LiteLLM** | OpenAI 兼容接口，路由、回退、花费统计都在这里 |
| 本地推理 | ollama / vLLM（工作站 GPU） | 跑 7–9B 的 Qwen 等模型 |
| 结构化决策 | Jev（TypeSafe）或 JSON Schema 约束输出 | 走 `decide()` 接口，后端可替换 |
| N100 兜底分类 | sentence-transformers + bge 中文小模型 + SetFit 少样本分类 | 跑在 CPU 上 |
| 召回 | SQLite FTS5 / sqlite-vec，或 Khoj | |
| 代码与多步任务 | Orca + Devin / Codex / Claude Code | |
| GUI 软件驱动 | CLI-Anything harness → computer-use + Jev | 见 [系统拓扑](system-topology.md) |
| 上网和信息获取 | agent-reach（已装） | |

## 4. 能力 provider

| 能力 | 复用 |
|---|---|
| 视频 | Remotion、ffmpeg、auto-editor、PySceneDetect、Kdenlive（MLT）、DaVinci Resolve 脚本 API |
| 音乐 | ACE-Step 1.5（生成，Apache-2.0）、REAPER（ReaScript）、MuseScore |
| 图像 | ComfyUI、ArtCraft PhotoCraft CLI、Krita、ImageMagick |
| 订阅 | RSSHub + Miniflux / FreshRSS；公众号可以用 wewe-rss（已归档，能用多久不确定，只当备选） |
| 价格监控 | changedetection.io |
| 记账 | double-entry-generator（支付宝 / 微信 → Beancount）+ Fava |
| 间隔重复 | Anki + AnkiConnect |
| 日历 | Radicale |
| 菜谱 | Mealie / Tandoor |
| 照片 / 书 / 音乐 / 影视 | Immich / Calibre / beets + Navidrome / Jellyfin |
| 墨水屏 | OpenEPaperLink（已定型） |
| 状态灯 | WLED |
| 热敏打印 | python-escpos |
| 电源 | NUT（UPS）、Wake-on-LAN |

## 5. 必须自建的部分（没有先例）

| 自建件 | 为什么没有现成的 | 大小 |
|---|---|---|
| `ev` 封装 + 分派 hook | 只是把 Taskwarrior 的 UDA 接到规则表上，每个人的规则都不一样 | 几百行脚本 |
| 能力 toml 和入口选择题 | 能力清单是你自己的 | 数据文件 + 一个提示词模板 |
| 呈现面的渲染模板 | 墨水屏和小组件显示什么由你决定 | 模板 |
| 场景 | 同上 | toml / HA script |

其余部分有现成项目就不自己写。新增需求时，先在本表里补一行"复用什么"，再动手。
