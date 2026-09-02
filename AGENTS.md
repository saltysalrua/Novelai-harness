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
│   │       ├── agent_harness.dart              # 核心 Agent 循环调度器 (多轮对话/工具执行/轮数上限/瞬态自动重试/耗尽收尾)
│   │       ├── session_recorder.dart           # 会话记录器抽象接口 (Pi 格式落盘钩子)
│   │       ├── presets/
│   │       │   └── agent_preset.dart           # Agent 预设模型 (系统提示词/可用Skills/工具与参数权限)
│   │       ├── providers/
│   │       │   ├── llm_provider.dart           # LLM 提供商通用接口
│   │       │   └── openai_provider.dart        # OpenAI 兼容协议流式实现 (支持 SSE 与思考链)
│   │       ├── tools/
│   │       │   ├── agent_tool.dart             # 工具抽象基类与工具注册中心
│   │       │   ├── annotation_tools.dart       # 图像批注五件套工具与覆盖层离屏渲染 (view/add/update/remove/clear_image_annotations)
│   │       │   ├── ask_user_tool.dart          # 向用户提出结构化问题 (选项+自定义回答)
│   │       │   ├── canvas_view_tool.dart       # 画板历史图片查看工具 (支持索引从新到旧与角色覆盖层)
│   │       │   ├── character_prompt_tools.dart  # 多角色提示词增删改查四件套工具
│   │       │   ├── danbooru_search_tools.dart  # Danbooru 离线/在线语义搜索与画师推荐工具
│   │       │   ├── load_skill_tool.dart        # Pi 标准按需加载专业技能工具 (Progressive Disclosure)
│   │       │   ├── novelai_tools.dart          # 生图、放大、标签联想与账号查询工具实现
│   │       │   ├── novelai_inpaint_tool.dart   # 局部修复与焦点特写工具 (novelai_inpaint / get_inpaint_geometry)
│   │       │   ├── ai_edit_image_tool.dart    # AI 整图编辑工具 (ai_edit_image，外部绘图模型整图重绘)
│   │       │   ├── prompt_library_tools.dart   # 词组合预设库增删改查工具
│   │       │   ├── studio_params_tool.dart     # 实时同步修改工作台 UI 生图参数工具
│   │       │   └── vision_image_codec.dart     # 视觉附件压缩 (最长边 1024 等比重编码 PNG) 与 MIME 嗔探
│   │       └── skills/
│   │           └── skills.dart                 # 内置技能库 (V5 自然语言与空间视觉架构师)
│   │
│   ├── data/                                   # 数据层
│   │   ├── models/
│   │   │   ├── novelai_models.dart             # 聚合出口 barrel (转发导出下列拆分文件，保持旧 import 路径不变)
│   │   │   ├── inpaint_models.dart             # 局部重绘与焦点特写几何/参数数据模型 (InpaintMode / InpaintGeometry / InpaintParams)
│   │   │   ├── nai_catalog.dart                # NaiModel/采样器/噪声调度/分辨率预设枚举 (含 inpaintModelId 映射)
│   │   │   ├── nai_character_prompt.dart       # 多角色提示词与位置布局模型
│   │   │   ├── nai_generation_params.dart      # 生图参数与官方 payload 构建 (含 toInfillApiPayload)
│   │   │   ├── nai_image_result.dart           # 生成结果图片与流式进度数据 (含放大/导入来源标记与角标文案)
│   │   │   ├── nai_account_info.dart           # 账号/体力池与 Tag 联想响应
│   │   │   ├── nai_prompt_presets.dart         # 质量词/UC 预设与提示词文本后处理
│   │   │   ├── prompt_library_models.dart     # 词组合预设分类常量与 PromptComboEntry 模型
│   │   │   ├── llm_models.dart                # LLM 协议/思考强度/模型与供应商配置
│   │   │   ├── tag_models.dart                 # Danbooru 标签分类、联想条目与 NovelAI Token 结构
│   │   │   ├── image_annotation.dart           # 图像批注模型 (rect 选区/point 图钉/global 整图，归一化坐标+Notion 调色板)
│   │   │   ├── canvas_board_models.dart        # 自由大画布节点模型 (图片卡/便利贴/画布数据，含 JSON 序列化)
│   │   │   └── image_metadata_models.dart      # 图像元数据与水印配置数据模型 (ImageMetadataResult / WatermarkConfig)
│   │   ├── services/
│   │   │   ├── inpaint_service.dart            # 焦点特写外延几何计算 (对齐 1MP 潜空间与 64 步长网格)、裁剪放大与客户端无损回贴引擎
│   │   │   ├── image_edit_service.dart         # AI 整图编辑服务 (OpenAI 兼容 /chat/completions 传图返图，兼容四种返回格式)
│   │   │   ├── novelai_service.dart            # NovelAI 官方 HTTP 通信、并发锁与 Zip 解包 (含 generateInfill / generateInfillStream)
│   │   │   ├── config_service.dart             # 本地配置与 ~/.pi/agent/novelai.json 自动识别
│   │   │   ├── session_log_service.dart        # Pi 官方会话格式 JSONL 记录与恢复
│   │   │   ├── usage_ledger_service.dart       # Token 用量增量账本 (pi-bill 式按天/供应商/模型聚合)
│   │   │   ├── llm_model_fetcher.dart          # 在线拉取远程 LLM 模型列表与能力元数据解析
│   │   │   ├── models_dev_catalog.dart         # models.dev 在线模型能力目录 (拉取/缓存/模糊匹配)
│   │   │   ├── tag_dictionary_service.dart     # 14万+ Danbooru 离线词库检索、多模态反查与缓存服务 (含词组合注入)
│   │   │   ├── prompt_library_service.dart     # 词组合预设库持久化/检索/预览图管理与 JSON 导入导出
│   │   │   ├── prompt_ast_engine.dart          # NovelAI 提示词 AST 分词、权重增减与 SD 语法转换引擎
│   │   │   ├── window_state_service.dart       # 桌面端窗口尺寸、坐标与最大化状态监听与防抖持久化服务
│   │   │   └── image_metadata_service.dart     # PNG Chunks/Alpha LSB 隐写读取、元数据抹除与嵌入服务 (水印/盲水印管道已迁至 watermark_service)
│   │   │   └── watermark_service.dart        # 水印合成 (自动对比度/智能选位)、盲水印 Koch-Zhao DCT 嵌入提取与统一导出管道
│   │   └── repositories/
│   │       └── novelai_repository.dart         # 图片落盘存储、历史记录与业务聚合 (含 generateInpaint / generateInpaintStream 管道)
│   │
│   └── ui/                                     # 表现层
│       ├── core/
│       │   ├── theme/
│       │   │   └── app_theme.dart              # 暗黑工作台主题与调色板
│       │   └── widgets/
│       │       ├── resizable_split_view.dart   # 可自由拖动分割线的三栏自适应容器
│       │       ├── custom_title_bar.dart       # 顶部自定义标题栏 (窗口拖拽与三键控制)
│       │       ├── context_menu.dart           # 右键菜单 (Notion 风格，图标+分隔线可扩展)
│       │       └── smooth_scroll_controller.dart # 平滑滚轮控制器 (重写 pointerScroll 为短滑动)
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
│               │   ├── studio_view_model.dart  # Studio 状态管理中枢：核心状态 Mixin (_StudioCore 全字段+共享签名) + ViewModel 主体 (init/updateConfig/selectModel)
│               │   ├── studio_vm_layout.dart    # 布局分部：分割线防抖落盘/侧栏页签 (同库 part+Mixin)
│               │   ├── studio_vm_harness.dart   # Harness 分部：工具装配/LLM与思考强度切换/预设技能工具 CRUD
│               │   ├── studio_vm_generation.dart # 生图分部：生图/超分/实时预览/账号 (含 _applyGeneratedImage 统一落图与 _raw.png 保护)
│               │   ├── studio_vm_inpaint.dart   # 修复分部：工具状态/描边增删/发送到修复/批注转选区与执行流水线 (含中间帧预览透传)
│               │   ├── studio_vm_chat.dart      # 对话分部：对话流/图片附件/ask_user/付费确认/用量记录/流式通知节流
│               │   ├── studio_vm_sessions.dart  # 会话分部：会话管理/回溯
│               │   ├── studio_vm_characters.dart # 角色分部：多角色提示词编辑与画板定位
│               │   ├── studio_vm_slash.dart     # 斜杠分部：斜杠指令分发
│               │   ├── studio_vm_library.dart  # 词库分部：词组合加载/增删改/导入导出/应用到工作台
│               │   ├── studio_vm_annotations.dart # 批注分部：自由大画布节点/便利贴 CRUD 与批注同步 (含 sendAnnotationsToChat)
│               │   ├── chat_checkpoints.dart   # 消息树分支检查点 (回溯视图数据结构)
│               │   ├── param_snapshot_journal.dart # 生图参数快照日志 (参数工具差异记录)
│               │   └── slash_command_catalog.dart # 内置斜杠指令目录单一数据源 (补全+/help 共用，含 /nai 方向标志解析)
│               ├── views/
│               │   └── studio_view.dart        # 工作台主界面
│               └── widgets/
│                   ├── studio_sidebar.dart      # 最左侧导航栏 (参数/提示词/修复/词库多页切换)
│                   ├── parameter_card.dart      # 左侧面板薄壳：三页 IndexedStack + 生成坞
│                   ├── parameters_page.dart     # 页面一：模型/分辨率/采样属性/高级选项 (含元数据删除/水印 2D 面板/保持原图开关)
│                   ├── prompts_page.dart        # 页面二：正负提示词双模式与提示词扩展甲板
│                   ├── inpaint_page.dart        # 页面三：Notion 极简修复卡片 (模式切换/几何卡片/上下文外延与噪声滑块/提示词复用)
│                   ├── inpaint_canvas_overlay.dart # 修复画板 InpaintRepairCanvas：独立单图画布 (contain 居中与源图严格对齐) + 框选/画笔/橡皮三工具 + 四角手柄缩放 + 外延上下文虚线框 + 执行中预览帧 + 顶部浮动工具坞
│                   ├── prompt_extension_deck.dart # 提示词扩展甲板 (多角色 ↔ 固定词缀左右滑动切换)
│                   ├── character_card_item.dart # 单角色编辑卡 (名称/启停/位置胶囊+正负词拖拽调高)
│                   ├── character_position_canvas_view.dart # 中间画板角色位置交互层 (锚点拖拽/5x5 网格/悬浮控制)
│                   ├── chat_image_attachment.dart  # 对话图片附件 (归一化≤1024px PNG + 缩略图共用组件)
│                   ├── prompt_editor_card.dart  # 通用提示词编辑卡 (只读灰色标签+输入框+工具条+快捷操作)
│                   ├── prompt_edit_actions.dart  # 光标标签操作共享工具 (权重增减/禁用/格式化，快捷键与按钮共用)
│                   ├── prompt_resize_handle.dart # 高度调节手柄 + ResizableTextField 可拖拽调高输入区 (含快捷键与补全挂载)
│                   ├── prompt_library_view.dart # 全屏词库管理视图 (顶栏/分类侧栏/词组合网格)
│                   ├── prompt_combo_card.dart   # 词组合画廊卡片 (预览图+应用叠加条+右键菜单)
│                   ├── prompt_combo_edit_dialog.dart # 词组合新建/编辑弹窗 (左侧预览图+右侧表单)
│                   ├── rich_prompt_text_controller.dart # NovelAI 富文本语法高亮控制器 (权重/记号淡显/分类着色/删除线)
│                   ├── tag_autocomplete_overlay.dart # 补全悬浮锚点 (光标跟随定位/键盘导航/防抖搜索)
│                   ├── tag_autocomplete_card.dart   # Danbooru 浮动补全建议卡片 (分类胶囊/中英双语/热度/选中滚动置顶)
│                   ├── tag_suggestion_tile.dart  # 标签分类胶囊与热度计数共享小组件
│                   ├── tag_browser_dialog.dart  # Danbooru 标签灵感库与分类速查浏览器弹窗
│                   ├── tag_inspiration_presets.dart # 标签灵感库内置分类与精选标签数据源
│                   ├── fixed_affixes_panel.dart # 固定词缀编辑卡内容 (Prefix/Suffix 拖拽调高)
│                   ├── generate_dock.dart       # 底部操作坞：账号/体力/免点 + 生成按钮
│                   ├── resolution_pad_picker.dart # 2D 可视化分辨率画板
│                   ├── watermark_pad_picker.dart # 水印设置面板 (自动对比度/智能选位/盲水印开关与载荷/滑块 + 画板定位胶囊)
│                   ├── watermark_position_overlay.dart # 水印 2D 位置与自由缩放画板交互层 (拖拽/缩放手柄/滚轮微调)
│                   ├── canvas_position_floating_controls.dart # 角色/水印位置编辑悬浮控制栏 + 滚轮循环切换监听 + 性别芯片推导
│                   ├── metadata_reader_dialog.dart # Notion 极简风格图像元数据解析弹窗 (参数网格/角色卡/Raw JSON/一键填入)
│                   ├── image_canvas_card.dart  # 中间：大图交互画板与历史轮播主壳 (支持拖入带元数据图片自动识别)
│                   ├── image_stream_view.dart  # 流式生图预览与当前图渲染 (含生成中卡片)
│                   ├── image_canvas_actions.dart # 画板操作工具条 (复制脱敏/复制原图/放大/打开目录)
│                   ├── canvas_history_sidebar.dart # 历史图像侧栏 (缩略图轮播 + 放大/导入来源角标)
│                   ├── canvas_overlays.dart     # 画板悬浮层 (未读新图横幅等)
│                   ├── freeform_annotation_board.dart # 自由大画布主壳：无限漫游缩放/参考图拖入粘贴/连线拖拽与落点命中
│                   ├── board_toolbar.dart      # 大画布顶部浮动工具坞 (漫游/圈选/图钉/便利贴/参考图/粘贴/适应视口) + AnnotationToolMode 枚举
│                   ├── board_image_card.dart   # 图片节点卡：顶栏拖拽移动 + 连线端口 + 圈选批注 + 选区/图钉本地拖拽
│                   ├── board_note_card.dart    # 便利贴节点卡：顶栏拖拽移动 + 左侧连线端口 + 文本编辑 + 连线状态
│                   ├── board_wire_painter.dart  # 网格/连线分层绘制器 + BoardLiveOverrides 实时覆盖层 + 落点命中工具函数
│                   ├── annotation_history_strip.dart # 批注模式历史图片侧栏 (拖出参考图到大画布)
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
│   ├── tag_dictionary_test.dart                # Danbooru 词库解析、中英多模态检索与热度排序测试
│   ├── prompt_ast_engine_test.dart             # 提示词 AST 分词、权重增减、禁用切换与 SD 语法转换测试
│   ├── rich_prompt_controller_test.dart        # 富文本语法高亮控制器 TextSpan 渲染测试
│   ├── tag_autocomplete_overlay_test.dart      # 标签自动补全悬浮窗触发与键盘/鼠标上屏测试
│   ├── prompt_library_test.dart               # 词组合模型/服务 CRUD/预览图清理/应用与补全建议测试
│   ├── prompt_library_view_test.dart          # 词库全屏视图与编辑弹窗 Widget 测试
│   ├── chat_image_attach_test.dart           # 用户图片附件序列化/发送/落盘恢复测试
│   ├── view_canvas_image_tool_test.dart       # 画板历史图片查看工具按索引与覆盖层渲染测试
│   ├── image_annotation_test.dart             # 批注模型 JSON 往返与坐标摘要测试
│   ├── board_interaction_test.dart            # 大画布交互回归 (漫游/拖拽/圈选/连线落点命中)
│   ├── image_annotation_ui_test.dart           # 批注画板与历史侧栏 Widget 渲染测试
│   ├── annotation_edit_tools_test.dart         # Agent 批注增删改查工具执行测试
│   ├── view_image_annotations_tool_test.dart   # 批注查看工具与覆盖层离屏渲染测试
│   ├── delete_image_history_test.dart          # 右键菜单删除历史图片与 ViewModel 历史管理集成测试
│   ├── window_state_persistence_test.dart      # 窗口尺寸、位置与最大化状态持久化及防抖测试
│   ├── image_metadata_service_test.dart        # PNG Chunks 与 Alpha LSB 隐写解析、抹除与序列化测试
│   ├── watermark_processor_test.dart           # 水印合成、自动对比度、智能选位、盲水印嵌入提取与导出管道测试
│   ├── metadata_reader_dialog_test.dart        # Notion 风格元数据读取弹窗与工作台参数应用测试
│   ├── advanced_settings_metadata_test.dart    # 高级设置元数据抹除/水印 2D 面板/保持原图开关集成测试
│   ├── inpaint_service_test.dart               # 局部重绘与焦点特写几何、潜空间 1MP 超采样与无损回贴测试
│   ├── inpaint_tools_test.dart                 # Agent 局部修复与几何检查工具执行测试
│   ├── inpaint_ui_test.dart                    # Notion 修复卡片与画板选区交互层 Widget 测试
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
- **超分新协议 (2026-08 换代)**：旧 `api.novelai.net/ai/upscale` 路由已下线。新端点 `https://image.novelai.net/ai/upscale` 改为 **multipart 表单**：`image` 字段为 PNG 图片文件 (filename `blob`)，`request` 字段为 JSON 文件 `{"image":"image","model":"nai-diffusion-5-curated","declared_blur_sigma":0}`；**不再接受 scale 参数**，新超分模型固定倍率输出，输出尺寸必须从返回图片字节解码获得；响应仍为 ZIP 归档 (兼容裸图片字节回退)，Accept 头 `application/x-zip-compressed`。

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
- **官方超分**：按输入面积分档计费，无倍率参数 (新超分模型固定倍率)：`<= 1,048,576 → 1 Anlas`、`<= 1,747,627 → 2`、`<= 2,446,678 → 3`、`<= 3,145,728 → 4`，超过最高档返回 `invalidCost`；Opus 用户输入不超过 `640x640` 时免费。输入尺寸用 `AnlasCalculator.decodeImageDimensions` 从图片字节解码 (不信任 params 上的宽高，可能是文件加载的假参数)，输出尺寸同样从结果字节解码。
- **接入点**：GenerateDock 生成按钮点数标识与提示 (`StudioViewModel.estimatedGenerationCost`)、Agent 生图/超分工具的确认与结果文本、`get_studio_parameters` 报表 (无账号信息时按 Opus/无订阅双价位展示)。服务端计费仍是最终依据。用户手动生图/手动超分**不再弹付费确认卡片** (2026-12)：生成坞按钮已实时显示“生成图片 (N Anlas)”警示色，足够的 UI 提醒已前置；“点数消耗申请”内嵌卡片仅在模型主动调用生图/超分工具 (消耗非零) 时出现。

### 3.3c 图像导出管道：元数据嵌入/抹除、可见水印与盲水印

导出处理单一事实源在 `lib/data/services/watermark_service.dart` 的 `WatermarkService.processExportImage`，顺序固定：可见水印合成 → 元数据抹除 → 盲水印嵌入 (盲水印最后，保证不被后续重编码破坏)。所有接入点 (仓库三处落盘、`getExportImageBytes` 复制导出) 共用这一管道。

- **元数据嵌入**：`ImageMetadataService.embedNovelAiMetadata` 把 Title/Software/Source/Description/Comment (来自 `NaiGenerationParams.toMetadataComment`) 插到 IHDR 后；内存中的 `NaiGeneratedImage.bytes` 始终是带元数据原图，仅落盘/复制时按配置处理 (开启处理且 `keepOriginalImage` 时额外存 `_raw.png`)。
- **可见水印**：2D 位置 posX/posY (0~1 归一化) + 缩放/不透明度/边距百分比，画板交互层 `watermark_position_overlay.dart` 与合成算法严格同构；高度做 contain 钳制防溢出底图。
- **自动对比度** (`autoContrast`)：统计水印覆盖区背景平均亮度，亮背景压暗水印、暗背景提亮 (0.65 混合强度)。
- **智能选位** (`autoPosition`)：降采样 (≤480) 后算亮度梯度能量积分图，32x32 滑窗找能量最低 (细节/边缘最少) 的放置区；`StudioViewModel.applySmartWatermarkPosition` 基于当前画板图一键预览选位。
- **盲水印** (Koch-Zhao DCT)：`_blindPairs` 中频系数对 + xorshift32 PRNG 选对，载荷 `magic('NHWM')+len(2B)+CRC16(2B)+UTF-8 文本` 循环嵌入全图 8x8 块 (≥2 倍容量冗余)；提取时前 64 块直读头部得真实长度，再按 i, i+N, i+2N... 多数投票还原；强度 1~5 控制系数对间距 (10+12s)。UI 入口：WatermarkPadPicker 盲水印区 (开关/文本/强度) + MetadataReaderDialog「提取盲水印」按钮 (注意服务返回 null=无水印，UI 需 `text ?? ''` 与未提取区分)。

### 3.3d 自动保存开关与未保存图片缓存 (2026-08 增)

全局设置 `AppConfig.autoSaveImages` (默认**关**)：

- **开启**：维持旧行为，生图直接按导出设置 (元数据/水印) 写入存储目录根。
- **关闭**：生图/超分结果写入 `<saveDir>/cache/` 子目录 (`NovelAiRepository.kCacheDirName`)，**无水印无导出处理**，图片带 `isUnsaved: true` 标记 (历史缩略图显示「未保存」角标)；重启后从索引恢复的仍是干净原图。持久化索引仍是根目录单一的 `image_history.json` (含缓存与已保存条目，靠 isUnsaved 字段区分)。
- **手动保存**：画板右下角 `CanvasSaveButton` (当前选中图 isUnsaved 时显示) → `StudioViewModel.saveCurrentImageToDisk` → `NovelAiRepository.saveUnsavedImageToDisk`：按导出设置处理 (含 keepOriginalImage 的 `_raw.png` 副本) 写入存储目录根、删除旧缓存文件、更新历史条目为已保存。
- **上限淘汰**：`savePersistedHistory` 裁剪历史时，被裁掉的未保存条目直接删除其缓存文件 ("超出上限直接删掉")；已保存文件永不自动删除。
- **清空历史语义**：`clearAllHistory(autoSave:)` — 自动保存**开启**时仅清空 UI 与索引 (本地文件全部保留)；**关闭**时一并删除整个 cache 子目录 (已保存文件保留)。

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
- `/upscale`：超分放大画板当前图片 (官方新超分模型，固定倍率，无倍率参数)。
- `/account`：查询账号等级与 V5 专属体力池余量。
- `/compact`：手动压缩对话上下文 (把更早消息摘要后移出 LLM 请求，原始消息仍保留在对话流与会话记录中)。
- `/new [标题]`：新建一个空白会话并切换过去。
- `/undo`：撤销上一轮对话 (回复、工具结果与同期参数修改一并回滚；轮数上限收尾提示不算一轮)。
- `/rename <标题>`：重命名当前会话。
- `/sessions`：列出已保存的会话 (前 12 个，带当前标记/消息数/时间)。
- `/clear`：清空会话消息流。

### 3.7 Agent 循环长程执行规范

- **轮数上限**：`AgentHarness.maxTurns` (默认 30，配置项 `AppConfig.agentMaxTurns`，设置页 Defaults 可调，钳制 1..100)。达到上限后注入 user 角色收尾提示，并追加一轮**无工具**的强制总结轮，保证对话永远以最终回答收尾而不是悬挂的工具结果。
- **瞬态自动重试**：`ErrorEvent.transient` 标记瞬态错误 (网络异常/HTTP 408/429/5xx/流解析中断)，Harness 按指数退避 (1s/2s/4s...) 自动重试同轮请求，总预算 `maxRetryAttempts` (默认 3，含首次)。重试前发 `RetryEvent` (ViewModel 转为流式气泡顶部的重试提示)，可重试错误**不直接透传** ErrorEvent，彻底失败才统一报错。重试时重发 `TurnStartEvent` 复位流式缓冲。
- **空响应保护**：无正文无思考无工具调用的空响应视为异常，占用同一重试预算。
- **失败不落盘**：重试预算耗尽的轮次不保存 assistant 消息，半截内容不进上下文与会话记录。

### 3.7b 上下文自适应压缩 (2026-12，参考 pi compaction)

AgentHarness 内置上下文压缩 (lib/core/harness/agent_harness.dart)：

- **自动触发**：每轮请求前估算上下文 Token (优先取窗口内最后一条带用量的 assistant 消息 totalTokens，其后消息按 chars/4 启发式累加，图片按 1200 token/张计)，超过 `contextWindowTokens - compactionReserveTokens` (默认 128000-16384，窗口大小由 ViewModel 装配时写入当前模型卡片的 contextWindow) 时自动压缩。
- **切点算法**：从新到旧回溯累计估算 Token，达到 `compactionKeepRecentTokens` (默认 20000) 预算后取其后最近的 user/assistant 消息为保留窗口起点；绝不在 tool 结果上切 (工具结果必须与其调用同进退)。当前轮的新用户消息永远在保留窗口内。
- **摘要生成**：把待压缩消息序列化为纯文本对话稿 (序列化上限 30 万字符防摘要请求自身超窗)，用当前 LLM 无工具一次性生成结构化中文摘要 (目标/约束与偏好/进展/关键决定/下一步/关键上下文)，已有旧摘要时迭代合并。失败或空摘要时放弃本次压缩，绝不破坏现有上下文。
- **数据模型**：摘要仅存于内存 (`_compactionSummary` + `_contextStartIndex`)，构建请求时注入为一条 user 消息替身；**原始消息仍完整保留在 UI 消息流、`messages` getter 与会话 JSONL 落盘中**，重启后全量回放 (旧图不重发，见 3.9b)，若仍超阈值会在下一次 send 时自动重新压缩。
- **手动触发**：`/compact` 斜杠指令调 `compactContext(force: true)`，跳过预算判断，保留最后一个 user 轮次开始的近期对话，摘要文本以普通消息形式展示在对话流中。
- **状态重置**：回溯到压缩窗口之外、切换会话、清空消息时重置压缩状态 (isCompacted=false)；回溯点在窗口内则压缩状态保留。

### 3.8 LLM 思考参数格式兼容矩阵 (对齐 pi)

- **解析侧**：OpenAiCompatibleProvider 按 pi 优先级短路解析思考流字段：`reasoning_content` (llama.cpp/DeepSeek/Qwen) → `reasoning` (OpenRouter/多数网关) → `reasoning_text`，只取第一个非空字段防双字段重复；另保留自研跨 chunk 内嵌思考标签状态机 (国产网关把 think 标签写进 content)。
- **请求侧**：不同供应商用不同字段开关思维链，格式不匹配时思考会被上游静默丢弃。`LlmProviderConfig.thinkingParamFormat` (设置页 Models 可选，默认 auto 按域名识别)：openai=`reasoning_effort`、deepseek=`thinking:{type}`、qwen=`enable_thinking`、qwen_chat_template=`chat_template_kwargs`、zai=`thinking:{type,clear_thinking}`、openrouter=`reasoning:{effort}`、together=`reasoning:{enabled}`。Qwen/DeepSeek/Z.ai 关闭思考也需显式发送 disabled，因此思考等级始终透传 (含 off)。中转站 (newapi 等) 请按其转发的模型家族手动指定格式。

### 3.9 Agent 对话卡滚动优化与图片附件 (2026-12)

**滚动性能三件套**：

- **平滑滚轮**：`SmoothWheelScrollController` (ui/core/widgets) 重写 `ScrollPosition.pointerScroll`，把桌面端滚轮逐格瞬移改为 160ms easeOutCubic 滑动；滑行中从上次目标累加；DragScrollActivity (滚动条拖动) 时回退默认实现。
- **消息 Widget 缓存**：AgentChatCardState 按 `messageId|thinkingExpanded` 缓存消息 Widget，itemBuilder 返回同实例时 Element 检测 identical 直接跳过重建，Markdown 只解析一次；会话切换/思考开关切换时清空，超 600 条整体清空。ListView 另设 `scrollCacheExtent: 600`、`addAutomaticKeepAlives: false`。
- **流式通知节流**：`_StudioChatMixin` 对 Thought/Content 增量按 40ms 批量 notifyListeners (其余事件立即刷新)，避免每个 token 全工作台重刷。

**流式底部跟随**：`maxScrollExtent` 是 SliverList 的懒估算值，新内容的 extent 可能晚 1-3 帧才结算 (Widget 缓存跳过重建时更明显)。跟随跳转 (`_followStreamBottom`) 必须链式 post-frame 校验最多 3 帧、双向夹到 max (补晚结算增量 + 纠正过高估算回落)；用户是否在底部只能在臂时 (build 阶段) 判断，链式回调里用 "低于上次跟随目标 32px 以上" 判定用户主动上翻并停止跟随。

**用户图片附件** (仅多模态模型)：

- 输入栏 Ctrl+V 挂在 `_inputFocusNode.onKeyEvent` (冒泡链最内层，先于 TextField 默认粘贴)：剪贴板有文本按默认插入；无文本时 `Pasteboard.image` 读图 (Windows 返回 BMP 字节)。
- 📎 按钮调 file_picker 选图；单条消息上限 4 张。
- `processImageAttachment` (chat_image_attachment.dart) 统一归一化：解码 (instantiateImageCodec 支持 BMP) → 最长边 > 1024 等比缩小 → 重编码 PNG → base64。
- 发送链路：`AgentMessageImage` (types.dart) → `AgentMessage.images` → `toOpenAiJson` 升级为 text + image_url(data URL) 多模态内容块 → harness.send(images:) 透传；空文本纯图片消息允许发送。
- 会话落盘：user 消息 JSONL 内容块追加 `{type:'image', mimeType, data}`，恢复时原样回读。
- 非多模态模型发送带图消息时拦截并提示；工具结果附带图片 (查看画板) 平铺渲染在折叠块外，不藏在内。

### 3.9b 图片一次性展示与视觉附件压缩 (2026-12)

解决“agent 吃了一堆图片后不认最新图”的核心机制：

- **图片只给模型看一次**：`AgentMessage.imageEpoch` 记录图片所属的发送轮次 (AgentHarness 每次自增)。构建请求时 (`_buildRequestMessages`)，仅当前轮次新增的图片 (用户附件与工具结果图) 原样发送，更早轮次与重启恢复的历史图片一律通过 `withVisionImagesCollapsed` 折叠为**固定占位文本** (清除 images/imageBase64，正文末尾追加恒定不变的占位符)——控制视觉 Token 且保证提示缓存前缀逐字稳定不被击穿。UI 消息流与会话落盘仍保留原图，模型需要再看画板图时可调 `view_canvas_image`。
- **视觉附件压缩**：`vision_image_codec.dart` 的 `compressVisionImage` 把工具返回的图片 (查看画板/批注合成图 1536px 级 PNG) 等比压到最长边 1024px 重编码 PNG (透明底涂白)，失败回退原字节。接入点：ViewCanvasImageTool、ViewImageAnnotationsTool 默认路径，以及 `sendAnnotationsToChat` 的主图合成图/参考图附件。用户粘贴附件归一化 (1024px PNG) 维持不变。
- **模型可请求原图**：`view_canvas_image` 与 `view_image_annotations` 新增 `full_resolution` 布尔参数 (默认 false)，压缩版看不清细节时传 true 获取未压缩原始尺寸图片；工具结果文本会提示该参数的存在。

### 3.10 自由大画布批注与动态连线 (2026-12)

**进入与数据生命周期**：`setAnnotatingImage(true, {targetImageId})` 进入批注模式，主图与参考图以卡片形式摆放在 6000x6000 画布 (`kBoardCanvasSize`，中心 `kBoardCenterOrigin`)；退出保留画布布局，重进原样恢复，仅当目标主图变化才 `_initBoardData` 重建 (含为既有批注自动生成相连便签)。批注模式与角色位置编辑模式互斥。

**数据模型**：

- `image_annotation.dart`：`ImageAnnotation` (rect 选区 / point 图钉锚点 / global 整图)，坐标为相对图片卡主体的**归一化值** (0.0~1.0)，附 Notion 调色板 `kAnnotationPalette`；`formatCoordinateSummary` 输出像素坐标文本。
- `canvas_board_models.dart`：`CanvasImageNode` (图片卡，主图 isMain 不可删)、`CanvasNoteNode` (便利贴，含 `width`+`height`，`targetImageId`+`targetAnnotationId` 表示连线)、`CanvasImageLink` (参考图连线，支持一对多)、`CanvasBoardData` (含 `viewScale`/`viewTx`/`viewTy` 视口矩阵)，均含 JSON 序列化；节点 JSON 另存 `imageFilePath`+`imageMeta` (不在历史里的参考图重启后按文件重建)。

**交互模型** (freeform_annotation_board.dart)：

- 空白处左键拖拽直接漫游 (无需切工具)；中键/右键/按住空格/漫游工具同样漫游；滚轮以光标为不动点缩放 (`kBoardMinScale`~`kBoardMaxScale`)。
- 图片卡顶栏拖拽移动卡片，右下角手柄拖拽调尺寸 (默认自由缩放，按住 **Shift** 锁定宽高比，`resizeImageNode` 提交)；**圈选/图钉批注仅主图支持，参考图是纯图片卡** (仅拖动/连线/删除/缩放)。选区本体可拖拽移动、**选中态四角圆点手柄拖拽缩放** (对角固定，最小 12px，归一化坐标 clamp 0~1)、图钉可拖拽移动。
- 便利贴右下角手柄拖拽调宽高 (`updateNoteNode` 的 `width`/`height` 参数)；文本编辑区填满卡片剩余高度 (`TextField expands`)。
- 选中选区/图钉后：选区右上角出现 ✕ 删除钮 (锚点删除钮在图钉右侧)，也可按 **Delete/Backspace** 删除 (`removeAnnotationById` 反查所属节点，删除时同步解绑便利贴与参考图连线)。
- **连线只能从便利贴左缘端口与参考图顶栏端口拉出**，落到选区或图钉上建立连接；选区/图钉上的编号徽章仅点击选中，不是连线来源。落点命中测试在画布坐标系进行 (点锚点半径 22、选框包围盒 inflate(6)，图钉优先于选框)，落空取消本次连线、**不误断既有连接** (便签断开用顶栏断开按钮，参考图连线再次拖到同一目标即断开 toggle)。
- **一对多**：`CanvasBoardData.imageLinks` (`CanvasImageLink`：sourceImageId/targetImageId/targetAnnotationId) 存参考图连线，一个选区/锚点可同时挂多条参考图连线与多张便签；`sendAnnotationsToChat` 会汇总关联参考图并把它们 (上限共 4 张) 作为视觉附件发送。
- 连线端点从图钉中心回缩 15px 到徽章边缘 (`retractFromPinBadge`)，避免遮挡编号数字；参考图连线为 Notion 绿虚线，与便签实线区分。
- Ctrl+V 粘贴 / 拖入文件导入参考图；`_handleGlobalKey` 空格漫游、Ctrl+V 与 Delete 必须让位文本输入焦点 (`_isTypingText` 检查 EditableText)。
- **坑 (命中测试)**：Flutter 的 `RenderBox.hitTest` 要求落点在父级 size 内 (`size.contains`)，悬出选区/锚点 Stack 边界外的删除钮/徽章永远点不到——按钮必须收进命中盒 (选区内右上角)，锚点批注用固定 60x26 命中盒 (图钉在左、删除钮在右)。

**性能架构 (拖拽不卡顿的关键)**：

- 卡片与选区拖拽期间只走**本地 state + `BoardLiveOverrides` (ValueNotifier)**，卡片经 `BoardLiveApi` 写入实时位置，连线层 `BoardWirePainter` 通过 `super(repaint: Listenable.merge(...))` 局部重绘，`panEnd` 才提交 ViewModel (`moveImageNode`/`updateNoteNode`/`updateAnnotationInImageNode`)，避免逐帧 `notifyListeners` 全工作台重建。
- 连线画在 `CustomPaint.foregroundPainter` (卡片之上不被图片遮挡)，网格点阵留在 `painter` (卡片之下)。
- 坑：CustomPaint widget **没有** repaint 参数，重绘监听必须挂在 CustomPainter 构造函数上；ValueNotifier 按 `!=` 通知，更新时必须 `withCurrent` 生成新实例，原地改字段不会触发重绘。
- VM 写入顺序：先同步更新 `_boardData` + `notifyListeners` 再 `await` 仓库落盘，否则松手瞬间旧位置会多渲染一帧 (闪回)。

**画布布局持久化 (2026-12 增)**：全部变更入口 (移动/缩放/便利贴/连线/批注) 经 `_scheduleBoardSave` 防抖 600ms 写入 `<saveDir>/canvas_board.json` (仓库 `saveBoardLayout`/`loadBoardLayout`)，dispose 与关闭持久化时立即落盘/删除；外部导入的参考图字节写入 `<saveDir>/board_refs/` (`writeBoardReferenceImage`，不进生图历史)，保存时清理孤立文件；视口矩阵经 `updateBoardViewport` 记录，首帧 `hasSavedViewport` 时原样还原、否则居中。

**Agent 工具** (annotation_tools.dart)：`view/add/update/remove/clear_image_annotations` 五件套统一经 `StudioViewModel.replaceImageAnnotations` 单一写入口 (仓库持久化 + 大画布同步 + 选图引用刷新 + 解绑指向已删除批注的便签与连线，防止幽灵连接)；`renderImageWithAnnotationOverlay` 把批注覆盖层离屏绘制进图片字节 (选区边框/锚点/编号徽章，最长边上限 1536px) 用于多模态视觉附件。`sendAnnotationsToChat` 汇总全部选区像素坐标与便签文本 (含未连接自由便签) 发送到对话并附主图合成图。选区批注右键菜单「发送到修复」直达修复页 (底图+选区+备注一并带入，`sendAnnotationToInpaint`)。

### 3.11 局部修复与焦点特写 (Inpaint / Focus Inpaint，2026-12 重构)

**入口与画板**：侧栏「修复」页签 (`StudioSidebarTab.inpaint`)；开启时中间画板整体切换为独立修复画板 `InpaintRepairCanvas` (不再叠加在图像瀑布流上)：单张底图 contain 居中、与交互层严格同矩形，彻底消除旧覆盖层「用整块画布算 contain 导致选区与图片错位」的问题。图片 contain 区域顶部预留 56px (`_dockTopReserve`) 给浮动工具坞 (工具坞限高约 36px，笔刷滑条 SizedBox 限高 28)，工具坞永不遮挡图片。历史侧栏与右上角展开按钮在修复页签下隐藏 (修复底图不与历史侧栏联动，换底图走图片右键「发送到修复」)。右键菜单入口：图片右键「发送到修复」(`sendImageToInpaint`) / 批注选区右键「发送到修复」(`sendAnnotationToInpaint`)。

**三工具** (`InpaintTool` rect/brush/eraser)：框选 (空白处拖出新选区、选区内拖拽平移、四角 28x28 命中盒手柄缩放)、画笔 (自由绘制描边，归一化轨迹点 + 相对短边半径，提交为 `InpaintBrushStroke`，单击也提交单点盖章)、橡皮 (反向画笔：描边带 isEraser 标记按提交顺序在蒙版上打黑，不是删除描边；覆盖层渲染用 saveLayer 隔离层 + BlendMode.clear，橡皮视觉上真正打穿粉色笔迹，绝不能画成白色叠层)。所有拖拽用「起点+增量」状态机 (`_dragBaseRect` + `_dragStartNorm`，注意新建选区时 base 为 null 不能早退)；手柄缩放必须用 globalPosition 差值且起点存 State 字段——手柄 RenderObject 随选区移动且 rebuild 后局部闭包会丢基准，localPosition 会跳变。蒙版优先级：正向画笔描边优先于矩形选区 (橡皮描边只减不增，`hasBrushMask`/`effectiveSelectionRect` 只统计非 eraser 描边；`buildSourceMask` 仅在存在非橡皮描边时走描边栅格化，只有橡皮描边时回退矩形选区)；橡皮拖拽不参与实时生效选区 (`_liveEffectiveSelNorm` 只算画笔轨迹包围盒)，外延裁剪框不跟随橡皮轨迹，但**提交橡皮描边时**用 `InpaintService.computeStrokeMaskBounds` (256² 低分辨率栅格化剩余白蒙版包围盒) 重算并写入 `InpaintParams.maskBounds`，`effectiveSelectionRect` 优先用它——擦完后松手外扩框才收缩 (Rect.zero=全擦掉回退矩形选区，与 buildSourceMask 同语义；null=旧数据回退几何并集)。清空蒙版/发送到修复需 `clearMaskBounds: true`。`effectiveSelectionRect` 仅做几何计算，UI 渲染选框必须用 `selectionRect`(null=不画框，不得用兜底默认框)。笔刷大小滑条本地拖动、松手 onChangeEnd 才提交 (拖动期间零 notifyListeners)。已提交描层录制为 ui.Picture 缓存 (identical 身份比对 + 尺寸变化才重录)，每帧只增量画进行中的描层。**Picture 必须用图层本地坐标录制** (原点 = 图片左上角)：回放发生在蒙版层 CustomPaint 里，其画布原点已经是 imageRect.topLeft，录制时再加 imageRect.left/top 会被平移两次，描边整体向右下漂移。

**执行入口与完成行为 (2026-12 统一)**：执行修复全局唯一入口是左侧 GenerateDock 主按钮——修复页签下显示「开始修复」(执行中「修复中...」)，其余页签为「生成图片」；修复页与画板工具坞不再携带各自的执行按钮 (旧三按钮已删)。修复完成时强制选中新图 (不弹「有新图」横幅) 并把 `_inpaintSourceImage` 切到新图，画板立即展示修复结果便于继续迭代。修复结果带 `isInpainted` 标记 (`_recordGenerated` 参数)，历史缩略图角标「修复」(优先级：未保存 > 放大 > 修复 > 导入)。

**几何与回贴** (InpaintService 单一事实源，对齐官方网页端/Aaalice 潜空间蒙版协议)：焦点模式 `resolveGeometry` 外延 contextPadding 后等比上采样至 1MP 潜空间 (64 网格对齐)；常规模式 `resolveStandardRequestSize` 按源图实际分辨率 64 网格对齐 (禁止用工作台生成参数宽高去拉伸任意源图，超 3MP 等比收敛)。**发 API 的请求蒙版必须先 `quantizeMaskToLatentGrid` 量化到 8px 潜空间网格** (格中心采样+亮度阈值，与官方一致)；服务端实际重绘区 = 量化后整格。回贴 `compositeFocusedResult`：合成蒙版 = 量化网格再膨胀 4 格 (`latentDilationIterations`) + 盒式模糊羽化 (20px×2，前缀和 O(1)/像素) + alpha 匹配亮度；生成图 RGB + 合成蒙版 alpha 组出补丁、缩小后 BlendMode.alpha 盖回原图——不膨胀会残留原图色环 (量化多出的格子边缘贴不回去)，不羽化会硬接缝。蒙版黑白均为 alpha 255，判定只看 RGB 亮度，禁止把 alpha 计入。image 包 `compositeImage` 的 mask 参数默认按 luminance 通道混合，标准模式可直接用。

**Agent 工具联动 (novelai_inpaint / get_inpaint_geometry ↔ 批注，2026-12 修复)**：`annotation_id` 复用画板批注——矩形批注直用其选区；图钉锚点转为中心 12% 短边小选区 (`kPointAnnotationHalfExtent`)；整图批注无位置明确报错。**批注只提供修复区域，批注文字禁止自动作为修复提示词 (2026-12 二次修正：批注是用户修改意见如「手画歪了」，盲抄当生图提示词会顶掉用户预期的工作台提示词并产出鬼图)**——prompt 留空一律复用工作台当前提示词，agent 需按批注意见修复时应自己翻译成绘制描述后显式传 prompt；工具结果把批注文字作为参考信息展示并注明提示词来源。(UI「发送到修复」仍会把备注填进修复页提示词输入框，但那是用户肉眼可见、点生成前可改的显式操作，与工具端盲抄不同，保持不变。)focus 模式无 rect/annotation_id 必须报错，**禁止静默回退修图片中心** (旧默认 0.25~0.75 框已废除)；rect 解析统一走 `parseToolRectArg`/`normalizeRectPoints` (返回 `ParsedToolRect` record：rect/error/detectedFormat)。**rect 坐标系自动识别 (2026-12，修复 agent 把批注百分比坐标直接抄给修复工具被钳成全图的问题)**：按四值最大值判定——全部 <= 1.0 → 归一化；(1, 100] 且至少两个值 > 1 → 百分比 (批注工具体系，÷100)；> 100 且提供了图片尺寸 → 像素 (按宽高换算，缺尺寸时明确报错而非钳成全图)。单个值轻微超 1 视为归一化越界宽容钳制；负值不预钳制 (保留 l+w 原始求和语义，边缘钳制交给 normalizeRectPoints)；字符串容错 %/px 后缀与逗号。还容错：JSON 序列化字符串 (数组/对象)、逗号/空格分隔四数字符串、{ymin, xmin, ymax, xmax} 与 {x1, y1, x2, y2} 对象键名、嵌套两点 [[x1, y1], [x2, y2]]；无法解析时报错携带收到的原值回显 (截断 80 字符) 便于定位 Agent 实际传了什么。对象写法支持 {left, top, width, height} 与 {left, top, right, bottom} (注意 right/bottom 角点必须映射到 (ymin=top, xmin=left) 而不是照抄 数组位序)。工具结果回显 detectedFormat 教会模型下次直接用对格式；两个工具的尺寸解码 (按真实字节) 必须先于 rect 解析 (像素换算依赖尺寸)。流式 `errorMessage` 必须透传到工具错误文本，不得吞成笼统的「未能生成修复图像」。`get_inpaint_geometry` 支持 annotation_id 且按实际图片字节解码尺寸 (导入图 params 可能是假宽高)。`view_image_annotations` 每条批注输出批注 ID 与可直接复制的归一化 bbox，归一化/百分比/像素三套坐标分行标注，并在存在矩形/图钉批注时提示可用 `annotation_id` 联动修复——否则模型拿不到 ID，联动链路是断的。

**仓库共享管线**：`generateInpaintStream` 与 `generateInpaint` 共用 `_prepareInpaintRequest` (覆盖链/蒙版/几何/请求字节) + `_compositeInpaintResult` (回贴+元数据) + `_persistInpaintResult` (autoSave 缓存/导出处理分支)，禁止再复制双胞胎长函数。中间帧预览走 `_inpaintPreviewBytes` 独立通道 (不占生图预览)。inpaint 模型 ID 映射：V5 Curated 重绘权重尚未就绪，官方网页端映射到 `nai-diffusion-4-5-curated-inpainting` (对齐 Aaalice resolveInpaintingModel)。侧栏页签持久化含 'inpaint' 键名映射。

### 3.12 AI 整图编辑 (AI Image Edit，2026-12 增)

在修复页第三个模式 `InpaintMode.aiEdit`：把整张图片原样发给**外部绘图模型** (如 nano banana / gemini-2.5-flash-image / gpt-image / seedream)，按自然语言指令重绘整图。不消耗 Anlas，计费走绘图模型供应商。

- **独立供应商配置**：`AppConfig.imageEditProviderId` + `imageEditModelId` (持久化键 `image_edit_provider_id` / `image_edit_model_id`)，独立于对话 LLM；getter `imageEditProvider` / `imageEditModel` (未配置返回 null)。设置 Models 页「AI 整图编辑」卡片单独选择供应商与模型 (模型下拉**仅列出 imageOutput 绘图模型**，选中模型被改掉能力时显示「未识别为绘图模型」防悬挂项)；模型拉取自动识别图像输出能力 (`LlmModelConfig.imageOutput`，OpenRouter `architecture.output_modalities` > models.dev `modalities.output` > 关键字启发式 `detectImageOutputCapability`；vision 多模态模型只看不产不误判)，能力可在模型档案弹窗手动修正，模型卡片显示「绘图」胶囊，模型网格工具条有「仅绘图模型」过滤开关。
- **ImageEditService** (`lib/data/services/image_edit_service.dart`)：标准 `/chat/completions`，图片 data URL 放 image_url 内容块 + `modalities:['image','text']`，Content-Type 必须带 `charset=utf-8` (http 包字符串请求体默认 Latin-1，中文指令会炸)。返回解析兼容四种格式：`message.images` 数组 (OpenRouter) / content 内容块数组 / content 字符串内嵌 markdown 或 data URL / http 临时链接自动下载；字节过魔数校验 (PNG/JPEG/WebP/GIF)。429 等待重试一次 (2500ms，可注入)。
- **生图比例/分辨率透传** (各家网关无统一约定)：`InpaintParams.aiEditAspectRatio` (空=跟随原图；1:1/2:3/3:2/3:4/4:3/4:5/5:4/9:16/16:9/21:9) + `aiEditResolution` (空=默认；1K/2K/4K)，服务端按**多写法冗余写入**请求体：`aspect_ratio` + `image_config:{aspect_ratio,image_size}` (google-genai snake_case，对应原生 generationConfig.imageConfig) + `size` (new-api 系网关字段，接受含冒号比例写法)；Go 系网关对未知顶层字段静默忽略，多传无害。修复页 AI 编辑模式有「生成设置」下拉；`ai_edit_image` 工具有 aspect_ratio/resolution 参数 (auto=跟随原图)。
- **仓库管线**：`NovelAiRepository.editImageAi` 调服务后按真实字节解码尺寸，经泛化的 `_persistInpaintResult` (`filePrefix='nai_ai_edit'`, `isAiEdited=true`) 落盘入史；autoSave 关闭时写缓存目录同规则；不嵌入 NovelAI 元数据。角标优先级：未保存 > 放大 > 修复 > AI 编辑 > 导入。
- **UI**：修复页第三模式卡 (选中时隐藏重绘强度/附加噪声/负向词等 NAI 专属控件，信息卡显示绘图模型与未配置引导)；生成坞按钮在 aiEdit 模式下为「开始 AI 编辑」(busy 检查 isExecutingInpaint || isExecutingAiEdit)；修复画板 aiEdit 模式下蒙版层/手势层/缩放手柄全部禁用，工具坞降级为提示胶囊。
- **Agent 工具**：`ai_edit_image` (AiEditImageTool，注册在 harness，预设键 `PresetToolKeys.aiEditImage`)，参数 prompt (自然语言指令，留空复用工作台提示词) / image_index / image_path；未配置时返回引导文案。执行入口：`StudioViewModel.executeInpaint` 在 aiEdit 模式下路由到 `executeAiImageEdit`。

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
