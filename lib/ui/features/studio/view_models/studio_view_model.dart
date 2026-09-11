import 'dart:async';
import 'dart:ui' show Color, Locale, Offset, Rect;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../../../../core/harness/agent_harness.dart';
import '../../../../core/harness/context_memory.dart';
import '../../../../core/harness/tools/context_memory_tool.dart';
import '../../../../core/harness/presets/agent_preset.dart';
import '../../../../core/harness/providers/openai_provider.dart';
import '../../../../core/harness/skills/skills.dart';
import '../../../../core/harness/tools/agent_tool.dart';
// AiEditImageTool 在 part 分部 studio_vm_harness.dart 中注册使用
import '../../../../core/harness/tools/ai_edit_image_tool.dart';
import '../../../core/locale/app_locale_controller.dart';
import '../../../core/theme/app_accent_controller.dart';
import '../../../core/theme/theme_mode_controller.dart';
import '../../../core/theme/ui_zoom_controller.dart';
import '../../../../core/harness/tools/annotation_tools.dart';
import '../../../../core/harness/tools/anysearch_tools.dart';
import '../../../../core/harness/tools/ask_user_tool.dart';
import '../../../../core/harness/tools/canvas_view_tool.dart';
import '../../../../core/harness/tools/character_prompt_tools.dart';
import '../../../../core/harness/tools/danbooru_search_tools.dart';
import '../../../../core/harness/tools/load_skill_tool.dart';
import '../../../../core/harness/tools/novelai_inpaint_tool.dart';
import '../../../../core/harness/tools/novelai_tools.dart';
import '../../../../core/harness/tools/prompt_library_tools.dart';
import '../../../../core/harness/tools/studio_params_tool.dart';
import '../../../../core/harness/types.dart';
import '../../../../data/models/novelai_models.dart';
import '../../../../data/models/comfyui_models.dart';
import '../../../../data/models/prompt_library_models.dart';
import '../../../../data/repositories/novelai_repository.dart';
import '../../../../data/services/anlas_calculator.dart';
import '../../../../data/services/config_service.dart';
import '../../../../data/services/comfyui_service.dart';
import '../../../../data/services/image_file_store.dart';
import '../../../../data/services/image_metadata_service.dart';
import '../../../../data/services/image_save_path_service.dart';
import '../../../../data/services/palette_service.dart';
import '../../../../data/services/prompt_token_counter_service.dart';
import '../../../../data/services/inpaint_service.dart';
import '../../../../data/services/watermark_service.dart';
import '../../../../data/services/prompt_library_service.dart';
import '../../../../data/services/session_log_service.dart';
import '../../../../data/services/tag_dictionary_service.dart';
import '../../../../data/services/tag_dictionary_update_service.dart';
import '../../../../data/services/usage_ledger_service.dart';
import '../../../../l10n/app_localizations.dart'
    show AppLocalizations, lookupAppLocalizations;
import 'param_snapshot_journal.dart';
import 'board/board_controller.dart';
import 'slash_command_catalog.dart';
import 'streaming_controllers.dart';

part 'studio_vm_characters.dart';
part 'studio_vm_chat.dart';
part 'studio_vm_comfyui.dart';
part 'studio_vm_generation.dart';
part 'studio_vm_harness.dart';
part 'studio_vm_inpaint.dart';
part 'studio_vm_layout.dart';
part 'studio_vm_library.dart';
part 'studio_vm_sessions.dart';
part 'studio_vm_slash.dart';

enum StudioSidebarTab { parameters, prompts, inpaint, library }

/// 核心状态 Mixin：集中声明全部状态字段、Getters 与跨分部共享的读写入口。
///
/// StudioViewModel 的实现按职责拆分为同库 part 文件中的多个 Mixin
/// (对外公开 API 与调用点完全不变)：
/// - studio_vm_layout.dart     页面布局持久化状态 (分割线/侧栏/页签)
/// - studio_vm_harness.dart    Agent Harness 装配 / LLM 与思考强度切换 / 预设技能工具 CRUD
/// - studio_vm_generation.dart 生图 / 超分 / 实时预览 / 账号信息
/// - studio_vm_chat.dart       对话流 / ask_user 提问 / 付费确认 / Token 用量记录
/// - studio_vm_sessions.dart   会话列表 / 切换 / 新建 / 删除 / 回溯
/// - studio_vm_characters.dart 多角色提示词编辑与画板定位
/// - studio_vm_slash.dart      斜杠指令分发
///
/// 各分部之间互相调用的方法，在本 Mixin 中只声明签名 (抽象成员)，
/// 由对应分部 Mixin 提供实现；构造注入字段声明为 late final，
/// 在 StudioViewModel 构造体内赋值。
mixin _StudioCore on ChangeNotifier {
  late final ConfigService _configService;
  late final NovelAiRepository _repository;
  PromptLibraryService _promptLibraryService = PromptLibraryService.instance;
  final SessionLogService _sessionLog = SessionLogService();
  final UsageLedgerService _usageLedger = UsageLedgerService();
  late final ToolRegistry _toolRegistry;
  late final AgentHarness _harness;

  /// 本地词组合库条目列表
  List<PromptComboEntry> _promptLibraryEntries = [];

  /// 本会话内各模型 (provider/model) 的累计 Token 用量 (悬停模型选择器时展示)
  Map<String, TokenUsage> _sessionModelUsage = {};

  /// 工作台参数时间轴快照账本 (回溯历史时刻时一并回滚生图参数)
  final ParamSnapshotJournal _paramJournal = ParamSnapshotJournal();

  /// 已保存的会话列表
  List<SessionInfo> _sessions = [];

  /// 当前正在进行的对话流订阅 (支持 ESC 强行终止)
  StreamSubscription<HarnessEvent>? _chatSubscription;

  AppConfig _config = const AppConfig();
  NaiGenerationParams _params = const NaiGenerationParams(prompt: '');

  /// VM 侧本地化取词入口 (阶段 4C 数据层文案解耦)：
  /// ViewModel 状态/错误/确认消息不再硬编码中文，统一经 vmL10n 生成；
  /// 默认 zh (与既有测试断言一致)，updateConfig 时随 localePreference 刷新。
  /// 后端原始错误、Agent prompt、用户输入仍原样透传不翻译。
  Locale _vmLocale = const Locale('zh');
  AppLocalizations get vmL10n => lookupAppLocalizations(_vmLocale);

  NaiAccountInfo? _accountInfo;
  bool _isLoadingAccount = false;
  bool _isGenerating = false;
  bool _isChatStreaming = false;

  /// 流式对话瞬态文本控制器：思考链/正文/重试提示增量只驱动对话气泡局部刷新
  final StreamingTextController _streamingText = StreamingTextController();

  /// 生图/修复实时进度控制器：去噪预览帧与步数只驱动占位卡/缩略图/按钮局部刷新
  final LiveProgressController _liveProgressController =
      LiveProgressController();

  /// 思考块全局展开开关 (Ctrl+O 切换，默认折叠只显示单行预览)
  bool _isThinkingExpanded = false;
  NaiGeneratedImage? _selectedImage;
  bool _hasUnseenLatest = false;

  /// 自适应取色：最近一次已提取主色的图片 id (去重，避免重复 Isolate 提取)
  String? _lastAccentImageId;
  String? _statusMessage;
  String? _errorMessage;

  // --- 局部修复状态 ---
  InpaintParams _inpaintParams = const InpaintParams();
  bool _isExecutingInpaint = false;
  bool _isExecutingAiEdit = false;
  NaiGeneratedImage? _inpaintSourceImage;
  InpaintTool _inpaintTool = InpaintTool.rect;
  Uint8List? _inpaintPreviewBytes;

  // --- 页面布局持久化状态 ---
  double _splitLeftWidth = 320.0;
  double _splitRightWidth = 400.0;
  StudioSidebarTab _activeSidebarTab = StudioSidebarTab.parameters;
  bool _promptTabbedMode = false;
  int _promptActiveTab = 0;
  int _deckActiveTab = 0;
  bool _canvasHistoryOpen = false;

  // 提示词输入框高度
  double _promptHeightStacked = 116.0;
  double _negativePromptHeightStacked = 92.0;
  double _promptHeightTabbed = 212.0;
  double _negativePromptHeightTabbed = 212.0;
  double _prefixPromptHeight = 88.0;
  double _suffixPromptHeight = 64.0;
  double _characterPromptHeight = 72.0;
  double _characterNegativePromptHeight = 56.0;

  /// 提示词输入框高度防抖保存计时器
  Timer? _promptHeightsSaveTimer;

  /// Agent 对话草稿输入文本
  String _chatDraft = '';

  /// Agent 对话草稿输入防抖保存计时器
  Timer? _chatDraftSaveTimer;

  /// 分割线宽度防抖落盘计时器 (拖动过程每帧回调，写盘必须节流)
  Timer? _splitWidthSaveTimer;

  /// UI 缩放防抖落盘计时器 (快捷键连续步进节流)
  Timer? _uiZoomSaveTimer;

  /// 实时生图预览状态 (全部委托 LiveProgressController 局部刷新)
  StreamSubscription<NaiStreamProgress>? _generationSubscription;

  ThinkingEffort _currentThinkingEffort = ThinkingEffort.high;

  AgentQuestionPrompt? _activeQuestionPrompt;

  /// 是否正在画板上交互式编辑角色位置
  bool _isEditingCharacterPositions = false;

  /// 是否正在画板上交互式编辑水印位置
  bool _isEditingWatermarkPosition = false;

  /// 当前选中的角色 ID (用于高亮锚点及左侧卡片)
  String? _selectedCharacterId;

  /// 自由大画布领域控制器 (阶段 4D 试点)：annotations 域整域迁出，
  /// 经 BoardControllerHost 最小接口回调宿主 (决策门 §7 契约)
  late final BoardController board;

  /// 参数持久化防抖计时器
  Timer? _paramSaveDebounceTimer;

  /// 全局配置防抖保存计时器
  Timer? _configSaveDebounceTimer;

  /// 参数保存按调用顺序串行，旧快照不可晚到覆盖新值。
  Future<void> _lastParameterSave = Future<void>.value();
  Future<void> _lastConfigSave = Future<void>.value();
  bool _hasRestoredParameterState = false;

  /// 测试注入用：会话日志根目录 (默认走系统 Documents/NovelAI_Sessions)
  late final String? _sessionLogBaseDir;

  // 动态注册中心
  final SkillRegistry _skillRegistry = SkillRegistry();

  // ------------------------- Getters -------------------------

  SkillRegistry get skillRegistry => _skillRegistry;
  List<Skill> get availableSkills => _skillRegistry.getAll();
  List<AgentTool> get availableTools => _toolRegistry.getAll();

  AppConfig get config => _config;
  NaiGenerationParams get params => _params;
  NaiAccountInfo? get accountInfo => _accountInfo;

  @visibleForTesting
  void setAccountInfoForTest(NaiAccountInfo? info) {
    _accountInfo = info;
    notifyListeners();
  }

  /// ComfyUI 模式开关 (开启后生图改走 PromptToolkit AI Bridge，
  /// 旁路质量词/UC 预设与 Token 上限)
  bool get isComfyUiMode => _config.comfyUiEnabled;

  /// ComfyUI Bridge 连接状态 / 节点注册快照 / 最近一次错误
  ComfyUiConnectionStatus get comfyConnectionStatus;
  ComfyUiBridgeState? get comfyBridgeState;
  String? get comfyLastError;

  /// ComfyUI 服务器实时可用选项清单 (采样器/调度器；连接成功后拉取)
  ComfyUiOptionCatalog? get comfyOptionCatalog;

  /// ComfyUI 采样器 / 噪声调度器 (空 = 跟随工作流，不下发)
  String get comfySampler;
  String get comfyScheduler;

  /// 设置 ComfyUI 采样器 / 调度器 (传空字符串回到跟随工作流)
  Future<void> setComfySampler(String value);
  Future<void> setComfyScheduler(String value);

  /// 当前工作台参数的预计 Anlas 消耗 (账号未加载时按非 Opus 保守估算)；
  /// ComfyUI 模式下本地不产生 Anlas 消耗，恒为 0
  int get estimatedGenerationCost => isComfyUiMode
      ? 0
      : AnlasCalculator.estimateGenerationCost(
          params: _params,
          isOpus: _accountInfo?.isOpus ?? false,
          opusQuotaExhausted: _accountInfo?.v5QuotaExhausted ?? false,
        );
  bool get isLoadingAccount => _isLoadingAccount;
  bool get isGenerating => _isGenerating;
  bool get isChatStreaming => _isChatStreaming;

  /// 流式对话瞬态文本控制器 (视图局部监听用)
  StreamingTextController get streamingText => _streamingText;

  /// 生图/修复实时进度控制器 (视图局部监听用)
  LiveProgressController get liveProgressController => _liveProgressController;

  String get currentStreamingThoughts => _streamingText.thoughts;
  String get currentStreamingContent => _streamingText.content;

  /// 流式请求重试提示 (流式气泡顶部展示)
  String? get streamingRetryNotice => _streamingText.notice;

  /// 对话卡思考块全局展开开关 (Ctrl+O 切换)
  bool get isThinkingExpanded => _isThinkingExpanded;
  NaiGeneratedImage? get selectedImage => _selectedImage;
  bool get hasUnseenLatest => _hasUnseenLatest;
  bool get isViewingLatest =>
      gallery.isEmpty ||
      _selectedImage == null ||
      _selectedImage?.id == gallery.first.id;
  List<NaiGeneratedImage> get gallery => _repository.history;
  List<AgentMessage> get messages => _harness.messages;
  ContextUsage get contextUsage => _harness.contextUsage;
  AgentPreset get currentPreset => _harness.currentPreset;
  List<AgentPreset> get presets =>
      _config.presets.isNotEmpty ? _config.presets : BuiltinPresets.all;
  String? get statusMessage => _statusMessage;
  String? get errorMessage => _errorMessage;

  /// 实时生图预览 Getters (委托 LiveProgressController)
  Uint8List? get livePreviewBytes => _liveProgressController.previewBytes;
  int get liveCurrentStep => _liveProgressController.currentStep;
  int get liveTotalSteps => _liveProgressController.totalSteps;
  double get liveProgress => _liveProgressController.progress;
  DateTime? get generationStartTime => _liveProgressController.startTime;

  /// 已保存的全部会话列表
  List<SessionInfo> get sessions => List.unmodifiable(_sessions);

  /// 当前活跃会话 ID
  String? get currentSessionId => _sessionLog.currentSessionId;

  /// 当前活跃会话元数据
  SessionInfo? get currentSessionInfo {
    final id = currentSessionId;
    if (id == null) return null;
    for (final s in _sessions) {
      if (s.id == id) return s;
    }
    return null;
  }

  ThinkingEffort get currentThinkingEffort => _currentThinkingEffort;

  AgentQuestionPrompt? get activeQuestionPrompt => _activeQuestionPrompt;

  /// 本会话内各模型 (provider/model) 的累计 Token 用量
  Map<String, TokenUsage> get sessionModelUsage =>
      Map.unmodifiable(_sessionModelUsage);

  /// Token 用量账本 (供设置页 Bill 页与统计使用)
  UsageLedgerService get usageLedger => _usageLedger;

  /// 将 "provider/model" 用量键中的供应商 id 映射为用户设定的供应商名称。
  /// 旧账本/旧会话记录的可能是 id (如 provider_173...)，统一按名称展示。
  String displayNameForModelKey(String key) {
    final slash = key.indexOf('/');
    if (slash <= 0) return key;
    final providerPart = key.substring(0, slash);
    for (final p in _config.llmProviders) {
      if (p.id == providerPart && p.name.isNotEmpty) {
        return '${p.name}${key.substring(slash)}';
      }
    }
    return key;
  }

  /// 按周期聚合账单 (供应商 id 自动映射为名称，同名行合并)
  BillSummary buildBillSummary(BillPeriod period) {
    final summary = _usageLedger.aggregate(period);
    if (summary.models.isEmpty) return summary;

    final merged = <String, BillModelUsage>{};
    var remapped = false;
    for (final row in summary.models) {
      final displayName = displayNameForModelKey(row.name);
      if (displayName != row.name) remapped = true;
      final existing = merged[displayName];
      merged[displayName] = BillModelUsage(
        name: displayName,
        requests: (existing?.requests ?? 0) + row.requests,
        usage: (existing?.usage ?? const TokenUsage()).add(row.usage),
      );
    }
    if (!remapped) return summary;

    final models = merged.values.toList()
      ..sort((a, b) => b.usage.total.compareTo(a.usage.total));
    return BillSummary(
      period: period,
      requests: summary.requests,
      usage: summary.usage,
      models: models,
    );
  }

  // ------------------------- 共享参数入口 -------------------------

  /// 更新侧边栏参数 (统一入口：UI 与 Agent 工具共用，含防抖持久化)
  void updateParams(NaiGenerationParams newParams) {
    if (newParams.characterAiPosition && _isEditingCharacterPositions) {
      _isEditingCharacterPositions = false;
    }
    _params = newParams;
    notifyListeners();

    _scheduleParameterSave();
  }

  /// UI、Agent、种子自动变更与修复偏好共用的防抖保存入口。
  void _scheduleParameterSave() {
    _paramSaveDebounceTimer?.cancel();
    _paramSaveDebounceTimer = Timer(
      const Duration(milliseconds: 300),
      _saveParameterSnapshot,
    );
  }

  Future<void> _saveParameterSnapshot() {
    _paramSaveDebounceTimer?.cancel();
    _paramSaveDebounceTimer = null;
    final generation = _params;
    final inpaint = _inpaintParams;
    final save = _lastParameterSave.then(
      (_) => _configService.saveStudioParameters(generation, inpaint),
    );
    // 防抖回调的异常被记录；显式 flush 仍返回原始 Future，使关闭流程可重试。
    _lastParameterSave = save.catchError((Object error, StackTrace stack) {
      debugPrint('工作台参数保存失败: $error');
    });
    return save;
  }

  /// 取消防抖并等待前序写入完成，关闭窗口及测试重启前使用。
  Future<void> flushPendingParameterSave() => _saveParameterSnapshot();

  /// 便捷更新主提示词
  void updatePrompt(String prompt) {
    updateParams(_params.copyWith(prompt: prompt));
  }

  /// 便捷更新负面提示词
  void updateNegativePrompt(String negativePrompt) {
    updateParams(_params.copyWith(negativePrompt: negativePrompt));
  }

  /// 便捷设置种子模式
  void setSeedMode(NaiSeedMode mode) {
    updateParams(_params.copyWith(seedMode: mode));
  }

  /// 便捷设置种子生成控制时机
  void setSeedTiming(NaiSeedTiming timing) {
    updateParams(_params.copyWith(seedTiming: timing));
  }

  // ------------- 跨分部方法签名 (由各分部 Mixin 实现) -------------

  /// 应用并持久化新配置 (类体实现；各分部可调用)
  Future<void> updateConfig(AppConfig newConfig);

  /// 装配 Harness、注册全部工具并配置 LLM Provider
  void _setupHarnessAndTools();

  /// 切换 Agent 当前预设
  void selectPreset(AgentPreset preset);

  /// 手动快速生图
  Future<void> generateImage();

  /// ComfyUI 模式生图 (经 PromptToolkit AI Bridge 驱动)
  Future<void> generateImageViaComfyUi();

  /// 刷新 ComfyUI Bridge 连接状态与节点注册快照
  Future<void> refreshComfyUiStatus();

  /// 重新拉取 ComfyUI 可用采样器/调度器清单 (失败静默保持旧值)
  Future<void> refreshComfyUiOptions();

  /// 测试钩子：直接注入模拟的采样器/调度器清单 (绕过网络)
  @visibleForTesting
  void setComfyOptionCatalogForTesting(ComfyUiOptionCatalog? catalog);

  /// 切换 ComfyUI 模式开关
  Future<void> setComfyUiMode(bool enabled);

  /// 标记中止当前 ComfyUI 出图等待
  void _requestComfyAbort();

  /// 种子生成控制：生图前变更种子
  void _applySeedMutationBefore();

  /// 种子生成控制：生图后变更种子
  void _applySeedMutationAfter(int generatedSeed);

  /// 超分放大当前图片 (官方新超分模型，固定倍率)
  Future<void> upscaleSelected();

  /// 刷新账号与体力信息
  Future<void> refreshAccountInfo();

  /// 获取用于导出/复制的图像字节 (根据全局设置决定是否去元数据或添加水印)
  Future<Uint8List> getExportImageBytes(
    NaiGeneratedImage image, {
    bool raw = false,
  });

  /// 生成完成后统一落图 (手动生成与 Agent 工具共用)
  void _applyGeneratedImage(
    NaiGeneratedImage image, {
    required bool wasViewingLatest,
  });

  /// 自适应取色：后台提取指定图片主色并注入主题强调色
  /// (仅 accentMode == adaptive 时生效，选图/生图/删图后调用)
  void _scheduleAdaptiveAccent(NaiGeneratedImage image);

  /// 手动保存当前选中的未保存 (缓存) 图片到本地存储目录 (支持自定义目录)
  Future<bool> saveCurrentImageToDisk({String? customDir});

  /// 导出任意图片到指定文件夹 (由原生文件选择器挑选，遵守命名模板与无覆盖落盘)
  Future<bool> exportImageToDirectory(
    NaiGeneratedImage image,
    String targetDir,
  );

  /// 解析当前命名模板下的导出文件名 (不含目录)，供系统 SAF 单文件保存使用
  String resolveExportFileName(NaiGeneratedImage image);

  /// 强行中止当前对话生成与工具执行
  Future<void> abortChat();

  /// 刷新会话列表
  Future<void> refreshSessions();

  /// 创建全新会话
  Future<void> createNewSession({String? title});

  /// 重命名指定会话
  Future<void> renameSession(String sessionId, String newTitle);

  /// 回退/撤销到指定历史消息时刻
  Future<void> rewindToMessage(String messageId);

  /// 从剩余消息中重新聚合本会话各模型用量
  void _recomputeSessionUsage();

  /// 分发斜杠指令
  Future<void> _handleSlashCommand(String command);

  /// 呈现 AI 提问卡片 (ask_user / 付费确认共用)
  Future<List<String>?> _presentQuestionsToUser(List<AgentQuestion> questions);

  /// 付费生图申请确认
  Future<bool> _confirmPaidGeneration({
    required NaiGenerationParams params,
    required int estimatedCost,
  });

  /// 付费超分确认
  Future<bool> _confirmPaidUpscale({
    required int estimatedCost,
    required int inputWidth,
    required int inputHeight,
  });

  /// 整体替换角色提示词列表 (Agent 工具与 UI 卡片共用入口)
  void _setCharacterPrompts(List<NaiCharacterPrompt> characters);

  /// 当前词库条目列表 (词库 Agent 工具读取)
  List<PromptComboEntry> get promptLibraryEntries;

  /// 新增词库条目 (词库 Agent 工具写入)
  Future<PromptComboEntry> addPromptCombo(PromptComboEntry entry);

  /// 更新词库条目 (词库 Agent 工具写入)
  Future<void> updatePromptCombo(PromptComboEntry entry);

  /// 删除词库条目 (词库 Agent 工具写入)
  Future<void> deletePromptCombo(String id);

  /// 保存预览图字节到托管目录并返回路径 (词库预览图工具)
  Future<String?> savePromptPreviewFromBytes(
    Uint8List bytes, {
    String extension = 'png',
  });

  /// 从本地路径复制预览图并返回持久化路径 (词库预览图工具)
  Future<String?> savePromptPreviewFromPath(String path);

  /// 发送对话消息 (支持 Slash 命令行；[images] 为用户图片附件)
  Future<void> sendChatMessage(String text, {List<AgentMessageImage>? images});

  /// 切换侧边栏激活页签 (修复分部右键发送后跳转用)
  void setActiveSidebarTab(StudioSidebarTab tab);

  /// 历史大图完整字节缓存通知器：避免大图加载逐帧触发 notifyListeners() 全局重建
  final ValueNotifier<Map<String, Uint8List>> imageBytesNotifier =
      ValueNotifier<Map<String, Uint8List>>({});

  /// 获取指定图片已加载的大图字节 (若内存中存在)
  Uint8List? getImageBytes(NaiGeneratedImage image) {
    if (image.bytes.isNotEmpty) return image.bytes;
    return imageBytesNotifier.value[image.id];
  }

  /// 确保指定图片的大图字节已载入内存，按需异步加载并通过 imageBytesNotifier 局部通知
  Future<Uint8List?> ensureImageLoaded(NaiGeneratedImage image) async {
    if (image.bytes.isNotEmpty) {
      if (!imageBytesNotifier.value.containsKey(image.id)) {
        final map = Map<String, Uint8List>.from(imageBytesNotifier.value);
        map[image.id] = image.bytes;
        imageBytesNotifier.value = map;
      }
      return image.bytes;
    }

    final inMemory = imageBytesNotifier.value[image.id];
    if (inMemory != null) return inMemory;

    final loaded = await _repository.loadHistoryImageBytes(image);
    if (loaded != null) {
      final map = Map<String, Uint8List>.from(imageBytesNotifier.value);
      map[image.id] = loaded;
      imageBytesNotifier.value = map;
      if (_selectedImage?.id == image.id && _selectedImage!.bytes.isEmpty) {
        _selectedImage = _selectedImage!.copyWith(bytes: loaded);
      }
      if (_inpaintSourceImage?.id == image.id &&
          _inpaintSourceImage!.bytes.isEmpty) {
        _inpaintSourceImage = _inpaintSourceImage!.copyWith(bytes: loaded);
      }
      return loaded;
    }
    return null;
  }
}

/// Studio 状态管理中枢 (MVVM)。
class StudioViewModel extends ChangeNotifier
    with
        _StudioCore,
        _StudioLayoutMixin,
        _StudioHarnessMixin,
        _StudioComfyMixin,
        _StudioGenerationMixin,
        _StudioChatMixin,
        _StudioSessionsMixin,
        _StudioCharactersMixin,
        _StudioSlashMixin,
        _StudioLibraryMixin,
        _StudioInpaintMixin {
  StudioViewModel({
    ConfigService? configService,
    NovelAiRepository? repository,
    PromptLibraryService? promptLibraryService,
    String? sessionLogBaseDir,
  }) {
    // Mixin 的 late final 字段无法进初始化列表，统一在构造体内注入
    _configService = configService ?? ConfigService();
    _repository = repository ?? NovelAiRepository();
    _promptLibraryService =
        promptLibraryService ?? PromptLibraryService.instance;
    _sessionLogBaseDir = sessionLogBaseDir;
    _toolRegistry = ToolRegistry();
    _harness = AgentHarness(
      tools: _toolRegistry,
      skillRegistry: _skillRegistry,
      recorder: _sessionLog,
      initialPreset: BuiltinPresets.v5Architect,
    );
    _harness.onContextChanged = () {
      _sessionLog.saveContextState(_harness.exportContextState());
      notifyListeners();
    };
    _harness.onCompactionUsage = (usage, model) {
      final provider = _config.llmProviders
          .where((p) => p.id == _config.compactionProviderId)
          .firstOrNull;
      final label = _harness.compactionProvider == null
          ? (_harness.providerLabel ?? 'unknown')
          : (provider?.name ?? provider?.id ?? 'unknown');
      _usageLedger.record(
        key: 'compaction_${DateTime.now().microsecondsSinceEpoch}',
        provider: label,
        model: model,
        usage: usage,
      );
    };
    // 大画布领域控制器：宿主回调经 _StudioBoardHost 最小接口接入
    board = BoardController(
      host: _StudioBoardHost(this),
      repository: _repository,
    );
  }

  // ------------------------- 初始化 -------------------------

  /// 初始化 Studio
  Future<void> init() async {
    _config = await _configService.loadConfig();
    final lastPrompt = await _configService.loadLastPrompt();
    final applyFixed = await _configService.loadApplyFixedPrompts();

    // 加载页面布局状态
    final (leftWidth, rightWidth) = await _configService.loadSplitWidths();
    _splitLeftWidth = leftWidth;
    _splitRightWidth = rightWidth;

    final savedTabName = await _configService.loadSidebarActiveTab();
    _activeSidebarTab = switch (savedTabName) {
      'prompts' => StudioSidebarTab.prompts,
      'inpaint' => StudioSidebarTab.inpaint,
      'library' => StudioSidebarTab.library,
      _ => StudioSidebarTab.parameters,
    };

    _promptTabbedMode = await _configService.loadPromptTabbedMode();
    _promptActiveTab = await _configService.loadPromptActiveTab();
    _deckActiveTab = await _configService.loadDeckActiveTab();
    _canvasHistoryOpen = await _configService.loadCanvasHistoryOpen();

    // 加载提示词输入框高度
    final promptHeights = await _configService.loadPromptFieldHeights();
    _promptHeightStacked = promptHeights.promptStacked;
    _negativePromptHeightStacked = promptHeights.negativeStacked;
    _promptHeightTabbed = promptHeights.promptTabbed;
    _negativePromptHeightTabbed = promptHeights.negativeTabbed;
    _prefixPromptHeight = promptHeights.prefix;
    _suffixPromptHeight = promptHeights.suffix;
    _characterPromptHeight = promptHeights.characterPrompt;
    _characterNegativePromptHeight = promptHeights.characterNegative;

    // 加载 Agent 对话草稿
    _chatDraft = await _configService.loadChatDraft();

    // 加载词组合库
    await loadPromptLibrary();

    _currentThinkingEffort =
        _config.activeLlmProvider.activeModel.defaultThinkingEffort;

    final legacyParams = NaiGenerationParams(
      prompt: lastPrompt,
      negativePrompt: _config.negativePrompt,
      model: _config.defaultModel,
      width: _config.customWidth,
      height: _config.customHeight,
      steps: _config.defaultSteps,
      scale: _config.defaultScale,
      cfgRescale: _config.defaultCfgRescale,
      sampler: _config.defaultSampler,
      noiseSchedule: _config.defaultNoiseSchedule,
      prefixPrompt: _config.prefixPrompt,
      suffixPrompt: _config.suffixPrompt,
      applyFixedPrompts: applyFixed,
      characterPrompts: await _configService.loadCharacterPrompts(),
      characterAiPosition: await _configService.loadCharacterAiPosition(),
      seedMode: await _configService.loadSeedMode(),
      seedTiming: await _configService.loadSeedTiming(),
    );
    final savedParams = await _configService.loadStudioParameters(legacyParams);
    _params = savedParams.generation;
    _inpaintParams = savedParams.inpaint;
    _hasRestoredParameterState = true;
    // 恢复模型后再预载，避免启动时错误加载出厂模型的分词器。
    unawaited(_precachePromptTokenizers());

    // 参数时间轴基线：后续每轮对话发出前再各记一次快照，供回溯时回滚
    _paramJournal.reset(_params);

    // 设置初始预设
    _harness.setPreset(_config.activePreset);

    _setupHarnessAndTools();

    // 初始化会话日志并续接上次对话 (Pi --continue 语义)
    await _sessionLog.init(baseDir: _sessionLogBaseDir);
    await _usageLedger.init(baseDir: _sessionLog.baseDirPath);
    final snapshot = _sessionLog.loadLatestSession();
    if (snapshot != null && snapshot.messages.isNotEmpty) {
      _harness.restoreMessages(snapshot.messages);
      _harness.restoreContextState(_sessionLog.loadContextState());
      _sessionModelUsage = {
        for (final e in snapshot.sessionUsage.entries)
          displayNameForModelKey(e.key): e.value,
      };
    }
    _sessionLog.recordModelChange(
      _config.activeLlmProvider.id,
      _config.activeLlmProvider.activeModel.id,
    );
    _sessionLog.recordThinkingLevelChange(_currentThinkingEffort.id);
    await refreshSessions();

    // 加载持久化的图像历史
    if (_config.enableImagePersistence && _config.saveDirectory.isNotEmpty) {
      await _repository.loadPersistedHistory(
        saveDir: _config.saveDirectory,
        maxImages: _config.maxPersistentImages,
      );
      if (_repository.history.isNotEmpty && _selectedImage == null) {
        _selectedImage = _repository.history.first;
        ensureImageLoaded(_selectedImage!);
        _scheduleAdaptiveAccent(_selectedImage!);
      }

      // 恢复大画布布局 (节点位置尺寸/便利贴/连线/视口)
      final restoredBoard = await _repository.loadBoardLayout(
        saveDir: _config.saveDirectory,
      );
      if (restoredBoard != null &&
          (restoredBoard.imageNodes.isNotEmpty ||
              restoredBoard.noteNodes.isNotEmpty)) {
        board.restoreLayout(restoredBoard);
      }
    }

    notifyListeners();

    // 后台加载账号信息
    if (_config.novelAiKey.isNotEmpty) {
      await refreshAccountInfo();
    }

    // 后台应用已安装的在线词库并按开关静默检查更新 (24 小时节流，不阻塞启动)
    unawaited(() async {
      await TagDictionaryUpdateService.instance.applyInstalledAtStartup();
      await TagDictionaryUpdateService.instance.maybeAutoUpdate(
        enabled: _config.enableTagDictionaryAutoUpdate,
      );
    }());
  }

  // ------------------------- 配置 -------------------------

  /// 解析 system 档位下的平台首选语言 (仅支持 zh/en，未知回退 zh)
  Locale _resolveSystemLocale() {
    final platform = PlatformDispatcher.instance.locale;
    final matched = AppLocalizations.supportedLocales
        .where((l) => l.languageCode == platform.languageCode)
        .firstOrNull;
    return matched ?? const Locale('zh');
  }

  /// 保存全局配置
  @override
  Future<void> updateConfig(AppConfig newConfig) async {
    final oldConfig = _config;
    _config = newConfig;
    // 主题模式即时生效：MaterialApp 根节点监听全局控制器局部刷新，
    // 200ms 平滑切色，不走 notifyListeners 全局重绘
    AppThemeModeController.instance.syncFromConfig(newConfig);
    // 强调色同步：MD3 自适应取色即时生效 (同样只重建主题层)
    AppAccentController.instance.syncFromConfig(newConfig);
    // 模式或方案变化时按当前展示图立即重取/重应用种子
    if (oldConfig.accentMode != newConfig.accentMode ||
        oldConfig.accentVariant != newConfig.accentVariant) {
      _lastAccentImageId = null;
      final current = _selectedImage;
      if (current != null) {
        _scheduleAdaptiveAccent(current);
      }
    }
    // 语言同理：根级 ValueListenableBuilder 局部接管，不全局重绘
    AppLocaleController.instance.syncFromConfig(newConfig);
    // VM 侧消息文案同步跟随语言设置 (system 跟随平台首选语言)
    _vmLocale = switch (newConfig.localePreference) {
      AppLocalePreference.zh => const Locale('zh'),
      AppLocalePreference.en => const Locale('en'),
      AppLocalePreference.system => _resolveSystemLocale(),
    };
    // UI 缩放同理：根级 ValueListenableBuilder 局部接管，不全局重绘
    AppUiZoomController.instance.syncFromConfig(newConfig);
    // ComfyUI 模式：开关或地址变化时刷新 Bridge 连接状态
    if (newConfig.comfyUiEnabled != oldConfig.comfyUiEnabled ||
        newConfig.comfyUiBaseUrl != oldConfig.comfyUiBaseUrl) {
      if (newConfig.comfyUiEnabled) {
        unawaited(refreshComfyUiStatus());
      } else {
        _comfyStatus = ComfyUiConnectionStatus.disconnected;
        _comfyBridgeState = null;
      }
    }
    _applyChangedGenerationDefaults(oldConfig, newConfig);
    notifyListeners();
    _configSaveDebounceTimer?.cancel();
    _lastConfigSave = _configService.saveConfig(newConfig);
    await _lastConfigSave;

    // 仅在生效供应商/模型真正变化时才重置思考强度；
    // 保存无关设置 (如存储目录) 不应吞掉用户在对话卡选定的强度
    final oldActive = oldConfig.activeLlmProvider;
    final newActive = newConfig.activeLlmProvider;
    final llmChanged =
        oldActive.id != newActive.id ||
        oldActive.activeModelId != newActive.activeModelId;
    if (llmChanged) {
      _currentThinkingEffort = newActive.activeModel.defaultThinkingEffort;
    }
    _setupHarnessAndTools();

    // 同步图片持久化状态与上限调整
    if (newConfig.enableImagePersistence != oldConfig.enableImagePersistence ||
        newConfig.maxPersistentImages != oldConfig.maxPersistentImages ||
        newConfig.saveDirectory != oldConfig.saveDirectory) {
      if (newConfig.enableImagePersistence &&
          newConfig.saveDirectory.isNotEmpty) {
        if (_repository.history.isEmpty) {
          await _repository.loadPersistedHistory(
            saveDir: newConfig.saveDirectory,
            maxImages: newConfig.maxPersistentImages,
          );
          if (_repository.history.isNotEmpty && _selectedImage == null) {
            _selectedImage = _repository.history.first;
            ensureImageLoaded(_selectedImage!);
            _scheduleAdaptiveAccent(_selectedImage!);
          }
        } else {
          await _repository.savePersistedHistory(
            saveDir: newConfig.saveDirectory,
            maxImages: newConfig.maxPersistentImages,
            enabled: true,
          );
        }
      } else if (!newConfig.enableImagePersistence &&
          newConfig.saveDirectory.isNotEmpty) {
        // 仅停止持久化，不删除已有 image_history.json 与画布布局：
        // 关闭开关就销毁历史索引等于破坏性删除用户数据，重新打开开关后应能继续恢复
        board.discardLayout();
      }
    }

    notifyListeners();

    // 仅在 NovelAI API Key 发生变更时刷新账号，避免调整参数/水印时频繁请求网络
    final keyChanged = oldConfig.novelAiKey != newConfig.novelAiKey;
    if (keyChanged && _config.novelAiKey.isNotEmpty) {
      await refreshAccountInfo();
    }
  }

  /// 用户显式修改默认参数时应用改动项；保存主题等无关设置不能重置工作台。
  void _applyChangedGenerationDefaults(AppConfig old, AppConfig next) {
    if (old.defaultModel == next.defaultModel &&
        old.defaultSampler == next.defaultSampler &&
        old.defaultNoiseSchedule == next.defaultNoiseSchedule &&
        old.customWidth == next.customWidth &&
        old.customHeight == next.customHeight &&
        old.defaultSteps == next.defaultSteps &&
        old.defaultScale == next.defaultScale &&
        old.defaultCfgRescale == next.defaultCfgRescale &&
        old.negativePrompt == next.negativePrompt &&
        old.prefixPrompt == next.prefixPrompt &&
        old.suffixPrompt == next.suffixPrompt) {
      return;
    }
    updateParams(
      _params.copyWith(
        model: old.defaultModel != next.defaultModel ? next.defaultModel : null,
        sampler: old.defaultSampler != next.defaultSampler
            ? next.defaultSampler
            : null,
        noiseSchedule: old.defaultNoiseSchedule != next.defaultNoiseSchedule
            ? next.defaultNoiseSchedule
            : null,
        width: old.customWidth != next.customWidth ? next.customWidth : null,
        height: old.customHeight != next.customHeight
            ? next.customHeight
            : null,
        steps: old.defaultSteps != next.defaultSteps ? next.defaultSteps : null,
        scale: old.defaultScale != next.defaultScale ? next.defaultScale : null,
        cfgRescale: old.defaultCfgRescale != next.defaultCfgRescale
            ? next.defaultCfgRescale
            : null,
        negativePrompt: old.negativePrompt != next.negativePrompt
            ? next.negativePrompt
            : null,
        prefixPrompt: old.prefixPrompt != next.prefixPrompt
            ? next.prefixPrompt
            : null,
        suffixPrompt: old.suffixPrompt != next.suffixPrompt
            ? next.suffixPrompt
            : null,
      ),
    );
  }

  /// 关闭前冲刷工作台、布局、全局配置与对话日志，不能只 cancel 防抖计时器。
  Future<void> flushPendingSaves() async {
    // 启动尚未读完偏好时直接关闭：保留磁盘原值，不用空工作台覆盖它，
    // 也不等待初始化尾部的账号网络查询才能退出。
    if (!_hasRestoredParameterState) return;
    await flushPendingParameterSave();
    await flushPendingLayoutSave();
    _uiZoomSaveTimer?.cancel();
    await _configService.saveUiZoom(_config.uiZoom);
    _configSaveDebounceTimer?.cancel();
    await _lastConfigSave;
    await _configService.saveConfig(_config);
    await _sessionLog.flush();
  }

  /// 防抖保存全局配置 (避免滑块/高频拖拽频繁写盘)
  void _debounceSaveConfig() {
    _configSaveDebounceTimer?.cancel();
    _configSaveDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      _lastConfigSave = _configService.saveConfig(_config);
    });
  }

  /// 切换模型并跟随官方出厂默认值。
  ///
  /// CFG 与步数只在用户未手动调整 (仍停留在旧模型出厂默认) 时才跟随新模型默认，
  /// 手动调过的一律保留；切到 v4+ 时 Native 噪声调度不合法，自动回落 Karras。
  void selectModel(NaiModel model) {
    final old = _params;
    // 切到不同分词器家族时预载对应词表 (幂等)
    if (model.tokenizerKind != old.model.tokenizerKind) {
      unawaited(_precachePromptTokenizers(model));
    }
    final scaleUntouched = (old.scale - old.model.defaultScale).abs() < 0.001;
    // 28 为本应用历史全局默认步数，视同未手动调整
    final stepsUntouched =
        old.steps == old.model.defaultSteps || old.steps == 28;
    final nativeInvalid =
        model.isV4OrAbove && old.noiseSchedule == NoiseSchedule.native;

    updateParams(
      _params.copyWith(
        model: model,
        scale: scaleUntouched && model.defaultScale != old.model.defaultScale
            ? model.defaultScale
            : null,
        steps: stepsUntouched && model.defaultSteps != old.model.defaultSteps
            ? model.defaultSteps
            : null,
        noiseSchedule: nativeInvalid ? NoiseSchedule.karras : null,
        // 模型切换后质量词档位可能不再有效 (Light 仅 V5)
        qualityPreset: _params.qualityPreset == 'Light' && !model.isV5
            ? 'Standard'
            : null,
      ),
    );
  }

  // ------------------------- 画板选图 -------------------------

  /// 预载当前 (或指定) 模型的提示词分词器；完成后通知重建，
  /// 提示词卡片的 token 计数从启发式估算切到真分词结果。
  Future<void> _precachePromptTokenizers([NaiModel? model]) async {
    final target = model ?? _params.model;
    try {
      await PromptTokenCounterService.instance.precache(target);
    } catch (_) {
      // 词表资产缺失时不阻断启动，计数保持启发式估算
      return;
    }
    if (_params.model.tokenizerKind == target.tokenizerKind) {
      notifyListeners();
    }
  }

  /// 选择画板当前查看的图片
  void selectImage(NaiGeneratedImage image) {
    _selectedImage = image;
    ensureImageLoaded(image);
    _scheduleAdaptiveAccent(image);
    if (gallery.isNotEmpty && image.id == gallery.first.id) {
      _hasUnseenLatest = false;
    }
    // 批注模式下不重置大画布：
    // 重置会清空用户手工摆放的参考图、便利贴与连线布局
    notifyListeners();
  }

  /// 快速查看最新生成的图片并消除提示气泡
  void selectLatestImage() {
    if (gallery.isNotEmpty) {
      _selectedImage = gallery.first;
      ensureImageLoaded(gallery.first);
      _scheduleAdaptiveAccent(gallery.first);
      _hasUnseenLatest = false;
      notifyListeners();
    }
  }

  /// 自适应取色：后台提取指定图片主色并注入主题强调色
  ///
  /// 仅 accentMode == adaptive 时生效；按图片 id 去重 (含 LRU 缓存)，
  /// fire-and-forget 不阻塞选图/生图主流程；结果回来时校验该图
  /// 仍是当前展示图，避免快速切换图片时旧结果覆盖新种子。
  @override
  void _scheduleAdaptiveAccent(NaiGeneratedImage image) {
    if (_config.accentMode != AppAccentMode.adaptive) return;
    if (_lastAccentImageId == image.id) return;
    _lastAccentImageId = image.id;
    unawaited(() async {
      try {
        final bytes = await ensureImageLoaded(image) ?? image.bytes;
        if (bytes.isEmpty) return;
        final palette = await PaletteService.instance.extract(
          bytes,
          cacheKey: image.id,
        );
        if (palette == null) return;
        if (_selectedImage?.id != image.id) return;
        AppAccentController.instance.applyAdaptiveSeed(Color(palette.seed));
      } catch (_) {
        // 取色失败静默降级：保持当前主题不变
      }
    }());
  }

  /// 将指定色设为手动主题强调色种子 (调色盘面板调用，立即生效并落盘)
  void setManualAccentSeed(Color seed) {
    unawaited(
      updateConfig(
        _config.copyWith(
          accentMode: AppAccentMode.manual,
          accentSeedColor: seedColorText(seed.toARGB32()),
        ),
      ),
    );
  }

  /// 关闭新图片提示气泡
  void dismissUnseenBanner() {
    _hasUnseenLatest = false;
    notifyListeners();
  }

  /// 从历史记录中删除单张图片并同步持久化
  Future<void> deleteImageFromHistory(String imageId) async {
    final deletedIndex = gallery.indexWhere((img) => img.id == imageId);
    if (deletedIndex < 0) return;

    final wasSelected = _selectedImage?.id == imageId;
    await _repository.deleteImage(
      imageId: imageId,
      saveDir: _config.saveDirectory,
      enablePersistence: _config.enableImagePersistence,
      maxImages: _config.maxPersistentImages,
    );

    final map = Map<String, Uint8List>.from(imageBytesNotifier.value)
      ..remove(imageId);
    imageBytesNotifier.value = map;

    if (wasSelected) {
      if (gallery.isNotEmpty) {
        final nextIndex = deletedIndex < gallery.length
            ? deletedIndex
            : gallery.length - 1;
        _selectedImage = gallery[nextIndex];
        ensureImageLoaded(_selectedImage!);
        _scheduleAdaptiveAccent(_selectedImage!);
      } else {
        _selectedImage = null;
      }
    }

    if (gallery.isEmpty ||
        (_selectedImage != null && _selectedImage!.id == gallery.first.id)) {
      _hasUnseenLatest = false;
    }

    // 同步大画布节点 (若大画布已加载)：主图节点替换为新选中图，其余删除
    board.pruneHistoryNodes({imageId}, mainReplacement: _selectedImage);

    _statusMessage = vmL10n.vmHistoryDeleted;
    notifyListeners();
  }

  /// 一键清空全部历史图片 (右键菜单)：删除本地文件与持久化索引，
  /// 同步移除大画布上来自历史的图片节点 (保留外部导入的参考卡片与自由便利贴，
  /// 指向已删节点的连线/便签连接同步解绑)
  Future<void> clearImageHistory() async {
    if (gallery.isEmpty) return;

    final historyIds = gallery.map((img) => img.id).toSet();
    await _repository.clearAllHistory(
      saveDir: _config.saveDirectory,
      enablePersistence: _config.enableImagePersistence,
      autoSave: _config.autoSaveImages,
    );

    _selectedImage = null;
    _hasUnseenLatest = false;
    imageBytesNotifier.value = const {};

    // 同步大画布：移除来自历史的图片节点 (保留外部导入的参考卡片与自由便利贴，
    // 指向已删节点的连线/便签连接同步解绑)
    board.pruneHistoryNodes(historyIds);

    _statusMessage = vmL10n.vmHistoryCleared;
    notifyListeners();
  }

  // ------------------------- 元数据与水印设置 -------------------------

  bool get stripMetadata => _config.stripMetadata;
  bool get enableWatermark => _config.enableWatermark;
  bool get autoSaveImages => _config.autoSaveImages;
  bool get keepOriginalImage => _config.keepOriginalImage;
  WatermarkConfig get watermarkConfig => _config.watermarkConfig;
  bool get isEditingWatermarkPosition => _isEditingWatermarkPosition;

  void setEditingWatermarkPosition(bool editing) {
    if (_isEditingWatermarkPosition == editing) return;
    _isEditingWatermarkPosition = editing;
    if (editing) {
      if (_isEditingCharacterPositions) {
        _isEditingCharacterPositions = false;
      }
      board.exitAnnotatingModeQuietly();
    }
    notifyListeners();
  }

  void setStripMetadata(bool value) {
    if (_config.stripMetadata == value) return;
    _config = _config.copyWith(stripMetadata: value);
    notifyListeners();
    _debounceSaveConfig();
  }

  void setEnableWatermark(bool value) {
    if (_config.enableWatermark == value) return;
    _config = _config.copyWith(enableWatermark: value);
    notifyListeners();
    _debounceSaveConfig();
  }

  void setKeepOriginalImage(bool value) {
    if (_config.keepOriginalImage == value) return;
    _config = _config.copyWith(keepOriginalImage: value);
    notifyListeners();
    _debounceSaveConfig();
  }

  void updateWatermarkConfig(WatermarkConfig watermarkConfig) {
    _config = _config.copyWith(watermarkConfig: watermarkConfig);
    notifyListeners();
    _debounceSaveConfig();
  }

  /// 基于当前画板图像智能计算低信息区域水印位置并应用到配置
  ///
  /// 返回是否成功 (画板无图或解析失败时返回 false)。
  Future<bool> applySmartWatermarkPosition() async {
    final source =
        _selectedImage ?? (gallery.isNotEmpty ? gallery.first : null);
    if (source == null) return false;
    final bytes = await ensureImageLoaded(source) ?? source.bytes;
    if (bytes.isEmpty) return false;
    final config = _config.watermarkConfig;
    try {
      final (
        posX,
        posY,
      ) = await WatermarkService.findLowInformationPositionAsync(
        bytes,
        scalePercent: config.scalePercent,
        marginPercent: config.marginPercent,
        watermarkBytes: config.imageBytes,
      );
      updateWatermarkConfig(config.copyWith(posX: posX, posY: posY));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> setWatermarkImageBytes(Uint8List bytes, {String? path}) async {
    final updated = _config.watermarkConfig.copyWith(
      imageBytes: bytes,
      imagePath: path,
    );
    _config = _config.copyWith(watermarkConfig: updated);
    notifyListeners();
    _debounceSaveConfig();
  }

  Future<void> clearWatermarkImage() async {
    final updated = _config.watermarkConfig.copyWith(clearImage: true);
    _config = _config.copyWith(watermarkConfig: updated);
    notifyListeners();
    _debounceSaveConfig();
  }

  /// 仅应用选中的有效元数据；省略选项时保持原有全部回填行为。
  void applyMetadataToWorkbench(
    ImageMetadataResult metadata, {
    Set<MetadataImportField>? fields,
  }) {
    final selected = metadata.importableFields;
    if (fields != null) selected.retainAll(fields);
    if (selected.isEmpty) return;
    bool includes(MetadataImportField field) => selected.contains(field);
    NaiModel? resolvedModel;
    if (metadata.model != null && metadata.model!.isNotEmpty) {
      try {
        resolvedModel = NaiModel.fromId(metadata.model!);
      } catch (_) {}
    }

    NaiSampler? resolvedSampler;
    if (metadata.sampler != null && metadata.sampler!.isNotEmpty) {
      try {
        resolvedSampler = NaiSampler.fromId(metadata.sampler!);
      } catch (_) {}
    }

    NoiseSchedule? resolvedSchedule;
    if (metadata.noiseSchedule != null && metadata.noiseSchedule!.isNotEmpty) {
      try {
        resolvedSchedule = NoiseSchedule.fromId(metadata.noiseSchedule!);
      } catch (_) {}
    }

    // 转换角色提示词
    List<NaiCharacterPrompt>? charPrompts;
    if (metadata.characterPrompts.isNotEmpty) {
      charPrompts = [];
      for (var i = 0; i < metadata.characterPrompts.length; i++) {
        final p = metadata.characterPrompts[i];
        final uc = (i < metadata.characterNegativePrompts.length)
            ? metadata.characterNegativePrompts[i]
            : '';
        charPrompts.add(
          NaiCharacterPrompt(
            id: 'char_${DateTime.now().millisecondsSinceEpoch}_$i',
            name: vmL10n.vmCharacterDefaultName(i + 1),
            prompt: p,
            negativePrompt: uc,
          ),
        );
      }
    }

    final newParams = _params.copyWith(
      prompt: includes(MetadataImportField.prompt) ? metadata.prompt : null,
      negativePrompt: includes(MetadataImportField.negativePrompt)
          ? metadata.negativePrompt
          : null,
      model: includes(MetadataImportField.model) ? resolvedModel : null,
      sampler: includes(MetadataImportField.sampler) ? resolvedSampler : null,
      noiseSchedule: includes(MetadataImportField.noiseSchedule)
          ? resolvedSchedule
          : null,
      width:
          includes(MetadataImportField.resolution) && (metadata.width ?? 0) > 0
          ? metadata.width
          : null,
      height:
          includes(MetadataImportField.resolution) && (metadata.height ?? 0) > 0
          ? metadata.height
          : null,
      steps: includes(MetadataImportField.steps) ? metadata.steps : null,
      scale: includes(MetadataImportField.scale) ? metadata.scale : null,
      cfgRescale: includes(MetadataImportField.cfgRescale)
          ? metadata.cfgRescale
          : null,
      seed: includes(MetadataImportField.seed) ? metadata.seed : null,
      qualityToggle: includes(MetadataImportField.quality)
          ? metadata.qualityToggle
          : null,
      qualityPreset: includes(MetadataImportField.quality)
          ? metadata.qualityPreset
          : null,
      ucPresetKey: includes(MetadataImportField.ucPreset)
          ? metadata.ucPreset
          : null,
      transparentBg: includes(MetadataImportField.transparentBackground)
          ? metadata.transparentBackground
          : null,
      characterPrompts: includes(MetadataImportField.characters)
          ? charPrompts
          : null,
    );

    updateParams(newParams);
    _statusMessage = vmL10n.vmMetadataApplied;
    notifyListeners();
  }

  // ------------------------- 杂项状态 -------------------------

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Ctrl+O: 切换对话卡思考块全局展开/折叠
  void toggleThinkingExpanded() {
    _isThinkingExpanded = !_isThinkingExpanded;
    notifyListeners();
  }

  void clearStatus() {
    _statusMessage = null;
    notifyListeners();
  }

  @visibleForTesting
  void setMessagesForTesting(List<AgentMessage> messages) {
    _harness.setMessages(messages);
    notifyListeners();
  }

  /// BoardController 宿主回调专用：借用全局广播刷新 UI。
  /// 独立适配器类不是 ChangeNotifier 子类，不能直接触 protected 的
  /// notifyListeners，统一经本转发入口。
  void _notifyFromBoard() {
    notifyListeners();
  }

  @visibleForTesting
  void setChatStreamingForTesting(bool streaming) {
    _isChatStreaming = streaming;
    notifyListeners();
  }

  @override
  void dispose() {
    _harness.dispose();
    _generationSubscription?.cancel();
    _paramSaveDebounceTimer?.cancel();
    _configSaveDebounceTimer?.cancel();
    _splitWidthSaveTimer?.cancel();
    _uiZoomSaveTimer?.cancel();
    _promptHeightsSaveTimer?.cancel();
    _chatDraftSaveTimer?.cancel();
    _chatSubscription?.cancel();
    // 瞬态控制器随宿主一起释放
    _streamingText.dispose();
    _liveProgressController.dispose();
    // 大画布领域控制器：内部取消防抖并立即落盘一次 (对齐旧 dispose 契约)
    board.dispose();
    unawaited(_sessionLog.flush());
    super.dispose();
  }
}

/// 大画布领域控制器的宿主适配器 (阶段 4D 试点，决策门 §7 契约)：
/// 仅暴露 BoardControllerHost 最小接口，不泄漏 StudioViewModel 全貌；
/// 共享底座 (_selectedImage/_config/字节缓存/全局广播) 经由此层单向供给。
class _StudioBoardHost implements BoardControllerHost {
  _StudioBoardHost(this._vm);

  final StudioViewModel _vm;

  @override
  NaiGeneratedImage? get boardSelectedImage => _vm._selectedImage;

  @override
  void onBoardSelectedImageChanged(NaiGeneratedImage image) {
    // 仅回写选中引用 (不加载字节/不广播)，行为对齐旧 annotations 分部直赋值
    _vm._selectedImage = image;
  }

  @override
  Future<Uint8List?> ensureBoardImageLoaded(NaiGeneratedImage image) =>
      _vm.ensureImageLoaded(image);

  @override
  Future<void> sendChatMessage(
    String text, {
    List<AgentMessageImage>? images,
  }) => _vm.sendChatMessage(text, images: images);

  @override
  void exitOtherCanvasEditModes() {
    if (_vm._isEditingCharacterPositions) {
      _vm._isEditingCharacterPositions = false;
    }
    if (_vm._isEditingWatermarkPosition) {
      _vm._isEditingWatermarkPosition = false;
    }
  }

  @override
  void onBoardStatus(String message) => _vm._statusMessage = message;

  @override
  bool get boardImagePersistenceEnabled => _vm._config.enableImagePersistence;

  @override
  String get boardSaveDirectory => _vm._config.saveDirectory;

  @override
  void requestGlobalNotify() => _vm._notifyFromBoard();
}
