# AGENTS.md

## 项目概要
project:
  type: Flutter 跨平台应用 (Dart 3 / Windows, macOS, Linux, Android)
  architecture: MVVM (StudioViewModel + 领域控制器 + Mixin) + 三层架构 (Core Harness / Data / UI)
  ui_style: Material 3 + 亮/暗/跟随系统主题 + MD3 动态强调色 (AppTheme) + MiSans 字体
  extras: Cloudflare Workers + D1 词库云同步、Windows RTX VSR 本地放大、多协议 LLM 与 CodeMode 工具编排
  details: 完整目录与职责见 ARCHITECTURE.md

## 常用命令
commands:
  run: flutter run -d windows # 或 macos / linux / android
  analyze: dart analyze       # 静态检查 (门禁: 必须 0 警告)
  test_target: dart run tool/gates.dart test test/<target_test>.dart # 跑改动相关的单测
  test_all: dart run tool/gates.dart test # 全量 Flutter 测试 (仅核心架构改动或发布前跑)
  cloudflare: dart run tool/gates.dart cloudflare # Cloudflare Worker 云同步单测
  gates: dart run tool/gates.dart # 门禁串行执行脚本 (analyze + flutter test + cloudflare)

## 什么时候做 (When)
when_to_do:
  before_coding:
    - 查既有代码: 先用 grep_search 或 find_by_name 搜索定位，不要凭空臆造 API 或重复写逻辑
    - 查既有组件: 动笔写 UI 前先查 lib/ui/core/widgets/、studio_shared.dart 等，优先复用
  during_coding:
    - 分层实现: View 纯写布局和事件传递；业务状态收敛在 StudioViewModel / 领域控制器；底层计算与数据收敛在 Service
    - 核心业务调用单一服务:
        点数与免费判定: AnlasCalculator
        局部修复与几何回贴: InpaintService
        图片导出与水印管道: WatermarkService
        离线标签检索: TagDictionaryService
    - 高频交互优化: 分割线拖拽、漫游、画笔绘制、微调必须用 ValueNotifier 或图层隔离，不逐帧触发 notifyListeners()
    - 拆分大组件: 提炼为无状态、参数驱动的原子组件放 lib/ui/core/widgets/，不要按行数硬切，不复制代码
    - 界面文案: 一律用官方大白话 (生成图片、开始修复、Opus 免费、需点数)，不加营销修饰后缀
  after_coding:
    - 静态检查: 执行 dart run tool/gates.dart analyze，必须 0 警告
    - 针对性验证: 若改动涉及既有测试或 Cloudflare Worker，跑对应的门禁确保绿灯即可，不强求每次全量跑

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
  principle: 禁止“AI 自写实现 + 自写测试 + 自证通过”的形式主义测试；默认不新增测试
  default_rule:
    - 默认禁止新建 *_test.dart 文件
    - 冻结 Widget 测试: 禁止新增 UI 布局、样式调整、回调胶水类的 testWidgets 用例；UI 改动通过 dart analyze + 受影响的既有核心测试 + 实际运行手验完成
  whitelist_only:
    - 仅当改动命中以下客观事实源领域时，才允许补充或更新纯 Dart 单元测试:
        1. 计费与额度公式 (AnlasCalculator)
        2. 外部协议编解码与状态机 (LLM 多协议、NovelAI API、ComfyUI Bridge、Cloudflare Sync)
        3. 图像/修复/水印/元数据算法 (InpaintService、WatermarkService、ImageMetadataService、RTX worker 边界)
        4. 解析器与分词器 (PromptAstEngine、PromptTokenCounterService、Skill YAML/ZIP)
        5. 持久化安全边界、路径净化与并发锁 (AsyncLock、ImageSavePathService、ImageFileStore、ConfigService、SessionLogService)
  anti_tautology_rules:
    - 打破同源盲区: 修 Bug 时先依据真实报错日志、API 样本或复现输入写出“未修前必红 (Red)”的最小纯数据复现用例，再改业务代码
    - 严禁自证断言: 不准直接在测试中手动调用 widget.onChanged(...) 后断言本地临时变量，不准断言控件内部实现结构 (如 SliverChildListDelegate 或特定 Widget 实例身份)
    - 禁止按改动碎片建文件: 严禁新建 *_v2_test.dart、*_fix_test.dart、*_updates_test.dart；命中白名单的补充用例一律合入对应模块的既有测试文件
  run_scope: 改了哪里跑对应测试，正常改动不频繁全量跑 flutter test

## 什么不该做 (Never)
never:
  - 严禁为普通 UI 微调、开关渲染或无业务逻辑的胶水代码新建任何测试
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
