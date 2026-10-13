# 订阅更新、香港固定策略与成对恢复材料

本次只读现有说明、归档 manifest 元数据、已取得的包内源码及本地部署脚本。没有 SSH、下载订阅、测速、读取私密归档内容或改动共享部署文件。以下是本轮实现需要纳入的路径和验证点；不是已经安装成功的声明。

最小接法是保留 LuCI 原 `download_sub` 按钮和原状态接口，controller 保存表单后只调用固定安全入口；安全更新器从 UCI 私密读取 URL，完成候选验证、生成、运行读回和失败恢复。固定香港策略与国外 DoH 放入持久 options，经现有 custom overwrite 每次生成。继续保持手动更新，不新建 cron 或守护服务。

## 精确路径与备份归属

现有 `work/deploy/root/finalize_optimization.py` 的 runtime 路径列表包含 `/etc/openclash/custom`、两个 Ninja YAML、`/etc/config/openclash`、`/etc/config/ninjaconnector2`、OpenClash init、两个核心更新入口及整个 `/usr/share/ninjaconnector2`。它未包含 LuCI controller。OpenClash 包的 keep.d 写入 `/etc/openclash/`，但应以主代理生成的 sysupgrade 实际成员校验为准，不能靠路径约定推断备份完整。

| 实际设备路径 | 用途与必要变化 | config／runtime 处理 |
| --- | --- | --- |
| `/usr/lib/lua/luci/controller/ninjaconnector2.lua` | 修改 `action_download_sub()`，保存 UCI 后调用固定命令，禁止将订阅 URL 放入 shell argv | **必须新增 runtime 的显式路径**；旧 runtime 没有此项。包安装脚本更新后需重新核对 |
| `/usr/share/ninjaconnector2/ninja_sub.sh` | 改为受控 wrapper 或增加无 URL 参数的 `download_saved`；只进入同一安全更新器，不能保留可绕过的新／旧下载路径 | 整个 share 目录已在 runtime，但必须刷新归档；Connector 包升级可能覆盖它 |
| `/etc/openclash/custom/ninja-subscription-update.sh` | 推荐的持久手动事务入口；路径可按实际实现定名，wrapper 和 controller 必须引用同一路径 | custom 整目录已在 runtime；sysupgrade 配置包的 `/etc/openclash/` 保留范围须读回验证 |
| `/etc/openclash/custom/<本轮 Ruby 辅助文件>.rb` | 候选结构、固定核心校验、生成后检查、私密数据处理等；确切名称由实现确定 | 同上；manifest 必须列出确切文件名及 SHA，不能只记录整目录已保存 |
| `/etc/openclash/custom/ninja-production-options.yaml` | 固定香港组／节点标识、国外 DoH 覆写和已有 UA3F、校园、LAN 保护；权限 0600 | 已在 custom 归档范围；本轮需与 hook、新源、当前运行配置一起刷新，旧 options 另存可恢复副本 |
| `/etc/openclash/custom/openclash_custom_overwrite.sh` | 扩展固定香港和 DNS 的幂等生成，保留既有 UA3F／LAN／校园规则；候选订阅缺失目标时失败 | 已在 custom；仍需逐文件 SHA 与实际部署读回一致 |
| `/etc/openclash/custom/restore-ninja-license.rb` | 保存最新 `#!PASS*-INFO` 注释的既有辅助文件 | 已在 custom；必须保持在启动前恢复许可的调用路径 |
| `/etc/init.d/openclash` | 既有 `start_run_core()` 许可恢复调用；如果本轮增加生成失败门禁，也在此版本内核对 | 已在 runtime；OpenClash 升级可能覆盖该 init。准备结果显示当前许可辅助调用为 1 次，不应再次重复插入 |
| `/etc/config/ninjaconnector2` | 私密订阅 URL 与 `sub_name=Ninja`；继续从 UCI 读取，不把 URL 放到新明文参数、普通日志或计划任务中 | 已在 runtime 和 UCI 配置恢复范围；检查权限 0600，配置读回只公开存在／scheme 等布尔信息 |
| `/etc/config/openclash` | 正确源 `config_path=/etc/openclash/config/Ninja.yaml`、自动更新关闭及其余生成开关 | 已在 runtime／config；本轮改变的字段必须与源、options 一起回退 |
| `/etc/openclash/config/Ninja.yaml` | 新服务端原订阅，保留许可注释；生产覆写不能写回这个源文件 | 现有两包应保留，但必须校验新归档成员和 SHA；私密内容不写公开报告 |
| `/etc/openclash/Ninja.yaml` | 由本轮 source＋hook＋options 生成的运行文件 | 已在 runtime／OpenClash 保留范围；恢复后仍须重新生成和运行检查，不能只解包宣称已恢复 |
| `/etc/openclash/core/clash_meta` | 固定 Ninja ARM64 UPX 核心；订阅更新不得替换 | 当前 runtime 未单独打包核心，config 是否包含由 `/etc/openclash/` 保留规则与实际归档核对；另有安装资产及固定 SHA `3398a44cca5db17710491ec3bb474c3c1cd4a30a3f849eb063dcfd2abd35375b` |
| `/usr/share/openclash/openclash_core.sh`、`/usr/share/openclash/openclash_update.sh`、`/usr/share/ninjaconnector2/ninja_kernel.sh` 与 `ninja_kernel.vendor.sh` | 保持既有核心更新保护，不把核心更新混入订阅动作 | 已在 runtime 的显式路径／share 目录；OpenClash 或 Connector 包升级均可能覆盖相关入口 |

如果新脚本最终放到 `/usr/libexec`、`/usr/share` 的其他目录，或新增其他 `/etc/config/<name>`，必须增加对应 runtime 路径；现有 custom 目录不会自动涵盖这些位置。LuCI view 若只是保留现有按钮和状态文案不需改；若实际改动 `/usr/lib/lua/luci/view/ninjaconnector2/main.htm`，该路径也要加入 runtime。

## 手动按钮如何进入完整流程

当前包内 `action_download_sub()` 在 UCI commit 后启动：

```text
/bin/sh /usr/share/ninjaconnector2/ninja_sub.sh download <name> <url>
```

URL 虽有 shellquote，仍作为进程参数出现；只改 helper 的 curl 命令无法消除上游这段 argv。controller 应保留 POST 限制、原路由和同一 `sub.status`，改为不含 URL 的固定 `download_saved` 或固定安全脚本命令。安全脚本从已保存 UCI 读值，curl 使用 stdin config，HTTPS 与 redirect 都受控，继续固定 Ninja UA，并隐藏候选校验及异常原文。LuCI `202 started` 仅是已派发，最终状态必须来自事务的成功／失败结果，不能把下载保存成功写成运行更新成功。

安全入口仍需要共用订阅互斥锁；遇锁忙应返回已有忙状态，不能绕过原锁再启动第二次更新。完整步骤限定为：固定核心 SHA／版本校验 → 下载候选 → 原订阅与许可结构检查 → 生产覆写与生成文件校验 → 备份源和相关 options → 原子替换 → 必要时重载 → 读回固定香港、DNS、代理请求 → 失败恢复旧源、旧 options 和旧运行。内容未变也应确认当前所需策略状态，不能把单纯字节相同当作所有维护目标均完成。

stock OpenClash 自定义 overwrite 的返回码未独立阻止启动；且 overwrite 后仍有 provider YAML dump，许可注释需在最终生成文件切换后、core 启动前恢复。应继续对候选执行 hook、最终 Ninja `-t`，并保留 init 中已有许可恢复门禁。运行验收失败时恢复旧源后重新生成，不能只将 `.bak` 放回磁盘却保留失败的运行配置。

自动更新继续关闭，不新增 `/etc/crontabs/root` 条目，也不调用原版 OpenClash 订阅 scheduler 处理私密 URL。原版 scheduler 源码会记录订阅 URL，且没有本轮专用固定核心与许可、策略的完整事务。Connector 内核安装按钮仍走既有拒绝未固定核心的 guard；不改变它的状态来伪装成功。

## 固定香港与国外 DoH 的持久化

仅 PUT API 的 selector 选择或保留 `/etc/openclash/cache.db` 不足以保证新订阅／全量生成后仍固定；应由 options 和 hook 明确重建目标。若用户要求具体香港节点，候选校验应要求该节点唯一存在，缺失、重复或类型不符就保留旧状态，不静默选择第一节点、不回到 URLTest、不自动换其他地区。一个只含目标的稳定 select 组或经准确校验的现有组可以实施这一契约；具体节点凭据始终只留在服务端订阅及私密归档中。

国外 DoH 的组后缀、nameserver-policy 和 fallback 属于同一持久 DNS 覆写；要随 options 备份。保留校园 DNS 策略、家庭 PAC 标识、独立节点 bootstrap 和避免 53／7874 自回指的约束。DoH 域名解析必须能在所需代理未建立前完成，不能为了固定香港又引入“解析节点要先连接该节点”的启动环路。若缺少目标组或加密上游业务验收失败，应恢复旧 DNS 选项，不能以公共明文悄悄降级而显示更新成功。

## 必要的归档及包升级后检查

当前 manifest 是本轮改动之前的归档：config 18,439,315 字节，runtime 180,863 字节、84 项，`restore_tested=false`。这些大小和 SHA 不能继续用于声称已包含新维护逻辑。由主代理在本轮成功验收后刷新 config＋runtime 成对归档，保留旧对；不在两个包之间混用不同轮次。

刷新脚本应在现有 runtime 列表上新增 controller，必要时新增实际改变的 view／辅助路径；成员检查至少要求安全入口、Ruby helper、controller、helper wrapper、overwrite、options、license helper、init 和源 Ninja YAML 都存在。manifest 新增这些非秘密脚本及 options 的 SHA／权限验证结果、固定核心 SHA、维护验收证据位置，同时保留 `restore_tested=false`，直到真实恢复演练完成。公开 manifest 可记录目标策略存在／唯一匹配的布尔值，不打印订阅 URL、许可注释或节点凭据。

OpenClash 升级后需要重新核对 init 许可调用、overwrite 时序、返回码处理、keep.d、两个核心更新入口和 custom 内容是否仍匹配；Connector 升级后需要重新核对 controller 固定调用、ninja_sub wrapper、kernel guard 和 vendor helper。包管理文件可能被替换，即使 custom updater 仍在，也不等于按钮仍会使用它。应匹配新版本后移植必要改动，不能无差别覆盖旧 init／controller。

本轮最低功能验证是从 LuCI 同一手动路由触发一次，确认 controller 传给子进程的命令不含 URL，最终脱敏状态反映完整事务；再确认新源、许可、固定核心、固定香港、DNS 和真实代理请求均读回成功。另用本地／受控失败输入验证候选缺失固定节点或校验失败不会替换旧源，不为此更换核心或新增计划任务。配置成功、归档可读和语法检查仍不等于正式恢复已验收。

## 本地依据

- `work/research/ninja/ipk-data/usr/lib/lua/luci/controller/ninjaconnector2.lua`：手动 POST 和 `202` 派发、UCI 保存及 URL argv。
- `work/deploy/ninja/ninjaconnector-subscription.sh`：锁、保存、备份、默认 UA，尚无完整运行更新事务。
- `work/deploy/ninja/connector-subscription-hooks.md`、`production-hook-notes.md`：包内调用、生成时序和许可恢复位置；其历史 cron 示例不适用于本轮手动范围。
- `work/deploy/root/finalize_optimization.py`、`finalize_artifacts.py`：当前 config／runtime 路径和成员检查。
- `work/deploy/ninja/openclash-uci-defaults.sh`：`/lib/upgrade/keep.d/luci-app-openclash` 保留 `/etc/openclash/`。
- `work/deploy/subscription-maintenance-prepared.json`：当前许可辅助调用 1 次；Ruby 已有 yaml、digest，未提供 open3／net/http／uri／socket／openssl／json／timeout。本轮辅助不能未经确认依赖这些缺失 stdlib，复用已装 curl／jsonfilter／timeout 与当前 YAML 路线。
- `outputs/ax6000-mainline/private-configuration/tuned-backup-manifest.json`：只读元数据，归档未恢复测试；未打开归档内容。
