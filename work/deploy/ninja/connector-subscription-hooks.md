# Ninja Connector 2 的订阅保存与持久更新入口

核对版本：1.1.0-r4 APK 的实际 controller、UCI 和 ninja_sub.sh。没有读取 private 或连接路由器。

## 实际 UCI 字段

```text
ninjaconnector2.main=ninjaconnector2
ninjaconnector2.main.sub_url=<已授权 HTTPS 订阅 URL>
ninjaconnector2.main.sub_name=Ninja
ninjaconnector2.main.mirror=''
openclash.config.config_path=/etc/openclash/config/Ninja.yaml
```

sub_name 是文件主名，大小写需与实际源 Ninja.yaml 匹配。不要在此填写 .yaml 扩展名（helper 会去掉）；不要填路径。mirror 仅影响内核 GitHub 下载，与订阅无关。没有账号密码字段，不需要账户密码。

配置文件 /etc/config/ninjaconnector2 权限为 0600，父目录使用系统原权限。主代理将授权 URL 通过私密文件或 UCI 输入流写入，禁止公开 `uci show ninjaconnector2`、status?details=1 或记录值；这两种读回会返回完整 URL。读回只检查字段存在、URL scheme 与长度等布尔/计数信息。

controller 的下载按钮会保存 sub_url 与 sub_name，删除 sub_ua，再调用 helper。ninja_sub.sh 硬编码默认 UA 为 clash-ninja/v2.4.0，不读取 main.sub_ua。无需设置 sub_ua，也不要以为设置它会覆盖默认。helper 的第三个位置参数可显式传 UA，但 LuCI 当前不传，使用这个默认值。

## 下载与定时能力

插件只有两个业务操作：内核 install、订阅 download。它没有原生 cron、init 或定时更新字段。订阅 helper 下载后保存 0600 源 YAML；只在 openclash.config.config_path 为空时设置路径，不会替换已有路径选择，也不重启 OpenClash。因此先设正确源路径，避免下载到 ninja.yaml 却仍在运行 Ninja.yaml。

helper 提供互斥锁、200 HTTP 检查、proxies/proxy-providers 字段检查、验证旧文件备份和同目录原子替换，但没有 Ninja 协议检查，也没有内核 -t。`OPENCLASH_INIT` 变量只检查 OpenClash 是否已安装，当前脚本没有 restart 调用。

不要把内核 install 合并进定时任务。当前核心已持久安装，guard 会明确拒绝 install；定时源更新不触发 kernel.status。可用 status 的 core_exist/core_ver 判断内核是否存在，kernel_status 是上一次安装动作结果，不能拿它表示订阅更新状态。首次安装旧状态若误导，可删除仅 /tmp/ninjaconnector2/kernel.status；不要把被阻止的更新伪造为成功。

## 最小持久更新 hook

推荐复用主代理已经通过 HTTPS/证书/固定 UA 验收的下载方法，生成一个私密读取 UCI 的小脚本 /etc/openclash/custom/ninja-subscription-update.sh。不需要新守护服务。该脚本的行为顺序：

1. 用相同互斥锁防止与手动更新重叠；从 main.sub_url/main.sub_name 读取授权 URL 与 Ninja 文件主名，URL 不作为 cron 内容或可见命令参数。
2. curl 固定 `User-Agent: clash-ninja/v2.4.0`、保持证书校验，限定 HTTPS 和 HTTPS redirect；通过 `curl --config -` 的 stdin 传 URL（先拒绝控制字符，再转义双引号与反斜杠），不使用 `curl <完整URL>` 命令参数。失败返回时保留现有源文件。
3. 下载到权限 0600 的同目录候选文件；要求 HTTP200、YAML数组合法且有 ninja 类型节点，使用持久固定核心 `clash_meta -t -d /etc/openclash -f <candidate>`。stdout/stderr进入受限临时文件，公开只报状态/退出码；不打印订阅 URL、节点凭据或许可内容。
4. 内容未变则退出，不重启。变化时验证备份、原子替换 /etc/openclash/config/Ninja.yaml；源仍是服务端 Ninja 订阅，不把生产覆写写回源。
5. 服务当前 enable=1 且 config_path 恰指向该源才触发 `/etc/init.d/openclash restart`。custom overwrite 生成 UA3F TCP 路径，start_run_core 的许可恢复从新源读回最新 #!PASS 元数据。首次确认对源的改动已使 /tmp/openclash.change 失效；必要时只移除这个单一缓存文件。
6. 只写 `/tmp/ninjaconnector2/sub.status` 的脱敏状态，更新失败保留旧运行。内核不变；生产hook/options和许可restore不变。

若主代理选择直接扩展原 helper，可新增 `download_saved` 命令从 UCI 读取字段，并把 curl URL 改为 stdin config，再插入 Ninja类型/-t检查和条件 restart。原 helper SHA256 为 9dac7b57e168b633d7f7693fe54fbc307ea0aef9dae435b266e5bd1f563b06e0。修改前核验/备份；Connector升级会覆写该包管理文件，所以独立 custom 小脚本更易保留。

cron 只保存固定脚本路径，不含授权 URL。时刻由主代理按用户的更新意图选择，先手动成功一次再启用；例如每天 04:17 的形式为 `17 4 * * * /etc/openclash/custom/ninja-subscription-update.sh >/dev/null 2>&1`。这里只给格式，没有添加或启用计划。不要同时开启原版 OpenClash 订阅 cron 和此计划。

## 原版 OpenClash scheduler 的字段及边界

原版可配置 config_subscribe section 的 name=Ninja、enabled=1、sub_convert=0、address=<URL>、sub_ua=clash-ninja/v2.4.0，并由 openclash.config.auto_update 等字段调度。其 openclash.sh 在 config_download() 中 LOG_INFO 下载 URL，且使用 converter 时可能记录拼装URL；所以当前私密授权 URL 不推荐直接走该入口。sub_convert 必须为 0，不把 Ninja 私有协议提交给外部 converter，也不让默认 clash-verge UA产生普通 Mihomo订阅。

本机仅核查当前源码。持久 scheduler 不是 Connector 原生能力；主代理需手动验收一次下载、候选校验、原子替换、hook重新生成和重启后实际代理流量，再决定启用计划。
