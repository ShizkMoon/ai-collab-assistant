# OC / Ninja DNS 与重定向生命周期审查

范围：只读非 private 生成脚本、stock 0.48.002 init/watchdog、生产 hook 和历史脱敏读回。没有 SSH、读取订阅或修改路由器。主代理已恢复单 WAN；UA3F gateway MAC/BPF 强故障由另一代理验证，本文件不把它归因到 DNS。

## 结论与当前保护

prepare_openclash.py 的新增 DNS 覆写没有引入本机 53/7874 回环：default/nameserver/proxy-server-nameserver 明确用 223.5.5.5、119.29.29.29，校园 policy 用 10.50.11.15、202.96.128.86；国外 fallback 是 1.1.1.1 DoH 经源首策略组。SmartDNS 没进入该生产覆写；其候选单向监听 127.0.0.1:6053 并用真实校园/公共上游，没有指向 dnsmasq 或 OC。

这不证明最终配置无其它回环：生产代码 merge 源 DNS，未清除源 direct-nameserver、proxy-server-nameserver-policy 或其它 nameserver-policy；stock 只去除 system resolver，并不全面拒绝 127.0.0.1:53/7874 等本机地址。最终配置需由主代理私密检查各 DNS 字段所有 resolver，公开只报自回指数量和字段名。上游代理失败会让指定国外 fallback 失败，属于可达性依赖，不是 DNS 端口回环。

当前国内 TCP 强依赖 UA3FLocal。为隔离验收，已在 production-custom-overwrite.sh 加入 options 布尔 enable_ua3f_tcp：缺省 true；false 移除本 hook 生成的 TCP 包装，让原全球直连规则重新匹配。每次先剥离旧包装再重建，支持重复执行/开关切换；UA3FLocal 节点可保留且不被规则调用。原组内当前选择状态不变，不能凭规则名声称一定 DIRECT。options 同步新增默认 true；首次 OC 单独验收明确设 false。

shell -n 已通过，Ruby body 已重新生成。validate-production-switch.rb 提供无凭据 synthetic 验收，覆盖 default true、重复执行、false 恢复、再次重复、重新开启及原节点/组/规则保持；目标 Ruby 实测待主代理完成。

## stock DNS 所有权与故障窗口

enable_redirect_dns=1 的启动流程先启动 core、等待 /group API 成功，然后 change_dnsmasq，再 set_firewall。正常启动不会在 core 未起来前先把 DNS 指过去；但其 readiness 仅证明 PID/API，不验证核心 DNS resolver 成功。

change_dnsmasq 会持久提交 dhcp：清 UCI server、只加 127.0.0.1#7874、删除 resolvfile、noresolv=1、缓存改 0。LAN :53 的 adblock include 仍保留；未命中广告全部依赖 core :7874。主 WAN重载、认证尚未恢复、core异常死亡或反复respawn时，dnsmasq不自动切回公共 upstream。

有序 OC stop 先移除透明规则，停止core，再 revert_dnsmasq恢复先前server/noresolv/resolvfile/cache并重启dnsmasq。若进程被强制杀死/系统断电，清理不一定执行；下次启动dnsmasq可能仍加载持久127.0.0.1#7874而core暂未启动。watchdog约每60秒检查，respawn耗尽会有序stop，但不能给出持续可用DNS承诺。

watchdog 还会强制恢复唯一OC upstream：若 UCI server不是只有核心地址，会清列表重新设置127.0.0.1#7874。因此不要运行中靠给dnsmasq追加公共fallback实现容错；它会被watchdog重置，也会改变代理DNS语义。WAN/firewall reload 的 check_core_status 无 start 参数，仅重建firewall，不调用change_dnsmasq；不同组件修改DNS时可能短暂分叉。

紧急恢复须先disable/stop OC，确认watchdog已退出，再设置dnsmasq明确可达的主WAN上游；否则旧watchdog会改回来。主代理现有emergency_recover.py有先OC stop再写202.96.128.86/223.5.5.5、noresolv=1的顺序，方向正确。读回运行配置与真实LAN查询仍必需。

## 重定向回环与路由边界

redir-host + router_self_proxy=0 时，stock 不建本机TCP/UDP透明输出或本机DNSHijack；LAN DNS 53→本机dnsmasq53，dnsmasq用本机socket到OC7874，OC resolver到公网/校园DNS，均不再走LAN透明入口。UA3F/Ninja新建的本机外层socket同样不应回到OC。这一配置可避免新引入代理套回本机SOCKS的循环；仍要核当前NFT是否残留旧selfproxy/fake-IP规则。

masked pref100/0xffff规则依赖stocktable354 local route；stop不删masked规则。主WAN恢复应精确移除该自定义rule或确认table354无路由；不能删所有ip rule。更大风险来自MWAN之后restore是否清低位、全markinput/postrouting规则与高位mark，独立于DNS。首次OC验收先UDP代理0、MWAN停用，确认TCP透明后再单独验UDP。

历史oc-first-acceptance.json的当次mixed返回407/NinjaHTTP000，且NFT含198.18/16fake-IP规则；不能把这一旧文件作为后来的redir-host成功证明。dns-filter-check.json当次doubleclick.net正解析，说明那个样本未证广告过滤成功。主代理较新204与恢复读回可作后续证据，但必须加LAN来源验收。

## 最小稳定启动顺序

1. 保持OC/UA3F/MWAN/SmartDNS自动启动关闭，恢复单WAN租约、默认路由、校园认证与主WANDNS。保持dnsmasq唯一LAN53/DHCP，公共/校园上游不依赖代理；先证LAN客户端IP直达、DNS及HTTPS，不能仅router curl。
2. 先验证adblock本地include：非广告正常、已在实际名单的广告域名NXDOMAIN；广告查询到此结束且不触发上游。adblock暂不能通过时保持直连DNS可用，单独排查规则加载，不联动重启认证。
3. OC单独阶段设置enable_ua3f_tcp=false、UDP代理0、router_self_proxy0、redir-host、DNSforward1、MWAN停用。私密最终配置/-t/许可检查通过，主WAN认证已成功再启OC。先测core7874的国内/校园/国外解析，再测dnsmasq53→core，再测真实LAN透明TCP国内/国外；国内原组选择读回DIRECT。启动返回并非全部ready，等后台check_core_status与实际DNS完成。
4. 只有UA3F socks_only启动且所有L3/BPF/TTL改写为0，127.0.0.1:1080通过真实HTTP/HTTPS出站后，才把开关设true，强制完整生成并测LAN国内TCP；Ninja国外流量与校园认证应仍成功。UA3F停止前先将开关false或有序停OC。
5. UDP透明、本机DNS路由、MWAN分别后加；每加一层重复LAN关键流量并读回mark/local route。不要同时network reload、认证切换、DNS切换和代理重启。冷启动与受控WAN重连最后验，START=99本身不证明认证已ready。

## LAN验收矩阵与停止验收

在实际LAN客户端完成：网关可达；无需DNS的公网IP连接；国内域名DNS+HTTPS；国外域名DNS+HTTPS；校园认证域名/校内业务；已在blocklist域名NXDOMAIN；Ninja选择/UA3F开关与实际目标路径对应；每个关键项连续多次新连接成功。明确客户端IP/接口、解析server、HTTP码与时间，不记录凭据。IP成功而DNS失败先查53/7874/upstream；IP也失败先查WAN租约/认证/ARP/route/BPF，避免把所有断网都归DNS。

有序stop后必须确认：core与watchdog不再运行；DNS运行配置没有127.0.0.1#7874；dnsmasq53有明确可达上游；OC redirect/mangle/output规则已移除；自定义pref100规则已处理；LAN新DNS+新HTTPS请求成功。受控断开core验故障恢复时在维护窗口进行，不把它当正常健康检查。现阶段保留用户已恢复的直连稳态，不自动重新开启全部集成。

Connector授权URL由主代理已私密写入UCI，尚无scheduler；本次不改此状态，也不启用自动下载/内核安装。
