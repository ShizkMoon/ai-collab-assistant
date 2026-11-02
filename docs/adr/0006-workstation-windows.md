# ADR 0006：工作站改为 Windows 11 原生，放弃 Linux 与 WSL

工作站操作系统从 NixOS 改为 **Windows 11 Pro 原生**，只保留单系统，不安装 WSL，不保留 Linux 分区。桌面环境使用 Windows 自带 shell，路径按 Windows 惯例分开放置。本决策取代 2026-10-31 的 Arch Linux 方案（该方案从未落地）。

**决策依据**：本机的主要用途是视频制作、游戏、设计工具链与 Windows 侧应用的日常使用，这些在 Windows 上是最少摩擦的形态。Linux 侧的收益集中在无头常驻与声明式配置，而 [ADR 0007](0007-deferred-resident-node.md) 已经把常驻节点推迟，剩下的 Linux 收益不足以抵消日常兼容性成本。Arch 方案解决的是「NixOS 兼容性差」，但没有回答「为什么不直接用 Windows」。

**选择纯原生而不是 Windows + WSL 的原因**：

1. **两套环境会重新制造这次的痛点。** WSL 里的路径、权限、网络与桌面自动化接口都和 Windows 侧不同，Agent 每次调工具都要判断「这个跑哪边」，正是迁移要消除的摩擦。
2. **需要 Linux 语义的地方很少且可以改写。** 现有脚本大部分是 Python 与 ffmpeg，Windows 原生可用；路径分隔符问题用 `pathlib` 统一处理即可。
3. **放弃的比想象中少。** 游戏、MAA、Office、Adobe 系、Blender 原生、微信 Windows 客户端本来就在 Windows 侧更完整。

**代价与前置条件**：

1. **回滚粒度变粗。** [ADR 0002](0002-three-confirmation-points.md) 的「默认放行，靠回滚兜底」在 Windows 上只能靠系统还原点、卷影副本与 `restic` 备份，无法做到整机原子回滚。因此 `upctl` 必须在每次安装或升级前建还原点，这不是可选项。
2. **声明式配置不再存在。** `%ProgramData%\aica\` 下的配置需要 `managed.list` 纳管并纳入 Git；已安装包清单由 `winget export` 周期导出。
3. **服务模型改变。** `systemd` 单元改为 Windows 服务（WinSW 或 `sc.exe`）与任务计划程序；所有定时任务以任务 XML 形式纳管。
4. **桌面自动化接口全部更换。** AT-SPI 换成 UI Automation，`ydotool` 换成 AutoHotkey v2 / `SendInput`，`kscreen-doctor` 换成 CCD API 脚本，`wpctl` 换成 `AudioDeviceCmdlets`，KRunner 换成 PowerToys Run。
5. **`upctl` 仍是唯一更新入口。** 系统层归 `winget`，其余组件经 `upctl` 统一，否则会重新散落成手动更新。

**架构影响**：[设计原则](../principles.md) 中「可回滚」一条改为以还原点与备份为基准；`meta.system.update` 的能力实现改为 `winget upgrade` + 还原点 + `restic`。Linux 专属工具如无 Windows 等价物，在 [本机工具链选型](../local-toolchain.md) 中明确标注「不采用」。
