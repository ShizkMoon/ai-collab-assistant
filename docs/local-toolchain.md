# 本机工具链选型

本机软件选型优先考虑自动化与命令行可编程性：**能通过 CLI 或脚本接口完成的任务不启动 GUI，必须操作 GUI 的任务优先使用无障碍树而非像素级点击**。本文记录选型标准与软件矩阵，本机实际安装版本以 `upctl` 状态为准。

## 1. 接口调用优先级

Agent 调用本地软件时按以下优先级依次选择：

1. **原生 CLI**：可直接通过命令行参数调用、具备明确退出码与标准输出。
2. **内嵌脚本 API**：支持无头运行 Python / Lua / JS 脚本（如 Blender `bpy`、REAPER ReaScript），通过薄封装脚本转为标准 CLI。
3. **`CLI-Anything` 封装（Agent Harness）**：针对缺少原生 CLI 的桌面应用，采用 [HKUDS/CLI-Anything](https://github.com/HKUDS/CLI-Anything) 模式封装出命令行接口。
4. **MCP Server**：作为补充接口接入（如 `re-toolkit` MCP），在需要结构化工具调用时配合使用。
5. **网页接口（`ego-browser`）**：有登录态或需要多步交互的网页任务走 ego(lite) 的 Space + Snapshot，再降级才是 GUI 自动化（见 §2.8）。
6. **GUI 自动化（`agent-desktop` + 视觉点击）**：最后兜底路径，优先经 `agent-desktop` 读取 UI Automation 无障碍树并执行 ref 语义动作（headless、不抢焦点），自绘画布等特殊场景再结合视觉模型与 AutoHotkey v2 / `SendInput` 操作（见 [系统拓扑 §7](system-topology.md#7-gui-自动化分级策略)）。

## 2. 领域工具选型矩阵

### 2.1 游戏开发与 3D 资产

| 软件工具 | 选型定位 | 自动化调用路径 |
| --- | --- | --- |
| **Godot 4** | **首选游戏引擎** | 原生支持 `godot --headless`（资源导入、多平台导出、GUT 测试），已具备 `CLI-Anything` 封装 |
| **Blender** | **主力 3D 建模与渲染** | 原生支持 `blender -b -P` 无头执行 Python 脚本，本机已安装 5.2.3 LTS |
| Houdini | 程序化资产备选 | 提供 `hython` / `hscript` 命令行接口，适合重度程序化生成项目 |
| Unity / Unreal Engine | 大型项目备选 | 支持 `-batchmode` 编译导出，但编辑器体积大、自动化启动开销高 |
| RenderDoc / Nsight Graphics | 图形渲染调试 | 均具备 `CLI-Anything` 封装接口 |

### 2.2 视频制作与摄影处理

| 软件工具 | 选型定位 | 自动化调用路径 |
| --- | --- | --- |
| **Remotion / HyperFrames** | **编程式视频主力** | 全流程 CLI 渲染（`npx remotion render` / `hyperframes` CLI），代码即视频 |
| **Multiplane** | 网页镜头转视频 | 通过 CLI 将符合规范的 HTML 页面确定性渲染为 MP4 镜头 |
| **ffmpeg / ffprobe** | **音视频处理基础底座** | 纯命令行转码、切分、滤镜与响度归一化 |
| **gphoto2 + darktable** | **相机联机与 RAW 冲印** | `gphoto2` 通过 PTP 协议控制索尼 A7R5，`darktable-cli` 批量冲印 RAW 文件 |
| DaVinci Resolve | 专业调色与剪辑备选 | 提供 Linux 原生版本及 Lua / Python 脚本接口 |
| Kdenlive / Shotcut | 开源非线性剪辑备选 | 底层基于 MLT 框架，支持命令行脚本渲染 |
| FilmCraft / EffectCraft / LightCraft | ArtCraft 系列工具 | 原生内置无头 `*-cli` 与 MCP 接口（见 §2.5） |
| DJI Action 5 Pro | 运动相机素材源 | 通过存储卡/USB 文件导入，经 `work.video.ingest` 归一化处理 |

### 2.3 游戏运行与日常托管

| 软件工具 | 选型定位 | 自动化调用路径 |
| --- | --- | --- |
| **MAA / MAAend** | 《明日方舟》与《终末地》日常托管 | 本机原生运行，通过 MAA CLI / Webhook 触发并回收结果 |
| **Steam / `steamcmd`** | 游戏发行与下载平台 | `steamcmd` 支持无头上传构建包（Depot）与管理下载 |
| Steam 原生游戏 | 游戏运行 | 直接运行，不需要兼容层 |

### 2.4 音乐制作与乐谱排版

| 软件工具 | 选型定位 | 自动化调用路径 |
| --- | --- | --- |
| **REAPER** | **主力宿主（DAW）** | Windows 原生运行，支持 ReaScript（Lua / Python）深度无头自动化 |
| **MuseScore 4 / LilyPond** | **乐谱排版与转换** | `mscore` CLI 支持批量导出 PDF / MIDI / MusicXML；LilyPond 纯文本编译乐谱 |
| **FluidSynth** | SF2 音色库合成渲染 | 纯 CLI 将 MIDI 渲染为 WAV 音频 |
| SoundCraft | ArtCraft 系列 DAW | 提供 `soundcraft-cli` 无头命令行与 MCP 接口 |
| Bitwig Studio / Ardour | 备选 DAW | 支持控制器脚本或 Lua 自动化 |

### 2.5 图形设计与办公套件（ArtCraft 系列）

本机已集成开源 Rust 原生创意与办公套件 **ArtCraft 全家桶**（13 个应用，统一由 `upctl update craft` 管理更新，配合 `craft-apps` Skill 调用）。每个应用均提供独立的 `*-cli` 无头二进制与 MCP 接口：

| 应用名称 | 适用领域 | 版本基线 | 无头 CLI |
| --- | --- | --- | --- |
| **PhotoCraft** | 位图与 PSD 图层编辑 | 0.16.0 | `photocraft-cli` |
| **VectorCraft** | 矢量图形与插画 | 0.17.0 | `vectorcraft-cli` |
| **FilmCraft** | 非线性视频剪辑 | 0.13.0 | `filmcraft-cli` |
| **LightCraft** | 图库管理与 RAW 冲印 | 0.14.0 | `lightcraft-cli` |
| **PdfCraft** | PDF 批处理与编辑 | 0.14.0 | `pdfcraft-cli` |
| **EffectCraft** | 动效与 VFX 合成 | 0.17.0 | `effectcraft-cli` |
| **DesignCraft** | 多页版面排版 | 0.13.0 | `designcraft-cli` |
| **FigCraft** | UI 设计与原型制作 | 0.11.2 | `figcraft-cli` |
| **WordCraft** | 文档处理 | 0.11.0 | `wordcraft-cli` |
| **SoundCraft** | 数字音频工作站（DAW） | 0.13.1 | `soundcraft-cli` |
| **DeckCraft** | 演示文稿制作 | 0.11.1 | `deckcraft-cli` |
| **CADCraft** | 2D / 3D CAD 制图 | 0.13.0 | `cadcraft-cli` |
| **GridCraft** | 电子表格处理 | 0.12.1 | `gridcraft-cli` |

传统开源设计工具（**Krita**、**Inkscape**、**GIMP**、**LibreOffice Headless**、`qpdf`）作为成熟后备方案并存。

### 2.6 电子书阅读与管理（Kindle Paperwhite 5）

| 工具或链路 | 当前状态 | 自动化与维护细节 |
| --- | --- | --- |
| **Calibre 9.16.0** | 已安装 | 提供 `calibredb`、`ebook-convert`、`ebook-meta` 全套原生 CLI，并已配置 `cli-anything-calibre` |
| **KPW5 USB 有线传书** | 已打通 | KPW5 识别为 USB 大容量存储设备（`1949:0324`），Windows 挂载为盘符（通常为 `E:`，实际盘符以设备管理器为准） |
| **KOReader（已越狱接管）** | 已部署 | KPW5 已越狱并安装 KOReader，开启 SSH 与 Tailscale（Userspace 模式）；原厂 OTA 升级程序（`otaupd`/`otav3`/`otaup`）均已重命名为 `.bck` 禁用 |
| **OPDS / Send to Kindle** | 无线传书备选 | 支持通过 KOReader OPDS 目录拉取或 Calibre 邮件推送 |

### 2.7 外部平台只读采集（`agent-reach`）

本机已安装 `agent-reach` v1.5.0 及配套上游 CLI（`yt-dlp`、`bili-cli`、`twitter-cli`、`rdt-cli`、`mcporter` + Exa、`OpenCLI`），直接支持网页正文抓取（Jina）、YouTube 字幕、RSS、V2EX、B 站搜索与 GitHub 查询。需要登录态的平台（Twitter/X、雪球、小红书、Reddit、Boss直聘）由用户在本地浏览器导出 Cookie 或登录专用 Profile 后供工具只读调用，Agent 不代管账号密码。

### 2.8 浏览器与网页自动化（ego(lite)）

本机浏览器选型为 **ego(lite)**（Chromium 内核，Windows 版目前为 beta）。选它不是为了换掉日常浏览器，而是因为它的 Agent 模型与本仓的派发方式吻合：

- **Space 隔离**：Agent 在独立的 Space 里开标签页，不切换用户当前标签页、不抢键盘焦点；同一浏览器可并行多个任务，上限取决于本机内存与 CPU。
- **沿用登录态**：首次启动可从 Chrome / Edge 导入资料，Agent 直接使用已登录的账号，不需要另配一套无头 Profile 或导出 Cookie。
- **接口形态**：控制面是 `ego-browser` Skill（已安装至 `%USERPROFILE%\.agents\skills\ego-browser\`，随应用更新）。Agent 通过 `ego-browser nodejs` 提交一段 Node.js 流程（Bash 用 heredoc，PowerShell 写 `.mjs` 文件），helper 已预注入，例如：

  ```bash
  ego-browser nodejs <<'EOF'
  const task = await taskSpace('check campus notices')
  const page = task.page('p1')
  await page.goto('https://example.edu/notice')
  console.log(await page.snapshot())
  await task.finish({ keep: [] })
  EOF
  ```

  核心 API：`taskSpace` / `listTaskSpaces`（Space 复用与接管）、`task.page` / `page.goto` / `page.snapshot`（语义树）、`page.click` / `page.fill` / `page.keyboard.*` / `page.mouse.*`、`task.adopt` / `task.release` / `task.handOff`、`task.finish({ keep })`（收尾并返回回执）、`task.cdp`。实测基线（2026-11-03）：`ego-browser 0.6.2.5`，隔离 Space 内打开页面、snapshot、收尾关闭全链路通过；跨轮引用 `snapshot` 引用用 `loc=...` 或 CSS selector。
- **定位边界**：优先用于「必须有登录态、需要多步点击或上传文件」的网页任务（`info.web.browse`）。无登录态的抓取仍走 `agent-reach` / RSS；纯 HTML 转图仍走 Playwright 无头截图；付款、删除、对外发布照常停在确认点。

已知限制（以官方文档为准）：Linux 版在路线图中、Windows 版为 beta；官方文档未列出 profile / 代理参数，也没有 MCP 或 REST 接口，驱动入口只有 `ego-browser`；会话仅限本机，不支持远程或容器内运行（浏览器任务只能在已登录的工作站会话内运行）。

### 2.9 桌面应用自动化（agent-desktop）

本机 GUI 自动化选用 **agent-desktop**（Vercel Labs，Apache-2.0，Rust 单文件二进制）：通过 UIA 无障碍树读取桌面应用结构，`snapshot` 返回带 ref 的 JSON 树，ref 语义动作默认 headless——不移动鼠标指针、不抢窗口焦点，与本仓「Agent 后台干活、人继续用同一台机器」的取向一致。

- **安装位置**：`%USERPROFILE%\agent-src\tools\agent-desktop\agent-desktop.exe`（GitHub Releases 原生二进制，无 Node 依赖），经 `%USERPROFILE%\.local\bin\` 封装进入 `PATH`；纳入 `upctl update git` 或自定义分区更新。
- **headless / headed 边界**：`click` / `set-value` / `toggle` / `scroll` 等走 UIA 语义调用可后台执行；`type` / `right-click` / 双击 / `press` 需 `--headed`（SendInput 物理输入）。最小化窗口、Session 0、锁屏与 UAC 安全桌面不可达（见 [工作站配置 §4.2](workstation-windows.md#42-桌面自动化命令行接口)）。
- **Agent 调用方式**：Worker 直接调用 CLI；`agent-desktop skills get desktop` 与 `skills get platform` 输出与版本匹配的 agent 使用文档，执行前先读。
- **实测基线（2026-11-03）**：v1.1.0，`version` / `list-apps` / `snapshot`（WindowsTerminal，19 个交互元素）冒烟通过。
- **定位边界**：承担 [系统拓扑 §7](system-topology.md#7-gui-自动化分级策略) 的 UIA 层；自绘画布与树稀疏应用仍走视觉兜底（Jev + AutoHotkey v2）。

### 2.10 任务库（Taskwarrior）

本机任务库选用 **Taskwarrior 3（TW3）**，作为 [事件与任务规格](event-spec.md) 中任务的唯一权威存储。

- **安装路径**：官方无 Windows 二进制，winget / scoop / choco 均不提供；实际路径是 MSYS2 包 —— `winget install MSYS2.MSYS2`，再执行 `C:\msys64\usr\bin\pacman -S mingw-w64-x86_64-task`（或 `pacman -S task`，取 MSYS2 池中的 `task 3.5.0-1`），二进制落在 `C:\msys64\usr\bin\task.exe`。备选是 WSL 内安装，本机未采用（要跨 Windows 路径读写任务文件，MSYS2 更直接）。
- **配置**：`%LOCALAPPDATA%\aica\state\taskrc`，`data.location` 指向同目录，数据库为 `taskchampion.sqlite3`；UDA 已配 `source` / `kind` / `payload` / `thread` / `severity` / `lifetime` / `reversible` / `attempts` / `lane` / `parent_uuid`。`TASKRC` 已设为用户环境变量。
- **字段命名坑**：TW3 的 `parent`、`depends` 等是内置属性，**不能**声明为 UDA；归属关系的 UDA 因此命名为 `parent_uuid`（值仍是父任务 UUID），CLI 侧由 `ev add --parent <uuid>` 写入。
- **调用垫片**：`%USERPROFILE%\.local\bin\task.cmd` 固定 `TASKRC` 后转发 `task.exe`，避免每次手动设环境变量；`%USERPROFILE%\.local\bin\ev.ps1`（及 `ev.cmd`）封装 `add` / `ls` / `next` / `done` / `wait` / `reopen` / `status` / `digest`，默认补 `source:me` 与 `lane:interactive`，写操作直接透传原生 `task` 参数。
- **Agent 侧接入**：DSH 技能 `task-ledger`（源码 `%USERPROFILE%\agent-src\skills-src\task-ledger`，junction 到 `~\.agents\skills\task-ledger`）规定何时写任务、字段取值与交接约定，Agent 通过 `ev` / `task` 命令行读写，不需要 MCP。
- **实测基线（2026-11-06）**：`task 3.5.0`，`winget install MSYS2.MSYS2`（20260927）→ pacman 装包 → `task add/done/annotate/wait/export` 全链路通过；`ev add/ls/done/status/digest` 冒烟通过；sqlite 落在 `%LOCALAPPDATA%\aica\state\taskchampion.sqlite3`。
- **已知限制**：`task` 的报表输出宽度依赖终端（非 TTY 时按 80 列截断）；MSYS2 的路径转换会把 `C:\...` 风格参数改写为 `/c/...`，跨工具调用一律用 `task` 原生命令并传相对/正斜杠路径；`ev` 封装一次性 `TASKRC` override 会打印一行提示，已在该垫片中抑制。
## 3. 工具在事件架构中的角色分类

引入任何新工具前，需明确其在系统中的职责层级：

| 角色层级 | 职责定义 | 典型工具示例 | 调用约束 |
|---|---|---|---|
| **事件采集源（Event Source）** | 从外部拉取或监听变化并生成原始输入 | `agent-reach`、`xxt`、`FileSystemWatcher` 目录监听、Git Hook | 仅负责采集并调用 `ev add`，不直接触发下游重操作 |
| **执行器 / Provider** | 接收派发器调用，独立完成一项能力并返回退出码与摘要 | Home Assistant 服务调用、`biliup`、`ar` CLI、`ebook-convert`、`ego-browser` | 必须支持无交互运行、具备幂等性与明确退出码 |
| **内部工具（Internal Tool）** | 仅在某个 Worker 执行过程中作为底层命令被调用 | `ffmpeg`、`blender`、`reaper`、ImageMagick、Ghidra | 不直接订阅任务库事件 |
| **显示端（Output Surface）** | 只读消费任务库与状态数据并渲染展示 | 墨水屏渲染服务、ThinkSmart View、DSH 会话 | 只读展示，不产生独立的业务状态源 |

## 4. 维护与升级约定

- 全机软件统一接入 `upctl`（`upctl check` / `upctl update [winget|scoop|npm|craft|uv|comfy|git|blender|biliup|all]`），系统层由 `winget upgrade --all` 承担，禁止遗留无法一键更新的手动安装包。
- 新工具引入时先在本文标为"待验证"，跑通一次完整的 CLI 自动化调用后再写入对应能力的 Provider 包。
