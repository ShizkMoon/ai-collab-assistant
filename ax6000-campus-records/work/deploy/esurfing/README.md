# 三路认证部署候选：保留原 WAN，逐路增加 Linux／Android

这些文件由子代理准备，只有主代理在路由器上序列执行。子代理没有连接路由器、读取私密账号配置、执行认证或改变网络。当前持久接管优先采用 `NETIFD-DEPLOYMENT.md` 的两路原生路由方案：主 Android＋一个 Linux，允许名单只启动 1／2，候选 3 保留但停用。`persistent-*` 与 `PERSISTENT-DEPLOYMENT.md` 是先前手写路由备选，不与 netifd 原生表同时运行。候选与持久 shell 文件已通过本机 `sh -n`；状态提取 awk 已通过合成日志的凭据不泄漏检查；`simulation-results.json` 记录实际 shell 的离线模拟。ucode、netifd、ubus procd 和实际认证仍需主代理在真实路由器上验证。不能把源码检查或语法检查写成部署成功。初次检测遗漏 mark 的源码问题见 `SOURCE-BUGS.md`；候选启动也已要求专用 GID 与相应 route OUTPUT 规则，单靠账号 SO_MARK 不能覆盖清洁启动的第一次检测。

## channel 的真实含义与凭据边界

固定 ESurfing `v2.1.5-r6` 提交为 `cc181fdef686a1e31628f1ae3d8ec97fe6e5ad09`。`channel` 可用数字或不区分大小写的名称：

| channel | 名称 | 源码的 CCTP User-Agent |
| --- | --- | --- |
| 1 | windows | `CCTP/WinSVR5/1068` |
| 2 | linux | `CCTP/Linux64/1003` |
| 3 | android | `CCTP/android11_64/2104` |
| 4 | ios／iphone | `CCTP/iOSdy/4023` |
| 5 | macos／mac／osx | `CCTP/macdy/5019` |

`channel` 选择的是客户端认证协议身份，不是程序实际运行平台。OpenWrt 上的同一个二进制能选择 Linux 或 Android；两个 Linux channel 也不是安装两套 Linux。通道 UA 参与认证 HTTP 与 XML，票据阶段根据服务端返回的 ZSM／Algo-ID 初始化对应密码算法。因此不只是 LuCI 下拉框名称不同。[ConfigAccounts.c](https://github.com/BadGhost520/ESurfingClient-CVersion/blob/cc181fdef686a1e31628f1ae3d8ec97fe6e5ad09/esurfingclient/app/src/config/ConfigAccounts.c)、[DialerTicket.c](https://github.com/BadGhost520/ESurfingClient-CVersion/blob/cc181fdef686a1e31628f1ae3d8ec97fe6e5ad09/esurfingclient/app/src/clients/dialer/DialerTicket.c)。

Android channel 没有单独的配置密码字段，也没有要求填手机 IMEI、设备码或短信验证码的输入。所有通道的 LOGIN XML 都从对应 account 对象读取 `username`／`password`；GET_TICKET XML 不包含这两项凭据。Android 与 Linux 的本机实现都沿用相同的初始化会话、取 ticket、登录、保活流程。`Refresh.c` 会生成协议使用的主机名、client_id 和 MAC 字段；这不是 netifd macvlan 的真实二层 MAC，也不能代替独立 DHCP 地址。[Xml.c](https://github.com/BadGhost520/ESurfingClient-CVersion/blob/cc181fdef686a1e31628f1ae3d8ec97fe6e5ad09/esurfingclient/app/src/utils/Xml.c)、[Refresh.c](https://github.com/BadGhost520/ESurfingClient-CVersion/blob/cc181fdef686a1e31628f1ae3d8ec97fe6e5ad09/esurfingclient/app/src/states/Refresh.c)。

据此可以**在路由器内部复用当前已验证的账号／密码作为 Android 通道的候选凭据**。这不证明服务端一定接受，不证明两条 Linux 可以同时在线，也不证明每条有独立带宽。若 Android 返回密码或通道拒绝，要记录实际错误并停止该候选，不自行生成新密码、设备码或反复改变身份。是否成功以该 WAN 的实际认证结果、原会话状态和后续保活为准。

主代理已只读确认原 `wan` account 的 channel 为 `3/Android`、mark 为空。因此按原会话不变的目标顺序为：当前 `wan` 的 Android、`wan2` 的 Linux、`wan3` 的 Linux，达到两个 Linux＋一个 Android，不需改原 channel。脚本**不修改原 account**；通道表述及新增序列已据此修正。

## JSON 配置结构

OpenWrt 的 `/etc/config/esurfingclient` 是 JSON，不是常规 UCI 文本。每个 account 有 `username`、`password`、`channel`、字符串 `mark`、`time_windows`。同一 username 可在多个对象重复，代码没有拒绝；各对象由 `--account N` 按从 1 开始的数组序号独立运行。真实凭据不应进入本地脚本、命令参数、聊天或回传日志。[Config.c](https://github.com/BadGhost520/ESurfingClient-CVersion/blob/cc181fdef686a1e31628f1ae3d8ec97fe6e5ad09/esurfingclient/app/src/config/Config.c)、[多实例 init](https://github.com/BadGhost520/ESurfingClient-CVersion/blob/cc181fdef686a1e31628f1ae3d8ec97fe6e5ad09/esurfingclient/files/etc/init.d/esurfingclient)。

最终三路 mark 的设计为：

| 实际接口与数组序号 | channel | 最终高位 mark | 前提 |
| --- | --- | --- | --- |
| wan／account 1 | android／3 | `0x01000000` | mwan interface ID 必须是 1 |
| wan2／account 2 | linux／2 | `0x02000000` | mwan interface ID 必须是 2 |
| wan3／account 3 | linux／2 | `0x03000000` | mwan interface ID 必须是 3 |

初期原账号的 mark 保持原值，原认证进程保持运行。新增两个账号使用独立临时完整 mark 规则；直到三路已验证、mwan3 的表与规则都准备好，再由主代理对原账号的 mark 做受控迁移并短暂重启多实例服务。不能先改原账号高位 mark、再去补路由。

`append-account.sh` 在路由器上调用 `append-account.uc`，从指定的已验证账号复制字段，仅改变新对象的 channel 与 mark；原账号、顶层选项和时间窗口保留。不启动认证。ucode 输出只有新增数组序号。准备错误留在 0700 状态目录，配置与备份为 0600。

## 文件职责

| 文件 | 执行目的 | 原 WAN 的处理 |
| --- | --- | --- |
| `stage-network.sh apply/rollback` | 按 wan2／wan3 建 macvlan、获取 DHCP；备份网络／防火墙并做哈希保护回滚 | 不改变接口、DNS、认证；network reload 应保留未变接口，仍须读回 |
| `stage-route.sh up/down` | mwan3 尚未运行时建立独立认证路由表 `25202/25203` 与完整 mark 规则 | 不更改原规则；表中保留 unreachable 默认作为失败兜底 |
| `append-account.sh`＋`.uc` | 路由器内部追加一个候选 account | 保留原对象和运行中的原进程 |
| `candidate-auth.sh start/stop` | 以临时独立 procd service 运行新增数组序号 | 不重启原 `esurfingclient` service，不注册开机项 |
| `rollback-account.sh` | 在新增进程已停止后恢复该步骤的 JSON | 哈希不符就拒绝覆盖，按新增顺序逆序回滚 |
| `stage-probe-route.sh up/down` | 临时为 curl 的候选源地址和绑定设备添加独立表规则 | 不操作原 WAN；主代理已有同优先级规则时不重复执行 |
| `auth-status.sh`＋`.awk` | 从客户端私密日志输出固定脱敏事件 | 只读，按数组索引及可选当前 PID 过滤 |
| `mwan3-threeway.uci.example` | 供最终 mwan3-nft 配置审阅 | 默认普通 IPv4 仍选 `wan_only`，没有自动启用三路均衡 |

`/etc/esurfing-deploy/` 保存路由器内的私密备份、步骤索引和哈希。未整体清理该目录；回滚过的状态改名保留。若途中 `uci` 或 reload 失败，停止、检查备份及实际状态，不继续下一步。

`stage-route.sh` 优先从当前候选接口的 `route` 读取 DHCP 默认网关，若 `defaultroute=0` 将其放在 `inactive.route`，再读取这一项；两处都没有网关就停止，不复制原 WAN 的网关。主代理已经在实机读回 wan2 的独立租约，以及网关位于 `inactive.route` 的状态，这验证了需要该分支；独立租约仍不等于认证成功。

## 主代理的序列执行入口

以下命令只是可审阅入口。子代理没有执行。先确认原 DHCP／认证／联网基线，核对可写空间、工具及内核 macvlan 支持；不凭驱动模块文件名推断 netifd 已支持。确定真实物理 WAN 设备，不能把 `br-lan` 或逻辑接口名误作下层设备。独立 MAC 使用以 `02` 开头的本地管理单播地址，核对与现有设备不同。

把脚本放到路由器同一目录后先做只编译检查：

```sh
sh -n /tmp/esurfing-deploy/stage-network.sh
sh -n /tmp/esurfing-deploy/stage-route.sh
sh -n /tmp/esurfing-deploy/append-account.sh
sh -n /tmp/esurfing-deploy/candidate-auth.sh
sh -n /tmp/esurfing-deploy/rollback-account.sh
ucode -c -o /tmp/append-account.ucb /tmp/esurfing-deploy/append-account.uc
```

按实际设备与独立 MAC 执行 wan2；下列大写占位值必须替换，不能原样运行：

```sh
sh /tmp/esurfing-deploy/stage-network.sh apply wan2 PHYSICAL_WAN_DEVICE 02:XX:XX:XX:XX:02
# 主代理读回 wan2：up、独立地址、网关、DNS、MAC；与原 wan 不同，并检查原会话。
sh /tmp/esurfing-deploy/stage-route.sh up wan2
sh /tmp/esurfing-deploy/append-account.sh wan2 1 linux
# 只有标记路由、凭据复用及原会话都已核对，才执行下一项认证动作。
sh /tmp/esurfing-deploy/candidate-auth.sh start wan2
```

原连接、wan2 登录与保活都通过后，用另一个 MAC 对 wan3 重复同一阶段，仍使用 `linux` 通道。不要一次性创建并启动两个候选。如果两个 macvlan 获取相同地址、没有第二租约、第二次登录挤掉原会话或标记路由回落到原 WAN，停止推进并报告实际状态。

临时认证服务由 procd 管理，预备 JSON 中只有程序与数组索引，没有密码。它们没有持久开机脚本；路由器重启后原 ESurfing 包会按已经追加的账号数组启动自身实例。**因此实验过程中不要假定重启仍然保持只有原账号运行**；若要回到单路开机状态，应先停止候选，逆序回滚新账号。最终统一切换到原包多实例服务之前，先停止临时候选服务，以免同一索引被两套 service 重复认证。

回滚一个未通过的新增候选，顺序为：停止候选认证并确认进程退出／登出 → `rollback-account.sh` → `stage-route.sh down` → `stage-network.sh rollback`。有 wan3 与 wan2 两阶段时整体按 wan3、wan2 逆序。若最终迁移或其他模块已改变配置，哈希保护会拒绝覆盖，主代理按保存的对应备份进行合并恢复，不能强制覆盖后续配置。

## 从临时路由迁移到 mwan3-nft

固定社区版 `v3.6.12-1` 将**所有** `config interface` 段按顺序编号，包括 disabled 段。因此不能保留一个插在 wan 与 wan2 之间的 wan6 段，然后假定 wan2 的 ID 仍为 2。最终按实际状态文件／规则确认接口 ID、mark 和表号。[固定 mwan3.sh](https://github.com/dl12345/mwan3/blob/cdd4fc56f4de9ccf56d40d6dc04a5b6a4e5a0ae6/files/lib/mwan3/mwan3.sh#L58-L82)。

另一个必要条件是路由来源。该版 `mwan3-create-iface-route.uc` 从 main 及显式额外源表读取路由，按实际设备复制默认路由到各接口表。初期保护原 WAN 所用的 `defaultroute=0` 可能让 wan2／wan3 在 main 没有默认路由；**不能保持这个设置就宣称 mwan3 表 2／3 已有出口**。[固定 route helper](https://github.com/dl12345/mwan3/blob/cdd4fc56f4de9ccf56d40d6dc04a5b6a4e5a0ae6/files/lib/mwan3/mwan3-create-iface-route.uc)。

常规迁移路线是在备份后，将已验证的 wan2／wan3 改为 `defaultroute=1`，保持其 main metric 为 `20/30`，先确认原 WAN metric 比它们低；更新候选接口，读回 main 里每个设备各有自己的默认路由。随后生成高位 mwan3 规则并验证表 1／2／3、跟踪出口及失败兜底，再移除临时精确 mark 规则。另一种路线是保留非 main 的显式路由源表，但它需要 DHCP 变化维护与 `rt_table_lookup` 配套，当前最小脚本没有实现该持久方案。

示例的两个公网 ping 目标只是待验证占位方案。主代理需要先从每条已认证 WAN 验证它们确实可达；若校园屏蔽 ICMP，应换成经该版支持且实际验证的跟踪方法。只检查校园网网关、或让所有 tracker 借原 WAN，不证明三路认证有效。普通流量先 `wan_only`；三个会话及各自真实出口通过后，再评估 `balanced_threeway` 的并发总量。

原账号必须迁移为与真实 WAN ID 对应的高位 mark，最终三路全部显式填写，减少自动编号与自定义混用的歧义。主代理完成统一服务切换后再重读进程、channel、mark、独立地址和保活。失败时恢复原配置并重新验证原 WAN；不能只看到三个 PID 就报告三路在线。

## 与代理的后续组合

在本阶段只验证三路认证及出口，不启动全局负载均衡、OpenClash／UA3F 全局规则。之后接入代理时，继续采用 `routing.md` 的边界：OpenClash 的本地 TPROXY `0x162` 是完整 mark 匹配，mwan3 高位不能随意叠入本地接管包；先分离本地接管路径，等核心新 OUTPUT WAN socket 再分类。UA3F HTTP NFQUEUE 的整值 ct mark 写入仍需避免或修补。认证／保活／校园 DNS 固定出口及节点 bootstrap 直连也要保留。

ESurfing 的 DEBUG `5` 会记录包含 password 的 XML，保持 INFO `4`；INFO 中仍有 ticket／会话信息，只读需要的成功、失败及保活状态，不把原始认证日志全部回传。独立 DHCP、启动进程、认证成功、持续保活、三路并发总量是五个不同验收结果。

## 脱敏状态与临时出口测试

原包与临时候选的日志编码可能让中文 `grep` 失败。`auth-status.awk` 按 ASCII 的 `[auth#N pid=PID]` 及固定源码定位生成事件，完全不输出原文消息；用户名、password XML、URL、ticket、client_id 等不进入输出。最近最多 40 个事件，支持当前 PID 过滤以免把旧会话成功当作本次成功。`AUTH_SUCCESS` 来自 `DialerAuth.c:138`，`HEARTBEAT_SUCCESS` 来自 `DialerClient.c:90`；只有 `INTERNET_ALREADY_REACHABLE` 不能说明该候选发起并完成了认证。固定源码行号变化后要更新提取器。

客户端日志优先用 `/usr/bin/esurfingclient --print-log-dir 2>/dev/null` 定位；该查询不启动认证。它返回实际日志目录，配置的 `log_dir` 是基目录，程序还会追加 `logs`。另可只读候选 PID 的 `/proc/PID/fd` 链接定位日志句柄。不要凭一个旧 `thisrun.log` 或 `logread` 无中文结果推断候选状态。

```sh
# 路径与 PID 以实际读回为准；不输出完整私密日志。
sh /tmp/esurfing-deploy/auth-status.sh /ACTUAL/PRIVATE/LOG/run.log 2 CURRENT_PID
```

候选 procd 的 service 名为 `esurfing-candidate-wan2`，instance 名为 `account2`，命令为 `/usr/bin/esurfingclient --role auth --account 2`；wan3 对应变化。直接调用 `ubus service set` 时，respawn 输入必须使用字符串数组 `["60","5","5"]`；原包的 `procd_set_param respawn 60 5 5` 生成这个数组。不能传数字数组 `[60,5,5]`：procd 用 `atoi(blobmsg_get_string())` 读取每项，数字 blob 不符合该输入约定。`service list` 返回的 `{threshold,timeout,retry}` 对象是输出格式，不能回抄为输入。`term_timeout=15`，stdout／stderr 开启。主代理可从该 service 提取 running、pid、exit code，但不要整段回传 env 或全局服务内容。[procd 输入解析](https://github.com/openwrt/procd/blob/master/service/instance.c)。

`curl --interface eswan2` 只绑定设备，不保证策略表已有路由；`defaultroute=0` 时该设备在 main 缺默认路由，curl 失败不等于 ESurfing 带 `SO_MARK` 的连接失败。`stage-probe-route.sh` 可临时添加 `from 当前地址/32` 和 `oif 当前设备` 规则指向该候选临时表，测试完删除。主代理已加相同优先级的规则时不重复运行。测试可用实际源地址配合 `curl --interface 实际IPv4`，检查 HTTP 状态及超时；仍须另外检查认证和保活。

## 已下载的 mwan3 APK 核验

文件为 `mwan3-3.6.12-1_openwrt-25.12_aarch64_cortex-a53.apk`，来自 [上游固定发布](https://github.com/dl12345/mwan3/releases/tag/v3.6.12-1)。文件大小 `85,713` 字节，SHA-256 为 `7123dc1c306241e40870c0402ba503396b45f84625731dbf0c8979053e3959a4`，与 GitHub asset 的 digest 相同；ADB 元数据版本为 `3.6.12-r1`，架构 `aarch64_cortex-a53`，installed_size 为 `334,460` 字节。固定架构与 digest 核验不证明当前 SNAPSHOT 的 libc、ucode 模块 ABI 或完整依赖可用，主代理仍需 apk 模拟解析。

包声明的直接依赖为：`ip-full`、`jshn`、`kmod-nft-core`、`libc`、`libnetfilter-conntrack3`、`nftables-json`、`rpcd-mod-ucode`、`ucode`、`ucode-mod-fs`、`ucode-mod-log`、`ucode-mod-rtnl`、`ucode-mod-socket`、`ucode-mod-ubus`、`ucode-mod-uci`、`ucode-mod-uloop`；声明提供 `mwan3-any`。包自带 `libwrap_mwan3_sockopt.so.1.0` 和 ucode helpers，不只是 shell 文件。完整 ADB 元数据、文件列表和安装脚本位于同目录 `apk-inspection.json` 及 `extracted-mwan3-3.6.12-1_openwrt-25.12_aarch64_cortex-a53/`。

**安装脚本会执行真实网络服务动作**：fresh install 的 preinst 写首次安装标志，postinst 会自动 enable／start mwan3、restart rpcd，并迁移／清理旧 mwan3 规则。包中默认各接口与 rule 虽为 enabled=0，仍会运行 general nft hook，不能把 `apk add` 当作纯落盘。安装前备份并安排受控启动顺序，明确新服务何时允许建规则；安装后立即读回服务、规则和原认证，不等待全部参数配完后再检查。
