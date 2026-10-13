# 受控健康故障后的代理连接边界

## 当前结论

主代理的首次受控测试发生了一次代理请求超时：只阻断 WAN2 的 TCP/80 健康探针，约 `43.7` 秒后 WAN2 被判定 offline，`ua3f_bal` 只保留 WAN1，百度请求为 `200`，gstatic 的 `generate_204` 在 `12` 秒内超时。移除阻断并恢复双 WAN 后，gstatic 返回 `204`。该结果说明当时直连可用、代理请求未及时完成，不能单独证明 Ninja 保留了失效 WAN 的共享传输。

第二次受控复测在约 `44.3` 秒判定 WAN2 offline 后，gstatic 在总计约 `44.7` 秒即返回 `204`；双 WAN 在约 `59.0` 秒恢复后也返回 `204`。这次没有调用清连接 API或重启内核。当前没有稳定重现第一次超时，也没有清连接改善的现场证据。主代理因此保持当前配置，不添加自动全局清连接或内核重启。

主代理证据：`../followup-mwan-controlled-failover.json`、`../followup-proxy-failover-trial.json`。这些时间是对应受控测试的经过时间，不是常规物理断网恢复承诺。两 WAN 共用同一物理上联，也不能由此推定独立链路冗余。

## 能确认的接口

已下载的 `mwan3track-curl204.sh` 中，健康状态变化会调用 `/sbin/hotplug-call iface`，传递 `ACTION=connected` 或 `ACTION=disconnected`，并附 `INTERFACE`、`DEVICE`。它们是健康事件，不要求 netifd 真正出现 ifup／ifdown。

同版本提取包的 `etc/hotplug.d/iface/25-mwan3` 在 `disconnected` 分支先标记 offline，再重建策略、删除该接口 sticky 映射；后续调用 `mwan3_flush_conntrack`。已下载的生产库对 ifdown／disconnected 按该 WAN 的高位 mark 选择性清理 conntrack。`26-mwan3-user` 位于其后，可将健康事件交给 `/etc/mwan3.user`；主代理现场确认该用户脚本目前只有官方注释，没有自定义动作。该入口可用于未来已有证据支撑的恢复动作，无需把健康故障误当成 DHCP 变动。[MWAN 用户事件文档](https://openwrt.org/docs/guide-user/network/wan/multiwan/mwan3-nft#hotplug_events_mwan3user)

Mihomo 的官方 API 文档定义 `DELETE /connections` 为关闭所有被统计的连接，`DELETE /connections/:id` 为关闭指定连接。公开 `Alpha` 源码的实现遍历 `statistic.DefaultManager`，调用各 Tracker 的 `Close()`；TCP Tracker 再调用所包装 Conn 的 `Close()`，UDP Tracker 调用 PacketConn 的 `Close()`。[API 文档](https://wiki.metacubex.one/api/#connections)、[connections 路由](https://github.com/MetaCubeX/mihomo/blob/Alpha/hub/route/connections.go)、[Tracker 关闭](https://github.com/MetaCubeX/mihomo/blob/Alpha/tunnel/statistic/tracker.go)

这个 API 不等价于明确清空所有代理适配器、共享隧道、会话池或底层传输。当前路由器使用私有 `ninja` 协议代理，公开 Ninja 内核仓库只提供说明与发布，不提供相应协议实现；无法证明其 `Close()` 是否销毁共享传输。HTTP `204` 也只能证明 API 请求已处理，不能证明目标出口恢复。[Ninja 内核发布仓库](https://github.com/kachetong1314/mihomo-ninja)

## 影响与未证明事项

已有 TCP 连接不能因为 MWAN 策略切换就无缝迁移到另一个 NAT 出口；客户端或代理必须重新建立相应连接。选择性清理内核 conntrack 与应用主动关闭、共享传输失效检测并非同一件事。所有连接 API 会中断正常业务；整个 OpenClash／内核重启的影响更大。因此不能仅为一次未稳定重现的超时加入每次 offline／online 自动全局重启。

本分支检查了已下载 OpenClash `0.48.002` 包文件清单及公开 watchdog：未找到该包自带按 MWAN connected／disconnected 自动重建 Ninja 会话的 hook。watchdog 的 WAN 地址／本地网络刷新不证明有健康故障下的传输重建功能。这个搜索范围不等价于否定所有版本、定制内核或未公开功能。

已证明的是当前状态、一次超时与一次无重置复测成功，以及可用事件和 API 的公开语义。未证明第一次超时根因、Ninja 底层连接缓存状态、清连接效果、物理拔线后的完整恢复或长期稳定性。本分支没有修改任何运行配置，也没有调用会改变连接状态的 API。
