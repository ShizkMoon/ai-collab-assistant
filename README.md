# 个人运行制度：AI 协作、问题处理与日常生活的基础架构

本仓是一套**个人助理系统**的设计文档集。你说一句话，或者发生一件事，系统听懂之后找到对应能力，交给合适的执行者去做，做完用一句话告诉你，并记进账。取向是**功能优先、复用开源、够用就行**。可执行工具不放在本仓（见 [AGENTS.md](AGENTS.md)）。

## 总览
- [设计原则](docs/principles.md)：功能优先、复用优先、事件优先、记录先于记忆、单一来源、可回退
- [架构总览](docs/architecture.md)：四层（能力 / 流转 / 执行 / 设施）加三个确认点；两端用语义、中间用约定；账用 Taskwarrior + HA · 设计中
- [事件规格](docs/event-spec.md)：字段、状态、`ev` CLI、分派 hook · 设计中
- [能力目录](docs/capabilities.md)：能力与实现分开；约 40 个能力；场景；维护流程 · 设计中
- [开源复用地图](docs/open-source-reuse.md)：每类需求复用什么，以及必须自建的部分
- [路线图](docs/roadmap.md)：P0–P4

## 主体与入口
- [Personal Agent](docs/personal-agent.md)：体验约定、Bot 模式、记忆
- [系统拓扑](docs/system-topology.md)：DS-Bot / Orca / worker、通道、GUI 自动化
- [DS-Bot 入口](docs/ds-bot-entry.md)：入口宿主、IM 接入、迁移
- [助手系统运行面](docs/assistant-system.md)：常驻服务与凭据
- [多 agent 协作](docs/agent-collaboration.md)：规则入口、协作模式、写作工作室和视频工作室
- [Super-agent 参考架构](docs/super-agent-architecture.md)：DeepSeek 文章摘要与取舍

## 设施
- [工作站：NixOS + KDE Plasma](docs/workstation-nixos.md)
- [本机工具链](docs/local-toolchain.md)
- [AX6000 路由](docs/ax6000-router.md)
- [智能家居落地](docs/home-automation-stack.md)、[宿舍全智能](docs/dorm-smart.md)
- [ThinkSmart View 主控台](docs/thinksmart-view-console.md)

## 能力专题
- [书籍精修流水线](docs/book-polish-pipeline.md)

## 墨水屏与电子价签档案
- [渲染管线](docs/render-pipeline.md)、[显示模块](docs/eink-display-modules.md)、[模块交互](docs/eink-modules-ux.md)、[开发套件计划](docs/eink-devkit-plan.md)、[术语表](docs/eink-tech-glossary.md)
- [OpenEPaperLink 内部](docs/oepl-internals.md)、[epdiy 内部](docs/epdiy-internals.md)、[电子价签运维](docs/esl-tag-ops.md)

## 归档子树
- `ax6000-campus-records/`：AX6000 设备实验记录（git subtree，不在这里直接修改）
