import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Offset;
import 'package:flutter/foundation.dart';
import '../../../../core/harness/agent_harness.dart';
import '../../../../core/harness/presets/agent_preset.dart';
import '../../../../core/harness/providers/openai_provider.dart';
import '../../../../core/harness/skills/skills.dart';
import '../../../../core/harness/tools/agent_tool.dart';
import '../../../../core/harness/tools/annotation_tools.dart';
import '../../../../core/harness/tools/ask_user_tool.dart';
import '../../../../core/harness/tools/canvas_view_tool.dart';
import '../../../../core/harness/tools/character_prompt_tools.dart';
import '../../../../core/harness/tools/danbooru_search_tools.dart';
import '../../../../core/harness/tools/load_skill_tool.dart';
import '../../../../core/harness/tools/novelai_tools.dart';
import '../../../../core/harness/tools/prompt_library_tools.dart';
import '../../../../core/harness/tools/studio_params_tool.dart';
import '../../../../core/harness/tools/vision_image_codec.dart';
import '../../../../core/harness/types.dart';
import '../../../../data/models/novelai_models.dart';
import '../../../../data/models/prompt_library_models.dart';
import '../../../../data/repositories/novelai_repository.dart';
import '../../../../data/services/anlas_calculator.dart';
import '../../../../data/services/config_service.dart';
import '../../../../data/services/image_metadata_service.dart';
import '../../../../data/services/watermark_service.dart';
import '../../../../data/services/prompt_library_service.dart';
import '../../../../data/services/session_log_service.dart';
import '../../../../data/services/tag_dictionary_service.dart';
import '../../../../data/services/tag_dictionary_update_service.dart';
import '../../../../data/services/usage_ledger_service.dart';
import 'param_snapshot_journal.dart';
import 'slash_command_catalog.dart';

part 'studio_vm_annotations.dart';
part 'studio_vm_characters.dart';
part 'studio_vm_chat.dart';
part 'studio_vm_generation.dart';
part 'studio_vm_harness.dart';
part 'studio_vm_layout.dart';
part 'studio_vm_library.dart';
part 'studio_vm_sessions.dart';
part 'studio_vm_slash.dart';

enum StudioSidebarTab { parameters, prompts, library }

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
  NaiAccountInfo? _accountInfo;
  bool _isLoadingAccount = false;
  bool _isGenerating = false;
  bool _isChatStreaming = false;
  String _currentStreamingThoughts = '';
  String _currentStreamingContent = '';

  /// 流式请求自动重试提示 (RetryEvent 时设置，新一轮 TurnStart 或结束时清空)
  String? _streamingRetryNotice;

  /// 思考块全局展开开关 (Ctrl+O 切换，默认折叠只显示单行预览)
  bool _isThinkingExpanded = false;
  NaiGeneratedImage? _selectedImage;
  bool _hasUnseenLatest = false;
  String? _statusMessage;
  String? _errorMessage;

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

  /// 实时生图预览状态
  Uint8List? _livePreviewBytes;
  int _liveCurrentStep = 0;
  int _liveTotalSteps = 28;
  double _liveProgress = 0.0;
  DateTime? _generationStartTime;
  StreamSubscription<NaiStreamProgress>? _generationSubscription;

  ThinkingEffort _currentThinkingEffort = ThinkingEffort.high;

  AgentQuestionPrompt? _activeQuestionPrompt;

  /// 是否正在画板上交互式编辑角色位置
  bool _isEditingCharacterPositions = false;

  /// 是否正在画板上交互式编辑水印位置
  bool _isEditingWatermarkPosition = false;

  /// 当前选中的角色 ID (用于高亮锚点及左侧卡片)
  String? _selectedCharacterId;

  /// 是否正在画板上批注当前选中的图片
  bool _isAnnotatingImage = false;

  /// 当前高亮选中的批注 ID
  String? _activeAnnotationId;

  /// 当前自由大画布上的完整节点与连接数据
  CanvasBoardData? _boardData;

  /// 参数持久化防抖计时器
  Timer? _paramSaveDebounceTimer;

  /// 大画布布局持久化防抖计时器 (拖拽/缩放/移动后延迟落盘)
  Timer? _boardSaveDebounceTimer;

  /// 全局配置防抖保存计时器
  Timer? _configSaveDebounceTimer;

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

  /// 当前工作台参数的预计 Anlas 消耗 (账号未加载时按非 Opus 保守估算)
  int get estimatedGenerationCost => AnlasCalculator.estimateGenerationCost(
    params: _params,
    isOpus: _accountInfo?.isOpus ?? false,
    opusQuotaExhausted: _accountInfo?.v5QuotaExhausted ?? false,
  );
  bool get isLoadingAccount => _isLoadingAccount;
  bool get isGenerating => _isGenerating;
  bool get isChatStreaming => _isChatStreaming;
  String get currentStreamingThoughts => _currentStreamingThoughts;
  String get currentStreamingContent => _currentStreamingContent;

  /// 流式请求重试提示 (流式气泡顶部展示)
  String? get streamingRetryNotice => _streamingRetryNotice;

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
  AgentPreset get currentPreset => _harness.currentPreset;
  List<AgentPreset> get presets =>
      _config.presets.isNotEmpty ? _config.presets : BuiltinPresets.all;
  String? get statusMessage => _statusMessage;
  String? get errorMessage => _errorMessage;

  /// 实时生图预览 Getters
  Uint8List? get livePreviewBytes => _livePreviewBytes;
  int get liveCurrentStep => _liveCurrentStep;
  int get liveTotalSteps => _liveTotalSteps;
  double get liveProgress => _liveProgress;
  DateTime? get generationStartTime => _generationStartTime;

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

    _paramSaveDebounceTimer?.cancel();
    _paramSaveDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      _configService.saveLastPrompt(_params.prompt);
      _configService.saveApplyFixedPrompts(_params.applyFixedPrompts);
      _configService.saveCharacterPrompts(_params.characterPrompts);
      _configService.saveCharacterAiPosition(_params.characterAiPosition);
      _configService.saveSeedMode(_params.seedMode);
      _configService.saveSeedTiming(_params.seedTiming);
      if (_params.negativePrompt != _config.negativePrompt ||
          _params.prefixPrompt != _config.prefixPrompt ||
          _params.suffixPrompt != _config.suffixPrompt) {
        final updatedConfig = _config.copyWith(
          negativePrompt: _params.negativePrompt,
          prefixPrompt: _params.prefixPrompt ?? '',
          suffixPrompt: _params.suffixPrompt ?? '',
        );
        _config = updatedConfig;
        _configService.saveConfig(updatedConfig);
      }
    });
  }

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

  /// 装配 Harness、注册全部工具并配置 LLM Provider
  void _setupHarnessAndTools();

  /// 切换 Agent 当前预设
  void selectPreset(AgentPreset preset);

  /// 手动快速生图
  Future<void> generateImage();

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

  /// 发送对话消息 (支持 Slash 命令行；[images] 为用户图片附件)
  Future<void> sendChatMessage(String text, {List<AgentMessageImage>? images});

  /// 全量替换某张历史图片的批注 (Agent 批注工具统一写入口：仓库持久化 + 画布同步)
  Future<bool> replaceImageAnnotations(
    String imageId,
    List<ImageAnnotation> annotations,
  );
}

/// Studio 状态管理中枢 (MVVM)。
class StudioViewModel extends ChangeNotifier
    with
        _StudioCore,
        _StudioLayoutMixin,
        _StudioHarnessMixin,
        _StudioGenerationMixin,
        _StudioChatMixin,
        _StudioSessionsMixin,
        _StudioCharactersMixin,
        _StudioSlashMixin,
        _StudioLibraryMixin,
        _StudioAnnotationsMixin {
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
      recorder: _sessionLog,
      initialPreset: BuiltinPresets.v5Architect,
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

    _params = NaiGenerationParams(
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
      }

      // 恢复大画布布局 (节点位置尺寸/便利贴/连线/视口)
      final board = await _repository.loadBoardLayout(
        saveDir: _config.saveDirectory,
      );
      if (board != null &&
          (board.imageNodes.isNotEmpty || board.noteNodes.isNotEmpty)) {
        _boardData = board;
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

  /// 保存全局配置
  Future<void> updateConfig(AppConfig newConfig) async {
    final oldConfig = _config;
    _config = newConfig;
    notifyListeners();
    await _configService.saveConfig(newConfig);

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
        await _repository.savePersistedHistory(
          saveDir: newConfig.saveDirectory,
          maxImages: newConfig.maxPersistentImages,
          enabled: false,
        );
        // 一并清理大画布布局与参考图缓存
        await _repository.saveBoardLayout(
          _boardData ?? const CanvasBoardData(imageNodes: [], noteNodes: []),
          saveDir: newConfig.saveDirectory,
          enabled: false,
        );
        _boardData = null;
      }
    }

    notifyListeners();

    // 仅在 NovelAI API Key 发生变更时刷新账号，避免调整参数/水印时频繁请求网络
    final keyChanged = oldConfig.novelAiKey != newConfig.novelAiKey;
    if (keyChanged && _config.novelAiKey.isNotEmpty) {
      await refreshAccountInfo();
    }
  }

  /// 防抖保存全局配置 (避免滑块/高频拖拽频繁写盘)
  void _debounceSaveConfig() {
    _configSaveDebounceTimer?.cancel();
    _configSaveDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      _configService.saveConfig(_config);
    });
  }

  /// 切换模型并跟随官方出厂默认值。
  ///
  /// CFG 与步数只在用户未手动调整 (仍停留在旧模型出厂默认) 时才跟随新模型默认，
  /// 手动调过的一律保留；切到 v4+ 时 Native 噪声调度不合法，自动回落 Karras。
  void selectModel(NaiModel model) {
    final old = _params;
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

  /// 选择画板当前查看的图片
  void selectImage(NaiGeneratedImage image) {
    _selectedImage = image;
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
      _hasUnseenLatest = false;
      notifyListeners();
    }
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

    if (wasSelected) {
      if (gallery.isNotEmpty) {
        final nextIndex = deletedIndex < gallery.length
            ? deletedIndex
            : gallery.length - 1;
        _selectedImage = gallery[nextIndex];
      } else {
        _selectedImage = null;
      }
    }

    if (gallery.isEmpty ||
        (_selectedImage != null && _selectedImage!.id == gallery.first.id)) {
      _hasUnseenLatest = false;
    }

    // 同步大画布节点 (若大画布已加载)
    final bData = _boardData;
    if (bData != null) {
      final hasNode = bData.imageNodes.any((n) => n.image.id == imageId);
      if (hasNode) {
        final remainingNodes = <CanvasImageNode>[];
        for (final node in bData.imageNodes) {
          if (node.image.id == imageId) {
            if (node.isMain && _selectedImage != null) {
              remainingNodes.add(
                node.copyWith(
                  image: _selectedImage!,
                  annotations: _selectedImage!.annotations,
                ),
              );
            }
            // 非主图节点或无替代图时直接移除
          } else {
            remainingNodes.add(node);
          }
        }

        final removedNodeIds = bData.imageNodes
            .where((n) => !remainingNodes.any((rem) => rem.id == n.id))
            .map((n) => n.id)
            .toSet();

        final updatedNotes = bData.noteNodes.map((n) {
          if (removedNodeIds.contains(n.targetImageId)) {
            return n.copyWith(clearConnection: true);
          }
          return n;
        }).toList();

        final updatedLinks = bData.imageLinks
            .where(
              (l) =>
                  !removedNodeIds.contains(l.sourceImageId) &&
                  !removedNodeIds.contains(l.targetImageId),
            )
            .toList();

        _boardData = bData.copyWith(
          imageNodes: remainingNodes,
          noteNodes: updatedNotes,
          imageLinks: updatedLinks,
        );
        _scheduleBoardSave();
      }
    }

    _statusMessage = '已从历史记录删除图片';
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
    );

    _selectedImage = null;
    _hasUnseenLatest = false;

    final bData = _boardData;
    if (bData != null) {
      final remainingNodes = bData.imageNodes
          .where((n) => !historyIds.contains(n.image.id))
          .toList();
      final removedNodeIds = bData.imageNodes
          .where((n) => historyIds.contains(n.image.id))
          .map((n) => n.id)
          .toSet();
      if (removedNodeIds.isNotEmpty) {
        final updatedNotes = bData.noteNodes.map((n) {
          if (removedNodeIds.contains(n.targetImageId)) {
            return n.copyWith(clearConnection: true);
          }
          return n;
        }).toList();
        final updatedLinks = bData.imageLinks
            .where(
              (l) =>
                  !removedNodeIds.contains(l.sourceImageId) &&
                  !removedNodeIds.contains(l.targetImageId),
            )
            .toList();
        _boardData = bData.copyWith(
          imageNodes: remainingNodes,
          noteNodes: updatedNotes,
          imageLinks: updatedLinks,
        );
        _scheduleBoardSave();
      }
    }

    _statusMessage = '已清空历史记录';
    notifyListeners();
  }

  // ------------------------- 元数据与水印设置 -------------------------

  bool get stripMetadata => _config.stripMetadata;
  bool get enableWatermark => _config.enableWatermark;
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
      if (_isAnnotatingImage) {
        _isAnnotatingImage = false;
      }
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
    final config = _config.watermarkConfig;
    try {
      final (
        posX,
        posY,
      ) = await WatermarkService.findLowInformationPositionAsync(
        Uint8List.fromList(source.bytes),
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

  /// 一键将外部解析出的元数据应用到工作台参数与提示词
  void applyMetadataToWorkbench(ImageMetadataResult metadata) {
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
            name: '角色 ${i + 1}',
            prompt: p,
            negativePrompt: uc,
          ),
        );
      }
    }

    final newParams = _params.copyWith(
      prompt: metadata.prompt.isNotEmpty ? metadata.prompt : _params.prompt,
      negativePrompt: metadata.negativePrompt.isNotEmpty
          ? metadata.negativePrompt
          : _params.negativePrompt,
      model: resolvedModel ?? _params.model,
      sampler: resolvedSampler ?? _params.sampler,
      noiseSchedule: resolvedSchedule ?? _params.noiseSchedule,
      width: (metadata.width != null && metadata.width! > 0)
          ? metadata.width!
          : _params.width,
      height: (metadata.height != null && metadata.height! > 0)
          ? metadata.height!
          : _params.height,
      steps: (metadata.steps != null && metadata.steps! > 0)
          ? metadata.steps!
          : _params.steps,
      scale: (metadata.scale != null && metadata.scale! > 0)
          ? metadata.scale!
          : _params.scale,
      cfgRescale: metadata.cfgRescale ?? _params.cfgRescale,
      seed: metadata.seed ?? _params.seed,
      qualityToggle: metadata.qualityToggle ?? _params.qualityToggle,
      qualityPreset: metadata.qualityPreset ?? _params.qualityPreset,
      ucPresetKey: metadata.ucPreset ?? _params.ucPresetKey,
      transparentBg: metadata.transparentBackground ?? _params.transparentBg,
      characterPrompts: charPrompts ?? _params.characterPrompts,
    );

    updateParams(newParams);
    _statusMessage = '已应用图片元数据至工作台';
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

  @visibleForTesting
  void setChatStreamingForTesting(bool streaming) {
    _isChatStreaming = streaming;
    notifyListeners();
  }

  @override
  void dispose() {
    _generationSubscription?.cancel();
    _paramSaveDebounceTimer?.cancel();
    _splitWidthSaveTimer?.cancel();
    _promptHeightsSaveTimer?.cancel();
    _chatDraftSaveTimer?.cancel();
    _chatSubscription?.cancel();
    _streamNotifyTimer?.cancel();
    // 大画布布局：取消防抖并立即落盘一次
    _boardSaveDebounceTimer?.cancel();
    unawaited(_flushBoardSave());
    unawaited(_sessionLog.flush());
    super.dispose();
  }
}
