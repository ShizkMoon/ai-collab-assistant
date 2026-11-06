# re-toolkit 在 Windows 的落位与验证

> 状态：部分完成 · 待复验 · 上位文档：[开发与逆向工程 §2](work-devsec.md#2-安全与逆向分析)、[本机工具链选型](local-toolchain.md)、[工作站：Windows 11 原生](workstation-windows.md)
>
> 本文是 re-toolkit 逆向工具集在本机的权威落位文档：安装路径、注册点、16 个工具与后端映射、不可用项与替代路径、验证状态。路径与版本为 2026-11-06 实测值；二进制逐行清单以 `C:\Users\Administrator\agent-src\tools\manifest.md` 为准（以原生文件为准）。

## 0. 现状一句话

MCP 已注册进 DSH desktop profile 并随会话启动，16 个工具函数全部可见，底层 30 余类二进制多数落位。但**端到端未通过**：实测调用 `disasm`、`kaitai_compile` 仍返回 `[工具缺失: <命令> 未找到]`，修补单尚未生效。因此本文状态为「部分完成 · 待复验」，不可引用为「已验证可用」。

## 1. 源码与安装落位

| 角色 | 本机路径 |
|---|---|
| 源码 | `C:\Users\Administrator\agent-src\src\nixpkgs-shizuku\pkgs\re-toolkit\re_toolkit_mcp.py`（私有仓 `ShizkMoon/nixpkgs-shizuku`，master@`58d5b76`，shallow + partial 检出） |
| 工作副本 | `C:\Users\Administrator\agent-src\tools\re-toolkit`，是指向上述源码目录的 junction，内含 `.venv` |
| 入口垫片 | `C:\Users\Administrator\.local\bin\re-toolkit-mcp.cmd`（venv 的 python + 入口 py） |
| Windows 适配补丁 | `C:\Users\Administrator\agent-src\patches\re-toolkit-windows.diff`（基线 `58d5b76`） |
| 镜像仓 | `https://github.com/ShizkMoon/agent-src`（私有，`main`），含 `scripts/install-scripts/`、`scripts/verify/`、`tools/manifest.md` |

工作副本是 junction：改工作副本即改源码，`.venv` 实际落在源码目录下，重建 venv 时不要跨 junction 移动。

## 2. 注册点

唯一的真实注册点是 `C:\Users\Administrator\.dsh\profiles\desktop\cordis.patch.yml`（以原生文件为准），条目 id `mcp-re-toolkit`：

```yaml
- id: mcp-re-toolkit
  name: "@deepseek-ai/dsh-mcp-client"
  config:
    serverName: re-toolkit
    transport: stdio
    command: "C:/Users/Administrator/agent-src/tools/re-toolkit/.venv/Scripts/python.exe"
    args:
      - "C:/Users/Administrator/agent-src/tools/re-toolkit/re_toolkit_mcp.py"
    cwd: "C:/Users/Administrator/agent-src/tools/re-toolkit"
    failOnStartupError: false
```

三个要点：

- 顶层 `- id:` 是**覆盖语义**。写一个当前不存在的 id 会被静默忽略——不报错、MCP 永远不启动。新条目必须写进 `insert:` 列表。
- `command` 直接指向 venv 的 `python.exe`，不走 `.cmd` 垫片；venv 里装了 `mcp<2` 与 `pyserial`。
- `failOnStartupError: false`：底层二进制大面积缺失时让 `toolkit_status` 报 `missing`，而不是把整条 MCP 起不来拖死会话。

同一 insert 列表下还挂着 `mcp-rea`（`rea` 6.8.0，Node stdio，229 个工具，Ghidra / JADX / rizin / tshark 多后端统一），两者能力重叠，可按需互为补充。

**旧记载作废**：`%APPDATA%\devin\mcp_config.json` 与 `%USERPROFILE%\.claude.json` 在本机都不存在（2026-11-06 `Test-Path` 均为 False）。此前文档写的「已注册到这两份配置」不成立。

## 3. 16 个工具与后端映射

| 工具 | 作用 | 实际后端 | 本机状态 |
|---|---|---|---|
| `toolkit_status` | 能力自检：能力 → 候选命令 → 命中路径，输出 ready / degraded / missing | 纯 Python | 已验证（2026-11-06 20:08，14 ready / 1 degraded / 1 missing） |
| `apk_analyze` | APK 体检：manifest 摘要、权限、DEX / so / assets 清单 | `aapt2` 2.20 → `apkanalyzer` → 纯 zip + AXML string pool 启发式 | 未验证 |
| `java_decompile` | jar / apk / dex 反编译成 Java 源码树 | `jadx` 1.5.6，缺则退 `apktool` 3.0.3 | 未验证 |
| `disasm` | 轻量反汇编与符号提取，不启 Ghidra | `rizin` 0.9.1；`objdump` / `readelf`（binutils 2.47）备选 | 失败（报「rizin 未找到」） |
| `ghidra_analyze` | Ghidra headless：导入 → 自动分析 → 导出函数清单，按函数名点取伪 C | Ghidra 12.2 + JDK 25 | 未验证 |
| `firmware_scan` | 只扫描不解包：列分区 / 文件系统 / 压缩段签名 | `binwalk` 3.1.0；缺则 Python 魔数扫描 + `7z l` | 未验证 |
| `firmware_extract` | 解包固件并提取文件系统 | auto 链：`binwalk -eM` → `unsquashfs`（squashfs-tools 4.7.5）→ `ubireader_extract_images`（ubi_reader 0.8.16）→ `7z x`（7-Zip 26.05）；`kindletool` 1.6.6 走 Kindle OTA | 未验证 |
| `firmware_inventory` | 盘点解包目录：文件树、ELF / 脚本 / 配置计数、可疑入口 | 纯 Python | 未验证 |
| `flash_read` | `flashrom` 只读 dump SPI / NOR（写操作不在工具面内） | `flashrom` 1.8.0 + CH341A | 失败（自检判 missing，二进制实际在 `tools\flashrom\bin`） |
| `frida_trace` | attach / spawn 本机进程并追踪导出函数 | `frida-tools` 14.11.0 | 未验证 |
| `kaitai_compile` | `.ksy` 格式描述 → 解析器代码 | `kaitai-struct-compiler` 0.11 | 失败（报「kaitai-struct-compiler 未找到」） |
| `net_scan` | `nmap` 服务指纹扫描，定位设备开放端口 | `nmap` 7.993 | 未验证 |
| `mitm_capture` | `mitmdump` 抓 HTTP(S) 并回摘要（regular / transparent） | `mitmproxy` 12.3.1 | 未验证 |
| `pcap_capture` | `tshark` 抓任意协议流量，全协议兜底 | `tshark` 4.7.4 | 未验证 |
| `qemu_boot` | QEMU 无头启动内核 / 固件，抓串口日志后自动终止 | QEMU 11.1.0（arm / aarch64 / mips / x86_64 四套 system 二进制） | 未验证 |
| `serial_capture` | 只读捕获串口输出，不发送任何数据 | pyserial；上游只认 `/dev/tty*` | 受限（Windows 需改造） |

## 4. 二进制落位

- 根目录 `C:\Users\Administrator\agent-src\tools\<name>`，2026-11-06 实测 **37 个工具目录**（含 `ghidra-12.1.4` 旧版与现行 `ghidra` 两套），总体积约 5.9 GB。
- 入口垫片 `C:\Users\Administrator\.local\bin\*.cmd` 共 **81 个**。
- 逐行版本与探针结果以 `C:\Users\Administrator\agent-src\tools\manifest.md`（81 行垫片探针表，2026-11-06 20:03 实测）为准，下表只保留选型相关项。

| 组件 | 版本 | 备注 |
|---|---|---|
| JDK 21 / JDK 25 | 21.0.13 / 25.0.5 | 双 JDK 并存，Ghidra 12.2 强制 JDK 25+ |
| Ghidra | 12.2 | `ghidra-analyzeHeadless.cmd` 内联 `JAVA_HOME` 指向 JDK 25 |
| jadx | 1.5.6 | `tools\jadx\bin\jadx.bat` |
| apktool | 3.0.3 | jadx 缺位时的 dex / apk 兜底 |
| rizin | 0.9.1 | `tools\rizin\bin\rizin.exe` |
| binwalk | 3.1.0 | MSYS2 ucrt64 构建 |
| squashfs-tools | 4.7.5 | `unsquashfs` |
| ubi_reader | 0.8.16 | `ubireader_extract_images` |
| aapt2 | 2.20 | APK 体检首选 |
| nmap | 7.993 | `net_scan` 后端 |
| tshark | 4.7.4 | Wireshark 套件，离线 `-r` 读包 |
| kaitai | 0.11 | `kaitai-struct-compiler.bat` |
| adb | 1.0.41 | platform-tools |
| payload-dumper-go | 2.1.0 | Android OTA 提取 |
| frida-tools | 14.11.0 | `frida-trace` |
| mitmproxy | 12.3.1 | `mitmdump` |
| QEMU | 11.1.0 | 四架构 system 模式 |
| openocd | 0.12.0 | JTAG / SWD |
| 7-Zip | 26.05 | `tools\7zip\7z.exe` 真身 |
| kindletool | 1.6.6 | 源码自建，Kindle OTA |
| flashrom | 1.8.0 | `tools\flashrom\bin`，含 `libcrypto-3-x64` / `libftdi1` / `libusb-1.0` |
| binutils | 2.47 | MSYS2，供 `objdump` / `readelf` |
| dtc | 1.8.1 | 设备树编译 |
| sigrok-cli | 0.8.0 | 逻辑分析仪采样 |
| rea | 6.8.0 | Node 包，独立 MCP（`mcp-rea`），非 re-toolkit 后端 |

## 5. 不可用与受限项

| 项 | 状态 | 替代路径 |
|---|---|---|
| `unblob` | **Windows 原生不可用**。PyPI 只发 macOS / Linux wheel，硬依赖 `pyscan`、`unblob-native` 均无 Windows 构建，sdist 需 MSVC + Rust 工具链。已决定搁置，不追 WSL | `firmware_extract` 的 binwalk → unsquashfs → ubireader → 7z 链覆盖 squashfs / UBI / cramfs 与常见容器；提取率低于 unblob，遇自定义头改用手写 Kaitai 或 Python 解析 |
| Hopper | macOS 独占，Windows 不可用 | Ghidra 12.2 顶上 |
| IDA | 商业授权，本机无 | Ghidra + rizin |
| `flashrom` 真实烧录 | 二进制到位，`-L` 可列 692 颗芯片，但**未验证过真实烧录**；CH341A 需管理员装 WinUSB 驱动 | 只读 dump 先跑通再谈写入；写入不在工具面内 |
| `tshark` 实时抓包 | 缺 Npcap（安装需 UAC 提权）；离线 `-r` 读包正常 | `pcap_capture` 依赖离线样本；实时抓包待装 Npcap |
| `apkanalyzer` | 装不上：`java.lang.IllegalStateException: The tools directory property is not set` | `apk_analyze` 退到 `aapt2` |
| 裸命令 `7z` | 被 WindowsApps 的 NanaZip 桩抢占 | server 侧固定走 `tools\7zip\7z.exe` 真身 |
| `serial_capture` | 上游只认 `/dev/tty*`，Windows 需 pyserial 改造 | 改造前只能用其他串口工具 |

## 6. 验证状态

| 轮次 | 时间 | 范围 | 结果 |
|---|---|---|---|
| 第一轮端到端核验 | 2026-11-06 | 16 个工具逐个调用 | **不通过**：`disasm`、`frida_trace`、`kaitai_compile`、`flash_read`、`net_scan`、`pcap_capture` 六个报「工具缺失」。根因判定：裸命令名在 Windows `CreateProcess` 下不读 `PATHEXT` |
| 修补单 | 2026-11-06 | `_resolve` 收口 + 别名表 + `.cmd` / `.bat` 走 `cmd.exe /c` + Ghidra 日志过滤 | 已发出，**未合入生效** |
| 第二轮复查 | 2026-11-06 20:08 | `toolkit_status` + `disasm` + `kaitai_compile` | 仍不通过。`toolkit_status` 自检报 14 ready / 1 degraded / 1 missing（`rizin`、`kaitai-struct-compiler` 的路径都被找到），但同一份解析结果喂不进执行路径：`disasm` 对绝对路径的 `rizin.exe` 仍返回「工具缺失: rizin 未找到」，`kaitai_compile` 返回「工具缺失: kaitai-struct-compiler 未找到」 |
| 复验（待补） | — | 修补生效后重跑 16 个工具 | 全部通过后本文状态改为「已验证」，并在此填日期与基线 |

结论口径：**`toolkit_status` 的 ready 不能当验收依据**——它只证明解析层看得到二进制，不证明执行路径能起进程。验收一律以实际调用返回为准。

## 7. 维护

- 改注册：编辑 `cordis.patch.yml` 的 `insert:` 列表，重启会话生效；不要写成顶层 `- id:`。
- 复验顺序：先 `toolkit_status` 看解析，再逐个实际调用；两者不一致以实际调用为准，并记进 §6。
- 不跑 `rea setup`：它会改写 Claude Desktop / Codex / Cursor 的 MCP 注册，与本文的落位口径冲突。
