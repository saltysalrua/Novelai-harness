# 第三方开源许可与引用声明 (Third-Party Notices & Licenses)

本文档详细记录了 **NovelAI Harness** 项目直接使用的所有第三方开源软件库、字体、数据集、在线服务以及设计与架构参考项目的许可证信息与致谢声明。

---

## 📜 开源许可证与引用说明 (License & References)

本项目自身基于 **[MIT License](LICENSE)** 开源。本项目所使用的依赖库、字体、数据集与参考项目遵循各自的开源授权或商用许可：

- **Dart / Flutter 依赖库**：采用 MIT、BSD-3-Clause 或 Apache-2.0 许可证。
- **字体资产 (MiSans)**：遵循《MiSans 字体知识产权许可协议》，允许免费商用与嵌入。
- **离线词库 (Danbooru TSV)**：来源于公开整理的社区标签数据集。
- **参考项目**：涉及的所有开源参考项目均已在此声明出处并致谢。

---

## 📦 直接使用的开源依赖库清单 (Direct Dependencies)

以下为本项目在 `pubspec.yaml` 中声明并直接编译打包的 Dart / Flutter 开源依赖库及其许可证信息：

| 依赖库 (Package) | 许可证 (License) | 用途与说明 | 源码 / 托管地址 |
| :--- | :--- | :--- | :--- |
| **`flutter`** (SDK) | BSD-3-Clause | 跨平台应用 UI 框架与渲染引擎 | [flutter.dev](https://flutter.dev) |
| **`http`** (`^1.2.1`) | BSD-3-Clause | HTTP 与 SSE 流式网络通信 | [pub.dev/packages/http](https://pub.dev/packages/http) |
| **`archive`** (`^3.6.1`) | Apache-2.0 | 内存 ZIP 归档数据解包与流式解析 | [pub.dev/packages/archive](https://pub.dev/packages/archive) |
| **`image`** (`^4.3.0`) | Apache-2.0 | 纯 Dart 图像处理：修复蒙版栅格化、潜空间量化、离屏覆盖层合成、DCT 盲水印频域运算与附件降采样 | [pub.dev/packages/image](https://pub.dev/packages/image) |
| **`desktop_drop`** (`^0.8.3`) | MIT | 桌面端原生拖拽：接收外部图片、参考图与带元数据图片一键回填参数 | [pub.dev/packages/desktop_drop](https://pub.dev/packages/desktop_drop) |
| **`sqlite3`** (`^2.4.6`) | MIT | 离线 SQLite 数据库引擎绑定 | [pub.dev/packages/sqlite3](https://pub.dev/packages/sqlite3) |
| **`sqlite3_flutter_libs`** (`^0.5.24`) | MIT | 各桌面平台 SQLite 原生动态链接库 | [pub.dev/packages/sqlite3_flutter_libs](https://pub.dev/packages/sqlite3_flutter_libs) |
| **`window_manager`** (`^0.5.2`) | MIT | 桌面端无边框窗口尺寸、坐标与最大化控制 | [pub.dev/packages/window_manager](https://pub.dev/packages/window_manager) |
| **`pasteboard`** (`^0.5.0`) | MIT | 桌面端剪贴板原生图像与文本读写 | [pub.dev/packages/pasteboard](https://pub.dev/packages/pasteboard) |
| **`flutter_markdown_plus`** (`^1.0.12`) | BSD-3-Clause | AI 消息流、思考链与 Skill 规范 Markdown 渲染 | [pub.dev/packages/flutter_markdown_plus](https://pub.dev/packages/flutter_markdown_plus) |
| **`msgpack_dart`** (`^1.0.1`) | MIT | MessagePack 二进制序列化与反序列化 | [pub.dev/packages/msgpack_dart](https://pub.dev/packages/msgpack_dart) |
| **`shared_preferences`** (`^2.2.3`) | BSD-3-Clause | 本地轻量级持久化键值存储 | [pub.dev/packages/shared_preferences](https://pub.dev/packages/shared_preferences) |
| **`file_picker`** (`^8.0.0`) | MIT | 跨平台文件、图片与预设库选取对话框 | [pub.dev/packages/file_picker](https://pub.dev/packages/file_picker) |
| **`path`** (`^1.9.0`) | BSD-3-Clause | 跨平台文件系统路径操作实用工具 | [pub.dev/packages/path](https://pub.dev/packages/path) |
| **`path_provider`** (`^2.1.3`) | BSD-3-Clause | 查找系统标准目录（文档、缓存、应用数据） | [pub.dev/packages/path_provider](https://pub.dev/packages/path_provider) |
| **`intl`** (`^0.19.0`) | BSD-3-Clause | 国际化、时间日期与数值格式化 | [pub.dev/packages/intl](https://pub.dev/packages/intl) |
| **`crypto`** (`^3.0.3`) | BSD-3-Clause | SHA-256 哈希与数据完整性校验 | [pub.dev/packages/crypto](https://pub.dev/packages/crypto) |
| **`cupertino_icons`** (`^1.0.8`) | MIT | iOS / macOS 风格常用图标集 | [pub.dev/packages/cupertino_icons](https://pub.dev/packages/cupertino_icons) |
| **`flutter_lints`** (`^6.0.0`) | BSD-3-Clause | 官方推荐的代码风格规范与静态分析规则 | [pub.dev/packages/flutter_lints](https://pub.dev/packages/flutter_lints) |

---

## 🔤 字体资产授权 (Font Licenses)

### MiSans (小米开源字体)
- **字体文件**：`MiSans/ttf/MiSans-Regular.ttf`, `MiSans-Medium.ttf`, `MiSans-Demibold.ttf`, `MiSans-Bold.ttf`
- **版权所有**：© Xiaomi Inc. All rights reserved.
- **授权协议**：《MiSans 字体知识产权许可协议》
- **授权摘要**：免费商用，允许在软件、移动端、桌面端应用及网页中免费嵌入、调用与分发，禁止单独转售字体文件。
- **官网地址**：[https://hyperos.mi.com/font/zh/](https://hyperos.mi.com/font/zh/)

---

## 🗄️ 数据集与数据源声明 (Datasets & Data Sources)

### Danbooru 32万+ 标签中英对照数据库 (`assets/danbooru.tsv`)
- **数据源一**：**[ffdkj/Danbooru_Tag-Chinese-English-Translation-Table](https://github.com/ffdkj/Danbooru_Tag-Chinese-English-Translation-Table)**
  - 维护者：ffdkj
  - 描述：每日自动构建的 Danbooru 标签中英文对照表（收录 post_count ≥ 10 全部词条，含分类与热度）。
- **数据源二**：**Danbooru 官方 API (`danbooru.donmai.us/tag_aliases.json`)**
  - 描述：Danbooru 官方活跃别名表，用于别名归一化与快速联想。
- **版权声明**：标签词条与别名数据来源于 Danbooru 社区公开数据，中英文对照与翻译整理归原贡献者与社区共同所有。

---

## 🌐 外部 API 与在线服务依赖 (Online APIs & Services)

本项目在运行特定功能时会与以下外部服务进行网络通信：

1. **NovelAI 官方服务 (Anlatan, Inc.)**
   - 端点：`https://image.novelai.net` / `https://api.novelai.net`
   - 用途：图像生成、新版 Multipart 超分放大、官方 Tag 联想及用户订阅状态查询。
   - 约束：使用本软件需用户自备有效账户及 API 凭证，遵守 [NovelAI 服务条款](https://novelai.net/terms)。

2. **models.dev 在线模型能力目录**
   - 端点：`https://models.dev/api.json`
   - 维护方：社区维护的权威 LLM 元数据中心。
   - 用途：在线自动获取 LLM 的上下文窗口长度、Reasoning Effort 思考参数配置与模态能力。

3. **DanbooruSearch 在线语义检索服务**
   - 端点：`https://sakizuki-danboorusearch.hf.space/api`
   - 维护方：SAkizuki / SuzumiyaAkizuki (HuggingFace Space)
   - 用途：提供模糊自然语言转标签 (`/search`)、标签共现推荐 (`/related`) 与 NPMI 画师推荐 (`/artists`) 的网络 API。

4. **第三方 OpenAI 兼容绘图模型网关 (外部图像编辑)**
   - 用途：在 AI 整图编辑模式下，向用户自主配置的多模态模型（如 Gemini 2.5 Image、GPT Image 等）发送图片与重绘指令。
   - 约束：Token 与绘图费用由用户自备的供应商账户承担。

---

## 🙏 开源致谢与架构参考 (Acknowledgments & References)

本项目在设计与开发过程中深入参考并借鉴了以下开源项目的架构设计、核心算法与产品交互理念：

### 1. [Pi Agent Harness (@earendil-works)](https://pi.dev)
- **项目**：[`pi`](https://github.com/earendil-works/pi) (`@earendil-works/pi-agent-core`, `@earendil-works/pi-ai`, `@earendil-works/pi-coding-agent`)
- **协议**：MIT License
- **致谢与参考**：
  - 参考了 Pi 的极简 Agent Harness 架构设计，构建了基于事件流的纯轻量级 Agent 循环调度器 (`agent_harness.dart`)。
  - 采用了基于 `SKILL.md` 规范的渐进式技能披露机制（Progressive Disclosure）与 `load_skill` 动态加载。
  - 采用了 Pi 官方标准的 JSONL 会话落盘格式与分支检查点回溯设计。
  - 借鉴了 `pi-bill` 的增量 Token 用量统计与按天/供应商账本聚合模式。
  - 引入了 `models.dev` 作为统一的大模型能力元数据源。

### 2. [Aaalice_NAI_Launcher (Aaalice233)](https://github.com/Aaalice233/Aaalice_NAI_Launcher)
- **项目**：[`Aaalice_NAI_Launcher`](https://github.com/Aaalice233/Aaalice_NAI_Launcher)
- **协议**：MIT License
- **致谢与参考**：
  - 移植并参考了其现代 NovelAI 图像生成计费公式（`AnlasCalculator`），包含 V3/V4/V4.5/V5 模型加权系数、Opus 免费档判定规则、V5 体力配额透支逻辑以及新版超分接口的分档计费算法。
  - 参考了多角色归一化坐标体系（`[0.0, 1.0]`）与自动网格排版算法。
  - 参考了 NovelAI 官方多角色协议三件套参数封装细节。

### 3. [DanbooruSearch (SAkizuki / SuzumiyaAkizuki)](https://github.com/SuzumiyaAkizuki/DanbooruSearch)
- **项目**：[`DanbooruSearch`](https://github.com/SuzumiyaAkizuki/DanbooruSearch) / [`ComfyUI-DanbooruSearcher`](https://github.com/SuzumiyaAkizuki/ComfyUI-DanbooruSearcher)
- **协议**：GPL-3.0
- **致谢与参考**：
  - 致谢其提供的公开语义向量检索与 NPMI 画师推荐算法模型，并在本项目中封装了与之对接的 HTTP 客户端与 Agent 工具箱。

### 4. [Plana-App (mc5024)](https://github.com/mc5024/Plana-App)
- **项目**：[`Plana-App`](https://github.com/mc5024/Plana-App)
- **协议**：GPL-3.0
- **致谢与参考**：
  - 参考了其在移动端处理 NovelAI `{}`/`[]` 与 SD `(tag:weight)` 语法双向转换、权重增减与禁用注释的 AST 设计思路。
  - 参考了中英多模态检索中针对中文别名首段的 `cnHead` 截取与匹配逻辑。
  - 参考了按 Danbooru 官方分类对 Prompt 进行富文本着色与透明度淡显的视觉呈现方案。

### 5. [NovelAI Prompt Autocomplete & nai5-prompting (Miint-Sunny / saltysalrua)](https://github.com/Miint-Sunny/nai-autocomplete)
- **项目**：[`nai-autocomplete`](https://github.com/Miint-Sunny/nai-autocomplete) / [`nai5-prompting`](https://github.com/Miint-Sunny/nai5-prompting)
- **协议**：MIT License
- **致谢与参考**：
  - 参考了浮动标签自动补全悬浮卡片、分类色条指示与键盘快速选词上屏的交互体验。
  - 参考了 `nai5-prompting` 关于 V5 散文提示词架构、漫画分镜、文字嵌入及管道符 `|` 物理防串色隔离的系统提示词指南。
  - 参考了提示词组合预设库的分类存储与复用设计。
