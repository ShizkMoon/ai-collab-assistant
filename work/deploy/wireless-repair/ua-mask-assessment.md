# UA-Mask 与当前 AX6000 代理链

**目前不建议直接用 UA-Mask 替换生产 UA3F。** 它值得作为后续实现候选，但公开性能材料与源码都不能证明该替换会消除当前 TCP 接收压力，或使无线电脑完整下载稳定超过 900 Mbps。本轮没有安装 UA-Mask。

本次固定 UA-Mask main `83846d3780b1e30f87816310ae75d95798a5bd4d` 与 v0.4.3 tag `1e5a5ce38fc207136ba21a3f82a6a3e892a3c572`。两者相差两个提交和一次大重构；main 的 VERSION 也写 0.4.3，不能只凭版本文字认定发布二进制采用新核心。[版本比较](https://github.com/Zesuy/UA-Mask/compare/1e5a5ce38fc207136ba21a3f82a6a3e892a3c572...83846d3780b1e30f87816310ae75d95798a5bd4d)、[发布页](https://github.com/Zesuy/UA-Mask/releases/tag/v0.4.3)。

## 性能主张与实际实现

作者宣传的 CPU 降幅主要涉及非 HTTP／Steam 等目标卸载。实际动态 nft 集合按目标 IPv4＋端口让之后的连接绕过 UA-Mask；教程说明可能放过真实 UA。main 的逐连接 `NoopFlowOffloader` 是空实现，不能理解为同一 HTTP 连接改完请求后已安全卸载下载正文。[固定教程](https://github.com/Zesuy/UA-Mask/blob/83846d3780b1e30f87816310ae75d95798a5bd4d/docs/tutorial.md#L186-L223)、[空实现](https://github.com/Zesuy/UA-Mask/blob/83846d3780b1e30f87816310ae75d95798a5bd4d/core/internal/offload/target.go#L43-L45)。

UA-Mask 的 TCP 下载返回使用 `io.Copy`；当前 UA3F GLOBAL 的 TCP 返回使用 `io.CopyBuffer`。Go 在 TCPConn 的 WriterTo／ReaderFrom 优化路径上忽略传入缓冲，并具备 Linux splice 路径。因此不能把“UA-Mask 零复制、UA3F 按 1 byte 复制”作为性能理由；源码也不证明每次运行都实际采用 splice。[UA-Mask 返回路径](https://github.com/Zesuy/UA-Mask/blob/83846d3780b1e30f87816310ae75d95798a5bd4d/core/internal/session/manager.go#L161-L176)、[UA3F 下行源码审阅](ua3f-copy-analysis.md)。

本机当前 UA3F 经相同完整正文负载，路由器本机链已达到约 911～923 Mbps；电脑链偏低且波动，不能据此给 UA3F 下结论为固定 800 Mbps 上限。需要处理的是完整电脑路径中的受限位置，而不是仅比较项目介绍。[接收压力来源核验](tcp-receive-drop-source-review.md)。

## 生产接入差异

| 当前必须保持的行为 | 未修改 UA-Mask 的状态 |
| --- | --- |
| Ninja 通过 SOCKS5 127.0.0.1:1080 调用 UA 处理 | 只有 IPv4 REDIRECT ingress，没有 SOCKS5 协商入口 |
| Ninja 先做国内直连／固定香港节点决策 | 默认 LAN PREROUTING 在 dstnat 前接管，可抢在 Ninja 决策之前直拨外网目标 |
| UA 外层新连接设置 C9，按现有三路递增轮换 | 普通 net.Dialer 没有 SO_MARK；原连接的 mark 不会自动继承到新 socket |
| 三认证专用 GID pin 与当前 TTL64 | 必须重新保护；官方 init 会改 firewall 并 reload，全面 OUTPUT 的默认豁免不含全部认证 GID／校园地址 |
| 保持持续 HTTP UA 改写 | 目标绕过、默认关键词和白名单不等价于现有全部选定 HTTP 改写 |

依据：[REDIRECT 入口](https://github.com/Zesuy/UA-Mask/blob/83846d3780b1e30f87816310ae75d95798a5bd4d/core/internal/ingress/redirect.go#L45-L67)、[拨号](https://github.com/Zesuy/UA-Mask/blob/83846d3780b1e30f87816310ae75d95798a5bd4d/core/internal/session/manager.go#L126-L142)、[实际接管规则](https://github.com/Zesuy/UA-Mask/blob/83846d3780b1e30f87816310ae75d95798a5bd4d/openwrt/root/etc/init.d/UAmask#L129-L159)。详细阅读范围见 [兼容性审阅](ua-mask-compatibility-review.md)与[公开性能证据审阅](ua-mask-evidence-review.md)。

一个可能有收益的方向是减少国内明文 HTTP 路径中的代理层和 TCP socket，同时保持 Ninja 的境外决策；收益来自路径变化，尚未实测。保留现有路径的候选则需补齐 SOCKS5 入口与 C9 socket 标记，关闭不等价的目标绕过，再以独立端口进行同条件比较。两条路线均不是直接安装 stock 包就完成。

## 已保留的 WED

按用户要求，WED 运行参数为 Y，实际挂接成功，`/etc/modules.d/mt7915e` 已读回 `mt7915e wed_enable=1`，独立定时回退已解除。原文件保存在私有恢复目录。电脑恢复 WLAN／HE160，三个认证 PID／starttime、WAN 地址与代理 PID 保持；三个绑定出口均 HTTP 204，UA 回显 FFF，Ninja 仍选择香港 02，电脑国内 200／境外 204，本地健康状态 HEALTHY。[保留验收](wed-retained-acceptance.json)。

此前 WED 的完整电脑两组为 821.45／626.39 Mbps，中间路由器组为 922.99 Mbps。它证明该设备能启用 WED，不证明稳定电脑 900 Mbps 或量化加速贡献；没有完整正文期间的 DMA 增量证据。启动参数已经保存，未重启整机验证冷启动。当前下载 CAKE 仍为 650 Mbit，覆盖该公共队列的下载与 900 Mbps 目标不相容；历史高吞吐样本在临时关闭该整形时取得。
