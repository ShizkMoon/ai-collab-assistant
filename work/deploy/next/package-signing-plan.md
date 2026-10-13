# OpenWrt APK v3：官方索引信任链与当前安装路径

当前设备的快照公钥与官方公开公钥一致，**不需要补入新密钥**。三个官方 APK 没有独立签名块；此前直接 `apk verify local.apk` 和按本地文件安装出现 `UNTRUSTED signature`，符合这类未逐包签名产物的行为，不能据此判断包被伪造或密钥过期。

正确路径是：使用设备已有可信密钥验证未修改的官方 `packages.adb`，按索引中的包名和精确版本取包，由 APK 校验包身份及数据内容，再模拟和执行安装。全程保留正常校验，不使用 `--allow-untrusted`、重新签名、削弱校验或改写索引。

本支线只读调查官方源码和本地已下载文件，只写此文档；没有 SSH、设备设置或安装。主线当前正在验证官方索引，实际返回值优先于本文方案，本文不把尚未返回的索引验证称为已通过。

## 为什么裸 APK 被拒绝

固定 OpenWrt `f29dfe25baaa5c03f2b52f49dfdc12ed99abe8df` 的配置将 `SIGNED_PACKAGES` 默认设为 `y`，表示签署包列表；`SIGN_EACH_PACKAGE` 对 Buildbot 默认设为 `n`。打包规则仅在后一选项启用时对每个 APK 使用 `--sign`，仓库规则则在前一选项启用时签署 `packages.adb`。因此官方仓库可以采用“可信签名索引覆盖未独立签名包”的发布方式。[固定构建选项](https://github.com/openwrt/openwrt/blob/f29dfe25baaa5c03f2b52f49dfdc12ed99abe8df/config/Config-build.in#L59)、[逐包签名条件](https://github.com/openwrt/openwrt/blob/f29dfe25baaa5c03f2b52f49dfdc12ed99abe8df/include/package-pack.mk#L608)、[索引签名规则](https://github.com/openwrt/openwrt/blob/f29dfe25baaa5c03f2b52f49dfdc12ed99abe8df/package/Makefile#L195)

本地 `next/packages/` 的三个文件均为 `ADBd` 压缩格式。按 APK 官方 `adb_comp.c` 解压，并按 `adb.h` 逐块读取，三个文件都只有 ADB 元数据和 DATA 块，SIGNATURE 块数均为 **0**。这与主线 `adbdump` 的观察相符。结构检查不代替验签；它解释为什么独立验签失败。[压缩格式](https://github.com/alpinelinux/apk-tools/blob/b5a31c0d865342ad80be10d68f1bb3d3ad9b0866/src/adb_comp.c#L82)、[块类型定义](https://github.com/alpinelinux/apk-tools/blob/b5a31c0d865342ad80be10d68f1bb3d3ad9b0866/src/adb.h#L56)

| 包 | 下载字节 | 整个 APK 的 SHA-256 | 解压后 ADB 元数据的 SHA-256 |
| --- | ---: | --- | --- |
| IFB `6.18.55-r1` | 4,399 | `9208237e9449800a2f9d0734101f81eef0995f2fb9991df954a69804ed69dd1b` | `3d4bbbe7fb59d3abcd20051595aa2fa423431506b50e2922587ae86c19cd95e1` |
| CAKE `6.18.55-r1` | 18,528 | `e3c033179df761248b6a2a86f88d845651017a8cb247d6879cc1958e18ab4da2` | `322b343783c5fc672db7b4a76257bf65f60c653fa0327ed32295be7cdda2f72c` |
| BBR `6.18.55-r1` | 5,915 | `e486eb1558f21b4b04312dbeffcc0141c0554e2f5be400ddb3f118c26461dedb` | `848416c83eacd75b9829704d57d72c97f36c23c5a6887b87b93e73873112d7f6` |

整包 SHA-256 与已保存 `package-preflight.json` 一致，只证明本地文件对应本次下载记录；该记录自身不是官方签名来源。APK v3 索引中的 `hashes` 是包身份摘要，本版本默认由 SHA-256 对包的 ADB 元数据计算，**不是整个压缩 APK 的 SHA-256**。数据文件的摘要位于已受保护的包元数据中。[索引摘要生成](https://github.com/alpinelinux/apk-tools/blob/b5a31c0d865342ad80be10d68f1bb3d3ad9b0866/src/app_mkndx.c#L315)

## 当前密钥：已经匹配

主线设备读回 `/etc/apk/keys/openwrt-snapshots.pem` 为 178 bytes，其 SHA-256 是下表中的值；`/usr/share/apk/keys` 不存在。APK 官方文档使用 `/etc/apk/keys`，并明确 v3 按公钥身份匹配，文件名不重要。缺少另一个目录不能单独作为信任故障。[APK v3 密钥规则](https://github.com/alpinelinux/apk-tools/blob/b5a31c0d865342ad80be10d68f1bb3d3ad9b0866/doc/apk-keys.5.scd)

本次读取官方 `openwrt/keyring` 镜像固定提交 `fbae29d730f81c892f52e0ff00fe867444aeeae6` 的快照 PEM，内容与设备摘要完全一致；对应主分支公开 PEM 也相同。固定固件的 keyring 配方将快照 PEM 安装到 `/etc/apk/keys/`。GitHub 镜像当前不能解析配方中的较新 keyring 提交 `f0670054fd3aa9616bcd8d0d0357a1a15c65b758`，因此这里以实际可读固定公钥和字节匹配为证据，不把镜像的旧 head 称为当前官方全部 keyring 历史。[固定公开快照 PEM](https://github.com/openwrt/keyring/blob/fbae29d730f81c892f52e0ff00fe867444aeeae6/apk/openwrt-snapshots.pem)、[固定固件 keyring 配方](https://github.com/openwrt/openwrt/blob/f29dfe25baaa5c03f2b52f49dfdc12ed99abe8df/package/system/openwrt-keyring/Makefile)

| 标识 | 值 |
| --- | --- |
| 公钥类型 | EC，曲线 `prime256v1`／`secp256r1`，不是 RSA |
| PEM 文件 SHA-256 | `ec0b8a34856a67c124dcc3bfc6717b4c0b7e60c237028f26b5daf0eb489f4bae` |
| SPKI DER SHA-256 | `2f413374b99d15fe953313802bd410cadeb34288a0470f2ffc217727bb45434f` |
| APK v3 公钥 identity | `51137f08ad577844d5fcfffda85dfb2f` |

APK 的 identity 在本版本由原始公钥编码的 SHA-512 前 16 bytes 得到。对于这把 EC 密钥，编码是 65-byte 非压缩 EC point，不能拿 SPKI DER 的 SHA-512 前缀替代。主线可以对照索引 SIGNATURE 块的 key id；最终信任仍以设备原生 APK 成功验签为准。[OpenSSL 后端 identity](https://github.com/alpinelinux/apk-tools/blob/b5a31c0d865342ad80be10d68f1bb3d3ad9b0866/src/crypto_openssl.c#L171)、[mbedTLS 后端 identity](https://github.com/alpinelinux/apk-tools/blob/b5a31c0d865342ad80be10d68f1bb3d3ad9b0866/src/crypto_mbedtls.c#L198)

当前不复制新 PEM 到设备，不更新全局信任，不安装一个自身无法验证的新 keyring 包。与某些 Alpine RSA key 示例不同，本机发布密钥的实际类型已经核对。

## 严格验证链

完整链条是：

1. 设备已有可信 `openwrt-snapshots.pem` 验证官方 `packages.adb` 的签名。
2. 已验签索引中的包身份绑定名称、版本、架构、依赖和包的 ADB 元数据。
3. 按包名安装／获取时，APK 用索引中的 identity 验证该包元数据；匹配后把该包视为可信，不需要独立包签名。
4. APK 读取包 DATA 时，逐一核对由受保护元数据给出的文件摘要，才能安全解包、执行脚本和安装模块。

源码明确：身份摘要匹配会把包标记为可信；从索引安装时会传入预期 identity；实际文件读取使用摘要校验流。这不是信任绕过，而是 v3 的正式仓库机制。[元数据 identity 信任判断](https://github.com/alpinelinux/apk-tools/blob/b5a31c0d865342ad80be10d68f1bb3d3ad9b0866/src/adb.c#L109)、[安装时传入索引 identity](https://github.com/alpinelinux/apk-tools/blob/b5a31c0d865342ad80be10d68f1bb3d3ad9b0866/src/database.c#L3192)、[文件数据摘要检查](https://github.com/alpinelinux/apk-tools/blob/b5a31c0d865342ad80be10d68f1bb3d3ad9b0866/src/extract_v3.c#L103)

`apk verify local.apk` 没有从可信索引取得预期包 identity，只能尝试独立签名；未签名包因此被拒绝。`apk verify packages.adb` 则是适用入口。安装时仍须保证精确 ABI `6.18.55-1-b218d80d146ac6c85db4989df73b5de9` 与设备 kernel 包对应，不能仅看版本号。

## 推荐路径：保留原签名的本地仓库

先下载这一**精确 ABI** 的官方索引，保持字节原样：

<https://downloads.openwrt.org/snapshots/targets/mediatek/filogic/kmods/6.18.55-1-b218d80d146ac6c85db4989df73b5de9/packages.adb>

将原索引和对应三个 APK 放在本轮专用目录，例如 `/tmp/codex-next/repo/`。不生成新索引、不筛选或改写官方索引、不用本地私钥重签。先检查索引中的 `pkgname-spec`；正常相对包名应解析到该目录。如果索引使用绝对远端路径，则 `--no-network` 应使缺失本地包的事务停止，不能静默放开网络。

在设备上执行时，命令选项先与已安装 APK `3.0.5` 的帮助核对。以下是正式方案，不是本支线已执行的命令：

```sh
# 使用现有系统密钥，不新增信任。
apk verify /tmp/codex-next/repo/packages.adb

# 仅加载这一个未改动的官方索引，按包名及版本求解。
apk --no-network --repositories-file /dev/null \
  --repository /tmp/codex-next/repo/packages.adb \
  add --simulate \
  kmod-ifb=6.18.55-r1 kmod-sched-cake=6.18.55-r1 kmod-tcp-bbr=6.18.55-r1
```

`--repositories-file /dev/null` 替换系统仓库及 repositories.d 扫描；`--repository` 加入本轮指定索引。路径以 `.adb` 结尾时属于直接索引 `ndx`，包的默认位置是索引同目录。`--no-network` 禁止借滚动 feed 补依赖。模拟若要求升级／降级 kernel、libc、base-files、替换未知包或出现签名／摘要错误，停止并读回原因。[全局选项](https://github.com/alpinelinux/apk-tools/blob/b5a31c0d865342ad80be10d68f1bb3d3ad9b0866/doc/apk.8.scd#L252)、[直接索引路径规则](https://github.com/alpinelinux/apk-tools/blob/b5a31c0d865342ad80be10d68f1bb3d3ad9b0866/doc/apk-repositories.5.scd)

模拟只证明索引加载和依赖求解，不证明每个 APK 的数据已经完整读验。可以先取到**本轮新建且为空**的另一个临时输出目录，完成无需安装的软件包身份及数据验证：

```sh
# verified-output 必须是本轮新建且为空的目录。
apk --no-network --repositories-file /dev/null \
  --repository /tmp/codex-next/repo/packages.adb \
  fetch --output /tmp/codex-next/verified-output \
  kmod-ifb=6.18.55-r1 kmod-sched-cake=6.18.55-r1 kmod-tcp-bbr=6.18.55-r1
```

该 `fetch` 入口用可信索引的 identity 读取并校验包。**不要复用已有同名、同尺寸文件的输出目录，也不要使用 `--link`**：源码会对已有同尺寸文件直接跳过，硬链接路径也可能不读取校验。保存取包成功结果，再由主线在已授权范围中执行相同本地索引、包名和版本的真实 `add`，去掉 `--simulate` 即可；仍保留全部校验。[fetch 校验与跳过条件](https://github.com/alpinelinux/apk-tools/blob/b5a31c0d865342ad80be10d68f1bb3d3ad9b0866/src/app_fetch.c#L133)

另一条正规路径是通过该精确远端 `packages.adb` 加载可信仓库，使用 `--cache-dir` 保存索引与包，再在缓存完整时用无网络模式安装。缓存目录选项仅改变存放位置，不建立信任；文件名、索引缓存键和内容须由 APK 管理，不手工把任意 APK 塞入缓存后宣称已验签。对当前仅三个小模块，本地原签名索引路径更容易核对，也不需要改设备永久 repositories 文件。[缓存选项及无网络模式](https://github.com/alpinelinux/apk-tools/blob/b5a31c0d865342ad80be10d68f1bb3d3ad9b0866/doc/apk.8.scd#L131)

## 如果以后真的需要补信任

本次不满足补信任的条件。若未来索引 SIGNATURE 的 key id 确实不在已可信集合，应先确认是否切错仓库、混入其他构建或目录，保存原值和失败证据，再处理密钥更新：

- 优先由旧可信密钥已经验证的官方仓库获取 keyring 更新，核对版本、完整指纹及更新说明；通过这条已有信任链添加新密钥。
- 如果旧链不再可用，从固定官方 keyring 来源取得候选公钥，先放在隔离目录，用已有独立认可的官方签名／指纹核验其身份，再用 `apk --keys-dir` 在该隔离目录验证目标索引。隔离验证不会把候选密钥永久加入设备全局信任。仅从同一未知下载源取得新公钥及索引不能完成信任引导。
- 官方镜像的 `openwrt-snapshots.pem.gpg` 是包含公钥 literal 的 OpenPGP 签名消息。本次仅解析得到签名 issuer fingerprint `92C561DE55AE6552F3C736B82B0151090606D1D9`，并未独立验证该 OpenPGP 签名或其信任锚。因此不能把这个解析值称为已可信根，更不能以它自行批准新密钥。需要先核对对应已有可信 OpenPGP 身份，再验证消息并比较其中 PEM 字节。[固定签名消息](https://github.com/openwrt/keyring/blob/fbae29d730f81c892f52e0ff00fe867444aeeae6/apk/openwrt-snapshots.pem.gpg)

只有公钥身份、索引签名、精确包版本／架构／ABI、包 identity 和 DATA 摘要全部满足，才继续安装。独立 APK 未签名是当前发布方式的一部分；包在可信索引链下通过验证，才是本轮的严格验收条件。
