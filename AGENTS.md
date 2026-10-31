# 仓库约定

- 本仓库为个人 AI 协作与助理系统的设计文档集，正文使用中文。
- 文档放在 `docs/`，文件名用英文 slug；新增主题同时更新 `README.md` 与 [总体架构设计 §11 文档地图](docs/architecture-north-star.md#11-文档地图)。
- **可执行工具不进本仓库**：通用工具打包为 Nix 包放入 `~/Repo/nixpkgs-shizuku`（如 `pkgs/re-toolkit/`），本仓只记录接口规范与集成方式（旧文档中的 `/data/Agent/nixpkgs-shizuku` 在本机不存在，`/data` 为空挂载点）。
- 引用本机实际文件时使用绝对路径并注明"以原生文件为准"；凭据、令牌与私人会话内容不写入仓库。
- **路径约定**：运行时状态放入 `~/.local/state/aica/`，数据资产放入 `~/.local/share/aica/`，大文件（成片、固件镜像、书库、备份暂存）放入 `/data/aica/`（需先建目录并 `chown`）。不使用 `/data/Agent/` 等旧路径。
- `ax6000-campus-records/` 是通过 `git subtree` 归档的设备实验记录，**不要直接在子树内修改**：修改设备记录应在源仓库 `~/Repo/ax6000-campus-records` 提交后执行 `git subtree pull`。设计结论写入 `docs/`，原始实验数据留在子树。其他设备仓库遵循同一模式，见 [开发与逆向工程 §2.4](docs/work-devsec.md)。
- 设计取向：功能优先、优先复用开源项目（新需求先在 `docs/open-source-reuse.md` 补充复用方案）；仅对付款、删除、对外发布三类操作设置确认点（[ADR 0002](docs/adr/0002-three-confirmation-points.md)），不额外叠加权限或校验层。
- 能力的增删改记录在 `docs/capabilities.md`（作为 `kind` 取值的唯一权威来源）；自动化场景记录在 `docs/ritual-scenes.md`。
- 跨文档统一使用 [术语表](GLOSSARY.md) 中定义的术语（如 `kind`、任务、任务库、派发器、场景、执行摘要）；引入新概念时先更新 `GLOSSARY.md`。
- 目录结构或约定变更时同步更新本文件。
