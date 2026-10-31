# ESurfing 两路固定认证与 netifd 原生路由

本方案供主代理审阅和设备内序列部署。子代理只修改离线文件并模拟 shell，不连接设备、不读取私有配置。当前交付范围是已观察稳定的 account 1 Android＋account 2 Linux；account 3 的 JSON 可保留，但统一 init 的允许名单严格为 `1 2`，wan3 `auto=0`。Windows／iOS／另一 Linux／macOS 的第三身份在本次主代理实验中都伴随某个既有会话重新认证，不能据此承诺三路长期在线，也不能把规律概括成普遍的 PC／mobile 各一个限制。

## 路由所有权

- 主 `wan` 继续使用 main 表；account 1 的空 mark、原 channel、root UID／GID 和凭据不变。
- `wan2` 设置 `ip4table=25202`、`defaultroute=1`、`peerdns=0`、`metric=20`、`auto=1`。**netifd 独占 DHCP 默认及直连路由**，随租约、地址和接口状态增删；不再从 main 表手抄。
- `wan3` 只保留 `ip4table=25203`、`defaultroute=1`、`peerdns=0`、`metric=30`、`auto=0` 的候选配置。允许名单不含 3 时，新 helper 不为它建立 rule／guard，init 不启动它。
- 新 helper 仅拥有 account 2 的 GID 65202、完整 mark `0x02000000/0xffffffff`、优先级 1802 的 rule 和表 25202 中 metric 32760 的 unreachable default。DHCP default 的 metric 20 优先于 guard；接口 down 后 guard 阻止回落 main。
- 新 nft 文件只有 GID 65202 的 `type route hook output priority -160`。这覆盖 ESurfing 清洁启动初次检测漏 SO_MARK 的源码路径。account 1 不进入此链的 GID 匹配。

`ip4table` 并非只加一张表，netifd 还会建立地址／网段和本机接口策略规则；迁移后应读回全部 `ip -4 rule`，检查共享校园网段的自动规则。只有对应字段变化时，netifd 的 config reload 才重装该接口 IP 设置；不能用这个源码事实声称任意现有网络配置都不会发生变化。

固定源码阅读入口：[netifd interface.c](https://github.com/openwrt/netifd/blob/master/interface.c) 的 `IFACE_ATTR_IP4TABLE`、`interface_change_config`；[interface-ip.c](https://github.com/openwrt/netifd/blob/master/interface-ip.c) 的 `interface_set_route_info`、`interface_handle_subnet_route`、`enable_route`、`interface_ip_set_enabled`。`defaultroute=0` 会禁用 DHCP default，即使指定了非 main 的 `ip4table`，所以这里必须改成 1。当前下载的是上游源码；设备包版本及真实规则仍由主代理核对。

## 文件与设备落点

| 本地文件 | 设备路径／执行方式 |
| --- | --- |
| netifd-network.uci | 检查已存在 wan2／wan3 后，设备内 `uci batch`；不直接覆盖 network 文件 |
| netifd-bindings.conf | /etc/esurfing-deploy/netifd-bindings.conf，0600 |
| netifd-accounts.allow | /etc/esurfing-deploy/netifd-accounts.allow，0600；当前严格 1、2 |
| netifd-route.nft | /etc/esurfing-deploy/netifd-route.nft，0600 |
| netifd-guard.sh | /usr/libexec/esurfing-netifd-guard，0755 |
| netifd-hotplug.sh | /etc/hotplug.d/iface/35-esurfing-route，0755；替换原同位置脚本 |
| netifd-esurfingclient.init | /etc/init.d/esurfingclient，0755；统一服务最终接管时使用 |
| netifd-firewall.uci | 审阅同名 include 后，设备内 `uci batch` |

所有权标志 `/etc/esurfing-deploy/netifd.owner` 必须恰为 `esurfing-netifd-route-v1`。只在统一服务接管时创建 `/etc/esurfing-deploy/netifd.enabled`；该标志出现前，hotplug 只恢复 guard，不启动／重启临时候选或原 Android。

原 `persistent-*` 为手写 DHCP 路由方案，不能与新方案同时运行。原 helper 已补有限重试并从 DHCP 地址／mask 算子网，作为离线备选；当前推荐新方案。保留原文件作为恢复证据，不从目录中删除未知状态。

## 最小接管顺序

1. 在路由器的私密目录备份当前 network、firewall、原 stock init、hotplug 和账号 JSON，保留权限；只回传无凭据差异。确认 PID 3789／4661 等当前进程值仍有效，主 Android 的实际外网和保活继续正常。备份不是长期稳定性证明。
2. 暂停旧生命周期入口：撤销旧 `persistent.enabled`，替换原 hotplug，并把 `firewall.esurfing_route` 的已知旧 include 改为新 nft 文件。不要让旧 `esurfing-route apply` 再 flush netifd 的表。
3. 检查 GID 65202 只属于 esauth2、优先级 1802 的现有规则确属当前候选、表 25202 的真实路由确属本次手工阶段。安装新文件和 owner 标志。账号 3 保持已停止，wan3 down；此时不要启用统一 init。
4. 在 **WAN2 单独 down 的窗口**中清理已审阅的手工真实路由，保留 unreachable default 和正确 mark rule；不得清理 main／未知表。具体旧条目必须按设备读回匹配，不盲目执行整表 flush。当前旧手工 default 是 metric 10，新 DHCP default 是 metric 20；旧 default 若残留会优先于 netifd，不能靠安装新 helper 消除。
5. 输入 `netifd-network.uci`，检查 diff 只涉及 wan2／wan3，保存后用 `ubus call network reload` 让 netifd 读取配置，再只对 wan2 执行 `ifup`（如 reload 已因 auto=1 启动，不重复 down/up）。不要 `/etc/init.d/network restart`，不要修改主 wan 或无线配置。执行新 `esurfing-netifd-guard check` 和 `apply all`。此过程仅暂停候选出口，主 Android 认证与 main 表应保持。
6. 读回表 25202：必须有 netifd 管理的当前网段／源地址和 DHCP default via 当前网关、metric 20，以及 unreachable default metric 32760。`ip -4 route get 1.1.1.1 mark 0x02000000` 应落当前 eswan2 且 src 为该 DHCP 地址；规则 1802 指向 25202。主 mark 空的路由仍由 main 选择。
7. 对新 firewall include 执行 `fw4 check`，然后 reload，读回独立 `ip esurfing_route` table、GID 65202、priority -160。规则恢复和 netifd 路由恢复是不同职责。重新启动候选 2（如曾暂停），确认其认证、心跳和逐源 HTTPS；主 Android PID、保活与实际外网也要读回。
8. 只有两路再次通过后，停止临时候选 2，安装新统一 init、创建 `netifd.enabled`，由主代理执行一次统一服务接管。统一服务切换会停止并重建认证实例，可能有短暂认证窗口；不是热迁移。其命令只应出现 `--account 1`／`--account 2`，account 1 不带专用 group，account 2 的实际 Gid 为 65202，respawn 输出为 60／5／5。JSON 即使保留 account 3，不能出现 account3 实例。

候选 2 的 account mark 保持 `0x02000000`；不改原 account 1 的 mark 或 channel，不导出凭据。后续 mwan3 启用时须给主出口正确分配高位 ID，并单独评估其客户端标记方式；不在本次持久化中顺带改主认证。

## DHCP、down/up 与 procd

新 hotplug 只处理 wan2／wan3；第一步恢复 guard，始终不删除任何 DHCP default 或 link 路由。因此，旧方案一次 down／up 窗口后“只剩 unreachable”的自写同步问题不会由此 helper 造成。实际 DHCP 未成功、netifd 自身失败或路由被其他软件删除，仍可能只剩 guard，必须按实机状态诊断。

允许账号且统一服务已接管时，hook 最多三次短读回，确认完整 mark 的 route get 对应当前设备／地址；只记录有效地址。same-IP down/up 不重认证，IP 改变时只给 account2 发 SIGTERM，交由 procd respawn。若仍注册的 account2 已因 crash-loop 停止，使用 `service add` 合并该实例，保留 account1；用户主动 stop 后 service 实例已移除，DHCP 不重新创建。允许名单不含 3 时，wan3 事件不会重建 rule 或启动进程。

这不是后台 watcher，也不通过短周期重启多个认证来维持表面在线。shell 模拟只能证明分支、调用范围与数据格式，不能证明设备内核／netifd／procd 的真实调度。

## 与 mwan3-nft 的组合

当前 mwan3 保持停止，先验收两路持久化。以后在现有 `globals` 中去重增加 `list rt_table_lookup '25202'`，如重新验收并启用第三路，再增加 `'25203'`；不要把 1／2／3 这些 mwan 自有目标表加入 lookup，形成循环来源。mwan interface 配置仍按 wan、wan2、wan3 顺序，3 可 disabled，防止 ID 偏移。

[mwan3 v3.6.12-1 create-iface-route.uc](https://github.com/dl12345/mwan3/blob/cdd4fc56f4de9ccf56d40d6dc04a5b6a4e5a0ae6/files/lib/mwan3/mwan3-create-iface-route.uc) 会从 main 和额外表取路由，再按 ubus `l3_device` 映射，只把每条 default 复制到对应 mwan 表。直连路由也能复制。无 oif 的 unreachable default 不能对应某个 WAN，因此不会当作该 WAN 的 DHCP default 复制；mwan 自有下线拒绝规则仍须验收。其 `mwan3-list-routes.uc` 跳过 default，只把子网加入 custom set，不会因为这些表有 default 就把整个互联网列成 custom bypass。

验证时要看到 mwan 目标表 2 中的 WAN2 DHCP default，而不是仅看到 `rt_table_lookup` 已写入。接口 up/down 由 mwan hotplug 更新，地址 renew 及 route-monitor 行为仍须按实际包验证。保持 `mmx_mask=0x3f000000`；不得让 UA3F 全值 connmark 写入或 OpenClash 本地接管 mark 覆盖认证路由。启用 mwan 前，主代理还须单独把 account 1 固定到主出口，防止普通 OUTPUT 分类将其未标记认证连接分给 WAN2；当前离线文件保持主 stock 身份，未抢先实现这个下一阶段改动。

## 设备验收与回退

在主线每次变更后分别读回：主 PID／GID、主逐源 HTTPS／保活；候选 PID／GID、表 25202、exact mark route get、候选逐源 HTTPS／两次 heartbeat；account3 不存在且 wan3 down。然后依次验证 `fw4 reload`、wan2 单独 down/up、DHCP renew／地址变化和真实重启。每次只改变一个入口，不能把语法模拟当作真实重启恢复。

回退先停新统一服务或候选 2，撤销 `netifd.enabled`，恢复原 stock init／旧已知 firewall include 和必要 network 字段。先停用新 hook，再恢复原手工路由 helper；不能在 netifd 仍持有 25202 时让旧 helper flush。同样只处理已确认所有权的 rule／guard。保留账号 3 的配置备份，不恢复其自动启动。最后验收主 Android 的外网、DNS 和保活。

## ARP 假设的观察范围

当前主代理只读结果为 all／default／wan 的 `arp_ignore=1`、`arp_announce=0`、`rp_filter=0`。Linux `arp_ignore`／`arp_announce` 的有效值取 all 与设备值的较大者；新 macvlan 的设备值还应在创建后读回。因此不能再把默认 `arp_ignore=0` 的 ARP flux 当作本次已证实主因。[内核 IP sysctl 文档](https://docs.kernel.org/networking/ip-sysctl.html)。

候选创建后只读检查 `/proc/sys/net/ipv4/conf/{all,default,wan,eswan2}/arp_ignore`、`arp_announce`、`rp_filter`，以及 `ip -d link show eswan2` 的 bridge 模式与 MAC、`ip -4 address`、`ip -4 neigh show dev wan`／`eswan2`。可用 `tcpdump -ni wan -e -c 80 arp` 限量观察 ARP 头：每个校园 IP 的应答源 MAC 是否对应它的设备，是否有同一 IP 多 MAC 的回复。避免抓取／回传认证 HTTP 的正文、ticket 或密码。

macvlan bridge 允许 sibling macvlan 本地互通；父接口与其 macvlan 子设备的主机内通信另有隔离限制，不能据此推断上游外网失败。多个虚拟设备经同一物理线连接上游，不等于服务端允许同账号多会话。`arp_announce=2` 会限制 ARP 请求的源地址选择，但当前没有相反 IP／MAC 绑定证据，所以不添加该 sysctl。`rp_filter=0` 已满足避免反向路径严格检查的条件，也不重复改设置。[ip-link macvlan 文档](https://man7.org/linux/man-pages/man8/ip-link.8.html)。
