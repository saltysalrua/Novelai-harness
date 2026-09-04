# AGENTS.md

- 本项目为 **Flutter 跨平台桌面端应用** (Dart 3 / Windows, macOS, Linux)
- 包管理器 / 构建工具：`flutter` / `pub`
- 架构模式：MVVM (`StudioViewModel` + Mixin 分部组合) + 三层分层架构 (Core Harness / Data / UI)
- UI 规范：Material 3 + Notion/暗黑自研主题 (`AppTheme`) + MiSans 字体

## Project Structure

```text
lib/
├── core/harness/      # 极简 AI Harness 运行时 (调度器/事件流/工具注册/技能系统)
├── data/              # 数据与服务层
│   ├── models/        # 数据模型与协议实体
│   ├── services/      # 核心业务服务与单一事实源 (Anlas/Inpaint/Watermark/AST)
│   └── repositories/  # 数据仓储与图片落盘聚合
└── ui/                # 表现层 (Flutter Widgets)
    ├── core/          # 全局主题 (AppTheme)、自定义标题栏与通用原子组件
    └── features/      # Studio 工作台与 Settings 设置中枢
```

> 完整目录树与各文件职责清单详见 [**ARCHITECTURE.md**](ARCHITECTURE.md)。

## Coding Style

**Dart 现代规范**

- 严格开启强类型与空安全，严禁使用 `dynamic` 或隐式强转（仅外部非类型化 JSON 边界允许）。
- 优先使用模式匹配（Pattern Matching）与 `switch` 表达式。
- 严禁使用废弃 API（禁止 `withOpacity`，统一使用 `withValues(alpha: ...)`；使用 `CardThemeData` 而非 `CardTheme`）。
- 私有变量与内部方法严格使用下划线 `_` 前缀，命名表意清晰直接。

**MVVM 状态与渲染规范**

- 视图（View）只负责 UI 布局与手势捕获，严禁在 View 中直接发起网络请求、处理业务计算或直接写仓储。
- 业务逻辑与响应式状态统统收敛在 `StudioViewModel` 及其 Mixin 分部中。
- 高频交互（分割线拖拽、大画布漫游、画笔绘制、水印微调）必须使用 `ValueNotifier` 或图层隔离（`BoardLiveOverrides`、`ui.Picture`），严禁逐帧调用 `notifyListeners()`。

**UI 原子组件复用规范 (Atomic Components First)**

- 界面搭建优先复用既有原子组件，严禁并行新造功能重复的组件；新代码动笔前必须先检索既有组件（`lib/ui/core/widgets/`、`studio_shared.dart`、`pill_widgets.dart`、`settings_shared.dart`、`editable_slider.dart`、`prompt_editor_card.dart` 等），找不到才允许新建。
- 同类交互与视觉形态必须统一类型：分组标题、卡片容器、胶囊选择器、下拉、滑块、输入框、开关行、徽章等一律使用既有原子组件，保证全应用观感与行为一致。
- 拆分大文件 (View/Widget) 时，严禁简单按行数切块搬运：优先用既有原子组件替换内联重复 UI；既有原子组件覆盖不到的重复片段，必须沉淀为新的原子组件（放 `lib/ui/core/widgets/` 或对应共享文件）再复用，而不是复制到新文件里各自为政。
- 原子组件必须保持无业务状态、参数化驱动（回调/配置注入），不得耦合 `StudioViewModel` 或具体业务逻辑。

**业务单一事实源 (SSOT)**

- 点数与免费判定：统一接入 `AnlasCalculator`。
- 局部修复几何与回贴：统一接入 `InpaintService`。
- 图像导出与水印管道：统一接入 `WatermarkService`。
- 离线标签检索：统一接入 `TagDictionaryService`。

**文案规范 (Zero Marketing Fluff)**

- 严禁使用任何营销修饰词（如“旗舰版 (最新)”、“无限/大师”等括号后缀）。
- 界面标签、选项与按钮统一使用官方标准名称与纯净大白话（`生成图片`、`开始修复`、`开始 AI 编辑`、`Opus 免费`、`需点数`、`V5 体力`）。

## Workflow (作业流程)

1. **意图分析与影响评估**：明确任务范围与诉求，识别受影响的架构分层（Core / Data / UI）及特定的 ViewModel Mixin 或 Service；评估单 Agent 独立闭环可行性，需并行或委派时按「多 Agent 协作规范 (Orca)」的模式判定分流。
2. **代码检索与事实源定位**：优先使用 `grep_search` 与 `find_by_name` 检索既有代码，严禁凭空臆造 API 或写平行重复逻辑。
3. **规范编码与状态收敛**：严格遵循 MVVM 模式，将状态收敛在 ViewModel，业务计算收敛在 Service，并保障高帧率图层隔离。
4. **质量门禁 (Quality Gate)**：代码修改后必须无条件执行并通过以下两道门禁；**多 Agent / 多会话共用同一 worktree 时，全量门禁必须统一走 `dart run tool/gates.dart`**（内置跨进程互斥锁，并发调用自动排队串行，杜绝两个全量 `flutter test` 竞态共享 `.dart_tool/flutter_build` 与 Windows 文件锁——结构安全，不依赖任何一方自觉）：
   - 门禁 1：`dart analyze`（必须 0 警告 / No issues found!）
   - 门禁 2：`flutter test`（全量自动化测试套件必须 100% 通过）
   - 受监督编排中，双门禁对子 Agent 具有同等约束力：Worker 汇报 `worker_done (succeeded)` 前须在子工作区自检通过，Coordinator 合并后须在主工作区复测。Worker 自检可用 `dart run tool/gates.dart test test/<自己的测试文件>` 缩小范围（同样过锁，天然安全）；单 Agent 独占会话时直接裸跑 `dart analyze` / `flutter test` 亦无妨。

## Build & Test Commands

```bash
flutter run -d windows    # 启动 Windows 桌面端调试
flutter run -d macos      # 启动 macOS 桌面端调试
flutter run -d linux      # 启动 Linux 桌面端调试
dart analyze              # 静态代码检查 (门禁：必须 0 警告)
flutter test              # 运行自动化测试套件 (门禁：全量用例必须 100% 通过)
dart run tool/gates.dart  # 统一门禁入口：跨进程互斥锁串行化 (多 Agent 共用 worktree 时强制)
```

## 多 Agent 协作规范 (Orca)

本机使用 Orca CLI 进行多 Agent 协作。**Orca 子命令与参数标志随版本演进，遇到具体语法疑问必须动态执行 `orca skills get orca-cli` 与 `orca skills get orchestration` 检索实时权威手册，严禁凭记忆罗列底层标志。**

**模式判定 (先分流，严禁混用生命周期)**：

| 模式 | 完全移交 (Full Handoff) | 受监督协作 (Supervised Orchestration) |
| --- | --- | --- |
| 触发语义 | "移交 / handoff / 给另一个 agent" | "监督 / 等待结果 / 跟踪 / DAG / 决策门" |
| 命令管线 | `orca worktree create --name <task> --agent <id> --prompt "<任务简报>" --json` | `run-create → task-create → worker-start → check --wait --types worker_done,escalation,question → worker-release` |
| 通信 | 无。目标 Agent 直接对用户负责，交付后回报并结束当前回合 | Worker 用 `ask` 提问，Coordinator 用 `reply --id <msg_id> --body <text>` 响应 |
| 核心禁令 | 严禁 `task-create` / `dispatch --inject` / `check --wait` / 轮询终端 | 严禁收到 `worker_done` 后遗漏 `worker-release --dispatch <dispatch_id>` |

**Worker 执行契约**：

- 仅在收到有效 Orchestration 前导 (Live Preamble) 时才可发送生命周期消息；任务结束必须且仅调用一次 `worker_done` (含 `--task-id` / `--dispatch-id` / `--outcome`)。
- Worker 发送 `--outcome succeeded` 前，必须在子工作区跑通项目双门禁（`dart analyze` 0 警告 + `flutter test` 100%）并在 body 附执行证据；Coordinator 合并分支后必须在主工作区无条件复测双门禁。

**协作纪律**：

- 非必要不新建 Worktree：常规代码修改优先在当前工作区开独立终端 (peer agent)；仅深层分支隔离或依赖排他时才 `worktree create`。**需要多个 Agent 各自跑全量门禁时属于依赖排他场景，必须 `worktree create` 物理隔离**（各自独立 `.dart_tool` 与 git index，天然零竞态），由 Coordinator 合并分支后在主工作区复测。
- 同一 worktree 内并行施工时：全量门禁一律走 `dart run tool/gates.dart`（互斥锁串行）；文件边界按独占清单切分；严禁 `git add -A` / `git commit -a`，提交只 add 自己的文件；每批过检立即独立 commit。
- 派工优先新开会话/新终端，不复用长会话终端（上下文漂移 + 会被用户中途征用）。
- 并行拆分任务必须按三层架构 (Core / Data / UI) 与 ViewModel Mixin 边界切分，严禁两个 Worker 交叉修改同一 Mixin、Model 或 barrel 导出文件 (如 `novelai_models.dart`)。
- 子 Agent / Worker 在测试中严禁调用未 Mock 的真实 NovelAI 线上接口；涉及真实端点的端到端测试必须在编排中作为单一节点严格串行。

## Never 规则

- **Never** 并发调用 NovelAI 官方绘图或超分端点（必须通过 `AsyncLock.runExclusive()` 串行执行，进程内并发数恒为 1；多 Worktree / 多进程场景必须串行调度或使用 Mock，严禁跨进程并发直连）。
- **Never** 在完全移交 (handoff) 之后调用 `task-create` / `dispatch --inject` / `check --wait` 或轮询子 Agent 终端状态（会造成行为死锁与上下文浪费）。
- **Never** 在受监督协作中收到 `worker_done` 后遗漏 `worker-release`（导致孤儿终端与常驻进程）。
- **Never** 采纳未通过双门禁的子 Agent 代码，或允许其标记 `--outcome succeeded`。
- **Never** 在局部修复中把用户便签批注文本盲目当做生图提示词（区域与提示词严格解耦；提示词留空默认复用工作台提示词）。
- **Never** 在高频拖拽或手势帧循环中调用 `notifyListeners()` 重建全局。
- **Never** 颠倒图像导出处理次序（必须且固定为：可见水印合成 → 元数据脱敏/嵌入 → Koch-Zhao DCT 盲水印嵌入）。
- **Never** 每轮向多模态模型重复发送历史图片（必须遵守 `imageEpoch` 单次展示占位规则与 ≤ 1024px PNG 等比压缩）。
- **Never** 绕过 `AnlasCalculator` 随意臆造生图或超分计费逻辑。
- **Never** 使用已废弃的 Flutter API（如 `withOpacity`）。
- **Never** 在界面文案或模型命名中增加营销修饰后缀。
- **Never** 新造与既有原子组件功能重复的 UI 组件，或在拆分大文件时把重复 UI 直接复制进新文件（必须替换为既有原子组件或沉淀新原子组件）。
- **Never** 在多 Agent / 多会话共用同一 worktree 时绕过 `dart run tool/gates.dart` 直接并发执行全量 `flutter test`（共享 `.dart_tool/flutter_build` 会竞态冲突）；需要各自全量自检时必须先 `worktree create` 隔离。
- **Never** 在代码库中硬编码敏感配置、API 密钥或私有凭证。

## 联动规范

- **架构与模块索引**：详细架构设计、数据流时序与完整文件清单参考 [**ARCHITECTURE.md**](ARCHITECTURE.md)。
- **架构演进与优化规划**：全景性能治理、通用原子组件沉淀、UI 统一及 i18n/全局主题四阶段实施规划与当前进度详见 [**plans/architecture_and_performance_optimization_plan.md**](plans/architecture_and_performance_optimization_plan.md)。
- **视觉设计规范**：全局调色板、阴影与组件风格参考 `lib/ui/core/theme/app_theme.dart`。
- **多 Agent 协作**：Orca 编排的模式判定、命令骨架与 Worker 契约详见上方「多 Agent 协作规范 (Orca)」章节；具体 CLI 语法以 `orca skills get orca-cli` / `orca skills get orchestration` 动态检索为准。
- **本地个人偏好**：支持在项目根目录创建 `AGENTS.local.md`（已加入 `.gitignore`），用于自定义回复语言、代码注释风格与个人交互偏好。
