# ESurfingClient 三通道源码核查

核查时间：2026 年 10 月 12 日，Asia/Shanghai。仅使用 agent-reach 的 GitHub／`gh API` 路由读公网源码、公开讨论及现有本地资料，没有连接路由器、触发认证、测速或修改生产配置。

## 结论

**ESurfingClient-CVersion 没有把 OpenWrt 认证实例数写死为两个，也没有写出“同一账号只准一台 PC 加一台手机”的规则。** OpenWrt 会读取账号数组，按可用对象启动独立认证进程。是否允许这些进程使用同一账号同时保持有效会话，由学校认证服务器及账号策略决定。

五个 `channel` 是客户端选择的协议身份，不等于服务器保证提供五个独立会话名额。源码没有服务端会话策略实现，也没有读取 `maxsession` 或设备数量上限的逻辑。Windows／Linux／macOS 是否被服务端归为同一 PC 类，Android／iOS 是否被归为同一手机类，不能只从这些枚举推断。

因此，本机第三路会干扰原会话，支持“现有组合未通过稳定共存验收”，不能升级为“所有三通道组合必然不行”；同样，五种身份能成功认证，也不能升级为“一个账号必然支持五路同时在线”。

## 固定版本与读取范围

| 对象 | 固定提交／状态 | 核查结果 |
| --- | --- | --- |
| 本机安装版本对应源码 | `cc181fdef686a1e31628f1ae3d8ec97fe6e5ad09`，`v2.1.5-r6` | 按主代理提供的安装提交核对，没有重新读取设备二进制 |
| 2026 年 10 月 12 日查询到的最新 HEAD | `cbc1f8ae2edf60abf66fe991af06698695356c0d`，提交时间 2026-10-08 09:07:43 UTC | 相对安装提交只领先一个提交 |
| 最新正式 release | `v2.1.5-r6`，发布时间 2026-10-05 15:33:43 UTC | release 标签仍与当前安装版本一致；没有升级 |

[两提交完整差异](https://github.com/BadGhost520/ESurfingClient-CVersion/compare/cc181fdef686a1e31628f1ae3d8ec97fe6e5ad09...cbc1f8ae2edf60abf66fe991af06698695356c0d)仅涉及六个文件：构建、PlatformUtils 头文件、DialerAuth、DialerClient、TimeUtil 和 Watchdog。最新提交把看门狗、心跳与会话时长的间隔计时改为单调时钟，没有增加 channel、旧 Android 选择入口或新的服务端名额设置。这项上游修正不是本机升级或本机故障根因证明。

通过 Git tree 的 blob SHA 核对，下面使用的 ConfigAccounts、Config、States、Refresh、Xml、DialerSession、DialerTicket、DialerNet、NetClientCurl 和 OpenWrt init 在两个提交中逐字节相同。正文优先链接安装提交，使结论能对应本机版本。DialerAuth 的 IP 提取部分在计时改动之前，行号与语句也未改变。

读取／检索最新提交的 103 个非第三方文本文件，覆盖全部客户端公共源码、头文件、配置前端、LuCI、init 和 Markdown 文档，排除 third_party 与算法实现目录；另读取 iOS／Windows ZSM 两个实现文件确认 `type` 的含义。对这些文件执行：

```text
max.?session|session.?max|devicename|device.?type|dev.?type|multilogin|simultaneous|maximum.sessions|最大.*会话|终端.*数量|设备.*数量|手机.*电脑|电脑.*手机|二开|三开
```

没有找到上述限制字段或规则。负结果限于这个仓库和上述固定版本，不涵盖学校 AAA／计费／认证服务器代码。

## channel 到实际请求的映射

| channel | 接受的主要名称 | 使用的 CCTP UA | 额外行为 |
| --- | --- | --- | --- |
| 1 | `windows` | `CCTP/WinSVR5/1068` | Windows ZSM 解包优先，失败再回退通用路径 |
| 2 | `linux` | `CCTP/Linux64/1003` | 主机名、ostag 随机生成 |
| 3 | `android` | `CCTP/android11_64/2104` | 主机名、ostag 随机生成；当前唯一可选 Android 身份 |
| 4 | `ios`／`iphone` | `CCTP/iOSdy/4023` | 主机名 `iPhone 14`，ostag `iPhone iOS 17.0`；首次 ZSM 使用空 POST |
| 5 | `macos`／`mac`／`osx` | `CCTP/macdy/5019` | 主机名 `MacBookPro`，ostag `macOS,14.4`；首次 ZSM 使用空 POST |

直接证据：[ConfigAccounts.c 第 16～21、32～109 行](https://github.com/BadGhost520/ESurfingClient-CVersion/blob/cc181fdef686a1e31628f1ae3d8ec97fe6e5ad09/esurfingclient/app/src/config/ConfigAccounts.c#L16-L109)、[Refresh.c 第 8～40 行](https://github.com/BadGhost520/ESurfingClient-CVersion/blob/cc181fdef686a1e31628f1ae3d8ec97fe6e5ad09/esurfingclient/app/src/states/Refresh.c#L8-L40)、[DialerSession.c 第 25～36 行](https://github.com/BadGhost520/ESurfingClient-CVersion/blob/cc181fdef686a1e31628f1ae3d8ec97fe6e5ad09/esurfingclient/app/src/clients/dialer/DialerSession.c#L25-L36)、[DialerTicket.c 第 169～243 行](https://github.com/BadGhost520/ESurfingClient-CVersion/blob/cc181fdef686a1e31628f1ae3d8ec97fe6e5ad09/esurfingclient/app/src/clients/dialer/DialerTicket.c#L169-L243)。

代码没有额外发送数字 `channel` 字段或 `devicename`／`device_type` 配置字段。它将选择结果变成 HTTP `User-Agent`、XML `<user-agent>` 及部分 `<host-name>`／`<ostag>`，并影响 ZSM 的首次请求和解包路径。实际运行平台是 OpenWrt，也能选择这些协议身份；这不证明服务端会按五种名字分配独立额度。

POST 同时带 `Client-ID`、`Algo-ID`、`CDC-SchoolId`、`CDC-Domain`、`CDC-Area` 和校验头，见 [NetClient.c 第 24～77 行](https://github.com/BadGhost520/ESurfingClient-CVersion/blob/cc181fdef686a1e31628f1ae3d8ec97fe6e5ad09/esurfingclient/app/src/clients/net/NetClient.c#L24-L77)。请求 XML 分为：

- 取 ticket：UA、client-id、主机名、IPv4、MAC、ostag、gwip。
- 登录：UA、client-id、ticket、userid、passwd。
- 心跳／登出：UA、client-id、主机名、IPv4、ticket、MAC、ostag。

这些字段均取当前实例的状态，见 [Xml.c 第 48～114 行](https://github.com/BadGhost520/ESurfingClient-CVersion/blob/cc181fdef686a1e31628f1ae3d8ec97fe6e5ad09/esurfingclient/app/src/utils/Xml.c#L48-L114)。**凭据在 LOGIN XML，GET_TICKET XML 本身没有用户名或密码。** 这修正了早期候选 README 对阶段的表述。

`auth_cfg.type` 不是 PC／phone 设备类编号；它保存动态密码模块的算法类型。iOS 实现从 JS `codex`／`cdy` 读取，Windows 实现保存 `cdy`，见 [iOS ZSM 第 548～568 行](https://github.com/BadGhost520/ESurfingClient-CVersion/blob/cc181fdef686a1e31628f1ae3d8ec97fe6e5ad09/esurfingclient/app/src/cipher/algo/ios/ios_zsm.c#L548-L568)、[Windows ZSM 第 390～402 行](https://github.com/BadGhost520/ESurfingClient-CVersion/blob/cc181fdef686a1e31628f1ae3d8ec97fe6e5ad09/esurfingclient/app/src/cipher/algo/windows/win_zsm.c#L390-L402)。

## 账号数量与实例隔离

OpenWrt 的账号数组大小用于动态分配 `prog_status_t` 数组，循环读取所有有效账号；不会按 username 去重，也没有“PC 对象只能一个、phone 对象只能一个”的条件。每个对象得到独立 idx 和配置，见 [Config.c 第 380～509 行](https://github.com/BadGhost520/ESurfingClient-CVersion/blob/cc181fdef686a1e31628f1ae3d8ec97fe6e5ad09/esurfingclient/app/src/config/Config.c#L380-L509)。

`--account N` 让一个 auth 进程只保留选中的一个对象。init 再对 `--list-accounts` 返回的每个序号启动 `accountN`，没有截至两个的判断，见 [Config.c 第 592～642 行](https://github.com/BadGhost520/ESurfingClient-CVersion/blob/cc181fdef686a1e31628f1ae3d8ec97fe6e5ad09/esurfingclient/app/src/config/Config.c#L592-L642)、[init 第 68～91 行](https://github.com/BadGhost520/ESurfingClient-CVersion/blob/cc181fdef686a1e31628f1ae3d8ec97fe6e5ad09/esurfingclient/files/etc/init.d/esurfingclient#L68-L91)。

数量及索引使用 8 位整数，存在表示范围和大数组边界，不能称为“无限实例”；这些边界不会把第三个有效对象拒绝为超出两路。

非 OpenWrt 分支在未指定序号时，只加载第一个有效账号；这是真实的默认行为限制，但它不是服务器“一 PC 加一手机”限制，见 [Config.c 第 513～585 行](https://github.com/BadGhost520/ESurfingClient-CVersion/blob/cc181fdef686a1e31628f1ae3d8ec97fe6e5ad09/esurfingclient/app/src/config/Config.c#L513-L585)。

| 信息 | 实例独立程度 | 不能据此证明的事情 |
| --- | --- | --- |
| client-id | 每轮状态刷新生成随机 UUID，存进当前实例的 auth_cfg | 新 UUID 不等于增加账号会话额度 |
| 协议 MAC | 每轮刷新随机生成，存进当前实例；不是直接读取真实网卡 MAC | XML MAC 独立不等于真实二层 MAC、DHCP 或出口独立 |
| 主机名／ostag | Windows／Linux／Android 随机；iOS／macOS 为固定型号字符串 | 同一个型号名字不表示共用内存；随机名字不表示独立服务器名额 |
| client_ip／ac_ip | 从当前实例取到的 ticket-url 中提取 `wlanuserip`／`wlanacip` | 代码不会凭空创建第三 DHCP 地址；走错出口可取到同一通路信息 |
| ticket／keep-url／term-url／cipher | 位于当前实例 auth_cfg；取票据与登录响应分别填入 | 服务端仍可按账号或设备类替换／终止另一个会话 |
| 登出存档 | `<配置路径>.<账号序号>.logout`，按 idx 分开 | 重复启动相同 idx 的进程会用相同存档路径，不能当成额外账号实例 |

直接证据：[States.h 第 80～141 行](https://github.com/BadGhost520/ESurfingClient-CVersion/blob/cc181fdef686a1e31628f1ae3d8ec97fe6e5ad09/esurfingclient/app/include/states/States.h#L80-L141)、[Refresh.c 第 42～82 行](https://github.com/BadGhost520/ESurfingClient-CVersion/blob/cc181fdef686a1e31628f1ae3d8ec97fe6e5ad09/esurfingclient/app/src/states/Refresh.c#L42-L82)、[DialerAuth.c 第 79～98 行](https://github.com/BadGhost520/ESurfingClient-CVersion/blob/cc181fdef686a1e31628f1ae3d8ec97fe6e5ad09/esurfingclient/app/src/clients/dialer/DialerAuth.c#L79-L98)、[DialerTicket.c 第 15～62 行](https://github.com/BadGhost520/ESurfingClient-CVersion/blob/cc181fdef686a1e31628f1ae3d8ec97fe6e5ad09/esurfingclient/app/src/clients/dialer/DialerTicket.c#L15-L62)、[DialerNet.c 第 118～213 行](https://github.com/BadGhost520/ESurfingClient-CVersion/blob/cc181fdef686a1e31628f1ae3d8ec97fe6e5ad09/esurfingclient/app/src/clients/dialer/DialerNet.c#L118-L213)、[LogoutState.c 第 13～28、104～128 行](https://github.com/BadGhost520/ESurfingClient-CVersion/blob/cc181fdef686a1e31628f1ae3d8ec97fe6e5ad09/esurfingclient/app/src/utils/LogoutState.c#L13-L128)。

OpenWrt 的 HTTP socket 按对应账号写 `SO_MARK`，见 [NetClientCurl.c 第 85～110 行](https://github.com/BadGhost520/ESurfingClient-CVersion/blob/cc181fdef686a1e31628f1ae3d8ec97fe6e5ad09/esurfingclient/app/src/clients/net/NetClientCurl.c#L85-L110)。正确的策略路由、独立 DHCP 地址及当前本机的 GID 约束仍是多路验收的前提；单独选择 channel 不会完成这些隔离。

## 旧 Android 与第三路的边界

`OLD_ANDROID_UA` 确实在第 18 行定义为 `CCTP/android64_vpn/2093`，但 channel 3 在第 92～95 行只使用新 `ANDROID_UA`，没有旧／新 Android 子选项，也没有从用户配置读取自定义 UA 的入口。数值只能 1～5，字符串只能五类名称及别名。

旧 Android 的算法文件仍在源码树，**CipherFactory 中对应分派第 19～95 行已经全部注释并标为弃用**，见 [CipherFactory.c 第 19～95 行](https://github.com/BadGhost520/ESurfingClient-CVersion/blob/cc181fdef686a1e31628f1ae3d8ec97fe6e5ad09/esurfingclient/app/src/cipher/CipherFactory.c#L19-L95)。不能将这些文件或未使用的 UA 常量解释为当前安装版已支持新／旧 phone 双身份。

其他项目声称 PC＋新 phone＋旧 phone，可以作为新的核查线索；它的旧 phone UA、算法、请求字段和服务器行为必须按其固定源码确认。当前 CVersion 的旧常量是 2093，不是其他项目所述的 2089。仅把 UA 改为另一个编号，既不能证明协议兼容，也不能证明广东药科大学当前账号允许第三个并存会话。本轮不提出未验证的生产替换或身份伪造方案。

## 服务端限制：已有线索与未知事实

维护者在 [Issue #8 的 2026 年 4 月 29 日回复](https://github.com/BadGhost520/ESurfingClient-CVersion/issues/8#issuecomment-4346972824)中说，当时自己使用双 WAN，三 WAN 及以上尚未测试。这是维护者实测范围声明，不是客户端或服务器最多两个的规则。更早的“最多拿两个 IP”讨论属于 2026 年 1 月开发中的旧逻辑，不能覆盖当前动态账号数组实现。

[PR #39](https://github.com/BadGhost520/ESurfingClient-CVersion/pull/39)提交者报告三个 iOS“账号”可取 ZSM、ticket、登录和心跳，没有明确证明同一账号的三个并存会话，更没有指定广东药科大学。不得把“3 个账号”换成“同一个账号三路”。

项目没有给出本校账号的 `maxsession`、PC／phone 分类表、同类替换策略或套餐速率。当前 login 仅从解密响应读取 keep-url、term-url、keep-retry，HTTP 头回调只处理学校信息和重定向，不解析专用会话上限错误。泛化的 HTTP 超时、取票据失败或解析失败不足以识别服务端限制原因。

**推断：** 如果第三次新认证后另一个同类会话被立即终止，而三个源地址和所有控制流量出口均已独立，现象与服务器按设备类替换旧会话或按账号限制总会话数相容。它仍可能涉及服务器会话回收、客户端检测路径、路由或协议差异，需对应响应与时间线区分。随机 MAC、随机 client-id 或换一个 OS 名称本身不能排除服务端账号限制。

## 可以继续推进的明确条件

1. 先只读取得广东药科大学当前账号／套餐允许的同时在线数量及设备分类说明，或已有脱敏认证响应中的明确策略／拒绝原因。没有这项证据时，保持“本机现有组合未通过”，不下“一 PC 加一手机是硬上限”的结论。
2. 若继续核查旧 phone 路径，须先固定候选项目提交，确认它实际实现的 UA、ZSM、加密与请求流程，并确认“三通道”描述是否明确指同一个账号、同一学校、同时保活及逐源外网有效。认证成功一次或不同账号的测试不够。
3. 只有在候选可实现且服务端允许范围明确后，再制定有回退的受控试验：三个真实源地址和控制出口独立，三个对应 PID 均完成新 AUTH；观测至少各两轮成功 heartbeat、逐源外网请求、原两路未被替换；出现原会话被终止或明确额度拒绝即停止候选。该条件清单不是本轮认证操作授权，本轮没有执行。
4. 若学校确认账号总额度就是两个，新增同账号身份没有已证实的成功依据。可继续核查学校提供的套餐升级或合法额外会话服务，以及现有两路的实际瓶颈；本源码报告没有测得套餐上限，也不把第三路认证次数当作带宽保证。

Agent Reach 本轮更新检查：本机 v1.5.0，检查结果为最新；未更新工具。
