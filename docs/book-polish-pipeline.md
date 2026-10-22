# 书籍精修流水线（设计，未部署)

> "全自动、顶级质量"是目标形态;本文件只做设计定稿,不做实际部署承诺。设计约束见 `system-topology.md`(下发即监督、任务总结反哺、单一事实源)。

## 触发与入口

两条触发路径,落到同一个工作流:

| 入口 | 动作 |
| --- | --- |
| **云端 Hermes** | 用户在手机/IM 发书(EPUB/TXT/MOBI/AZW3/PDF/CBZ…),Hermes 解析附件 → 生成任务简报下发本机 |
| **本地 Calibre** | 书库新增书籍(calibre 本身无 hook,由本地 watcher/inotify 或 `cli-anything-calibre` 轮询检测新书)→ 触发同一工作流 |

下发即监督:整段流程走 Orca `orchestration`(Run → worker → `worker_done` → 回报),每阶段产出证据,不留"静默完成"。

## 流水线阶段(worker 编排,非单脚本)

```
摄入 → 解析 → 清洗 → 重排 → 元数据 → 成品导出 → 推送 → 任务记录
```

### 1. 摄入(Ingest)

- 格式归一:任何输入先转"工作中间格式"(EPUB unzip / TXT→EPUB / PDF→解析层)。
- 工具:`ebook-convert`(格式转换底座)、`pandoc`(md/txt/docx)、`calibre-meta`。
- TXT 特判:GBK/BIG5 编码检测(chardet)、章节正则切分("第N章"模式),生成结构化 EPUB。

### 2. 清洗(Clean)— LLM 介入第一层

- **机械层(无 LLM)**:正则/脚本去掉书源站广告行("请记住本书域名""无弹窗")、多余空行、乱码符、HTML 实体残留、页眉页脚水印、`sdr`/`calibre` 垃圾目录。
- **LLM 层(agent)**:对可疑段落做语义级清洗——缺字错字校对、断章续接、繁简/异体字归一、机翻痕迹修整。逐章 diff,产出"清洗报告"(删了哪几行、改了哪几个字)。
- **门禁**:清洗报告进任务记录;删改幅度超阈值(如章节字数掉 >5%)升级为人工确认,不静默吞。

### 3. 重排(Reformat)— 目标是"阅读友好"

- **EPUB 侧**:标准语义化 HTML5 + 统一 CSS(思源宋体正文/苹方标题层级);目录/页码 toc.ncx 重建;插图就地嵌入(<img> + 正确 mime),无插图书目可生成章节分隔装饰。
- **PDF 侧**:走 `weasyprint` 或 `pandoc+typst`/`xelatex`(中文字体完整嵌入);排版参数按"电子书 PDF"调(6 寸近似版面、行距、首行缩进),不是打印排版。
- **门禁**:产出交"样张验证"——worker 抽前/中/后三页渲染图,与输入对比目检,不合格回退重排参数。

### 4. 元数据(Metadata)

- `ebook-meta` 补齐:title/author/series/publisher/language/isbn/tags/description。
- 网文特判:从来源站(或 calibre 插件/来源 URL 记忆)抓作者、完结状态、最新章节号、简介。
- **门禁**:title/author 缺失或置信度低时升级问用户("这本书叫什么、谁写的")——不是猜。

### 5. 成品导出(Output)

- **EPUB**:符合 EPUB 3 规范,过 `epubcheck`;嵌入字体(思源宋体+Literata,和 Kindle 那边字体族一致,观感统一);封面规范尺寸。
- **PDF**:内嵌字体、目录书签、可检索文本层;和 EPUB 同内容同排版基线。
- **产出定义**:"顶级质量"的验收锚点 = `epubcheck` 零错误 + 样张过审 + 元数据齐全 + 正文清洗报告无遗留 TODO。

### 6. 推送(Deliver)

- **私有渠道**:上传到云服务器(静态/目录服务)→ Kindle KOReader 经 OPDS/KOSync 拉取;或 Send-to-Kindle 邮箱。
- **Calibre 归库**:成品进 `/home/shizuku/EBook/Calibre`,和原文件并存(版本标记如 `_polished`)。
- **任务记录**:每本书产出一条任务记录(清洗报告+转换参数+门禁结果+耗时),反哺提示模板和规则候选——不自动改写 AGENTS.md,候选变更显式确认。

## 质量与兜底

| 情况 | 行为 |
| --- | --- |
| 清洗后章节字数异常 | 回退原文,人工确认 |
| 元数据置信度低 | 问,不猜 |
| EPUB 校验不过 | 修复重排参数重跑,最多 N 次后升级 |
| 渲染样张不合格 | 调 CSS/排版参数重跑 |
| 任何门禁超时 | 任务挂起等回话,不静默标记完成 |

## 与现有系统的衔接

- **编排**:就是 `orchestration run-create` + worker;Calibre watcher 是"事件源",Hermes 是"入口"。
- **执行工具**:`calibredb`/`ebook-convert`/`ebook-meta`/`epubcheck`/`pandoc`/`weasyprint`(或 typst)+ worker 的 LLM 能力做语义清洗。
- **呈现**:IM 渠道给"清洗报告"文本图;App/Web 渠道给书籍卡片(封面+清洗 diff 摘要+成品下载/推送按钮)。
- **固化的细节**(以原生文件为准):书库 `/home/shizuku/EBook/Calibre`,Kindle 侧 `/mnt/us/Books/` 是 KOReader 的 `home_dir`,字体思源宋体/Literata/苹方已在 `/mnt/us/fonts/`。
- **尚缺**:云端服务器(书成品托管)+ KOSync 账号——这两件等云端 Hermes 就绪一起上,现在不部署。

## 未决项

- 元数据抓取的来源站(起点/番茄/独阅读等网文站各有反爬,要不要上 OpenCLI 走浏览器)
- "顶级质量"的更细验收(要不要自动跑文字密度/排版指标的客观评分)
- 推送端的云端选型(对象存储/CDN vs 简易 HTTP,取决于 Hermes 部署形态)
