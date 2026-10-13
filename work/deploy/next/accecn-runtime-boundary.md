# AccECN：本机拒绝模式 3 的版本边界

当前设备的 `net.ipv4.tcp_ecn=3` 被内核以 `Invalid argument` 拒绝，随后读回仍为 `2`。本轮没有启用或协商 AccECN，无效持久文件已移除；`tcp_ecn_option=2`、`tcp_ecn_option_beacon=3`、`tcp_ecn_fallback=1` 保持原值。[实机操作记录](accecn-applied.json)、[最终运行验收](final-acceptance.json)。

原因已从“有符号但写入失败”收窄到明确的上游版本边界。官方稳定树 `v6.18.55` 的 `net/ipv4/sysctl_net_ipv4.c` 定义 `tcp_ecn_mode_max=2`，`tcp_ecn` 由 `proc_dou8vec_minmax` 处理，最小值为 0，最大值引用该变量。因此该版本的正常 sysctl 路径只接受 0～2，3～5 会在值范围检查时被拒绝。[固定同版源码](https://github.com/gregkh/linux/blob/v6.18.55/net/ipv4/sysctl_net_ipv4.c#L64)。

后续上游提交 `8ae3e8e6ceedfb3cf74ca18169c942e073586a39`，标题为 `tcp: accecn: enable AccECN`，明确将 `tcp_ecn_mode_max` 从 2 改为 5。这个 enable 改动没有包含在上述 `v6.18.55` 文件中。[上游 enable 提交](https://github.com/torvalds/linux/commit/8ae3e8e6ceedfb3cf74ca18169c942e073586a39)。

同版参数文档和部分 AccECN 处理代码已经存在，设备也能看到 `tcp_accecn_process` 等符号；它们说明代码组件存在，不能代替公开 sysctl 是否开放、设备是否实际接受参数和连接是否协商成功。[同版参数文档](https://github.com/gregkh/linux/blob/v6.18.55/Documentation/networking/ip-sysctl.rst)、[设备符号与状态](current-runtime-socket.json)。所以早期依据文档与符号直接判定“当前可在线启用”的结论已经纠正于 [拥塞控制方案](congestion-install-plan.md)。

本机写入拒绝与同版源码上限一致，强烈支持该版本边界解释。这里没有反汇编实际安装内核或取得完整最终构建配置，因此不声称已经从二进制中读出了这个变量，也不把缺少某个假定的专用 Kconfig 选项当成根因。已验证事实仍是值 3 被拒绝、原值保持、无效持久文件不存在。

当前处理是保留原值，停止重复写入或尝试更高值。若以后确需主动 AccECN，应在包含完整实现、启用改动和相关修复的新内核构建中选择模式 3，重新匹配全部内核模块 ABI，使用 Redmi AX6000 RB06 的 stock 布局，并分别验证认证、Ninja、CAKE、握手和回退。当前只准备了机制与维护入口，没有为 AccECN 构建、刷入固件或重启路由器。不能只绕过 sysctl 上限就声称实现完整可用。

以后验收仍分开记录：值 3 的实际接受、新建连接 SYN 的请求、对端 SYN-ACK 与反馈的协商，以及拥塞收益。本轮第一层失败，后续层未执行。AccECN、普通 ECN、BBR 和 L4S 是不同条件，任一启用不能替代其他条件的证据。
