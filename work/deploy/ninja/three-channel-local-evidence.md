# 三通道历史证据复核

## 当前能得出的结论

现有本地记录不能证明学校实行“一台 PC＋一台手机”的两类上限，也不能证明第三认证绝对不可行。第三 Linux、macOS、iOS、Windows 均取得过认证成功与首个心跳；Linux 和 iOS 阶段还有三个绑定源地址同时取得 HTTPS 200 的短时记录。准确结论是：本次候选没有取得可保持的三路共存证据，生产保留已经持续保活的两路。

第三路没有被简单地因进程 offline 否定；有重复 HTTP 302 后重新 AUTH 的记录，iOS／Windows 阶段还伴随主 Android 重新 AUTH。但早期确有本地路由、启动标记与服务生命周期混淆，且后期没有服务端踢线理由或逐包证据。现象可以支持继续验证会话互斥，不能直接确定学校的分类规则。

本报告只复核本地文件，没有 SSH、认证、测速或修改运行配置。时间为 2026 年 10 月 12 日北京时间。JSON 文件修改时间仅用来确定取证顺序；认证时间以脱敏日志事件为准。`account=1/2/3` 是本机数组下标，三份旧配置的用户名相同；没有输出用户名、密码、票据、会话 URL、client_id 或存档内容。

## 时间顺序和各候选

| 时段 | 候选身份与认证／心跳 | 绑定出口请求 | 既有会话变化与当时路由 | 证据 |
| --- | --- | --- | --- | --- |
| 15:37～15:49，第三路之前 | 原主路为 Android 3，第二路 Linux 2。15:45～15:46 第二实例只报告已联网，没有 AUTH／心跳 | 15:45 普通绑定源探测第二路 HTTPS 超时、HTTP 检测 302；15:49 pin 后两路均 HTTPS 200／HTTP 204 | 清洁启动初次检测漏 SO_MARK 是已识别的客户端路径。GID pin 修复后才可把第二路自身认证与主路可达区分 | `wan2-auth-events.json`、`auth-probes2.json`、`auth-probes2-pinned.json`、`esurfing/SOURCE-BUGS.md` |
| 15:51，第三 Linux 2 初次启动 | 第三路 AUTH 15:51:26，首心跳 15:51:32 | `wan3-auth-validation` 取得 HTTPS 200 | `eswan3` 有独立 DHCP 源地址；临时 table 25203、账号 mark `0x03000000`、GID 65203 和源规则已准备。最初 procd respawn 输入使用对象格式，后续统一服务才采用正确数组 | `wan3-start.json`、`wan3-auth-validation.json`、`root/start_wan3.py` |
| 15:56～16:00，统一三实例 Linux 2 | 15:56 三路均重新 AUTH 并有首心跳；第二 Linux 15:57:05／15:58:03／15:59:04 再 AUTH；第三 Linux 15:57:15／15:58:08 再 AUTH | 五轮绑定固定源探测：第二路首轮 000，其他 14 次均 200；第 2～5 轮三个源同时可达 | 15:56 的三路重启是持久接管脚本主动执行，不能算被踢线。此后的约一分钟重新 AUTH 是实际现象，但记录尚未锁定原因；同时有 DNS／广告列表下载失败及 reload | `persistent-auth-status1.json`、`three-auth-stability.json`、`auth-block-followup.json`、`root/persist_auth.py` |
| 16:00～16:03，第三改 macOS 5 | 旧配置第三 channel=2，切换脚本改为 5。第三 AUTH 16:02:08／16:03:11，首心跳 16:02:13／16:03:16；第二 Linux AUTH 16:02:04／16:03:04，均有首心跳 | 本轮 compare 文件没有独立绑定 HTTPS 结果 | 切换脚本只 delete 原服务 account3、再用 service add 合并 account3；不是 service set 覆盖另两实例。第二／第三约一分钟再 AUTH，但当时仍使用手写路由生命周期 | `auth-macos-compare1.json`、`root/change_third_channel.py`、旧配置仅作 channel 读回 |
| 16:05～16:10，macOS 阶段的本地路由故障与修复 | 修复后第二 AUTH 16:08:12／16:09:10，第三 16:09:07；两者均有首心跳。记录宣告下一心跳 250 秒，但不到 250 秒已再次 AUTH | 16:07 第二绑定源的三项请求均 curl 7，耗时约 8～63 ms；主源为 200／204／200 | `oc-auth-routing-diagnose` 的两张认证表只剩 unreachable default；这是明确本地路由缺失，不能归为学校限制。16:08 `auth-route-repair` 补回主／第二真实 default 和 link route；没有同一份诊断证明第三表也缺路由。16:08～16:10 又有 PID 变化，故需区分部署恢复和会话失效 | `main-three-routes.json`、`oc-auth-routing-diagnose.json`、`auth-probes-afteroc.json`、`auth-route-repair.json`、`auth-after-route-repair.json`、`auth-keep-times.json` |
| 16:35～16:56，两路重新建立的对照 | 主 Android AUTH 16:35:42，心跳 16:35:50／16:50:00，间隔 850 秒；第二 Linux AUTH 16:49:20，心跳 16:49:26／16:53:37，间隔 250 秒 | 第二候选的 mark route get 指向 eswan2，主普通 route get 指向 wan | 主账号恢复为空 mark、main 路由；第二由独立 candidate 服务持有，mark/source/oif 规则指向 25202。旧 persistent 生命周期已撤，尚未采用后来 netifd 持久接管 | `second-restage-routes.json`、`two-session-auth-events-1.json`、`two-session-auth-events-2.json`、`root/recover_primary.py`、`root/stage_second_again.py` |
| 16:57～16:58，第三 iOS 4 | AUTH 16:57:06，首心跳 16:57:11；再次 AUTH 16:58:05，首心跳 16:58:10。服务端返回下次心跳间隔 10750 秒 | 95.6 秒内七轮：三个绑定源共 21 次 HTTPS 请求全部 200；个别请求约 1.1 秒 | 新候选服务与原两路独立。mark 25203、源地址规则、oif 规则及 GID pin 已显式创建；route get 读回第三 eswan3 与主 wan 各自源地址。第三首次 AUTH 后约 6 秒主路收到重新 AUTH 检测，主 AUTH 16:57:20；第二轮第三 AUTH 16:58:05 后主 AUTH 16:58:09。第二 Linux 16:57:47 正常心跳。证明短时可达与重新 AUTH 同时发生，不证明业务一直断线或踢线分类 | `third-ios-routes.json`、`three-ios-initial-auth.json`、`three-ios-observation.json`、`root/stage_third_ios.py`、`root/monitor_three.py` |
| 16:58:56，停止 iOS／换身份间隙 | 第三多次 curl 7、connect／total 均为 0.000 | 无有效请求 | `third-ios-stopped.json` 与这组错误同一取证时刻；候选被主动停止或接口改变时的错误不能算 Windows 或服务端拒绝证据 | `third-ios-stopped.json`、`third-windows-auth.json` |
| 16:59～17:02，第三 Windows 1 | route 取证约 16:59:43；第三 AUTH 16:59:44，首心跳 16:59:49，间隔 10750 秒；再次 AUTH 17:00:19／17:01:13，17:00:24 有首心跳 | 提供的 Windows 文件没有单独三路 HTTPS 探测序列；不要把前一 iOS 文件的七轮 200移作 Windows 结果 | mark route get 指向新 eswan3 源地址，主普通 route get 保持 wan。主 Android AUTH 17:00:13／17:01:09；第二 Linux 17:01:58 正常心跳。候选 procd incarnation=22 提示已发生多次实例重建，文件没有列出逐次原因。17:02 主动停止候选 | `third-channel1-routes.json`、`third-windows-auth.json`、`third-final-comparison.json`、`third-windows-stopped.json`、`steady-auth.json` |
| 17:22 以后，原生路由正式接管 | 第二 Linux AUTH 17:22:25，首心跳 17:22:32；当前两路后来取得多轮正常保活 | 当轮 WAN1／WAN2 独立 204 | netifd 原生管理 25202、第三停用。第三各身份都没有在这一修复后的正式生命周期中再验收 | `two-native-routes-acceptance.json`、`esurfing/NETIFD-DEPLOYMENT.md` |

## 不能混为一谈的证据

1. **认证成功不是从未成功。** 第三四种身份均实际完成过 AUTH 和首心跳；不是只看三个 PID 或第三 offline。Linux／iOS 还取得短时三源互联网成功。
2. **HTTP 302 后 AUTH 不是服务器踢线理由。** `keepalive-status.awk` 将固定 `DialerClient.c:104` 记为 `AUTH_REQUIRED_HTTP302`。它来自联网检测判据，没有服务端“超过 PC／手机数量”的原因码。iOS 七轮 HTTPS 均 200 时仍重新 AUTH，说明检测状态与实际 HTTPS 可达须分别记录。
3. **早期确有源地址／mark 混淆。** 第二实例 15:45 只见已有通路；固定源码的首次检测漏 SO_MARK，GID pin 是必要修复。第三启动脚本已设 GID pin，不能把这个缺陷自动套给所有第三失败。source-bound curl 仍须有对应 source/oif rule；后期 stage 脚本补齐这些规则，并保留 unreachable 兜底。
4. **16:07 的即时 connect failure 有本地根因证据。** 两张认证表只剩 guard，curl 7 在几十毫秒内退出，随后补回路由。不能把该段“无法连接”当作账号上限。这之后再次 AUTH 仍存在，但不代表所有先前失败都由路由造成。
5. **不能把主代理主动重启和 respawn 当作会话互踢。** 15:56 统一接管主动停止三个旧实例；macOS 切换只操作 account3 并用 service add；后期 iOS／Windows用独立候选 service。未找到这些已读脚本用全局 killall 反复杀认证来维持在线，但事件摘要未逐次保留 PID 与退出原因，incarnation=22 不能单独归因于学校。
6. **早期 `.logout` 身份不是完全重复。** `auth-session-compare.json` 显示 Linux 2／3 的 client_id、协议 MAC、hostname、client_ip 四项均不相同，只证明这些字段不同，不代表服务器一定将它们作为独立设备槽位。改 channel 后没有逐次独立存档对照。
7. **日志是累计摘要，不能把 iOS 的事件算给 Windows。** `third-windows-auth.json` 含 16:57 iOS 事件和 16:58:56 停止间隙错误；只有 Windows stage 之后的 16:59:44 等事件属于该候选阶段。摘要大多没有 PID 过滤，必须保留这一限制。
8. **没有等到 iOS／Windows 的完整心跳周期。** 10750 秒约为 2 小时 59 分 10 秒；两种第三候选的观察只有约 1～2 分钟，虽然首心跳已成功，但没完成下一次完整周期。Linux／macOS 声明 250 秒却频繁重新 AUTH，也缺乏三路都跨过主路 850 秒及各自完整周期的记录。因此“不稳定样本”成立，“长期三路必定不行”不成立。
9. **DNS 和检测请求没有完全消除混淆。** 早期有 DNS／广告组件变更；后期监测为域名 HTTPS，没有固定目的 IP，认证联网检测还使用自身 HTTP 判据。route get 到公共 IP是路由准备证据，不等于每个认证／检测／DNS socket 的线上出口抓包。既有两路后来稳定是有用对照，但不能替代对第三认证请求的逐源验证。

## 对“一台 PC＋一台手机”的判断

channel 是 ESurfing 认证协议身份，1／2／3／4／5 分别对应 Windows／Linux／Android／iOS／macOS，不是路由器真实运行操作系统。当前两路刚好采用 Android＋Linux并不能反推学校按这两类各保留一个。另一个 Linux出现约一分钟重新 AUTH 可以符合“同类互斥”假说；iOS后主 Android重新 AUTH 也可以符合“手机同类”假说。但 Windows第三身份时主 Android同样频繁重新 AUTH，而第二 Linux继续正常心跳，现有记录不符合一个无需其他条件的简单 PC／手机归类规则。

还可能是总会话数、账号或套餐策略、协议字段、过期旧会话、联网检测判据、客户端生命周期或上游 IP／MAC 状态。此处列出的是待区分解释，没有任何一项已确认。没有学校当前账号策略、在线设备列表或明确踢线原因，无法把现象升级为学校硬上限。

## 哪一种复试才有新增价值

值得复试的条件是使用当前已修复、经过两路运行验收的 netifd 路由与恢复生命周期，先完成第三账号的隔离与回退准备，才启动单个第三身份。现有第三 trial 都早于 17:22 原生路由验收，简单重复旧脚本缺少区分价值。

若目标专门是辨别 PC／手机分类，先分别做两路替换对照：Android＋Windows 与 Linux＋iOS，两路数量不增加；确认每种身份独自可认证并跨过完整心跳周期。替换会主动影响现有会话，应由主代理按用户授权安排，不能在本次只读审计中执行。随后只选一个已确认单路有效的第三候选加入，记录各 current PID 与协议身份，不在候选运行时重载其他服务或改变 DNS。

每次需要同时记录三项：实际请求的设备／源地址／SO_MARK 与当前 DHCP 租约一致；多个固定公共源和原联网检测源的结果分别记录（HTTP 302、预期 204、HTTPS 可达与内容不混淆）；原两路 AUTH／心跳和服务退出／重新拉起原因。失败时先证实该路仍有正确 default、不是即时本地 curl 7或DNS解析失败；“检测302而HTTPS持续成功”应单列，不能立即当成断网。

跨过主路 850 秒、第二路 250 秒及候选实际返回周期，才有完整保活依据。iOS／Windows若仍返回 10750 秒，须安排约 3 小时观察；不能强行改小服务端间隔或靠反复重登录制造通过。原两路受影响时停止候选并读回恢复，可以支持安全生产取舍，但其早停结果不代替长期政策证明。只有稳定复现的加入／退出对照、真实业务出口证据与服务器策略／原因，才能进一步判断两类上限；单次短期共存也不能证明第三份独立带宽。

## 已读文件范围

重点为父代理指定的 `wan3-auth-validation`、`three-auth-stability`、`auth-macos-compare1`、`third-channel1-routes`、`third-final-comparison`、`third-ios-routes`、`three-ios-initial-auth`、`three-ios-observation`、`third-windows-auth/stopped`、`auth-session-compare`。补读相关脱敏 JSON、`root/start_wan3.py`、`persist_auth.py`、`change_third_channel.py`、`recover_primary.py`、`stage_second_again.py`、`stage_third_ios.py`、`monitor_three.py`、`three-auth-stability.sh`，以及 `esurfing/SOURCE-BUGS.md`、旧持久和 netifd 文档与提取 awk。必要旧私有配置只输出 channel／mark 与用户名相等布尔值。两份已留存私有 auth 日志不覆盖 15:50～17:03 的第三候选窗口，没有将其当作这一时段的证据。
