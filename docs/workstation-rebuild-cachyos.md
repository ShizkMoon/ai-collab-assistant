# 工作站重装:CachyOS + KDE Plasma(开发机定位)

> 状态：未动工 · 角色：执行基座（本机）；§5、§11、附录 A 为执行手册区，其余为设计决策
>
> 结论:本机从 NixOS + Hyprland 整体重装为 **CachyOS + KDE Plasma**,定位收窄为**开发、日常使用、助理系统执行端**;Steam 游戏、《明日方舟》《明日方舟:终末地》及其自动化**全部留在 Windows 11**,Linux 侧只保留被编排调用的远程控制面。安装本身由 **U 盘 live 环境里的 Claude Code CLI** 驱动,分阶段、可断点、每阶段有验收。
>
> 核对基线:2026-10-31 本机实测硬件/分区 + 当日 Arch 官方仓库与 AUR 数据。标注「待确认」的条目是设计上依赖、但尚未在本机验证的事实,不当作结论使用。

## 0. 已定参数

| 项 | 决定 | 来源 |
| --- | --- | --- |
| 发行版 | CachyOS(Arch 系) | 本机默认建议,详见 §2 |
| 桌面 | KDE Plasma 6.x（当前 Arch 仓库为 6.8.x) | 仓库数据 2026-10-31 |
| 游戏落点 | 同一台笔记本的 Windows 11,原样保留 | 用户决定 |
| Arch 职责 | 开发、日常、助理系统、媒体与图形工作 | 用户决定 |
| 旧数据 | 不迁移,全部删除(见 §11 不可逆项) | 用户决定 |
| 安装方式 | U 盘 live + Claude Code 自动配置 | 用户决定 |
| 分区 | `nvme1n1` 整盘给 Linux;`nvme0n1` 的 Windows 与共用 ESP 不动 | 本机实测 |

## 1. 定位变化

| 维度 | 现状(NixOS + Hyprland) | 目标(CachyOS + KDE) |
| --- | --- | --- |
| 系统事实源 | flake 声明式,generation 即回滚 | **不可变系统不再有**:包清单 + dotfiles 入库,回滚靠 btrfs 快照 |
| 桌面控制 | `hyprctl eval`、`grim` | `kscreen-doctor`、Spectacle/portal、KWin DBus script、kdotool（见 §6） |
| 游戏 | Steam/Proton、Waydroid、终末地 DW-Proton | **不承担**,全部移交 Windows |
| 助理系统 | Orca 常驻、DS-Bot 入口、Tailscale | 不变(制度层),只换落地方式 |
| 更新 | `nixos-rebuild` + upctl | `pacman -Syu` + AUR 助手 + upctl 重写(§7) |

不变量(沿用 [设计原则](principles.md) 与 [Personal Agent](personal-agent.md)):Orca 仍是唯一任务账;工人凭证留本机原生位置;破坏性操作需显式指令。**唯一被换掉的底层假设是「系统状态可声明重建」**——这正是本设计必须补的最重一块。

## 2. 发行版判断:为什么 CachyOS 而不是纯 Arch

| 判据 | Arch 官方 | CachyOS | 对本机的影响 |
| --- | --- | --- | --- |
| 内核/调度 | 原版 `linux` | 预编译 `linux-cachyos`(BORE/EEVDF 等变体) | 13980HX 混合架构,调度差异直接影响编译与桌面响应 |
| 桌面开箱 | 全手工 | KDE 安装即用 | 少一轮桌面调参,符合「日常使用」定位 |
| 安装器 | archinstall(JSON 全自动) | **`cachyos-installer --config` + `headless_mode`**(C++ 实现,非 archinstall 包装) | 直接决定 §5 的自动化路径 |
| 快照/回滚 | 需自建 snapper | btrfs(ZSTD-3,7 子卷)+ snapper + snap-pac + `limine-snapper-sync` 开机菜单 | 替代 NixOS generation 的关键 |
| 与上游关系 | 上游 | 上游派生,仓库紧跟 Arch | 滞后风险与混用风险须管理 |
| 生态风险 | — | 社区发行版,维护者规模小 | 出问题时要能退回 Arch 官方仓库 |

结论:**CachyOS**,理由只有两条且都成立——内核/调度与桌面是这台机器日常体验的主要变量;而「可回滚」在本设计里被当作硬需求。代价是接受一个派生发行版的维护节奏。

三条纪律,否则不如用 Arch:

1. **不混用仓库方向**:装的是 CachyOS 就用它的仓库与内核,不要「Arch 装好后加半个 CachyOS」。反向(从 CachyOS 退回 Arch 官方内核)是允许的降级路径,但要一次性切干净。具体原因:`[cachyos]` 仓库**自带 fork 的 pacman**(7.1.0.r9),装了它包管理器就换了实现;官方也明说只用优化内核的话别加 `[cachyos]`,只加 `-v3`/`-v4` 优化仓库。回退步骤官方有,但一步都不能漏(keyring、`%INSTALLED_DB%`、`pacman -Qqn | pacman -S -`)。
2. **CPU 微架构档位**:13980HX 是 Raptor Lake,AVX-512 已熔断,只能上 `x86-64-v3` 仓库档,不能上 v4。CachyOS 安装器会探测,手写配置时别写错。
3. **关键包不吃 AUR 的 CachyOS 内核补丁**:nvidia、linux 头文件这类由发行版指定的组合,以 CachyOS 的 `linux-cachyos*` + 对应 `nvidia-open` 预编译包成对使用为准(§6.1)。

## 3. 机器事实(2026-10-31,本机实测)

| 类别 | 事实 |
| --- | --- |
| 机型 | MSI Vector 16 HX A13VHG,MSHybrid 双显卡 |
| CPU | i9-13980HX,24C/32T,最高 5.6GHz |
| GPU | RTX 4080 Laptop(AD104M)+ Intel Raptor Lake UHD |
| 内存 | 31GiB + zram 15.5GiB |
| 磁盘 A | `nvme0n1` Samsung 990 PRO 4TB:**Windows 11 Pro for Workstations**(p1 300M、p2 16M MSR、p3 3.99T、p4 1G 恢复) |
| 磁盘 B | `nvme1n1` Samsung 990 PRO 4TB:现 NixOS(p1 ESP 1G、p2 btrfs 3.99T) |
| 引导 | UEFI 2.80,systemd-boot 262,Secure Boot **关闭**,TPM2 可用,ESP 上已有 `Microsoft/` 与 `windows.conf` 手动条目 |
| 显示 | 内屏 BOE 2560x1600@240;Microstep 4K OLED@240(HDMI,dGPU);MSI 3440x1440@240(DP/USB-C) |
| 网络 | Intel Wi-Fi 7(BE20 系,`8086:272b`)、Realtek 2.5GbE、Thunderbolt 4 |
| 音频 | XMOS-208 USB DAC、Yamaha UR22C、板载 HDA |
| 外设 | GAOMON M5 V2 数位板、SteelSeries 键盘、罗技接收器、Chicony 摄像头、小米平板、SD Express 读卡器 |

继承自旧机的硬件结论(与发行版无关,重装后仍适用):OLDE 面板开 VRR 会闪亮度;连接器名不稳定,规则要用 EDID 匹配。**DSC 两项降级为本机观测**:旧机在 dGPU 的 DP 口连续两次 DSC modeset 会显示引擎报错并黑屏,3440x1440 长期跑 120Hz——但 2026-10-31 的核查没有在 KDE bugzilla、KWin 源码、NVIDIA 文档里找到对应记录,所以它是本机个例而非已知问题,新系统上按观测值规避即可,不要当成平台缺陷写进排障手册。

## 4. 分区与引导

### 4.1 目标布局(只动 `nvme1n1`)

| 分区 | 用途 | 大小 | 处理 |
| --- | --- | --- | --- |
| `nvme1n1p1` | ESP(与 Windows 共用) | 1G | **保留**,删掉 `EFI/nixos` 旧内核与 `loader/entries/nixos-*`,保留 `EFI/Microsoft` |
| `nvme1n1p2` | btrfs 根 | ~3.6T | 重新格式化 |
| (可选)`nvme1n1p3` | btrfs 数据/共享 | 按需 | 只有确实要「系统与素材分开备份」时才拆 |

CachyOS 默认就是 btrfs + **ZSTD level 3**,默认七个子卷:`@`→`/`、`@home`、`@root`、`@srv`、`@cache`(`/var/cache`)、`@tmp`(`/var/tmp`)、`@log`。按这个来,不要自创布局——快照与 `limine-snapper-sync` 都按默认布局设计。`zram` 默认开;要休眠再加 swapfile(≥ 内存大小;放在 `@` 之外或单独关 noCOW)。

不建议把 `/home` 单独分区:快照要覆盖 `@home`,`/home` 挂载进快照体系对「误删比配置回滚」的场景更实用;素材类大文件本来就该单独管理(见 §7 数据层)。

### 4.2 引导器

| 方案 | 优点 | 缺点 | 取舍 |
| --- | --- | --- | --- |
| Limine + `limine-snapper-sync` | 开机菜单能直接进快照,回滚最短路径 | Windows 条目要手写;`MAX_SNAPSHOT_ENTRIES=10`,受 FAT32 `/boot` 大小限制 | **首选**,这是 CachyOS 自己维护的快照路径;Windows 条目 `protocol: efi` → `bootmgfw.efi` |
| GRUB + `grub-btrfs` | 快照菜单成熟,`os-prober` 探 Windows 稳 | 配置面大,丑 | 备选 |
| systemd-boot | 与现 ESP 一致,Windows 条目手写即可 | 快照菜单要另接,不能原生列快照 | 只在 limine 不可用时 |

不改 Secure Boot。**若 Windows 侧 BitLocker 已启用,任何引导改动都可能触发恢复密钥要求**——装前在 Windows 里 `manage-bde -status` 确认,并先导出恢复密钥(这是唯一一件必须在 Windows 侧做的事)。BitLocker 绑 PCR 7,而**引导链里出现非微软证书时 Windows 会拒绝 PCR7 绑定**,所以在 GRUB/systemd-boot 里 chainload 省不了恢复密钥那一关;Secure Boot 关闭时 Windows 侧仍用微软签名的 `bootmgfw.efi`,不需要 shim(shim 是给 Linux 引导器用的)。

三个引导器探 Windows 的方式不同:`systemd-boot` 自动生成 `auto-windows` 条目;**GRUB 必须开 `os-prober` 并装 `fuse3`**,否则看不到 Windows;Limine 手写 `protocol: efi` 指向 `bootmgfw.efi`。本机 ESP 已有现成 `windows.conf`,systemd-boot 方案几乎零改动。

**CachyOS 文档里"默认引导器"的说法自相矛盾**:引导器对比页说 systemd-boot 是"CachyOS 默认自动配置",快照页却把 Limine + `limine-snapper-sync` 当作快照菜单方案。取舍按需求定,不看"默认"二字:**要开机快照菜单就 Limine**;要少动现有 ESP 就 systemd-boot + 另接快照。安装器支持四种(UEFI 下 systemd-boot / rEFInd / GRUB / Limine 都可选),`has_removable_support` 只有 GRUB/Limine。

### 4.3 双系统四条硬约束

1. Windows 侧关 **Fast Startup**(休眠式关机让 NTFS 处于脏状态;`ntfs-3g` 有休眠保护,但**内核 `ntfs3` 没有**,Linux 侧挂载会直接损坏系统盘)。
2. Linux 侧**不自动挂载**任何 Windows 分区;要读临时 `mount -o ro`。
3. 时钟:`timedatectl set-local-rtc 0`(UTC),并在 Windows 注册表设 `RealTimeIsUniversal=1`,否则每次切换差 8 小时。
4. Windows 大版本更新可能重排 EFI 启动顺序;装完在 Linux 侧 `efibootmgr` 自查,必要时用固件菜单把 Linux 放回第一。

ESP 现状 1G,够用(Arch wiki 建议 1G、保险 4G);**不要再建第二个 ESP**,Windows 默认那 100M 才是常见坑。**archinstall 对"已有 Windows ESP"没有任何专门逻辑**(只认 `status: "existing"` 挂上去),也**不校验 ESP 大小**——如果走 Arch 官方路径,这一点必须由阶段 0 自查;走 `cachyos-installer` 时按它的分区字段显式指定。

若 CachyOS 文档里"用 Limine 作安装器默认"这一条成立,那 `limine-snapper-sync` 的快照菜单会直接可用;若安装器默认给的是 systemd-boot,则要额外接 `sdboot-manage` 一类的入口。**以安装器实际产出的配置为准**,不预设。

## 5. 无人值守安装链路(U 盘 live + Claude Code)

### 5.1 设计约束

live 环境是 **RAM 无状态**的:重启即清空,断网就停摆,API 计费按次。所以这条链路必须满足:

- **阶段化**:每阶段一个脚本 + 一个验收断言,失败不进入下一阶段;
- **状态落 U 盘**:token、配置、日志、进度标记写在 U 盘分区,不写 RAM;
- **破坏性动作单独成段**:清盘、格式化、写引导各自独立,且需要一次性确认令牌;
- **可重入**:同一阶段重复执行不产生二次破坏(格式化前校验 UUID/分区表)。

### 5.2 关键事实:装系统那一步不归 Claude 管

CachyOS 有**两个**安装器,ISO 里都在,`archinstall` 不在:

- GUI:`cachyos-calamares-next`(图形,不可无人值守);
- CLI:`cachyos-cli-installer-new`,二进制 `cachyos-installer`,**官方支持无人值守**:`cachyos-installer --config settings.json --dry-run`;配置里 `"headless_mode": true` 即全自动。headless 分支自己会等网络、装 CachyOS 仓库、校验配置、安装,然后执行可选的 `post_install` 脚本。

它是独立 C++ 实现,**不是 archinstall 的包装**。headless 必填字段:`device`、`fs_name`、`partitions`(除非 `allow_auto_partition`)、`user_name`、`user_pass`、`root_pass`、`desktop`;用 `server_profile` 时反而禁止 `desktop` 并要求 `ssh_authorized_keys`。

**推论(直接改设计)**:分盘和基础安装交给 `cachyos-installer` 的 JSON,Claude 的职责从"装系统"降为**写配置、装完之后做定制、排错**。这比原来的设想更安全也更稳——安装器失败时不会留下 Claude 改了一半的盘。原方案里的 `pacstrap` 路径降为备选(只有当 `cachyos-installer` 在本机硬件上出问题时才用)。

### 5.3 CachyOS live 环境与 Arch live 的差别(影响脚本)

Arch 官方 live(releng)与 CachyOS live 的包集不同,写脚本前要认清:**releng 没有 NetworkManager(用 iwd + systemd-networkd),也没有 curl / wget / jq / git**——所以"从 HTTP 拉安装配置"的官方钩子(`/proc/cmdline` 的 `script=` + `.automated_script.sh`)**缺 curl 会失败**;Arch 官方推荐的定制路径是重打 ISO 的 airootfs,而不是"官方 ISO + U 盘第二分区"。

本设计因此**不依赖 live 环境的包**,只用三样东西:

1. **U 盘上自带的文件**:安装配置、脚本、Claude 二进制、`env`;
2. **ISO 里已有的**:`cachyos-installer`、`pacman`、`arch-install-scripts`、`efibootmgr`、`openssh`;
3. **自带的静态二进制**(不在 ISO 里的工具,先放 U 盘 `bin/`)。

CachyOS live 的具体包集以它的 `packages_desktop.x86_64` 为准(含 `cachyos-cli-installer-new`、`chwd`、`paru`、`networkmanager`、`openssh`、`plasma-desktop`、`arch-install-scripts`、`archlinux-keyring`),**不含 `archinstall`**。

### 5.4 U 盘内容

```
usb/
├── iso/                 cachyos-desktop-linux-<date>.iso
├── install/
│   ├── settings.json    cachyos-installer 的 headless 配置(唯一的系统布局事实源)
│   └── post_install.sh  安装器最后一步调;从这里起才轮到自定义
├── agent/               Claude Code 原生二进制(离线可用,见 5.6 的体积约束)
├── profile/             CLAUDE_CONFIG_DIR 指向这里;settings、skills
├── env                  环境变量脚本(0600):token、代理、BASE_URL
├── scripts/
│   ├── 00-preflight.sh  硬件/磁盘/网络/token 检查
│   ├── 10-install.sh    cachyos-installer --config install/settings.json --dry-run 后再执行
│   ├── 30-config.sh     用户、locale、时区、主机名、zram、NVIDIA 与内核配对
│   ├── 40-desktop.sh    KDE、输入法、音频、显示
│   ├── 50-services.sh   Tailscale、sshd、Orca、upctl
│   └── 90-verify.sh     验收清单(§11)
└── notes.md             人读的断点说明
```

### 5.5 安装阶段

| 阶段 | 做什么 | 验收断言 | 失败回退 |
| --- | --- | --- | --- |
| 0 预检 | 联网(有代理要显式导出)、`lsblk` 快照、确认 `nvme0n1` 上有 Windows 且 **不在** 操作集、token 可调用 | `claude -p 'ok'` 有返回;分区表哈希已记录 | 直接停 |
| 1 装基础系统 | `cachyos-installer --config install/settings.json --dry-run` 复核后执行;headless 自己分盘、装仓库、装桌面、跑 `post_install.sh` | `arch-chroot` 内 `pacman -Syu` 成功;`nvme0n1` 分区表未变 | 从 0 重来 |
| 2 系统配置 | 用户、sudo、locale(zh_CN)、时区(Asia/Shanghai)、主机名 `shizuku`、zram、NVIDIA 与内核配对 | `/proc/driver/nvidia` 正常;`localectl` 正确 | 从快照回滚 |
| 3 桌面 | Plasma、SDDM、PipeWire、fcitx5(含 rime)、字体、显示布局 | 登录进桌面;三屏按 EDID 规则就位;输入法可切换 | 同上 |
| 4 服务 | Tailscale 入网、`sshd` 仅 tailnet、Orca 安装、upctl | `tailscale status` 有节点;`orca --version` 可跑 | 阶段重跑 |
| 5 助理层 | Claude Code / Codex / dsh 安装与凭证恢复、skills、规则文件 | `claude -p`、`codex` 自检通过 | 重装用户层 |
| 6 验收 | 跑 §11 清单 | 全绿后打「黄金快照」 | — |

### 5.6 Claude Code 在 live 环境的接入

**安装**:官方主推原生安装脚本(静态二进制),但**官方支持列表只有 Ubuntu / Debian / Alpine,没有 Arch**(AUR 有 `claude-code`,live 环境没有)。因此按"已知可用但非声明支持"处理,装完必须实测。

**体积是硬约束**:linux-x64 二进制 **328MB**,而 archiso 的 RAM overlay(cowspace)默认 **256MiB**——`cow_spacesize=` 调大,或干脆跑 U 盘上的副本。这是"U 盘方案"里最容易撞墙的一条。

**认证**:`claude setup-token` 生成**一年期** OAuth token,**会打开浏览器授权**、结果打印到终端不落盘,用 `CLAUDE_CODE_OAUTH_TOKEN` 传入;过期只能重新生成。只对订阅账号有效,且只能发模型请求。自定义中转用 `ANTHROPIC_BASE_URL`——官方口径是"标准 Anthropic API 格式的网关可用",但**不背书第三方网关、不支持路由到非 Claude 模型**;且 v2.1.196 起 `ANTHROPIC_BASE_URL` 不是 `api.anthropic.com` 时 **Remote Control 被禁用**。

**配置落盘**:`CLAUDE_CONFIG_DIR` 存在,settings/history/plugins 都跟着走;但**凭据固定读 `~/.claude/.credentials.json`,是否跟随 `CLAUDE_CONFIG_DIR` 未确认**——所以用环境变量传 token,不要赌文件跟随。

**非交互执行的三个坑**(2026 年版本行为):
- `claude -p` 默认 **Manual** 权限模式,没人批准就拒绝;
- `--dangerously-skip-permissions` ≡ `bypassPermissions`,官方定位是"只在隔离容器/VM";而且 **deny 规则在任何模式下都生效**,对"关键路径"的删除照拦,`-p` 下直接拒绝(另有 `CLAUDE_CODE_EVEN_MORE_DANGEROUSLY_SKIP_PERMISSIONS=1` 只从启动环境读,本设计**不用**——破坏性动作本来就该由阶段脚本执行);
- `-p` 会话**不显示 workspace trust 对话框,直接信任目录** → 提交在 `.claude/settings.json` 里的 hooks 会执行。对策:装前审 `.claude/`,或 `--bare`(跳过 hooks/skills/MCP/CLAUDE.md 发现),或 `--settings '{"disableAllHooks": true}'`。

> 这条链路的真正风险不是「Claude 会不会乱删」,而是**网络中断导致安装停在半途、而人又在另一台设备上**。所以阶段脚本必须单机可跑,Claude 是加速器不是依赖。

## 6. 桌面栈与可脚本化控制面

### 6.1 显卡与显示

- **驱动已经只剩 open**:Arch 在 2025-12-20 的新闻里把 `nvidia`/`nvidia-dkms`/`nvidia-lts` **移除了**(不是改名共存),对应的替代是 `nvidia-open`/`nvidia-open-dkms`/`nvidia-open-lts`。本机 AD104M(RTX 4080 Laptop)在 615.78.08 的 supportedchips 里。当前版本:linux 内核配 `615.78.08-3`、lts 配 `-7`、`-dkms` 配 `-1`(任意内核)。`nvidia_drm.modeset` 与 `fbdev` 在上游源码里已经是默认 true,不需要再传内核参数。
- CachyOS 这边给的是预编译组合:`linux-cachyos` + `linux-cachyos-nvidia-open`,后者**精确钉死** `nvidia-utils=615.71.09` 且**取代**同名 dkms 包——升内核必须跟 CachyOS 仓库同步。若嫌钉版本太死,退回 Arch 的 `nvidia-open-dkms` 是可行路径,代价是每次内核升级要重编模块。
- **多 GPU 只能靠 `KWIN_DRM_DEVICES`**:KWin 6.8.2 里 GPU 选择只有这一个变量(冒号分隔);设了它会忽略 seat,写错路径会**直接回退软件渲染**。`__GLX_VENDOR_LIBRARY_NAME` 在 KWin 源码里根本没被读取(只管 GLX 客户端),旧机笔记里那条对 KDE 无效。
- **Vulkan 跨 GPU 拷贝对 NVIDIA 源默认关闭**(KWin 源码注释:驱动侧 dmabuf 有 bug),可用 `KWIN_ALLOW_VULKAN_MGPU_COPIES=1` 强行开。是否值得开,等装完实测。
- **Plasma 6.8 起 X11 会话退役**:Arch 仓库里 `kwin-x11`/`plasma-x11-session` 已不存在,`kwin` 6.8.2 的依赖里也没有 X11 会话,没有"退 X11"这条路;6.8 同时把 NVIDIA 三缓冲改成默认。这改变了旧机的排障策略——以前"Wayland 不稳就退 X11",现在只能往前修。三缓冲真出问题时用 `KWIN_DRM_DISABLE_TRIPLE_BUFFERING=1` 关(6.8.2 源码 `drm_output.cpp` 实证)。
- 240Hz + DSC:旧机观测到 dGPU 的 DP 口连续两次 DSC modeset 会显示引擎报错并黑屏。**KWin 源码里完全没有 DSC 代码**(全仓库 grep 零命中),所以这不是 KDE 能规避的问题,只能归到 nvidia-modeset/内核层;KDE bugzilla 里也没有可引用的对应 bug。处理方式是操作纪律:高带宽 modeset 一次只改一个输出,先 120Hz 验证再上 240Hz。
- VRR:OLED 屏默认关,用 `kscreen-doctor` 逐屏确认而非全局开。

### 6.2 自动化命令面(替代 hyprctl / grim)

| 能力 | KDE Wayland 下的入口 | 说明 |
| --- | --- | --- |
| 列输出/改 mode/缩放/位置/主屏/VRR | `kscreen-doctor`(37 个子命令) | 6.8 新增 `kscreenctl`;输出可直接解析,取代 `hyprctl monitors -j` |
| 截图(区域/窗口/全屏) | `spectacle -b -n -f/-a/-r` 或 `org.kde.KWin.ScreenShot2` DBus(v5) | portal 截图在调用方需要授权弹窗,agent 路径优先 Spectacle CLI |
| 窗口列举/激活 | `kdotool search/getwindowname/windowactivate` | **只有 AUR(0.3.0)**,不在官方仓库 |
| 键鼠注入 | `ydotool`(uinput) | 与旧机一致,跨 X11/Wayland |
| 配置读写 | `kwriteconfig6` / `kreadconfig6` | 改 Plasma/KWin 配置不碰文件格式(flag 细节未逐条核) |
| KWin 脚本 | `org.kde.kwin.Scripting` DBus | 需要窗口几何、工作区级操作时用 |
| 音频 | `wpctl` / `pactl` | PipeWire 1.6.10 + WirePlumber 0.5.18 |
| 剪贴板 | `wl-copy` / `wl-paste` | KWin 只确认实现了 `ext_data_control`,**是否实现 `wlr_data_control` 未确认**——wl-clipboard 走哪条路要装完实测 |
| 锁屏/空闲抑制 | `kscreenlocker` 的 `LockOnStart`/`LockOnResume`/`Timeout`/`LockGrace` 键 | KScreenLocker 只监听 logind 的 `Lock`/`Unlock` 并做 `Inhibit("sleep", …, "delay")`,**不读 logind 的 idle inhibitor**——`systemd-inhibit --what=idle` 挡不住自动锁屏;要抑制锁屏走 ScreenSaver/PowerManagement 两路 DBus |
| 无障碍树(AT-SPI) | 需 `at-spi2-core` + 开 accessibility | `orca computer` 的前提;Plasma 下默认开关**未确认**,装完先测 |

### 6.3 输入法与音频

- `fcitx5` + `fcitx5-rime`(`GTK_IM_MODULE`/`QT_IM_MODULE`/`XMODIFIERS` 三件套写进 `/etc/environment` 或 KDE 环境脚本);Rime 词库单独管理,放数据层。
- PipeWire + WirePlumber:XMOS DAC 作默认输出、UR22C 保留、HDMI/DP 输出与数字麦克风禁用——旧机这套规则按 WirePlumber 配置文件重建。
- **路径与 NixOS 不同,别照抄旧机**:Arch 上 PipeWire 配置在 `/etc/pipewire/`,WirePlumber 走 `XDG_DATA_DIRS` 查找(不是 `/etc/wireplumber/`)。规则放用户级 `~/.config/wireplumber/` 最稳。

### 6.4 登录与自启

两个登录器并存:`sddm` 0.21.0-7 与 `plasma-login-manager` 6.8.2-1,两者的 `[Autologin]` 键都是 `User`/`Session`/`Relogin`。CachyOS 安装器默认给哪个以它产出为准。需要免登录时用 autologin(开发机可开,安全面在磁盘加密,不在登录器);用户级 systemd unit 承载 DS-Bot、Orca、Tailscale 相关辅助进程。

## 7. 系统与包管理:用 Arch 的方式重建 NixOS 的四件事

NixOS 真正给过的四样东西,重装后在 Arch 上必须有对应,否则「可回退」就只是口号:

| NixOS 能力 | Arch 替代 | 落实方式 |
| --- | --- | --- |
| 声明式包集合 | 包清单 | `/etc/pacman.d/` 下维护 `base.list`、`dev.list`、`media.list`;`pacman -Qqe > installed.list` 定期与 git 比对 |
| 可重建系统 | bootstrap 脚本 | U 盘 `scripts/` 即种子;装完归档成 `~/Repo/dotfiles/bootstrap/` |
| generation 回滚 | btrfs 快照 | 每次变更前 `snapper create -d <原因>`;引导菜单或 live 挂载回滚;自动变更前快照由 `snap-pac` 承担 |
| 配置集中 | `/etc` 入 git | 只纳入手写文件(不纳入生成的),`etckeeper` 可选 |

层次划分(沿用旧机「系统包 / 用户层 / 自管二进制」的三分):

- **系统层**:pacman 官方仓库,`pacman -Syu` 统一升级;
- **AUR 层**:`paru`(作者维护活跃、2026-10 仍在更新);AUR 只用来填官方仓库的缺口,升级时人工过目;
- **用户层**:npm(`~/.npm-global`)、uv、cargo、pipx,各自前缀,不污染系统 python/node;
- **自管二进制**:`~/.local/opt` + `~/.local/bin` 包装(Orca、Blender 官方 tarball、biliupR、ArtCraft),必须接进 upctl。

### 7.1 工具链映射(结论,细节见附录 A)

- 对照 156 个工具:**官方仓库 132、仅 AUR 25、两者都没有 1**(2026-10-31 直读仓库数据库与 AUR RPC)。主要缺口按领域看没有掉队的,逆向/硬件类也基本齐全。
- **少量只能 AUR**:`dasel`、`sasquatch`、`jefferson`、`unyaffs`、`android-apktool`、`abootimg`、`frida`、`python-oletools`、`readpe`(原 pev)、`can-utils`、`tio`、`kdotool`、`mtkclient`、`kaitai-struct-compiler`、`ubi_reader`;
- **两条都没有、只能 pipx/源码**:`unblob`;
- re-toolkit(现为 nix 包 + MCP):迁成 `~/agent-src/mcp/re-toolkit` 的 uv 项目,`uv tool install` 进 PATH,MCP 注册不变。**这是本设计里唯一需要重写代码而不是重新打包的部分**。
- 包名陷阱:`pandoc` 实为 `pandoc-cli`、`exiftool` 实为 `perl-image-exiftool`、`delta` 实为 `git-delta`、`7z` 实为 `7zip`、`edid-decode` 在 `v4l-utils` 里、`aapt2` 走 `android-sdk-build-tools`。
- AUR 互斥对只能二选一:`yq` ↔ `go-yq`、`rust` ↔ `rustup`(都 provides cargo)、`tldr` ↔ `tealdeer`。
- AUR 里四处要盯:`android-apktool` 标 OutOfDate 但版本正是上游最新(疑误标)、`davinci-resolve` 标 OutOfDate、`payload-dumper-go` 落后上游、`frida` 落后上游;`abootimg` 自 2021 未动(上游本身停更),Qualcomm 侧改用 AUR `qdl`。

### 7.2 upctl 重写

旧 `upctl` 的 `nix` section 换成 `pacman`,新增 `aur`;`blender`/`biliup`/`craft` 逻辑可原样保留。建议 section:`pacman | aur | npm | uv | cargo | craft | git | opt | all`,每周 user timer 跑一次,日志仍落 `~/.local/state/upctl/last.log`。**升级前自动快照**写进 `pacman` section 的第一步。

## 8. 助理系统在新机上的落地

| 组件 | 旧落地(NixOS) | 新落地(Arch) | 注意 |
| --- | --- | --- | --- |
| Orca | `pkgs/orca.nix` 从 AppImage 解包 | 官方 AppImage 直跑,放 `~/.local/opt`,`upctl` 一条 section 管更新 | 旧补丁 `--disable-features=WaylandWpColorManagerV1` 是 Hyprland 广色域 bug 的规避,换 KDE 后先验证是否需要 |
| Claude Code / Codex / dsh | 已经是 npm 用户层 | 不变 | 官方 Node 二进制仍是硬约束(dsh 会读 Node 内建符号) |
| DS-Bot | 待部署 | 不变 | 入口层与系统发行版解耦 |
| re-toolkit MCP | nix 包 | uv 项目(§7.1) | 工具名与注册键保持不变 |
| Tailscale | systemd | pacman 包 + `tailscaled` | SSH 只走 tailnet 的规则不变 |
| 薄入口脚本 | `~/.local/bin/` | 不变 | 只暴露创建/查询/取输出/追问四类动作 |

## 9. 游戏侧衔接(Windows 保留)

边界只有一句:**游戏与游戏自动化不跨系统**。Arch 不装 Steam、不装 Waydroid、《明日方舟》和终末地都不在 Linux 跑;它们与 MAA/MAAend 全在 Windows。

| 需求 | 做法 |
| --- | --- |
| 从 Arch 侧查看/触发 Windows 自动化 | Windows 开 OpenSSH Server(`Add-WindowsCapability` + `sshd` 自启),只绑局域网/Tailscale;管理员公钥**必须放** `C:\ProgramData\ssh\administrators_authorized_keys`(放用户目录无效),`DefaultShell` 注册表可改 PowerShell;配合 SSH 端口转发最省事 |
| 存档/配置 | 留在 Windows;不通过 Linux 写 NTFS |
| 游戏库共享 | **不建议**把 Steam 库放 NTFS 给 Linux 用(Valve 社区 wiki 明标 NOT OFFICIAL / NOT RECOMMENDED:compatdata 软链、shadercache 常损坏);且这台机器不再需要 |
| 切换 | 引导菜单选 Windows;Linux 侧不自动挂载 Windows 分区 |

### 9.1 自动化工具的 Linux 支持边界(存档,不落地)

这一节只为将来反悔时留证据,默认不实施。

- **MAA**:maa-cli 有 AUR(`maa-cli` 0.7.7),配置在 `$XDG_CONFIG_HOME/maa`(`tasks/`、`profiles/`、`cli.toml`),命令 `maa fight|run|startup` 等,Linux 完整支持;GUI 的 release 有 `linux-x86_64.AppImage`,但**官方安装文档写"GUI 暂未支持 Linux"**,两份一手材料冲突,以文档为准(Wine 路径属非官方支持)。
- **MaaEnd**(`github.com/MaaEnd/MaaEnd`,2026-10-30 的 v2.36.0):PC 路径走 `Win32-Front` 控制器控 `UnityWndClass` 窗口,该实现非 Windows 为空,**终末地 PC 端只能在 Windows 原生跑**;Linux 那一套控制器(`Linux-Gamescope`/`Linux-ScreenCast`/`Linux-Wlroots`)是给"游戏本身跑在 Linux 上"的场景,不是"Windows 下跑 Wine"。
- **Waydroid**:Arch 侧 `waydroid` 在 extra,CachyOS 内核自带 C binder(比 Arch 官方内核的 Rust binder 更稳,后者 ≥6.18 有大事务 `ENOSPC` 导致 HAL 崩的已知 issue);翻译层走 `waydroid-extras install libndk|libhoudini`,但**方舟在 x86+翻译层下的可玩性官方从未承诺**。

## 10. 安全与凭证

- 仓库仍然不存凭据:token、SSH 私钥、API key 只在 U 盘(0600)与本机原生位置。
- live 环境里导出的 `ANTHROPIC_*`/代理变量放在 U 盘脚本里 `source`,不写进 shell 历史。
- 安装脚本对磁盘的破坏性动作必须显式传 `--wipe-nvme1n1 --confirm <一次性码>`;默认 dry-run 打印将要做的操作。`cachyos-installer` 自己的 `--dry-run` 是第一道闸,阶段脚本的确认令牌是第二道。
- 远程链路不变:SSH 只走 Tailscale,入口脚本白名单化。
- 这台机器没有启用 Secure Boot,不新增;若将来要开,先处理 BitLocker 与签名链。

## 11. 迁移清单

### 11.1 装前(Windows 侧,一次性)

- [ ] `manage-bde -status` 记录 BitLocker 状态,已启用则导出恢复密钥
- [ ] 关 Fast Startup;设 `RealTimeIsUniversal=1`(DWORD)
- [ ] 记下 Windows 启动项在固件里的顺序(重排后可恢复)
- [ ] 确认两块盘的型号/序列,防止把 `nvme0n1` 当目标盘

### 11.2 装中

按 §5.5 阶段推进;每阶段把「做了什么、断言结果」追加到 U 盘 `notes.md`(这就是新机的第一份任务记录)。

### 11.3 装后验收(全绿才算完成)

| # | 验收项 | 命令/观察点 |
| --- | --- | --- |
| 1 | 内核与驱动配对 | `uname -r`、`/proc/driver/nvidia/gpus/`;确认走的是 `nvidia-open`,没有回退到 i915 独占 |
| 1b | X11 会话不存在 | `ls /usr/share/xsessions` 为空是预期;排障只能在前向修,不能退 X11 |
| 2 | 三屏刷新率/缩放 | `kscreen-doctor -o`,内屏 240、带鱼屏 120 起步 |
| 3 | 休眠/挂起 | `systemctl suspend` 与唤醒;要休眠则 `systemctl hibernate` |
| 4 | 输入法 | 中文输入、Rime 候选 |
| 5 | 音频 | `wpctl status`,DAC 默认输出、UR22C 可用 |
| 6 | 网络 | Wi-Fi 7 与 2.5G 口各测一次 |
| 7 | Tailscale | `tailscale status` 能看到既有节点 |
| 8 | Orca | 启动、建 Run、`orca --version` |
| 9 | agent 三件套 | `claude -p`、`codex`、`dsh-tui` 各跑一次 |
| 10 | upctl | `upctl check` 无报错 |
| 11 | 快照回滚演练 | 打快照 → 改坏一个配置 → 从引导菜单回滚成功 |
| 12 | Windows 往返 | 切过去再切回来,时钟正确、启动顺序未乱 |
| 13 | 断电恢复 | 断电后重启,`nvme0n1` 分区表与 Windows 引导项仍在 |

### 11.4 不可逆项(用户已确认「全都删除」)

| 数据 | 后果 |
| --- | --- |
| `~/Repo` 全部 16 个仓库 | 仅已推送的远端可恢复;**`digital-media-course-labs`、`sports-world-campus-analysis`、`orca-ai-pool` 的未提交改动直接消失** |
| `~/.agents`(2.2G,含 skills/notes) | 规则与踩坑笔记清零,需重写 |
| `~/.config/orca`(1.2G,含 533MB 会话库) | 全部 Run/Task 历史不可恢复 |
| `~/Repo/video` 项目与素材、`3d` | 8.4M/22M,同盘删除 |
| Windows 侧数据 | 不动 |

## 12. 风险

| 风险 | 影响 | 缓解 | 验证点 |
| --- | --- | --- | --- |
| `cachyos-installer` 在本机硬件上失败 | 安装中断 | 先 `--dry-run` 过一遍配置;失败回退到 live 里 `pacman -S archinstall` + 官方 JSON 路径(ISO 里没有 archinstall,属可做但非官方) | 阶段 1 |
| `cowspace` 装不下 Claude Code(328MB > 256MiB) | live 里跑不起 agent | `cow_spacesize=2G`,或二进制放 U 盘直接执行 | 阶段 0 |
| live 无 Arch 官方支持声明 | 原生二进制可能缺库 | 预检里跑 `claude -p 'ok'`;失败改用 npm 包(Node 22+) | 阶段 0 |
| live 环境断网 | 安装停在半途 | 阶段脚本单机可跑;每阶段落盘 | 阶段 0 |
| NVIDIA + 多屏 DSC | 黑屏/降频 | 单输出递增带宽;保留 120Hz 回退 | 验收 1、2 |
| KWin 跨 GPU 合成性能未知 | 外屏掉帧 | 允许迁就接线(两根线都插 dGPU 或都插 iGPU) | 验收 2 |
| 快照≠备份 | 盘坏全丢 | 关键数据(照片、成片)放另一台机器或外部存储;本设计只保证系统可回滚 | — |
| AUR 包腐烂 | 更新失败 | 少用 AUR;腐烂的包转 pipx/uv | `upctl check` |
| 派生发行版维护风险 | 仓库或内核出问题 | 随时可退回 Arch 官方仓库 + `linux`;packages 清单保留 | 季度检查 |
| 安装器误判目标盘 | 可能碰 `nvme0n1`(Windows) | 阶段脚本按 `/sys/block/nvme1n1/serial` 锁定设备,不信 `/dev` 编号;§11.1 记序列号 | 阶段 1 |
| Waydroid 在当前内核 | CachyOS 内核是 C binder,比 Arch 官方内核的 Rust binder 更稳 | 不依赖 Waydroid(游戏已全在 Windows);真要试以 `waydroid-extras` 为准 | — |

## 13. 待确认(研究未落地项)

**已在本次核查中确认**(不再是待确认):

- CachyOS 有 CLI 无人值守入口(`cachyos-installer --config` + `headless_mode`);
- 内核与 nvidia 包名、版本钉定关系(§6.1);
- `setup-token` 一年期、必须过浏览器、`--bare` 不读它;`CLAUDE_CONFIG_DIR` 存在;
- `kscreen-doctor` 37 个子命令、Spectacle flag、`kdotool` 仅 AUR、`KWIN_DRM_DEVICES` 是唯一 GPU 选择入口;
- Arch 已无 X11 会话包、`nvidia` 系包已被移除并只留 open;
- 6.8.2 三缓冲可用 `KWIN_DRM_DISABLE_TRIPLE_BUFFERING` 关闭;KScreenLocker 不读 logind idle inhibitor。

**仍未确认**(装完必须实测,不能当结论用):

- **旧机 DSC 黑屏与双 240Hz 同链路**:KDE bugzilla、KWin 源码、NVIDIA 文档里都查不到对应记录。本机个例,新系统上是否复现未知。
- 带鱼屏实际挂在哪张卡(硬件事实,只能装完 `kscreen-doctor` 看)。
- 多显示器不同刷新率下的合成节拍(无一手文档)。
- `linux-cachyos` 与 Arch `nvidia-open` 的 ABI 搭配(官方无证据)——这也是坚持"不混用仓库"的实际理由。
- AT-SPI 在 Plasma 下默认是否开启(`orca computer` 的前提)。
- KWin 是否实现 `wlr_data_control`(只确认 `ext_data_control`);`kwriteconfig6` 的 flag 细节。
- Claude Code 原生二进制在 Arch 缺哪些库;`cow_spacesize` 实测需要多大。
- CachyOS 安装器"默认引导器"官方两处说法冲突(引导器页说 systemd-boot,快照页指向 Limine)。
- Waydroid/MAA/MaaEnd 的结论仅作存档;MAA GUI 的 Linux 支持在 release 与文档之间相互矛盾。

## 附录 A:工具链包名对照(2026-10-31 仓库数据)

> 完整逐条对照(196 行,含维护状态与来源 URL)在装机材料里,文档只留需要决策的部分。

官方仓库直装(节选):ripgrep/fd/bat/eza/zoxide/fzf/jq/go-yq/miller/htmlq/git-delta/difftastic/tokei/ast-grep/sd/btop/procs/dust/doggo/xh/just/moreutils/imagemagick/poppler/pandoc-cli/7zip/openssh/tailscale;gcc/clang/cmake/ninja/mold/ccache/bear/rustup/rust-analyzer/jdk21-openjdk/kotlin/gradle/python/uv/nodejs/pnpm/go;ghidra/rizin/radare2/gdb/gef/binwalk/squashfs-tools/mtd-utils/sleuthkit/foremost/android-tools/jadx/scrcpy/heimdall/libimobiledevice/mitmproxy/wireshark-cli/volatility3/flashrom/openocd/sigrok-cli/picocom/esptool/avrdude/stlink/dfu-util/i2c-tools/rtl-sdr/libnfc/usbutils/v4l-utils/qemu-full;ffmpeg/obs-studio/blender/godot/darktable/gphoto2/calibre/reaper/kdenlive/shotcut/ardour/musescore/fluidsynth/lilypond/krita/inkscape/gimp/libreoffice-fresh/qpdf/pdftk;ollama/waydroid/spectacle/ydotool/xdg-desktop-portal-kde/wireplumber/pipewire/networkmanager/sddm/firefox/chromium。

AUR 补充:dasel、sasquatch、ubi_reader、jefferson、unyaffs、android-apktool、aapt2(android-sdk-build-tools)、abootimg、payload-dumper-go、frida、python-oletools、readpe、can-utils、tio、kaitai-struct-compiler、mtkclient、kdotool、claude-code、comfyui、davinci-resolve(标 OutOfDate)、paru。

无包:unblob(pipx/源码)。

## 附录 B:与现有文档的差异(后续同步)

- [system-topology.md](system-topology.md):「本机运维任务」整节按 Arch 重写(NixOS 代际 → btrfs 快照;`configuration.nix` → `/etc` + 快照)。
- [local-toolchain.md](local-toolchain.md):游戏行改为「Windows 侧」;新增包管理策略与 AUR 策略。
- [home-automation-stack.md](home-automation-stack.md):HA 的 NixOS 部署形态改为容器 + compose 版本。
- [ds-bot-entry.md](ds-bot-entry.md):Hyprland 实测记录标注为历史;KDE 下需重测托盘与 Wayland。
- 全局 `~/.agents/notes/system.md` 与 `CLAUDE.md` 中的 NixOS/Hyprland 段落在装完后重写(以原生文件为准)。
