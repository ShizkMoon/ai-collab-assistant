# 系统拓扑：常驻入口与本地编排

> 状态：部分已部署 · 角色：执行层中 `agent:orca` 链路的部署拓扑（见 [架构总览 §5](architecture.md#5-执行器列表)）

系统整体按职责分为三层：**常驻入口部署在 N100，任务编排运行在工作站本地，具体执行下沉至各 Worker 与 Provider**。用户可通过手机或任意终端随时发起和跟进任务，而依赖本地文件、GPU 或桌面环境的任务均在工作站本地完成。

## 1. 三层职责划分

| 层级 | 核心组件 | 职责范围 |
|---|---|---|
| 常驻入口 | DS-Bot（按需配合 AstrBot），运行于 N100 | 解析自然语言输入，从能力目录中匹配 `kind` 并录入任务；向用户发送执行摘要与交互卡片；维护轻量交互设定 |
| 本地编排 | Orca，运行于工作站 | 管理 Git Worktree、终端会话、Run / Task / Dispatch 生命周期与消息队列，作为代码与多步任务执行的权威状态源 |
| 任务执行 | Devin / Codex / Claude Code Worker，以及各能力 Provider | 在隔离的 Worktree 或运行目录内完成具体派发的子任务 |

对比 [Super-agent 参考架构](super-agent-architecture.md) 的云端 Router / 端侧轻量守护进程模式，本系统采用了相反的部署方向（[ADR 0003](adr/0003-loop-local-entry-remote.md)）：**将任务库与编排核心留在工作站本地，远端入口仅负责意图解析与消息转发**，避免为访问本地文件、GPU 与原生凭据而引入复杂的跨机 RPC。

## 2. 入口直办与下发工作站的分界

任务在 N100 入口直接处理还是派发至工作站，取决于**是否依赖工作站本地资源**（本地文件系统、独立显卡、桌面 GUI 应用与外设）：

- **N100 入口直接处理**：信息检索、短文起草、日程管理、文本翻译、公开网页只读抓取。
- **派发至工作站执行**：视频渲染、音乐生成、游戏构建、代码仓库开发、逆向分析及本机系统维护。
- 当工作站处于休眠或关机状态时，N100 入口将任务加入等待队列并回复"已排队"，同时通过有线局域网发送 Wake-on-LAN（WoL）魔术包唤醒工作站。

## 3. 跨机通信通道

- **虚拟局域网**：各节点通过 Tailscale 互联。目前工作站（`systemd` 常驻服务）与 Kindle KPW5（Userspace 网络模式，仅支持出站连接）已接入；N100 接入后同时配置为 **Tailscale 子网路由（Subnet Router）与出口节点（Exit Node）**，通过 `tailscale0 → eth0` 的 SNAT 将局域网 `192.168.31.0/24` 暴露给 Tailnet。AX6000 仍作为局域网唯一默认网关，负责校园网多账号认证、分流与透明代理。详见 [网络与设备组网 §3](network-fabric.md#3-子网路由与-exit-node-选型) 与 [AX6000 校园网路由](ax6000-router.md)。
- **命令调用通道**：N100 上的 DS-Bot 通过 Tailscale SSH 调用工作站上的受限入口脚本，底层转发至本机 `orca` CLI（当前路径为 `~/.config/orca/linux-orca-cli-shim/orca`，以原生安装为准），不额外开发自定义 RPC 协议。
- **受限入口脚本**：在工作站 `~/.local/bin/` 下放置封装脚本，仅向远端暴露四项受控操作：创建任务、查询状态、读取输出、发送跟进回复。

## 4. 任务派发与闭环跟进

- DS-Bot 通过 `orca orchestration run-create` 创建 Run，调用 `worker-start --spec` 派发 Worker，并通过 `check --wait` 等待 `worker_done`、`escalation` 或 `question` 事件，将结果整理为简明通知发给用户；用户的确认或补充回复再经 `orca orchestration reply` 传回 Worker。
- 每次派发均持续跟踪至任务进入终态；单次轮询超时仅作为进度检查点，不将超时静默标记为完成。
- 渲染成片、构建包、代码分支等大体积产物保留在工作站本地，仅向入口回传执行摘要与本地文件路径；仅在用户明确索取文件时才跨机传输。
- 任务执行完毕后调用 `ev done <id> "<执行摘要>"` 写回任务库；执行过程中总结出的通用做法同步沉淀至对应 Skill 或 `AGENTS.md`。

## 5. 状态展示与交互界面

- **DS-Bot Web / Desktop**：展示任务进度卡片、中间输出与多候选比选结果。
- **即时通讯（IM）**：私聊通过 `@xmanrui/dsh-im` 插件接入；群聊或更多平台通过 AstrBot 接入，将交互卡片渲染为图片发送。
- 前端界面展示的任务状态直接读取自 Orca 与 Taskwarrior，不在前端维护独立的状态副本。

## 6. 会话连续性

- 任务的完整执行状态保存在工作站 Orca 中。DS-Bot 仅缓存 `Run`、`Dispatch`、`Worktree` 的 ID 与最新摘要，网络重连后按 ID 即可恢复跟踪。
- 用户回到工作站桌面后，可在 Orca GUI 中直接查看并接管同一批 Worktree 与 Run。

## 7. GUI 自动化分级策略

对于必须操作图形界面的软件，按以下优先级依次降级：

1. **结构化接口优先（默认）**：具备原生 CLI 或 `CLI-Anything` 封装的工具直接走命令行；浏览器网页通过 `orca-cli` 的 DOM 接口控制；原生桌面应用通过 `orca computer` 读取 AT-SPI 无障碍树进行操控。
2. **像素级视觉操作（兜底）**：面对自绘画布、游戏窗口或无障碍树缺失的界面，使用 KWin DBus / `spectacle` 截图并配合视觉决策模型（如本地 VL 模型或 Jev）输出坐标动作，通过 `ydotool` 注入键鼠事件（见 [工作站配置 §4.2](workstation-nixos.md#42-桌面自动化命令行接口)）。
3. **重规划升级**：仅在连续多次操作失败或任务需要重新拆解时，才升级调用大参数模型重新规划步骤。

视觉操作逻辑封装在 Worker 自身的 Skill 中，不直接修改 Orca 内置 Skill（避免被 `orca skills update` 覆盖）。

## 8. 本机系统维护规范

| 操作类别 | 执行方式 | 回滚手段 |
|---|---|---|
| 状态诊断（查磁盘、看日志） | 入口或 Worker 直接执行只读命令并返回结论 | 无需回滚 |
| 配置与软件包变更 | 修改 NixOS Flake → `nixos-rebuild switch` → 执行冒烟检查 | 回滚 NixOS generation |
| 系统例行升级 | `work.nixos.update`：先构建、用 `nvd` 对比包差异、切换配置并检查服务，失败自动回滚 | 回滚 NixOS generation |

系统不向 Agent 暴露 `sudo` 明文密码（本机 `wheel` 组已配置免密 `nixos-rebuild`）。涉及删除用户数据或对外发布的操作严格受确认点约束。

## 9. 部署进度

- **已就绪**：工作站已安装 Orca 1.4.237，全局已配置 `orca-cli`、`computer-use`、`orchestration` 三个 Skill。
- **待部署**：N100 上的 DS-Bot 容器化常驻部署、Tailscale 子网路由配置、工作站受限入口脚本。
- **推进顺序**：先在工作站本地跑通"创建 Run → 派发 Worker → 回收结果 → 写回任务库"的完整闭环，再将入口迁移至 N100 常驻。
