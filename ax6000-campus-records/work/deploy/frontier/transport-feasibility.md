# Ninja 链路的 MPTCP、BBR 与 AccECN 可行性

本报告只判断可行性，没有修改路由器、进程环境、内核、节点、账号或服务器。现场基线由主代理本轮读回：RB06 stock，OpenWrt SNAPSHOT `r37185-f29dfe25ba`，Linux `6.18.55`；可选 TCP 拥塞控制为 `reno cubic`，当前为 `cubic`；`tcp_ecn=2`，`net.mptcp.enabled=1`。两个 DHCP 出口共用一个物理 WAN，Ninja 核心为 `ab32ad2d`，固定香港 02，保留 UA3F。基线不能证明任何实际连接已协商 MPTCP、ECN 或 AccECN。

当前有意义的判断是：**不把 OpenMPTCProuter 引入现有路由架构；不为 BBR／BBRv3 换内核；MPTCP 先查实际拨号进程和远端握手；AccECN 可作为一个可恢复的短时兼容性试验候选，但没有提速证据。** 这些技术均不要求替换 Ninja 协议；是否能在现有二进制中启用，需要分别核实。

| 选项 | 仅在本机开启是否足够 | 当前成立的条件与缺口 | 本轮判断 |
| --- | --- | --- | --- |
| MPTCP 内核开关 | 不够 | 应用须创建 MPTCP socket，对端须支持 MP_CAPABLE；多路径还须建立 MP_JOIN 子流并分别选中两个出口 | 先验证 socket 和对端；没有成功握手就停止 |
| OpenMPTCProuter | 不够 | 官方方案以路由端和远端 VPS 聚合端配对部署，会引入新的隧道、服务端和路由责任 | 当前授权与现有架构内不引入 |
| BBR | 不够 | 当前可选列表中没有 BBR；是否存在兼容但未加载的模块未查证 | 不安装、不换内核；不能用 sysctl 凭空启用 |
| BBRv3 | 不够 | Google 的 v3 实现需要相应内核实现；Linux 版本号不能证明已包含该实现 | 当前不作为落地项 |
| AccECN | 可以发起协商，不能保证收益 | `tcp_ecn=3` 可主动请求 AccECN；远端、路径与反馈须兼容，并需实际 CE 标记或相关拥塞证据 | 允许设计单变量短试验；没有理由直接持久化 |

## MPTCP 必须作用于真正经过校园网的 socket

Linux 的 `net.mptcp.enabled=1` 允许应用使用 MPTCP，并不会把普通 TCP 自动转换为 MPTCP。应用使用 `IPPROTO_MPTCP` 创建 socket，远端接受 MP_CAPABLE，才能建立 MPTCP 连接；普通 TCP 回退能保证连接继续使用，也容易掩盖“开了参数但没有启用”的结果。多路径另需 path manager、endpoint 与子流限制配置。应先证明一条连接确实协商成功，再讨论第二条路径。[MPTCP 官方设置说明](https://www.mptcp.dev/setup.html)、[path manager 说明](https://www.mptcp.dev/pm.html)、[RFC 8684](https://www.rfc-editor.org/rfc/rfc8684.html)

应区分 PC 到路由器、本机回环代理、路由器到香港节点、UA3F 的 DIRECT 出口。若 UA3F 只覆盖 DIRECT 分支，其 MPTCP 设置影响它拨向网站的连接，不会自动改变 Ninja 自己拨向香港节点的连接。在路由器本地代理之间启用 MPTCP，也不能聚合校园网出口。**以创建最终外发 socket 的进程、目的地址和连接为验收对象。** 本报告没有从“同时运行 Ninja 和 UA3F”推断全部代理流量经过 UA3F。

公开源码提供两条可能的入口，但不能代替现场二进制核验：

- UA3F `v3.7.0` 的 `go.mod` 指定 Go `1.23.0`。Linux `base.Connect()` 创建 `net.Dialer`，设置 `SO_MARK` 后调用 `Dial("tcp", addr)`，未显式调用 `SetMultipathTCP`。Go 文档提供 `GODEBUG=multipathtcp=1` 的默认拨号 opt-in；Go 1.24 文档还区分 listen 和 dial 的数值。实际行为须核对二进制 Go 版本、构建兼容默认值、已有环境及连接是否回退。此入口不要求修改 UA3F 源码，却仍需改变进程环境和重启，故本轮没有执行。[UA3F go.mod](https://github.com/SunBK201/UA3F/blob/v3.7.0/go.mod)、[Linux 拨号源码](https://github.com/SunBK201/UA3F/blob/v3.7.0/internal/server/base/tcp_linux.go)、[Go GODEBUG](https://go.dev/doc/godebug)、[Go Dialer](https://go.dev/src/net/dial.go)
- 上游 mihomo 提供节点 `mptcp` 选项，并在拨号中调用 `SetMultipathTCP(opt.mpTcp)`。显式布尔值会覆盖 Go 环境默认值；因此，单独添加 `GODEBUG` 不能保证 Ninja 外层 socket 使用 MPTCP。Ninja 是定制核心，当前版本是否保留这个选项、订阅生成器是否传递它、实际远端是否支持，均未验证。不能直接套用上游配置宣称可用。[mihomo 节点文档](https://github.com/MetaCubeX/Meta-Docs/blob/main/docs/config/proxies/index.md)、[dialer 源码](https://github.com/MetaCubeX/mihomo/blob/Meta/component/dialer/dialer.go)、[显式设置实现](https://github.com/MetaCubeX/mihomo/blob/Meta/component/mptcp/mptcp_go121.go)

没有 VPS 不等于 MPTCP 一定不可用：如果现有香港节点接受相应外层连接的 MPTCP，就可能直接使用。反过来，本机单方面启用而节点不支持，只会回退到普通 TCP，不能聚合。`mptcpize` 是 libc 包装路线，官方说明它不适用于 Go 应用，不能把它当作 Ninja／UA3F 的通用补丁。[MPTCP 应用说明](https://www.mptcp.dev/setup.html)

两个出口共用物理 WAN，不提供两条独立物理链路。即使建成两个子流，也仍共享网口、AP、校园上联和可能的公共队列。若学校分别限制两账号，而公共链路仍有余量，存在利用剩余账号配额的可能；这是条件推断，尚无 MPTCP 实测。MPTCP 标准允许路径并不完全独立，因此同一物理接口不是协议禁用条件，却也不能证明速率会相加。现有 mwan3／自定义 mark 必须让子流分别使用对应源地址和策略表，不能只添加 endpoint 然后假设绑定成功。[RFC 8684 路径说明](https://www.rfc-editor.org/rfc/rfc8684.html#section-1.1)

OpenMPTCProuter 官方方案需要远端 VPS 配合聚合、隧道及路由。它不是在现有 mwan3 中开启一个选项；采购 VPS、部署远端或迁移整套固件均超出本轮只读可行性分析。本报告不把它列为当前可直接执行的优化。[OpenMPTCProuter 官方文档](https://github.com/Ysurac/openmptcprouter/wiki)

## BBR 与 BBRv3 的收益位置

`tcp_congestion_control` 控制本机 TCP 发送行为。更改它不会改变香港节点作为下载发送端所用的拥塞控制，也不会改变仅由路由器转发的 PC TCP。Ninja／UA3F 在路由器终止或重建 TCP 时，本机发送的上传或代理 LAN 侧发送可能受影响；这些位置必须和目标下载瓶颈分开核验。[Linux TCP 参数说明](https://github.com/torvalds/linux/blob/v6.18/Documentation/networking/ip-sysctl.rst)

当前 `reno cubic` 列表证明 BBR 尚不可选，不能证明磁盘上一定没有兼容的未加载模块。本轮没有查模块、加载模块或重编内核。BBRv3 是具体内核实现，不由 `6.18.55` 版本号自动成立；Google v3 项目提供相应实现与构建说明。若日后确有本机发送端拥塞瓶颈，再核对本机可用模块、内核 ABI、实现版本与回退；当前不能承诺安装后超过 700 Mbps。[Google BBR v3 源码与说明](https://github.com/google/bbr/blob/v3/README.md)

## AccECN 可以协商，不能替代队列与拥塞控制

Linux 6.18 TCP 文档中，`tcp_ecn=2` 是入站允许经典 ECN、出站不主动请求；`3` 是入站与出站均支持并主动请求 AccECN；`4` 是入站 AccECN、出站经典 ECN；`5` 是入站 AccECN、出站不请求 ECN。实际内核 6.18.55 的 `tcp_ecn_send_syn()` 只有值为 `3` 或拥塞控制要求 AccECN 时，才主动使用 AccECN 握手。路由 `features ecn` 可以要求经典 ECN，不能把 `tcp_ecn=2` 的连接变成 AccECN。[Linux 6.18 参数定义](https://github.com/torvalds/linux/blob/v6.18/Documentation/networking/ip-sysctl.rst)、[6.18.55 握手实现](https://github.com/gregkh/linux/blob/v6.18.55/include/net/tcp_ecn.h)

因此没有“只给两个 WAN 路由加 ecn，其他不动”就启用 AccECN 的等价方案。`tcp_ecn=3` 影响新建本机 TCP 的协商，不能声称只影响 Ninja 某一连接。是否协商成功需要查看真实 SYN／SYN-ACK 或 socket 状态；旧连接和普通回退成功均不能作为验收。

AccECN 增加拥塞标记反馈的精度；它不自动创建 AQM，也不自动采用 L4S／Prague 拥塞控制。当前 CUBIC 的拥塞响应仍是经典逻辑。没有证明路径产生 CE 标记、反馈完整保留，或现有队列造成相关瓶颈时，AccECN 不能凭空提高可用带宽。若 Ninja 外层未协商该反馈，内层应用的 ECN 也不能证明加密隧道外层具备同样行为。[RFC 9768：AccECN](https://www.rfc-editor.org/rfc/rfc9768.html)、[RFC 9330：L4S 架构](https://www.rfc-editor.org/rfc/rfc9330.html)、[6.18.55 TCP 接收处理](https://github.com/gregkh/linux/blob/v6.18.55/net/ipv4/tcp_input.c)、[6.18.55 CUBIC](https://github.com/gregkh/linux/blob/v6.18.55/net/ipv4/tcp_cubic.c)

## 最小验证与停止条件

以下是后续候选流程，没有在本轮执行。保持 Ninja 协议、香港 02、双认证、DHCP、现有规则、UA3F、Wi-Fi 与 offload 状态固定；一次只验证一个变量。

1. **MPTCP 先验证连接，后考虑第二路径。** 核对真正拨号的二进制和配置入口，选一条真实 Ninja 外层连接，观察 MP_CAPABLE、回退与对端接受状态。如果远端不接受，停止，不为此部署新代理协议。若接受，再以单连接短样本验证两个 MP_JOIN 子流、不同源地址、每条子流对应路由表及出口计数；普通多连接分别走 WAN 不等于 MPTCP。
2. **AccECN 先确认有试验理由。** 保存原值 `2`，只临时改为 `3`，新建同一节点、同一目标连接，核对握手、是否回退、CE／反馈与失败情况；完成后恢复 `2`。短样本无标记或无收益，停止，不把协商成功当成性能成功。
3. **结果同时包含吞吐、延迟与代价。** 同路径、同固定目标的 A／B／恢复 A 至少记录完成字节、耗时、失败、CPU、内存、重传与满载延迟。需要能确认 socket 实际经过该技术；不从一次速度波动归因。若影响认证、下载完整性、节点可用性或资源预算，立即恢复原值。

当前没有新的生产变更，也没有 MPTCP／AccECN 的现场收益数据。上游能力、内核开关、应用 socket、对端协商、双子流选路和实际收益分别是独立验收点。
