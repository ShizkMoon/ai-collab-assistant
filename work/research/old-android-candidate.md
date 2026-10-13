# 旧 Android 2089 候选核对

2026-10-12，Asia/Shanghai。使用 agent-reach 的 GitHub／gh API 路由，只读固定源码与 README，没有编译、安装、连接设备、认证或测速。

## 结论

**EchoPing07/Esurfing-go-webui 的旧 Android 2089 有实际认证与旧代算法实现，不能把它归为只改 UA 的占位功能。** 代码将指定 UA 用于 HTTP 和 XML，按服务器返回的 Algo-ID 选择旧代算法，执行加密取票据、登录、心跳和登出。它可以继续作为协议候选核查；这不证明广东药科大学当前账号允许三路同时在线。

**没有找到作者明确报告同一个账号的 PC＋新 Android 2104＋旧 Android 2089 三会话同时共存。** README 的 L3 只报告三种通道各自完成真实服务器全链路验证，没有给出同账号、三个同时在线会话、持续观察时长或三路独立外网的证据。

## 固定版本

- [HEAD 2b5309d2f93b2b0889693ff96b52f37a201aa55a](https://github.com/EchoPing07/Esurfing-go-webui/commit/2b5309d2f93b2b0889693ff96b52f37a201aa55a)，2026-09-07 02:56:15 UTC，提交主题为声明永久停止维护。
- [README 第 4 行](https://github.com/EchoPing07/Esurfing-go-webui/blob/2b5309d2f93b2b0889693ff96b52f37a201aa55a/README.md#L4)说明本学期校园网运营商调整，无法继续实际测试，因此永久停止维护。GitHub archived 字段为 false，不应写成已归档。

## 2089 实现证据

| 路径 | 固定源码证据 | 可确认的行为 |
| --- | --- | --- |
| UA 与 XML | [xml.go 第 13～25、119～167 行](https://github.com/EchoPing07/Esurfing-go-webui/blob/2b5309d2f93b2b0889693ff96b52f37a201aa55a/xml.go#L13-L167) | 2089 为真实预设；取票据、登录和状态报文统一调用 currentUA |
| 完整认证 | [auth.go 第 43～116 行](https://github.com/EchoPing07/Esurfing-go-webui/blob/2b5309d2f93b2b0889693ff96b52f37a201aa55a/auth.go#L43-L116) | 每次 UA 尝试重置独立会话，重新获取学校配置、IP、Algo-ID，选择加密器，再取 Ticket 和 Login |
| 旧代算法 | [cipher.go 第 22～59 行](https://github.com/EchoPing07/Esurfing-go-webui/blob/2b5309d2f93b2b0889693ff96b52f37a201aa55a/cipher.go#L22-L59)；[ZUC 第 583～610 行](https://github.com/EchoPing07/Esurfing-go-webui/blob/2b5309d2f93b2b0889693ff96b52f37a201aa55a/cipher.go#L583-L610) | 注册九个旧代 GUID，包含 README 实战所称 B809531F 的 ZUC，具有 Encrypt／Decrypt 实现 |
| 实际加解密调用 | [xml.go 第 177～218 行](https://github.com/EchoPing07/Esurfing-go-webui/blob/2b5309d2f93b2b0889693ff96b52f37a201aa55a/xml.go#L177-L218) | 发送前调用选中算法 Encrypt，HTTP 响应调用 Decrypt；不是仅发送 UA |

以上是源码路径确认，没有运行算法测试，也没有独立复现作者 L3 实测。

## 每接口绑定与恢复

- [manager.go 第 617～641 行](https://github.com/EchoPing07/Esurfing-go-webui/blob/2b5309d2f93b2b0889693ff96b52f37a201aa55a/manager.go#L617-L641)为每个 ManagedClient 构造单独 Config、context 和 Client，包括账号、UA、BindInterface。
- [utils.go 第 221～273 行](https://github.com/EchoPing07/Esurfing-go-webui/blob/2b5309d2f93b2b0889693ff96b52f37a201aa55a/utils.go#L221-L273)将源 IP 和设备绑定回调用于该客户端 HTTP transport；[utils_linux.go 第 20～38 行](https://github.com/EchoPing07/Esurfing-go-webui/blob/2b5309d2f93b2b0889693ff96b52f37a201aa55a/utils_linux.go#L20-L38)实际调用 SO_BINDTODEVICE。设备缺失或 setsockopt 失败会静默退回源 IP 绑定，部署前仍须验证真实出接口，不能只凭配置字段断言绝不串线。
- [session.go 第 10～42 行](https://github.com/EchoPing07/Esurfing-go-webui/blob/2b5309d2f93b2b0889693ff96b52f37a201aa55a/session.go#L10-L42)会话文件按接口 name 存储，保存独立的 ClientID、MAC、IP、AlgoID、Ticket、UA 和绑定设备；[manager.go 第 705～722、762～769 行](https://github.com/EchoPing07/Esurfing-go-webui/blob/2b5309d2f93b2b0889693ff96b52f37a201aa55a/manager.go#L705-L769)按同一 name 保存／恢复。
- [client.go 第 580～627 行](https://github.com/EchoPing07/Esurfing-go-webui/blob/2b5309d2f93b2b0889693ff96b52f37a201aa55a/client.go#L580-L627)恢复原 UA 与会话字段，重建加密器，并以一次成功心跳作为恢复成功条件。UA 或 username 更新时，[manager.go 第 478～481 行](https://github.com/EchoPing07/Esurfing-go-webui/blob/2b5309d2f93b2b0889693ff96b52f37a201aa55a/manager.go#L478-L481)删除原接口存档以强制重新认证。

## 作者实测的边界

[README 第 371～378 行](https://github.com/EchoPing07/Esurfing-go-webui/blob/2b5309d2f93b2b0889693ff96b52f37a201aa55a/README.md#L371-L378)的 L3 行给出月份 2026-09 和 PC、新 phone、旧 phone 三类对应 GUID。它没有写同账号、同时共存、学校名称或观察时长。[xml.go 第 15～18 行](https://github.com/EchoPing07/Esurfing-go-webui/blob/2b5309d2f93b2b0889693ff96b52f37a201aa55a/xml.go#L15-L18)补充“本校实测 2026-09-03”，并在 2089 注释写本校＋WYU；仍未给出本校名称、WYU 的展开、共存时长或本校同账号三路证据，不能改写为广东药科大学实测。

检索范围为固定 HEAD 的 README、xml.go、client.go、cipher.go、utils_linux.go、utils.go、manager.go、session.go、auth.go、request.go、config.go。README 检索同账号／同时／共存／三拨／多拨／学校／时长，仅命中多接口管理和三协议全链路表述。公开 issue 仅一个，[Issue #1](https://github.com/EchoPing07/Esurfing-go-webui/issues/1)在 2026-08-31 报旧算法失效，2026-09-05 关闭；它没有并发额度证据，也不能覆盖后续 HEAD 的新算法说明。

下一步若继续候选路线，需要先确认本校账号允许的同时在线数量，再按三个独立源地址、控制出口、持续心跳和原两路保持在线设计受控试验。当前核对不构成部署或试验授权。
