# 两路 MWAN 与 OC / UA3F / 认证兼容审查

范围：离线只读 `work/deploy/esurfing` 和 `work/deploy/ninja` 中的非 private 源码与候选脚本；不 SSH、不读取订阅/账号内容、不安装。路由器部署与实时验证由主代理独占。本机验证不等于目标 BusyBox ash、NFT 内核或真实流量验证。

主代理提供的当前状态：OC redir-host、router_self_proxy=0、UDP 代理关闭；LAN 百度 200 / gstatic 204；UA3F 127.0.0.1:1080 明文 UA=FFF / HTTPS=200；934 条国内 TCP 包装已开启。只保留 Android 与 Linux 两个稳定认证会话。账号 1 使用 main，JSON mark 留空；账号 2 的 GID=65202、mark=0x02000000、pref1802→table25202，wan2 的 DHCP 路由由 netifd 所有。两 WAN 共用物理线路，不提供物理线路冗余。

## 当前结论与优先级

1. 主账号 GID 65201 在 MWAN OUTPUT 前设 DEFAULT sentinel 0x3f000000，固定沿 main，不受 MWAN online/offline 状态影响。不要匹配 UID=0/GID=0；root 同时运行 core、UA3F、DNS 和控制服务。
2. 保持 mask=0x3f000000，MWAN masked restore/save 保留 OC 低位。账号 2 继续 exact 0x02000000→25202，不要改为与 core 共享的宽泛 UID 匹配。
3. 公共/校园 DNS bootstrap 的 UDP/TCP 53→MWAN default 规则放在普通平衡规则之前，解除“认证等 DNS、DNS 又等认证 online”的启动互锁；不要只 pin 认证进程，解析由 DNS 服务的新 socket 完成。
4. 先在 UDP0 下验两路普通 TCP、UA3F TCP 和 Ninja 外层连接，再启 UDP。OC TPROXY UDP 在 MWAN PREROUTING 高位 clear/restore 前早退，保留纯低位 0x162。现有 pref100 masked rule 保留作精确路由保护。
5. stock httping 无 expected-code 配置，不能证明拒绝 302；新增 curl204 只接受 exit0 且 HTTP=204，初始 offline。源码存在 wrapper 把解析 socket 绑 WAN 的风险，但主代理已在两出口真实运行 hostname wrapper 并得到 204，现保留简单方案，不加入预解析/固定 IP。

## mark、hook 与规则顺序

| 流量 | 本机起点/低位 mark | MWAN 高位处理 | 预期出口或交付 |
| --- | --- | --- | --- |
| 主认证账号 1 | 专用 skgid65201；JSON mark 空 | OUTPUT -160 强设高位 0x3f000000 | main；不由 MWAN 健康状态截断 |
| 第二认证账号 2 | skgid65202，exact0x02000000 | MWAN 的 guarded restore/rules 不改非零高位 | pref1802→25202→eswan2；down 时 unreachable |
| LAN TCP 被 OC redirect | LAN mark 不等于外层 socket mark | OC 新建 socket 重新进 OUTPUT | Ninja/UA3F 外层按本机平衡策略独立选择 |
| UA3F 外层 TCP | SO_MARK=0xc9 | 保留低位，新增/恢复高位 0x01000000 或 0x02000000 | 两路择一；不能假设继承 LAN 出口 |
| Ninja 外层连接 | 实际 routing-mark 需私密读回 | 按本机 OUTPUT 平衡策略，ct 固定每个连接 | 两路择一；需核 source/device bind 与低位不为 0x162 |
| LAN UDP 已被 OC TPROXY | fw4 PREROUTING -150 全值设 0x162 | MWAN -149 首部早退，保持纯 0x162 | pref100→354 local→core UDP listener |
| core 新建外层 UDP / DIRECT UDP | 新 OUTPUT socket | 按本机平衡策略；不得再回 OC TPROXY | 两路择一，self_proxy=0 保持 |
| 认证域名的解析 | dnsmasq→OC→公共 UDP/TCP53 新 socket | DNS53 默认策略 | main bootstrap，打破启动互锁 |
| HTTP 健康探测 | 原 wrapper DEVICE+SRCIP+MMX_DEFAULT | 明确默认 mark，原设备绑定 | 两出口 hostname 实测均 204；不能经 OC/另一 WAN 假成功 |

依据：mwan3 skeleton 的 OUTPUT 是 type route、priority mangle+1（-149）；认证 candidate/netifd 输出在 -160；fw4 mangle 是 -150。`mwan3-fixed.sh:591` 高位清理、`:610` restore、`:647` OUTPUT、`:1039` per-interface ip rule。`common.sh:165` masked set 与 `:221` vmap setter 保留 mask 外位。`installed-openclash.init:1544` UDP local rule、`:1582` TPROXY、`:1628` full-mark input accept。真实 hook priority 与 rule base 仍由主代理读回。

## 主账号最小 GID pin

使用已存在的专用 `esauth1` / 65201，并让 procd 账号 1 实例的 primary group 为该组。仅修改候选认证所属 OUTPUT 表中的这一条，保留账号 2 规则：

```nft
meta skgid 65201 counter meta mark set meta mark & 0xc0ffffff | 0x3f000000 comment "esurfing account1 main bootstrap"
meta skgid 65202 counter meta mark set 0x02000000 comment "esurfing account2 wan2"
```

链仍为 `type route hook output priority -160; policy accept`。0xc0ffffff 为 ~0x3f000000，第一条仅占用 MWAN mask，保留无关低位；账号 2 当前精确 mark / exact ip rule 契约保持。专用 GID 覆盖账号最早网络检测、HTTP、TLS、后续认证等 socket；旧客户端初次检测时 SO_MARK 回调未就绪，所以只设置 JSON mark 不能替代 GID。

MWAN DEFAULT=0x3f000000，是内建“继续原默认路由”的 sentinel，不是成员编号；它不匹配每成员或 blackhole/unreachable fwmark，最终到 main。MWAN 未运行时也到 main。无需新增 pref1801→main；新增 UID0→main 会把整个路由器所有 root 输出固定，破坏 UA3F/Ninja 平衡。

该方案依赖 main 始终只提供主 WAN 默认路由。如果未来把 wan2 默认放进 main，或给 main 增加自动 fallback，账号 1 可能被换出口；必须同时维护 main 的所有权与当前默认路由。物理线路失联时 main 可返回 unreachable，不能把账号 1 偷送到账号 2。

只 pin DNS 查询的认证 GID 不够：认证可能用本机 resolver，实际公网解析是 dnsmasq/core 新 socket，不继承认证 GID。健康 probe 也有独立 wrapper，而不是认证进程。

## DNS bootstrap 与最小 OUTPUT 规则

主代理提出的 UDP53/TCP53→use_policy default 方向正确。实际配置应生成两条明确规则，避免未经验证地依赖 `proto 'tcp udp'` 解析；先于普通 balance catchall：

```uci
config rule 'dns_boot_udp'
    option family 'ipv4'
    option proto 'udp'
    option dest_port '53'
    option use_policy 'default'

config rule 'dns_boot_tcp'
    option family 'ipv4'
    option proto 'tcp'
    option dest_port '53'
    option use_policy 'default'
```

源码 `mwan3-fixed.sh:1700` 把 use_policy default 渲染成 DEFAULT sentinel，不走成员 online 状态。原规则匹配高位=0；账号 2 的精确 mark 已存在，所以不会被 DNS53 默认规则覆盖。core 公共 UDP53 / TCP fallback、健康预解析和认证 bootstrap 均沿 main。LAN DNS 被 dnsmasq 接收不受影响；OC TPROXY UDP53 早退后，由 core 新建的 DNS 外层 socket 才匹配此规则。

规则 section 名不能超过 15 字符；先前 bootstrap_dns_udp/tcp 分别 17 字符，会被生成器 warn 后跳过。主代理通过实际 NFT 只剩 balanced 发现此遗漏，现示例统一为 dns_boot_udp/tcp（12 字符）。离线快审未捕获此限制，实际渲染读回才发现，因此不能以 UCI 写入或无语法错误代替 NFT 规则存在。部署须确认这两条都先于 balanced 并实际产生 DEFAULTmark。

若要进一步缩小范围，可对所有最终 DNS config 中真实 resolver IP 限定 dest_ip=/32，多 resolver 各生成 UDP/TCP 两条；但需列全校园/default/proxy bootstrap resolver 及变化生命周期。当前公共 DNS list 明确且固定时，按目标列表限制较精确；仅按端口两条是更小、可审阅的初期实现。不要匹配所有 GID65534 输出，因为 core 常用 nogroup，会把国外节点连接也固定。也不要默认豁免所有 TCP80/443，这会取消本机平衡。

此例只解决裸 DNS53。若认证所需 DNS 改为 DoH/DoT，或仍要求失败时走代理 fallback，必须把相应 bootstrap URL/IP/端口另行固定；本次先保持默认 DNS223.5.5.5 /119.29.29.29 及校园实际 resolver 独立于节点。两 WAN 初始 offline 时至少须实测普通未代理 DNS53 成功，否则 balance last_resort unreachable 会阻塞认证/健康域名解析。wrapper 域名目前实测成功，仍保留这条 bootstrap 保护。

## 路由导入 UC 的边界

`mwan3-create-iface-route.fixed.uc` 将 main + globals.rt_table_lookup 列出的表作为来源，再通过 netifd ubus l3_device 映射筛选 default 到对应 member 表。wan2 的 DHCP 默认已在 25202 而不在 main，**globals 必须包含 rt_table_lookup 25202**，否则 MWAN member2 无 default：可 ping/认证，但普通被标记的平衡流会命中 member backstop unreachable。

来源表不要包括 354：其中 local0/0 是 OC 交付，不是 WAN 默认；也不要导入旧 wan3 表或所有表。来源表 25202 中的 unreachable default 允许保留，真实 metric20 默认优先；它只应进入 wan2member 表，不能进入 wan1。当前代码跳过无匹配 l3dev 的 default，会忽略 unreachable 而不是把它变成全局 default；memberdown 保护由 MWAN 的独立 backstop 维持。

接口编号依 UCI interface section 顺序计算，包含 disabled section；假设 wan=1、wan2=2 前要读回，不能从名字推断编号。name_tid 是 enabled 且 family 匹配才映射；目标名称必须是 network interface wan/wan2，与 ubus l3_device 一致。两接口若共享相同 l3_device 会发生后写覆盖；当前 wan 与 eswan2 应是两个不同 l3 设备。

ROUTE_FIELDS 只复制 dst/gateway/oif/prefsrc/priority/scope/type/tos/metrics，未复制 src 除非 source_routing=1。IPv4prefsrc 必须保留当前 DHCPsrc，以免 OUTPUT 初始源为 wan1、重路由至 wan2 而源 IP 未修正；fw4 WAN masquerade 仍须包含两出口。不要把 netifd 所有表路由再交给手工 clear 脚本同时维护。

`rt_table_lookup25202`还会把该表的非 default CIDR 加入 mwan3_custom_v4，并在前/后规则阶段把这些目的地设为 DEFAULT→main。如果校园内部网段只通过 wan2 可达而 main 没有同路由，需从校园业务验收观察；不能因 rt_table_lookup 已配置就声称所有自定义路由都能直达。该表的 DHCP 网段与 main 重叠时，main 直达可能正确，但须读回实际网段。

UC 刷新前由 mwan3_delete_iface_route 清 member 表，然后重新复制；现有脚本不删 stale existing key。完整 reload/ifupdate 须确认先清后复制并读回新 DHCPsrc/gateway；仅单独调用 UC 追加不能证明旧路由被清理。table25202 的 DHCP 与 fallback 仍由 netifd/现有 guard 持有。

## 最后启用 UDP

独立候选 `mwan3-oc-udp.sh` 基于已有两处兼容修补的 `mwan3-fixed.sh`，只增加一条位于高位清理之前的规则：

```nft
add rule inet mwan3 mwan3_prerouting meta nfproto ipv4 meta l4proto udp meta mark & 0xffff == 0x162 counter return comment "OpenClash UDP already TPROXY"
```

应由 mwan3_set_general_nft 的每次 start/reload 原生重建，不能只在当前 NFT 链临时 insert 后当作持久完成。`return`仅退出 MWAN 的 basechain，后续其他表的 hook 仍运行。限定 IPv4UDP+低位 0x162，没有跳过普通 WAN 转发或 UA3F0xc9。fw4OC 在-150 已经全值设 0x162，该规则在-149 保持纯 0x162；stock input 全值 accept、postrouting 全值保护仍匹配。若将 OChook 移到 MWAN 之后，此规则无效，因此须读回顺序。

只加 pref100 maskedroute 并不覆盖 fullinput 风险：0x01000162 可到 354，但 stock `meta mark0x162 accept`不匹配，LANinputACCEPT 可能暂时遮住问题。最小策略是已 TPROXY 包不再被 MWAN 加高位，而不是同时扩大所有 stockinput/postrouting 规则。

现有 production-custom-firewall.sh 增加`pref100 fwmark0x162/0xffff lookup354`且仅 UDP 开时运行；它检查 priority100 是否空闲并避免重复，但不检查 table354 localroute/listenerready，也不在关闭 UDP/stop 时删除自定义 rule。目标验收必须读回下面全部条件：

- OC 为 redir-host，UDP1，router_self_proxy0，disable_udp_quic0；IPv6 保持关闭；无 stockUA3F 透明接管/L3BPF。
- UDP listener 存在；table354 为`local0.0.0.0/0 devlo`及所需 throwLAN/校园段；pref100 精确一条且优先于 MWANiif/memberlookup。
- fw4mangle→OC TPROXY 在-150；MWANPREROUTING 在-149；早退 counter 增加，输入低位纯 0x162。
- mainauthGID 和第二 authmark 保持；DNS53default 规则仍先于 balance；本机 UA3F/Ninja 外层没有低位 0x162。不要把最终 core 所有 outbound routing-mark 设 354，pref100 会把它送回自身。
- 两路 UDP 新流真实走通并有可观察回包；不以 ping、HTTP204、SOCKS1080 或 LAN 普通 DNS53 代替 UDP 代理验证。

实际 LAN 最小矩阵：保持成功的国内/国外 TCP 与校园认证；从同一 LAN 客户端对一个明确规则走 DIRECT 的公网上游 UDP DNS 查询、一个明确选中且声称支持 UDP 的 Ninja 节点路径测试新 UDP DNS/STUN/QUIC；同时读 core 连接 policy、目标、UDP 计数和真实出口包。普通 LAN DNS53 通常被 dnsmasq 专用链处理，不证明 tproxyport 收到了 UDP。Ninja -t 不能证明 UDP 节点支持；若该订阅节点 UDP 失败，不强称 UDP 交付成功。

先在 MWAN 停用或 wan_only 策略下验 OC UDP；再启两路 balance，重复相同新 UDP 矩阵。回包与 mark 稳定、counter 路径清晰才算组合通过。国内 UA3FLocal udp=false，国内 UDP 仍按原策略，不应进 SOCKS；check 国内 DIRECT 与国外 UDP 分别验证。既有 TCP、登录、DNS 任一回退，先关 UDP/恢复上一策略，避免同时重启认证。

有序 rollback：UDP0→完整 OC 防火墙 reload 或有序 restart，精确删除自定义 pref100maskedrule；确认 stockUDP 链、354local route 按生命周期清理、LAN 新 DNS/TCP 继续成功。仅把 UCIUDP 改 0 而不 reload 不是回滚，仍留旧 NFT。maskedrule 无 localroute 会继续后续 lookup，但仍应精确清理，不删所有 iprule。

## TCP 实际双出口与 deterministic numgen 偏置

主代理真实 LAN 连续创建 12 个百度 HTTPS 请求，均 HTTP 200，但抓到 12 条 UA3F 外层连接全部 eswan2。这证明业务可达，没有证明两个出口都承担新连接。两个 tracker online、两个 member 表有默认路由也不能代替实际出口验证。

当前源码多个 member 的同一个 policy 使用 numgen inc mod total_weight。LAN 的原 TCP 在 PREROUTING 被 MWAN 分类一次，之后 OC redirect 并由 UA3F 创建新的外层 OUTPUT，再进入同一个 policy 分类一次；共同计数器每次前进两步，两 member 等权时外层可能总占同一奇偶槽位。主代理已给 127.0.0.0/8 加 bypass_network 避免回环连接额外消耗，但它不能单独消除 LAN 原流 + 外层这两次分类。

主代理独立 `work/deploy/root/production-mwan3.sh` 只将唯一 policy 生成行 `numgen inc mod $_total_fam vmap` 改为 `numgen random mod $_total_fam vmap`。审查直接对比确认是该唯一变更，UDP early return 保留，权重 range、vmap setter 和 ct save / restore 不变。这是合理的最小修复：随机选择避免固定奇偶相关，ct 高位已存在时 restore 跳过新分类，既有连接仍固定同一 WAN。不能删 ct guard 改为逐包 random，否则 TCP / UDP 同一流会换出口。

实际验证抓 UA3F SO_MARK 0xc9 的新外层 TCP：两个设备都出现新的 SYN 和成功回包，国内 / 国外 / 校园原矩阵仍通过。样本必须说明请求数、真实外层连接数和两出口计数；十二个随机样本无需恰好 6:6。core 可能复用或多路复用 Ninja 连接，HTTP 请求数不等于 Ninja 外层连接数。短窗两个出口均有新连接，只支持本机本次负载分配可用，不证明长期比例、连接稳定性或带宽相加。

本审查不修改已定稿 `mwan3-oc-udp.sh`；主代理部署 random 生产副本后应以生产 SHA 和实际 NFT 的 numgen random 为准。回退到旧 inc 不应声称仍实现有效外层分流。

## HTTP204 tracking 候选与目标部署

stock3.6.12-1 支持 ping/arping/httping/nping-*/nslookup。httping_ssl 控制 scheme，具体执行`WRAP httping -c count -t timeout -q http://track_ip`；以退出码判成功，无 expectedstatus/正文参数。缺 httping 会自动 fallbackping。nslookup 方法查询 www.google.com 而不验认证页面，不适合严格 portal 判定。

`mwan3track-curl204.sh`只新增选择 method=curl204 时的分支，已有方法保持；WRAP 从$*改为"$@"，避免 literal*展开和空格参数丢失。curl 调用第一参数-q 禁.curlrc，--noproxy'*'强直连，无-L/--location，exit0 且 code 必须严格等于 204；200portal/302/000/网络失败/额外输出都失败。缺 curl 时停止 curl204tracker 并拒绝 fallbackping；check_quality 自动沿原逻辑关闭，不捏造 latency。

主代理已验证目标 curl 为动态 musl，wrapper 能加载；随后真实使用 FAMILY=ipv4、DEVICE=wan/eswan2、SRCIP=各自地址、FWMARK=0x3f000000、LD_PRELOAD=原 wrapper，两个出口对`http://connectivitycheck.platform.hicloud.com/generate_204`均 204。/etc/resolv.conf 为 127.0.0.1/::1 仍可完成本次 hostname 调用，证据在`work/deploy/mwan-wrapper-real-precheck.json`，本审查未读私密文件。源码 socketwrapper 存在把解析 socket 也绑 WAN 的潜在风险，但当前目标真实结果已排除“必然失败”，不新增预解析/固定 IP。冷启动、未缓存及 DNS53default 启用后的首轮仍需目标观察，不能把源码推断放在实测结论之上。

探测目标在 track_ip 只放 hostname/IP，path 单独放 curl204_path，避免原 TRACK_${track_ip}状态文件路径含 slash。IPv6 仍未启，本次实测不覆盖 IPv6。

最小 UCI 合并文件：`mwan3-curl204-two-wan.uci`，只改已存在 wan/wan2section，initial_state=offline、track_gateway=0、check_quality=0、reliability1、count1、timeout4、interval10、failure/recovery_interval5、down/up3。初次 offline 后的认证/健康逐轮恢复不能承诺固定几秒；还受超时、DNS、调度影响。两出口共用同一探测站时，该站故障会一起 offline；第二独立 204 站点需各出口先实测，不能未经验证加入 reliability1 后“允许任意一个”导致 portal 可达目标假 online。

原 MWANscore 算法仍保留：初始 offline 时 up=3 要求逐次成功累积到 3，失败会回 0；online 时 down=3 从 score6 降到 3，夹杂成功只加 1 而不会直接重置 6。因此 down=3 不是严格“连续 3 次失败”，而是原有积分滞后阈值。本补丁仅改探测成功判定，不修改该状态机；若要求严格连续失败，需另行改动并专门验证。

目标安装：curl204 候选→`/usr/sbin/mwan3track`；UDP 候选→`/lib/mwan3/mwan3.sh`。UC 路由候选继续用现有`mwan3-create-iface-route.fixed.uc`→`/lib/mwan3/mwan3-create-iface-route.uc`。先保存对应原文件及 UCI 恢复副本，核对当前 SHA 与候选基线，sh-n，原子替换并 0755；只有主代理部署。不覆盖新出现的未知补丁。

| 文件 | SHA256 | 用途 |
| --- | --- | --- |
| 已下载 stock mwan3track | 3cf809ea489ec931b29eb5887c24e76409f98d324fdfedade6e5367951de78bc | curl204 源码基线 |
| mwan3track-curl204.sh | 0e8b1431c4c8382cf8f8cd73dff4ac73954a0fc51b8befe02220753e7a7d72c3 | HTTP204 健康方法 |
| 原 mwan3-fixed.sh | d41a0ffcef0775a30ef5b9c0bf6117c133b9466f777debbe96c2e46720278db7 | UDP 补丁基线，保留已有两处修补 |
| mwan3-oc-udp.sh | 49ef7a105bb7572c789d94f9a49f097f3c812b798e6b531bb97f3a982715fdf9 | 只加 UDP early return 的离线候选 |
| root/production-mwan3.sh | e857916d9c414b53a5679d7806243a606e0845f241b1fcde7e8223b7ed2b5246 | 主代理将唯一 numgen inc 改 random 后的生产副本 |

离线已通过 bash-n 及 stub 测试：204 成功，302/200/000/非零 exit/空码/额外输出拒绝，literal'*'保留、-q 禁 curlrc、不 followredirect、count 重试、缺 curl 不 fallback。UDP 渲染验证精确一条且早于高位 clear 和 ctrestore。生成器`prepare-mwan3track-curl204.py`和验证器`verify-mwan3track-curl204.sh`都不访问网络；候选/patch/hash 随文件生成。本代理未运行目标 ash/nft-c；由主代理独占执行。

主代理较新读回已报告：两 WAN wrapper204、trackeronline、member 表 1/2 路由和 LAN200/204 通过。DNSbootstrap 长名称被实际渲染拒绝，主代理正在改短名称并 reload 读回；在两条 DNSDEFAULT 规则存在之前，不声称冷启动 bootstrap 保护完成。UDP 运行验收仍独立待最后启用。

目标部署后先保持 balanceunreachable 且两 route 有效，可用只读`mwan-curl204-first-check.sh`逐 DEVICE+SRCIPwrapper204 验证，再观察各 tracker 由 offline→online 及实际 healthy 目标状态。该脚本不改 UCI/服务、不读账号/订阅、只公开接口名/HTTP 码/exit，源码可直接审阅。受控 HTTP302/200 或无 204 样本必须记 failed，不能用未跟随的 curl exit0 当成功。可用本地 stub 验证目标 shell 分支；不需要真的登出当前稳定认证来造坏样本。最后在已授权维护窗口验证 wan2 认证失效后健康 offline，主认证不换出口；物理线去回同时 down/up 应等待 DHCP、认证与健康恢复，不能声称有独立故障冗余。

回退：先切接口 track_method 回原 ping 及原 track_ip，然后恢复备份 mwan3track 与 UCI 并 reload；原 ping 仅链路可达，不声称认证健康。停止 MWAN 不应删除认证 GID/25202，也不触碰 OC/UA3F 服务。包升级会覆盖补丁，必须重新核 source 基线并复测，不能自动覆盖。

## 不能从现有检查推出的结论

- 负载均衡按新连接选择，不把单个 TCP/QUIC/Ninja 隧道带宽相加。UA3F/Ninja 外层连接由新 socket 决定，OC multiplex 或长 UDP 隧道可能让大量 LAN 业务共用一个 WAN。
- SOURCE 预选 main 再 OUTPUT 重路由可能保留 main 源；须捕获两出口最终 src/SNAT，source/devicebind 会影响可迁移性，iproutegetmark 不能模拟整个 nftOUTPUT。
- HTTP204 只是该指定直连站点可达。运营商 walledgarden 若允许该 204 站点，仍需 ESurfing 已认证状态与独立 HTTPS 业务作补充，不能把 204 单项称账号授权证明。
- 软件 flowoffload 可绕过后续计数/重路由。此 mwan3start 在 flowoffload=1 时会全 conntrackflush，影响现有认证/core 长连接；即使为 0 也会 flush 高位=0 连接，旧 auth/UA3F 低位 0xc9 均可能命中。启动前读取现状并预告真实连接重建影响，不把它归因 DNS。运行中不要频繁 restartMWAN。
- 两稳定会话只证明当前两种终端策略可用；不启 wan3/第三账号、不把旧三账号 persistent 脚本整套恢复。主认证 GID 整合由主代理单独管理，审查代理不编辑 init/共享文件。
