# 助手系统运行面

> 状态：设计中 · 上位文档：[架构总览](architecture.md)、[工作站](workstation-nixos.md)

## 组成

| 组件 | 跑在哪 | 复用 |
|---|---|---|
| 事项账 + `ev` + 分派 hook | 工作站 | Taskwarrior 3 + 自建薄封装 |
| 任务编排 | 工作站 | Orca |
| 本地模型 | 工作站 | ollama / vLLM |
| 模型网关 | N100 | LiteLLM |
| IM 入口 | N100 | DS-Bot / AstrBot |
| 家居 | N100 | Home Assistant + Mosquitto + Zigbee2MQTT + ESPHome |
| SaaS 串联、webhook | N100 | n8n |
| 推送 | N100 | ntfy |
| 账备份 | N100 | Litestream / 每日 `.backup` |
| UPS | 两台 | NUT |

## 常驻服务

- 全部写成 NixOS 的 `systemd.services` / `systemd.user.services`，在 flake 里声明，开机自启，静默运行。
- 入口层用 `~/.local/bin` 薄封装，只负责修正环境变量后转发。
- 工作站离线时，N100 上的入口负责排队，回复"已收到，工作站开机后处理"，并通过 Wake-on-LAN 唤醒工作站。

## 凭据与状态

- 凭据保存在应用的原生位置（KWallet、各应用自己的配置），不写进本仓、规则或事项。
- 服务令牌和会话数据库属于运行中的状态，不能当缓存清理。

## 确认点

只有付款、删除、对外发布需要人确认，其余动作直接执行；可以撤销的动作给一个撤销窗口。
