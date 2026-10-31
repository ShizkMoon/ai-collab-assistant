# 工作站：NixOS + KDE Plasma

> 状态：未动工 · 角色：设施层（本机）
>
> 结论：本机继续用 **NixOS**，桌面从 Hyprland 换成 **KDE Plasma 6**。N100 同样用 NixOS，两台机器共用一个 flake。Steam 游戏、《明日方舟》《明日方舟：终末地》及其自动化仍留在 Windows 11。（之前的 CachyOS 方案已放弃。）

## 1. 已定参数

| 项 | 决定 |
|---|---|
| 发行版 | NixOS（工作站和 N100） |
| 桌面 | KDE Plasma 6（Wayland） |
| 游戏 | 同一台笔记本上的 Windows 11，原样保留 |
| 切换方式 | **不需要重装**：在 flake 里关掉 Hyprland、打开 `services.desktopManager.plasma6.enable`，然后 `nixos-rebuild switch`；不满意就回滚 generation |
| 分区 | 保持不变：`nvme1n1` 给 NixOS，`nvme0n1` 上的 Windows 和共用 ESP 不动 |

## 2. 机器事实（2026-10-31 本机实测）

| 类别 | 事实 |
| --- | --- |
| 机型 | MSI Vector 16 HX A13VHG，MSHybrid 双显卡 |
| CPU | i9-13980HX，24C/32T |
| GPU | RTX 4080 Laptop（AD104M）+ Intel Raptor Lake UHD |
| 内存 | 31GiB + zram |
| 磁盘 A | `nvme0n1` Samsung 990 PRO 4TB：Windows 11 Pro for Workstations |
| 磁盘 B | `nvme1n1` Samsung 990 PRO 4TB：NixOS（p1 ESP 1G、p2 btrfs） |
| 引导 | UEFI，systemd-boot，Secure Boot 关闭，ESP 上有 Windows 的手动条目 |
| 显示 | 内屏 BOE 2560x1600@240；4K OLED@240（HDMI，dGPU）；3440x1440@240（DP/USB-C） |
| 网络 | Intel Wi-Fi 7、Realtek 2.5GbE、Thunderbolt 4 |
| 音频 | XMOS-208 USB DAC、Yamaha UR22C、板载 HDA |

旧机得出的硬件结论依然适用：OLED 面板开 VRR 会闪亮度；连接器名不稳定，规则要按 EDID 匹配；dGPU 的 DP 口连续两次 DSC modeset 可能黑屏（只是本机观测）。

## 3. flake 结构

```
flake.nix
hosts/workstation/   # Plasma、NVIDIA、CUDA、ollama、Orca、worker
hosts/n100/          # HA、Mosquitto、Z2M、ESPHome、n8n、ntfy、LiteLLM、账备份
modules/agent/       # Taskwarrior + ev + 分派 hook、能力 toml、场景
home/                # home-manager + plasma-manager
```

- 部署：用 colmena 一条命令下发到两台机器。
- 二进制缓存：国内使用清华、中科大、上交的 nix 镜像；CUDA 包另外配置预编译缓存，避免本地编译。
- 能力 provider 打成 nix 包放进 `nixpkgs-shizuku`，并被 flake 引用。

## 4. 桌面栈

### 4.1 显卡
- `hardware.nvidia.open = true` + PRIME offload；多 GPU 场景用 `KWIN_DRM_DEVICES` 指定 KWin 使用哪块显卡（变量写错会退回软件渲染）。
- Plasma 6.8 起不再有 X11 会话。
- VRR：OLED 屏默认关闭，用 `kscreen-doctor` 逐屏开启。

### 4.2 自动化命令面（替代 hyprctl / grim）

| 能力 | 入口 |
| --- | --- |
| 显示输出、分辨率、缩放、VRR | `kscreen-doctor` |
| 截图 | `spectacle -b -n -f/-a/-r`，或 `org.kde.KWin.ScreenShot2` DBus |
| 窗口列举和激活 | `kdotool` |
| 键鼠注入 | `ydotool` |
| 配置读写 | `kwriteconfig6` / `kreadconfig6`，能声明的部分交给 plasma-manager |
| KWin 脚本 | `org.kde.kwin.Scripting` DBus |
| 音频 | `wpctl` / `pactl` |
| 剪贴板 | `wl-copy` / `wl-paste` |
| 无障碍树（AT-SPI） | 打开 accessibility，作为 `orca computer` 的前提 |

### 4.3 Plasma 与助理系统的集成

| 集成 | 用途 |
|---|---|
| KDE Connect | 手机端入口和输出：通知、短信、剪贴板、分享入账 |
| KRunner 插件 | Alt+Space 输入一句话直接入账 |
| Plasma 小组件 | 显示待处理数量和当前模式 |
| 通知（D-Bus） | 桌面信道，与勿扰模式同步 |
| Activities | 与 Bot 模式（工作 / 生活 / 专注）双向联动 |
| KWallet | 凭据的原生存放处 |

### 4.4 输入法与音频
- fcitx5 + Rime（`i18n.inputMethod`），Rime 词库放在数据层。
- PipeWire + WirePlumber：XMOS DAC 作为默认输出，保留 UR22C，禁用 HDMI/DP 输出；规则写进 NixOS 配置。

## 5. 助理系统在本机

- Orca 常驻，Taskwarrior + 分派 hook，ollama / vLLM 提供本地模型。
- 闲置时自动休眠；N100 通过 Wake-on-LAN 按需唤醒。
- 夜间批处理队列：转码、渲染、训练。

## 6. 游戏侧（Windows 保留）

游戏和 MAA 留在 Windows 11。Linux 这边只保留被编排调用的远程控制入口。
