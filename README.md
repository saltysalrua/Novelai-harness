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

## ⚠️ 第三方提醒与免责声明 (Notices & Disclaimers)

- **非官方产品**：本项目为第三方非官方开源工作台，与 **NovelAI (Anlatan, Inc.)** 官方无从属关系。使用前请自备合法 NovelAI 账号并遵守其服务条款。
- **费用提示**：NovelAI Anlas 点数扣除与第三方 LLM API Token 消耗均由用户各自账号承担，请合理配置。
- **凭证安全**：所有 API 密钥均仅保存在本地设备，绝不上传至任何第三方服务器。
- **完整声明**：关于在线服务可用性、数据源版权与字体许可的完整声明，请参阅 [**THIRD_PARTY_NOTICES.md**](THIRD_PARTY_NOTICES.md)。

---

## 📦 第三方资源与开源致谢 (Third-Party & Acknowledgments)

本项目基于 **[MIT License](LICENSE)** 开源，经审查全部直接依赖与内嵌资产均为宽松协议（Permissive Licenses）或免费商用许可，**不包含任何传染性开源许可证（如 GPL / AGPL 等）的代码依赖**。

- 🔤 **字体资产**：**[MiSans](https://hyperos.mi.com/font/zh/)**（小米开源字体，免费商用）。
- 🗄️ **离线词库**：**[Danbooru 32万+ 标签中英对照表](https://github.com/ffdkj/Danbooru_Tag-Chinese-English-Translation-Table)**（ffdkj 每日构建 + Danbooru 官方别名）。
- 🌐 **在线 API**：NovelAI 官方服务、[models.dev](https://models.dev) 元数据目录、[DanbooruSearch](https://huggingface.co/spaces/SAkizuki/DanbooruSearch) 语义检索。
- 🙏 **核心架构与设计参考**：
  - **[Pi (@earendil-works)](https://pi.dev)**：极简 AI Harness 内核哲学、`SKILL.md` 渐进式技能加载、JSONL 会话落盘与 `pi-bill` 账本思想。
  - **[Aaalice_NAI_Launcher (Aaalice233)](https://github.com/Aaalice233/Aaalice_NAI_Launcher)**：Anlas 消耗算法 (`AnlasCalculator`)、多角色归一化坐标排版与官方协议封装。
  - **[DanbooruSearch (SAkizuki)](https://github.com/SuzumiyaAkizuki/DanbooruSearch)**：语义向量匹配、标签共现与画师推荐 API 接入。
  - **[Plana-App (mc5024)](https://github.com/mc5024/Plana-App)**：Prompt AST 语法解析引擎、SD ⇄ NAI 语法转换与富文本分类高亮设计。
  - **[NovelAI Prompt Autocomplete & nai5-prompting (Miint-Sunny)](https://github.com/Miint-Sunny/nai-autocomplete)**：标签补全浮动交互、V5 散文提示词指南与词组合预设库。

> 📄 详细的许可证合规报告、开源包清单及完整版权信息，请查阅 [**THIRD_PARTY_NOTICES.md**](THIRD_PARTY_NOTICES.md)。

---

## 🛠️ 快速开始与开发指南

### 环境要求

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (`>= 3.12.0`)
- [Dart SDK](https://dart.dev/get-dart) (`>= 3.12.0`)
- 支持的操作系统：Windows 10/11、macOS 或 Linux

### 安装与运行

1. **克隆仓库**：
   ```bash
   git clone https://github.com/saltysalrua/Novelai-harness.git
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

