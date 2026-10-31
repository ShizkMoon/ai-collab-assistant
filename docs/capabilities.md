# 能力目录

> 状态：设计中 · 上位文档：[架构总览](architecture.md)

## 1. 能力和实现分开

- **能力（capability）**：包括名字、一句话描述、几个例句（可以带反例）和所需设施。入口 Agent 和其他能力只认 `kind`。
- **实现（provider）**：具体的工具链，打成 nix 包放进 `nixpkgs-shizuku`，可以多个版本并存。

```toml
# capabilities/work.video.make.toml
kind = "work.video.make"
desc = "把素材剪成成片，带字幕和配乐"
examples = ["把今天录的剪成 3 分钟 vlog", "给这段录屏加字幕"]
not = ["放个视频", "下载这个视频"]
needs = ["workstation.gpu"]
provider = "video-remotion"
```

能力的 toml 和场景的 toml 都放在 flake 里，和 provider 一起版本化。

## 2. 目录

所选工具都优先复用，详细说明见 [开源复用地图](open-source-reuse.md) 和 [本机工具链](local-toolchain.md)。

### 内容创作
| kind | 做什么 | 复用 |
|---|---|---|
| `work.video.make` | 剪辑、字幕、封面、片头片尾、B 站投稿草稿 | Remotion、ffmpeg、auto-editor、FunASR / SenseVoice、biliup |
| `work.video.highlight` | 从游戏录屏里找高光，剪成短视频 | ffmpeg + 场景检测（PySceneDetect） |
| `work.music.compose` | 作曲、编曲、给视频配乐 | ACE-Step 1.5（本地，显存需求小于 4 GB），REAPER 负责后期 |
| `work.music.score` | 乐谱转换和排版 | MuseScore CLI |
| `work.image.make` | 海报、壁纸、墨水屏抖动图 | ComfyUI、PhotoCraft CLI、ImageMagick |
| `work.write.longform` | 多 Agent 长文写作 | 见 [多 agent 协作](agent-collaboration.md) |
| `work.write.wechat` | 公众号排版 | Markdown → 公众号 HTML 的开源排版工具 |
| `work.podcast.make` | 录音 → 转写 → 去口癖 → show notes | FunASR、auto-editor |
| `work.book.polish` | 书籍精修 | 见 [书籍精修流水线](book-polish-pipeline.md) |

### 信息
| kind | 做什么 | 复用 |
|---|---|---|
| `info.feed.digest` | 订阅（RSS / 公众号 / B 站 / 知乎）汇总成每日早报 | RSSHub + Miniflux / FreshRSS、agent-reach |
| `info.paper.track` | arXiv 关键词追踪 | arXiv RSS + Zotero |
| `info.price.watch` | 价格监控，降价提醒 | changedetection.io |
| `info.recall` | 回答"我上次是怎么弄的" | SQLite FTS5 / sqlite-vec，或 Khoj |

### 开发
| kind | 做什么 | 复用 |
|---|---|---|
| `work.code.task` | 代码任务 | Orca + Devin / Codex worker |
| `work.repo.patrol` | 依赖更新、CI 失败巡检 | Renovate、gh CLI |
| `work.nixos.update` | flake 更新 → 构建 → 切换 → 冒烟检查，失败自动回滚 | `nixos-rebuild`、nvd（显示差异） |
| `work.game.build` | Godot / Unity 定时出包 | `godot --headless`、Unity `-batchmode` |

### 生活
| kind | 做什么 | 复用 |
|---|---|---|
| `life.schedule.*` | 日程 | Radicale（CalDAV），与 Taskwarrior 同步 |
| `life.trip.plan` | 解析 12306、机票、酒店邮件，生成行程卡 | n8n IMAP + 入口 Agent 抽取 |
| `life.finance.ledger` | 支付宝 / 微信账单 → 复式记账 → 月报 | double-entry-generator + Beancount + Fava |
| `life.learn.review` | 间隔重复 | Anki + AnkiConnect（FSRS 算法） |
| `life.maintain.*` | 滤芯、体检、续费、证件到期 | Taskwarrior `recur` |
| `life.shop.list` | 购物清单 | Taskwarrior 项目 + 出门时推送 |
| `life.cook.plan` | 菜谱和购物清单 | Mealie / Tandoor |

### 家居
| kind | 做什么 | 复用 |
|---|---|---|
| `home.scene.*` | 回家、离家、睡眠、观影 | Home Assistant script / scene |
| `home.energy.report` | 能耗周报，工作站闲置时休眠 | HA Energy |
| `home.plant.water` | 土壤湿度提醒 | ESPHome + HA |

### 媒体库
| kind | 做什么 | 复用 |
|---|---|---|
| `media.photo.organize` | 照片整理和年度精选 | Immich |
| `media.book.*` | 书库，推送到 KPW5 | Calibre / calibre-web |
| `media.music.library` | 音乐库标签整理 | beets + Navidrome |
| `media.video.library` | 影视库 | Jellyfin |

### 元能力
| kind | 做什么 |
|---|---|
| `meta.capability.propose` | 你说"想加个 X 能力"，worker 起草 toml、provider 和例句，然后提 PR |
| `meta.review.weekly` / `meta.review.yearly` | 周报和年度回顾 |
| `meta.scene.record` | 把你刚做过的一串操作保存成一个场景 |

## 3. 场景 = 能力组合

```toml
# scenes/start-work.toml
trigger = ["me: 开始工作", "nfc: desk"]
steps = ["plasma.activity work", "home.light focus", "info.feed.digest --short", "ev ls --today"]
```

场景本身也是一个能力：可以说出来，可以用 NFC 碰一下，也可以定时触发。家居类场景直接写成 HA script。

## 4. 维护

| 情况 | 做法 |
|---|---|
| 换工具或优化选型 | 改 provider 的 nix 包 → `nixos-rebuild` → 不满意就回滚 generation |
| 新增能力（比如作曲） | 先查 [开源复用地图](open-source-reuse.md)，然后新建 toml 和 provider 包；手动触发几次，满意了再加进入口清单 |
| 能力之间组合 | 用子事项调用（视频 → 配乐），不直接 import 对方的工具 |
| 退役 | 删掉 toml；旧 `kind` 在入口处映射到替代能力 |
| 决定先优化哪个 | 看周报里每个能力的调用次数和返工次数 |
