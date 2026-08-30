# NovelAI Harness

<p align="center">
  <strong>专为 NovelAI 图像生成与二次元视觉创作设计的极简化、响应式 Flutter AI Harness 工作台</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-Windows%20%7C%20macOS%20%7C%20Linux-blue?style=flat-square" alt="Platforms">
  <img src="https://img.shields.io/badge/Flutter-%3E%3D3.12-02569B?style=flat-square&logo=flutter" alt="Flutter">
  <img src="https://img.shields.io/badge/License-MIT-green?style=flat-square" alt="License">
  <img src="https://img.shields.io/badge/NovelAI-V5%20%2F%20V4.5%20%2F%20V3-orange?style=flat-square" alt="NovelAI">
</p>

<p align="center">
  <img src="assets/images/preview.png" alt="NovelAI Harness 界面预览" width="95%">
</p>

---

## 📖 项目简介

**NovelAI Harness** 是一个面向 NovelAI 深度创作者的桌面端全能工作台。它融合了 **Pi 风格的极简 AI Harness 内核** 与 **高响应性三栏自适应界面**，将参数调优、图像画板、多角色定位、Danbooru 标签生态与智能 Agent 交互深度结合，提供纯粹、克制且高效的二次元视觉创作体验。

### 🌟 核心设计哲学

1. **Pi 风格极简内核**：参考 Pi（Minimalist Agent Harness）设计思想，保持内核精简、低耦合，通过事件流（Event Stream）、动态工具调用（Function Calling）与模块化技能（Skills）驱动 AI 行为。
2. **纯粹、直接与克制的交互表达**：所有界面标签、选项名称、提示语与工具输出，均使用**最纯净、直接的大白话与官方标准名称**，严禁使用营销修饰词与花哨符号。
3. **高响应性三卡片工作台**：支持自由拖动分割线的三栏结构（左：参数与提示词，中：图像画板，右：AI 对话），提供无缝自适应体验。
4. **官方协议与并发安全**：严格执行单并发排队（Concurrency = 1）、429 智能退避重试、纯内存 ZIP 数据解包以及精准的 Opus 免点数保护。

---

## ✨ 核心特性

- 🎨 **三卡片自适应工作台**：
  - **左侧面板**：生图参数设置（模型、采样算法、噪声调度、分辨率 2D 画板、CFG/步数）与提示词编辑（正负提示词、多角色扩展甲板、固定前缀/后缀）。
  - **中间画板**：流式生图实时渲染、生成中状态卡片、历史图片缩略图轮播、全屏灯箱预览、画板历史图片审查工具、多角色画布拖拽定位层。
  - **右侧 AI 对话**：多轮对话交互、模型/思考强度（Reasoning Effort）无缝切换、思考链折叠/展开、内嵌提问卡片（`ask_user`）、多分支历史回溯（双击 `ESC`）。
- 🤖 **极简 AI Harness 运行时**：
  - 支持 OpenAI 兼容协议流式通讯，智能解析 Thinking 思考链与 Token 用量。
  - **按需加载技能（Progressive Disclosure）**：内置 `V5 自然语言架构师`、`Danbooru 标签`、`艺术总监` 等技能，支持通过标准 `SKILL.md` 格式导入导出自定义技能。
  - **丰富的内置工具箱**：生图/超分、参数读写、多角色增删改查、Danbooru 语义检索/画师推荐、词组合库管理、画板图像查看等。
- ⚡ **NovelAI 官方协议与计费保护**：
  - 全面适配 NovelAI Diffusion V5/V4.5/V4/V3 及 Furry 系列模型。
  - 全局并发锁保护与 429 速率限制智能重试机制。
  - 精准内置 **Anlas 预计消耗计算器**，严格执行 Opus 免费档规则（像素 ≤ 1,048,576 且步数 ≤ 28 且单张）与 V5 体力配额保护。
  - 适配 2026-08 最新官方超分协议（Multipart 表单传输、新超分模型固定倍率、字节级尺寸解析）。
- 🏷️ **Danbooru 32万+ 离线/在线双轨标签体系**：
  - 内置 32万+ Danbooru 标签中英对照离线词库，后台 Isolate 毫秒级分词打分与排序检索。
  - 浮动标签自动补全悬浮卡片，支持分类色彩胶囊、热度统计与键盘导航。
  - 集成 DanbooruSearch 在线语义检索服务，支持自然语言模糊描述搜词、标签共现关联推荐与擅长画师（NPMI）推荐。
  - 独立「Danbooru 标签灵感库」弹窗，精选高频标签与分类速查。
- 👥 **多角色可视化定位与防串色隔离**：
  - 深度支持 V5（自由连续坐标）与 V4/V4.5（5×5 量化网格）官方多角色协议。
  - 画板角色锚点交互拖拽，支持 AI 自动排版与自定义定位无缝切换。
  - 遵循 V5 管道符 `|` 物理防串色与独立角色提示词/负面词三件套协议。
- 📝 **提示词 AST 引擎与语法高亮**：
  - 独创 NovelAI 语法 AST 解析引擎，支持 `{}`/`[]` 权重即时增减、SD ⇄ NAI 语法双向互转与标签禁用（`#` / 删除线）。
  - 富文本语法高亮控制器，根据 Danbooru 官方分类（Artist/Character/Copyright/General/Meta）智能着色。
- 📚 **提示词组合预设库 (Prompt Combo Library)**：
  - 结构化管理角色、画风、服饰、场景等词组合预设，支持缩略图关联、快速导入/导出 JSON 与一键追加/覆盖到工作台。
- 📊 **Token 账本与 Pi 会话持久化**：
  - 会话按 Pi 官方标准 JSONL 格式落盘，支持断点续传与消息树分支恢复。
  - 增量 Token 用量账本，按天、供应商、模型多维统计输入/输出与思考 Token 消耗。

---

## ⚠️ 第三方提醒与免责声明 (Third-Party Notices & Disclaimers)

> [!IMPORTANT]
> **非官方产品声明 (Non-Official Disclaimer)**
> - 本项目（NovelAI Harness）是由社区开发者自主构建的第三方开源客户端与 AI 工作台，**并非 NovelAI（Anlatan, Inc.）的官方产品，亦未获得官方的赞助或授权**。
> - “NovelAI”及其相关标志均为 Anlatan, Inc. 的注册商标或服务标志。
> - 使用本软件前，请确保您拥有合法有效的 NovelAI 账号与 API Key，并在使用过程中严格遵守 [NovelAI 官方服务条款 (Terms of Service)](https://novelai.net/terms)。

> [!WARNING]
> **第三方 API 凭证与费用提示 (API Credentials & Billing)**
> - **NovelAI Anlas 消耗**：图像生成与超分可能消耗您 NovelAI 账号中的 Anlas 点数。尽管本软件内置了精准的 Anlas 预估与 Opus 免点数保护拦截，**但实际计费仍以 NovelAI 官方服务器为最终依据**。
> - **LLM 供应商费用**：AI 对话与 Agent 功能需要连接第三方大语言模型提供商（如 OpenAI、Anthropic、DeepSeek、Google 等）。调用大模型 API 所产生的 Token 用量与账单费用由用户所配置的供应商账号自行承担。
> - **凭证安全**：您的 NovelAI API Key 与第三方 LLM API Key 均仅加密/明文保存在您本地设备上（通过 `shared_preferences` / 本地配置文件），本软件绝不会向任何未经授权的第三方服务器上传您的密钥。

> [!NOTE]
> **在线数据与网络服务说明 (Online Services Availability)**
> - 本软件集成的部分在线服务（如 `DanbooruSearch` HuggingFace Space、`models.dev` 模型元数据库、`Danbooru` 官方 API、`GitHub` 每日词库构建源）均属于第三方独立维护的公共或免费资源。
> - 第三方服务的可用性、响应速度、接口稳定性以及数据准确性受其各自运维方与网络环境影响，本软件不对此做任何明示或暗示的保证。

> [!NOTE]
> **字体与开源资产授权 (Font & Open Source Assets)**
> - 本项目内置的 **MiSans** 字体遵循小米官方《MiSans 字体知识产权许可协议》（允许免费商用、嵌入与分发）。
> - 本项目内置的 Danbooru 标签翻译数据来源于开源社区公开整理的数据集，版权归原整理者与社区共同所有。

---

## 📦 直接使用的第三方资源清单 (Direct Third-Party Resources & Assets)

本项目在开发与运行过程中，直接引入和使用了以下第三方开源资产、数据集、网络服务与依赖库：

### 1. 字体资源 (Fonts)
- **[MiSans](https://hyperos.mi.com/font/zh/)** (小米开源字体)
  - 路径：`MiSans/ttf/` (`MiSans-Regular.ttf`, `MiSans-Medium.ttf`, `MiSans-Demibold.ttf`, `MiSans-Bold.ttf`)
  - 授权：MiSans 免费商用版权授权协议。

### 2. 离线数据集与词典 (Offline Datasets)
- **Danbooru 中英文对照标签库 (`assets/danbooru.tsv`)**
  - 数据源：来源于 **[ffdkj/Danbooru_Tag-Chinese-English-Translation-Table](https://github.com/ffdkj/Danbooru_Tag-Chinese-English-Translation-Table)** 每日构建的 `tag.sqlite` 数据表，以及 **Danbooru 官方 API** (`https://danbooru.donmai.us/tag_aliases.json`) 的活跃别名数据。
  - 数据规模：收录超过 324,000 条包含中英文名称、使用频次、别名及 Danbooru 官方分类代码（General/Artist/Copyright/Character/Meta）的标签词条。

### 3. 在线 API 与网络服务 (Online APIs & Services)
- **[NovelAI 官方服务](https://novelai.net)**：图像生成 API (`https://image.novelai.net/ai/generate-image`)、新版超分 API (`https://image.novelai.net/ai/upscale`)、标签联想 API 与用户账号订阅状态 API。
- **[models.dev](https://models.dev)**：社区维护的权威 LLM 能力元数据目录 (`https://models.dev/api.json`)，用于自动识别大模型的上下文窗口尺寸、思考参数配置（Reasoning Effort / Budget）等能力。
- **[DanbooruSearch (HuggingFace Space)](https://huggingface.co/spaces/SAkizuki/DanbooruSearch)**：基于语义向量匹配的在线 Danbooru 标签搜索引擎（由 SAkizuki / SuzumiyaAkizuki 提供），提供模糊自然语言转标签、标签共现推荐及擅长画师（NPMI）推荐 API。
- **[Danbooru 官方站点](https://danbooru.donmai.us)**：官方标签别名同步服务。

### 4. 主要 Dart / Flutter 开源依赖 (Pub Packages)

| 依赖包 (Package) | 用途说明 |
| :--- | :--- |
| **`http`** (`^1.2.1`) | 处理与 NovelAI、LLM 供应商、models.dev 及 DanbooruSearch 的 HTTP / SSE 通信 |
| **`archive`** (`^3.6.1`) | 纯内存解压 NovelAI 官方返回的 ZIP 格式图像与元数据流 |
| **`sqlite3`** & **`sqlite3_flutter_libs`** | 本地 SQLite 引擎，用于极速解析与更新 Danbooru 离线标签库 |
| **`window_manager`** (`^0.5.2`) | 桌面端无边框窗口控制、窗口大小/位置监听与持久化 |
| **`pasteboard`** (`^0.5.0`) | 桌面端剪贴板原生图片与文本复制交互 |
| **`flutter_markdown`** (`^0.7.7+1`) | AI 对话消息、思考链与 Skill 规范的 Markdown 渲染 |
| **`msgpack_dart`** (`^1.0.1`) | MessagePack 二进制数据流编解码 |
| **`shared_preferences`** (`^2.2.3`) | 本地用户配置、生图参数与界面状态持久化 |
| **`file_picker`** (`^8.0.0`) | 跨平台文件、图片与词组合预设库导入导出选取器 |
| **`path`** & **`path_provider`** | 跨平台文件路径拼接与系统专属存储目录定位 |
| **`intl`** (`^0.19.0`) | 国际化、时间日期格式化与数值格式化 |
| **`crypto`** (`^3.0.3`) | SHA-256 哈希校验与数据完整性校验 |

---

## 🙏 致谢与参考项目 (Acknowledgments & References)

NovelAI Harness 的诞生离不开开源社区优秀项目的启发与技术积累。在此向以下开源项目、开发者及社区贡献者致以崇高的敬意与由衷的感谢（排名不分先后）：

### 1. [Pi Agent Harness (@earendil-works)](https://pi.dev)
- **项目仓库**：[`pi`](https://github.com/earendil-works/pi) (`@earendil-works/pi-agent-core`, `@earendil-works/pi-ai`, `@earendil-works/pi-coding-agent`)
- **参考与借鉴内容**：
  - **极简 AI Harness 架构哲学**：借鉴 Pi 的 Minimalist Harness 理念，构建了轻量级、低耦合的 Agent 事件流循环调度器 (`agent_harness.dart`)。
  - **渐进式技能加载体系 (Progressive Disclosure)**：实现了标准 `SKILL.md` 规范与 `load_skill` 动态按需加载机制，避免长上下文污染。
  - **会话持久化与分支回溯规范**：会话日志记录器 (`session_log_service.dart`) 采用 Pi 官方 JSONL 结构，支持消息树分支回溯与状态恢复。
  - **增量用量账本机制**：借鉴 `pi-bill` 账本设计思路，实现基于本地日志的增量 Token 用量统计与按天/供应商聚合。
  - **统一模型能力元数据源**：引入与 Pi 一致的 `models.dev` 目录解析与启发式能力推断逻辑。

### 2. [Aaalice_NAI_Launcher (Aaalice233)](https://github.com/Aaalice233/Aaalice_NAI_Launcher)
- **项目仓库**：[`Aaalice_NAI_Launcher`](https://github.com/Aaalice233/Aaalice_NAI_Launcher)
- **参考与借鉴内容**：
  - **Anlas 预计消耗算法 (`AnlasCalculator`)**：完整移植了针对 NovelAI V3/V4/V4.5/V5 的现代计费公式、Opus 免费生图判定逻辑、V5 专属体力配额透支检测以及新版超分接口的分档计费规则。
  - **多角色归一化坐标与自动布局体系**：参考了角色在 `[0.0, 1.0]` 归一化坐标系下的自动网格排版算法与默认负面词预设。
  - **NovelAI 官方协议封装细节**：参考了多角色参数（`characterPrompts`、`v4_prompt.caption.char_captions`、`centers`、`use_coords`）在不同模型版本下的构建与传递规则。

### 3. [DanbooruSearch (SAkizuki / SuzumiyaAkizuki)](https://github.com/SuzumiyaAkizuki/DanbooruSearch)
- **项目仓库**：[`DanbooruSearch`](https://github.com/SuzumiyaAkizuki/DanbooruSearch) / [`ComfyUI-DanbooruSearcher`](https://github.com/SuzumiyaAkizuki/ComfyUI-DanbooruSearcher) / [HuggingFace Space](https://huggingface.co/spaces/SAkizuki/DanbooruSearch)
- **参考与借鉴内容**：
  - **在线语义检索与标签推荐 API**：集成了 DanbooruSearch 的语义向量搜索接口 (`/search`)、标签共现关联接口 (`/related`) 以及基于 NPMI 的擅长画师推荐接口 (`/artists`)，并封装为 Agent 工具与在线补全增强。

### 4. [Plana-App (mc5024)](https://github.com/mc5024/Plana-App)
- **项目仓库**：[`Plana-App`](https://github.com/mc5024/Plana-App)
- **参考与借鉴内容**：
  - **提示词 AST 解析与权重引擎 (`PromptAstEngine`)**：参考了其对 NovelAI `{}`/`[]` 与 SD `(tag:weight)` 语法的 AST 分词、权重增减、语法双向转换及注释禁用（`#` / 删除线）算法。
  - **中文标签首段提取逻辑 (`cnHead`)**：参考了在中英多模态检索中对中文别名首段的高效截取与匹配算法。
  - **富文本标签语法高亮视觉设计**：参考了按 Danbooru 官方分类为 Prompt 标签着色及权重透明度淡显的视觉呈现方案。

### 5. [NovelAI Prompt Autocomplete & nai5-prompting (Miint-Sunny / saltysalrua)](https://github.com/Miint-Sunny/nai-autocomplete)
- **项目仓库**：[`nai-autocomplete`](https://github.com/Miint-Sunny/nai-autocomplete) / [`nai5-prompting`](https://github.com/Miint-Sunny/nai5-prompting)
- **参考与借鉴内容**：
  - **标签自动补全悬浮窗交互**：参考了光标跟随悬浮卡片、分类色条指示、热度展示与无缝键盘选词上屏的交互体验。
  - **NovelAI V5 提示词指南与内置 Skills**：参考了 `nai5-prompting` 关于 V5 散文提示词架构、漫画多格分镜排版、文字嵌入以及管道符 `|` 物理防串色隔离的系统提示词设计。
  - **词库预设与组合管理思想**：参考了常用 Prompt 词组合的分类存储与复用设计。

### 6. [Danbooru Tag Chinese Translation Table (ffdkj)](https://github.com/ffdkj/Danbooru_Tag-Chinese-English-Translation-Table)
- **项目仓库**：[`ffdkj-Danbooru_Tag-Chinese-English-Translation-Table`](https://github.com/ffdkj/Danbooru_Tag-Chinese-English-Translation-Table)
- **参考与借鉴内容**：
  - **32万+ 离线标签中英对照数据库**：为本项目的离线词库提供了高质量的 Danbooru 标签中英对照、使用计数与分类基础数据，并支持通过应用内更新服务无缝同步每日最新构建。

---

## 🛠️ 快速开始与开发指南

### 环境要求

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (`>= 3.12.0`)
- [Dart SDK](https://dart.dev/get-dart) (`>= 3.12.0`)
- 支持的操作系统：Windows 10/11、macOS 或 Linux

### 安装与运行

1. **克隆仓库**：
   ```bash
   git clone https://github.com/your-username/Novelai-harness.git
   cd Novelai-harness
   ```

2. **获取依赖**：
   ```bash
   flutter pub get
   ```

3. **启动应用程序**：
   ```bash
   flutter run -d windows    # Windows 桌面端
   # 或
   flutter run -d macos      # macOS 桌面端
   # 或
   flutter run -d linux      # Linux 桌面端
   ```

### 自动化验证与测试

在提交代码或修改前，请确保通过所有静态分析与单元测试：

```bash
# 执行代码静态分析
dart analyze

# 运行全量自动化单元测试与 Widget 测试
flutter test
```

---

## 📄 开源许可证 (License)

本项目采用 [MIT License](LICENSE) 许可证开源。请在使用前仔细阅读上述 [第三方提醒与免责声明](#️-第三方提醒与免责声明-third-party-notices--disclaimers)。

