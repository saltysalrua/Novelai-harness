# AGENTS.md — NovelAI Harness 项目规范与开发指南

本文档用于规范 **NovelAI Harness** 项目的架构设计、开发规范、核心协议与后续维护要求。

---

## 1. 项目愿景与设计哲学

NovelAI Harness 是一个专为 **NovelAI 图像生成与二次元视觉创作** 设计的极简化、响应式 **Flutter AI Harness**。

### 核心哲学

1. **Pi 风格极简内核**：参考 Pi（Minimalist Agent Harness）设计思想，保持内核精简、低耦合，通过事件流（Event Stream）、动态工具调用（Function Calling）与模块化技能（Skills）驱动 AI 行为。
2. **纯粹、直接与克制的交互表达**：所有界面标签、选项名称、提示语与工具输出，均使用**最纯净、直接的大白话与官方标准名称**，严禁使用营销修饰词（如“旗舰版 (最新)”、“大师/无限”等括号后缀）或花哨的装饰符号。
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
│   │       ├── session_recorder.dart           # 会话记录器抽象接口 (Pi 格式落盘钩子)
│   │       ├── presets/
│   │       │   └── agent_preset.dart           # Agent 预设模型 (系统提示词/可用Skills/工具与参数权限)
│   │       ├── providers/
│   │       │   ├── llm_provider.dart           # LLM 提供商通用接口
│   │       │   └── openai_provider.dart        # OpenAI 兼容协议流式实现 (支持 SSE 与思考链)
│   │       ├── tools/
│   │       │   ├── agent_tool.dart             # 工具抽象基类与工具注册中心
│   │       │   ├── ask_user_tool.dart          # 向用户提出结构化问题 (选项+自定义回答)
│   │       │   ├── character_prompt_tools.dart  # 多角色提示词增删改查四件套工具
│   │       │   ├── load_skill_tool.dart        # Pi 标准按需加载专业技能工具 (Progressive Disclosure)
│   │       │   ├── studio_params_tool.dart     # 实时同步修改工作台 UI 生图参数工具
│   │       │   └── novelai_tools.dart          # 生图、放大、标签联想与账号查询工具实现
│   │       └── skills/
│   │           └── skills.dart                 # 内置技能库 (V5 架构师、标签、艺术总监)
│   │
│   ├── data/                                   # 数据层
│   │   ├── models/
│   │   │   └── novelai_models.dart             # 模型、采样器、分辨率预设、请求/响应与账号结构
│   │   ├── services/
│   │   │   ├── novelai_service.dart            # NovelAI 官方 HTTP 通信、并发锁与 Zip 解包
│   │   │   ├── config_service.dart             # 本地配置与 ~/.pi/agent/novelai.json 自动识别
│   │   │   ├── session_log_service.dart        # Pi 官方会话格式 JSONL 记录与恢复
│   │   │   ├── usage_ledger_service.dart       # Token 用量增量账本 (pi-bill 式按天/供应商/模型聚合)
│   │   │   ├── llm_model_fetcher.dart          # 在线拉取远程 LLM 模型列表与能力元数据解析
│   │   │   └── models_dev_catalog.dart         # models.dev 在线模型能力目录 (拉取/缓存/模糊匹配)
│   │   └── repositories/
│   │       └── novelai_repository.dart         # 图片落盘存储、历史记录与业务聚合
│   │
│   └── ui/                                     # 表现层
│       ├── core/
│       │   ├── theme/
│       │   │   └── app_theme.dart              # 暗黑工作台主题与调色板
│       │   └── widgets/
│       │       ├── resizable_split_view.dart   # 可自由拖动分割线的三栏自适应容器
│       │       ├── custom_title_bar.dart       # 顶部自定义标题栏 (窗口拖拽与三键控制)
│       │       └── context_menu.dart           # 右键菜单 (Notion 风格，图标+分隔线可扩展)
│       └── features/
│           ├── settings/
│           │   ├── views/
│           │   │   └── settings_dialog.dart    # 全局配置弹窗壳 (导航+IndexedStack 装配+保存聚合)
│           │   └── widgets/
│           │       ├── settings_shared.dart    # 设置域共享件 (分组标题/设置卡/下拉/操作钮/密钥框/遮罩弹窗)
│           │       ├── general_settings_tab.dart # General 页：服务凭证/存储目录/保护开关
│           │       ├── models_settings_tab.dart # Models 页：供应商/端点/模型卡片与在线拉取
│           │       ├── presets_settings_tab.dart # Presets 页：预设/系统提示词/技能/工具/参数权限
│           │       ├── defaults_settings_tab.dart # Defaults 页：出厂默认模型/采样/步数
│           │       ├── bill_settings_tab.dart  # Bill 页：Token 用量账单表格
│           │       ├── model_card.dart         # 模型小卡片 (选中态/能力胶囊/设置按钮)
│           │       ├── model_profile_dialog.dart # 单模型设置弹窗 (名称/ID/温度/能力)
│           │       ├── skill_card.dart          # 技能小卡片 (启用开关/导出/编辑)
│           │       ├── skill_editor_dialog.dart  # 自定义技能编辑弹窗 (SKILL.md 导入导出)
│           │       ├── tool_card.dart           # 工具小卡片 (启用开关/Schema 查看)
│           │       └── tool_editor_dialog.dart  # 自定义模板工具编辑弹窗
│           └── studio/
│               ├── view_models/
│               │   ├── studio_view_model.dart  # Studio 状态管理中枢 (MVVM)
│               │   ├── chat_checkpoints.dart   # 消息树分支检查点 (回溯视图数据结构)
│               │   ├── param_snapshot_journal.dart # 生图参数快照日志 (参数工具差异记录)
│               │   └── slash_command_catalog.dart # 内置斜杠指令目录单一数据源 (补全+/help 共用)
│               ├── views/
│               │   └── studio_view.dart        # 工作台主界面
│               └── widgets/
│                   ├── studio_sidebar.dart      # 最左侧导航栏 (参数/提示词双页切换)
│                   ├── parameter_card.dart      # 左侧面板薄壳：双页 IndexedStack + 生成坞
│                   ├── parameters_page.dart     # 页面一：模型/分辨率/采样属性/高级选项
│                   ├── prompts_page.dart        # 页面二：正负提示词双模式与提示词扩展甲板
│                   ├── prompt_extension_deck.dart # 提示词扩展甲板 (多角色 ↔ 固定词缀左右滑动切换)
│                   ├── character_card_item.dart # 单角色编辑卡 (名称/启停/位置胶囊+正负词拖拽调高)
│                   ├── character_position_canvas_view.dart # 中间画板角色位置交互层 (锚点拖拽/5x5 网格/悬浮控制)
│                   ├── prompt_editor_card.dart  # 通用提示词编辑卡 (只读灰色标签+输入框+工具条)
│                   ├── prompt_resize_handle.dart # 高度调节手柄 + ResizableTextField 可拖拽调高输入区
│                   ├── fixed_affixes_panel.dart # 固定词缀编辑卡内容 (Prefix/Suffix 拖拽调高)
│                   ├── generate_dock.dart       # 底部操作坞：账号/体力/免点 + 生成按钮
│                   ├── resolution_pad_picker.dart # 2D 可视化分辨率画板
│                   ├── image_canvas_card.dart  # 中间：大图交互画板与历史轮播主壳
│                   ├── image_stream_view.dart  # 流式生图预览与当前图渲染 (含生成中卡片)
│                   ├── image_canvas_actions.dart # 画板操作工具条 (复制/放大/打开目录)
│                   ├── canvas_history_sidebar.dart # 历史图像侧栏 (缩略图轮播)
│                   ├── canvas_overlays.dart     # 画板悬浮层 (未读新图横幅等)
│                   ├── image_lightbox.dart     # 全屏灯箱预览
│                   ├── agent_chat_card.dart    # 右侧：AI 对话卡主壳 (三视图切换+布局组装)
│                   ├── agent_chat_messages.dart # 对话消息平铺渲染块 (user/assistant/toolCall/toolResult/流式)
│                   ├── agent_chat_blocks.dart  # 折叠块与思考块通用组件
│                   ├── agent_chat_input_bar.dart # 对话底部模型/思考强度切换与输入发送栏
│                   ├── slash_command_overlay.dart # 斜杠指令自动补全面板与建议目录
│                   ├── agent_rewind_view.dart   # 历史时刻回溯视图 (双击 ESC 进入)
│                   ├── agent_session_list_view.dart # 会话管理列表视图
│                   ├── inline_agent_question_card.dart # ask_user 内嵌提问卡片
│                   ├── pill_widgets.dart       # 胶囊控件复用 (PillDropdown / ToggleChip)
│                   ├── editable_slider.dart    # 数值微调滑块 (整型/浮点统一实现)
│                   └── studio_shared.dart       # 共享原子件 (标题/下拉框/清空钮/Token条)
│
├── test/                                       # 单元测试与 Widget 测试
│   ├── novelai_models_test.dart                # 参数构建、Opus 免费算法与 JSON 解析测试
│   ├── character_prompt_test.dart              # 角色提示词模型、payload 构建与增删改工具测试
│   ├── novelai_stream_test.dart                # 流式生图预览的分块解码与进度测试
│   ├── agent_harness_test.dart                 # Harness 对话循环与工具调度测试
│   ├── agent_preset_test.dart                  # 预设权限白名单与 JSON 往返测试
│   ├── agent_session_and_rewind_test.dart      # 会话切换与回溯集成测试
│   ├── ask_user_tool_test.dart                 # ask_user 工具参数解析与执行测试
│   ├── chat_checkpoints_test.dart              # 消息树分支检查点测试
│   ├── param_snapshot_journal_test.dart        # 参数快照日志测试
│   ├── studio_params_tool_test.dart            # 生图参数工具执行测试
│   ├── session_log_test.dart                   # Pi 会话格式 JSONL 写入与恢复测试
│   ├── usage_ledger_test.dart                  # Token 用量账本记录、去重与周期聚合测试
│   ├── models_dev_catalog_test.dart            # models.dev 目录拉取/缓存/模糊匹配测试
│   ├── slash_command_overlay_test.dart         # 斜杠指令补全建议与面板测试
│   ├── context_menu_test.dart                  # 右键菜单组件测试
│   ├── settings_dialog_test.dart               # 设置弹窗五标签页渲染冒烟测试
│   ├── character_position_canvas_test.dart    # 画板角色位置编辑全流程集成测试
│   ├── prompt_ui_resize_test.dart              # 调高手柄/编辑卡/甲板切换 Widget 测试
│   └── widget_test.dart                        # 核心组件渲染测试
│
├── pubspec.yaml                                # 项目依赖配置文件
└── AGENTS.md                                   # 本开发规范文档
```

---

## 3. 核心协议与业务规范

### 3.1 纯净、直接的命名与文案准则 (Zero Marketing Fluff)

所有面向用户的标签、选项、按钮和状态必须遵循以下统一标准：

- **模型名称**：直接使用标准 ID 名称，禁止添加营销后缀：
  - `NAI-Diffusion-v5-Full`
  - `NAI-Diffusion-v5-Curated`
  - `NAI-Diffusion-v4.5-Full`
  - `NAI-Diffusion-v4.5-Curated`
  - `NAI-Diffusion-v4-Full`
  - `NAI-Diffusion-v4-Curated`
  - `NAI-Diffusion-v3`
  - `NAI-Diffusion-Furry-v3`
- **账号等级**：直接写纯净等级名称：`Paper`、`Tablet`、`Scroll`、`Opus`。
- **采样算法与噪声调度**：保持纯净名称（`Euler`、`Euler Ancestral`、`DPM++ 2M`、`Karras` 等），不在下拉列表中附带多余的括号解释。
- **操作与状态文案**：
  - 生图按钮统一命名为 `生成图片`。
  - 免点标识统一命名为 `Opus 免费` / `需点数`。
  - 体力栏统一命名为 `V5 体力`，状态为 `已满` / `恢复中` / `X 秒后 +1%`。
  - 步数与 CFG 统一命名为 `步数: 28`、`CFG: 5.0`、`CFG Rescale: 0.00`。

### 3.2 NovelAI 并发与网络保护

- **并发锁 (`AsyncLock`)**：所有发送至 NovelAI 官方端点的绘图（`/ai/generate-image`）和放大（`/ai/upscale`）请求必须通过 `AsyncLock.runExclusive()` 串行执行，确保全局并发数恒等于 1。
- **429 频控退避**：当捕获 HTTP 429 状态码时，必须自动等待 2500ms 并执行单次重试。
- **内存解包**：必须使用纯内存方式（`package:archive`）解压官方返回的 ZIP 数据流，不得生成临时无用文件。

### 3.3 Opus 免点数保护规则

满足以下全部条件时为 **0 Anlas 免费生图**：

1. 像素总数 `<= 1,048,576`（例如 `832x1216`、`1216x832`、`1024x1024`）。
2. 采样步数 `<= 28` 步。
3. 样本数量 `nSamples == 1`。

当用户开启 `opusFreeMode` 时，UI 与参数构建应自动限制尺寸与步数在此区间内。

### 3.3b 预计 Anlas 消耗计算 (AnlasCalculator)

`lib/data/services/anlas_calculator.dart` 移植自 Aaalice_NAI_Launcher 的 AnlasCalculator，所有预估接入点共用这一份单一事实源：

- **基础公式 (现代计费，V3+ 全系适用)**：`ceil(2.951823174884865e-6 × 像素数 + 5.753298233447344e-7 × 像素数 × 步数)`，再乘模型倍率 (`NaiModel.anlasMultiplier`，仅 V5 为 1.5，其余 1.0)，单张下限 2 Anlas、上限 140 Anlas (超出返回 `invalidCost = -3`)。
- **Opus 折扣**：`isOpus && 步数 <= 28 && 像素 <= 1,048,576` 时首张免费；仅 V5 受体力配额池限制 (`NaiAccountInfo.v5QuotaExhausted`，来自 `subscription.usage.isNegative`，透支后不再抵扣)；单次请求多张 (`n_samples > 1`) 只有第一张享受免费折扣。
- **官方超分**：按输入面积分档计费，放大倍数不参与价格：`<= 1,048,576 → 1 Anlas`、`<= 1,747,627 → 2`、`<= 2,446,678 → 3`、`<= 3,145,728 → 4`，超过最高档返回 `invalidCost`；Opus 用户输入不超过 `640x640` 时免费。输入尺寸用 `AnlasCalculator.decodeImageDimensions` 从图片字节解码 (不信任 params 上的宽高，可能是文件加载的假参数)。
- **接入点**：GenerateDock 生成按钮点数标识与提示 (`StudioViewModel.estimatedGenerationCost`)、手动生成/超分的付费确认闸门 (预计非零时先弹问)、Agent 生图/超分工具的确认与结果文本、`get_studio_parameters` 报表 (无账号信息时按 Opus/无订阅双价位展示)。服务端计费仍是最终依据。

### 3.4 NovelAI V5 自然语言提示词架构

- **连续自然语言散文**：单人或单场景使用连贯英文散文，禁止堆叠标签，禁止使用 `{}`、`()` 权重修饰符。
- **漫画分镜排版**：声明漫画多格布局（`A dynamic manga page layout, comic strip, multiple sequential panels...`）。
- **原生文字排版**：包含对话气泡或招牌时，使用语法：`text, <样式> "<文字内容>"`。
- **多角色物理防串色隔离**：多角色画面使用管道符 `|` 分隔：`[全局环境与光影] | [左侧角色A] | [右侧角色B]`。

### 3.5 多角色提示词

仅 V4 及以上模型生效，数量上限按模型区分 (官方文档：V5 为 22、V4/V4.5 为 6，v3 不支持)。参与生成的角色按启用顺序构建官方协议三件套：

- `characterPrompts`: `[{prompt, uc, enabled}]`，自定义定位时追加 `center: {x, y}`。
- `v4_prompt.caption.char_captions` 与 `v4_negative_prompt.caption.char_captions`: `[{char_caption}]`，自定义定位时追加 `centers: [{x, y}]`。
- `use_coords`: 仅在全局关闭 AI 自动布局且存在启用角色时为 true。

角色定位是区块级全局开关 (官方 AI's Choice / Custom)：开启时**不发送任何位置参数**，由模型自行安排；关闭时发送 use_coords=true 与各角色 center，手动定位过的角色用其坐标，未手动定位的按启用顺序自动布局。V5 为自由连续小数坐标 (画布拖拽 + 直接输入)，V4/V4.5 官方限制 5x5 网格 (坐标量化到 1/4 步长)。各角色位置数据在 AI 模式下保留，切回自定义原样恢复。

角色列表持久化在 SharedPreferences (`novelai_character_prompts` + `novelai_character_ai_position` 全局开关)，Agent 通过 `list/add/update/remove_character_prompt` 四个工具增删改查，全局位置模式可经 `update_studio_parameters` 的 `character_ai_position` 参数切换，工具白名单受预设 `enabledToolNames` 控制。人数标签 (如 `2girls`) 写在主提示词，单个角色提示词内用不带数字的 `girl/boy/other`。

内置预设 (BuiltinPresets) 以代码定义为唯一事实来源：`ConfigService.loadConfig` 启动时按 id 用出厂定义覆盖磁盘上的旧副本，保证新版本新增的工具/参数白名单自动升级到已保存的预设；用户自定义预设不受影响。设置页对内置预设只读 (字段 readOnly、开关禁用)，定制需先「复制」生成副本。对话卡思考块默认折叠只显示单行预览，`Ctrl+O` 全局展开/折叠全部思考内容 (流式中的思考不再截断)。

### 3.6 快捷 Slash 指令集

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
   - 所有面对用户的中文日志、按钮标签、提示框与帮助文档，务必保持**专业、简洁、大白话**，严禁使用花哨的特殊符号排版或营销修饰。
4. **自动化验证要求**：
   - 任何改动完成后，必须在终端执行并通过：

     ```bash
     dart analyze
     flutter test
     ```

   - 确保分析器报告 `No issues found!`，且所有单元测试保持 100% 通过。
