# 无线重载后恢复系统 packet steering

建议增加一个窄范围的 `net` hotplug hook，针对 `phy*-ap*` 的 `add／move` 事件，在后台合并事件、确认接收队列存在后调用现有 `/etc/init.d/packet_steering reload`。不用自定义 CPU mask，不改原 init，也不启用 flow offload。

这是离线候选，未 SSH、未改路由器。主代理已实测：HE160、CN 信道 36 完成 60 秒 CAC，PC 协商 2402 Mbps／约 −38 dBm；radio1 reload 后新 `phy1-ap0` 的 `rps_cpus=0`，再次 reload 系统 steering 后恢复为 `2`。这支持“netdev 重建后缺一次后续应用”的解释，不证明 RPS 是所有性能变化的唯一原因。

## 固定源码依据

设备对应 OpenWrt `f29dfe25baaa5c03f2b52f49dfdc12ed99abe8df` 的 init 注册 `network`／`firewall` 配置 reload 和延迟 1000 ms 的 `interface.*` 原始触发器。reload 时通用 ucode 每次重新枚举当时存在的 netdev、sysfs queue 和 NAPI 线程，不监听此后才出现的队列。无线成员设备被销毁重建时，LAN 逻辑接口可以继续在线；现有触发器可能没有发生或早于 netdev ready，不能保证每个新的无线接收队列都已被枚举。[固定 init](https://github.com/openwrt/openwrt/blob/f29dfe25baaa5c03f2b52f49dfdc12ed99abe8df/package/network/config/netifd/files/etc/init.d/packet_steering)、[固定 steering 实现](https://github.com/openwrt/openwrt/blob/f29dfe25baaa5c03f2b52f49dfdc12ed99abe8df/package/network/config/netifd/files/usr/libexec/network/packet-steering.uc)

固定 procd `hotplug.json` 在对应目录存在时调用 `/sbin/hotplug-call net`；`hotplug-call` 按文件名执行脚本，并导出 `DEVICENAME=${DEVPATH##*/}`。net 内核事件还提供 `INTERFACE`。已有 mediatek hook `00-netdev-name` 处理 `add`，候选使用 `99-` 放在其后，并同时接收 `move`，覆盖创建后的重命名。[固定 procd hotplug](https://github.com/openwrt/openwrt/blob/f29dfe25baaa5c03f2b52f49dfdc12ed99abe8df/package/system/procd/files/hotplug.json)、[固定 hotplug-call](https://github.com/openwrt/openwrt/blob/f29dfe25baaa5c03f2b52f49dfdc12ed99abe8df/package/base-files/files/sbin/hotplug-call)、[mediatek netdev 名称 hook](https://github.com/openwrt/openwrt/blob/f29dfe25baaa5c03f2b52f49dfdc12ed99abe8df/target/linux/mediatek/filogic/base-files/etc/hotplug.d/net/00-netdev-name)

固定 netifd `06d06c86d757196e56bb13a1a8d6d69df7cad04d` 区分逻辑接口 `iface` hotplug 与设备生命周期；仅链路 up 不调用 `hotplug.d/iface`。因此，不把 `iface` hook 当成无线 netdev 重建的唯一可靠入口。[固定 netifd 事件实现](https://github.com/openwrt/netifd/blob/06d06c86d757196e56bb13a1a8d6d69df7cad04d/interface-event.c#L142)

## 候选文件与行为

| 本地候选 | 安装目标 | 作用 |
| --- | --- | --- |
| `99-wireless-steering.hotplug.candidate` | `/etc/hotplug.d/net/99-wireless-steering` | 仅接受 `add／move` 和安全格式的 `phy[0-9]*-ap[0-9]*` 名称，调用 helper |
| `wireless-steering-reload.candidate.sh` | `/usr/libexec/wireless-steering-reload` | tmpfs 事件队列、单 worker、2 秒合并、最多 5 秒 queue-ready 等待；调用原 init reload |

两个文件安装后需可执行（0755）。hook 只触发创建／重命名，忽略 remove、WAN、MACVLAN、bridge 和其他接口；不会因 steering 自己写 RPS 引发同类 net add 事件循环。

helper 先写入独立随机 staging 文件，再在同目录 rename 为事件文件，保证 worker 只看到完整事件，然后启动一个后台 worker。worker 的同轮文件列表在处理前固定；reload 期间的新事件不会被删除，下一轮继续处理。释放锁后再检查事件，避免把锁释放窗口进入的事件留在无人处理的队列。所有临时路径都固定在 `/var/run/wireless-steering.*`，不写 overlay，不使用递归删除。

helper 不改 `packet_steering`／`steering_flows` UCI。无论当前值是 unset、0、1 还是 2，最终都由原 init 和原 ucode 解释。若用户设为 0，候选不会强制恢复非零 mask。

这只保证本 helper 自己的 worker 去重，不能与原 procd trigger 或人工 reload 建立全局互斥。2 秒合并通常晚于原 1 秒 trigger，但不能把这种时序称为严格互斥。原算法重新计算所有现有网络设备，不只改 `phy1-ap0`；其行为与这次已验证的手动 reload 一致，仍需读回有线与无线分配。

## 主代理执行前检查

1. 只读核对目标机器的 `/etc/hotplug.d/net/` 现有文件、`/sbin/hotplug-call`、`/etc/init.d/packet_steering` 和 `/usr/libexec/network/packet-steering.uc` 与本轮固定源码一致。确认 helper 的安装目标不存在未知现有文件；保护旧内容。
2. 确认 BusyBox／当前 PATH 有 `mktemp`、`mkdir`、`rmdir`、`mv`、`sleep`、`cat`、`logger`。候选不引入 `flock`、ubus 常驻监听器、额外包或新服务。
3. 先原子写入 helper，再写 hook；两者 0755。安装无需重启 network／firewall；真正验收由下一次已授权的 radio reload 触发。

## 验收与回退

主代理在一次 radio1 reload 前后记录 ifindex、`phy1-ap0` 的所有 `rx-*/rps_cpus`、其他相关设备的 masks、NAPI 亲和性，以及 `logread -e wireless-steering`。在 AP 重建后约 2～7 秒内应出现成功日志并恢复系统算法分配；这台默认模式下期待非零且通常为 `2`，但不能把 `2` 硬编码为协议要求。检查队列 pending 已空、lock 已释放、无持续 worker，并验证 Wi-Fi 和 WAN 请求仍通。

随后再做一次 radio1 reload，确认重复生命周期也恢复；若本轮同时需要软件 reboot 验收，在软件重启后同样读回。没有使用物理断电或长期重连验收时，结论只限已执行条件。吞吐改善另用原有持续 LAN 对照验证，不能由 mask 恢复推出固定速率收益。

异常日志、queue-ready 超时、mask 仍为 0 或事件没有触发时，暂停候选，读回实际事件环境和 sysfs 生命周期。不要补写自定义 CPU masks。回退只移除／恢复这两个 owned 安装目标，取消 pending worker 后清理其固定 tmpfs 目录；不改原 init、UCI 或其他 hotplug 文件。

`SIGKILL`／OOM 可使 worker 无法运行 trap，锁可能保留至重启，需要主代理按上述固定路径确认 pid 已死亡后清理。候选不让多个并发 hotplug 调用抢占旧锁，因为抢占可能误删另一个正在启动的 worker 的锁。候选没有新增常驻 watchdog，不能声称对任意进程崩溃提供绝对恢复保证。

## 离线检查

两份 shell 候选已通过本机 Git Bash `bash -n`。`validate-steering-events.py` 只对隔离的本地假 sysfs 和 mock init 执行模拟，验证连续三个事件合并、reload 中到达的事件保留、稍后出现的 RX queue 被接受、无效设备忽略、最终 pending 清空和锁释放。结果保存为 `steering-event-validation.json`。这验证事件调度逻辑，不证明目标 BusyBox、真实 kernel uevent、NAPI 就绪或 radio reload 的实际结果；主代理仍须执行前述实机验收。
