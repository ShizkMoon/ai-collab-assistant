# 当前固件的 BBR 与 AccECN 启用方案

当前系统拒绝 `tcp_ecn=3`，AccECN 未能在线启用，保留 `2`，无效持久文件已移除。匹配内核 ABI 的官方 BBRv1 模块已经在线安装、加载并选为新建本机 TCP 默认，一个真实新 socket 也已报告 `bbr`。BBRv3 没有现成的已验证入口，需要把指定实现移植到对应 OpenWrt 内核并构建；不能通过写入 `bbr` 或 `bbr3` 字符串启用。[实机 AccECN 结果](accecn-applied.json)、[实际 BBR socket](bbr-socket-acceptance.json)、[AccECN 版本边界](accecn-runtime-boundary.md)。

本文件保留机制核查、操作边界与当前部署结果。原研究支线没有 SSH 或设备修改；实际模块安装、BBR socket 与 AccECN 拒绝来自主线执行证据，不能以研究方案代替实机结果。

## 设备与软件证据

下表为操作前 `state-before.json` 快照，读取时刻以该文件的 `time` 为准，表中 CUBIC／无新模块不代表当前状态。最新安装、队列和默认值见 [最终验收](final-acceptance.json)：

| 项目 | 读回结果 | 含义 |
| --- | --- | --- |
| 系统 | OpenWrt SNAPSHOT `r37185-f29dfe25ba`，`mediatek/filogic`，`aarch64_cortex-a53` | 选择当前平台包 |
| 内核 | `6.18.55` | 还须匹配完整 ABI |
| kernel 包 | `6.18.55~b218d80d146ac6c85db4989df73b5de9-r1` | 不能用任意同版本 kmod 替代 |
| 可用／允许拥塞控制 | `reno cubic`／`reno cubic` | BBR 当前未注册 |
| 默认拥塞控制 | `cubic` | 新建 socket 默认值 |
| 本地模块候选 | 空 | 未找到当前所查 BBR／CAKE／IFB／DualPI2 候选；不等于内核不支持模块 |
| AccECN 参数 | `tcp_ecn=2`，`tcp_ecn_option=2`，`tcp_ecn_option_beacon=3`，`tcp_ecn_fallback=1` | 后续实机写 3 被拒绝；符号与文档不替代运行接受 |
| 默认 qdisc | `fq_codel` | `fq_codel` 与 BBR pacing 推荐的 `fq` 是不同 qdisc |
| WAN qdisc | `wan`、`eswan2`、`eswan3` 均为 `noqueue` | 本方案无需更改这些队列 |
| 空间／内存 | overlay 可用 `13,820 KiB`，MemAvailable `163,316 KiB` | 文件可得性不替代安装事务预算 |

精确 ABI 仓库本次可读，列有 `kmod-tcp-bbr-6.18.55-r1.apk`，目录显示约 `5.8 KB`。这是下载可得性证据；安装前仍须由设备包管理器验证可信签名和完整 kernel 依赖。[当前 ABI 仓库](https://downloads.openwrt.org/snapshots/targets/mediatek/filogic/kmods/6.18.55-1-b218d80d146ac6c85db4989df73b5de9/)

固定 OpenWrt 源码的 `KernelPackage/tcp-bbr` 设置 `CONFIG_TCP_CONG_BBR`，打包 `net/ipv4/tcp_bbr.ko`，并通过 `AutoProbe` 加载。它安装的 `/etc/sysctl.d/12-tcp-bbr.conf` 仅设置 `net.ipv4.tcp_congestion_control=bbr`，没有设置 `fq`。[模块配方](https://github.com/openwrt/openwrt/blob/f29dfe25baaa5c03f2b52f49dfdc12ed99abe8df/package/kernel/linux/modules/netsupport.mk#L1133)、[包内 sysctl](https://github.com/openwrt/openwrt/blob/f29dfe25baaa5c03f2b52f49dfdc12ed99abe8df/package/kernel/linux/files/sysctl-tcp-bbr.conf)

## AccECN：当前 sysctl 拒绝模式 3

Linux 参数文档描述以下模式，但官方 `v6.18.55` 的 sysctl 上限仍为 `tcp_ecn_mode_max=2`，通过 `proc_dou8vec_minmax` 拒绝 3～5。本机写 3 返回 EINVAL，读回仍为 2。后续上游 `8ae3e8e6ceedfb3cf74ca18169c942e073586a39` 才将上限改为 5；可见 AccECN 代码和参数文档先进入，但启用开关没有进入当前版本。[固定 sysctl](https://github.com/gregkh/linux/blob/v6.18.55/net/ipv4/sysctl_net_ipv4.c#L64)、[后续 enable 提交](https://github.com/torvalds/linux/commit/8ae3e8e6ceedfb3cf74ca18169c942e073586a39)、[实机拒绝](accecn-applied.json)。下表的 3～5 为具备完整启用支持时的含义，本机当前不能设置；数值本身也不保证对端会协商：

| 值 | 入站新连接最高支持 | 出站新连接主动请求 |
| ---: | --- | --- |
| 0 | 无 ECN | 无 ECN |
| 1 | 经典 ECN | 经典 ECN |
| 2 | 经典 ECN | 不主动请求 ECN |
| 3 | AccECN | AccECN |
| 4 | AccECN | 经典 ECN |
| 5 | AccECN | 不主动请求 ECN |

源码 `tcp_ecn_send_syn()` 对值 `3` 设置 AccECN 握手标志；`tcp_ecn_create_request()` 对值至少 `3` 接受 AccECN 入站请求。路由 `features ecn` 仅能要求经典 ECN，不能代替值 `3`。[固定参数文档](https://github.com/gregkh/linux/blob/v6.18.55/Documentation/networking/ip-sysctl.rst)、[固定 SYN 实现](https://github.com/gregkh/linux/blob/v6.18.55/include/net/tcp_ecn.h#L603)、[固定入站实现](https://github.com/gregkh/linux/blob/v6.18.55/net/ipv4/tcp_input.c#L7248)

当前保持 `tcp_ecn=2`、`option=2`、`beacon=3`、`fallback=1`，只需读回，不再尝试写 3 或更高值。若以后确需主动 AccECN，应构建／选择包含完整支持与相关修复、匹配 stock 布局和新 kmod ABI 的固件，再另验新连接握手与回退；不能绕过当前 sysctl 上限。

```sh
# 当前设备只读核对；值 3 已被拒绝。
sysctl net.ipv4.tcp_ecn net.ipv4.tcp_ecn_option net.ipv4.tcp_ecn_option_beacon net.ipv4.tcp_ecn_fallback
```

本轮拒绝后已保持原值，无效持久文件已移除。原值恢复入口为：

```sh
sysctl -w net.ipv4.tcp_ecn=2
```

`tcp_ecn_option=2` 表示已协商 AccECN 且反向选项可用时，TCP 选项空间允许就发送 AccECN 选项。`0` 会关闭选项，`1` 会更节省地发送。`beacon=3` 是默认的反馈频率参数，不是“每 RTT 最多三个包”的限额；当前不降低频率，也不关闭回退。该内核对 option 只接受 `0..2`，对 beacon 只接受 `0..3`，不采用网上随意增大 beacon 的配置。[参数边界](https://github.com/gregkh/linux/blob/v6.18.55/net/ipv4/sysctl_net_ipv4.c#L728)、[发送选项条件](https://github.com/gregkh/linux/blob/v6.18.55/net/ipv4/tcp_output.c#L1183)、[beacon 检查](https://github.com/gregkh/linux/blob/v6.18.55/include/net/tcp_ecn.h#L660)

协商允许降级：对端仅回应经典 ECN 时，普通 CUBIC／BBRv1 连接可以采用经典 ECN；对端不支持时采用无 ECN。`fallback=1` 还保留 ECN SYN 失效时的无 ECN 重传，以及相关 AccECN 反馈校验。它不是“所有中间盒都一定兼容”的保证。[SYN-ACK 模式选择](https://github.com/gregkh/linux/blob/v6.18.55/include/net/tcp_ecn.h#L496)、[SYN 重传回退](https://github.com/gregkh/linux/blob/v6.18.55/net/ipv4/tcp_output.c#L3550)

以后换成接受模式 3 的完整实现时，验收分三层：读回值 3 表示配置启用；新建路由器本机 TCP 的 SYN 带 AccECN 标志表示实际发起请求；SYN-ACK、后续 ACK／AccECN 选项或 socket 诊断才证明该连接协商成功。本轮第一层即失败，没有握手或收益结论。仅连通或回退成功不能称为 AccECN 已协商；抓包限定新连接四元组与 TCP 头，不采集认证、代理或用户业务载荷。

该设置影响路由器当前网络命名空间内参与握手的 TCP。既有已协商连接不会因为修改 `tcp_ecn` 重新握手；回滚到 `2` 也不会追溯改变已经建立的 AccECN 连接。纯转发／NAT 的 Windows PC TCP 仍由 Windows 与远端决定；路由器上的透明代理若终止内层连接并创建新的内核 TCP 外层连接，外层可以受此设置影响。使用 UDP／QUIC 或自带 TCP 栈的协议不因此切换。AccECN 不自动启用 L4S、Prague、AQM 或 BBR。

## BBRv1：匹配模块可在线安装、加载和选择

固定 Linux `v6.18.55` 的上游 `tcp_bbr.c` 是 BBRv1 系列实现，依据 ACK 估计带宽与最小 RTT，包含原始 BBR 状态机；不能仅因内核版本新就称为 BBRv3。它推荐 `fq` pacing，同时明确没有 `fq` 时可以使用每 socket 的内部定时器 pacing。因此本轮可以保持现有 qdisc，先启用 BBRv1；不用先修改三个出口或改全局默认队列。[固定 BBR 实现](https://github.com/gregkh/linux/blob/v6.18.55/net/ipv4/tcp_bbr.c#L1)

实际安装沿用设备已有可信公钥验证原官方签名索引，再按精确包名／版本验证包 identity 与 DATA 摘要。此仓库的裸 APK 不带独立签名，直接 `apk verify local.apk` 或按裸文件路径安装会返回 UNTRUSTED；不是靠添加密钥或忽略签名解决。[信任路径](package-signing-plan.md)、[实际索引验签与模拟](package-index-preflight.json)、[安装结果](packages-installed.json)。BBR 精确包 URL：

<https://downloads.openwrt.org/snapshots/targets/mediatek/filogic/kmods/6.18.55-1-b218d80d146ac6c85db4989df73b5de9/kmod-tcp-bbr-6.18.55-r1.apk>

主线已经使用专用 repositories 文件限定到这份原签名索引，永久 feeds 未改；模拟与真实事务只新增 IFB／CAKE／BBR 三包，没有改 kernel、libc 或 base-files。以下为已执行入口的精确包选择，当前不需要重复安装。若以后恢复时解析计划要求升级、降级或替换其他包，应停止核对，不强行覆盖、不使用 `--allow-untrusted`。

```sh
apk --repositories-file /tmp/codex-next/repositories --cache-dir /tmp/codex-next/cache \
    add --simulate kmod-ifb=6.18.55-r1 kmod-sched-cake=6.18.55-r1 kmod-tcp-bbr=6.18.55-r1
# 本轮已执行并通过，不需要重复；只适用于原签名索引与精确 ABI。
apk --repositories-file /tmp/codex-next/repositories --cache-dir /tmp/codex-next/cache \
    add kmod-ifb=6.18.55-r1 kmod-sched-cake=6.18.55-r1 kmod-tcp-bbr=6.18.55-r1
modprobe tcp_bbr
sysctl net.ipv4.tcp_available_congestion_control net.ipv4.tcp_allowed_congestion_control
sysctl -w net.ipv4.tcp_congestion_control=bbr
sysctl net.ipv4.tcp_congestion_control
```

安装过程可能触发模块自动加载，包也带有启动时选择 BBR 的配置。不能把包安装当成纯落盘。执行前保存 `/etc/sysctl.conf`、已有相关 `/etc/sysctl.d/` 文件、模块／包状态和默认拥塞控制；安装后立即核对这些值及认证、进程和 qdisc。若本轮仅需运行时试用，必须同时处理包内 `12-tcp-bbr.conf` 的持久化效果，而不是只做一次运行时回滚。

运行时回滚只需恢复保存的默认算法，本次基线是：

```sh
sysctl -w net.ipv4.tcp_congestion_control=cubic
```

已经使用 BBR 的 socket 继续使用各自的拥塞控制；默认算法恢复不改写既有连接。模块可以保留加载，避免对活跃连接强行卸载。完整撤销还需恢复本轮新增／修改的持久化 sysctl；若删除新装包，先模拟 `apk del kmod-tcp-bbr`，确认只移除该包并保护原有文件，再执行和读回。不要删除任务开始前已有的包或设置。

默认算法在新建 socket 时取得；已有监听 socket 的接受连接会继承监听 socket 的选择。应用也可以用 `TCP_CONGESTION` 覆盖默认值。验收应查看本轮新建的路由器外层 socket，确认它实际报告 `bbr`，不能以 sysctl 默认值代替该 socket 的算法。[默认及每 socket 算法选择](https://github.com/gregkh/linux/blob/v6.18.55/net/ipv4/tcp_cong.c#L215)

BBR 控制本机发送端。它不能替远端下载服务器选择发送算法，也不能把纯转发的 PC 连接改成 BBR。代理可能为 PC 接收远端数据再向 LAN 发送，这涉及两个独立 TCP 连接。启用结果与下载、上传、隧道发送方向的实际收益须分别描述。

若后续明确需要 `fq`，固定 OpenWrt 的 `sch_fq` 位于 `kmod-sched`，该包同时带其他调度器、依赖及 TEQL hook；不是独立 `kmod-sched-fq`，也不是已有 `kmod-sched-core`。加载 `sch_fq` 或改 `net.core.default_qdisc` 不会自动替换所有已存在的 qdisc，必须另做对象明确的队列变更。本轮在线启用 BBRv1不需要扩大到该变更。[固定额外调度器包](https://github.com/openwrt/openwrt/blob/f29dfe25baaa5c03f2b52f49dfdc12ed99abe8df/package/kernel/linux/modules/netsupport.mk#L1092)

## 已构建配置：区分模板、最终内核与安装状态

固定 `generic/config-6.18` 含 `CONFIG_TCP_CONG_ADVANCED=y`、`CONFIG_TCP_CONG_CUBIC=y`、`CONFIG_DEFAULT_TCP_CONG="cubic"`，模板里 BBR 与 `NET_SCH_FQ` 未设置；filogic 对应配置没有覆盖这些项。这个模板不等于最终已构建 `.config`。OpenWrt 会把包生成的 Kconfig override 合入 `.config.set`，并以结果生成 ABI hash。不能因此断言“当前内核根本没编 BBR”。[固定配置模板](https://github.com/openwrt/openwrt/blob/f29dfe25baaa5c03f2b52f49dfdc12ed99abe8df/target/linux/generic/config-6.18)、[配置合并与 ABI 计算](https://github.com/openwrt/openwrt/blob/f29dfe25baaa5c03f2b52f49dfdc12ed99abe8df/include/kernel-defaults.mk#L115)

`state-before.json` 没有导出实机完整内核配置。本支线不把上游模板称为实机 config。若设备有 `/proc/config.gz`，主线可以只读：

```sh
test -r /proc/config.gz && zcat /proc/config.gz | grep -E 'CONFIG_(TCP_CONG|DEFAULT_TCP_CONG|NET_SCH_FQ|IKCONFIG)'
```

文件不可得时，以设备 kernel 包 ABI、模块文件、包依赖、加载结果和实际 socket 为证据。精确 ABI 的官方 BBR 包可得意味着有匹配构建产物可供验证，不意味着已经安装或启用。自编上游 BBR 模块至少需要 `CONFIG_TCP_CONG_ADVANCED=y`、`CONFIG_TCP_CONG_BBR=m` 或 `y`；OpenWrt 包选择是 `CONFIG_PACKAGE_kmod-tcp-bbr=y` 或 `m`，最终内核通常将对应模块编成 `m`。默认算法仍可在线用 sysctl 改为 `bbr`，不要求将 `CONFIG_DEFAULT_BBR=y` 编入内核。

## BBRv3：当前准确路径与不能直接启用的原因

Google 官方 `v3` 分支本次解析到提交 `90210de4b779d40496dee0b89081780eeddf2a60`；该提交的基础内核是 `6.13.7`。源码明确 `BBR_VERSION=3`，注册名仍是 `bbr`，所以 `tcp_available_congestion_control` 出现 `bbr` 不能单独辨别 v1／v3。[固定 Google 版本定义](https://github.com/google/bbr/blob/90210de4b779d40496dee0b89081780eeddf2a60/net/ipv4/tcp_bbr.c#L72)、[固定基础内核](https://github.com/google/bbr/blob/90210de4b779d40496dee0b89081780eeddf2a60/Makefile#L2)

该分支还包含 TCP 丢包通知回调、扩展的 BBR 诊断字段、ECN 相关状态和测试工具补丁。它的完整实现不是与当前 `6.18.55` ABI 已验证兼容的独立 APK，不能把其 `.ko` 直接复制到当前固件，也不能只改模块名制造兼容。[官方构建说明](https://github.com/google/bbr/blob/90210de4b779d40496dee0b89081780eeddf2a60/README.md)、[诊断字段](https://github.com/google/bbr/blob/90210de4b779d40496dee0b89081780eeddf2a60/include/uapi/linux/inet_diag.h#L225)、[丢包通知](https://github.com/google/bbr/blob/90210de4b779d40496dee0b89081780eeddf2a60/net/ipv4/tcp_input.c#L1129)

可行的落地步骤是固定当前 OpenWrt 源码、目标 profile 与 Google 实现提交，审阅并移植完整所需改动到 OpenWrt 实际使用的内核，设置 `CONFIG_TCP_CONG_BBR=m/y`，在完整 OpenWrt buildroot 构建内核、匹配 kmod 和 **Redmi AX6000 stock layout** 固件；检查编译与符号，验收 BBR 版本诊断、回退、认证和代理业务，再部署对应固件。涉及内核主体更改时会产生新的 ABI，不能混用当前旧 kmod；正常固件升级需要重启。ImageBuilder 只组装已有内核与包，不能把 BBRv3 内核补丁加入现有官方内核。

若未来出现只使用当前内核已有 API、正确移植且完整 ABI 匹配的 BBRv3 模块，可以另验证在线加载；本次没有取得这种产物，不声称绝对不存在。当前已执行的在线选择是官方 BBRv1；AccECN 模式 3 已实际被拒绝。Google v3 的 `ecn_low` 示例来自它自己的内核／iproute2 补丁，不能套用到本机并称为 AccECN 或 L4S 已启用。

## 本轮交付边界

- 支线读取了固定官方 Linux／OpenWrt／Google BBR 源码与精确 ABI 下载目录，使用 Agent Reach 的 GitHub CLI／网页阅读入口。
- 支线只写此文件；没有执行文件中的设备命令。后续主线实际启用记录优先于本文件的操作前快照。
- `agent-reach check-update` 已尝试，因 GitHub API 速率限制未能确认是否存在新版，未安装或升级工具。
