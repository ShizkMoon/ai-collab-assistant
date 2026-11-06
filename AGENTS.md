# 仓库约定

- 本仓库为个人 AI 协作与助理系统的设计文档集，正文使用中文。
- 文档放在 `docs/`，文件名用英文 slug；新增主题同时更新 `README.md` 与 [总体架构设计 §11 文档地图](docs/architecture-north-star.md#11-文档地图)。
- **可执行工具不进本仓库**：通用工具源码与安装脚本放入 `%USERPROFILE%\agent-src\tools\`（如 `re-toolkit\`），本仓只记录接口规范与集成方式（旧文档中的 `/data/Agent/nixpkgs-shizuku` 在本机不存在；Nix 包方案随工作站改用 Windows 一并废止，见 [ADR 0006](docs/adr/0006-workstation-windows.md)）。
- 引用本机实际文件时使用绝对路径并注明"以原生文件为准"；凭据、令牌与私人会话内容不写入仓库。
- **路径约定**：运行时状态放入 `%LOCALAPPDATA%\aica\state\`，数据资产放入 `%LOCALAPPDATA%\aica\data\`，能力与端口配置放入 `%ProgramData%\aica\`，大文件（成片、固件镜像、书库、备份暂存）放入 `D:\aica\`，**项目仓放 `C:\Repos\`**（本机当前约定；旧文档 `D:\repo\` 路径以本机实际为准）。不使用 `/data/Agent/`、`~/.local/state` 等旧路径。
- `ax6000-campus-records/` 是通过 `git subtree` 归档的设备实验记录，**不要直接在子树内修改**：子树本体在仓内 `ax6000-campus-records/`；如需回到源仓，先在 `C:\Repos\` 下恢复检出（2026-11-06 实测 `D:\repo\ax6000-campus-records` 与 `C:\Repos\ax6000-campus-records` 均不存在），再执行 `git subtree pull`。设计结论写入 `docs/`，原始实验数据留在子树。其他设备仓库遵循同一模式，见 [开发与逆向工程 §2.4](docs/work-devsec.md)。
- 设计取向：功能优先、优先复用开源项目（新需求先在 `docs/open-source-reuse.md` 补充复用方案）；仅对付款、删除、对外发布三类操作设置确认点（[ADR 0002](docs/adr/0002-three-confirmation-points.md)），不额外叠加权限或校验层。
- 能力的增删改记录在 `docs/capabilities.md`（作为 `kind` 取值的唯一权威来源）；自动化场景记录在 `docs/ritual-scenes.md`。
- **决策记录（ADR）**：影响多文档或难回退的决策写入 `docs/adr/NNNN-<slug>.md`，编号递增；新 ADR 同时更新 `README.md` ADR 列表与 [文档地图](docs/architecture-north-star.md#11-文档地图)。被取代的旧 ADR 正文保留不改，由新 ADR 注明取代范围（如 [ADR 0008](docs/adr/0008-local-agent-runtime.md) 对 ADR 0001/0003 的限定）。
- **命名约定**：编排与交互由 DSH 承担（会话内领导模式，工作区级 SuperAgent），执行由 DSH subagent / teammate 完成；`ar` 是控制面 CLI（0.1.0，19 个动词，无 `list` / `watch`），不承担编排与执行，设计中的运行目录为 `%LOCALAPPDATA%\aica\state\runs\<root_id>\`（本机未部署）。新增执行器值、`source` 值或运行概念时先更新 `GLOSSARY.md` 与 `docs/event-spec.md`。
- **工具验证**：新工具在 `docs/local-toolchain.md` 先标「待验证」，跑通一次完整 CLI 自动化调用后转正，并在对应章节写明实测基线与日期。
- 跨文档统一使用 [术语表](GLOSSARY.md) 中定义的术语（如 `kind`、任务、任务库、控制面、场景、执行摘要）；引入新概念时先更新 `GLOSSARY.md`。
- 提交信息沿用历史风格：`<type>: <中文摘要>`（如 `docs:`），必要时附要点列表。
- 目录结构或约定变更时同步更新本文件。
