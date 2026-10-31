# Windows No SMPS 单项 A/B/A 试验

[Set-WirelessSmpsTrial.ps1](Set-WirelessSmpsTrial.ps1) 默认执行 `DryRun`，只读取当前网卡的高级属性，不改设备、不写快照、不启动子进程。主线在 [windows-current-state.json](windows-current-state.json) 已保存本机 BE200 的真实中文选项：`自动SMPS`、`静态SMPS`、`动态SMPS`、`无SMPS`，RegistryKeyword 为 `MIMOPowerSaveMode`；现值是 `自动SMPS`，U-APSD 为 Disabled。本支线没有重复查询设备或执行修改。No SMPS（本机显示 `无SMPS`）仍是需要对照验证的候选，不能预先称为根因或修复。

脚本只识别当前驱动公开的唯一 SMPS 属性，以及 `ValidDisplayValues` 中明确等于英文 `No SMPS` 或本机简体中文 `无SMPS` 的选项；仅忽略首尾空白和英文大小写，不做模糊翻译或局部匹配。脚本从同一个对象读取显示值、完整 `RegistryValue` 数组和可选值对应关系；修改目标使用驱动真实字符串执行 `Set-NetAdapterAdvancedProperty -DisplayName ... -DisplayValue ...`，本机不会被替换成英文显示值。恢复使用该正规 cmdlet 和保存的完整原值。名称不唯一、原值 / 选项不完整或值映射不一致时停止，没有预设 SMPS 数值，也没有直接访问注册表。[Microsoft：Get-NetAdapterAdvancedProperty](https://learn.microsoft.com/en-us/powershell/module/netadapter/get-netadapteradvancedproperty)、[Set-NetAdapterAdvancedProperty](https://learn.microsoft.com/en-us/powershell/module/netadapter/set-netadapteradvancedproperty)

## 授权与执行边界

目前主线为非管理员。`Trial`、`Rollback` 和 `Accept` 必须在已经获得授权的管理员 PowerShell 7 中执行；非管理员调用会在读取 / 保存试验快照和设备修改之前停止。脚本不会自行请求 UAC、安装软件、改执行策略、建立任务计划或服务。主线在获得 UAC 授权后独立启动管理员进程；用户处理 UAC 界面，Agent 不绕过它。

高级属性修改通常需要网卡重启。脚本省略 `-NoRestart`，让正规 cmdlet 完成必要操作，因此 WLAN 可能短暂断开。设置后的读回只验证驱动公开属性，不能代替重新关联、地址恢复、LAN / 互联网业务及认证读回。[Microsoft：Set-NetAdapterAdvancedProperty 的 NoRestart 参数](https://learn.microsoft.com/en-us/powershell/module/netadapter/set-netadapteradvancedproperty#-norestart)

一次只改 SMPS。保持 U-APSD Disabled、TCP 自动调节 Normal、heuristics Disabled、已工作的 IPv4 / IPv6 RSC，以及其他无线、路由器、认证和限速设置。Trial 期间不能同时进行另一项 WLAN 修改。快照仅保存 SMPS 白名单字段、网卡名称和说明；不保存或输出整个 CIM 对象、SSID、MAC、GUID 或设备实例路径。参数必须是单个精确网卡名称，不能使用通配符。

## 参数和状态

| 参数 / Action | 行为 |
| --- | --- |
| 无 Action，或 `-Action DryRun` | 只读匹配当前真实属性，输出 `DryRunNoChanges`。可在非管理员窗口运行；无文件和子进程副作用 |
| `-Action Trial` | 保存原值；启动隐藏、独立的管理员回滚进程；回滚进程确认就绪后才改 No SMPS；读回成功后输出 `TrialReadbackPassedRollbackArmed` |
| `-StatePath` | 本地已有目录中的 JSON 路径。默认是脚本旁的 `smps-trial-state.json`。新 Trial 不覆盖已有快照或日志；每轮使用新路径 |
| `-RollbackAfterSeconds` | 自动还原期限，默认 300 秒，允许 60～3600 秒。从原值快照建立时开始计时，不从测速开始计时；需要在 B 完成前预留还原时间 |
| `-Action Rollback -StatePath ...` | 从独立快照准确恢复原值并读回；不依赖发起 Trial 的进程。已是原值时只读回；Accept 后仍可 Rollback |
| `-Action Accept -StatePath ... -ConfirmAccept` | 明确保留 No SMPS。若已经 Rollback 并完成 A/B/A，会重新应用 No SMPS 后读回；若仍在 B，就保留 B 并取消自动还原。缺少 ConfirmAccept 时不改变设备或取消还原 |
| `-Action Watchdog` / `-WatchdogToken` | 内部回滚进程参数，由 Trial 生成并调用；主线不要手工调用 |

运行 Trial 时生成原值 JSON、`.watchdog-ready`、`.watchdog.stdout.log` 和 `.watchdog.stderr.log`。JSON 始终保留 Original；状态更新使用同目录替换文件。独立回滚进程按 UTC 期限检查状态，并用同一网卡互斥锁与 Rollback / Accept 串行操作；它通常在 Accepted / Restored 后自行退出。不要删除或改写活动快照和这些文件。

正常 Trial 自动还原状态为 Restored。若驱动设置、读回或还原失败，输出明确失败并尝试还原；未确认恢复时保留 RollbackFailed 和原快照。当前值变成第三个值、网卡说明、属性名称或驱动选项变化时停止，不覆盖其他操作。该保护意味着发生冲突后必须由主线确认当前对象，再从可靠原值处理。

独立进程可在发起 Trial 的脚本结束后继续计时，但不是 Windows 服务或启动任务。关机、注销、进程被终止、设备消失或管理员会话受到进程管理限制时，不能保证自动回滚；原快照仍是手工 Rollback 的恢复入口。计时器就绪信号只证明进程已进入计时逻辑，不能证明未来的设备还原一定成功。跨 Windows 登录会话、网卡重命名 / 替换或驱动更新后，不应沿用旧快照。

## 执行 A → B → A

以下命令以本任务工作区为执行位置，在 PowerShell 7 中使用。路径与网卡名称应由主线核对；当前已有网卡名称为 WLAN。目录已存在，脚本不会自动创建目录。

```powershell
$smpsScript = 'C:/Users/Shizuku/Documents/Codex/2026-10-12/za/work/deploy/wireless-repair/Set-WirelessSmpsTrial.ps1'
$smpsState = 'C:/Users/Shizuku/Documents/Codex/2026-10-12/za/work/deploy/wireless-repair/smps-trial-01.json'
$smpsPwsh = Join-Path $PSHOME 'pwsh.exe'

# 只读预检；可在当前非管理员窗口运行。
& $smpsPwsh -NoLogo -NoProfile -NonInteractive -File $smpsScript -AdapterName 'WLAN'
```

1. 在原值 `自动SMPS`（Auto SMPS）下完成 A。复用主线相同纯 LAN 发送器、总字节、并发、位置、电源状态和路由器状态，确认完整正文。停止 A 后再切换。不要把 PHY 2402 Mbps 当作正文结果。
2. 在已获授权的管理员 PowerShell 7 中执行 Trial。检查返回 JSON 的 Status、StatePath、RollbackDeadlineUtc 和 CurrentDisplayValue；只有读回驱动真实目标值 `无SMPS` 且主线确认 WLAN / 业务重新正常后，才开始 B。

```powershell
& $smpsPwsh -NoLogo -NoProfile -NonInteractive -File $smpsScript -Action Trial -AdapterName 'WLAN' -StatePath $smpsState -RollbackAfterSeconds 300
if ($LASTEXITCODE -ne 0) { throw 'Trial 未完成；先检查快照并恢复，不能开始 B。' }
```

3. 在期限前完成 B，使用同一 LAN 测试条件和完整正文；保存每秒速率、CPU / DPC、AP 速率与重试增量以及网卡错误 / 丢弃增量。试验脚本不包含测速或压测。B 不完整、明显退化或断连时，立即停止自己的测试并执行 Rollback。
4. 不等待计时器，直接从快照执行 Rollback；读回原值并确认 WLAN / 业务正常后，再完成第二次 A。自动回滚已经完成时，显式 Rollback 可以再次确认原值。

```powershell
& $smpsPwsh -NoLogo -NoProfile -NonInteractive -File $smpsScript -Action Rollback -StatePath $smpsState
if ($LASTEXITCODE -ne 0) { throw '没有确认原值恢复；停止后续测试。' }
```

只有 B 的提升超过前后 A 的自然波动，且没有连接、重传或延迟退化，才支持保留候选。由主线检查完整 A/B/A 证据并决定是否明确 Accept；不要在第一项 B 峰值出现时自动保留。通过单项 LAN 对照后仍需无线 PC 的正式下载验收，不能由属性读回或一次峰值代替 900 Mbps 目标。

```powershell
# 仅在主线决定保留后执行；会把已恢复的“自动SMPS”再改为“无SMPS”。
& $smpsPwsh -NoLogo -NoProfile -NonInteractive -File $smpsScript -Action Accept -StatePath $smpsState -ConfirmAccept
if ($LASTEXITCODE -ne 0) { throw 'Accept 未完成；先确认原值 / 目标值状态。' }

# 后续撤销保留仍使用同一个原快照。
& $smpsPwsh -NoLogo -NoProfile -NonInteractive -File $smpsScript -Action Rollback -StatePath $smpsState
```

上面的命令均以独立 PowerShell 7 进程调用，因此 `$LASTEXITCODE` 对应本次调用。独立进程成功退出码为 0，失败为 1；返回 Status 是实际是否改动的进一步判据。原值已经是 No SMPS 时 Trial 返回 `AlreadyNoSmpsNoChanges`，不创建新快照或计时器，此时没有可比较的 SMPS 变化，应跳过该项。

## 当前交付的验证范围与来源

本次只创建脚本和操作文档，没有运行脚本查询设备、触发 UAC、更改系统、启动计时器或压测。交付检查限于 PowerShell 语法、静态控制流程和模拟属性数据；真实 NetAdapter cmdlet 的管理员执行、网卡重启、读回、独立计时还原与性能收益均由主线在授权窗口验收。

Intel 说明 No SMPS 保持接收天线活动，也提示部分 AP 的 SMPS 互操作问题可能影响吞吐；该说明不能单独证明 AX6000 / BE200 当前存在同一问题。[Intel：Advanced Intel Wireless Adapter Settings](https://www.intel.com/content/www/us/en/support/articles/000005585/wireless/legacy-intel-wireless-products.html)

相关路径结论与限速 / 外层连接边界见 [windows-path-analysis.md](windows-path-analysis.md) 和 [wifi-path-analysis.md](wifi-path-analysis.md)。本次复用已有 Intel 证据，并通过 Agent Reach 的网页读取通道核对 Microsoft Get / Set cmdlet 的真实参数与重启说明；没有安装或升级工具。
