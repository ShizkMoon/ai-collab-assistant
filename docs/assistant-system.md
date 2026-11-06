# 常驻服务分布与凭据管理

> 状态：设计中 · 上位文档：[架构总览](architecture.md)、[工作站配置](workstation-windows.md)、[ADR 0007](adr/0007-deferred-resident-node.md)

## 1. 服务分布

工作站是唯一的执行节点；云服务器只承担消息搬运。家居类服务（Home Assistant、Zigbee2MQTT、n8n）随常驻节点一起延后，不在此表中。

| 服务组件 | 部署位置 | 底层实现 |
|---|---|---|
| 任务库 + `ev` CLI | 工作站 | Taskwarrior 3 + `ev` 封装；派发方为会话内 DSH Agent 或人工，无常驻守护进程 |
| 事件库与线索（`events.sqlite3`） | 工作站（主）/ 云服务器（入站暂存） | SQLite，见 [输入端口与输出路由 §3](output-routing.md#3-事件线索与线索上下文) |
| 多 Agent 任务编排 | 工作站 | DSH 会话（领导模式）编排，DSH subagent / teammate 执行 |
| 本地大模型与向量推理 | 工作站 | vLLM / Ollama |
| 统一模型网关 | 工作站 | LiteLLM |
| 入口解析与 IM 收发 | 工作站 | DSH 会话 / AstrBot |
| 消息接收与等待队列 | 云服务器 `orca-pool` | 端口轮询脚本 + `events.sqlite3` |
| 消息推送服务 | 云服务器 `orca-pool` | ntfy |
| 任务库增量备份 | 云服务器 `orca-pool` | Litestream + 每日 `.backup` + Restic |

数据库与模型缓存放在工作站本地磁盘，不做网络挂载——本地文件系统是编排循环的前提（[ADR 0003](adr/0003-loop-local-entry-remote.md)）。

## 2. 常驻服务管理规范

- 全部服务以 Windows 服务或计划任务声明，随开机自启并在后台静默运行：系统级服务用 WinSW 包装后 `sc.exe create`，用户态进程用「登录时启动」的计划任务。服务定义（WinSW XML 与任务 XML）放入 `%ProgramData%\aica\units\`，由安装脚本注册，并随 `restic` 备份留存版本。
- 命令行入口统一放置在 `%USERPROFILE%\.local\bin\` 下并加入用户 `PATH`，需要补充环境变量或运行路径时通过轻量 `.cmd` / PowerShell Wrapper 封装。
- 工作站休眠或关机期间，云服务器只把外部消息写入等待队列，不回复、不解析、不执行；恢复后由工作站按端口游标增量拉取。回复用户的「已收到」提示由端口声明，不由云服务器自行生成。
- 单机方案的直接后果是**没有服务级高可用**：工作站关机即全系统暂停。可接受的边界是输入不丢、任务不丢，否则需要重新评估常驻节点（[ADR 0007](adr/0007-deferred-resident-node.md) 的复评条件）。

## 3. 凭据与运行状态保护

- API 密钥、OAuth 令牌与平台 Cookie 一律保存在各应用的原生安全位置（Windows 凭据管理器 / DPAPI 加密或应用私有配置目录），严禁写入本设计仓库、规则文件或 Taskwarrior 任务字段中。
- 各工具的登录态 Cookie 与本地会话数据库属于有状态运行数据，不得作为临时缓存目录清理。
- 云端只保存推送凭据与端口轮询所需的会话文件，且使用独立的最小权限账号；工作站的 SSH 密钥不复制到云端。
- 端口配置文件中只写凭据的**引用路径**（如 `cred_ref = "credman:aica/wechat"`，指向 Windows 凭据管理器的目标名），不写凭据本身。

## 4. 人工确认点

全系统仅对**付款、删除、对外发布**三类不可逆操作设置人工确认点；其余操作默认直接执行，可逆变更提供默认 5 分钟的撤销窗口。
