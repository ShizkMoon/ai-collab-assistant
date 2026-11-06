# ADR 0010：撤回 ADR 0009，交互层回到 DSH 原生会话

> 状态：已决策（2026-11-06）· 取代 [ADR 0009](0009-dsbot-as-control-interface.md) 全篇（交互层）· 保留 [ADR 0008](0008-local-agent-runtime.md) 的执行层结论
>
> 触发因素：回复中出现 `dsh-ui` 围栏（GenUI 卡片）时，DS-Bot 界面整体失去响应。根因未定位，因此本文不把它写成已证实的缺陷，只记现象与现场。

## 1. 背景

2026-11-04 的 [ADR 0009](0009-dsbot-as-control-interface.md) 把主控制界面交给 DS-Bot（DSH 多角色插件），`ar` 收敛为控制面契约。落地后有两件事同时成立：

- **界面卡死**：DS-Bot 0.2.7 + DSH 0.2.1-rc.5 + `@changfenhuang/dsh-genui` 0.15.0，回复里出现含两张表格与 `steps` 的 `dsh-ui` 围栏后，整个界面无响应。解析层已排除（同一份围栏过校验工具正常），未取得实测证据，不做根因结论。
- **耦合代价兑现**：[DS-Bot 入口 §2](../ds-bot-entry.md#2-功能缺口与配套补充方案) 早就写过「与 DSH 版本强耦合」。而它带来的增量只有界面，不是能力——Run 状态、任务库、事件流本来就不在它手里。

判断：为一个只提供界面、却会和 DSH 版本一起坏掉的插件，维持一套双份记忆与状态目录，不划算。

## 2. 决策

1. **移除 `ds-bot` 插件**：profile `package.json` 的 bundles 与 dependencies 一并摘除，`cordis.patch.yml` 的 `bot` 条目删除，`~/.dsh/bot` 与 `D:\aica\dsbot-workspace` 删除。
2. **交互层回到 DSH 原生会话**（Web / Desktop 自带界面），不自建前端，也不恢复工作台为主界面。
3. **控制面契约继续有效**：[control-plane-api.md](../control-plane-api.md) 的动词表、事件面、卡片语义、状态权威逐条不变，只把「客户端」由 DS-Bot 泛化为任意前端。
4. **ws 检索改为 profile 级 MCP**：`ws_*` 由 `@deepseek-ai/dsh-mcp-client` 在 `cordis.patch.yml` 注册，密钥写在该条目 `config.env` 内；`web_search` / `web_fetch` 的 ws provider 同样自带 env，不再读任何 Bot 状态目录。
5. **`ar` 的 `list` / `watch` 仍在待实现清单**（[系统拓扑 §9](../system-topology.md#9-部署进度)）。它们与前端无关，是控制面自身的最低门槛。

## 3. 后果

- **丢掉**：多角色 Bot、Bot / 群 / 团队三级 Markdown 记忆、交互卡片、定时任务、GitHub Connector（`mcp__github__*` 由 DS Bot 的 connector 提供）。恢复卡片与 IM 需要另装 `@xmanrui/dsh-im`（绑定普通 Session）或部署 AstrBot。
- **保留**：`runs/` 权威、`events.jsonl` 数据面、`ar` 命令面、ws 检索（profile 级，任何会话可用）。
- **风险**：移动端触达归零。DSH Web 只绑 `127.0.0.1`，未配 `tailscale serve`；这条记为待办，不是已完成。

## 4. 未解决

- `dsh-ui` 围栏导致的界面卡死没有根因。复现条件未收敛，记录为已观察现象。若后续重新引入任何做卡片渲染的前端，先按这份现场复测。
- 被删除的 `~/.dsh/bot` 含 Bot 记忆与对话摘要，未做备份。这次是明确选择不备份：内容是一次性的会话摘要，重建成本低于维护成本。

## 5. 落地记录（2026-11-06）

- 删除 `~/.dsh/bot`（含 `state.json`、`secrets.json`、`usage.sqlite`、`memory/`、`mobile/`、`learning/`、`workspace/` 下 5 个临时脚本）与 `D:\aica\dsbot-workspace`。`secrets.json` 内的 GitHub PAT 随目录一并消失，未抄录、无备份；再要 GitHub connector 需重新申领。
- 摘掉唯一一处隐式依赖：`ws-web.mjs` 原先从 `~/.dsh/bot/state.json` 播种 `EXA_API_KEY` / `TAVILY_API_KEY` / `SEARXNG_URL` / `BRAVE_API_KEY`，现改为只读 `cordis.patch.yml` 中本条目 `config.env`。删除 `~/.dsh/bot` 后调用 `ws/lib.mjs` 的 `search` 实测返回 3 条结果、`exa:ok` + `searxng:ok`，检索不受影响。
- 清掉 profile 内 7 个 `.bak-*` 配置备份（均含 `ds-bot` 依赖或锁行，留着就是可回滚的引入点）与 pnpm store 中 `ds-bot-0.1.4.tgz` 的条目。
- 保留：`.dsh-market/log.ndjson` 的 toggle 记录、`.plugin-manager/logs/*/pnpm.log` 的安装/卸载行——那是审计日志，不是插件文件。
