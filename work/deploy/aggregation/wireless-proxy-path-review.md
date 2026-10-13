# 无线电脑固定目标代理路径复核

只读保存资料、wireless_fixed_probe.py与已结束的wireless-fixed-cases.json；没有 SSH、网络、浏览器、进程操作或共享文件修改。电脑继续使用 Wi-Fi。下列候选已经由主线执行小型预检，结果为核心链通过、Internet端点未固定，未进入大批测速。

## 结论

可以使用现有 LAN mixed SOCKS 入口，发出数字 IPv4 SOCKS 请求并保留原 HTTP Host，作为固定端点的小型预检候选。保存配置没有显式 sniffer 段，OpenClash 安装脚本的 enable_meta_sniffer／pure_ip 缺省均为 0，但没有本地完整的固定 Ninja tunnel／metadata／sniffer 源码，不能由配置静态保证私有核心不会做 IP→域名映射，也没有确认现有入口的每连接“禁止重解析”开关。只有读回这条连接实际选择 UA3FLocal、UA3F Internet socket 仍为固定数字目标，才算固定端点成功。

当前不能把 PC 低速判为校园防检测限速。相同 UA3F 改写和本机 TTL 处理下，路由器数字目标 SOCKS 组已经短窗 902.30 Mbps、三路各4个外连；它反驳“UA 重写／TTL 处理本身固定只能两三百 Mbps”的解释。PC 组还多了 Wi-Fi、OpenClash 软件处理及额外本地 TCP 段，实际 CDN 又没有固定；当前日常 650 Mbit CAKE 也不能持续承载900 Mbps应用正文。处理压力和来源差异有证据，学校检测后主动限速没有直接证据。现有结果不能将所有差额唯一归因于任何一个程序、无线硬件或防检测机制。

## 当前入口与凭据读取契约

从最新私有归档 `outputs/ax6000-mainline/private-configuration/router-tuned-final-config.tar.gz` 中只读 member `etc/openclash/Ninja.yaml`，不要误用源订阅 member `etc/openclash/config/Ninja.yaml`。前者是生成运行配置，保存形状为：

| 字段 | 值或位置 |
| --- | --- |
| mixed-port | 7893，HTTP／SOCKS 共用入口 |
| socks-port | 7891，专用 SOCKS 入口 |
| port | 7890，HTTP 入口 |
| allow-lan／bind-address／mode | true／*／rule |
| authentication | 共1项，取 `authentication[0]`，仅在私有内存中分拆用户名／密码 |
| DNS enhanced-mode | redir-host |
| sniffer | 保存生成配置没有该顶层字段 |

路由器当前 LAN 地址为192.168.31.1。上述是保存配置，不等于本轮已经新请求验证；主线实际使用前可用现有小型连接验证读取状态。凭据不可放日志、命令显示、共享结果或回显。curl可从stdin配置读取代理鉴权，避免把用户名／密码放argv；鉴权握手只通过本机家庭LAN。

## 最小数字目标预检

- PC继续用当前Wi-Fi，显式代理 `socks5://192.168.31.1:7893`，SOCKS CONNECT使用ATYP=IPv4、目的171.108.211.12:80。可用数字URL `http://171.108.211.12/filestreamingservice/files/79f6dea5-67d3-4861-94ab-0aaa9d006847/26300.9457.260913-1737.26h2_ge_release_svc_refresh_CLIENTCONSUMER_RET_x64FRE_zh-cn.esd`，同时发送HTTP `Host: dl.delivery.mp.microsoft.com`。不要以 `socks5h`＋域名或只对域名URL加 `--resolve` 代替数字CONNECT。
- 参数契约：`-q -4 --http1.1 --proxy socks5://192.168.31.1:7893 --noproxy "" --retry 0 --header "Host: dl.delivery.mp.microsoft.com" --header "Connection: close"`，固定Range、`--max-filesize`、有界connect／total timeout，输出丢弃，读取Content-Range和curl JSON。`--noproxy '*'`会绕过显式代理，不可沿用旧直连测速参数。curl的remote_ip会是代理LAN地址，不是Internet目标，不能拿它确认固定源。
- 先做一个数MiB限速预检，读取受鉴权控制的现有核心连接状态：inbound应为SOCKS，所选chain必须包括UA3FLocal；保存实际Host／destinationIP的脱敏形状。再用UA3F PID→inode→ESTABLISHED→conntrack reply确认Internet remote=171.108.211.12:80、目标出口和明显接收增长。PC到mixed端口只出现127或LAN相关socket不等于固定Internet端点成功。
- 当前数字IP没有显式IP-CIDR规则命中。保存运行规则有下载域名的TCP→UA3FLocal包装，并在后部有TCP＋GEOIP,CN→UA3FLocal。数字请求是否命中后者、是否被DNS映射回域名，必须由chain和outer读回；若未走UA3F或outer改变，停止这个可比对照，不先假定每连接有skip-sniff参数。
- 成功后可按既有12条×64MiB形状做PC无线预筛，所有对比保持相同实际数字Internet目标、对象、Range、CAKE epoch和Wi-Fi位置／链接状态。它保留OpenClash→UA3F软件路径，用于定位原透明入口的重解析和处理差异，不能宣称已绕过全部软件成本。若要验900，需主线单独管理临时CAKE off或更高预算、独立回退与最终读回；现650Mbit持续正文900不相容。短窗明显低于目标时不自动扩大数据量。

## 每连接重解析与源码边界

本地仅保存了Mihomo规则解析／逻辑／common和SOCKS出站说明，没有tunnel、metadata预处理、DNS反向映射和sniffer完整实现。`no-resolve`是规则参数，不能作为SOCKS连接级“保留数字目标”开关；HTTP Host也不能单独保证目标数字IP被保留。Ninja发布方声称同步上游5019cc090ed7cafb76643f964a76b1e97aee2985，但这不是私有二进制与公版逐行等价证明，不把其私有协议称为普通加密或公版Shadowsocks。

已保存UA3F v3.7.0 `internal__server__socks5__socks5.go` 第213～235行：先取SOCKS request address调用base.Connect，再返回SOCKS成功并将已建RConn交给ServeConnLink。数字地址确实传至UA3F时，原HTTP Host不会在这段Connect之后自动改成另一个连接；本轮路由器902.30Mbps实测也支持这一固定目标路径。最待验证的位置是PC进入OpenClash后到UA3F提交的metadata，而非已验证UA3F数字CONNECT。

## 防检测处理与成本

UA3F对选定明文HTTP改写UA，重新建立Internet TCP，因此还改变了真正进入该分支流量的TCP端点。它同时带来代理copy、用户态处理、socket和调度成本。独立nft TTL为逐包IPv4出口处理；它不负责CDN选择。HTTPS没有启用MitM，不能把其内层UA当已改写；UDP／QUIC仍另行判断。

路由器本机curl→UA3F→Internet约902Mbps，与裸出口约909Mbps处于相同快端点短窗，说明该路径有接近千兆的短时能力。无线PC→OpenClash→UA3F→Internet还有Wi-Fi收发、LAN进入核心、本地核心→UA3F TCP和额外softirq；CPU2在一个PC批次平均busy96.4%、softirq89.9%只是处理压力信号。当前RAM HTTP→PC约567～605Mbps包含uhttpd及本机处理，不能当Wi-Fi硬件上限。固定相同outer后才可区分来源与完整软件／无线成本，仍不用有线作为目标条件。
## 新脚本与已结束预检复核

`wireless_fixed_probe.py` 的数字URL、原Host、authenticated SOCKS、固定PC local-port和API sourceIP／sourcePort过滤可以确认这些PC连接进入现有核心，且没有打印凭据：proxy-user与Bearer只经stdin，结果只保留筛选后的metadata／chains和curl指标，stderr只记是否存在。保存的认证init命令只有role／account参数，未见用户名／密码作为procd命令行。没有发现本次脚本把代理鉴权写入结果或argv。

已结束预检12×8MiB全部完整。12个核心source-port均包含UA3FLocal，metadata.destinationIP均为171.108.211.12，但metadata.host均已填为dl.delivery.mp.microsoft.com；该固定目标的新增UA3F外连为0，fixed_outer_valid=false。由于每请求限速1MiB/s，98.46Mbps是限速预检的整批均值，不能作为PC吞吐上限或性能对照。程序在CAKE停用之前停止，temporary_queue_off未出现，queue_restored／pids_unchanged／cleanup_complete均为true。

这次观察说明inbound数字ATYP4不能冻结整条链后续目标。核心metadata可以同时保留原destinationIP和非空Host；SOCKS出站若根据Host形成下一段目标，UA3F收到域名便会再次解析。它与redir-host的IP→域名反向映射相符，但没有本地固定私有核心完整源码来确认具体赋值分支。保存配置没有sniffer，不能将原因直接定性为HTTP Host sniff override-destination。已证明的是实际outer未固定，不能把metadata.destinationIP当作Internet实际dial地址。

脚本的核心链门控与outer门控结合，成功避免以错误端点进行后续对照。`all_matching_outer_have_exit`和`positive_receive_growth`在空目标集合上可因all([])显示true，但`all_target_requests_observed=false`已使完整fixed_outer_valid为false，不构成本次误验收。后续报告必须继续用完整门控而不是孤立的true字段。

另两项比较边界已告知主线：fixed_outer_valid没有独立要求三个出口各有增长／同窗，三路承载应另核new_owned_outer_by_exit与route_windows；Wi-Fi身份不能只用拼接邻居／station输出中存在MAC＋authorized=yes判断，应核CLIENT IP邻居同一行对应MAC和Windows绑定IP所属Wi-Fi接口。PC→路由器UA3F→PC即使固定端点全部通过，也只比较完整额外路径成本，不能独立分离Wi-Fi与OpenClash。