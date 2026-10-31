# 本机工具链选型

agent 驱动优先的软件选择:能写脚本的不开 GUI,能开 GUI 的不靠像素。这份清单是选型意图,本机实际装了什么以原生安装为准。

## 调用优先级

1. **原生 CLI**:直接可调用、可入脚本、可入任务记录。
2. **可脚本 API**:嵌入式 Python/Lua/JS(如 Blender `bpy`、REAPER ReaScript),经薄封装转成命令。
3. **CLI-Anything harness**:没有 CLI 的 GUI 软件,用 [HKUDS/CLI-Anything](https://github.com/HKUDS/CLI-Anything) 的 agent-harness 模式造一层 CLI;仓库已有的直接拿来(见下),没有的照其模式给本机软件补一个。
4. **MCP**:不作为主路径(调用面不直观、依赖宿主集成),但有现成好使的可结合。
5. **GUI(computer-use + Jev)**:最后兜底,见系统拓扑的 GUI 自动化一节。

## 游戏开发

| 工具 | 地位 | 自动化路径 |
| --- | --- | --- |
| Godot | **首选引擎** | `godot --headless` 全套(导入/导出/测试),CLI-Anything 有 harness,Linux 原生 |
| Blender | **必备 DCC** | `blender -b -P` 完全可脚本,harness 已有,Linux 原生 |
| Houdini | 进阶备选 | `hython`/`hscript` CLI,Linux 原生,程序化流程适合自动化;商业重 |
| Unity / UE | 重载备选 | Unity `-batchmode`、UE 可编译,但编辑器重、agent 驱动性价比低;大项目才上 |
| Substance Painter / ZBrush | 跨平台受限 | Win/mac 为主;Linux 侧中度需求用 Blender 雕刻+节点材质顶着,重度需求再议 |
| RenderDoc / Nsight Graphics | 渲染调试 | 两者均有 harness |

## 视频与摄影

| 工具 | 地位 | 自动化路径 |
| --- | --- | --- |
| Remotion | **编程式主力** | `npx remotion render` 全 CLI,代码即视频,与 agent 工作流天然契合 |
| Hyperframes / Multiplane | 交互式主力(已选) | CLI 能力待验证;GUI 部分走 computer-use + Jev |
| DaVinci Resolve | 剪辑/调色备选 | 原生 Linux,Lua/Python 脚本 API,免费版够用 |
| FilmCraft / EffectCraft | 跟踪中(ArtCraft) | 剪辑与动效/VFX,官方 CLI+JSON 通道;尚在开发期,先验证再定档 |
| Kdenlive / Shotcut | 开源备选 | 均有 harness,MLT 可脚本渲染 |
| ffmpeg / ffprobe | **底座必备** | 纯 CLI |
| gphoto2 + darktable | **摄影链路(A7R5)** | gphoto2 走 PTP/tether CLI 控制索尼机身,darktable `--cli` 批处理 RAW;Imaging Edge 无 Linux 版,不走 |
| LightCraft | 跟踪中(ArtCraft) | 图库+RAW 冲印,CLI 可控;若成熟可替换 darktable 在链路中的位置 |
| DJI Action 5 Pro | 素材来源 | 生态封闭,按文件导入处理,不做联机控制 |

## 游戏

| 工具 | 地位 | 自动化路径 |
| --- | --- | --- |
| MAA(maa-cli / MAAend)| **明日方舟托管** | CLI 存在,核心是 adb+安卓端;终末地用 MAAend |
| Steam | 平台 | Linux 原生;`steamcmd` 无头装游戏,Proton 跑 Win 游戏 |
| Galgame | 兼容运行 | 多为 Win VN,走 Wine/Proton/Lutris(lutris 有 CLI);自动化兜底 computer-use + Jev |

## 音乐制作

| 工具 | 地位 | 自动化路径 |
| --- | --- | --- |
| REAPER | **类 Cubase 首选** | 原生 Linux,ReaScript(Lua/Python)深度可脚本,便宜轻量 |
| SoundCraft | 跟踪中(ArtCraft) | DAW,官方 CLI+JSON 通道;开发期,成熟后可挑战首选 |
| Bitwig Studio | 备选 DAW | 原生 Linux,控制器脚本 API(JS),modular 强 |
| Ardour | 开源备选 | 原生 Linux,Lua 脚本 |
| MuseScore 4 | **乐谱(类 Guitar Pro)** | 原生 Linux,`mscore` CLI 批转换,可导入 Guitar Pro,有 harness |
| FMOD / Wwise | 游戏音频中间件 | FMOD Studio 有 Linux authoring;Wwise Linux 侧受限,按引擎集成走 |

## 设计/美术("全家桶"位)

| 工具 | 地位 | 自动化路径 |
| --- | --- | --- |
| **ArtCraft 全家桶**(getartcraft.com)| **待验证(目标首选)** | 开源 Rust 原生应用,macOS/Windows/**Linux**/Web 全平台;官方 "agent-ready":每个应用暴露 CLI、JSON 控制通道和 MCP——与调用优先级完全对齐 |
| Krita / Inkscape / GIMP | 成熟备选/兜底 | 原生 Linux,均有 CLI-Anything harness;ArtCraft 各应用尚在 alpha/开发期,功能缺口先用它们顶 |
| Affinity 系 | 不引入 | 无 Linux 原生 |

ArtCraft 各应用与领域需求的对应:PhotoCraft(位图)、VectorCraft(矢量)、FigCraft(UI 设计)、LightCraft(图库+RAW 冲印)、FilmCraft(视频剪辑)、EffectCraft(动效/VFX)、SoundCraft(DAW)、DesignCraft(排版)、WordCraft/GridCraft/DeckCraft/PdfCraft/CADCraft(办公与制图)。多数还在 early alpha / in development,装 Launcher 后逐个验证 CLI 控制通道再升档。

| 应用 | 领域 | 版本 | Stars | CLI | 本机 |
| --- | --- | --- | --- | --- | --- |
| PhotoCraft | 位图/PSD 编辑 | 0.16.0 | 73.6k | ✅ | ✅ 已装 |
| VectorCraft | 矢量插画 | 0.17.0 | 10.8k | ✅ | — |
| FilmCraft | 非线性剪辑 | 0.13.0 | 16.5k | ✅ | — |
| LightCraft | 图库+RAW 冲印 | 0.14.0 | 14.8k | ✅ | — |
| PdfCraft | PDF 阅读/编辑 | 0.14.0 | 18.1k | ✅ | — |
| EffectCraft | 动效/VFX 合成 | 0.17.0 | 8.0k | ✅ | — |
| DesignCraft | 版面排版 | 0.13.0 | 4.8k | ✅ | — |
| FigCraft | UI 设计/原型 | 0.11.2 | 3.6k | ✅ | — |
| WordCraft | 文字处理 | 0.11.0 | 16.3k | ✅ | — |
| SoundCraft | DAW | 0.13.1 | 3.8k | ✅ | — |
| DeckCraft | 演示文稿 | 0.11.1 | 4.3k | ✅ | — |
| CADCraft | CAD 制图 | 0.13.0 | 6.9k | ✅ | — |
| GridCraft | 电子表格 | 0.12.1 | 6.6k | ✅ | — |

13 个应用统一发版节奏(2026-10-25 同一批),每个都带 `linux-x86_64.tar.gz` + `*-cli` 无头包,
官方口径是"agent-ready"。`AniCraft`(2D 动画)在 GitHub 上有仓库但还没发版、也没进官网 lineup。
ArtCraft 主仓(artcraft, v0.41.0)是引擎/生成式那套,不提供 Linux 原生包。

## 办公与文档

ArtCraft 已覆盖大半;补两个开源件:LibreOffice(headless `--convert-to` 批量转换,有 harness)和 PdfCraft 之外的 PDF 处理可用 `qpdf`/`pdftk`。

## 电子阅读(KPW5)

| 工具 | 地位 | 自动化路径 |
| --- | --- | --- |
| Calibre | **首选(已装 9.16.0)** | `calibredb`/`ebook-convert`/`ebook-meta` 全套原生 CLI;CLI-Anything `calibre` harness 已装(`cli-anything-calibre`) |
| KPW5 有线传书 | ✅ 可用 | KPW5 实为 **USB mass storage**(`1949:0324`,不是 MTP),udisks2 自动挂载到 `/run/media/$USER/Kindle`;calibre 已识别。之前"读不到"是设备未挂载;libmtp udev 规则留作其他 MTP 设备兜底 |
| KOReader(已装)| 已越狱+已装+已接管 | KOReader 运行时 SSH 已通(端口/地址/认证方式以本机 ssh 配置与 KOReader 设置为准,不在此记录);公钥已写 `usbnet/etc/authorized_keys` 备用。OTA 三件(`otaupd`/`otav3`/`otaup`)已全改 `.bck`;metrics/索引守护已停用;广告关闭;KUAL 里加了 KOReader `--framework_stop` 入口 |
| Send to Kindle | 备选无线路径 | calibre 内置邮件发送,配一次 Amazon 授权邮箱即可,不依赖 USB |

## 信息获取(agent-reach)

已装 `agent-reach` v1.5.0 + 上游工具链(yt-dlp、bili-cli、twitter-cli、rdt-cli、mcporter+Exa、OpenCLI)。装好即用:网页(Jina)、YouTube、RSS、V2EX、B站搜索、GitHub(gh)。

仍欠的按渠道列出(都需要用户在浏览器侧提供登录态,agent 不代登录):

- Twitter/X、雪球:xueqiu/twitter 的 Cookie-Editor 导出
- Reddit、小红书:Chrome + OpenCLI 扩展(本机目前只有 Firefox,缺 Chrome)
- LinkedIn:mcp-server-linkedin 首次浏览器登录
- Boss直聘:专用 Chrome profile + 手动登录
- 按约定不配:Facebook、Instagram、小宇宙

## 已装与验证快照(2026-10-22,以本机实际安装为准)

- 运行时:nodejs 24.21(nix profile)、uv/uvx、`~/.local` npm 前缀
- agent-reach:5/16 渠道可用,skill 已进 `~/.agents/skills/agent-reach`
- CLI-Anything:`cli-hub` 本体 + `cli-hub-meta-skill`(universal+devin);已配 harness:calibre
- Calibre 9.16.0(`speechSupport=false` 绕过 piper-tts 上游测试失败;要 TTS 时再开)
- ArtCraft Launcher 0.5.1 tarball 实测:二进制在 NixOS 直接可跑;Launcher 本身是 GUI(无 headless),各应用的 CLI/JSON 通道要逐个装出来验证
- **PhotoCraft 0.16.0 已装**(2026-10-27,已从 0.7.0 升级):官方 Linux tarball 装到 `~/.local/opt/photocraft-0.16.0`,`photocraft`/`photocraft-cli` 已进 `~/.local/bin` 并写好 desktop 条目。GUI 需 wrapper 补 `LD_LIBRARY_PATH` 才能找到 `libwayland-client.so.0`(见 `~/.agents/notes/gotchas.md`);`photocraft-cli` 无头直跑,`mcp`/`serve` 即 agent 通道,convert/info/run/batch 已验证

## 维护约定

- 清单按"首选 / 备选 / 待验证"分层;新工具进来先标待验证,跑通一次 agent 驱动再升档。
- 软件安装本身走运维下发链路;每个工具装完顺手验证它的自动化路径(CLI 跑一次)再记进任务记录。
- 换掉某个工具不推翻本页结构,只改对应行。
