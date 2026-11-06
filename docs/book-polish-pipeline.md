# 电子书精修流水线（`work.book.polish`）

> 状态：设计定稿，待部署 · 上位文档：[内容创作流水线](creative-studio.md)、[系统拓扑](system-topology.md)
>
> 本文细化 `work.book.polish` 能力的实现方案：将杂乱格式的原始电子书（EPUB / TXT / MOBI / AZW3 / PDF）自动化处理为排版规范、字体统一、元数据齐全并经过 `epubcheck` 校验的标准 EPUB 3 与 6 英寸阅读版 PDF，随后归档至本地 Calibre 书库并推送到 Kindle Paperwhite 5（KOReader）。

## 1. 触发入口与管线阶段映射

电子书精修复用 [内容创作流水线 §2](creative-studio.md#2-七段式文件管线规范) 的七段式目录与四件套文件规范（`artifact`、`metrics.json`、`critique.md`、`decision.md`）：

| 触发入口 | 接入链路 |
| --- | --- |
| **对话上传** | 用户在手机或桌面把电子书文件发给 DSH 会话 → 入口创建 `work.book.polish` 任务 → 派发方启动执行（`agent:local` 为执行器取值） |
| **本地目录自动监听** | 本地待处理目录新增文件 → 文件系统监听守护进程（`FileSystemWatcher`）触发 `ev add --kind work.book.polish` → 进入同一条派发链路 |

整条流水线由协调 Worker 按阶段推进，每个阶段完成时向任务库写入一句话执行摘要，不在后台静默吞掉异常。

## 2. 六个核心处理阶段

```
1. 格式摄入 (Ingest) → 2. 文本清洗 (Clean) → 3. 样式重排 (Reformat) → 4. 元数据补齐 (Metadata) → 5. 成品校验导出 (Export) → 6. 归档与推送 (Deliver)
```

### 2.1 格式摄入与归一化（`01-ingest`）

- **统一中间格式**：使用 Calibre 的 `ebook-convert` 与 `pandoc` 将不同输入格式（MOBI / AZW3 / DOCX / Markdown）统一解包转换为标准结构化 EPUB 工作目录。
- **纯文本（TXT）专门处理**：使用 `chardet` 检测字符编码（自动将 `GBK` / `GB18030` / `Big5` 转为 `UTF-8`），通过正则表达式识别章节标题（如 `第[零一二三四五六七八九十百千万0-9]+[章节回卷]`），切分生成独立章节 HTML 与目录索引。

### 2.2 双层文本清洗（`03-draft/clean`）

- **确定性规则清洗（脚本层，不调大模型）**：使用正则脚本批量剔除来源站植入广告行、多余连续空行、未转义的 HTML 实体残留、扫描页眉页脚水印以及无用的 `.sdr` 附属目录。
- **语义级校对（LLM 层）**：针对 OCR 识别错误、缺字断句、繁简转换误用（如"后/後""发/髮"）或明显机翻病句的段落，调用大模型逐章审校并生成章节级 Diff 与 `clean-report.md`（明确列出修改位置与删减字数）。
- **字数异常熔断检查**：若单章清洗后的字数较原文减少超过 **5%**，立即中止自动覆盖并将任务转为 `escalated`（`+me`）交由人工审阅 Diff，防止模型截断正文。

### 2.3 样式重排与字体嵌入（`03-draft/reformat`）

- **EPUB 3 侧**：转换为语义化 HTML5 标签并挂载统一的阅读 CSS 样式表（中文正文默认绑定思源宋体，标题层级绑定苹方，西文与数字搭配 Literata，与 Kindle KPW5 本地 `/mnt/us/fonts/` 字体配置保持一致）；重建完整的 `nav.xhtml` 与 `toc.ncx` 嵌套目录；校正内嵌插图的 MIME 类型与自适应宽高。
- **6 英寸阅读版 PDF 侧**：通过 `typst` 或 `weasyprint` 编译生成针对 6–7 英寸墨水屏优化的小版面 PDF（紧凑页边距、适中行距、完整内嵌中文字体子集与 PDF 书签树）。
- **抽样渲染目检**：导出初稿后，自动抽取前、中、后各 3 页渲染为位图，检查是否存在缺字方框（Tofu）、标题孤行或插图溢出；发现问题则调整排版参数重跑。

### 2.4 元数据补齐（`04-review/metadata`）

- 调用 `ebook-meta` 补齐标准字段：`title`、`author`、`series`、`publisher`、`language`、`isbn`、`tags`、`description` 及高清封面图。
- **缺失确认**：若书名或作者无法从原文件或公开书目源中可靠提取，任务转入 `escalated`（`+me`）询问用户，禁止编造 ISBN 或作者信息。

### 2.5 成品导出与规范校验（`06-export`）

- **自动化验收条件**：生成的 EPUB 必须通过 **`epubcheck` 零错误（0 Errors）校验**，样张渲染无版面破损，元数据完整，且清洗报告无异常截断告警。

### 2.6 书库归档与设备推送（`07-publish`）

- **本地 Calibre 归档**：调用 `calibredb add <成品.epub> --with-library <书库路径>` 归档入库（保留原文件备份，精修版添加 `_polished` 标记；书库路径以本机实际创建位置为准）。
- **无线同步至 Kindle KPW5**：由于属于个人私有设备传输，**不触发对外发布确认点**。直接通过 KOReader 配置的 OPDS 目录服务、Tailscale SSH（目标目录 `/mnt/us/Books/`）或 Send-to-Kindle 邮件完成推送。
- **完成回写**：调用 `ev done <id> "《<书名>》精修完成，epubcheck 0 error，已入 Calibre 库并同步至 KPW5"`。

## 3. 异常分支与挂起处理

| 异常情况 | 停止位置 | 系统处理行为 |
| --- | --- | --- |
| 清洗后单章字数缩减 > 5% | 人工确认（`escalated`） | 保留原文备份，推送清洗 Diff 卡片等待人工确认 |
| 书名或作者元数据缺失 | 人工确认（`escalated`） | 向用户发送卡片询问准确书名与作者 |
| `epubcheck` 校验报错 | 自动重试 | 根据报错行号自动修复 HTML/OPF 结构并重跑，连续 3 次未通过则转人工处理 |
| 样张渲染版面异常 | 自动重试 | 回退 CSS 样式参数重新编译，并将样张截图附在任务注解中备查 |
| 外部网络超时 | 延迟等待（`waiting`） | 设置 `wait` 唤醒时间稍后重试，不将超时任务静默标为完成 |

## 4. 关联工具链与本机状态

- **本机已就绪工具**：Calibre `9.16.0`（含 `calibredb`、`ebook-convert`、`ebook-meta`）、`cli-anything-calibre`、Kindle KPW5（已越狱安装 KOReader，`/mnt/us/fonts/` 已预置思源宋体、Literata 与苹方字体）。
- **待按需补装工具**：`epubcheck`、`pandoc`、`typst` / `weasyprint`（统一通过 `winget` 或 `upctl` 安装）。
