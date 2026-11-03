# ADR 0008：多 Agent 运行时改用自建 `agent:local`，交互层采用生成式 UI

执行层不再依赖 Orca。多步任务的编排（Run 生命周期、Worktree 隔离、Worker 派发与跟进）由自建的 `agent:local` 运行时承担；其命令行入口为 `ar`（agent runtime），子命令面对齐原 `orca` CLI 的常用面（`ar repo add`、`ar worktree create`、`ar agent launch`、`ar terminal create|wait`、`ar orchestration run-create|check|reply`），Worker 的 agent loop 基于 Pi / DSH 深度定制，编码类任务仍可调用 Devin / Codex / Claude Code 作为具体 Worker。

交互层同时调整：放弃「Orca GUI 接管 + 终端」的组合，改为自建 **生成式 UI 工作台**——任务进度、Run 树、产物预览、多候选比选与升级卡片由模型按需渲染组件（形态参考 T3Code 一类生成式界面），不作为单一固定前端；TUI 仅保留为调试与兜底入口。

**决策依据**：

- Orca 的 Run / Task / Dispatch 模型与本仓的节点信封模型（`runs/<root_id>/nodes/<path>/` + `spec.json` / `result.json`）本已平行存在，维护两套概念映射反而比按信封协议实现一层薄运行时更复杂。
- 编排状态的唯一权威位置是 `runs/` 运行目录与任务库，自建运行时后不再存在第三份需要同步的 Run 状态。
- Pi / DSH 提供可组装的 agent loop，Skill 加载、模型路由（`decide()` / LiteLLM）与信封字段可按需定制，不受第三方运行时升级节奏约束（历史上 `orca skills update` 覆盖内置 Skill 曾迫使 Worker 侧逻辑外置）。
- 需要的 GUI 能力（查看进度、回复升级、打开 Worktree）规模远小于通用 agent 控制面，自建生成式 UI 与 DS-Bot Web 复用同一渲染管线即可覆盖；第三方控制面（OpenHands Agent Canvas 等）均绑定各自 runtime，无法消费本仓信封协议。
- GUI 桌面自动化层同期定型：UIA 无障碍树操作选用 `agent-desktop`（headless 语义动作不抢占鼠标与焦点），替代原 `orca computer` 路径，见 [系统拓扑 §7](../system-topology.md#7-gui-自动化分级策略) 与 [本机工具链选型 §2.8](../local-toolchain.md#28-浏览器与网页自动化egolite)。

**代价与回退**：

- Worker 崩溃恢复、Worktree 并发冲突、租约续期、升级通道时序等编排边界问题转为自测自担；`evd` 租约与 `+stalled` 看门狗机制不变，兜底逻辑沿用。
- Orca 安装暂保留为影子期兜底：新 `kind` 先路由 `agent:local`，对照期按 [ADR 0005](0005-proposal-shadow-promotion.md) 影子测试评估后再扩大路由；回退路径为把规则表 `to` 改回 `agent:orca`（执行器适配层保留兼容期别名）。
- 云服务器主机名 `orca-pool` 与 rclone 远端名为既有部署标签，不随本决策更名。
- 本 ADR 不否定 [ADR 0003](0003-loop-local-entry-remote.md) 的「入口与编排循环分离」与 [ADR 0001](0001-taskwarrior-as-event-store.md) 的「任务库精简」结论，仅将「复杂任务中间过程由 Orca 管理」替换为「由 `agent:local` 运行目录管理」。
