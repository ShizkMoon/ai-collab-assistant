# 开发与逆向工程：代码流水线、逆向分析、游戏与设计工具链

> 状态：设计中 · 上位文档：[架构总览](architecture.md)、[能力目录](capabilities.md)、[本机工具链选型](local-toolchain.md)、[内容创作流水线](creative-studio.md)
>
> 本文细化 `work.*` 域下代码开发、固件与软件逆向、游戏构建及图形设计工具链的执行流程。文中所涉命令与软件状态均按 2026-11-01 本机实测结果核对。

## 0. 本机工具链实测基线

| 工具或资产 | 本机实测状态 |
|---|---|
| `orca` CLI | 可用；支持 `worktree create`、`agent launch`、`terminal wait`、`automations create`、`repo add`；已配置 `local`、`orca-pool`、`orca-pool-ts` 主机 |
| `gh` CLI | 已登录 `ShizkMoon`，具备 `repo`、`workflow`、`gist`、`read:org` 权限 |
| `claude` / `codex` / `gemini` / `dsh` | 均在 `PATH` 中，可用于跨厂商交叉审阅代码 |
| `git` + `just` + `%USERPROFILE%\agent-src\tools\` | 可用 |
| `blender` | 5.2.3 LTS，支持无头模式（`-b -P`）运行 |
| `photocraft-cli` | 0.16.0，已安装可用 |
| ComfyUI | Windows 服务 `comfyui`（WinSW）运行中，`127.0.0.1:8188` 响应正常 |
| `adb` | 可用 |
| `godot` / `butler` / `pre-commit` / `mergiraf` / `jj` / `git-absorb` | 当前未安装 |
| `%USERPROFILE%\.agents` | 包含 71 个 Skill 及 `vendor/` 子库，当前尚未初始化 Git 仓库 |

存储路径说明：工作站的 `D:` 数据卷（4TB NTFS）存放全部大体积文件，统一规划存放在 `D:\aica\`（首次使用前执行 `New-Item -ItemType Directory D:\aica`），目录建好前暂存至 `%LOCALAPPDATA%\aica\data\`。

## 1. 代码开发流水线

代码开发任务以 `kind = work.code.task` 作为父任务，其下拆分为明确的阶段子任务，每个阶段以确定性的命令退出码或评审文件作为交接条件：

| 阶段 | 阶段名 | 执行动作 | 标准命令 | 产出物 | 对应 `kind` |
|---|---|---|---|---|---|
| 1 | 需求定义 | 将需求整理为结构化规格说明（Spec） | `gh issue create --repo <owner>/<r> --title <t>` 或编写 `<repo>/docs/specs/<slug>.md` | Issue 或 Spec 文档 | `work.code.spec` |
| 2 | 仓库注册 | 已存在仓库直接注册；新项目创建私有仓 | `orca repo add --path D:\repo\<r> --json`；`gh repo create shizkmoon/<r> --private --source=. --push` | Orca Repo ID | `work.code.task` |
| 3 | 隔离分支 | 单任务单 Worktree，基于 `origin/main` 创建 | `orca worktree create --repo path:$PWD --name <slug> --base-branch origin/main --agent claude --model <id> --json` | 独立 Worktree 与分支 | `work.code.task` |
| 4 | 代码实现 | Worker 在独立 Worktree 内编码，不在主工作区直接切换分支 | `orca agent launch --worktree name:<slug> --agent codex --prompt "$(cat docs/specs/<slug>.md)"` | Git Commit | `work.code.task` |
| 5 | 构建与测试 | 在受控终端内运行测试并等待进程退出码 | `orca terminal create --worktree name:<slug> --command "just check && make build" --json` → `orca terminal wait --terminal <h> --for exit --timeout-ms 1800000 --json` | 终端日志 + 退出码 | `work.code.verify` |
| 6 | 交叉评审 | 切换不同厂商的模型只读审阅 `git diff` | 见 §1.1 / §1.2 | `review.md` 或 PR 评论 | `work.code.review` |
| 7 | 分支合并 | 创建 PR 并在 CI 通过后自动 Squash 合并 | `gh pr create --fill --base main` → `gh pr merge --squash --auto --delete-branch` | Merge Commit | `work.code.merge` |
| 8 | 版本发布 | 构建产物发布 GitHub Release，桌面工具同步接入 `upctl` | `just check` / `gh release create v<x>` / `upctl update <section>` | Release Tag 与构建产物 | `work.code.release` |
| 9 | 任务完成 | 将一句话执行摘要写回任务库 | `ev done <id> "完成 X 模块实现，just check 通过并已合并至 main"` | 任务库注解 | - |

### 1.1 多 Agent 协同开发模式

| 协作模式 | 实现方式 | 适用场景 |
|---|---|---|
| 并行子分支 | `orca worktree create --parent-worktree name:<hp> --name <slug>-<n>` | 同一特性的多个独立子模块并行开发，通过 `orca worktree ps` 查看全局状态 |
| 任务依赖图（DAG） | `orca orchestration run-create` → `task-create --deps '["<id>"]'` → `dispatch` | 存在 3 个以上先后依赖关系的复杂模块重构 |
| 异构模型评审 | 另起只读会话，指定不同厂商模型审阅 `git diff origin/main...HEAD` | 减少同源模型的盲区（如 Codex 编写代码，Claude 或 DeepSeek 审阅） |
| 合并冲突处理 | 先执行 `git fetch && git rebase origin/main`；若冲突文件 > 3 个则在独立 Worktree 中解析并输出补丁 | 可按需用 `mergiraf` 做语法感知合并 |
| 分支合并串行化 | 个人仓库通过 `gh pr merge --auto` 配合本地 `main` 分支锁串行合入 | 多 PR 并行时可先合入 `next` 集成分支，验证通过后再快进合并至 `main` |
| 架构方案决策点 | `orca orchestration gate-create --task <id> --question "..." --options '["A","B"]'` | 仅在涉及不可逆架构选型时挂起等待人工选择 |

### 1.2 代码评审输出规范

评审报告固定分为三类结论，结合 `code-review` Skill 的编码规范与 Spec 一致性双轴执行：

| 结论级别 | 含义 | 后续处理 |
|---|---|---|
| **必须修改（Blocker）** | 存在功能缺陷、安全隐患或违背 Spec 要求，阻断合并 | 修复后重新执行第 5 步构建与测试 |
| **建议优化（Nit / Suggestion）** | 代码风格或非关键改进项，不阻断当前 PR 合并 | 记录为后续优化项，不阻塞主流程 |
| **存疑待确认（Question）** | 需求边界不明确，需人工裁决 | 任务转入 `escalated`（`+me`）交由人工决定 |

### 1.3 工程规则（`AGENTS.md`）的沉淀流程

仓库规则从实际发生的返工记录中提炼：

1. 每次代码评审打回或人工手动返工时，在任务注解中标记返工类型：`rework:style`、`rework:missing-test`、`rework:wrong-layer`、`rework:destructive`。
2. 每周复盘任务（`meta.review.weekly`）统计各标签频次，同一类问题累计出现 **≥ 3 次**时生成规则提案。
3. 跨仓库通用规则写入 `%USERPROFILE%\.agents\rules\common\`，特定仓库约束写入对应仓库的 `AGENTS.md`。每条规则遵循 `writing-for-agents` 规范：明确写出触发条件与可判定的禁止项，并附带简短示例。
4. 新规则上线 30 天后复查同类返工是否下降；长期不触发的过时规则通过 `config-gc` 定期清理。

| 配置文件位置 | 承载内容 | 维护方式 |
|---|---|---|
| `%USERPROFILE%\.claude\CLAUDE.md` / `%APPDATA%\devin\AGENTS.md` | 全局核心约束与笔记索引指针 | 人工维护，保持精简 |
| `%USERPROFILE%\.agents\rules\common\` | 跨仓库复用的具体工程规则 | 由周报提案合入 |
| `<repo>/AGENTS.md` | 单个项目的目录结构、构建命令与测试方法 | 随项目代码提交维护 |
| `%USERPROFILE%\.agents\link-skills.ps1` | 将同一套规则与 Skill 符号链接至各家 Agent 配置目录 | 脚本同步 |
| `docs/adr/` | 关键架构决策记录 | 做出不可逆选型时编写 |

### 1.4 Skill 开发与维护生命周期

当前 `%USERPROFILE%\.agents\` 下共有 71 个自定义 Skill 与 `vendor/` 下的四个外部技能集（`gamedev`、`litrev`、`music`、`rex`）。需尽快执行 `git init %USERPROFILE%\.agents` 将其纳入版本控制。

| 阶段 | 执行规范 |
|---|---|
| 编写 | 遵循 `writing-for-agents` 规范，每个 Skill 独立目录（`SKILL.md` + `scripts/` + `references/`），`description` 字段写明触发场景与用户常见表述 |
| 验证 | 使用 `skills-stocktake` 审查描述清晰度；在真实任务中测试触发准确性，并在干净 Shell 中验证全部配套脚本 |
| 版本控制 | `%USERPROFILE%\.agents\skills\` 纳入 Git 管理，`vendor/` 下的第三方技能库作为只读上游（通过入口 Skill 路由，不直接修改上游文件） |
| 分享与发布 | 对外分享前剥离本机绝对路径与私有主机名，通过 `orca skills share` 或独立仓库 `%USERPROFILE%\agent-src\skills\` 发布 |
| 定期清理 | 连续 30 天未触发或与其它 Skill 功能重叠的条目，经 `config-gc` 盘点确认后归档至 `%USERPROFILE%\.agents\_gc_trash\` |

## 2. 安全与逆向分析

### 2.1 逆向工具链基线

| 工具层 | 本机配置状态 |
|---|---|
| `re-toolkit` MCP | 源码与安装脚本位于 `%USERPROFILE%\agent-src\tools\re-toolkit`（v0.3.0），已注册至 `%APPDATA%\devin\mcp_config.json` 与 `%USERPROFILE%\.claude.json`，共暴露 16 个工具函数（含 `apk_analyze`） |
| 底层分析工具 | Ghidra 12.1.4、`binwalk`、`unblob`、QEMU、`mitmproxy`、Frida、`rizin`、`jadx`、`apktool`、`payload-dumper-go`、Kaitai Struct、`tshark`、`flashrom`、`openocd`、`sigrok-cli`、`picocom`、`nmap` |
| 配套 Skill | `%USERPROFILE%\.agents\skills\reverse-engineering`（REX）及 `%USERPROFILE%\.agents\vendor\rex` |
| 历史分析仓库 | `D:\repo\kpw5-analysis`、`D:\repo\mu22mk2-analysis`、`D:\repo\chaoxing-app-analysis`、`D:\repo\d3v-analysis`、`D:\repo\sports-world-campus-analysis` |

### 2.2 六类逆向分析流水线

所有逆向任务共享标准阶段结构：**目标识别 → 样本获取 → 解包提取 → 静态分析 → 动态插桩 / 流量分析 → 仿真验证 → 报告归档**，按目标类型裁剪所需阶段：

| 目标类型 | 标准步骤与调用的 MCP / CLI 工具 | 阶段产物 |
|---|---|---|
| **路由器与 IoT 固件** | 获取固件镜像（官方包 / OTA / `flash_read` 提取）→ `firmware_scan` → `firmware_extract`（优先 `unblob`）→ `firmware_inventory` → `disasm` 扫描启动脚本 → `ghidra_analyze` 反编译关键服务 → `qemu_boot` 仿真 | 解包文件树、启动链路说明、二进制资产清单 |
| **Android APK / OTA** | 校验 `SHA256SUMS` → `apk_analyze` → `java_decompile`（`jadx`）→ Native 库交由 `ghidra_analyze` / `disasm` → 在 Waydroid（ARM64 + `libndk`）或真机上运行 `frida_trace` | 组件暴露面、通信协议与加密逻辑分析 |
| **Linux ELF / 驱动模块** | `toolkit_status` → `disasm` 提取符号与字符串 → `ghidra_analyze` 交叉引用追踪 → `frida_trace` 动态验证 | 核心函数调用图与单函数反编译伪代码 |
| **私有网络/串口协议** | `pcap_capture` 或 `mitm_capture` 抓包 → 编写 Kaitai Struct `.ksy` 格式定义 → `kaitai_compile` 生成解析器验证 | `.ksy` 协议规范、样本流量包与字段说明 |
| **硬件接口采集** | `serial_capture` 只读抓取 UART 日志 → `sigrok-cli` 采集逻辑电平 → `openocd` / `flash_read` 只读导出 Flash 镜像 | 引导日志、引脚时序图与原始 Flash 镜像 |
| **系统仿真** | `qemu_boot --machine <m> --kernel <img>` 捕获串口输出 | 内核引导日志与外设缺失阻断点定位 |

为防止反编译输出撑爆模型上下文，工具调用默认仅返回函数列表与交叉引用摘要，仅对明确点名的目标函数拉取伪 C 代码。大体积原始固件镜像存放在 `D:\aica\re/<case>/`（或 `%LOCALAPPDATA%\aica\data\re/<case>/`），不提交至 Git 仓库。

### 2.3 分析案例仓库目录结构

```
<case>-analysis/
  README.md            # 核心结论汇总表与分析范围声明
  manifest.json        # 样本名称、版本号、来源 URL、文件大小、SHA256 与采集时间
  SHA256SUMS
  target-bin/          # 原始固件或 APK 样本（写入 .gitignore）
  analysis/
    00-recon/          # 基础资产盘点：文件清单、导出符号、字符串与 URL 列表
    agents/<role>/     # 按角色分拆的专项分析记录（re-bughunt / re-native / re-protocol 等）
    coordinator/       # 任务说明与仿真环境配置
    final/
      findings.json    # 结构化发现清单（Schema v1.0）
      report.md        # 完整分析报告
      coverage.md      # 覆盖率矩阵（已分析模块与未覆盖模块）
      reproduction.md  # 验证与复现步骤
      adjudication.md  # 多 Agent 结论分歧裁定记录
```

证据质量要求（沿用 `reverse-engineering` Skill 规范）：

1. **完整证据链**：每条确认的缺陷必须具备完整的 `source → sink → guard → principal` 四要素；链条不完整的推断归入 `unresolved` 假设列表。
2. **明确状态分级**：结论状态严格区分 `confirmed`、`likely`、`unresolved`、`refuted`。
3. **如实声明分析手段**：在元数据中逐项布尔标记 `static_only`、`apk_executed`、`emulator_used`、`device_used`、`new_network_requests`。
4. **敏感信息脱敏**：样本中涉及的个人账号、令牌与私有密钥一律替换为 `[REDACTED]`。

### 2.4 设备实验记录仓库的 `git subtree` 归档规范

以 `ax6000-campus-records/` 为代表的长期硬件调试记录，遵循以下归档约定：

| 规范项 | 具体做法 |
|---|---|
| 独立源仓库维护 | 每台受管设备建立独立的实验记录仓库 `D:\repo\<device>-records`，原始调试 JSON 与恢复脚本在源仓库提交 |
| 设计结论提炼入 `docs/` | 跨设备复用的架构结论写入本仓 `docs/`，原始实验数据保留在子树内 |
| 单向 `git subtree` 同步 | 通过 `git subtree add --prefix <device>-records D:\repo\<device>-records main --squash` 引入；后续更新一律在源仓提交后执行 `git subtree pull`，不在本仓子树目录内直接修改 |
| 排除大文件与凭据 | 固件二进制、私钥、订阅链接与包含密码的备份包不入库，仅在 `manifest.json` 中记录 SHA256 校验值 |

### 2.5 逆向任务接入派发器

```toml
[[rule]]
match = { kind = "work.rev.firmware" }
to = "orca:run"
run = { workdir = 'D:\repo\<case>-analysis', agent = "claude", model = "deepseek-chat" }

[[rule]]
match = { kind = "work.rev.apk" }
to = "orca:run"

[[rule]]
match = { kind = "work.rev.report" }
to = "notify"          # 报告生成后推送给用户审阅，对外公开前需经人工确认
```

逆向操作与三类人工确认点的映射关系：

| 具体操作 | 确认点归类 | 执行策略 |
|---|---|---|
| 本地静态解包、反编译、QEMU 仿真、抓取本机测试流量 | 无需确认 | 默认直接执行 |
| 向实体设备主动发包、串口写入命令、打断 U-Boot 引导 | **视同对外发布** | 需人工确认（MCP 工具面不暴露自动串口写入） |
| 刷写 Flash、覆盖设备分区、执行固件升级 | **视同删除/覆盖** | 必须先完整备份原厂分区镜像，并经人工确认后执行 |
| 向外公开漏洞报告或分析文章 | **对外发布** | 人工确认后发布 |

## 3. 游戏构建与图形设计工具链

### 3.1 Godot 4 无头构建与测试

Godot 以 `winget` 或官方二进制安装，标准无头构建命令如下：

```powershell
# 首次构建前导入资产并生成 UID 缓存（CI 与无头导出必跑）
godot --headless --path . --import

# 按 export_presets.cfg 中的预设名导出各平台构建包
godot --headless --path . --export-release "Windows Desktop" build/win/<game>.exe

# 运行 GUT 单元测试套件
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://test -gexit
```

- **版本号管理**：以仓库根目录 `version.txt` 为唯一来源，导出脚本自动同步至 `project.godot` 的 `config/version`。
- **3D 资产导入**：Blender 无头脚本将 `art/source/*.blend` 导出为 `.glb` 至工程目录，再由 `godot --headless --import` 编译；源文件纳入 Git（大文件走 Git LFS），`build/` 构建产物不入库。
- **渠道发布**：itch.io 使用 `butler push build/win user/<game>:windows` 上传；Steam 使用 `steamcmd` 上传 Depot，商店页面配置与最终发布上线作为人工确认点处理。

### 3.2 Blender 无头资产管线

本机已安装 Blender 5.2.3 LTS（`%USERPROFILE%\.local\bin\blender.exe`），通过 Python 脚本无头导出资产：

```powershell
blender -b art/source/character.blend -P tools/export_gltf.py -- --out build/assets/character.glb
```

每次导出在执行摘要中记录模型的三角面数、贴图分辨率与输出文件 SHA256，用于核对导出结果。

### 3.3 图像处理与生成式设计

| 处理需求 | 调用入口 | 标准命令示例 |
|---|---|---|
| 格式转换与 PSD 图层处理 | `photocraft-cli convert` | `photocraft-cli convert in.psd out.png --quality 92`（保留 TIFF 图层加 `--tiff-layers`） |
| 批量预设动作（封面裁切、墨水屏抖动） | `photocraft-cli batch` | `photocraft-cli batch --actions D:\repo\design\actions\covers.json --in raw --out out --format png` |
| 脚本化图层编辑 | `photocraft-cli run` | `photocraft-cli run in.pcraft --cmd layer.new.layer --params '{...}' --out out.pcraft` |
| 生成式图像制作 | ComfyUI HTTP API（`127.0.0.1:8188`） | `curl -s -X POST 127.0.0.1:8188/prompt -H 'content-type: application/json' -d @wf-api.json`，轮询 `/history/<prompt_id>` 获取输出文件 |
| 矢量图形与 UI 设计 | VectorCraft / FigCraft CLI | 通过 `craft-apps` Skill 调用对应无头 CLI |

ComfyUI 工作流统一保存为 API 格式 JSON（存放于 `D:\repo\design\comfy\<用途>.json`），并在元数据中记录 `prompt_id`、工作流哈希与随机种子以保证可复现。调用 ComfyUI 出图前需先获取 `%LOCALAPPDATA%\aica\state\gpu-lease` 显存锁。

### 3.4 Windows 侧游戏日常托管（MAA）

游戏本体与 MAA 运行在双系统笔记本的 Windows 11 分区（或独立 Windows 环境），Linux 侧仅通过远程命令触发并回收执行摘要：

| 环节 | 交互方式 |
|---|---|
| 远程触发任务 | 通过 OpenSSH 调用 Windows 侧 `MAA.exe` CLI，或由 Windows 计划任务定时拉起 |
| 结果回传 | MAA 完成后通过 Webhook 推送至 `ntfy` 或触发 `ev done`，将一句话摘要写回任务库（`kind = work.game.maa`） |

### 3.5 参数化 CAD 与 3D 打印

- **参数化建模**：使用 FreeCAD Headless（`freecadcmd script.py`）或 `cadcraft-cli` 生成 STEP / STL 模型，并在执行摘要中输出模型包围盒尺寸与体积。
- **切片与打印**：通过 PrusaSlicer / OrcaSlicer CLI（`--export-gcode`）导出 G-code 与预计打印时长；实际发起 3D 打印机任务消耗耗材且不可逆，需经人工确认后启动。
