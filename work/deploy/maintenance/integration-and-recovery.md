# 订阅容量检查与成对恢复

本候选只补手动 Ninja 订阅更新的资源检查。核心版本、自动计划和生产网络设置沿用现状。容量检查不下载订阅、不输出配置内容，也不写入闪存。

## 更新事务的接入位置

1. 在已固定的 helper 中 `require_relative 'ninja-capacity'`，创建 `NinjaCapacity::Guard.new(@opt.fetch('capacity', {}))`。可选 `capacity` 仅接受 `overlay_reserve_bytes`、`tmp_reserve_bytes`、`memory_reserve_bytes` 三个整数；默认分别为 4、32、64 MiB。
2. 源路径、启用状态和运行状态确定后，先用 `File.size` 调用 `predownload!`，再读取旧源和旧生成配置、开始下载。下载前 overlay 只检查预留，因为实际候选与投影大小仍未知。`/tmp` 检查还计入 2 MiB 订阅、8 MiB 投影和 2 MiB scratch；内存检查计入这些文件的四倍工作预算。
3. 下载候选、投影和探测文件改用 `/tmp` 下本事务独占的目录：原子 `Dir.mkdir(..., 0700)`，文件用 `File::EXCL` 与 `0600`，退出后只清理已登记路径。不要根据外部名称拼接清理目录。
4. 保持原子发布临时文件与目标位于同一个 overlay 目录。临时下载迁至 `/tmp` 后，`File.rename(candidate, @source)` 会跨文件系统失败；应改为原 helper 的 `atomic(@source, @new)`。`atomic` 必须独立使用同目录 `.ninja-update.*` 文件，不能复用迁至 `/tmp` 的普通 `temp` 方法。
5. 发布前，在原有文件、hook、UCI、运行状态复核之后，再调用 `precommit!`。参数为 `old_source_bytes`、`old_generated_bytes`、`candidate_bytes`、`projected_bytes`、`active`；只有 `active: true` 时计入旧生成与重生成。此检查完成后才创建持久备份和写新源。读取投影正文前先检查其大小不超过 8 MiB。
6. 捕获 `NinjaCapacity::Failure`，公开状态只返回 `ERR:<code>`。低容量拒绝发生在持久备份、源提交和重启之前。原有信号、共享锁和回滚继续保留。

发布阶段 overlay 的额外峰值按 `2S + 2G + C + P + 64 KiB + 4 MiB` 计算，所有文件向上取整到 4 KiB 块。`S` 为旧源，`G` 为旧生成，`C` 为新源，`P` 为新生成上界。上界取 `2 × 投影大小 + 256 KiB`；这为原版 OpenClash 调整全局字段留出空间，不假定生成文件与投影完全相同。两个 `S`、两个 `G` 分别覆盖新备份与失败回滚的原子写入。已经存在的旧备份不计作可回收空间。

当前脱敏快照的 overlay 可用 14,204 KiB，`/tmp` 可用 240,028 KiB，MemAvailable 为 201,264 KiB；旧源 217,052 B、旧生成 289,026 B。用相同大小的新源与投影演算时，发布需 overlay 6,336,512 B，下载前需 `/tmp` 44 MiB、内存约 107.9 MiB。正式接入后应由目标 Ruby 再读实时快照。检查只证明执行时的资源余量，不预留空间，也不限制其他进程；超出投影上界的原版行为或检查后的外部资源竞争仍可能触发已有回滚。

`run` 的 stderr、核心 `-t` 原始输出应直接丢弃，不创建携带订阅详情的原始日志。健康请求的正文使用 `/dev/null`；控制 API 的返回仅在内存中解析，并把 `curl --max-filesize` 限为 1 MiB。每次准备状态重试不要累计留存探测正文。固定订阅下载维持独立的 2 MiB 上限。

## 已有日志边界

本机读回：OpenClash `log_size=512`、`log_level=0`，系统 `log_size=128`，`/tmp/openclash.log` 约 364 KiB，没有 flash log 配置。已安装 watchdog 使用 `/tmp/openclash.log`，超过设置大小后清空；检查在 watchdog 循环中进行，因此不是任意瞬间都严格小于 512 KiB。日志已有内存存储与周期清理，本候选不再添加轮转任务或闪存日志。

## 成对恢复次序

1. 从同一份 `tuned-backup-manifest.json` 选取 config、runtime 两个归档，先核对文件长度和 SHA256；不能混用不同状态的两个归档。保留现有生产文件与当前可恢复备份。
2. 先在 `/tmp` 独占目录做隔离演练：校验归档成员路径、类型和链接，展开到 `config/`、`runtime/` 两个子目录；将绝对 symlink 转为该子目录内部相对链接。核对清单里的 18 个必需运行文件、许可恢复 helper、配置文件和固定核心的摘要。演练不得执行解包所得脚本、不得启动核心、不得覆盖 `/etc`、`/usr` 或改变服务。
3. 真正恢复须先确定同型号、同 OpenWrt 基线与软件包版本，并保留有线管理和本地恢复材料。恢复系统与软件包以后，再恢复同一对 config/runtime；否则包升级可能覆盖自定义 init、LuCI、订阅入口和更新禁用保护。
4. 先恢复网络、认证与 UA3F/MWAN 的配置和必要程序，再恢复固定核心、Ninja 源与生成配置、生产 hook、许可恢复和安全订阅 helper。最后恢复 hotplug、无线 steering 与标准更新入口的保护。标准 config 归档缺少定制 hotplug，不能省略 runtime。
5. 先检查文件权限与全部摘要，再做 shell/Ruby 语法、核心版本和 `-t` 校验；然后依次启动认证、DNS／防火墙／MWAN、OpenClash，读回真实 WAN 出口、国内／代理 HTTPS 与所需 UDP。认证必须观察实际后续心跳，不能只凭服务运行或 AUTH 成功认定恢复完成。
6. 在恢复状态通过验收后再生成新的成对备份。隔离展开及摘要一致只证明归档内部可读与文件完整，不证明真实设备的恢复流程、重启和业务可用。

候选文件：`ninja-subscription-update.capacity.rb`、`ninja-capacity.rb`、`ninja-subscription-update.capacity-fixtures.rb`、`ninja-capacity-fixtures.candidate.rb`。两份 fixtures 分别覆盖资源边界与真实事务的旧 11 项行为、新增下载前／提交前容量拒绝，共 13 个事务场景。语法与 fixtures 要在当前目标 Ruby 运行；本机未安装 Ruby。本说明没有更新旧清单的 `restore_tested`，生产恢复尚未执行。

## 公开使用说明的建议替换

以下是目标安装与实际验收通过后可采用的段落。独立 E 盘副本与隔离展开证据尚待主代理完成，不能提前写成已完成。修改时替换原文对应段落和旧结论，不再附加普通日期补丁。

第 45 行的手动订阅段落建议改为：

> 日常更新订阅：在已登录的 LuCI 打开“服务→Ninja Connector 2”，使用现有订阅下载／更新入口。点击后先显示执行中；HTTP 202 只表示请求已接收，需等待最终状态。`OK:UPDATED_VERIFIED` 表示候选通过固定 Ninja 核心检查、授权注释保留、配置重生成及 DNS／真实代理请求验收；`OK:UNCHANGED` 表示内容未变化，不重启核心。资源不足时返回 `ERR:CAPACITY_OVERLAY_LOW`、`ERR:CAPACITY_TMP_LOW` 或 `ERR:CAPACITY_MEMORY_LOW`，本次更新会在提交前停止，保留原有运行状态。提交后失败尝试回退，只有最终状态以 `:ROLLED_BACK` 结束才确认回退与健康验收通过，`ROLLBACK_FAILED` 需要处理。先查看最终脱敏状态，不要把下载成功当作运行已更新。更新过程有锁，执行中不要重复点击。核心升级继续单独维护。

第 145 行容量说明建议在原容量段落内合并：

> 手动订阅更新在下载前与发布前分别检查 overlay、`/tmp` 和可用内存，默认保留 4 MiB、32 MiB、64 MiB，再计入候选、投影、备份和回滚的工作空间。下载、校验副本放在私有 `/tmp` 目录，源发布与持久回滚副本仍在闪存中原子替换。更新结束会清理本事务临时文件，健康探测正文和原始校验错误不落盘。这些检查会拒绝已知低余量状态；检查不预留资源，其他进程随后占用空间仍可能使更新失败，因此维护时以实际最终状态为准。

第 169 行诊断日志说明保留既有口令轮换事实，增加：

> 系统日志使用约 128 KiB 的内存环形缓存，OpenClash 日志位于 `/tmp`，watchdog 按 512 KiB 设置周期清理。日志大小可能在两次检查之间超过设置值。订阅事务只保存脱敏结果，不另存订阅下载、核心校验或探测的原始正文；已有校园认证与 OpenClash 日志仍可能含账号、会话或授权信息，不宜整份公开。

恢复材料第 185～191 行建议按本轮新 manifest 改写字节数、文件数和必需文件数量，并采用以下边界：

> `router-tuned-final-config.tar.gz`、`router-tuned-final-runtime.tar.gz` 与 `tuned-backup-manifest.json` 必须作为同一组保留，恢复前先核对两份归档的 SHA-256。标准配置归档缺少自定义 hotplug，runtime 不能省略。恢复时先准备同型号、同固件与相容软件包，恢复这组配置及定制文件后，按认证、DNS／防火墙／MWAN、OpenClash 的顺序启动，再核对真实出口、代理请求与后续认证心跳。升级包可能覆盖定制入口与保护，应按清单重新检查。

主代理完成实际证据后，E 盘备份与隔离展开的结果只增加一段准确事实：保存位置、成对摘要一致、隔离展开后的必需文件核对数量。`restore_tested` 仍应明确区分“隔离展开验证”与“生产恢复”；没有覆盖真实设备并重新运行业务时，不能写成生产恢复成功。第 167 行“仍需独立介质和恢复演练”与第 191 行旧结论要同步替换，不能与新证据并存。
