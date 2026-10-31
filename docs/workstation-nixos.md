# 工作站配置：NixOS + KDE Plasma 6

> 状态：设计定稿 · 角色：本地计算与执行环境基础设施
>
> 选型结论：工作站操作系统继续采用 **NixOS**，桌面环境由 Hyprland 迁移至 **KDE Plasma 6（Wayland）**。N100 迷你主机同样运行 NixOS，两台设备共用同一个 Flake 仓库。Steam 游戏、《明日方舟》《明日方舟：终末地》及其自动化工具（MAA）保留在同一台笔记本的 Windows 11 分区上运行。

## 1. 核心配置决策

| 配置项 | 决定方案 |
|---|---|
| 操作系统 | NixOS（工作站与 N100 共用 Flake） |
| 桌面环境 | KDE Plasma 6（Wayland 会话） |
| 游戏环境 | 保留 `nvme0n1` 上的 Windows 11 Pro for Workstations 双系统分区 |
| 桌面切换方式 | 无需重装系统：在 Flake 中关闭 Hyprland、启用 `services.desktopManager.plasma6.enable`，执行 `nixos-rebuild switch`；遇到问题直接回滚 NixOS generation |
| 磁盘分区布局 | 维持现状：`nvme1n1` 运行 NixOS，`nvme0n1` 运行 Windows 11 并共用 ESP 引导分区 |

## 2. 工作站硬件规格（2026-10-31 本机实测）

| 硬件类别 | 实测参数 |
| --- | --- |
| 机型与显卡架构 | MSI Vector 16 HX A13VHG，MSHybrid 双显卡架构 |
| CPU | Intel Core i9-13980HX（24 核 32 线程） |
| GPU | NVIDIA RTX 4080 Laptop（AD104M，16GB VRAM）+ Intel Raptor Lake UHD 核显 |
| 内存 | 31 GiB 物理内存 + zram 交换分区 |
| 磁盘 A | `nvme0n1` Samsung 990 PRO 4TB：Windows 11 Pro for Workstations |
| 磁盘 B | `nvme1n1` Samsung 990 PRO 4TB：NixOS（`p1` 为 1G ESP，`p2` 为 btrfs 根分区） |
| 引导方式 | UEFI + `systemd-boot`，Secure Boot 关闭，ESP 内包含 Windows 引导条目 |
| 显示器配置 | 内屏 BOE 2560×1600@240Hz；外接 4K OLED@240Hz（HDMI 直连独显）；外接 3440×1440@240Hz（DP/USB-C） |
| 网络接口 | Intel Wi-Fi 7、Realtek 2.5GbE 有线网卡、Thunderbolt 4 |
| 音频设备 | XMOS-208 USB DAC、Yamaha UR22C 声卡、板载 HDA 声卡 |

本机显示硬件注意事项：OLED 显示器开启可变刷新率（VRR）会出现低灰阶亮度闪烁，建议默认关闭；多屏输出接口名称在内核重枚举时可能漂移，显示规则需按显示器 EDID 匹配；独显 DP 接口连续执行两次 DSC modeset 偶发黑屏，需避免频繁重设模式。

## 3. NixOS Flake 目录结构

```
flake.nix
hosts/workstation/   # KDE Plasma 6、NVIDIA 驱动、CUDA、vLLM/Ollama、Orca、Worker 工具链
hosts/n100/          # Home Assistant、Mosquitto、Z2M、ESPHome、n8n、ntfy、LiteLLM、备份服务
modules/agent/       # Taskwarrior 3 + ev CLI + 派发器 evd、能力与场景 TOML
home/                # Home Manager + plasma-manager 用户态配置
```

- **双机部署**：使用 `colmena` 统一构建并下发至工作站与 N100。
- **二进制缓存（Substituters）**：配置清华大学、中国科学技术大学与上海交通大学 Nix 镜像源，并额外启用 `cuda-maintainers` 二进制缓存，避免在本地从源码编译 CUDA 包。
- **自定义软件包**：各能力对应的 Provider 工具打包为 Nix Derivation 放入 `~/Repo/nixpkgs-shizuku` 并由主 Flake 引用。

## 4. 桌面环境与自动化接口

### 4.1 显卡与显示合成

- 启用 `hardware.nvidia.open = true` 与 PRIME Offload；多 GPU 环境下通过环境变量 `KWIN_DRM_DEVICES` 指定 KWin 优先使用核显合成桌面（释放独显显存供本地推理与创作任务使用，需注意路径拼写正确以免回退至软件渲染）。
- KDE Plasma 6.8 起默认采用纯 Wayland 会话。
- 刷新率与 VRR：OLED 外接屏默认关闭 VRR，通过 `kscreen-doctor` 按需单屏调节。

### 4.2 桌面自动化命令行接口

迁移至 KDE Plasma 6 后，替换原 Hyprland 下 `hyprctl` / `grim` 的标准控制工具如下：

| 控制需求 | 命令行或 DBus 接口 |
| --- | --- |
| 显示器输出、分辨率、缩放与 VRR 调节 | `kscreen-doctor` |
| 屏幕与窗口截图 | `spectacle -b -n -f/-a/-r` 或 `org.kde.KWin.ScreenShot2` DBus 接口 |
| 窗口枚举、搜索与激活 | `kdotool` |
| 全局键盘与鼠标事件注入 | `ydotool` |
| KDE 配置文件读写 | `kwriteconfig6` / `kreadconfig6`（长期配置写入 `plasma-manager`） |
| KWin 窗口脚本控制 | `org.kde.kwin.Scripting` DBus 接口 |
| 音频路由与音量调节 | `wpctl` / `pactl`（PipeWire） |
| Wayland 剪贴板读写 | `wl-copy` / `wl-paste` |
| 无障碍控件树（AT-SPI） | 启用桌面无障碍服务，供 `orca computer` 结构化控制 GUI 应用 |

### 4.3 KDE Plasma 与助理系统的集成点

| 桌面组件 | 集成用途 |
|---|---|
| **KDE Connect** | 手机通知同步、剪贴板共享、文件一键分享录入任务库 |
| **KRunner 插件** | 按 `Alt+Space` 呼出输入框直接执行 `ev add` 录入任务 |
| **Plasma 桌面小组件** | 实时显示当前待处理任务数量与活跃通知模式 |
| **桌面通知（D-Bus）** | 本地通知输出端，与系统勿扰模式状态同步 |
| **Plasma Activities** | 与通知模式（工作 / 生活 / 专注）双向联动切换 |
| **KWallet** | 本地应用密钥与令牌的加密存储后端 |

### 4.4 输入法与音频路由

- 输入法采用 `fcitx5` + Rime（通过 `i18n.inputMethod` 声明），个人 Rime 词库独立存放在用户数据目录。
- 音频子系统采用 PipeWire + WirePlumber：将 XMOS USB DAC 设为默认音频输出，保留 Yamaha UR22C 专业声卡通道，在 WirePlumber 规则中禁用显示器 HDMI/DP 音频输出以防止切换显示器时默认声卡漂移。

## 5. 工作站本地服务与电源唤醒管理

- **常驻服务**：工作站本地常驻运行 Orca、Taskwarrior + 派发器守护进程 `evd`，以及 vLLM / Ollama 本地推理服务。
- **睡眠与有线唤醒（WoL）**：工作站闲置时自动进入挂起睡眠（Suspend-to-RAM），由 N100 按需发送 Wake-on-LAN 魔术包唤醒。由于笔记本无线网卡的 WoWLAN 在 Linux 下不可靠，**WoL 统一通过 Realtek 2.5GbE 有线网口触发**，需在 NixOS 配置中显式开启网卡唤醒（`wakeOnLan.enable = true`），并确保 NetworkManager 不将其覆盖为 `ignore`。
- **夜间批处理防休眠锁**：夜间批处理窗口定为 **01:00–07:00**，与本地推理共用 `~/.local/state/aica/gpu-lease` 显存锁（见 [模型路由与本地推理 §5](model-fleet.md#5-本地推理显存分配16gb-vram)）。当 `batch` 批处理队列非空时，批处理服务持有 `systemd-inhibit --what=sleep:idle` 抑制锁（锁标识 `/run/aica/batch.active`），队列清空后自动释放并恢复空闲休眠，防止渲染或转码任务执行到一半系统自动休眠。

## 6. Windows 双系统边界

Steam 游戏与 MAA 保留在 Windows 11 分区运行，NixOS 侧仅保留远程触发与状态回收接口（见 [开发与逆向工程 §3.4](work-devsec.md#34-windows-侧游戏日常托管maa)）。
