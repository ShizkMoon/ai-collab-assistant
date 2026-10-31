# 个人运行制度：AI 协作、问题处理与日常生活的基础架构

本仓是一套**基于事件的个人运行制度**的设计文档集：定义事件从哪来、谁来判定、谁去处置、如何落定、怎样反哺规则。AI 协作、问题处理、日常生活不是三件事，而是同一套机制的三个面；机器、设备、入口、墨水屏都是它的实现。

先读 [架构总览](docs/architecture.md)——它给出五条不变量、事件信封、判定与处置契约、域的挂载规则。其余文档是它在各层的实例。核心文档在标题下标注状态（**已部署 / 设计中 / 未动工**），全部文档的当前状态见下方分层列表。

## 文档地图

| 层 | 回答的问题 | 文档 |
|---|---|---|
| **L0 制度** | 什么不许变 | [设计原则](docs/principles.md) · [多 agent 协作](docs/agent-collaboration.md) |
| **L1 架构** | 事件怎么流动 | [**架构总览**](docs/architecture.md) |
| **L2 主体与入口** | 谁下指令、谁处置 | [Personal Agent](docs/personal-agent.md) · [系统拓扑](docs/system-topology.md) · [助理系统架构](docs/assistant-system.md) · [DS-Bot 入口层](docs/ds-bot-entry.md) |
| **L3 执行基座** | 跑在哪、用什么跑 | [工作站：CachyOS + KDE](docs/workstation-rebuild-cachyos.md) · [本机工具链](docs/local-toolchain.md) · [AX6000 校园网路由](docs/ax6000-router.md) |
| **L4 生活域** | 一个域怎么落地 | [宿舍全智能](docs/dorm-smart.md) · [墨水屏模块产品线](docs/eink-display-modules.md) · [墨水屏体验设计](docs/eink-modules-ux.md) · [统一渲染管线](docs/render-pipeline.md) · [ThinkSmart View 主控台](docs/thinksmart-view-console.md) · [书籍精修流水线](docs/book-polish-pipeline.md) · [电子墨水改造路线](docs/eink-devkit-plan.md) |
| **档案** | 结论的上游证据 | 见下节 |

## L0 制度

- [设计原则](docs/principles.md)：约束先行、单一来源、作用域分层、可回退 —— 五条不变量的来源 · 已部署
- [多 agent 协作](docs/agent-collaboration.md)：规则入口统一、上下文的 always-on / 触发式 / 长期资料分层、任务边界 · 已部署

## L1 架构

- [架构总览：基于事件的个人运行制度](docs/architecture.md)：五条不变量、词汇表、事件信封、分类学；预过滤/入账/判定/直通/处置/落定/反哺的主干与所有者；投机与全双工；呈现面与渠道带宽；按需召回与进展检查；域挂载八项（含手机 agent、智能家居、不可信输入边界）、失败模式、分阶段实施 · 设计中（P0 未实现）
- [事件规格（实现契约）](docs/event-spec.md)：命名与域划分、信封校验、两档输入信任（一道闸门）、规则谓词白名单与冲突规则、处理器调用协议与退出码、执行记录（回执）、SQLite schema、CLI 清单、P0 验收与十项基座校验 · 设计中
- [路线图：P0 起步与判据](docs/roadmap.md)：把 P0 写成一周内可执行、可判定成败的实验——范围、每日三分钟、首批十个 kind、一周后看什么、放弃标准、P1–P4 进入条件 · 设计中

## L2 主体与入口

- [Personal Agent 设计](docs/personal-agent.md)：人的一侧——体验约定、能力登记、任务生命周期、记忆分层 · 设计中
- [系统拓扑](docs/system-topology.md)：处置环节的实现——DS-Bot 入口、本地 Orca 编排、worker 执行、下发即监督、GUI 自动化 · 部分已部署
- [助理系统架构](docs/assistant-system.md)：常驻服务、入口包装、凭证与状态归属、自动化边界 · 已部署（表述待按 CachyOS 更新）
- [DS-Bot 入口层选型](docs/ds-bot-entry.md)：为什么接替 Hermes、DSH 插件边界、Linux/Wayland、服务器规格、Docker/SSH 接入契约与迁移风险 · 设计中

## L3 执行基座

- [工作站重装：CachyOS + KDE](docs/workstation-rebuild-cachyos.md)：NixOS→CachyOS 的开发机定位、双系统分区与引导、U 盘 live + Claude Code 的分阶段安装链路、KDE 自动化命令面、NixOS 能力的 Arch 替代 · 未动工（含执行手册区）
- [本机工具链选型](docs/local-toolchain.md)：CLI/脚本优先的软件清单——游戏开发、视频摄影、游戏、音乐、美术 · 已部署（待按 Arch 包名重定）
- [AX6000 校园网路由](docs/ax6000-router.md)：路由不搬到 N100 的理由、目标拓扑、N100 只做入口宿主的规格与三条硬约束 · 已部署

## L4 生活域

- [宿舍全智能设计](docs/dorm-smart.md)：`home` 域——不动电路/全可拆走/¥1000 内的环境智能，BLE+Zigbee 传感器、HA 本地兜底、六场景与分阶段实施 · 设计中
- [墨水屏模块产品线](docs/eink-display-modules.md)：标签/桌面卡/看板/大标牌四梯队选型，模块作哑渲染终端 · 设计中
- [墨水屏模块体验设计](docs/eink-modules-ux.md)：环境智能体验原则 + 点位地图 + 采购清单 + ¥300-500 最小落地 · 未动工
- [统一渲染管线规格](docs/render-pipeline.md)：呈现面——数据→PNG+元数据→终端，版面/bpp 档/温度自适应与局部刷新/触发路由 · 设计中
- [ThinkSmart View 桌面主控台](docs/thinksmart-view-console.md)：唯一可交互呈现面（触控+语音）——CD-18781Y 改造与 LOS 15.1 选型、View Assist 入口 · 未动工
- [书籍精修流水线](docs/book-polish-pipeline.md)：一条完整流水线样例——DS-Bot/Calibre 双触发，清洗/重排/元数据/成品/推送全自动 · 设计中
- [电子墨水改造两条路线](docs/eink-devkit-plan.md)：KPW5 拆件自研 vs 现成套件——先买套件保体验，屏改造当并行工程 · 未动工

## 技术参考档案

> 为选型决策提供底层依据的深度档案。事无巨细、表驱动——说明层文档引用其结论，不重复其细节。

- [OpenEPaperLink 内部机制](docs/oepl-internals.md)：AP 固件架构、802.15.4/BLE/sub-GHz 三条射频路、九类标签芯片族、推图/OTA 协议、功耗模型、刷机解锁与已知限制
- [epdiy 内部机制](docs/epdiy-internals.md)：波形系统（`.epw`/`wbf`/LUT/温度档）、16 灰渲染管线、ESP32-S3 LCD_CAM 并行驱动、支持面板对照、ESPHome/HA 集成现状
- [E-Ink 技术术语对照表](docs/eink-tech-glossary.md)：GDEY/GDEW/ED/OTP 命名、波形模式与 Regal、LUT/VCOM/FPL、协议与刷机缩写速查
- [智能家居落地技术档案](docs/home-automation-stack.md)：HA 部署形态对比、mosquitto/zigbee2mqtt/esphome 真实选项名与 systemd 细节、ZBDongle-E/P 与 LYWSD03MMC/LD2410 实操、自动化三层兜底、Zigbee 密钥与 Tailscale 安全面、断电断网恢复矩阵
- [Super-agent 架构参考](docs/super-agent-architecture.md)：外部对照——DeepSeek 产品部的双层 Router/Worker、Trigger 两级过滤、Thread 订阅直通、Inline&Spill 与链式召回、投机执行、存算分离、Watchdog；含两套设计的逐条对照与本仓采纳/不采纳的理由
- [ESL 价签实操档案](docs/esl-tag-ops.md)：ZBS243/TLSR8359/MSP430 等芯片族刷机路径与救砖、OTA 真实边界、不开壳辨 SoC、电池与天线细节、闲鱼问卖家 5 问+收货 10 分钟检查、2021-2026 成交价锚点、坑实录

## 归档子树

> 从独立仓库并入的设备记录。用 `git subtree` 保留完整提交历史；设备细节与实验原始证据以子树内文档为准。

- [ax6000-campus-records/](ax6000-campus-records/README.md)：Redmi AX6000 校园网部署与性能记录——四路 ESurfing 自动认证、mwan3 分流、TTL64、OpenClash 回滚、WED/AQL/CAKE 实验批次与恢复验证。设计结论见 [AX6000 校园网路由](docs/ax6000-router.md)。

## 工具层（可执行工具不属本仓库）

- **Shared RE Toolkit**：通用固件/设备/软件逆向 MCP 服务（15 工具）——已迁至
  `/data/Agent/nixpkgs-shizuku/pkgs/re-toolkit/` 作为标准 nix 包（`re-toolkit-mcp`，以原生文件为准）。
  注册在 `~/.config/devin/mcp_config.json` 与 `~/.mcporter/mcporter.json`；
  安装 `nix profile add path:/data/Agent/nixpkgs-shizuku#re-toolkit`。

## 维护约定

- 本仓库只放设计文档；**可执行工具归 `/data/Agent/nixpkgs-shizuku`**（标准 nix 包），
  agent 契约归 `~/.config/devin/skills/`，MCP 注册归 `~/.config/devin/mcp_config.json`。
- 新增域文档必须满足 [架构总览 §12](docs/architecture.md) 的七项挂载规则（事件命名空间、源、规则包、处置器、呈现面、留痕、回退），否则先补规则再写文档。
- 新增文档同时更新本 README 对应层；标题下标注状态（已部署 / 设计中 / 未动工）与决策日期。
- 设备实验原始记录放在归档子树（`ax6000-campus-records/`），用 `git subtree` 同步，不在本仓库重复其内容。
- 文档用中文撰写；文件名、目录用稳定的英文 slug。
- 涉及本机实际配置时，以对应系统的原生文件为准，本仓库记录设计意图与决策，不复制运行中的配置。
