# 工作站配置：Windows 11 原生

> 状态：规划中（本机当前仍为 NixOS，尚未重装） · 角色：本地计算与执行环境基础设施 · 决策见 [ADR 0006](adr/0006-workstation-windows.md)
>
> 选型结论：工作站只保留 **Windows 11 Pro 原生环境**，不装 WSL、不保留 Linux 分区。全部工具使用 Windows 原生版本，路径按 Windows 惯例分开放置。桌面环境为 Windows 11 自带 shell（Explorer + 任务栏 + 开始菜单），不额外引入第三方壳。

## 1. 核心配置决策

| 配置项 | 决定方案 |
|---|---|
| 操作系统 | Windows 11 Pro（单一系统，32 位应用与 x64 应用共存） |
| 桌面环境 | Windows 11 原生 shell；PowerToys 提供窗口管理与快捷键增强 |
| Linux 兼容层 | **不使用 WSL**；确需 Linux 语义的脚本改写为 PowerShell 或 Python |
| 安装方式 | 在 `nvme1n1` 上全新安装，`nvme0n1` 现有 Windows 分区保持系统卷 |
| 系统卷 | `C:`（NVMe，4TB，BitLocker 开启） |
| 数据卷 | `D:`（`nvme1n1` 抹掉后重建为单分区 NTFS，存放全部项目与大文件） |
| 回滚手段 | 系统还原点 + 卷影副本（VSS）+ `restic` 增量备份；软件降级用 `winget install --version` 或 Scoop 版本桶 |
| 引导方式 | UEFI + Windows Boot Manager，Secure Boot 开启 |

## 2. 工作站硬件规格（2026-10-31 本机实测）

| 硬件类别 | 实测参数 |
| --- | --- |
| 机型与显卡架构 | MSI Vector 16 HX A13VHG，MSHybrid 双显卡架构 |
| CPU | Intel Core i9-13980HX（24 核 32 线程） |
| GPU | NVIDIA RTX 4080 Laptop（AD104M，16GB VRAM）+ Intel Raptor Lake UHD 核显 |
| 内存 | 31 GiB 物理内存 |
| 磁盘 A | `nvme0n1` Samsung 990 PRO 4TB：Windows 11 Pro 系统卷 `C:` |
| 磁盘 B | `nvme1n1` Samsung 990 PRO 4TB：数据卷 `D:`（原 NixOS 分区，重装时抹掉） |
| 显示器配置 | 内屏 BOE 2560×1600@240Hz；外接 4K OLED@240Hz（HDMI 直连独显）；外接 3440×1440@240Hz（DP/USB-C） |
| 网络接口 | Intel Wi-Fi 7、Realtek 2.5GbE 有线网卡、Thunderbolt 4 |
| 音频设备 | XMOS-208 USB DAC、Yamaha UR22C 声卡、板载 HDA 声卡 |

本机显示硬件注意事项：OLED 显示器开启 VRR 会出现低灰阶亮度闪烁，建议默认关闭；多屏输出接口枚举顺序在休眠唤醒后可能变化，显示配置需按显示器 EDID 或型号匹配而不是按接口序号；独显 DP 接口连续执行两次 DSC modeset 偶发黑屏，需避免频繁重设模式。

## 3. 目录布局

路径按 Windows 惯例分开：运行时状态与用户数据进用户配置目录，大文件与项目进 `D:`。

| 用途 | 路径 |
|---|---|
| 能力与场景 TOML、规则表、端口配置 | `%ProgramData%\aica\` |
| 运行时状态：Spool、队列、影子测试输出、游标 | `%LOCALAPPDATA%\aica\state\` |
| 导出数据、模型权重缓存、索引 | `%LOCALAPPDATA%\aica\data\` |
| 任务库 | `%LOCALAPPDATA%\aica\state\taskchampion.sqlite3` |
| 项目与视频工程 | `D:\repo\` |
| 大文件：成片、固件镜像、书库、备份暂存 | `D:\aica\` |
| Provider 工具源码 | `%USERPROFILE%\agent-src\tools\` |
| 单体二进制与 Wrapper | `%USERPROFILE%\.local\bin\`（并加入用户 `PATH`） |

- **系统包**：`winget` 为主、`scoop` 管便携式命令行工具。两者都写进 `upctl` 对应分区，不留手动下载的摊子。
- **Provider 工具**：源码留在 `%USERPROFILE%\agent-src\tools\`，构建产物放 `%USERPROFILE%\.local\bin`，由 `upctl update git` 统一 `git pull` 并重建。
- **配置纳管**：`%ProgramData%\aica\` 下本系统接管的文件列在 `managed.list`，用于重装后比对还原；其余配置不进纳管。

## 4. 桌面与自动化接口

### 4.1 显卡与显示

- 独显固定给计算任务（本地推理、渲染、游戏），核显负责桌面合成，通过 NVIDIA 控制面板或 Windows 图形设置按应用指定 GPU。
- 显示切换用 `DisplaySwitch.exe`（复制 / 扩展 / 仅第二屏幕）或 NirSoft `MultiMonitorTool` 按显示器名称切换；分辨率与刷新率通过 CCD API 脚本设置，避免手工点设置面板。
- OLED 外接屏默认关闭 HDR 自动切换与 VRR，防止低灰阶闪烁。

### 4.2 桌面自动化命令行接口

| 控制需求 | 接口 |
| --- | --- |
| 显示器输出、分辨率、刷新率切换 | `DisplaySwitch.exe`、`MultiMonitorTool.exe` |
| 截图（全屏 / 区域 / 窗口） | `nircmd savescreenshot`、PowerShell + `System.Drawing`、`orca computer` 内置截图 |
| 窗口枚举、搜索与激活 | AutoHotkey v2 `WinGet` 系列、`orca computer` 走 UI Automation |
| 全局键鼠事件注入 | AutoHotkey v2 `Send` / `Input`，或 `SendInput` 直接调用 |
| 系统配置读写 | 注册表 `reg.exe`、`Get-ItemProperty` / `Set-ItemProperty`；长期配置以导出 `.reg` 或 JSON 纳管 |
| 音频路由与音量 | PowerShell `AudioDeviceCmdlets`（`Get-AudioDevice` / `Set-AudioDevice`） |
| 剪贴板读写 | `Get-Clipboard` / `Set-Clipboard` |
| 无障碍控件树 | **UI Automation**（UIA），供 `orca computer` 结构化控制 GUI 应用 |
| 通知 | `BurntToast` PowerShell 模块或自建 toast 转发 |

### 4.3 与助理系统的集成点

| 桌面组件 | 集成用途 |
|---|---|
| **PowerToys Run** | `Alt+Space` 呼出输入框直接执行 `ev add` 录入任务，替代 KRunner |
| **任务栏固定项 + 托盘** | 常驻 `evd` 状态、待处理计数 |
| **Windows 通知中心** | 本地通知输出端，与勿扰模式（Focus Assist）状态同步 |
| **Rainmeter 或 WebView2 面板** | 桌面待办计数、最近截止倒计时 |
| **虚拟桌面 + 脚本** | 按通知模式（工作 / 生活 / 专注）切换壁纸与桌面布局 |
| **Windows 凭据管理器 / DPAPI** | 本地令牌与密钥的加密存储后端 |
| **Phone Link** | 手机通知同步、短信与通话记录 |
| **ego(lite) + `ego-browser`** | 浏览器选型（Chromium，Windows beta）：Agent 在独立 Space 内操作并沿用登录态；首次安装从 Chrome / Edge 导入资料，之后纳入 `upctl update winget`（若未上架则用官方 `.exe` + 自定义 update 函数），见 [本机工具链选型 §2.8](local-toolchain.md#28-浏览器与网页自动化egolite) |

### 4.4 输入法与音频

- 输入法用微软拼音；如需要 Rime，用 Windows 版小狼毫，词库放在用户数据目录。
- 音频默认输出设为 XMOS USB DAC，保留 Yamaha UR22C 输入通道。显示器 HDMI/DP 音频设备在 `AudioDeviceCmdlets` 规则里显式禁用，避免切换显示器时默认声卡漂移。

## 5. 更新、回滚与故障恢复

| 场景 | 操作 | 恢复手段 |
|---|---|---|
| 日常软件更新 | `upctl update`（内部调 `winget upgrade --all` 与各分区更新） | 更新前自动建还原点 |
| 单次升级后应用异常 | `winget install --version <旧版本>` 或 Scoop 版本桶回退 | 安装包缓存 |
| 系统级故障（无法进桌面、驱动冲突） | 系统还原点回滚；必要时用安装介质修复 | 还原点 + `D:\aica\backup` |
| 数据误删或损坏 | `restic restore` 从 `D:\aica\backup` 取回 | 卷影副本（VSS）保留最近 30 天 |

自动规则：`upctl` 在每次安装或升级前调用 `Checkpoint-Computer` 建还原点；`restic` 每日 02:00 增量备份 `%LOCALAPPDATA%\aica` 与 `D:\repo`，保留 7 日 / 4 周 / 6 月三档。**还原点不覆盖用户数据**，业务数据只靠 `restic` 与 VSS。

**重装系统不重建业务状态**：任务库、Spool 与游标位于 `%LOCALAPPDATA%\aica\state`，恢复备份即可继续；回滚系统不应回滚已发生的任务事实。

## 6. 本地服务与电源管理

- **常驻服务**：Orca、Taskwarrior + 派发器守护进程 `evd`、本地推理服务。桌面应用型服务用 WinSW 或 `sc.exe` 注册为 Windows 服务；用户态进程用「登录时启动」的计划任务。
- **定时任务**：统一走任务计划程序（`schtasks` 或任务 XML），替代 `systemd.timer`。任务 XML 纳入 `%ProgramData%\aica\tasks\` 并由安装脚本 `schtasks /create /xml` 注册。
- **保持唤醒**：工作站独机常驻，接交流电时禁止睡眠——电源计划设为「从不睡眠」，或用调用 `SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED)` 的守护进程在 AC 供电下持有唤醒锁，电池供电时恢复默认策略。
- **电池保护**：长期插电使用，MyASUS / MSI Center 里把充电上限设到 60–80%。
- **夜间批处理窗口**：**01:00–07:00**，与本地推理共用 `%LOCALAPPDATA%\aica\state\gpu-lease` 显存锁（见 [模型路由与本地推理 §5](model-fleet.md#5-本地推理显存分配16gb-vram)）。批处理队列非空时，批处理守护进程持有唤醒锁，队列清空后释放。

## 7. 构建与验证

```powershell
just check          # pytest + PSScriptAnalyzer + 配置语法校验
```

`work.code.verify` 的验收命令在 Windows 上替换为上面的命令，不得退化为只检查退出码为 0 的空命令，否则「假完成」会重新出现。具体见 [能力目录](capabilities.md) 与 [开发与逆向工程 §1](work-devsec.md#1-代码开发流水线)。

## 8. 与 Windows 原生工具链的取舍

- **《明日方舟》《终末地》与 MAA**：直接在本机跑，不再需要跨系统 SSH 触发。
- **Steam 游戏**：原生运行，不再需要 Proton 兼容层。
- **微信 4.x**：本机 Windows 客户端，数据库位于 `Documents\xwechat_files\...\db_storage`；密钥提取路径见 [IM 采集](im-ingest.md)。
- **需要 Linux 语义的脚本**：改写为 PowerShell 或 Python（`pathlib` 统一处理分隔符），不保留 WSL 兼容分支。
- **仅 Linux 有的工具**：替换为 Windows 原生等价物；找不到等价物的，在 [本机工具链选型](local-toolchain.md) 里标注为「不采用」并写清原因，不静默降级。
