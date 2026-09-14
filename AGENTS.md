# AGENTS.md

## 项目概要
project:
  type: Flutter 跨平台桌面端应用 (Dart 3 / Windows, macOS, Linux)
  architecture: MVVM (StudioViewModel + Mixin) + 三层架构 (Core Harness / Data / UI)
  ui_style: Material 3 + 暗黑主题 (AppTheme) + MiSans 字体
  details: 完整目录与职责见 ARCHITECTURE.md

## 常用命令
commands:
  run: flutter run -d windows # 或 macos / linux
  analyze: dart analyze       # 静态检查 (门禁: 必须 0 警告)
  test_target: flutter test test/<target_test>.dart # 跑改动相关的单测
  test_all: flutter test      # 全量测试 (仅在核心架构改动或发布前跑)
  gates: dart run tool/gates.dart # 门禁串行执行脚本

## 什么时候做 (When)
when_to_do:
  before_coding:
    - 查既有代码: 先用 grep_search 或 find_by_name 搜索定位，不要凭空臆造 API 或重复写逻辑
    - 查既有组件: 动笔写 UI 前先查 lib/ui/core/widgets/、studio_shared.dart、pill_widgets.dart 等，优先复用
  during_coding:
    - 分层实现: View 纯写布局和事件传递；业务状态收敛在 StudioViewModel / Mixin；底层计算与数据收敛在 Service
    - 核心业务调用单一服务:
        点数与免费判定: AnlasCalculator
        局部修复与几何回贴: InpaintService
        图片导出与水印管道: WatermarkService
        离线标签检索: TagDictionaryService
    - 高频交互优化: 分割线拖拽、漫游、画笔绘制、微调必须用 ValueNotifier 或图层隔离，不逐帧触发 notifyListeners()
    - 拆分大组件: 提炼为无状态、参数驱动的原子组件放 lib/ui/core/widgets/，不要按行数硬切，不复制代码
    - 界面文案: 一律用官方大白话 (生成图片、开始修复、Opus 免费、需点数)，不加营销修饰后缀
  after_coding:
    - 静态检查: 执行 dart analyze，必须 0 警告
    - 针对性验证: 若改动涉及既有测试，跑对应的测试文件确保绿灯即可，不强求每次全量跑

## 怎么做 (How)
how_to_do:
  dart_syntax:
    - 开启强类型与空安全，严禁 dynamic 或隐式强转 (仅外部原始 JSON 边界除外)
    - 条件分流优先使用 Pattern Matching 与 switch 表达式
    - 私有变量与内部方法严格以 _ 开头，命名清晰直接
    - 杜绝废弃 API: 统一使用 withValues(alpha: ...) 替代 withOpacity；使用 CardThemeData 替代 CardTheme
  ui_components:
    - 原子组件保持纯粹: 无业务状态，不耦合 StudioViewModel，纯靠参数与事件回调驱动
    - 统一样式类型: 按钮、输入框、滑块、分组标题、胶囊选择器一律使用既有原子组件

## 测试策略 (Testing)
testing:
  principle: 拒绝形式主义与过度测试，只在必要时补测
  when_to_test:
    - 核心算法与计算逻辑变动 (如 AnlasCalculator 点数公式调整)
    - 复杂协议/数据编解码与底层管道 (如元数据脱敏、DCT 盲水印、AST 解析)
    - 修复了容易复发的复杂边界 Bug 时，补充单测防止回归
  when_not_to_test:
    - 纯 UI 布局排版、颜色样式微调、文案替换
    - 简单的事件转发与参数传递胶水层
    - 已经有充分覆盖的普通 CRUD 或简单配置修改
  run_scope: 改了哪里跑对应测试，正常改动不频繁全量跑 flutter test

## 什么不该做 (Never)
never:
  - 严禁为普通 UI 微调或无业务逻辑的代码堆砌假测试或无意义测试
  - 严禁并发调用 NovelAI 绘图或超分接口 (必须通过 AsyncLock.runExclusive() 串行执行，并发数恒为 1)
  - 严禁在高频拖拽、画布漫游或手势帧循环中调用 notifyListeners() 重建全局
  - 严禁绕过 AnlasCalculator 臆造生图或超分计费逻辑
  - 严禁颠倒图像导出处理次序 (固定顺序: 可见水印合成 -> 元数据脱敏/嵌入 -> DCT 盲水印嵌入)
  - 严禁每轮向多模态模型重复发送历史图片 (遵守 imageEpoch 占位规则与 <= 1024px 等比压缩)
  - 严禁在局部修复中把便签批注文本盲目当做生图提示词 (区域与提示词解耦，留空默认复用工作台提示词)
  - 严禁使用废弃的 Flutter API (如 withOpacity)
  - 严禁新建与既有原子组件功能重复的 UI 组件
  - 严禁在代码中硬编码任何 API Key、Token 或敏感私钥
  - 严禁提交未通过 dart analyze (0 警告) 或破坏既有相关测试的代码
