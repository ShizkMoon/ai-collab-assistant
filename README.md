# 个人 AI 协作与助理系统设计

个人 AI 协作方式与助理系统的持续设计笔记：如何组织多个 AI agent 的分工、规则、记忆与工具链，让它们在真实工作流中长期、稳定地协作。

## 目录

- [设计原则](docs/principles.md)：约束先行、单一来源、作用域分层、可回退
- [多 agent 协作](docs/agent-collaboration.md)：全局规则统一、入口与上下文的分层加载、任务边界
- [助理系统架构](docs/assistant-system.md)：常驻服务、入口包装、状态与凭证的归属、自动化边界
- [系统拓扑](docs/system-topology.md)：云端 Hermes 入口、本地 Orca 编排、worker 执行的分层与下发链路
- [本机工具链选型](docs/local-toolchain.md)：CLI/脚本优先的软件清单——游戏开发、视频摄影、游戏、音乐、美术
- [书籍精修流水线](docs/book-polish-pipeline.md)：云端/Calibre 双触发，清洗/重排/元数据/成品/推送全自动的设计
- [电子墨水改造两条路线](docs/eink-devkit-plan.md)：KPW5 拆件自研 vs 现成套件——先买套件保体验，屏改造当并行工程
- [墨水屏显示模块产品线](docs/eink-display-modules.md)：标签/桌面卡/看板/大标牌四梯队选型——OpenEPaperLink ESL + Inkplate + TRMNL，模块作哑渲染终端，KPW5 逆向当选型范例

## 能力件（随设计沉淀的可执行模块）

- [Shared RE Toolkit](re-toolkit/)：通用固件/设备/软件逆向 MCP 服务（15 工具）——
  注册在 `~/.config/devin/mcp_config.json` 与 `~/.mcporter/mcporter.json`；
  `.venv/` 不入库，重建 `python3 -m venv .venv && pip install 'mcp<2'`

## 维护约定

- 一件作品一个主目录；本仓库以设计文档为主，但**能力件代码也归属于此**
  （如 `re-toolkit/`——它是协作体系的能力沉淀，不是独立项目）。
- 文档用中文撰写；文件名、目录用稳定的英文 slug。
- 涉及本机实际配置时，以对应系统的原生文件为准，本仓库记录设计意图与决策，不复制运行中的配置。
