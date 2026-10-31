# ESurfing 三路固定认证出口的持久接管

这些文件供主代理审阅与安装。子代理仅离线准备，没有连接路由器、读取私有配置或改变设备。不要覆盖主代理已经安装并通过验证的实现；先比较实际差异。源码根因见 `SOURCE-BUGS.md`。

## 绑定与所有权

| account | 接口 | 专用组／GID | 完整 mark | 独立表 | rule priority |
| --- | --- | --- | --- | --- | --- |
| 1 | wan | esauth1／65201 | 0x01000000 | 25201 | 1801 |
| 2 | wan2 | esauth2／65202 | 0x02000000 | 25202 | 1802 |
| 3 | wan3 | esauth3／65203 | 0x03000000 | 25203 | 1803 |

UID 继续为 root；GID 用于 socket 识别。不得复用 OpenClash 的 GID 65534，也不得让其他程序使用这些专用组。procd 找不到指定组时可能静默忽略 group，所以 helper 会检查 `/etc/group` 的名称、数字和唯一性；仍须读回 `/proc/<PID>/status` 的 Uid／Gid。

首次安装前检查表 25201～25203、优先级 1801～1803 和 `ip esurfing_route` 的现有内容。表为空可以接管；现有候选表只有在确认与 `stage-route.sh` 的 owner、mark、接口及网关一致时才接管。这里没有自动删除陌生规则或路由的安装器。主代理确认后，在设备 `/etc/esurfing-deploy/persistent.owner` 写入唯一一行 `esurfing-gid-route-v1`，helper 才允许修改。

精确 mark 规则使用 `/0xffffffff`，优先于 mwan3 的普通高位 mask 选择。mwan3 仍使用 `0x3f000000`；认证请求不随在线策略借用其他 WAN。与同值 mark 的普通 WAN 连接共用相同出口，需注意这些独立表也须随 DHCP 更新。所有表始终保留 metric 32760 的 unreachable 默认；接口 down 时只移除真实默认和直连项，禁止回落 main。

## 文件落点

| 准备文件 | 设备路径 | 权限／用途 |
| --- | --- | --- |
| persistent-bindings.conf | /etc/esurfing-deploy/persistent-bindings.conf | 0600；仅三条固定映射，无凭据 |
| persistent-route.nft | /etc/esurfing-deploy/persistent-route.nft | 0600；独立 ip 表，route OUTPUT priority -160 |
| persistent-route.sh | /usr/libexec/esurfing-route | 0755；路由与 nft 更新 |
| persistent-hotplug.sh | /etc/hotplug.d/iface/35-esurfing-route | 0755；DHCP up／update／down |
| persistent-esurfingclient.init | /etc/init.d/esurfingclient | 0755；上游原 init 的最小修改 |
| persistent-firewall.uci | 不直接作为配置文件复制 | 主代理检查后用 uci batch 输入，增加规则恢复 include |

首次安装先备份现有 `/etc/init.d/esurfingclient`、`/etc/config/firewall` 和当前账号 JSON 到设备的私密状态目录，保留权限。已有 esauth2／esauth3 组继续复用且核对数字；不存在的组仅在 GID 未占用时创建。不要将账号备份或 `.logout` 存档下载至工作目录。

## 接管顺序

1. 确认三路单独认证已获成功与心跳，三个地址绑定的外网探针同时可达，并观察是否互踢。只要两个 Linux 仍反复交替掉线，就不能将“三个进程”作为稳定三路目标已完成。
2. 安装 helper、固定映射、nft 和 hotplug，核对权限、组及所有权；先对三个 shell 文件执行 `sh -n`，运行 `esurfing-route check`。这些检查不启动认证。
3. 运行 `esurfing-route apply all`，读回三个精确 mark 的 `ip -4 route get`，默认网关及源地址必须对应各自接口；`nft -c -f` 由 helper 执行，之后读回链类型、priority、三个 GID 和计数器。现有候选认证仍可运行。
4. 在备份和检查同名 include 后应用 `persistent-firewall.uci`。必须 `type=nftables`、`position=ruleset-append`；默认的 table-append 会把独立 table 放进 fw4 table 内，语法不成立。先 `fw4 check` 再 reload，读回独立 table 和 WAN zone masquerade。fw4 恢复规则与 helper 初始化路由是两项职责。
5. 安装修改后的原 init。它保留上游停止、日志归档和 respawn 行为，只在开始实例前准备路由，并为每个 account 加 `group esauthN`。先停止两个临时候选 service 并等待其退出，避免和统一服务重复认证；随后由主代理在设备内将三个账号 mark 统一为上述显式值，保留原 channel 3／2／2、凭据、时间窗口及其他选项。
6. 创建 `/etc/esurfing-deploy/persistent.enabled` 标志，启用并启动原 `esurfingclient` 服务。读回三个 account 的命令、UID／GID、respawn threshold=60／timeout=5／retry=5。每路均需重新取得认证、心跳与逐源外网证据。确认后才处理实验源地址／oif 探针规则与旧临时候选状态，不要提前撤路由。

## DHCP 与服务恢复

hotplug 只处理 wan／wan2／wan3 的 ifup、ifupdate、ifdown。它先更新该接口的独立表，再判断状态；地址变化时只对对应 `accountN` 发送 SIGTERM，由 procd 独立恢复，不重启另外两路。网关变化但地址没变时刷新路由，不主动重认证。

如果接口长时间未 up，某账号可能达到上游 respawn 的重试上限。DHCP 恢复时，hotplug 只恢复**仍注册在原 service 中**、仍在 `--list-accounts` 列表中且已停止的那个实例，使用 `service add` 合并，避免 `service set` 删除其他实例。用户禁用账号或主动 stop 后，已移除的服务不会由 DHCP 事件重新创建。首次临时候选阶段没有 `persistent.enabled` 标志，hotplug 不接管候选 service。

规则恢复覆盖原 init start／reload、相关 DHCP 事件及 fw4 reload。上游升级若覆盖 `/etc/init.d/esurfingclient`，group/helper 调用可能丢失；升级后须对照这两处补丁并重新验证。外部脚本全局 `nft flush ruleset` 后、尚未触发任一恢复入口时，认证固定规则会短暂缺失；不能声称抵抗任意第三方清空。

## 必要验收与回退

本机 `sh -n` 已通过；这些持久文件的 nft 内核检查、procd 合并行为、DHCP 地址变更、接口掉线及真实重启恢复仍应以主代理设备实测记录为准。依次验证 fw4 reload 后规则存在、单实例恢复不改另两路 PID、接口 down 时标记路由不可达、恢复后认证与外网重建，以及用户 stop 后 DHCP 不擅自拉起。不要为验证一条链路而反复重启全部网络。

回退先停止统一认证与候选服务，撤销 `persistent.enabled`，恢复原 init 和账号 JSON，再恢复所备份的 firewall include 状态。确认没有专用组认证进程后才撤 GID nft 规则、精确 mark rules 和独立表；若后续文件有其他修改，不能整份覆盖旧备份。组本身留在设备不影响流量，可在确定无其他引用后单独处理。最后验证原 WAN 的认证、保活、DNS 和实际外网。
