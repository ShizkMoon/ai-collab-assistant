# 系统拓扑:常驻入口与本地编排

整套系统分三层:**入口在常驻宿主,编排在本地,执行下沉到 worker**。目标是任何设备(尤其手机)都能发起和跟踪任务,而真正碰设备的执行只发生在本地工作站上。

入口层实现已从 Hermes 切到 [DS-Bot](ds-bot-entry.md)。DS-Bot 替换的是入口平台,不改变 Orca 的编排职责;它带来的插件兼容性只在 DSH 生态内成立。

## 角色分层

- **入口层(常驻)— DS-Bot**:基于 DeepSeek Harness 的 Bot 团队,以 Web/Desktop 形态常驻,是所有设备的统一入口。负责人格化交互、长期记忆、任务理解与路由;自身不执行设备相关任务。
- **编排层(本地)— Orca**:本机 agent 运行时兼编排器。worktree、终端、Run/Task/Dispatch、消息队列都由它持有,是本机工作的唯一事实源。
- **执行层(本地)— worker**:Devin / Codex / Claude 等 coding agent,以及 Hyperframe、MultiPlane、DAW、游戏引擎等本机生产力工具。

入口层的价值是"任何设备可及";编排层的价值是"状态可持久、可接管";执行层只做被派发的具体任务。

## 路由规则

判据只有一个:**任务是否依赖具体设备**(本机文件系统、GPU、桌面应用、音视频与外设)。

- **入口侧执行(DS-Bot 自办)**:搜索调研、写作、规划、翻译、日程、邮件/IM、只读平台抓取——产出是信息或通信结果,不需要摸本机设备;受控网页操作由独立浏览器进程(或可选 worker)执行,购买、发送、删除等写动作必须显式确认。
- **下发本机(经 Orca)**:视频制作(Hyperframe/MultiPlane)、音乐制作、游戏开发、深度代码、本机运维与系统维护——任何要读本机文件、开本机窗口或改动本机状态的任务。
- 下发前先在入口侧把任务拆成"任务简报"(目标、上下文、验收标准);下发的最小单元是简报,不是逐条指令。

## 通道

- **网络层**:Tailscale 组网;入口宿主到本机只暴露 SSH,ACL 收敛到 DS-Bot 主机。**已落地**:workstation(systemd 常驻)、KPW5(userspace 模式——只能出不能入,找它走 WiFi 侧 SSH);DS-Bot 常驻宿主(N100)待加入。节点地址以 `tailscale status` 为准。
- **宿主位置**:入口宿主是接在 AX6000 后面的 N100,不是云主机。AX6000 仍是唯一网关,负责校园网认证、多出口与代理;N100 断电只影响入口可达性,不影响任何设备联网。选型理由与硬约束见 [AX6000 校园网路由](ax6000-router.md)。
- **命令面**:DS-Bot 经 SSH 调用本机 `orca` CLI(解析规则见 orca-cli skill;当前 shim 为 `~/.config/orca/linux-orca-cli-shim/orca`,以原生安装为准)。不另造 RPC,Orca CLI 已覆盖 worktree、agent launch、orchestration、terminal 读写。
- **入口收敛**:SSH 侧放一个薄入口脚本(`~/.local/bin/`,与入口层约定一致),只暴露四类动作——创建任务、查询状态、读取输出、发送跟进;不给裸 shell 自由操作。

## 下发与监督链路

只有一条路:**下发即监督**。凡经 DS-Bot 派到本机的任务一律走编排层,不存在"扔下去不管"的移交。

- DS-Bot 做 coordinator:`orchestration run-create` 建 Run,`worker-start --spec` 派发 worker(如 Devin),`check --wait` 回收 `worker_done` / `escalation` / `question`,翻译后推给用户;用户回复经 `orchestration reply` 回注 worker。复杂任务在同一 Run 内派 DAG。
- 必须监控到每个 Dispatch 落定(worker_done 或证实的退出),且每次派发都必须有结果回答给用户——超时与失联是检查点而非终态,没有正面证据不得报"完成"或"失败"。
- 完成回流:worker 的 `worker_done` 摘要 → DS-Bot → 用户。工件(成片、构建产物、分支)留在本机 worktree/artifact,DS-Bot 只回传摘要与指针;用户明确要求才搬运文件。

### 任务总结与反哺

每次派发落定后必须产出一份**任务记录**,这是链路的一部分而非可选报告:

- 内容:任务简报、实际执行路径(用了什么命令/工具、走了几次重试)、`worker_done` 摘要、卡点与根因、可复用的做法。
- 归档:任务记录归记录层(见助理系统架构),与运行状态分离,完成后归档。
- 反哺:记录中"可复用做法"与"卡点"定期回流到两处——派发侧的提示模板(让下次简报写得更准)和执行侧的 `AGENTS.md` / skill(把踩过的坑写成规则)。修改规则文件仍需显式确认,记录本身只提供候选,不自动改写。

手机端不问 Orca 直连:用户经 DS-Bot 间接做 `worker-list` / `check` / `terminal read`,也能经 DS-Bot 给运行中的 worker 发跟进(`terminal send` / `reply`)。

## 呈现层:渠道自适应输出

同一份状态,按渠道给不同形态:

- **DS-Bot Web / Desktop**:生成式交互 UI——任务卡片带实时进度,可对内操作(发跟进、放行/拒绝、挑工件),用户操作回写为对 worker 的 `reply` / `terminal send`。
- **IM 渠道**:不是 DS-Bot 自带能力。需要另装 DSH IM 插件;`@xmanrui/dsh-im` 已能把私聊绑定到 DS-Bot Bot,但只支持私聊,群聊仍走 DS-Bot Web/Desktop。IM 消息按纯文本 + 图片处理,任务卡片和进度渲染成图发送,不假设富交互能力。

两条约束:

- **表达即操作,但按需生成**:由 DS-Bot 按任务裁量——状态跟踪、工件预览、多方案对比给卡片;一问一答给纯文本。生成式 UI 是会话内一次性构件,不是常驻前端工程。
- **前端不产生第二事实源**:卡片读的是 Orca 持有的同一份状态,DS-Bot 只做视图缓存;操作经编排链路回写,不旁路。

## 连续性与事实源

- 执行状态只存于本机 Orca runtime;DS-Bot 只缓存 Run ID、Dispatch ID、worktree id 和最近摘要,不复制状态(单一来源)。断线重连按 ID 恢复,消息队列可重放。
- 用户回到 Linux 机器:同一批 worktree、chat、Run 在 Orca UI 原样可见,可直接键入接管——入口会话与本地桌面是同一份状态的两种视图,不存在"同步"动作。
- 这正好补 Orca 的短板:它偏终端/桌面,不便手机操作;DS-Bot 是它的移动外壳。

## GUI 自动化:结构化优先,像素循环内建 Jev

本机的 ComputerUse / BrowserUse 默认走"截图 → 大模型推理 → 操作 → 再截图"的循环,慢且在 Linux 上易受 X11/Wayland 差异影响。整体仍按三层组织,但 Jev 不是外挂兜底——**它沉淀在像素循环内部,是这两套能力每步决策的引擎**:

1. **结构化层(默认,最快最稳)**:Orca 内置浏览器走 `orca-cli` 的 DOM 级控制;本机原生应用走 `orca computer` 的 AT-SPI 无障碍树。无像素、无视觉模型,操作近乎即时,且在 X11/Wayland 下行为一致。能走这一层就不走下面两层。
2. **像素循环(结构够不到时)**:画布、自绘 UI、webview 内部、游戏画面等目标需要截图操作。循环内部的每步决策固定走 Jev 类决策模型(Jev-Vision,开源 8B,一次前向约 160ms)的类型化问答:下一步点哪个候选元素(ground)、该元素是否已达成所需状态(skip)、上一步操作是否生效(effect)、目标是否完成(done)。候选元素用 Set-of-Mark 式标注给出,Jev 只返回概率;置信度与间隔门不达阈值宁可拒绝也不误点。**被替换的是"通用 VLM 逐步看图"这一环,不是 Orca 的驱动**——执行仍由 `orca computer` / DOM 完成。
3. **规划层(只在异常时调用)**:决策门连续拒绝、任务需要重新分解时,才上调大模型。日常步进不经过它。

### 沉淀方式(结合点)

Jev 不进调度链路(DS-Bot/Orca 不管像素),而是沉淀进 **worker 的执行环境**——Devin 被派发后自己调它:

- **决策即服务(云端)**:调用云端 Jev(`/v1/systemone` 兼容端点),本机不部署推理、不依赖 GPU。决策调用本身是毫秒级,延迟主要来自网络往返,仍远小于通用 VLM 逐步推理。
- **调用面是薄封装**:给 agent 的入口是 `~/.local/bin` CLI 或本地 MCP server,只暴露 ground / skip / effect / done 四个类型化动作——browser-use 与 computer-use 的像素循环内部默认走它,对使用者透明。薄封装负责截图压缩/裁剪,控制每次上行的像素量;云端端点与 key 由封装持有,worker 只见命令面不见凭证。
- **结合靠 worker 的规则层**:`worker-start` / `agent launch` 不需要为 Jev 传任何参数——Devin 的 skill/全局规则里写明"像素路径默认经 Jev 决策",它读到规则自然调用薄封装。这是唯一的注入点,也是为什么它必须放在 always-on 或触发式规则里而不是任务简报里。
- **浏览器路径可以再省一步**:候选元素直接从 DOM/AT-SPI 快照取(近乎免费),Set-of-Mark 标注到截图后 Jev 只做"选哪个"——一步一次调用,连 tile 描述都不需要额外的视觉模型。
- **不改 Orca 捆绑 skill**:computer-use / orca-cli 是版本化 stub,`orca skills update` 会覆盖本地改动。Jev 循环的教法放在我们自己维护的 skill/规则里(全局 `~/.agents/skills/` 或 AGENTS.md 层),与捆绑 skill 并存,升级互不干扰。
- **边界要诚实**:Jev 是决策模型不是规划器,只回答类型化问题;任务分解、报错解读仍归规划层。它换掉的是每步的感知-决策延迟,不是 agent 本身。

Linux 兼容与速度约定:

- 截图:Wayland 走 PipeWire/XDG 门户,X11 走 XShm;输入注入走 uinput/ydotool(双栈通用),不依赖 xdotool(仅 X11)。
- 单步总开销目标 <1s(决策调用 + 网络往返);规划层调用只发生在异常路径。
- 像素路径的截图会出本机到云端决策端点,含敏感内容的画面要走门控或直接退避——这条写进调用面薄封装,不靠口头约定。
- 每步的类型化问答天然是审计日志,直接并入任务记录反哺链路。

## 本机运维任务(方向待定)

手机上发"帮我装个软件/配下环境/整理目录/维护系统",可行性骨架如下,实现细节未验证:

- **诊断类(只读)**:磁盘占用、服务状态、NixOS 代际列表这类查询,走薄入口的只读白名单,由 DS-Bot 直接回答,不为查个状态就派一个 worker。
- **变更类**:装软件、改配置、整理目录,一律走"下发即监督"——worker 在 folder context(编排不强制 Git)或维护用工作区里执行,过程经 ask/reply 与用户在手机上往返,落定后照常产出任务记录。
- **系统级(最高风险)**:改 `configuration.nix`/flake、`nixos-rebuild`、引导项、用户/权限变更。在普通显式确认之上再加预授权清单:只有清单内的命令允许免密执行(polkit/sudoers 按命令粒度配),清单外一律升级给用户;不把密码交给任何 agent。
- **回退天然存在**:NixOS 代际即回滚路径,每次系统级变更必须在任务记录里写明回退到哪个代际。

开放问题:DS-Bot 直碰 shell 的边界划在哪(目前是"只读白名单",要不要放宽待定);授权模型的具体落地;worker 跑在 folder context 还是专门的维护 worktree;长时间运维任务在手机上怎么推送节点进展。

## 边界与安全

- SSH 只走 Tailscale,本机不对公网暴露;薄入口白名单化。
- worker 消耗本机已登录的订阅与凭证;DS-Bot 不持有本机 agent 的 API key,凭证仍留本机原生位置。
- 破坏性操作(worktree rm、push、发布)沿用自动化边界:必须显式指令,不因链路变长而放宽。
- 本机 Orca 需常驻运行,入口宿主依赖 `orca` CLI 可达;若未来要真正的无头远端,再评估 Orca 的配对/远程 server 模式(`--environment` / `orca serve`),不提前引入。

## 当前状态与阶段

- 已就绪:Orca 1.4.237(NixOS 本机),`orca-cli` / `computer-use` / `orchestration` 三个 skill 已全局安装,worker 侧可被驱动。
- 未就绪:DS-Bot 常驻部署及其加入 Tailscale(workstation、KPW5 已入网)、薄入口脚本。
- 顺序:先在本机手动扮演入口层角色把编排链路跑通(建 Run → 派 worker → check 回收 → 回报),链路验证稳定后再部署 DS-Bot;通道和入口收敛最后做,且每一步留可回退路径。
