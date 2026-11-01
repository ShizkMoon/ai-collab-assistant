# 系统运维：能力演进、监控告警与备份恢复

> 状态：设计中 · 上位文档：[总体架构设计 §8](architecture-north-star.md#8-规则与能力的演进闭环)、[设计原则](principles.md)、[模型路由与本地推理](model-fleet.md)
>
> 本文定义规则与能力的迭代流程、系统监控指标、健康检查、自动恢复以及全量备份策略。

## 1. 规则与能力的演进流程

新能力或新规则从发现需求到正式启用分为六个阶段，每个阶段的产物均落盘为独立文件：

| 阶段 | 触发条件 | 阶段产物 | 存储位置 |
|---|---|---|---|
| 1. 观察采集 | 每晚 02:20 定时运行 | `observe/<date>.jsonl`：高频任务序列、返工聚类、未命中规则的记录 | `~/.local/state/aica/evo/` |
| 2. 生成提案 | 候选模式评分 `score ≥ 3.0` | `proposals/<date>.md` 与 `proposal.json` | `~/.local/state/aica/evo/` 或 `docs/proposals/` |
| 3. 编写草案 | 人工确认采纳或执行 `cap draft <id>` | `capabilities/<kind>.toml` + Provider 安装脚本 + 正反触发例句 | `/etc/aica/`（Git 分支） |
| 4. 影子测试 | 合入 `main` 分支但保持 `enabled = false` | `shadow/<date>/<uuid>.json` 旁路对比记录 | `~/.local/state/aica/shadow/` |
| 5. 正式上线 | 样本数 ≥ 20 且达标率 ≥ 0.6 | 修改 `enabled = true` 并提交 Git Commit | `/etc/aica/` |
| 6. 归档下线 | 连续 90 天零调用或连续 5 次执行失败 | 关闭配置并将旧 `kind` 映射到替代能力 | `/etc/aica/` |

```toml
# capabilities/work.video.make.toml（影子测试阶段）
kind = "work.video.make"
desc = "将原始素材剪辑为带字幕和配乐的成片"
examples = ["把今天录的剪成 3 分钟 vlog", "给这段录屏加字幕"]
not = ["播放这个视频", "下载这个视频"]
needs = ["workstation.gpu"]
provider = "video-remotion"
enabled = false
shadow_since = "2026-11-10"
```

新能力默认设置 `enabled = false`，在未启用前不会进入线上派发路由。

## 2. 频繁模式与规则挖掘

每晚从 `task export` 导出历史任务，按 `thread` 或自然日切分序列，使用 PrefixSpan 算法挖掘高频 `kind` 组合：

```python
ps = PrefixSpan(seqs); ps.minlen, ps.maxlen = 2, 5
for sup, pat in ps.frequent(4):                       # 支持度 support ≥ 4
    if covered_by_existing(pat): continue
    saved_min = sum(EST_MIN.get(k, 2) for k in pat) * sup
    score = math.log2(sup) * saved_min / 60
    if score >= 3.0: propose(pat, sup, score)
```

挖掘结果对应三类候选提案：

- **新场景提案**：连续出现的 `kind` 序列（`support ≥ 4`），生成 `scenes/*.toml` 草案（见 [自动化场景](ritual-scenes.md)）。
- **新能力提案**：同一 `kind` 下任务描述向量聚类 ≥ 8 条且均由人工（`me`）手动完成，生成 `capabilities/*.toml` 草案。
- **规则优化提案**：定时触发（`source=cron`）的任务超过 30% 被人工忽略（`dropped`），或待分类队列中同类描述反复出现，生成规则表修改补丁。

候选提案优先级评分公式：

```
score = log2(support) × (预估节省分钟数 / 60) × (1 − 与现有规则重叠度) × 可逆系数
```

其中可逆系数按操作风险赋值：只读操作为 `1.0`，写本地文件为 `0.8`，修改系统配置为 `0.5`，涉及付款、删除、对外发布的操作固定为 `0`（此类高风险操作不生成自动执行规则，仅在周报中统计手动执行次数）。

## 3. 提示词与 Skill 的迭代评估

提示词与 Skill 的调整以**实际返工率**作为核心评估指标。当同一 `thread` 下追加了修复子任务或原任务被调用 `ev reopen` 时，记为一次返工。

系统按 `(kind, prompt_version)` 记录返工次数、完成耗时与被忽略比例。测试新版本提示词 `v2` 时，保留旧版本 `v1`，按 `sha256(uuid)[:1] % 2` 进行确定性分流（确保同一任务重试时始终命中同一版本）。累计满 20 个样本后对比两组返工率的 Wilson 置信区间下界，仅当 `v2` 显著优于 `v1` 时才将默认版本切换为 `v2`。

当意图分类积累满 300 条已确认样本后，可在离线环境下使用 DSPy（`BootstrapFewShot`）优化分类提示词文本，将优化后的静态提示词提交至仓库，不在运行时引入 DSPy 依赖。

## 4. 影子测试与上线标准

在影子测试阶段，新 Provider 针对真实触发输入旁路运行一次，将结果写入 `~/.local/state/aica/shadow/`，不触发对外通知或实际状态变更：

```json
// shadow/2026-11-12/8f3a.json
{"uuid": "8f3a…", "kind": "work.video.make",
 "live":   {"provider": "video-remotion",    "exit": 0, "artifact": "/data/aica/out/a.mp4",    "secs": 412},
 "shadow": {"provider": "video-remotion-v2", "exit": 0, "artifact": "/data/aica/shadow/a.mp4", "secs": 388},
 "judge":  {"duration_pct": 99.2, "ssim": 0.94, "audio_ok": true}}
```

不同类型产物的自动化对比指标：

| 产物类型 | 对比指标 |
|---|---|
| 视频 / 音频 | 时长偏差 < 1% + 关键帧 SSIM / 音频响度合规检查 |
| 文本生成 | Embedding 余弦相似度 + 抽样 3 条人工审阅 |
| 结构化抽取 | JSON 字段级 Diff 对比 |
| 代码开发 | 测试套件通过率 + Diff 行数对比 |

累计满 20 个样本、达标率 ≥ 60% 且无异常退出时，执行 `cap promote` 将 `enabled` 设为 `true`。为节省算力与电费，夜间批处理（`lane = "batch"`）任务不开启双份旁路影子测试。

## 5. 监控与可观测性

系统监控直接复用成熟的开源组件：

| 监控层级 | 选用工具 | 部署位置 | 监控范围 |
|---|---|---|---|
| 服务探活 | **Uptime Kuma** | 工作站 | HTTP / TCP / Ping 连通性探测与状态页 |
| 主机与硬件指标 | **Prometheus + node_exporter + Grafana** | 工作站采集主机与云服务器指标 | CPU、内存、磁盘、systemd 单元状态、工作站 GPU |
| 任务队列概览 | **`ev status` + HA Dashboard** | 工作站终端 / ThinkSmart View | 待处理任务计数、当前通知模式、今日完成列表 |

```nix
# hosts/n100/observability.nix
services.uptime-kuma.enable = true;
services.prometheus = { enable = true; scrapeConfigs = [
  { job_name = "node"; static_configs = [ { targets = [ "localhost:9100" "workstation.ts.net:9100" ]; } ]; }
  { job_name = "gpu";  static_configs = [ { targets = [ "workstation.ts.net:9835" ]; } ]; } ]; };
services.prometheus.exporters.node = { enable = true;
  enabledCollectors = [ "systemd" "processes" "textfile" ];
  extraFlags = [ "--collector.textfile.directory=/var/lib/node-exporter/textfile" ]; };
services.grafana = { enable = true; settings.server.http_port = 3000; };
```

工作站 GPU 指标无需额外部署独立 Exporter，直接由定时脚本每 15 秒采集一次显存与功耗数据写入 `/var/lib/node-exporter/textfile/gpu.prom`，由 `node_exporter` 的 `textfile` 收集器一并上报。Grafana 直接导入 Node Exporter Full（Dashboard ID `1860`）模板。

## 6. 日志聚合与链路追踪

工作站的 `systemd-journald` 日志与 Orca / Worker 运行日志统一由 **Grafana Alloy** 采集并写入本地 Loki，保留周期设为 30 天，磁盘配额上限 20GB（上游 Promtail 已于 2025 年停止维护，统一使用 Alloy）：

```alloy
loki.source.journal "system" {
  path = "/var/log/journal"
  labels = { host = constants.hostname, job = "journal" }
  forward_to = [loki.write.n100.receiver]
}
loki.write "n100" { endpoint { url = "http://n100.ts.net:3100/loki/api/v1/push" } }
```

任务的业务完成状态以 Taskwarrior 任务库为准，Loki 日志仅用于排障诊断。

## 7. 定时健康检查（`hc`）

核心组件健康状态通过 `~/.config/aica/healthcheck.toml` 声明，由 `systemd.timer` 每 5 分钟巡检一次：

```toml
# ~/.config/aica/healthcheck.toml
[[check]]
name = "ev-taskstore"
cmd = ["sqlite3", "/home/shizuku/.local/state/aica/task/taskchampion.sqlite3", "PRAGMA quick_check;"]
expect_stdout = "ok"

[[check]]
name = "litellm"
cmd = ["curl", "-fsS", "http://127.0.0.1:4000/health/readiness"]
timeout = 5

[[check]]
name = "workstation-up"
cmd = ["tailscale", "status", "--json"]
assert = '.Peer[] | select(.HostName=="workstation") | .Online == true'

[[check]]
name = "orca-worker-heartbeat"
cmd = ["aica", "worker", "stale", "--max-age", "30m"]

[[check]]
name = "disk-root"
cmd = ["aica", "disk", "--min-free-gb", "20", "/"]
```

`hc check` 将每次检查结果写入 `~/.local/state/aica/hc.db`；为过滤偶发网络抖动，**同一检查项连续 2 次失败才通过 `ntfy` 发送告警通知**。

```nix
systemd.services.hc = { serviceConfig = { Type = "oneshot"; ExecStart = "${pkgs.aica}/bin/aica hc check"; }; };
systemd.timers.hc = { wantedBy = [ "timers.target" ]; timerConfig = { OnBootSec = "2min"; OnUnitInactiveSec = "5min"; }; };
```

## 8. 常见故障自动恢复

| 故障现象 | 自动恢复动作 | 失败兜底处理 |
|---|---|---|
| 常驻守护进程崩溃 | 配置 `Restart=on-failure`、`RestartSec=5s`、`StartLimitBurst=5` | 达到重启上限后触发 `OnFailure=` 告警通知，防止无限重启风暴 |
| 系统升级后冒烟检查失败 | 自动执行 `snapper rollback` 并重启 | 发送告警通知并保留构建错误日志 |
| 工作站意外关机 | 云服务器继续接收外部消息并写入等待队列 | 持续不可达超过 2 小时推送通知提醒人工开机 |
| 根分区可用空间低于阈值 | 自动执行 `nix-collect-garbage --delete-older-than 14d` 并轮转日志 | 清理后仍不足则推送告警 |
| 工作站断电后恢复供电 | BIOS 配置来电自启，开机后执行 `hc check` 汇总离线期间状态并触发 `ev sync` 补拉事件 | - |

```nix
systemd.services.orca.serviceConfig = { Restart = "on-failure"; RestartSec = "5s";
  StartLimitIntervalSec = 300; StartLimitBurst = 5; };
systemd.services.orca.unitConfig.OnFailure = "aica-notify@%n.service";
```

系统不自动执行 `git reset --hard`、不自动清理用户业务数据、也不自动覆盖线上失败的 Provider 包。

## 9. 备份与恢复演练

数据备份遵循 3-2-1 原则（工作站本地一份、云服务器副本一份、加密异地对象存储或外置硬盘一份）：

| 数据项 | 备份频率 | 备份工具 | 恢复验证周期 |
|---|---|---|---|
| `taskchampion.sqlite3`（任务库） | 每小时 | `sqlite3 .backup` + Litestream | 每月 1 日自动演练 |
| LiteLLM `spend.db`、`calibration.db` | 每日 | Restic | 每季度 |
| Home Assistant 配置与 Recorder | 每日 | HA 原生备份 + Restic | 每季度 |
| `~/knowledge/kb.sqlite`（知识库） | 每日 | Restic | 每月 |
| Calibre 书库、音乐库 | 每周 | Restic | 每季度 |
| `~/Repo`（含文档与 Provider 源码） | 每日 | Git + Restic | 每月 |
| 应用凭据 | 变更时触发 | 原生位置（KWallet）+ 加密归档 | 每季度 |

每日定时备份脚本（`~/.config/aica/backup.sh`）：

```bash
set -euo pipefail
ST=~/.local/state/aica
export RESTIC_REPOSITORY="rclone:n100:/backup/restic" RESTIC_PASSWORD_FILE="/run/secrets/restic"
sqlite3 "$ST/task/taskchampion.sqlite3" ".backup '/var/backups/ev-$(date +%F-%H).sqlite3'"
restic backup --tag daily /var/backups/ev-*.sqlite3 \
  "$ST/litellm" "$ST/calibration" ~/knowledge ~/Repo \
  --exclude-caches --exclude '/home/shizuku/Repo/video/*/render' \
  --exclude '/home/shizuku/Repo/video/*/node_modules'
restic forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune
```

**每月 1 日自动恢复演练脚本**（在临时目录还原最新备份并校验 SQLite 完整性，校验结果写入周报）：

```bash
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
restic restore latest --target "$T" --include /var/backups/ev-*.sqlite3
DB=$(ls "$T"/var/backups/ev-*.sqlite3 | tail -1)
test "$(sqlite3 "$DB" 'PRAGMA integrity_check;')" = "ok"
task rc.data.location="$(dirname "$DB")" rc.json.array=on export | jq length
```

## 10. 每日巡检汇总与夜间功耗管理

系统通过每日两次定时检查与一份周度清单完成运行巡检：

| 时间 | 动作 | 异常升级策略 |
|---|---|---|
| 每日 07:00 | 运行 `hc check`，汇总过去 24 小时失败项、备份状态、批处理队列积压数以及待分类任务数 | 若存在异常，写入当日早报首行 |
| 每日 07:30 | 复查 07:00 已报告但仍未恢复的故障项 | 通过 `ntfy` 发送高优先级推送并附带操作卡片 `[处理] [忽略] [今日静默]` |

**能耗与夜间批处理窗口**：工作站满载功耗约 260W（175W GPU + 55W CPU），空闲待机约 20W；夜间满载运行 6 小时约耗电 1.5kWh（按 0.6 元/kWh 计约 0.9 元）。重负载批处理（`lane = "batch"`）统一固定在 **01:00–07:00** 时间窗内运行，兼顾云端 API 夜间折扣与本地谷电时段，并避免白天与交互任务争抢 GPU 显存。
