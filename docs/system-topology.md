# 系统拓扑：常驻入口与本地编排

> 状态：部分已部署 · 角色：执行层中 `agent:orca` 这一路的实现（见 [架构总览 §5](architecture.md)）

整体分三段：**入口常驻在 N100，编排在工作站本地，执行下沉到 worker**。手机等任何设备都能发起和跟踪任务，而需要用到本机文件、GPU 或桌面的执行只发生在工作站上。

## 1. 角色

| 角色 | 组件 | 职责 |
|---|---|---|
| 入口（常驻） | DS-Bot（必要时加 AstrBot），跑在 N100 | 听懂你的话，从能力目录里选出 `kind`，入账，说人话回报，保存人格记忆 |
| 编排（本地） | Orca，跑在工作站 | worktree、终端、Run/Task/Dispatch、消息队列，是本机工作的事实源 |
| 执行（本地） | Devin / Codex / Claude Code worker，以及各能力的 provider | 只做派发下来的具体任务 |

参考 [Super-agent](super-agent-architecture.md) 里的 Router / Worker 两层结构，本仓的做法正好相反：**Loop 和账都在本机，入口宿主只做转发**。单用户没有多租户需求，而本机的文件、GPU 和凭据在执行时都离不开。

## 2. 什么交给入口，什么下发本机

判断标准只有一个：**是否要用到本机设备**（文件系统、GPU、桌面应用、音视频和外设）。

- **入口自己办**：调研、写短文、规划、翻译、日程、只读抓取。
- **下发本机**：视频、音乐、游戏开发、深度代码、本机运维，也就是所有要读本机文件、开本机窗口或改本机状态的任务。
- 工作站离线时，入口回复"已排队"，然后通过 Wake-on-LAN 唤醒工作站。

## 3. 通道

- **网络**：节点之间用 Tailscale 组网。已入网的有工作站（systemd 常驻）和 KPW5（userspace 模式，只能出站）；N100 待加入。AX6000 仍是唯一网关，负责校园网认证、多出口和代理；N100 断电只影响入口能不能连上。见 [AX6000](ax6000-router.md)。
- **命令面**：DS-Bot 通过 SSH 调用本机 `orca` CLI（当前 shim 为 `~/.config/orca/linux-orca-cli-shim/orca`，以原生安装为准）。不另造 RPC。
- **薄入口**：在 `~/.local/bin/` 放一个脚本，只提供四个动作：创建任务、查询状态、读取输出、发送跟进。

## 4. 下发与跟进

- DS-Bot 用 `orchestration run-create` 建 Run，用 `worker-start --spec` 派发 worker，再用 `check --wait` 收回 `worker_done` / `escalation` / `question`，翻译成人话发给你。你的回复通过 `orchestration reply` 交回 worker。
- 每个 Dispatch 都要跟到真正结束；超时只是检查点，不是结束。
- 产物（成片、构建、分支）留在本机，只回传摘要和路径；你明确要文件时才搬运。
- 做完之后调用 `ev done <id> "<一句话>"` 写回账。可复用的做法顺手更新到 skill 或 AGENTS.md。

## 5. 呈现

- **DS-Bot Web / Desktop**：任务卡片，带进度、跟进和挑选产物。
- **IM**：通过 `@xmanrui/dsh-im` 插件接入私聊；群聊用 DS-Bot Web 或 AstrBot。卡片和进度渲染成图片发出。
- 卡片读取的是 Orca 和 Taskwarrior 里的状态，不另存一份。

## 6. 连续性

- 执行状态只保存在 Orca。DS-Bot 只缓存 Run、Dispatch、worktree 的 ID 和最近一次摘要，断线后按 ID 恢复。
- 回到电脑前，同一批 worktree 和 Run 在 Orca UI 里都能看到，直接接着做。DS-Bot 相当于 Orca 的手机外壳。

## 7. GUI 自动化：结构化优先，像素循环用 Jev

1. **结构化**（默认）：浏览器走 `orca-cli` 的 DOM 控制，原生应用走 `orca computer` 的 AT-SPI 无障碍树。有现成 CLI 或 CLI-Anything harness 时优先用它们。
2. **像素循环**（结构化够不到的情况，如画布、游戏画面、自绘 UI）：每一步决策交给 Jev 类决策模型做类型化选择（点哪个、跳过、是否完成），截图和输入注入用 Spectacle / KWin DBus + ydotool（见 [工作站 §4.2](workstation-nixos.md)）。
3. **规划**：只在多次失败或任务需要重新拆分时，才调用大模型。

Jev 不进入调度链路，而是写进 worker 自己的 skill / 规则："走像素路径时默认通过 Jev 薄封装"。不要修改 Orca 捆绑的 skill，因为 `orca skills update` 会覆盖它们。

## 8. 本机运维

| 类型 | 做法 | 回退 |
|---|---|---|
| 诊断（查磁盘、看日志） | 问一句，入口或 worker 直接回答 | 不需要 |
| 变更（装包、改配置） | 改 flake → `nixos-rebuild switch` → 冒烟检查 | 回滚 NixOS generation |
| 系统更新 | `work.nixos.update`：先构建，再用 nvd 看差异、切换、检查，失败就自动回滚 | 同上 |

不把密码交给 agent。删除数据、对外发布属于确认点。

## 9. 当前状态

- 已就绪：Orca 1.4.237（NixOS 本机），`orca-cli` / `computer-use` / `orchestration` 三个 skill 已全局安装。
- 未就绪：DS-Bot 常驻部署和加入 Tailscale、薄入口脚本。
- 顺序：先在本机手动扮演入口，把建 Run → 派 worker → 收回结果 → 回报这条链路跑通，再部署 DS-Bot。
