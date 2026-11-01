# 工作站配置：Arch Linux + KDE Plasma 6

> 状态：设计中（未重装） · 角色：本地计算与执行环境基础设施 · 决策见 [ADR 0006](adr/0006-workstation-arch.md)
>
> 选型结论：工作站操作系统改为 **Arch Linux**，桌面环境为 **KDE Plasma 6（Wayland）**。Steam 游戏、《明日方舟》《明日方舟：终末地》及其自动化工具（MAA）保留在同一台笔记本的 Windows 11 分区上运行。常驻入口暂时不由本机之外的节点承担，见 [ADR 0007](adr/0007-deferred-resident-node.md)。

## 1. 核心配置决策

| 配置项 | 决定方案 |
|---|---|
| 操作系统 | Arch Linux（滚动更新，`linux` 或 `linux-lts` 内核二选一） |
| 桌面环境 | KDE Plasma 6（Wayland 会话） |
| 游戏环境 | 保留 `nvme0n1` 上的 Windows 11 Pro for Workstations 双系统分区 |
| 安装方式 | 全新安装，沿用现有分区布局：`nvme1n1` 为 Linux，`p1` ESP 与 Windows 共用 |
| 根文件系统 | btrfs，`@` 与 `@home` 分卷，`@snapshots` 存放快照 |
| 回滚手段 | `snapper` + `snap-pac` 自动快照；软件降级用 `downgrade` |

## 2. 工作站硬件规格（2026-10-31 本机实测）

| 硬件类别 | 实测参数 |
| --- | --- |
| 机型与显卡架构 | MSI Vector 16 HX A13VHG，MSHybrid 双显卡架构 |
| CPU | Intel Core i9-13980HX（24 核 32 线程） |
| GPU | NVIDIA RTX 4080 Laptop（AD104M，16GB VRAM）+ Intel Raptor Lake UHD 核显 |
| 内存 | 31 GiB 物理内存 + zram 交换分区 |
| 磁盘 A | `nvme0n1` Samsung 990 PRO 4TB：Windows 11 Pro for Workstations |
| 磁盘 B | `nvme1n1` Samsung 990 PRO 4TB：Linux（`p1` 为 1G ESP，`p2` 为 btrfs 根分区） |
| 引导方式 | UEFI + `systemd-boot`，Secure Boot 关闭，ESP 内包含 Windows 引导条目 |
| 显示器配置 | 内屏 BOE 2560×1600@240Hz；外接 4K OLED@240Hz（HDMI 直连独显）；外接 3440×1440@240Hz（DP/USB-C） |
| 网络接口 | Intel Wi-Fi 7、Realtek 2.5GbE 有线网卡、Thunderbolt 4 |
| 音频设备 | XMOS-208 USB DAC、Yamaha UR22C 声卡、板载 HDA 声卡 |

本机显示硬件注意事项：OLED 显示器开启可变刷新率（VRR）会出现低灰阶亮度闪烁，建议默认关闭；多屏输出接口名称在内核重枚举时可能漂移，显示规则需按显示器 EDID 匹配；独显 DP 接口连续执行两次 DSC modeset 偶发黑屏，需避免频繁重设模式。

## 3. 系统目录布局

```
/boot/                        # ESP，与 Windows 共用
/etc/                         # 受管配置；纳入快照
/etc/aica/                    # 能力与场景 TOML、规则表、任务库模块配置
/var/lib/taskwarrior/         # taskchampion.sqlite3
~/.local/state/aica/          # 运行时状态：Spool、队列、影子测试输出、游标
~/.local/share/aica/          # 导出数据、模型权重缓存
~/agent-src/tools/            # Provider 源码仓（如 re-toolkit）
~/.local/bin/                 # 单体二进制与 Wrapper
```

- **系统包**：仅使用官方仓库与 AUR，`pacman` + `paru`。
- **Provider 工具**：以 PKGBUILD 形式维护在 `~/agent-src/tools/`，构建后安装至 `/usr/local/bin` 或 `~/.local/bin`，纳入 `upctl` 的 `git` 分区统一更新。
- **配置纳管**：`/etc` 下由本系统接管的文件记录清单（`/etc/aica/managed.list`），用于重装后比对与还原；其余保持 pacman 默认。
- **包清单导出**：每周由 `upctl` 导出 `pkglist-explicit.txt`，随备份保留。

## 4. 桌面环境与自动化接口

### 4.1 显卡与显示合成

- 通过 `nvidia-open-dkms` + `nvidia-prime` 启用 PRIME Offload；多 GPU 环境下通过环境变量 `KWIN_DRM_DEVICES` 指定 KWin 优先使用核显合成桌面（释放独显显存供本地推理与创作任务使用，需注意路径拼写正确以免回退至软件渲染）。
- KDE Plasma 6.8 起默认采用纯 Wayland 会话。
- 刷新率与 VRR：OLED 外接屏默认关闭 VRR，通过 `kscreen-doctor` 按需单屏调节。

### 4.2 桌面自动化命令行接口

| 控制需求 | 命令行或 DBus 接口 |
| --- | --- |
| 显示器输出、分辨率、缩放与 VRR 调节 | `kscreen-doctor` |
| 屏幕与窗口截图 | `spectacle -b -n -f/-a/-r` 或 `org.kde.KWin.ScreenShot2` DBus 接口 |
| 窗口枚举、搜索与激活 | `kdotool` |
| 全局键盘与鼠标事件注入 | `ydotool` |
| KDE 配置文件读写 | `kwriteconfig6` / `kreadconfig6`（长期配置以导出文件纳管） |
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

- 输入法采用 `fcitx5` + Rime，个人 Rime 词库独立存放在用户数据目录。
- 音频子系统采用 PipeWire + WirePlumber：将 XMOS USB DAC 设为默认音频输出，保留 Yamaha UR22C 专业声卡通道，在 WirePlumber 规则中禁用显示器 HDMI/DP 音频输出以防止切换显示器时默认声卡漂移。

## 5. 更新、回滚与故障恢复

三个动作分别对应三个层级，不能互相替代：

| 场景 | 操作 | 恢复手段 |
|---|---|---|
| 日常软件更新 | `upctl update`（内部调用 `pacman -Syu` 与各分区更新） | 更新前自动快照 |
| 单次升级后应用异常 | `downgrade <pkg>` 取回上一个版本 | 包缓存 `/var/cache/pacman/pkg` |
| 系统级故障（无法进桌面、驱动冲突） | `snapper rollback <id>` 后重启 | 从 `@snapshots` 恢复根卷 |
| 配置误改 | 从 `/etc` 快照比对还原 | `snapper diff` + 手工回填 |

自动快照规则：`snap-pac` 在每次 pacman 事务前后各建一个时间线快照；`snapper` 保留最近 20 个日快照与 10 个月快照，空间不足时按 `snapper` 清理策略淘汰。`/etc` 必须在快照子卷范围内，否则「回滚系统却不回滚配置」会留下更难排查的混合状态。

**残留在运行目录的状态不随快照回退**：任务库、Spool 与游标位于 `~/.local/state`，回滚系统不会撤销业务数据。这是有意的——回滚系统不应回滚已发生的任务事实。

## 6. 本地服务与电源管理

- **常驻服务**：工作站本地常驻运行 Orca、Taskwarrior + 派发器守护进程 `evd`，以及 vLLM / Ollama 本地推理服务，全部以 `systemd` 单元声明。
- **保持唤醒**：由于没有第二台常驻节点发 WoL（[ADR 0007](adr/0007-deferred-resident-node.md)），工作站改为「接交流电时不睡眠」：`systemd-inhibit` 仅在 AC 供电下生效，`HandleLidSwitch=ignore`，电池供电时按正常策略休眠。
- **电池保护**：长期插电使用，充电上限设为 60–80%（BIOS 或 `acpi` 设置），避免电池鼓包。
- **夜间批处理防休眠锁**：夜间批处理窗口定为 **01:00–07:00**，与本地推理共用 `~/.local/state/aica/gpu-lease` 显存锁（见 [模型路由与本地推理 §5](model-fleet.md#5-本地推理显存分配16gb-vram)）。当 `batch` 批处理队列非空时，批处理服务持有 `systemd-inhibit --what=sleep:idle` 抑制锁（锁标识 `/run/aica/batch.active`），队列清空后自动释放。

## 7. 构建与验证

NixOS 时期的 `nix flake check` 与 generation 回滚不再存在，构建验收改为：

```bash
just check          # pytest + shellcheck + 配置语法校验
```

`work.code.verify` 的验收命令随之替换，不得退化为只检查退出码为 0 的空命令，否则「假完成」会重新出现。具体见 [能力目录](capabilities.md) 与 [开发与逆向工程 §1](work-devsec.md#1-代码开发流水线)。

## 8. Windows 双系统边界

Steam 游戏与 MAA 保留在 Windows 11 分区运行，Linux 侧仅保留远程触发与状态回收接口（见 [开发与逆向工程 §3.4](work-devsec.md#34-windows-侧游戏日常托管maa)）。
