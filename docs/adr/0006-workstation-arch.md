# ADR 0006：工作站改用 Arch Linux，回滚保证从 generation 挪到 btrfs 快照

工作站操作系统从 NixOS 改为 **Arch Linux + KDE Plasma 6**。桌面环境、磁盘布局与 Windows 双系统边界不变。

**决策依据**：工作站上的痛点是兼容性而不是可维护性——NVIDIA 驱动与 Wayland 的组合、Electron 与 AppImage 类应用、Blender 与 Craft 全家桶、只在 AUR 有的冷门工具。这些恰好是 NixOS 投入最多、Arch 几乎零成本的部分。声明式与原子升级在无头常驻节点上是净收益，在每天装新软件的工作站上是持续摩擦。

**代价与前置条件**：

1. **回滚不再是一条命令。** [ADR 0002](0002-three-confirmation-points.md) 的「默认放行，靠回滚兜底」以随时能回到已知良好状态为前提。Arch 上必须由 `snapper` + `snap-pac` 在每次 pacman 事务前后自动建 btrfs 快照、把 `/etc` 纳入快照、软件降级用 `downgrade`。这套机制是迁移的前置条件，不是可选项。
2. **配置不再是单一事实源。** `/etc` 与已安装包列表成为实际状态，需要导出 `pkglist.txt` 并把受管配置纳管，否则重装后无法还原。
3. **打包形态改变。** Provider 工具从 Nix Derivation 改为 PKGBUILD；`nix flake check` 不能继续作为构建验收命令，替换为测试套件、`just check` 与 shellcheck。
4. **`upctl` 从便利工具变成唯一更新入口。** NixOS 时代 `nixos-rebuild` 覆盖了系统层；Arch 上系统层归 pacman，其余组件仍须经 `upctl` 统一，否则会重新散落成手动更新。

**架构影响**：[设计原则](../principles.md)中「可回滚」一条改为以快照为基准实现；`work.nixos.update` 能力随之更名为 `meta.system.update`。N100 若日后采购，仍可单独按无头节点选型，与本决策无关（见 [ADR 0007](0007-deferred-resident-node.md)）。
