# 常驻服务分布与凭据管理

> 状态：设计中 · 上位文档：[架构总览](architecture.md)、[工作站配置](workstation-nixos.md)

## 1. 双机组件分布

| 服务组件 | 部署主机 | 底层实现 |
|---|---|---|
| 任务库 + `ev` CLI + 派发器守护进程 `evd` | 工作站 | Taskwarrior 3 + 自建轻量守护进程 |
| 多 Agent 任务编排 | 工作站 | Orca |
| 本地大模型与向量推理 | 工作站 | vLLM / Ollama |
| 统一模型网关 | N100 | LiteLLM |
| 对话与 IM 入口 | N100 | DS-Bot / AstrBot |
| 智能家居中枢 | N100 | Home Assistant + Mosquitto + Zigbee2MQTT + ESPHome |
| 外部 SaaS 与 Webhook 接入 | N100 | n8n |
| 消息推送服务 | N100 | ntfy |
| 任务库增量备份 | N100 | Litestream + 每日 `.backup` + Restic |
| UPS 电源监控 | 工作站 + N100 | NUT（N100 作为 Primary，工作站作为 Secondary） |

## 2. 常驻服务管理规范

- 所有常驻服务统一通过 NixOS 的 `systemd.services` 或 `systemd.user.services` 在 Flake 中声明，随系统开机自启并在后台静默运行。
- 命令行入口统一放置在 `~/.local/bin/` 下，需要补充环境变量或运行路径时通过轻量 Wrapper 脚本封装。
- 当工作站处于休眠或关机状态时，N100 上的入口服务负责将重负载任务暂存排队，向用户回复"已加入队列，等待工作站唤醒后处理"，同时发送有线 Wake-on-LAN（WoL）魔术包唤醒工作站。

## 3. 凭据与运行状态保护

- API 密钥、OAuth 令牌与平台 Cookie 一律保存在各应用的原生安全位置（如 KDE KWallet 或应用私有配置目录），严禁写入本设计仓库、规则文件或 Taskwarrior 任务字段中。
- 各工具的登录态 Cookie 与本地会话数据库属于有状态运行数据，不得作为临时缓存目录清理。

## 4. 人工确认点

全系统仅对**付款、删除、对外发布**三类不可逆操作设置人工确认点；其余操作默认直接执行，可逆变更提供默认 5 分钟的撤销窗口。
