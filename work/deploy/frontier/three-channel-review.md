# 独立新账号的第三手机通道接入审阅

本轮可在不重启整机、保留原两路认证进程的条件下加入第三路。使用新账号的 Android `channel=3`，保留固定 `account3 → wan3/eswan3 → esauth3/GID 65203 → 完整 mark 0x03000000 → 表 25203`。不要重新使用原第三份同用户名配置的 Windows／Linux 身份。Root 是唯一设备操作者；本支线只读取指定安全副本、写离线候选并执行模拟，没有 SSH、凭据读取或生产写入。

Root 的本轮预检确认：允许名单 `1 2`；wan3 已有 DHCP 定义、`auto=0`、`ip4table=25203`，但 down；GID 65203 已存在；MWAN interface 按 wan／wan2／wan3 排列；只有源表 25202 被 MWAN 收录；第三 MWAN 表尚无 default。现场 `/lib/mwan3/mwan3.sh` 与既有生产 RR 副本 SHA256 同为 `b46f6b29884916aba60f2a5dfc4b98b20fff0441d75bff16b83b8026194313be`；现场 init 和 25-hotplug 也与已读包副本逐字节相同。依据见 `three-preflight.json`、`live-mwan3-lib.sh`、`live-mwan3-common.sh`、`live-mwan3.init.sh`、`live-25-mwan3.sh`。

## 必须同步的契约与精确位置

| 位置 | 现有行为／问题 | 本轮最小调整 |
| --- | --- | --- |
| `live-esurfingclient.sh:77` | 只接受允许名单 1／2，加入 3 会拒绝整个启动 | `three-esurfingclient.sh:77` 只增加 3，保留重复项与字段数拒绝 |
| `live-esurfingclient.sh:100–108` | 只为 wan／wan2 写初始 DHCP 地址基线 | `three-esurfingclient.sh:100–108` 增加 idx3 到 wan3；原 group／respawn 不变 |
| `live-esurfing-netifd-guard.sh:31–38` | 绑定本来就支持候选 2／3，是否准备第三路由由允许名单决定 | `three-esurfing-netifd-guard.sh:17` 严格验证允许名单 1／2／3；默认仍为 1／2；不改绑定和完整 mask |
| `live-netifd-route.nft:5–7` | 原主 DEFAULT bypass 与第二全 mark 存在，第三 GID 规则缺失 | `three-netifd-route.nft:7` 仅增加 65203 设置 0x03000000；原两行逐字保留 |
| `live-35-esurfing-route.sh:4,14,57–78` | 已有 wan3 映射和单实例恢复，但只恢复已注册 account3 | 候选 `three-35-esurfing-route.sh` 与现场逐字节相同；第一次启动由 Root `service add` 注册 |
| `live-95-esurfingclient-wan.sh:3–12` | 主 wan 迟到时补启动整个获允许服务 | 候选逐字节不变；不能改成任何 wan3 ifup 都全服务 start |
| `live-90-ua3f-wan-ttl.nft:5–6` | TTL 仅覆盖 wan／eswan2 | `three-90-ua3f-wan-ttl.nft:7` 增加 eswan3；保持 IPv4、TTL≥10、64、BPF/offload 关闭 |
| `live-mwan3-lib.sh:694–701,1171–1268` | UA3F socket 低位 0xc9；RR 的模数按在线同 metric 成员权重动态生成 | 不修改 RR 代码；新增 wan3_equal，成员均 metric 1／weight 1，读回 `numgen inc mod 3` |
| `live-mwan3-common.sh:467–505` 与 `live-mwan3-lib.sh:1058–1092` | 认证精确 rule 与普通 MWAN masked rule 是两层 | 保留 1803 完整 mask→25203；另由 MWAN 建 2003 高位 mask→表 3，并补第三高位 unreachable backstop |
| `live-25-mwan3.sh:73,94` | ifup／connected 会清理全部未回包 MWAN 连接 | `three-25-mwan3.sh` 仅对 wan3 跳过这两次清理；其他接口路径不变 |
| `live-mwan3.init.sh:277–303` | tracker 数量不符时 reload 升级为 stop/start | 不调用全服务 reload；只 `service add` 合并 track_wan3，再对 rtmon_ipv4 发 HUP |

`three-netifd-accounts.allow` 默认只有 `1 2`。安装支持第三索引的代码不等于开启第三账号。第三认证启动阶段再明确把 3 写入实际允许名单，与第三 nft 规则同步。nft 候选中预备的第三 GID 行不会创建进程；默认名单仍阻止第三 route guard 和统一 init 启动。批量加载这个独立 nft 表时，原两路表达式保留，不需要全 fw4 reload。

## mark 与路由不能混同

认证 socket 的 GID pin 设置完整 `0x03000000`，由优先级 1803 的 `fwmark 0x03000000/0xffffffff lookup 25203` 选择 netifd DHCP 路由。该表须同时有当前 DHCP link/default 与 metric 32760 的 unreachable default。不要重新执行旧 `persistent-route` 或 `stage_third_ios.py` 的手写 default／源地址／oif 接管。

UA3F 第三路出站的复合 mark 是 `0x030000c9`，不会匹配上述完整 mask rule，而是由 MWAN 的 `0x3f000000` mask 选择表 3。必须将源表 25203 去重加入 `mwan3.globals.rt_table_lookup`，使实际 eswan3 DHCP default 被复制到表 3；同时读回低位 c9 未被覆盖。只认证成功而表 3 缺路由，会使随后业务失败。第三 masked lookup 失去路由时需要高位 unreachable backstop，防止复合 mark 回落 main；不能把 1803 放宽为高位 mask，绕过 MWAN 的 tracker 与政策生命周期。

## 不重启、保留已有连接的接入顺序

1. Root 在受保护位置保存原第三账号与本轮相关配置，私有字段不进入本报告。保留 1／2 所有字段和 PID，第三替换为独立新账号 Android 3。原第三 `.logout` 属于旧身份，任何处理只能针对 index 3，不能清理 1／2 存档。
2. 第三仍不进入 MWAN 分流。只 `ifup wan3` 获得 DHCP，检查 25203 当前 default/link、1803 精确 rule、独占 GID 65203 和第三 nft 行，再用统一服务的 `service add` 仅注册 account3；respawn 使用字符串数组 `["60","5","5"]`。不要执行 esurfing reload，其实现是 stop/start。35-hotplug 不会首次创建未注册账号。
3. 记录当前第三 PID 的新 AUTH、实际首心跳、服务端返回间隔、独立请求与原两路 PID。Root 已报告 account3 PID 9375、DHCP 10.207.117.66、AUTH 21:19:36、实际首心跳 21:19:44，下一间隔 850 秒；多次三源 HTTP 204，原 PID 7620／7679 不变。另一个自然心跳预计约 21:33:54。首心跳与短时持续外网可支持继续受控接入，尚不等于完整长期保活；不缩短服务器间隔，不靠重认证制造第二次成功。
4. 安装审阅后的 `three-25-mwan3.sh`，执行下列候选，待 tracker 自然 online 后读回业务结果。保持原两路及 Ninja 协议、核心、香港节点、DNS、Wi-Fi、ECN、MPTCP、offload 参数不变。

```sh
sh /tmp/three-mwan-activate.sh after-third-auth-validation
```

`three-mwan-activate.sh` 是已审阅的离线现场候选，只有 shell 语法检查，未由本支线在设备执行。它依次检查第三 route/GID 前提和已安装的无全局清理 hotplug；只写第三 tracker 字段、去重追加源表 25203 与 wan3_equal 成员；提交 MWAN 配置后核对 ID=3／mask；补第三 masked backstop；HUP rtmon_ipv4，使用 CLI `mwan3 ifup wan3` 建第三路规则和表；再用 `service add` 仅合并 track_wan3，respawn 沿用现场的 `["3600","5","5"]`；最后核对原认证 PID。它不调用全服务 reload/restart、reload_config、全局 conntrack flush 或整机重启。

脚本前部预检保留 `set -eu`。OpenWrt 函数库与其函数允许可选变量未设置，因此加载前执行 `set +u`，并令 `IPKG_INSTROOT=${IPKG_INSTROOT:-}`；库调用阶段保持 nounset 关闭。Root 首次执行已提交第三 UCI 配置，随后在旧候选加载库时因 `IPKG_INSTROOT` 未设置退出；当时原两路仍在线，认证 PID 9375／7679／7620 不变，第三 MWAN 表与 tracker 尚未建立。修正候选的 SHA256 为 `f475920fa6e99393ee74bb42eee575f1a85ae3318cdada4d09cd742242e952ef`，`sh -n` 已通过；重试后的现场读回由 Root 完成。

候选不是跨 UCI、内核与 procd 的原子事务；中间失败后应读回实际完成的步骤，不能认为所有步骤已经回退。Root 保留唯一设备写入权并负责现场错误处理。提交配置时不触发 LuCI Save & Apply 或全 reload。rtmon 必须接收 HUP，运行进程才会重新读取新增源表。

接入读回应包含：第三 table 3 DHCP default 与 2003 masked rule；第三 fail-closed backstop；UA3F `inc mod 3` 与普通 balanced `random mod 3`；第三复合 mark 的实际 dev/src；原 auth、tracker 与 rtmon PID；三源 HTTP 204、LAN 的独立 TCP 流各出口计数、DNS和当前 Ninja 节点。既有 conntrack 的出口不应因新增成员改变；新的独立连接才参与三路分配。不需要为了这一读回停止原 wan／wan2 或重启设备。

## 最小回退

先从 ua3f_bal／balanced 移除 wan3_equal，并只刷新政策使新连接回到 1／2；停止单个 track_wan3，第三 MWAN 下线只处理第三接口的 mark、规则和链；然后 `service delete` 只删除 esurfingclient 的 account3，允许名单恢复 `1 2`，wan3 `auto=0` 并仅 ifdown wan3。最后恢复本轮已知第三配置和 nft／TTL 候选，保留 1／2 原字段，读回它们的 PID、外网与心跳。不能使用 `service set` 只携带 account3 覆盖整个现有 service，也不能用全局 killall。

中止第三路时，第三连接本身可能失败；无需清理原 1／2 的 conntrack。旧整体网络重启、统一服务 reload、手工 flush 25202／25203 的流程不属于这次回退。

## 旧第三失败对这次新账号的意义

`work/deploy/three-channel-account-scope.json` 明确旧三份配置用户名全部相同；`work/deploy/ninja/three-channel-local-evidence.md:9,17–24,28–42` 复核了 Linux／macOS／iOS／Windows 旧时间线。旧第三 Linux／macOS 的约一分钟重认证，以及旧 iOS／Windows 加入后主 Android 再认证，均发生在同用户名组合。现象可以与同账号额度或设备类替换相容，却没有明确服务端原因码。这次使用独立新用户名，旧现象不构成阻止三路的已确认限制。

这些旧试验还有真实的本地混淆：清洁启动首次检测漏 SO_MARK；16:07 两张认证表只剩 unreachable default；主动统一接管造成 PID 重建；全部第三试验早于 17:22 netifd 修复；iOS／Windows 10750 秒的心跳周期只观察约 1～2 分钟。因此不能把旧 connect failure、累计 302 或 incarnation 数量直接归因于学校会话上限。

独立账号也不保证第三份独立带宽：三个出口仍共用物理 WAN 与校园上联，服务器可能还有其他策略。现在的新增价值是新账号、手机通道、已修复 netifd 生命周期和单实例启动同时保持明确。第三认证成功、完整自然保活、业务实际经过第三出口、两路／三路同源完整下载的差异，仍须分别报告；不从三个 PID 或一组 204 承诺 700 Mbps。

## 本支线验证边界

`three-contract-fixture.json` 记录 15 项实际候选 shell 的离线通过结果，系统命令由既有 stand-in 模拟：默认 1／2 不建第三 rule；显式 3 建 1803 完整 mask 与 25203 guard；重复／未知／多字段名单拒绝；init 的三路 GID和地址基线；未注册第三不自动创建；地址变化只恢复 account3；同 IP／初始基线无重认证；单实例 service add 保留原两路；signal／查询失败保留旧地址。所有六份 shell 候选通过 `sh -n`。35／95 候选与本轮 live SHA 完全相同。

离线模拟没有证明真实 nft、netifd、procd、服务器策略或速率。实际认证与外网证据由 Root 的 `three-auth-start.json`、`three-observation.json` 及后续现场接入读回负责；自然第二心跳和三路性能尚待它们对应的记录。
