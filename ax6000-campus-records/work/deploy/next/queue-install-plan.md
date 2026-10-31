# AX6000：启用 CAKE 的最小部署方案

当前目标是给三路校园网的共享物理出口启用可回退的队列管理，同时保留已经测到的最高下载能力。先部署 CAKE；L4S / DualPI2 保留为独立备选。方案不重启整机、不重载网络、不刷新连接跟踪，不修改认证、Ninja 核心、TTL、MSS 或 MWAN 的标记规则。

## 当前设备与可安装包

本次读取的设备是 OpenWrt SNAPSHOT `r37185-f29dfe25ba`，内核为 `6.18.55`，目标是 `mediatek/filogic`，架构为 `aarch64_cortex-a53`。内核包的 ABI 标识为 `b218d80d146ac6c85db4989df73b5de9`。`tc` 是 iproute2 `6.18.0`，已安装 `kmod-sched-core`。`wan`、`eswan2`、`eswan3` 当前使用 `noqueue`；`eth0` 已有 `mq` 及多个 `fq_codel` 子队列，应保留。读取时 overlay 可用空间为 `13,820 KiB`，`MemAvailable` 为 `163,316 KiB`。

官方精确内核仓库在此次公开读取时返回 HTTP 200，并列出以下包：

| 包 | 版本 | 仓库所示大小 | 用途 |
| --- | --- | --- | --- |
| `kmod-sched-cake` | `6.18.55-r1` | 18.1 KB | CAKE 队列 |
| `kmod-ifb` | `6.18.55-r1` | 4.3 KB | 聚合入口整形 |
| `kmod-sched-dualpi2` | `6.18.55-r1` | 7.9 KB | 备选 L4S / DualQ AQM |

精确仓库：<https://downloads.openwrt.org/snapshots/targets/mediatek/filogic/kmods/6.18.55-1-b218d80d146ac6c85db4989df73b5de9/>。这个仓库和当前内核对应；普通 SNAPSHOT 基础软件仓库会滚动，不能因此升级基础包或内核。

在限定的 `work/deploy` 文件名搜索范围内，没有找到可直接复用的上述 `.apk` 文件。安装时先用实际 `apk --help` 核对当前参数，使用仅含上述精确仓库的临时 repositories 文件更新签名索引，然后模拟安装明确版本的 CAKE 和 IFB。只有解析计划仅新增所需模块及其已匹配依赖，且没有升级、替换或移除现有包时，才执行安装。不要使用 `--allow-untrusted`、忽略依赖或强制覆盖。安装 DualPI2 模块不会自动启用 L4S；本轮可以只装 CAKE 和 IFB。

## 队列位置与初始参数

三路虚拟 WAN 的 macvlan 发包最终交给它们共同的下层物理设备。Linux 在入口调用 ingress 处理后，才调用 macvlan 的接收处理器。因此，在确认三路的 `lowerdev` 都是 `wan` 后，可以在 `wan` 出口设置一个 CAKE，并将 `wan` 入口重定向到单个 IFB，在 IFB 上设置一个 CAKE。这样三路共用聚合队列；不应在每个虚拟 WAN 上各设置一个完整的总带宽上限。

先用 `ip -d link show`、接口的 `iflink`、`tc -s qdisc show` 和 `tc filter show` 核对下层关系及原有过滤器。只有 `wan` 仍是三路共享下层设备、没有需保留的入口过滤器冲突时，才能直接采用下列命令。验证时必须通过三路流量及计数增量确认覆盖，源码路径本身不能代替设备验证。

建议本轮采用以下初始参数：

| 方向 | 位置 | 初始速率 | 原因及限制 |
| --- | --- | --- | --- |
| 下载 | `wan` ingress → `ifb-cake` root | `650Mbit` | 为旧样本 `612.86 Mbps` 及以太网开销留出余量；先保留峰值能力。这个上限可能高于实际校园网瓶颈，不能保证把所有上游排队移到路由器。 |
| 上传 | `wan` root | `unlimited` | 已有单一路径上传样本不能确定三路聚合上传容量。先启用 CAKE 的本地 AQM，不编造会限速的上传值；这也不能保证控制校园网上游的上传队列。 |

这是一套保留下载峰值优先的初始 CAKE 配置。若后续需要更强的拥塞延迟控制，必须根据实际聚合容量选择略低于瓶颈的整形速率。不能直接把单次多连接下载样本乘以 90% 当作稳定线路容量，也不能宣称 `650Mbit` 已完成全部上下行 SQM 验收。

选择 `besteffort flows`，暂不按 DSCP 分档，也不把 MWAN 的 fwmark 解释成 CAKE tin。三路账号及代理外层连接会改变路由器看到的主机与流，主机公平性不能自动代表 LAN 用户公平性。保留 `no-ack-filter`、默认 `split-gso`，每个 CAKE 设置 `memlimit 8mb`，限制此轮队列内存预算。按已经确认的以太网 MTU 1500 使用 `ethernet` 开销，不套用 DSL、ATM 或 PPPoE 配置。

以下是原有 `wan` root 为 `noqueue`、没有入口 qdisc / filter 时的候选命令，须由唯一设备操作方顺序执行：

```sh
# 模块安装并确认成功后；先确认此 IFB 名称尚未使用。
modprobe sch_cake
modprobe ifb
ip link add ifb-cake type ifb
ip link set dev ifb-cake up

tc qdisc add dev ifb-cake root handle 1: cake bandwidth 650Mbit \
    besteffort flows nonat ingress ethernet rtt 100ms \
    no-ack-filter split-gso memlimit 8mb
tc qdisc replace dev wan root handle 1: cake unlimited \
    besteffort flows nonat ethernet rtt 100ms \
    no-ack-filter split-gso memlimit 8mb

tc qdisc add dev wan handle ffff: ingress
tc filter add dev wan parent ffff: protocol all pref 49152 \
    matchall action mirred egress redirect dev ifb-cake
```

此处没有清除 DSCP、改写 TTL、skb mark 或 connmark。若 `wan` 已有入口 qdisc，则保留它，改用一个确认未占用的 filter 优先级，并只删除本轮建立的 filter；不能执行整段替换或删掉既有 ingress / clsact。若创建 IFB 或任何 qdisc 失败，立即撤回本轮已执行部分。

初次部署先设置自动回退计时器，再临时应用队列。管理连接、DNS、认证和三路路由通过后，才取消计时器。持久化可复用项目现有服务方式，使用单一所有者、幂等的 start / stop，并记录本轮创建的 root、filter 和 IFB。接口重新创建后需要再次应用队列；服务重启不能触发网络 reload、认证重启或连接跟踪清空。若没有安装 `sqm-scripts` / LuCI SQM，应如实注明队列由自定义服务管理，不能声称已经具备标准 SQM 页面和全部脚本功能。

## 最小验证与回退

先记录原有 qdisc、filter、路由、策略规则、认证 PID、代理 PID、各接口地址及空闲延迟。应用后读取 `tc -s qdisc show dev wan` 和 `tc -s qdisc show dev ifb-cake`，确认参数与字节计数增长。再执行国内 HTTPS、代理 HTTPS、DNS 和三路路由读回，确认既有路径继续工作。

吞吐验收复用既有相同下载任务及文件大小，同时采样空闲与负载下的网关 / 外部延迟、队列 backlog、丢包、CPU 和可用内存。不要只凭一个不同时间的下载数字判断增益。若出现断路、认证重启、接口覆盖不全、路由 / 标记改变或明确的吞吐退化，恢复原队列。若总流量进入 IFB 但某一路没有测试流量，不能宣称三路均已覆盖。若延迟没有改善，也应保留这个结果及其速率偏高的限制。

基线没有入口 qdisc，且以下对象均由本轮建立时，回退动作是：

```sh
tc filter del dev wan parent ffff: protocol all pref 49152
tc qdisc del dev wan ingress
tc qdisc del dev wan root
ip link set dev ifb-cake down
ip link del dev ifb-cake
```

删除自建 root 后，读取确认 `wan` 恢复原先的 `noqueue`。若基线已有 root / filter，则按原始记录精确恢复；不要套用上述无过滤器基线。模块包可保留，回退不需要卸载共享模块，也不需要重启整机。

## L4S / DualPI2 的实际边界

CAKE 是 classless qdisc，不能把 DualPI2 作为 CAKE 子队列。一个接口的 root 同时只有一棵队列树；在同一瓶颈串联 CAKE 与 DualPI2 也不能当作标准 DualQ / L4S 部署。若以后启用 DualPI2，应使用独立配置替换 CAKE，例如经过验证的 HTB / TBF 整形器加 DualPI2 leaf，并保留同样的聚合出口、入口及回退条件。

DualPI2 提供 AQM 和双队列耦合，本身不是带宽整形器。默认按 ECT(1) 识别 L4S 流量；普通互联网混合流量不应开启 `any_ect` 把所有 ECN 流量当作可扩展拥塞控制。获得 L4S 效果还要求发送端、接收反馈、拥塞控制与隧道 ECN 传播配合。启用路由器普通 `tcp_ecn`，或仅安装内核模块，都不能证明这些条件成立。Ninja 代理可能重建外层连接，内层客户端的 ECN 状态不一定保留到路由器实际整形的外层流量。

本轮不同时切换 CAKE 和 DualPI2，不改全局拥塞控制。可以记录内核与 `tc` 已支持 DualPI2，后续以真实 ECT(1)、CE 标记、反馈及混合经典流量测试决定是否启用。没有端点证据时，应交付“具备部署能力，L4S 效果尚未验证”。

## 原始来源

- [当前精确 OpenWrt 内核仓库](https://downloads.openwrt.org/snapshots/targets/mediatek/filogic/kmods/6.18.55-1-b218d80d146ac6c85db4989df73b5de9/)。包可用性仅代表本次读取的仓库状态。
- [OpenWrt 当前对应提交的调度模块定义](https://github.com/openwrt/openwrt/blob/f29dfe25baaa5c03f2b52f49dfdc12ed99abe8df/package/kernel/linux/modules/netsupport.mk)。CAKE / DualPI2 依赖及构建选项。
- [iproute2 6.18.0：CAKE 手册](https://github.com/iproute2/iproute2/blob/v6.18.0/man/man8/tc-cake.8)。速率、隔离、开销、ACK、GSO 和内存参数。
- [iproute2 6.18.0：DualPI2 手册](https://github.com/iproute2/iproute2/blob/v6.18.0/man/man8/tc-dualpi2.8)。DualQ、ECT(1) 与参数边界。
- [Linux 6.18：macvlan 发送路径](https://github.com/torvalds/linux/blob/v6.18/drivers/net/macvlan.c)、[Linux 6.18：核心接收路径](https://github.com/torvalds/linux/blob/v6.18/net/core/dev.c)。聚合下层设备与 ingress 处理顺序；设备覆盖仍须用实际计数验证。
- [RFC 9330：L4S 架构](https://www.rfc-editor.org/rfc/rfc9330.html)、[RFC 9331：L4S 标识](https://www.rfc-editor.org/rfc/rfc9331.html)、[RFC 9332：DualQ 耦合 AQM](https://www.rfc-editor.org/rfc/rfc9332.html)。L4S 的端点、反馈与队列条件。
