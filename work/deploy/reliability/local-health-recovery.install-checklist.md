# 局部健康恢复候选

本支线仅写本目录。没有 SSH、生产修改、公网请求或读取私密配置。候选只确认本地最低协议可用性，不证明校园认证、香港节点、WAN 或实际应用业务正常。

## 候选文件与目标位置

| 本目录文件 | 目标路径 | 权限 |
| --- | --- | --- |
| local-health-recovery.candidate.sh | /usr/libexec/local-health-recovery | 0755 |
| local-health-probe.candidate.lua | /usr/libexec/local-health-probe.lua | 0644 |
| local-health-recovery.init.candidate.sh | /etc/init.d/local-health-recovery | 0755 |
| local-health-recovery.fixture.sh | 仅在隔离目录运行 | 0755 |

安装由主代理独占处理。候选不会自动安装，不改业务组件 init、UCI、DNS 上游、核心、规则、固定节点、路由或认证。

## 探针与决策

Lua 5.1 兼容探针使用现有 nixio。对 127.0.0.1:53 与 :7874 分别发送 localhost IN A，查询头为 RD=1、QDCOUNT=1，其余计数 0。connected UDP 在内核只接收对应的 127.0.0.1:port 来源；解析校验事务 ID、QR、opcode、TC、rcode、问题 name/type/class、答案边界和 localhost IN A 的 127.0.0.1 地址。未知 Lua／nixio 错误及外层硬截止退出为 UNKNOWN，暂停恢复。

UA3F 只在本地 1080 协商 SOCKS5 无认证方法，发送 05 01 00，要求 05 00。TCP 短读会累积至 2 字节，最多读两次，每次至多 2 秒，外层 timeout 5 限定整个探针总时长；没有 SOCKS CONNECT 或公网探针。此结果不证明外连及 UA 改写。

每轮完成后等待 60 秒。只在恰好一个组件连续失败 3 轮、锁内三组件重查仍为同一结果时，请求对应 init 的局部 restart。两个或三个同时失败、UNKNOWN、组件停用、固定配置偏离、init／核心更新正在执行时暂停。没有公网失败触发输入。

watcher 启动、任一 PID＋starttime 变化、init 忙碌及动作后均设置 120 秒宽限。动作之间至少 300 秒，滑动 1 小时最多 2 次，当前 /tmp 状态生命周期合计最多 6 次；失败或超时也扣预算，重启 watcher 不清预算。策略较保守，不承诺固定恢复时长。

## 锁、状态与记录

持有独立 singleton flock；动作期间父 watcher 持有与订阅更新器相同的 /tmp/lock/openclash_subs.lock，并尊重 ninjaconnector2-sub.lock fallback 目录。启动 init 的子进程关闭两把锁的文件描述符，防止业务后台进程继承；父 watcher 持有共享锁直到 init 请求结束。锁内复核配置、init、PID 和三个探针。缺 flock 时拒绝运行。

状态为 /tmp/local-health-recovery，目录 0700、umask 077。status 原子写入，events.log 最多 128 条，仅含组件、状态、uptime 秒数。无凭据、URL、响应正文、周期闪存写入或 cron。RECOVERY_REQUESTED 只说明 init 返回成功；OpenClash 可在后台继续启动，应通过后续 PID／探针和实际请求验收。

## 目标验证与安装

1. 运行 lua local-health-probe.candidate.lua selftest；DNS wire 样本必须全通过。依次运行 dns 53、dns 7874、socks 1080，均须 exit 0。每探针外层 timeout 5 秒。
2. 对 watcher、fixture 和 init 执行 sh -n，再执行 sh local-health-recovery.fixture.sh。fixture 只使用隔离输入，禁止网络和真实 init；目标有 flock 时测真实持锁，本机缺 flock 时明确使用 mock。
3. probe 只输出三端口状态。它与 watch 共享 singleton 锁，守护运行时可能空输出并 exit 0；空输出不证明健康。此时读取 /tmp/local-health-recovery/status，或用上述 timeout 5 lua 独立协议探针。check 积累状态但不执行生产动作。只有 watch 执行局部动作；fixture 的 check 只记录模拟动作。
4. 主代理确认现场 UCI 与探针通过后，保留同名已有文件，安装上述 3 个生产文件并启动独立 procd 服务。不覆盖未知文件。
5. 主代理安排单组件隔离故障，保存 PID／动作、端口、真实 LAN DNS 和代理请求。订阅锁、宽限、同时故障及外部掉线保持无动作，不停认证制造故障。

## 回退

stop／disable 新 local-health-recovery 服务，再按安装前记录恢复或移走 3 个新增文件。保留 /tmp 状态供脱敏复核；不回滚已有业务配置、不清所有锁或连接。
