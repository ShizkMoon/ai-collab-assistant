# ESurfing v2.1.5-r6 多出口边界

本文件记录固定源码 `cc181fdef686a1e31628f1ae3d8ec97fe6e5ad09` 的行为及部署 workaround。客户端认证结果必须由主代理的设备验收单独证明。

## 清洁启动的初次网络检测缺少 SO_MARK

1. [States.c:33](https://github.com/BadGhost520/ESurfingClient-CVersion/blob/cc181fdef686a1e31628f1ae3d8ec97fe6e5ad09/esurfingclient/app/src/states/States.c#L33) 将 `_Thread_local int8_t tl_thread_idx` 初始化为 `-1`。
2. [DialerAuth.c:272](https://github.com/BadGhost520/ESurfingClient-CVersion/blob/cc181fdef686a1e31628f1ae3d8ec97fe6e5ad09/esurfingclient/app/src/clients/dialer/DialerAuth.c#L272) 在 `work_auth()` 中先执行 `wait_need_auth()`，随后才执行 `dialer_app(0)`。
3. [DialerNet.c:253](https://github.com/BadGhost520/ESurfingClient-CVersion/blob/cc181fdef686a1e31628f1ae3d8ec97fe6e5ad09/esurfingclient/app/src/clients/dialer/DialerNet.c#L253) 的等待循环调用 `check_network_status(true)`，后者调用 GET。
4. [NetClient.c:216](https://github.com/BadGhost520/ESurfingClient-CVersion/blob/cc181fdef686a1e31628f1ae3d8ec97fe6e5ad09/esurfingclient/app/src/clients/net/NetClient.c#L216) 仅在 `tl_thread_idx > -1` 时安装 OpenWrt `open_socket_callback`，因此该阶段不会应用账号的 `SO_MARK`。
5. [DialerClient.c:155](https://github.com/BadGhost520/ESurfingClient-CVersion/blob/cc181fdef686a1e31628f1ae3d8ec97fe6e5ad09/esurfingclient/app/src/clients/dialer/DialerClient.c#L155) 到 `dialer_app()` 才将下标设成 0。`logout_previous_session()` 也会设 0，但只在成功加载旧 `.logout` 存档时到达该语句；无存档的清洁启动没有这条补偿路径。

如果主 WAN 已认证，初次检测可能沿 main 表看到主 WAN 的互联网，候选进程就等待而不发起自身认证。进程存在及 `INTERNET_ALREADY_REACHABLE` 均不能证明候选 WAN 已认证。

本次最小部署方案是保留 root UID，为每个 auth 进程指定独占 GID，再用 `type route hook output priority -160` 的 `meta skgid` 规则设置对应高位 mark。固定 mark 使用独立表及不可达默认；候选源地址在 fw4 WAN zone masquerade 后应成为该 macvlan 的地址。主代理已报告 WAN2 的 GID pin 后得到 AUTH_SUCCESS 与 HEARTBEAT_SUCCESS，且原 WAN 保持可达；这些是运行时证据，不能外推为长期稳定或聚合带宽。

另一条源码修复是让单账号 auth 角色在首次网络请求前就将 `tl_thread_idx=0`；本次没有重编二进制。mwan3 的 LD_PRELOAD wrapper 可拦截动态程序 socket，但设备上的 ESurfing 二进制由主代理验证为静态，不能用该机制补救。

## 多个 Linux 身份与重认证

[Refresh.c](https://github.com/BadGhost520/ESurfingClient-CVersion/blob/cc181fdef686a1e31628f1ae3d8ec97fe6e5ad09/esurfingclient/app/src/states/Refresh.c) 为各实例生成协议 hostname、client_id 和 MAC；[BytesUtil.c:178](https://github.com/BadGhost520/ESurfingClient-CVersion/blob/cc181fdef686a1e31628f1ae3d8ec97fe6e5ad09/esurfingclient/app/src/utils/BytesUtil.c#L178) 在 Linux 直接从 `/dev/urandom` 读取，没有按启动秒数 `srand(time)`。代码没有检查随机 read 的完整长度，这是一个边界；正常运行时不能仅因同时启动就推断身份重复。

仅 channel `2` 是 Linux `CCTP/Linux64/1003`，没有第二个 Linux 子通道。channel 3／4／5 分别是 Android／iOS／macOS 身份；改成这些不能称为“另一个 Linux 通道”。本地没有拒绝两个 Linux account 的逻辑，服务端是否允许同账号两个该身份同时在线，须通过实际会话和逐源外网验证。

`AUTH_REQUIRED` 只是 [CheckNetwork.c](https://github.com/BadGhost520/ESurfingClient-CVersion/blob/cc181fdef686a1e31628f1ae3d8ec97fe6e5ad09/esurfingclient/app/src/clients/net/CheckNetwork.c) 收到检测请求 HTTP 302 后进入 `DialerClient.c:104` 的结果，不是本地识别出的“被另一会话挤掉”。应比较两路连续外网探针、认证和心跳的时间关系。交替认证同时伴随另一源实际失网，才加强互斥会话的解释；检测 URL 302 但其他外网持续可达时，需继续检查检测判据。

`compare-sessions.uc` 可在路由器内部比较 `.2.logout` 与 `.3.logout` 的身份字段，只回传是否相等与是否非空；不要读取或导出整个存档。INFO 日志可能仍包含 ticket／会话 URL；DEBUG 含密码 XML，不能为诊断重复身份而开启。

## procd respawn 输入与输出格式不同

[procd instance.c](https://github.com/openwrt/procd/blob/master/service/instance.c) 的 `respawn` 输入 schema 是数组，解析逐项调用 `atoi(blobmsg_get_string())`，因此直接 ubus 输入应为 `["60","5","5"]`。数字数组 `[60,5,5]` 不符合这个字符串输入约定，service list 可能显示零值。service list 返回 `{threshold,timeout,retry}` 对象是输出格式，不能直接作为输入。原包 `procd_set_param respawn 60 5 5` 会生成字符串数组，应继续沿用。
