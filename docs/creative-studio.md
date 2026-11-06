# 内容创作流水线：统一管线、多候选比选与分发

> 状态：设计中 · 上位文档：[总体架构设计 §3 五类工作流](architecture-north-star.md#3-五类工作流)、[多 Agent 协作](agent-collaboration.md)
>
> 本文统一视频、音乐、长文写作与电子书精修的制作流程，采用**七段式文件管线 + 多候选比选（Best-of-N）+ 协调 Worker + 成品登记表**的架构。能力标识使用 `kind`，底层工具封装为 Provider，阶段交接通过 Taskwarrior 的 `thread` 与 `parent` 关联，仅在最终"对外发布"环节设置人工确认点。

## 1. 跨领域流程对齐

写作、视频、音乐与电子书精修虽然最终产物格式不同，但生产阶段完全同构：

| 流水线阶段 | 长文写作 | 视频制作 | 音乐制作 | 电子书精修 |
|---|---|---|---|---|
| 1. 素材摄入（`ingest`） | 笔记、历史文章、录音 | 相机素材、屏幕录制 | 参考曲目、MIDI 文件 | 原始 EPUB / TXT / PDF |
| 2. 大纲规划（`plan`） | 章节提纲、论点结构 | 分镜表、镜头时长预算 | 曲式结构（Intro/Verse/Chorus） | 目录结构重建方案 |
| 3. 初稿生成（`draft`） | 各章节初稿 | 粗剪时间线与静音裁剪 | 初版生成音频 | 文本清洗与重排初稿 |
| 4. 评审与比选（`review`） | 异构模型审校 | 封面、配乐、标题多候选比选 | 多 Seed 配乐比选 | 抽样页面渲染目检 |
| 5. 合成组装（`assemble`） | 统稿与文风对齐 | 音视频合轨、响度归一化、烧录字幕 | 分轨混音与母带处理 | 字体嵌入与样式打包 |
| 6. 成品导出（`export`） | Markdown / 公众号 HTML | `final.mp4` + 封面 + 字幕 | WAV / FLAC 分轨与乐谱 PDF | 标准 EPUB 3 / PDF |
| 7. 发布准备（`publish`） | 写入公众号草稿箱 | 生成 `biliup` 投稿配置文件 | 导入本地音乐库 | 导入 Calibre 书库 / OPDS |

各领域的差异仅在于**每个阶段调用的 Provider 不同**，管线的七个阶段本身固定不变。

## 2. 七段式文件管线规范

所有创作项目统一以 `<项目根目录>/run/` 作为运行工作区，每个阶段对应一个编号子目录。阶段之间仅通过磁盘文件交接，每个阶段固定产出四类文件：`artifact`（阶段产物）、`metrics.json`（客观量化指标）、`critique.md`（评审意见）与 `decision.md`（下一步动作说明），直接复用 `closed-loop-production` Skill 的阶段规范。

| 序号 | 阶段名 | 输入 | 输出产物路径 | 写回任务库的执行摘要示例 |
|---|---|---|---|---|
| 1 | `ingest` | 原始素材目录或上传文件 | `run/01-ingest/manifest.json`（记录路径、时长/字数、哈希、授权信息） | `"导入 42 个素材文件，总时长 3h12m，其中 2 个无音轨"` |
| 2 | `plan` | `manifest.json` + 任务需求 | `run/02-plan/brief.md`（大纲或分镜表，含各段时长/字数预算） | `"生成 18 个分镜，目标总时长 3:10"` |
| 3 | `draft` | `brief.md` | `run/03-draft/`（初稿文件 + `metrics.json`） | `"完成粗剪 3:24，自动裁剪静音片段 11 处"` |
| 4 | `review` | 初稿 + 评审标准 | `run/04-review/critique.md`（或多候选目录 `cand-*/`） | `"完成审校：第 3 段节奏偏慢，建议缩减 40s"` |
| 5 | `assemble` | 选定候选 + 配乐/字幕等子产物 | `run/05-assemble/final.*` + `mix-report.json` | `"音画合轨完成，响度 -14 LUFS，烧录字幕 97 条"` |
| 6 | `export` | `final.*` | `out/<name>.mp4`、`cover.jpg`、`subs.srt` | `"导出成片 3:12 / 1080p / 214MB"` |
| 7 | `publish` | `out/` + 发布元数据 | `run/07-publish/draft.yaml`（本地发布草稿，不直接提交公网） | `"B 站投稿草稿已生成，等待人工确认发布"` |

管线交接遵循三条基础约束：

1. **文件交接隔离上下文**：下游阶段仅读取上游阶段产出的文件路径，不继承上游 Worker 的对话历史，防止长上下文污染。
2. **结构化结果回写**：每个阶段完成时向任务库写入一句话执行摘要，产物路径与指标文件路径附在任务注解中。
3. **`thread` 与 `parent` 追踪进度**：同一作品的所有子任务共享同一个 `thread` ID，阶段先后依赖通过 `parent`（映射到 Taskwarrior `depends`）表达。

### 2.1 管线阶段与任务状态机的映射

| 管线事件 | 任务库操作 |
|---|---|
| 启动第 N 阶段 | 执行 `task <id> start`，创建带 `parent:<id> thread:<tid>` 的阶段子任务 |
| 阶段子任务完成 | 调用 `ev done <child> "<执行摘要>"`，协调 Worker 检查下一阶段依赖是否就绪 |
| 多候选比选等待人工挑选 | 主任务设为 `ev wait <id> <+2d>`，推送带 `[选A] [选B] [选C] [全部重做]` 按钮的卡片 |
| GPU 显存被其他任务占用 | 子任务设为 `ev wait`，等待获取 GPU 文件锁后唤醒 |
| 放弃当前作品 | 执行 `task <id> delete`，保留 `run/` 目录下的已处理素材备查 |

视频制作任务的命令行拆解示例：

```powershell
$thread = [guid]::NewGuid().ToString()
ev add "剪辑周末爬山 vlog" --kind work.video.make   # 假设返回 id=17
task 17 modify thread:$thread +video

ev add "导入与归一化素材" --kind work.video.ingest --parent 17 thread:$thread
ev add "生成配乐（ACE-Step）" --kind work.music.compose --parent 17 thread:$thread
# 按 thread 查询整条流水线状态
task thread:$thread export
```

## 3. 多候选比选（Best-of-N）

封面生成、配乐制作、标题起草、字幕识别与章节命名等环节，均支持"并行运行 N 个 Provider 或参数组合生成候选，由人工挑选最优项"。该机制封装为通用元能力 `meta.contest.run`：

```toml
# capabilities/meta.contest.run.toml
kind = "meta.contest.run"
desc = "同一需求并行调用多个 Provider 生成候选方案，由人工挑选并记录偏好"
needs = ["workstation.gpu"]
```

```toml
# <项目>/contest/cover.toml
[[contestant]]
name = "comfy-sft"
provider = "work.image.make"
cmd = "comfyui gen '{prompt}' --style product --size 1146x717 --seed {seed}"
cost = "~40s"

[[contestant]]
name = "comfy-base"
provider = "work.image.make"
cmd = "comfyui gen --model base '{prompt}' --size 1146x717 --seed {seed}"

[[contestant]]
name = "photocraft-composite"
provider = "work.image.make"
cmd = "photocraft-cli run cover.json"
```

输出目录结构：

```
run/04-review/cover/cand-01/  artifact.png  metrics.json
run/04-review/cover/cand-02/  artifact.png  metrics.json
run/04-review/cover/choice.json   { "chosen": "cand-02", "rejected": ["cand-01","cand-03"],
                                    "reason": "标题文字更清晰", "ts": "..." }
```

- **选择即偏好样本**：人工点击卡片按钮（`[选1] [选2] [选3] [全部重做]`）后，结果写入 `choice.json` 并调用 `ev done`。周度复盘任务会自动汇总各模型的胜率与高频选中特征，更新至 [知识库与记忆分层](knowledge-memory.md) 的 `mem` 偏好表。
- **客观指标仅做预筛**：`metrics.json` 记录分辨率、响度、错字率等确定性指标，仅用于过滤明显损坏的产物，最终审美选择交由人工完成。

| 比选对象 | 候选生成方式 | 人工挑选粒度 |
|---|---|---|
| 视频封面 | ComfyUI SFT / Base / `photocraft-cli` 图层合成 | 3 选 1 |
| 视频/文章标题 | DeepSeek / Qwen / 本地 8B 模型各生成 5 条 | 挑 1 条或组合修改 |
| 语音转写字幕 | SenseVoice / FunASR Paraformer / Whisper-small | 按错字率挑 1 套底稿 |
| 背景配乐 | ACE-Step 3 组随机种子 × 2 组风格标签 | 挑 1 条 |
| 书籍/长文章节名 | 异构模型重写章节标题 | 整组采纳或微调 |

## 4. 协调 Worker（Pipeline Coordinator）

复杂创作任务由一个绑定在当前 `thread` 上的协调 Worker 负责拆解阶段、检查文件完整性与推进状态，其自身不直接执行剪辑或渲染命令：

| 核心职责 | 明确不做的事项 |
|---|---|
| 拆解管线阶段、创建带 `parent` 与 `thread` 的子任务 | 不亲自执行视频剪辑、渲染或长文正文撰写 |
| 每个阶段结束时检查四件套文件是否齐全，缺失则挂起报错 | 不代替人工对作品质量做主观打分 |
| 在多候选比选阶段整理候选预览卡片并记录 `choice.json` | 不替用户做最终候选拍板 |
| 汇总各阶段一句话执行摘要写回主任务 | 不跨任务与其他 Worker 进行自由对话 |
| 执行失败时按策略重试（最多 3 次并切换备选参数） | 不将超时或半成品静默标记为完成 |

```text
协调 Worker → 创建子任务（ev add --parent --thread）
阶段 Worker → 完成回写：ev done <id> "<执行摘要>" + 产物路径
协调 Worker → 推送给用户：交互卡片（产物预览、时长/字数、[查看] [修改] [选稿] [发布]）
用户回复   → 协调 Worker：点击按钮或回复修改意见，转化为下一步 ev 操作
```

协调 Worker 对应一个独立的 `agent:local` Run，其进度状态完全存储在 `task thread:<tid> export` 与 `runs/<root_id>/` 运行目录中，进程中断后可根据 `root_id` 与 `thread` 无缝恢复（见 [系统拓扑 §6](system-topology.md#6-会话连续性)）。

## 5. 视频制作管线

### 5.1 工程目录结构（`C:\Repos\video\<片名>\`）

在 `%USERPROFILE%\.agents\notes\video.md`（以原生文件为准）规范的基础上，补充 `run/` 与 `out/` 目录：

```
C:\Repos\video\<片名>\
  NOTES.md               记录使用的 Skill、目标时长与画幅、BGM 与音效出处及许可协议
  run/
    01-ingest/manifest.json
    02-plan/brief.md
    03-draft/draft.mp4 + metrics.json
    04-review/{cover,subs,bgm}/cand-*/ + choice.json
    05-assemble/{final.mp4,mix-report.json}
    06-export/{<片名>.mp4,cover.jpg,subs.srt}
    07-publish/draft.yaml
  assets/                音效、配乐与字体子集（纳入 Git 管理）
  out/                   最终交付成片（默认写入 .gitignore，按需强制归档）
```

### 5.2 标准处理命令

**素材归一化、分镜检测与静音裁剪**：

```powershell
New-Item -ItemType Directory -Force run/01-ingest, run/02-plan | Out-Null
# 统一转码为 1080p 中间格式，确保后续拼接参数一致
Get-ChildItem assets/raw/*.MP4 | ForEach-Object {
  ffmpeg -hide_banner -loglevel error -i $_.FullName `
    -vf "scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2,setsar=1" `
    -c:v libx264 -preset fast -crf 18 -c:a aac -b:a 192k `
    (Join-Path run/01-ingest ($_.BaseName + ".mp4"))
}

scenedetect -i run/01-ingest/*.mp4 detect-adaptive list-scenes -o run/01-ingest/
auto-editor run/01-ingest/clip.mp4 --edit audio:threshold=-32dB \
  --export premiere -o run/03-draft/clip.xml
```

**粗剪渲染**：根据视频类型选择对应工具链：

| 视频类型 | 粗剪 Provider | 执行命令 |
|---|---|---|
| 编程式动效 / 宣传短片 / 解说视频 | HyperFrames / Remotion | `npx remotion render src/index.ts Main run/03-draft/rough.mp4` |
| 实拍 Vlog | `auto-editor` + 时间线微调 | `auto-editor ... --export final-cut-pro` |
| 多镜头网页转视频 | Multiplane | `multiplane render --shot main` |

**字幕识别、音画混流与字幕压制**：

```powershell
funasr --model sensevoice-small --input run/05-assemble/final.wav `
  --output-format srt > run/05-assemble/subs.srt

# 混音（人声标准化至 -14 LUFS，背景音乐压低 8dB 并加限幅）
ffmpeg -i run/03-draft/draft.mp4 -i run/05-assemble/bgm.wav `
  -filter_complex "[0:a]loudnorm=I=-14[a0];[1:a]volume=-8dB,alimiter=limit=0.9[a1];[a0][a1]amix=inputs=2:duration=first[aout]" `
  -map 0:v -map "[aout]" -c:v copy -c:a aac -b:a 192k run/05-assemble/final.mp4
# Windows 下 subtitles 滤镜的路径分隔符与盘符冒号需要转义
$sub = (Resolve-Path run/05-assemble/subs.srt).Path -replace '\\','/' -replace '^([A-Za-z]):','$1\:'
ffmpeg -i run/05-assemble/final.mp4 `
  -vf "subtitles='$sub':force_style='FontName=Microsoft YaHei,FontSize=22'" `
  -c:v libx264 -crf 20 -preset slow -c:a copy ("run/06-export/" + (Split-Path $PWD -Leaf) + ".mp4")
```

### 5.3 交付前抽帧与编码检查

```powershell
foreach ($t in 0, 30, 75, 120, 180) {
  ffmpeg -ss $t -i run/06-export/<片名>.mp4 -frames:v 1 -q:v 2 "$env:TEMP\frame-$t.jpg"
}
ffprobe -v error -show_entries format=duration,size:stream=width,height,codec_name `
  -of default=nw=1 run/06-export/<片名>.mp4
```

## 6. 音乐制作管线

```
ACE-Step 生成候选曲目 → REAPER ReaScript 无头后期处理 → 导出分轨（Stems）→ 混音交付
```

```powershell
# 生成 2 个不同风格的候选版本供比选
ace-step generate --prompt "cinematic, warm strings, 90 bpm, hopeful" `
  --duration 180 --seed 42 -o run/04-review/bgm/cand-01.wav
ace-step generate --prompt "city pop, 100 bpm, nostalgic guitar" `
  --duration 180 --seed 7 -o run/04-review/bgm/cand-02.wav

# 调用 REAPER 无头渲染工程
reaper -new -nosplash -renderproject run/04-review/bgm/post.rpp
```

ReaScript 批处理脚本示例（`post.lua`）：

```lua
reaper.Undo_BeginBlock()
reaper.Main_OnCommand(40001, 0)  -- 插入新音轨
reaper.Main_OnCommand(42230, 0)  -- 导出分轨至 run/04-review/bgm/stems/
reaper.Undo_EndBlock("bgm post", -1)
```

乐谱排版导出：`mscore run/05-assemble/score.mscz -o run/06-export/score.pdf`。

**本机已安装工具链替代路径**（在 ACE-Step 与 REAPER 尚未安装时使用 FluidSynth + LilyPond）：

```powershell
fluidsynth -ni -F run/05-assemble/melody.wav -r 44100 -g 0.8 `
  "$env:ProgramFiles\FluidSynth\share\soundfonts\FluidR3_GM2-2.sf2" run/05-assemble/melody.mid
lilypond -o run/06-export run/05-assemble/score.ly
```

## 7. 显卡显存分配（RTX 4080 Laptop 16GB）

本机实测数据：ComfyUI 运行 MOSS-Image SFT int8（1024×1024，25 步）单张耗时 36–52 秒，峰值显存占用 10.7GB；配置 `--disable-smart-memory --reserve-vram 2` 后空闲显存回落至约 3.0GB。显存查询统一通过 Python 调用 NVML 动态库完成，不依赖 `nvidia-smi` 的文本输出。

| 任务类型 | 显存占用（VRAM） | 能否与 ComfyUI 空闲态共存 | 调度说明 |
|---|---|---|---|
| ComfyUI MOSS SFT 出图 | 10.7 GB | - | 需配置 `--disable-smart-memory` 释放空闲显存 |
| ComfyUI 空闲待机（已优化） | ~3.0 GB | - | 常驻基线 |
| ACE-Step 1.5 音乐生成 | < 4.0 GB | 可与空闲态共存 | 不可与 ComfyUI 出图同时运行 |
| Remotion / HyperFrames 渲染 | 0（CPU / 软件光栅化） | 可共存 | 纯 CPU 渲染 |
| `ffmpeg` x264 1080p 压制 | 0 | 可共存 | 纯 CPU 编码 |
| SenseVoice / FunASR 语音转写 | ~2.0 GB | 可共存 | 也可回退至 CPU 运行 |
| MuseScore / FluidSynth / LilyPond | 0 | 可共存 | 纯 CPU 运行 |
| Blender Headless（Eevee / Cycles） | 2–8 GB | 视场景复杂度而定 | Cycles OptiX 渲染需独占显存锁 |
| Godot Headless 游戏导出 | 0 | 可共存 | `godot --headless --export-release` |

**显存互斥规则**：同一时刻只允许运行一个高显存生成任务（ComfyUI 出图、ACE-Step 生成、Blender 渲染或本地大模型推理），所有高显存 Provider 共用 `%LOCALAPPDATA%\aica\state\gpu-lease` 文件锁（见 [模型路由与本地推理 §5](model-fleet.md#5-本地推理显存分配16gb-vram)）。CPU 类任务可并发执行。

通过 NVML 查询当前显存占用的脚本：

```python
# vram.py —— 通过 NVML 查询显存；Windows 下 DLL 由驱动安装，优先从 NVSMI 目录加载
import ctypes, os, pathlib

candidates = [
    pathlib.Path(os.environ["ProgramFiles"]) / "NVIDIA Corporation" / "NVSMI" / "nvml.dll",
    pathlib.Path(os.environ["SystemRoot"]) / "System32" / "nvml.dll",
]
nvml = ctypes.CDLL(next(p for p in candidates if p.exists()).as_posix())
nvml.nvmlInit()
h = ctypes.c_void_p(); nvml.nvmlDeviceGetHandleByIndex(0, ctypes.byref(h))
m = (ctypes.c_uint64 * 3)(); nvml.nvmlDeviceGetMemoryInfo(h, m)
print(f"VRAM {m[0] / 2**30:.1f}GB total, {m[1] / 2**30:.1f}GB used")
```

Blender 与 Godot 在创作管线中的调用方式：

| 工具 | 适用环节 | 标准无头命令 |
|---|---|---|
| Blender Headless | 3D 镜头渲染、片头立体字、产品展示动画 | `blender -b scene.blend -P render.py -o //run/03-draft/frames/ -F PNG -a` |
| Godot Headless | 游戏实机演示录制、UI 交互动效导出 | `godot --headless --path . --export-release "Windows Desktop" run/06-export/demo.exe` |
| 序列帧合成视频 | 将 Blender 输出序列帧压制为 MP4 | `ffmpeg -framerate 30 -i run/03-draft/frames/%04d.png -c:v libx264 -pix_fmt yuv420p out.mp4` |

## 8. 作品分发与成品登记

### 8.1 分发渠道与确认点边界

| 分发渠道 | 调用工具 | 是否触发确认点 | 执行边界 |
|---|---|---|---|
| B 站投稿 | `biliup`（`%USERPROFILE%\.local\bin\biliup.exe`，配置在 `%APPDATA%\biliup\`） | **触发对外发布确认点** | 管线仅生成 `draft.yaml`，人工确认后才执行 `biliup upload` |
| 微信公众号 | Markdown 转 HTML + 官方草稿箱接口 | **触发对外发布确认点** | 仅上传至公众号后台草稿箱，由人工点击群发 |
| 播客 RSS | 静态 RSS Feed 生成 | **触发对外发布确认点** | 先生成本地 Feed 预览，人工确认后同步至公网 |
| Kindle 阅读器 | Calibre + OPDS / KOSync | 无需确认（私有设备） | 精修完成后直接推送 |
| Jellyfin / Immich / Navidrome | 本地媒体库目录扫描 | 无需确认（私有媒体库） | 导出后直接归档入库 |

### 8.2 B 站投稿配置示例

```yaml
# run/07-publish/draft.yaml：经人工确认后调用 biliup upload 提交
line: cnbldsa
limit: 3
submit: app
streamers:
  - title: "周末爬山 vlog｜3 小时素材剪成 3 分钟"
    tag: "vlog,户外,爬山"
    desc: "素材拍摄于 DJI Action 5 Pro，配乐由 ACE-Step 生成，字幕使用 SenseVoice 转写"
    cover: run/06-export/cover.jpg
    tid: 21              # 21=日常，4=电子竞技/游戏，188=数码科技，201=科学科普
    copyright: 1
```

```powershell
biliup -u "$env:APPDATA\biliup\cookies.json" upload -c run/07-publish/draft.yaml
biliup list --not-pubed
biliup show BV1xxxxxxxxx
biliup append --vid BV1xxxxxxxxx run/06-export/第2集.mp4
```

注：`biliup` 关闭评论与弹幕的参数名为 `--up-close-reply` 与 `--up-close-danmu`；若遇到 `601` 错误码表示上传频次过快，需间隔十余分钟后重试；请使用 `%USERPROFILE%\.local\bin\biliup.exe`（预编译 `biliupR`），不要安装缺少入口的 PyPI 版本。

### 8.3 成品登记与反馈回收表

所有创作领域的导出成片统一记录在 `%LOCALAPPDATA%\aica\data\studio/works.db` 中，通过 `task_uuid` 与任务库关联：

```sql
CREATE TABLE works (
  id          INTEGER PRIMARY KEY,
  task_uuid   TEXT NOT NULL,          -- 关联的主任务 UUID（thread 根节点）
  kind        TEXT NOT NULL,          -- work.video.make / work.music.compose 等
  title       TEXT NOT NULL,
  artifact    TEXT NOT NULL,          -- 成品文件绝对路径
  sidecars    TEXT,                   -- JSON：{cover, subs, stems, score}
  duration_s  REAL,                   -- 音视频时长（秒）；文本作品为 NULL
  words       INTEGER,                -- 文本字数；音视频为 NULL
  hash        TEXT NOT NULL,          -- sha256(artifact)
  meta        TEXT,                   -- JSON：标题、标签、分区、许可证
  publish     TEXT NOT NULL DEFAULT 'draft',
                                      -- draft | scheduled | published | archived
  channel     TEXT,                   -- bilibili | wechat | podcast | kindle | library
  external_id TEXT,                   -- B 站 BV 号 / 公众号文章 ID / Feed GUID
  published_at TEXT,
  created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE feedback (               -- 发布后数据与评论摘要回采
  id          INTEGER PRIMARY KEY,
  work_id     INTEGER NOT NULL REFERENCES works(id),
  ts          TEXT NOT NULL,
  source      TEXT NOT NULL,          -- biliup | wechat | podcast | manual
  metrics     TEXT,                   -- JSON：{views, likes, coins, favs, comments}
  comment_digest TEXT                 -- 评论区高频反馈摘要
);
```

`export` 阶段完成时自动插入一条 `publish='draft'` 的记录；人工确认发布成功后更新为 `published` 并写入 `external_id`；发布后第 24 小时、72 小时与第 7 天由定时任务拉取播放指标与评论摘要写入 `feedback` 表，供周报复盘参考。

### 8.4 本地私有媒体库归档命令

```powershell
beet import run/06-export/stems/
immich upload run/06-export/cover.jpg
calibredb add run/06-export/<书名>.epub --with-library <书库路径>   # 书库路径以实际创建位置为准
```

## 9. 开源复用与自建边界

| 环节 | 复用的开源工具或规范 | 自建部分与原因 |
|---|---|---|
| 阶段产物规范 | `closed-loop-production` Skill 的四件套规范 | 七段管线的目录与文件命名约定 |
| 任务编排与状态跟踪 | Taskwarrior 3（`thread` / `parent` / `wait` / `recur`） | 协调 Worker 的阶段推进逻辑 |
| 视频渲染与剪辑 | Remotion、HyperFrames、Multiplane、`ffmpeg`、`auto-editor`、`PySceneDetect` | - |
| 音乐与乐谱 | ACE-Step 1.5、REAPER ReaScript、MuseScore CLI、LilyPond、FluidSynth | - |
| 语音转写与封面制作 | FunASR / SenseVoice、ComfyUI、`photocraft-cli` | 多候选比选配置文件 `contest.toml` 与 `choice.json` |
| 平台发布与本地归档 | `biliup`、Calibre、`beets`、Navidrome、Jellyfin、Immich | `works.db` 成品登记表与定时反馈回收脚本 |
