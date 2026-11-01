# 个人 AI 协作与助理系统

本仓库是一套**个人 AI 协作与助理系统**的设计文档集。语音、消息或外部事件进入系统后，入口解析意图并匹配对应能力，由派发器路由给合适的执行器完成处理，最后将一句话执行摘要写回任务库并按需通知。整体设计坚持**功能优先、开源复用、够用即止**。可执行代码与工具包不放在本仓库（见 [AGENTS.md](AGENTS.md)）。

## 从哪里开始

- [设计原则](docs/principles.md)：功能优先、开源复用、事件驱动、单一数据源、可回滚
- [**总体架构设计**](docs/architecture-north-star.md)：核心闭环（草稿 → 触发 → 任务 → 执行 → 完成 → 复盘 → 上线）、五类工作流、自治等级、故障域、定时节奏与实施阶段
- [术语表](GLOSSARY.md)：全仓统一术语定义
- [文档地图](docs/architecture-north-star.md#11-文档地图)：各篇文档的职责边界

## 核心机制

- [架构总览](docs/architecture.md)：五层架构与三类确认点（速览入口）
- [事件运行时与派发器](docs/event-runtime.md)：九态状态机、派发器守护进程（Hook 写 Spool 队列）、规则匹配与幂等控制 · 设计中
- [事件与任务规格](docs/event-spec.md)：字段定义、状态映射与 `ev` CLI · 设计中
- [多 Agent 运行时](docs/multi-agent-runtime.md)：归属树与依赖图、派发与结果信封、发散收敛、编排者的能力裁剪 · 设计中
- [知识库与记忆分层](docs/knowledge-memory.md)：多源索引、三路混合检索、记忆分层与偏好提炼 · 设计中
- [提案库](docs/proposals/README.md)：规则与能力的迭代流程

## 能力与选型

- [能力目录](docs/capabilities.md)：`kind` 全集的唯一权威来源
- [开源复用清单](docs/open-source-reuse.md)：各模块复用的开源项目与自建边界

## 执行域

- [系统拓扑](docs/system-topology.md)：常驻入口、Orca 本地编排、Worker 执行与 GUI 自动化
- [多 Agent 协作规范](docs/agent-collaboration.md)：规则共享、协作模式与流水线分工
- [内容创作流水线](docs/creative-studio.md)：视频、音乐、写作、电子书与播客的统一制作管线 · 设计中
- [开发与逆向工程](docs/work-devsec.md)：代码开发、固件与软件逆向、游戏构建与设计工具链 · 设计中
- [日常事务管理](docs/life-operations.md)：日程、健康、财务、物品、社交与课程学习 · 设计中
- [自动化场景](docs/ritual-scenes.md)：14 个跨设备场景、触发方式与部分完成处理 · 设计中

## 交互与平台

- [Personal Agent 设计](docs/personal-agent.md)：交互约定、通知模式与记忆分层
- [DS-Bot 入口](docs/ds-bot-entry.md)：常驻宿主、IM 接入与迁移方案
- [常驻服务分布](docs/assistant-system.md)：服务部署位置与凭据管理
- [Super-agent 参考架构](docs/super-agent-architecture.md)：DeepSeek Super-agent 架构摘要与本仓取舍
- [系统运维](docs/platform-ops.md)：规则挖掘、影子测试、监控告警与备份恢复 · 设计中
- [模型路由与本地推理](docs/model-fleet.md)：模型注册表、按类路由、降级缓存、16GB 显存分配与置信度校准 · 设计中
- [路线图（历史）](docs/roadmap.md)：早期 P0–P4 划分，已被总体架构设计 §13 取代

## 基础设施

- [输入端口与输出路由](docs/output-routing.md)：`sources` / `surfaces` 约定、效果分类、投递回执与去重 · 设计中
- [工作站：Arch + KDE Plasma](docs/workstation-arch.md)
- [本机工具链选型](docs/local-toolchain.md)
- [网络与设备组网](docs/network-fabric.md)：Tailscale 组网、出口感知与外设接入 · 设计中
- [AX6000 校园网路由](docs/ax6000-router.md)
- [智能家居技术栈](docs/home-automation-stack.md)、[宿舍智能家居方案](docs/dorm-smart.md)
- [ThinkSmart View 桌面主控台](docs/thinksmart-view-console.md)

## 显示与硬件终端

- [多端显示仲裁](docs/surface-arbiter.md)：多显示端的内容优先级与刷新预算分配 · 设计中
- [统一渲染管线](docs/render-pipeline.md)
- [墨水屏硬件选型](docs/eink-display-modules.md)、[墨水屏交互设计](docs/eink-modules-ux.md)、[墨水屏改造方案](docs/eink-devkit-plan.md)、[E-Ink 技术术语表](docs/eink-tech-glossary.md)
- [OpenEPaperLink 内部机制](docs/oepl-internals.md)、[epdiy 内部机制](docs/epdiy-internals.md)、[电子价签刷机与验收](docs/esl-tag-ops.md)

## 架构决策记录（ADR）

- [ADR 0001](docs/adr/0001-taskwarrior-as-event-store.md)：使用 Taskwarrior 作为任务库
- [ADR 0002](docs/adr/0002-three-confirmation-points.md)：仅对三类操作设置确认点
- [ADR 0003](docs/adr/0003-loop-local-entry-remote.md)：入口与编排循环分离
- [ADR 0004](docs/adr/0004-draft-layer-ttl.md)：草稿层设置 24 小时 TTL
- [ADR 0005](docs/adr/0005-proposal-shadow-promotion.md)：通过提案与影子测试上线新能力
- [ADR 0006](docs/adr/0006-workstation-arch.md)：工作站改用 Arch Linux，回滚保证从 generation 挪到 btrfs 快照
- [ADR 0007](docs/adr/0007-deferred-resident-node.md)：常驻入口延后，先单机加云端等待队列

## 能力专题

- [电子书精修流水线](docs/book-polish-pipeline.md)

## 归档子树

- `ax6000-campus-records/`：AX6000 路由器实验记录（`git subtree` 归档，不在本仓直接修改）
