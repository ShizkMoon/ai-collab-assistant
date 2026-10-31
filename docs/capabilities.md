# 能力目录

> 状态：设计中 · 上位文档：[架构总览](architecture.md)、[总体架构设计 §4](architecture-north-star.md#4-执行边界与确认点)
>
> 本目录是全系统 `kind` 取值的**唯一权威清单**。新增能力时先在本表登记 `kind`，再编写对应的 Provider 实现。跨设备自动化场景的完整清单见 [自动化场景](ritual-scenes.md)。

## 1. 能力声明与 Provider 实现分离

- **能力（Capability）**：声明 `kind` 名称、功能简述、正反触发示例、所需软硬件依赖与自治等级。入口意图分类器仅针对 `kind` 进行路由。
- **实现（Provider）**：具体的工具链或脚本，打包为 Nix 包放入 `~/Repo/nixpkgs-shizuku`，支持多版本并存与回滚。

```toml
# capabilities/work.video.make.toml
kind = "work.video.make"
desc = "将原始素材剪辑为带字幕和配乐的成片"
examples = ["把今天录的剪成 3 分钟 vlog", "给这段录屏加字幕"]
not = ["播放这个视频", "下载这个视频"]
needs = ["workstation.gpu"]
provider = "video-remotion"
task_class = "longform"          # 可选，覆盖默认模型路由类别
autonomy = "L2"                  # 可选，见总体架构设计 §5
enabled = true
```

能力与场景的 TOML 配置文件均纳入 NixOS Flake 管理。**新编写的能力默认设置 `enabled = false`**，经过提案与影子测试达标后再正式启用（见 [ADR 0005](adr/0005-proposal-shadow-promotion.md)）。

## 2. `kind` 分类清单

底层工具选型详见 [开源复用清单](open-source-reuse.md) 与 [本机工具链选型](local-toolchain.md)。

### 内容创作

| `kind` | 功能说明 | 复用工具链 |
|---|---|---|
| `work.video.ingest` | 视频素材导入、格式归一化、分镜切分、语音转写 | `ffmpeg`、`PySceneDetect`、`FunASR` |
| `work.video.make` | 视频粗剪、字幕烧录、封面合成、片头片尾拼接 | Remotion、`ffmpeg`、`auto-editor`、`biliup` |
| `work.video.highlight` | 从长录屏中提取高光片段生成短视频 | `ffmpeg` + `PySceneDetect` |
| `work.video.export` | 按不同平台规格导出视频成片 | `ffmpeg` |
| `work.video.publish` | 生成 B 站投稿草稿，经人工确认后提交发布 | `biliup` |
| `work.music.compose` | 作曲、编曲、配乐生成与混音 | ACE-Step 1.5（本地显存占用 < 4GB）、REAPER |
| `work.music.score` | 乐谱格式转换与排版导出 | MuseScore CLI / LilyPond |
| `work.image.make` | 海报生成、壁纸处理、墨水屏抖动量化图制作 | ComfyUI、`photocraft-cli`、ImageMagick |
| `work.write.longform` | 多 Agent 协同长文写作与审校 | 见 [多 Agent 协作](agent-collaboration.md) |
| `work.write.wechat` | 微信公众号文章排版与草稿生成 | Markdown → 公众号 HTML 转换工具 |
| `work.podcast.make` | 录音转写、静音与口癖裁剪、生成节目单（Show Notes） | `FunASR`、`auto-editor` |
| `work.book.polish` | 电子书清洗、重排与元数据补齐 | 见 [电子书精修流水线](book-polish-pipeline.md) |
| `meta.contest.run` | 多候选比选：并行调用多个 Provider 生成候选，记录人工选择结果 | 见 [内容创作流水线 §3](creative-studio.md#3-多候选比选best-of-n) |

### 信息订阅与知识检索

| `kind` | 功能说明 | 复用工具链 |
|---|---|---|
| `info.feed.digest` | 汇总 RSS 与平台订阅，生成每日早报与晚报 | RSSHub + Miniflux / FreshRSS、`agent-reach` |
| `info.feed.item` | 将值得跟进的单条订阅内容录入任务库 | 同上 |
| `info.paper.track` | arXiv 论文关键词追踪与归档 | arXiv RSS + Zotero |
| `info.price.watch` | 商品价格监控与降价提醒 | `changedetection.io` |
| `info.recall` | 检索历史任务记录、笔记与会话（"上次是怎么处理的"） | `kn` CLI（见 [知识库与记忆分层](knowledge-memory.md)） |

### 软件开发与系统维护

`work.code.task` 为代码开发父任务，其下六个子阶段作为带 `parent` 依赖的子任务流转，详见 [开发与逆向工程 §1](work-devsec.md#1-代码开发流水线)。

| `kind` | 功能说明 | 复用工具链 |
|---|---|---|
| `work.code.task` | 代码开发父任务 | Orca + Devin / Codex / Claude Code Worker |
| `work.code.spec` | 将需求整理为结构化开发规格说明（Spec） | `gh issue` / `docs/specs/<slug>.md` |
| `work.code.verify` | 在隔离终端执行构建与测试并检查退出码 | `orca terminal wait --for exit`、`nix flake check` |
| `work.code.review` | 调用异构厂商模型审阅代码 Diff | Orca Worktree + LiteLLM |
| `work.code.merge` | 创建 PR 并在 CI 通过后自动合并 | `gh pr merge --auto` |
| `work.code.release` | 打标签发版、更新 Nix 软件源或 `upctl` 组件 | `gh release`、`upctl update <section>` |
| `work.repo.patrol` | 仓库依赖更新与 CI 失败巡检 | Renovate、`gh` CLI |
| `work.nixos.update` | NixOS Flake 更新、构建、差异对比、切换与失败自动回滚 | `nixos-rebuild`、`nvd` |

### 逆向工程与安全分析

| `kind` | 功能说明 | 复用工具链 |
|---|---|---|
| `work.rev.firmware` | 固件镜像提取、解包、静态反编译与 QEMU 仿真 | `re-toolkit` MCP、`unblob`、Ghidra、QEMU |
| `work.rev.apk` | Android APK 与 OTA 包逆向分析 | `apk_analyze`、`jadx`、Frida |
| `work.rev.elf` | Linux ELF 二进制与内核驱动分析 | `disasm`、`ghidra_analyze`、`frida_trace` |
| `work.rev.protocol` | 网络与串口私有协议抓包及结构解析 | `pcap_capture`、`mitm_capture`、Kaitai Struct |
| `work.rev.device` | 硬件接口只读采集（UART、逻辑分析仪、Flash 读取） | `sigrok-cli`、`openocd`、`flashrom` |
| `work.rev.report` | 汇总分析证据，生成结构化 `findings.json` 与分析报告 | 标准案例仓库模板 |

分析规范与确认点边界见 [开发与逆向工程 §2](work-devsec.md#2-安全与逆向分析)。

### 游戏构建与图形设计

| `kind` | 功能说明 | 复用工具链 |
|---|---|---|
| `work.game.build` | Linux 侧无头构建游戏包与导出 3D 资产 | `godot --headless`、`blender -b -P`、GUT |
| `work.game.release` | 上传构建产物至 itch.io 或 Steam Depot | `butler`、`steamcmd` |
| `work.game.maa` | 远程触发 Windows 侧 MAA 日常托管任务 | OpenSSH / ADB / Webhook |
| `work.design.*` | 位图批处理、矢量转换与参数化 CAD 建模 | `photocraft-cli`、ComfyUI、FreeCAD Headless |

### 日常事务管理

原 `life.maintain.*` 已按实际触发周期与数据结构拆分为独立子项，详见 [日常事务管理](life-operations.md)。

| `kind` | 功能说明 | 复用工具链 |
|---|---|---|
| `life.schedule.*` | 日程管理与提醒 | Radicale（CalDAV）+ `khal` |
| `life.trip.plan` | 解析 12306、机票与酒店确认邮件，生成行程卡片 | n8n IMAP + 结构化字段抽取 |
| `life.finance.ledger` | 导入支付账单并转换为复式记账条目，生成月度报表 | `double-entry-generator` + Beancount + Fava |
| `life.finance.budget` | 月度分类预算核算与超支提醒 | Beancount + `fava-envelope` |
| `life.sub.audit` | 周期性订阅盘点、扣费预告、涨价检测与试用到期提醒 | `subscriptions.toml` + Beancount |
| `life.doc.renew` | 身份证件、校园卡、租约与学籍注册到期提醒 | Taskwarrior `recur` |
| `life.health.checkup` | 年度体检、复诊与疫苗接种计划 | Taskwarrior `recur` |
| `life.health.med` | 日常用药提醒与常备药余量预警 | Taskwarrior `recur` + `life.stuff.inventory` |
| `life.sleep.winddown` | 晚间睡前准备清单与床头墨水屏刷新 | 渲染服务 + 推送通知 |
| `life.sleep.review` | 周度作息统计报表 | Home Assistant Recorder 历史查询 |
| `life.meal.plan` | 周度食谱规划、采购清单生成与食材库存核对 | Mealie |
| `life.fit.session` | 每日训练计划提醒与完成记录 | Taskwarrior `recur` + `plan.md` |
| `life.social.keep` | 亲友生日提醒、人情往来记录与定期联络提示 | Radicale CardDAV + `vdirsyncer` |
| `life.stuff.inventory` | 日常耗材余量、电子产品保修期与物品借出登记 | `inventory.toml`（超过 100 件后迁移至 HomeBox） |
| `life.maintain.home` | 宿舍清洁、滤芯更换等周期性维护 | Taskwarrior `recur` |
| `life.study.plan` | 学习通课程作业、通知同步与考试倒计时 | `xuexitong-cli`（`xxt`）→ `ev add` |
| `life.learn.review` | 间隔重复记忆复习 | Anki + AnkiConnect（FSRS 算法） |
| `life.shop.list` | 随手添加待购物品清单 | Taskwarrior 项目分组 |
| `life.cook.plan` | 已合并至 `life.meal.plan`（保留别名兼容） | - |

### 智能家居控制

| `kind` | 功能说明 | 复用工具链 |
|---|---|---|
| `home.action.*` | 调用 Home Assistant 脚本执行单设备或组合动作 | Home Assistant |
| `home.energy.report` | 用电功耗统计周报 | Home Assistant Energy |
| `home.plant.water` | 绿植土壤湿度过低提醒 | ESPHome + Home Assistant |
| `home.power.*` | UPS 断电告警、电池电量监控与停电挂起 | NUT（Network UPS Tools） |
| `home.plug.power` | 智能插座通断控制与异常高功率提醒 | Home Assistant + Zigbee2MQTT |

跨设备场景（如晨间唤醒、出门通勤、离宿断电、周度复盘等 14 个场景）统一使用 `meta.scene.<id>` 命名，与单设备动作 `home.action.*` 区分，完整列表见 [自动化场景](ritual-scenes.md)。

### 网络与唤醒

| `kind` | 功能说明 | 复用工具链 |
|---|---|---|
| `net.egress` | 校园网多出口状态变更与代理状态同步 | AX6000 `hotplug` 脚本（见 [网络与设备组网](network-fabric.md)） |
| `net.wake` | 由 N100 发送有线 WoL 魔术包唤醒工作站 | `wakeonlan` + Tailscale |

注：`net.github`、`net.nix` 等属于能力配置中 `needs` 字段的**环境依赖标识**，并非任务 `kind`。

### 个人媒体库

| `kind` | 功能说明 | 复用工具链 |
|---|---|---|
| `media.photo.organize` | 照片归档去重与年度精选相册生成 | Immich |
| `media.book.*` | 电子书入库与无线推送至 Kindle（KPW5） | Calibre / `calibre-web` / KOReader |
| `media.music.library` | 音乐库元数据整理与音频流媒体服务 | `beets` + Navidrome |
| `media.video.library` | 本地影视库刮削与管理 | Jellyfin |

### 系统元能力（Meta）

| `kind` | 功能说明 |
|---|---|
| `meta.capability.propose` | 根据高频任务模式生成新能力的 TOML 配置、Provider 骨架与触发示例 |
| `meta.review.daily` / `weekly` / `yearly` | 生成每日早晚报、周度复盘报表与年度总结 |
| `meta.scene.record` | 将近期连续执行的一组操作固化为可复用的场景配置 |
| `meta.scene.<id>` | 记录一次自动化场景的执行结果（如 `meta.scene.morning`） |
| `meta.contest.run` | 并行运行多个 Provider 生成候选方案并收集人工选择结果 |
| `meta.device.discovered` | 局域网发现新设备时的接入提示（见 [网络与设备组网 §6](network-fabric.md#6-设备接入方式)） |
| `meta.triage.pending` | 未命中任何规则或低置信度任务的待人工分类入口 |

### 系统自检事件（`system.*`）

| `kind` | 产生来源 | 触发条件说明 |
|---|---|---|
| `system.task.stalled` | 看门狗定时器 | 任务处于 `doing` 状态的时长超过 `2 × lease` |
| `system.exec.flapping` | 派发器守护进程 | 同一规则在 1 小时内连续失败 ≥ 3 次并触发自动熔断 |
| `system.source.silent` | 看门狗定时器 | 外部数据源超过声明的 `max_silence` 时长未产生新事件 |
| `system.ev.backlog` / `system.ev.gate_stuck` | 看门狗定时器 | Spool 队列积压超限，或门控规则连续抑制达 24 小时 |
| `system.disk.low` / `system.ledger.stale` | 看门狗定时器 | 磁盘剩余空间不足，或任务库备份同步延迟超限 |
| `system.net.egress` | AX6000 `hotplug` | 路由器出口或透明代理状态变化，触发 `parked` 任务恢复检查 |
| `system.power.*` | NUT 守护进程 | 市电中断、UPS 电量低或市电恢复事件 |
| `system.render.failed` | 渲染管线服务 | 显示端图像渲染或下发失败（终端画面保留上一帧） |
| `system.host.journal` | 远端主机日志 | 远端服务器关键 systemd 日志告警接入 |

## 3. 场景配置示例

```toml
# scenes/start-work.toml
id = "start-work"
triggers = ["me: 开始工作", "nfc: desk"]
steps = [
  { action = "plasma.activity", args = { name = "work" } },
  { action = "home.light.focus" },
  { action = "info.feed.digest", args = { short = true } },
  { action = "ev.ls", args = { today = true } },
]
```

场景同样作为能力管理，可通过自然语言、NFC 标签或定时任务触发。其中涉及智能家居的步骤直接调用已有的 Home Assistant 脚本，详细规格见 [自动化场景](ritual-scenes.md)。

## 4. 能力生命周期维护

| 维护操作 | 标准流程 |
|---|---|
| 升级或更换底层工具 | 修改对应 Provider 的 Nix 包定义 → 执行 `nixos-rebuild switch` → 异常时回滚 generation |
| 新增能力 | 先核对 [开源复用清单](open-source-reuse.md)；编写能力 TOML 与 Provider 包（默认 `enabled = false`）；经影子测试验证达标后启用 |
| 能力组合调用 | 通过创建带 `parent` 的子任务进行编排（如视频制作任务派生配乐子任务），不在 Provider 内部硬编码耦合其他能力的脚本 |
| 能力下线 | 设置 `enabled = false` 观察 90 天后移除配置，并将旧 `kind` 在路由表中映射到替代能力 |
| 确定优化优先级 | 依据每周复盘报表中各能力的调用频次与返工率排序 |
| 新增 `kind` 完整步骤 | 1. 登记本文件 → 2. 配置路由规则（[事件运行时与派发器 §1](event-runtime.md#1-规则表)）→ 3. 打包 Provider → 4. 将正反例句导入知识库索引 |
