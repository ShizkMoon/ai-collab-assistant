# 仓库约定

- 本仓库为个人 AI 协作与助理系统的设计文档集，正文使用中文。
- 文档放在 `docs/`，文件名用英文 slug；新增主题同时更新 `README.md` 目录。
- **可执行工具不进本仓库**；标准工具做 nix 包进 `/data/Agent/nixpkgs-shizuku`（如 `pkgs/re-toolkit/`），
  文档只记设计契约与集成方式。
- 引用本机实际文件时使用绝对路径并注明"以原生文件为准"；不把凭据、令牌、私人会话内容写入仓库。
- `ax6000-campus-records/` 是 `git subtree` 归档的设备实验记录，**不要直接在里面改**：
  改设备记录应在其源仓库 `~/Repo/ax6000-campus-records` 提交后 `git subtree pull`。
  设计结论写进 `docs/`，原始证据留在子树。
- 结构或约定变更时同步修改本文件。
