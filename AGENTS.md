# AGENTS.md — NovelAI Harness 项目规范与开发指南

本文档用于规范 **NovelAI Harness** 项目的架构设计、开发规范、核心协议与后续维护要求。

---

## 1. 项目愿景与设计哲学

NovelAI Harness 是一个专为 **NovelAI 图像生成与二次元视觉创作** 设计的极简化、响应式 **Flutter AI Harness**。

### 核心哲学
1. **Pi 风格极简内核**：参考 Pi（Minimalist Agent Harness）设计思想，保持内核精简、低耦合，通过事件流（Event Stream）、动态工具调用（Function Calling）与模块化技能（Skills）驱动 AI 行为。
2. **纯粹与克制的交互表达**：所有界面说明、提示语及工具输出均使用**专业、克制的大白话**，严禁使用夸张符号或冗长无意义的修饰。
3. **高响应性三卡片自适应工作台**：采用可自由拖动分割线的三卡片结构（左：参数设置，中：图像画板，右：AI 对话），小屏幕自动降级适配。
4. **官方协议与并发安全**：严格执行单并发排队（Concurrency = 1）、429 智能退避重试、纯内存 ZIP 数据解包以及精准的 Opus 免点数保护。

---

## 2. 目录结构与分层架构

项目严格遵循 Flutter 推荐的分层架构（Core Harness / Data / UI）：

```text
Novelai-harness/
├── lib/
│   ├── main.dart                               # 应用启动入口
│   │
│   ├── core/                                   # 极简 AI Harness 运行时
│   │   └── harness/
│   │       ├── types.dart                      # 消息、事件、角色与工具调用数据模型
│   │       ├── agent_harness.dart              # 核心 Agent 循环调度器 (多轮对话/工具执行)
│   │       ├── providers/
│   │       │   ├── llm_provider.dart           # LLM 提供商通用接口
│   │       │   └── openai_provider.dart        # OpenAI 兼容协议流式实现 (支持 SSE 与思考链)
│   │       ├── tools/
│   │       │   ├── agent_tool.dart             # 工具抽象基类与工具注册中心
│   │       │   └── novelai_tools.dart          # 生图、放大、标签联想与账号查询工具实现
│   │       └── skills/
│   │           └── skills.dart                 # 内置技能库 (V5 架构师、标签大师、艺术总监)
│   │
│   ├── data/                                   # 数据层
│   │   ├── models/
│   │   │   └── novelai_models.dart             # 模型、采样器、分辨率预设、请求/响应与账号结构
│   │   ├── services/
│   │   │   ├── novelai_service.dart            # NovelAI 官方 HTTP 通信、并发锁与 Zip 解包
│   │   │   └── config_service.dart             # 本地配置与 ~/.pi/agent/novelai.json 自动识别
│   │   └── repositories/
│   │       └── novelai_repository.dart         # 图片落盘存储、历史记录与业务聚合
│   │
│   └── ui/                                     # 表现层
│       ├── core/
│       │   ├── theme/
│       │   │   └── app_theme.dart              # 暗黑工作台主题与调色板
│       │   └── widgets/
│       │       └── resizable_split_view.dart   # 可自由拖动分割线的三栏自适应容器
│       └── features/
│           ├── settings/
│           │   └── views/
│           │       └── settings_dialog.dart    # 全局配置弹窗 (API Key / 存储路径 / LLM)
│           └── studio/
│               ├── view_models/
│               │   └── studio_view_model.dart  # Studio 状态管理中枢 (MVVM)
│               ├── views/
│               │   └── studio_view.dart        # 工作台主界面
│               └── widgets/
│                   ├── parameter_card.dart     # 左侧：参数调节面板
│                   ├── account_stamina_card.dart # 左侧：V5 体力池与点数卡片
│                   ├── image_canvas_card.dart  # 中间：大图交互画板与历史轮播
│                   └── agent_chat_card.dart    # 右侧：AI 对话流与 Slash 命令行
│
├── test/                                       # 单元测试与 Widget 测试
│   ├── novelai_models_test.dart                # 参数构建、Opus 免费算法与 JSON 解析测试
│   ├── agent_harness_test.dart                 # Harness 对话循环与工具调度测试
│   └── widget_test.dart                        # 核心组件渲染测试
│
├── pubspec.yaml                                # 项目依赖配置文件
└── AGENTS.md                                   # 本开发规范文档
```

---

## 3. 核心协议与业务规范

### 3.1 NovelAI 并发与网络保护
- **并发锁 (`AsyncLock`)**：所有发送至 NovelAI 官方端点的绘图（`/ai/generate-image`）和放大（`/ai/upscale`）请求必须通过 `AsyncLock.runExclusive()` 串行执行，确保全局并发数恒等于 1。
- **429 频控退避**：当捕获 HTTP 429 状态码时，必须自动等待 2500ms 并执行单次重试。
- **内存解包**：必须使用纯内存方式（`package:archive`）解压官方返回的 ZIP 数据流，不得生成临时无用文件。

### 3.2 Opus 免点数保护规则
满足以下全部条件时为 **0 Anlas 免费生图**：
1. 像素总数 `<= 1,048,576`（例如 `832x1216`、`1216x832`、`1024x1024`）。
2. 采样步数 `<= 28` 步。
3. 样本数量 `nSamples == 1`。

当用户开启 `opusFreeMode` 时，UI 与参数构建应自动限制尺寸与步数在此区间内。

### 3.3 NovelAI V5 自然语言提示词架构
- **连续自然语言散文**：单人或单场景使用连贯英文散文，禁止堆叠标签，禁止使用 `{}`、`()` 权重修饰符。
- **漫画分镜排版**：声明漫画多格布局（`A dynamic manga page layout, comic strip, multiple sequential panels...`）。
- **原生文字排版**：包含对话气泡或招牌时，使用语法：`text, <样式> "<文字内容>"`。
- **多角色物理防串色隔离**：多角色画面使用管道符 `|` 分隔：`[全局环境与光影] | [左侧角色A] | [右侧角色B]`。

### 3.4 快捷 Slash 指令集
对话框支持以下快捷指令：
- `/help`：查看指令帮助列表。
- `/nai <提示词> [--landscape|--portrait|--square|--wallpaper]`：快速生图。
- `/tag <关键词>`：查询 Danbooru 官方标签联想与使用频次。
- `/upscale [2|4]`：超分放大画板当前图片。
- `/account`：查询账号等级与 V5 专属体力池余量。
- `/clear`：清空会话消息流。

---

## 4. 编码与修改准则

任何对此代码库进行修改的智能体或开发者，必须遵守以下准则：

1. **类型安全与现代 Dart 语法**：
   - 启用强类型与空安全，优先使用模式匹配、Switch 表达式与初始化形参。
   - 避免使用已废弃的 Flutter API（例如避免 `withOpacity`，推荐 `withValues(alpha: ...)` 或语义化颜色定义；使用 `CardThemeData` 而非 `CardTheme`）。
2. **状态管理**：
   - 遵循 MVVM 模式，视图（View）只负责 UI 渲染与事件监听，业务逻辑统一收敛在 `StudioViewModel` 中。
3. **文案规范**：
   - 所有面对用户的中文日志、按钮标签、提示框与帮助文档，务必保持**专业、简洁、大白话**，严禁使用花哨的特殊符号排版。
4. **自动化验证要求**：
   - 任何改动完成后，必须在终端执行并通过：
     ```bash
     dart analyze
     flutter test
     ```
   - 确保分析器报告 `No issues found!`，且所有单元测试保持 100% 通过。
