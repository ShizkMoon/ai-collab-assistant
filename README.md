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
- [墨水屏显示模块产品线](docs/eink-display-modules.md)：标签/桌面卡/看板/大标牌四梯队，全部国内现货+高性价比——拆机 ESL 价签(OEPL 开源固件) + LilyGo T5 + 微雪/佳显模组，模块作哑渲染终端，KPW5 逆向当选型范例
- [墨水屏模块体验设计](docs/eink-modules-ux.md)：环境智能体验原则(2秒可读/零打扰/永远在线/一屏一事/无输入)+ 点位地图 + 筛过的 OEPL 兼容型号采购清单 + ¥300-500 最小落地路径
- [Personal Agent 设计](docs/personal-agent.md)：入口/编排/执行/记录四层制度——能力登记表、任务生命周期(简报→派发→落定→记录→反哺)、记忆分层;参考 AIWORKSTATION 的 contracts/ADR/体验先行但不照搬其重型中心
- [宿舍全智能设计](docs/dorm-smart.md)：不动电路/全可拆走/¥1000 内的环境智能——BLE+Zigbee 传感器、HA 本地兜底+agent 增强、墨水屏作环境表面、六场景与分阶段实施清单
- [统一渲染管线规格](docs/render-pipeline.md)：数据→PNG+元数据→终端的服务端管线——版面系统/bpp 输出档/温度自适应与局部刷新策略/触发路由/最小环验收

### 技术参考档案

> 为选型决策提供底层依据的深度档案。事无巨细、表驱动——说明层文档引用其结论，不重复其细节。

- [OpenEPaperLink 内部机制](docs/oepl-internals.md)：AP 固件架构、802.15.4/BLE/sub-GHz 三条射频路、九类标签芯片族、推图/OTA 协议、功耗模型、刷机解锁与已知限制
- [epdiy 内部机制](docs/epdiy-internals.md)：波形系统（`.epw`/`wbf`/LUT/温度档）、16 灰渲染管线、ESP32-S3 LCD_CAM 并行驱动、支持面板对照、ESPHome/HA 集成现状
- [E-Ink 技术术语对照表](docs/eink-tech-glossary.md)：GDEY/GDEW/ED/OTP 命名、波形模式与 Regal、LUT/VCOM/FPL、协议与刷机缩写速查
- [智能家居落地技术档案](docs/home-automation-stack.md)：NixOS HA 部署形态对比、mosquitto/zigbee2mqtt/esphome 真实选项名与 systemd 细节、ZBDongle-E/P 与 LYWSD03MMC/LD2410 实操、自动化三层兜底、Zigbee 密钥与 Tailscale 安全面、断电断网恢复矩阵

## 工具层（可执行工具不属本仓库）

- **Shared RE Toolkit**：通用固件/设备/软件逆向 MCP 服务（15 工具）——已迁至
  `/data/Agent/nixpkgs-shizuku/pkgs/re-toolkit/` 作为标准 nix 包（`re-toolkit-mcp`，以原生文件为准）。
  注册在 `~/.config/devin/mcp_config.json` 与 `~/.mcporter/mcporter.json`；
  安装 `nix profile add path:/data/Agent/nixpkgs-shizuku#re-toolkit`。

## 维护约定

- 本仓库只放设计文档；**可执行工具归 `/data/Agent/nixpkgs-shizuku`**（标准 nix 包），
  agent 契约归 `~/.config/devin/skills/`，MCP 注册归 `~/.config/devin/mcp_config.json`。
- 文档用中文撰写；文件名、目录用稳定的英文 slug。
- 涉及本机实际配置时，以对应系统的原生文件为准，本仓库记录设计意图与决策，不复制运行中的配置。
