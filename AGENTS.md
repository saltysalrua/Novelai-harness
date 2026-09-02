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

**业务单一事实源 (SSOT)**
- 点数与免费判定：统一接入 `AnlasCalculator`。
- 局部修复几何与回贴：统一接入 `InpaintService`。
- 图像导出与水印管道：统一接入 `WatermarkService`。
- 离线标签检索：统一接入 `TagDictionaryService`。

**文案规范 (Zero Marketing Fluff)**
- 严禁使用任何营销修饰词（如“旗舰版 (最新)”、“无限/大师”等括号后缀）。
- 界面标签、选项与按钮统一使用官方标准名称与纯净大白话（`生成图片`、`开始修复`、`开始 AI 编辑`、`Opus 免费`、`需点数`、`V5 体力`）。

## Workflow (作业流程)

1. **意图分析与影响评估**：明确任务范围与诉求，识别受影响的架构分层（Core / Data / UI）及特定的 ViewModel Mixin 或 Service。
2. **代码检索与事实源定位**：优先使用 `grep_search` 与 `find_by_name` 检索既有代码，严禁凭空臆造 API 或写平行重复逻辑。
3. **规范编码与状态收敛**：严格遵循 MVVM 模式，将状态收敛在 ViewModel，业务计算收敛在 Service，并保障高帧率图层隔离。
4. **质量门禁 (Quality Gate)**：代码修改后必须在终端无条件执行并通过以下两道门禁：
   - 门禁 1：`dart analyze`（必须 0 警告 / No issues found!）
   - 门禁 2：`flutter test`（全量自动化测试套件必须 100% 通过）

## Build & Test Commands

```bash
flutter run -d windows    # 启动 Windows 桌面端调试
flutter run -d macos      # 启动 macOS 桌面端调试
flutter run -d linux      # 启动 Linux 桌面端调试
dart analyze              # 静态代码检查 (门禁：必须 0 警告)
flutter test              # 运行自动化测试套件 (门禁：全量用例必须 100% 通过)
```

## Never 规则

- **Never** 并发调用 NovelAI 官方绘图或超分端点（必须通过 `AsyncLock.runExclusive()` 串行执行，并发数恒为 1）。
- **Never** 在局部修复中把用户便签批注文本盲目当做生图提示词（区域与提示词严格解耦；提示词留空默认复用工作台提示词）。
- **Never** 在高频拖拽或手势帧循环中调用 `notifyListeners()` 重建全局。
- **Never** 颠倒图像导出处理次序（必须且固定为：可见水印合成 → 元数据脱敏/嵌入 → Koch-Zhao DCT 盲水印嵌入）。
- **Never** 每轮向多模态模型重复发送历史图片（必须遵守 `imageEpoch` 单次展示占位规则与 ≤ 1024px PNG 等比压缩）。
- **Never** 绕过 `AnlasCalculator` 随意臆造生图或超分计费逻辑。
- **Never** 使用已废弃的 Flutter API（如 `withOpacity`）。
- **Never** 在界面文案或模型命名中增加营销修饰后缀。
- **Never** 在代码库中硬编码敏感配置、API 密钥或私有凭证。

## 联动规范

- **架构与模块索引**：详细架构设计、数据流时序与完整文件清单参考 [**ARCHITECTURE.md**](ARCHITECTURE.md)。
- **视觉设计规范**：全局调色板、阴影与组件风格参考 `lib/ui/core/theme/app_theme.dart`。
- **本地个人偏好**：支持在项目根目录创建 `AGENTS.local.md`（已加入 `.gitignore`），用于自定义回复语言、代码注释风格与个人交互偏好。
