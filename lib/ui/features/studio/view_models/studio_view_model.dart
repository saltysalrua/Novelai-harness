import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../../core/harness/agent_harness.dart';
import '../../../../core/harness/presets/agent_preset.dart';
import '../../../../core/harness/providers/openai_provider.dart';
import '../../../../core/harness/skills/skills.dart';
import '../../../../core/harness/tools/agent_tool.dart';
import '../../../../core/harness/tools/ask_user_tool.dart';
import '../../../../core/harness/tools/load_skill_tool.dart';
import '../../../../core/harness/tools/novelai_tools.dart';
import '../../../../core/harness/tools/studio_params_tool.dart';
import '../../../../core/harness/types.dart';
import '../../../../data/models/novelai_models.dart';
import '../../../../data/repositories/novelai_repository.dart';
import '../../../../data/services/config_service.dart';
import '../../../../data/services/session_log_service.dart';
import '../../../../data/services/usage_ledger_service.dart';

class StudioViewModel extends ChangeNotifier {
  final ConfigService _configService;
  final NovelAiRepository _repository;
  final SessionLogService _sessionLog = SessionLogService();
  final UsageLedgerService _usageLedger = UsageLedgerService();
  late final ToolRegistry _toolRegistry;
  late final AgentHarness _harness;

  /// 本会话内各模型 (provider/model) 的累计 Token 用量 (悬停模型选择器时展示)
  Map<String, TokenUsage> _sessionModelUsage = {};

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
  NaiGeneratedImage? _selectedImage;
  bool _hasUnseenLatest = false;
  String? _statusMessage;
  String? _errorMessage;

  StudioViewModel({ConfigService? configService, NovelAiRepository? repository})
    : _configService = configService ?? ConfigService(),
      _repository = repository ?? NovelAiRepository() {
    _toolRegistry = ToolRegistry();
    _harness = AgentHarness(
      tools: _toolRegistry,
      recorder: _sessionLog,
      initialPreset: BuiltinPresets.v5Architect,
    );
  }

  // 动态注册中心
  final SkillRegistry _skillRegistry = SkillRegistry();
  SkillRegistry get skillRegistry => _skillRegistry;
  List<Skill> get availableSkills => _skillRegistry.getAll();
  List<AgentTool> get availableTools => _toolRegistry.getAll();

  // Getters
  AppConfig get config => _config;
  NaiGenerationParams get params => _params;
  NaiAccountInfo? get accountInfo => _accountInfo;
  bool get isLoadingAccount => _isLoadingAccount;
  bool get isGenerating => _isGenerating;
  bool get isChatStreaming => _isChatStreaming;
  String get currentStreamingThoughts => _currentStreamingThoughts;
  String get currentStreamingContent => _currentStreamingContent;
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

  ThinkingEffort _currentThinkingEffort = ThinkingEffort.high;
  ThinkingEffort get currentThinkingEffort => _currentThinkingEffort;

  AgentQuestionPrompt? _activeQuestionPrompt;
  AgentQuestionPrompt? get activeQuestionPrompt => _activeQuestionPrompt;

  /// 本会话内各模型 (provider/model) 的累计 Token 用量
  Map<String, TokenUsage> get sessionModelUsage =>
      Map.unmodifiable(_sessionModelUsage);

  /// Token 用量账本 (供设置页 Bill 页与统计使用)
  UsageLedgerService get usageLedger => _usageLedger;

  /// 按周期聚合账单
  BillSummary buildBillSummary(BillPeriod period) =>
      _usageLedger.aggregate(period);

  /// 初始化 Studio
  Future<void> init() async {
    _config = await _configService.loadConfig();
    final lastPrompt = await _configService.loadLastPrompt();
    final applyFixed = await _configService.loadApplyFixedPrompts();

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
    );

    // 设置初始预设
    _harness.setPreset(_config.activePreset);

    _setupHarnessAndTools();

    // 初始化会话日志并续接上次对话 (Pi --continue 语义)
    await _sessionLog.init();
    await _usageLedger.init(baseDir: _sessionLog.baseDirPath);
    final snapshot = _sessionLog.loadLatestSession();
    if (snapshot != null && snapshot.messages.isNotEmpty) {
      _harness.restoreMessages(snapshot.messages);
      _sessionModelUsage = Map.of(snapshot.sessionUsage);
    }
    _sessionLog.recordModelChange(
      _config.activeLlmProvider.id,
      _config.activeLlmProvider.activeModel.id,
    );
    _sessionLog.recordThinkingLevelChange(_currentThinkingEffort.id);
    await refreshSessions();

    notifyListeners();

    // 后台加载账号信息
    if (_config.novelAiKey.isNotEmpty) {
      await refreshAccountInfo();
    }
  }

  void _setupHarnessAndTools() {
    // 动态同步 SkillRegistry
    _skillRegistry.registerAll(_config.customSkills);

    // 注册内置工具
    _toolRegistry.register(
      NovelAiGenerateTool(
        repository: _repository,
        configService: _configService,
        getCurrentParams: () => _params,
        onGenerated: (image) {
          if (isViewingLatest) {
            _selectedImage = image;
            _hasUnseenLatest = false;
          } else {
            _hasUnseenLatest = true;
          }
          notifyListeners();
          refreshAccountInfo();
        },
        onConfirmPaidGeneration: _confirmPaidGeneration,
      ),
    );
    _toolRegistry.register(
      NovelAiUpscaleTool(
        repository: _repository,
        configService: _configService,
        onUpscaled: (image) {
          _selectedImage = image;
          notifyListeners();
        },
      ),
    );
    _toolRegistry.register(
      NovelAiSuggestTagsTool(
        repository: _repository,
        configService: _configService,
      ),
    );
    _toolRegistry.register(
      NovelAiAccountInfoTool(
        repository: _repository,
        configService: _configService,
      ),
    );
    _toolRegistry.register(AskUserTool(onAsk: _presentQuestionsToUser));
    _toolRegistry.register(
      NovelAiGetStudioParamsTool(getCurrentParams: () => _params),
    );
    _toolRegistry.register(
      NovelAiUpdateParamsTool(
        getCurrentParams: () => _params,
        onUpdateParams: updateParams,
        permissionChecker: (key) =>
            _harness.currentPreset.isParamModifiable(key),
      ),
    );
    _toolRegistry.register(
      LoadSkillTool(
        // 仅允许加载当前预设开放的技能，防止越权读取
        skillResolver: (name) {
          final skill = _skillRegistry.get(name);
          if (skill == null) return null;
          return _harness.currentPreset.enabledSkillIds.contains(skill.id)
              ? skill
              : null;
        },
        availableSkillIds: () =>
            _harness.currentPreset.enabledSkillIds.toList(),
      ),
    );

    // 注册自定义扩展工具
    for (final customTool in _config.customTools) {
      _toolRegistry.register(customTool);
    }

    // 配置 LLM Provider
    final activeLlm = _config.activeLlmProvider;
    final activeModel = activeLlm.activeModel;
    _harness.providerLabel = activeLlm.id;
    if (activeLlm.apiKey.isNotEmpty) {
      final isReasoningActive =
          activeModel.supportsThinking &&
          _currentThinkingEffort != ThinkingEffort.off;

      _harness.provider = OpenAiCompatibleProvider(
        baseUrl: activeLlm.fullEndpointUrl,
        apiKey: activeLlm.apiKey,
        model: activeModel.id,
        reasoning: isReasoningActive,
        thinkingEffort: isReasoningActive ? _currentThinkingEffort.id : null,
      );
    } else {
      _harness.provider = null;
    }
  }

  /// 动态调整 Agent 思考强度 (在对话工作台中随点随切)
  void setThinkingEffort(ThinkingEffort effort) {
    if (_currentThinkingEffort == effort) return;
    _currentThinkingEffort = effort;
    _setupHarnessAndTools();
    _sessionLog.recordThinkingLevelChange(effort.id);
    notifyListeners();
  }

  /// 动态切换当前生效的大模型 (在对话工作台中即时切换)
  void switchActiveModel(String modelId) {
    final activeProvider = _config.activeLlmProvider;
    if (!activeProvider.models.any((m) => m.id == modelId)) return;

    final updatedProviders = _config.llmProviders.map((p) {
      if (p.id == activeProvider.id) {
        return p.copyWith(activeModelId: modelId);
      }
      return p;
    }).toList();

    _config = _config.copyWith(llmProviders: updatedProviders);
    final targetModel = activeProvider.models.firstWhere(
      (m) => m.id == modelId,
    );
    _currentThinkingEffort = targetModel.defaultThinkingEffort;

    _configService.saveConfig(_config);
    _sessionLog.recordModelChange(activeProvider.id, modelId);
    _setupHarnessAndTools();
    notifyListeners();
  }

  /// 动态切换当前生效的供应商
  void switchActiveProvider(String providerId) {
    if (!_config.llmProviders.any((p) => p.id == providerId)) return;
    _config = _config.copyWith(activeLlmProviderId: providerId);
    _currentThinkingEffort =
        _config.activeLlmProvider.activeModel.defaultThinkingEffort;

    _configService.saveConfig(_config);
    _sessionLog.recordModelChange(
      providerId,
      _config.activeLlmProvider.activeModel.id,
    );
    _setupHarnessAndTools();
    notifyListeners();
  }

  /// 立即持久化 LLM 供应商列表 (设置对话框在线拉取后写盘，避免忘记点保存丢失)
  Future<void> persistLlmProviders(
    List<LlmProviderConfig> providers,
    String activeProviderId,
  ) async {
    _config = _config.copyWith(
      llmProviders: providers,
      activeLlmProviderId: activeProviderId,
    );
    _currentThinkingEffort =
        _config.activeLlmProvider.activeModel.defaultThinkingEffort;

    await _configService.saveConfig(_config);
    _setupHarnessAndTools();
    notifyListeners();
  }

  /// 保存全局配置
  Future<void> updateConfig(AppConfig newConfig) async {
    _config = newConfig;
    await _configService.saveConfig(newConfig);
    _currentThinkingEffort =
        _config.activeLlmProvider.activeModel.defaultThinkingEffort;
    _setupHarnessAndTools();
    notifyListeners();

    if (_config.novelAiKey.isNotEmpty) {
      await refreshAccountInfo();
    }
  }

  Timer? _paramSaveDebounceTimer;

  /// 更新侧边栏参数
  void updateParams(NaiGenerationParams newParams) {
    _params = newParams;
    notifyListeners();

    _paramSaveDebounceTimer?.cancel();
    _paramSaveDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      _configService.saveLastPrompt(_params.prompt);
      _configService.saveApplyFixedPrompts(_params.applyFixedPrompts);
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

  /// 快速切换官方分辨率预设 (分类 + 方向)
  void selectResolution(
    ResolutionCategory category,
    ResolutionOrientation orientation,
  ) {
    if (category == ResolutionCategory.custom) {
      if (orientation == ResolutionOrientation.landscape &&
          _params.width < _params.height) {
        final tmp = _params.width;
        _params = _params.copyWith(width: _params.height, height: tmp);
      } else if (orientation == ResolutionOrientation.portrait &&
          _params.width > _params.height) {
        final tmp = _params.width;
        _params = _params.copyWith(width: _params.height, height: tmp);
      }
    } else {
      final (w, h) = ResolutionPresetHelper.getDimensions(
        category,
        orientation,
      );
      _params = _params.copyWith(width: w, height: h);
    }
    notifyListeners();
  }

  /// 快速交换宽高
  void swapResolution() {
    _params = _params.copyWith(width: _params.height, height: _params.width);
    notifyListeners();
  }

  /// 快速切换分辨率预设 (兼容老调用)
  void selectResolutionPreset(ResolutionPreset preset) {
    _params = _params.copyWith(width: preset.width, height: preset.height);
    notifyListeners();
  }

  /// 选择画板当前查看的图片
  void selectImage(NaiGeneratedImage image) {
    _selectedImage = image;
    if (gallery.isNotEmpty && image.id == gallery.first.id) {
      _hasUnseenLatest = false;
    }
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

  /// 切换 Agent 当前预设
  void selectPreset(AgentPreset preset) {
    _harness.setPreset(preset);
    _config = _config.copyWith(activePresetId: preset.id);
    _configService.saveConfig(_config);
    _harness.addInfoMessage('已切换为预设: 【${preset.name}】\n${preset.description}');
    notifyListeners();
  }

  /// 保存/更新预设配置
  Future<void> savePreset(AgentPreset preset) async {
    final currentList = presets.toList();
    final index = currentList.indexWhere((p) => p.id == preset.id);
    if (index >= 0) {
      currentList[index] = preset;
    } else {
      currentList.add(preset);
    }
    _config = _config.copyWith(presets: currentList);
    if (_harness.currentPreset.id == preset.id) {
      _harness.setPreset(preset);
    }
    await _configService.saveConfig(_config);
    notifyListeners();
  }

  /// 删除自定义预设
  Future<void> deletePreset(String presetId) async {
    if (presets.length <= 1) return;
    final currentList = presets.where((p) => p.id != presetId).toList();
    var activeId = _config.activePresetId;
    if (activeId == presetId) {
      activeId = currentList.first.id;
      _harness.setPreset(currentList.first);
    }
    _config = _config.copyWith(presets: currentList, activePresetId: activeId);
    await _configService.saveConfig(_config);
    notifyListeners();
  }

  /// 保存/更新自定义技能
  Future<void> saveCustomSkill(Skill skill) async {
    _skillRegistry.register(skill);
    final customList = _config.customSkills.toList();
    final idx = customList.indexWhere((s) => s.id == skill.id);
    if (idx >= 0) {
      customList[idx] = skill;
    } else {
      customList.add(skill);
    }
    _config = _config.copyWith(customSkills: customList);
    await _configService.saveConfig(_config);
    notifyListeners();
  }

  /// 删除自定义技能
  Future<void> deleteCustomSkill(String skillId) async {
    _skillRegistry.unregister(skillId);
    final customList = _config.customSkills
        .where((s) => s.id != skillId)
        .toList();
    _config = _config.copyWith(customSkills: customList);
    await _configService.saveConfig(_config);
    notifyListeners();
  }

  /// 从标准 SKILL.md 导入技能
  Future<Skill> importSkillFromMd(String mdContent, {String? defaultId}) async {
    final skill = Skill.fromSkillMd(mdContent, defaultId: defaultId);
    await saveCustomSkill(skill);
    return skill;
  }

  /// 保存/更新自定义扩展工具
  Future<void> saveCustomTool(CustomAgentTool tool) async {
    _toolRegistry.register(tool);
    final customTools = _config.customTools.toList();
    final idx = customTools.indexWhere((t) => t.name == tool.name);
    if (idx >= 0) {
      customTools[idx] = tool;
    } else {
      customTools.add(tool);
    }
    _config = _config.copyWith(customTools: customTools);
    await _configService.saveConfig(_config);
    notifyListeners();
  }

  /// 删除自定义扩展工具
  Future<void> deleteCustomTool(String toolName) async {
    _toolRegistry.unregister(toolName);
    final customTools = _config.customTools
        .where((t) => t.name != toolName)
        .toList();
    _config = _config.copyWith(customTools: customTools);
    await _configService.saveConfig(_config);
    notifyListeners();
  }

  /// 手动快速生图 (使用左侧面板参数)
  Future<void> generateImage() async {
    if (_params.prompt.trim().isEmpty) {
      _errorMessage = '提示词不能为空，请先在左侧或对话框中输入描述。';
      notifyListeners();
      return;
    }

    if (_config.novelAiKey.trim().isEmpty) {
      _errorMessage = '未配置 NovelAI API Key，请点击右上角设置。';
      notifyListeners();
      return;
    }

    final wasViewingLatest = isViewingLatest;

    _isGenerating = true;
    _errorMessage = null;
    _statusMessage =
        '正在请求 NovelAI 生图 (${_params.width}x${_params.height}, ${_params.steps}步)...';
    notifyListeners();

    try {
      final results = await _repository.generate(
        apiKey: _config.novelAiKey,
        params: _params,
        saveDir: _config.saveDirectory,
      );

      if (results.isNotEmpty) {
        final newImage = results.first;
        if (wasViewingLatest) {
          _selectedImage = newImage;
          _hasUnseenLatest = false;
        } else {
          // 当前在查看历史图片，不强行跳转，在 UI 给出新图生成提醒
          _hasUnseenLatest = true;
        }
        _statusMessage = '生图完成，已保存在 ${newImage.localFilePath ?? '本地'}';
      }
    } catch (e) {
      _errorMessage = '生图失败: $e';
      _statusMessage = null;
    } finally {
      _isGenerating = false;
      notifyListeners();
      // 生图后异步刷新体力与点数
      refreshAccountInfo();
    }
  }

  /// 超分放大当前图片 (2x / 4x)
  Future<void> upscaleSelected({int scale = 4}) async {
    if (_selectedImage == null) {
      _errorMessage = '当前画板中无图片可供放大。';
      notifyListeners();
      return;
    }

    if (_config.novelAiKey.trim().isEmpty) {
      _errorMessage = '未配置 NovelAI API Key。';
      notifyListeners();
      return;
    }

    _isGenerating = true;
    _errorMessage = null;
    _statusMessage = '正在执行 ${scale}x 图像超分放大...';
    notifyListeners();

    try {
      final upscaled = await _repository.upscale(
        apiKey: _config.novelAiKey,
        sourceImage: _selectedImage!,
        scale: scale,
        saveDir: _config.saveDirectory,
      );
      _selectedImage = upscaled;
      _statusMessage = '放大完成 (${scale}x)';
    } catch (e) {
      _errorMessage = '放大失败: $e';
      _statusMessage = null;
    } finally {
      _isGenerating = false;
      notifyListeners();
      refreshAccountInfo();
    }
  }

  /// 刷新账号与体力信息
  Future<void> refreshAccountInfo() async {
    if (_config.novelAiKey.trim().isEmpty) return;

    _isLoadingAccount = true;
    notifyListeners();

    try {
      _accountInfo = await _repository.fetchAccountInfo(
        apiKey: _config.novelAiKey,
      );
    } catch (_) {
      // ignore
    } finally {
      _isLoadingAccount = false;
      notifyListeners();
    }
  }

  /// 强行中止当前对话生成与工具执行 (ESC 触发)
  Future<void> abortChat() async {
    if (!_isChatStreaming) return;
    await _chatSubscription?.cancel();
    _chatSubscription = null;
    _isChatStreaming = false;
    _currentStreamingThoughts = '';
    _currentStreamingContent = '';
    _statusMessage = '已强制终止当前生成';
    notifyListeners();
  }

  /// 刷新会话列表
  Future<void> refreshSessions() async {
    if (!_sessionLog.isInitialized) return;
    _sessions = await _sessionLog.listSessions();
    notifyListeners();
  }

  /// 切换至指定会话
  Future<void> switchSession(String sessionId) async {
    if (_isChatStreaming) {
      await abortChat();
    }
    final snapshot = _sessionLog.loadSession(sessionId);
    if (snapshot != null) {
      _harness.setMessages(snapshot.messages);
      _sessionModelUsage = Map.of(snapshot.sessionUsage);
      if (snapshot.thinkingLevel != null) {
        final effort = ThinkingEffort.fromId(snapshot.thinkingLevel);
        _currentThinkingEffort = effort;
      }
      _statusMessage = '已切换会话: ${snapshot.sessionTitle ?? sessionId}';
    } else {
      _harness.setMessages([]);
      _sessionModelUsage = {};
    }
    await refreshSessions();
    notifyListeners();
  }

  /// 创建全新会话
  Future<void> createNewSession({String? title}) async {
    if (_isChatStreaming) {
      await abortChat();
    }
    await _sessionLog.createSession(title: title);
    _harness.setMessages([]);
    _sessionModelUsage = {};
    _statusMessage = '已创建新会话';
    await refreshSessions();
    notifyListeners();
  }

  /// 删除指定会话
  Future<void> deleteSession(String sessionId) async {
    final isCurrent = sessionId == currentSessionId;
    await _sessionLog.deleteSession(sessionId);
    if (isCurrent) {
      final remaining = await _sessionLog.listSessions();
      if (remaining.isNotEmpty) {
        await switchSession(remaining.first.id);
      } else {
        await createNewSession();
      }
    } else {
      await refreshSessions();
    }
    _statusMessage = '会话已删除';
    notifyListeners();
  }

  /// 重命名指定会话
  Future<void> renameSession(String sessionId, String newTitle) async {
    await _sessionLog.renameSession(sessionId, newTitle);
    await refreshSessions();
    notifyListeners();
  }

  /// 回退/撤销到指定历史消息时刻 (按两次 ESC 触发选择)
  Future<void> rewindToMessage(String messageId) async {
    if (_isChatStreaming) {
      await abortChat();
    }
    final success = _harness.rewindToMessage(messageId);
    if (success) {
      // 重新聚合本会话各模型剩余用量
      final updatedUsage = <String, TokenUsage>{};
      for (final msg in _harness.messages) {
        if (msg.role == AgentRole.assistant &&
            msg.providerModelKey != null &&
            (msg.usage?.total ?? 0) > 0) {
          final key = msg.providerModelKey!;
          updatedUsage[key] = (updatedUsage[key] ?? const TokenUsage()).add(
            msg.usage!,
          );
        }
      }
      _sessionModelUsage = updatedUsage;
      _statusMessage = '已回到历史时刻，后续对话与修改已撤回';
      await refreshSessions();
      notifyListeners();
    }
  }

  /// 发送对话消息 (支持 Slash 命令行如 /nai, /tag, /upscale, /account, /clear, /help)
  Future<void> sendChatMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    // 1. 处理 Slash 指令
    if (trimmed.startsWith('/')) {
      await _handleSlashCommand(trimmed);
      return;
    }

    // 2. 正常 Agent 对话循环
    _isChatStreaming = true;
    _currentStreamingThoughts = '';
    _currentStreamingContent = '';
    _errorMessage = null;
    notifyListeners();

    final completer = Completer<void>();

    try {
      final stream = _harness.send(
        trimmed,
        temperature: _config.llmTemperature,
      );

      _chatSubscription = stream.listen(
        (event) {
          if (event is ThoughtDeltaEvent) {
            _currentStreamingThoughts += event.delta;
            notifyListeners();
          } else if (event is ContentDeltaEvent) {
            _currentStreamingContent += event.delta;
            notifyListeners();
          } else if (event is UsageEvent) {
            _recordModelUsage(event.usage);
          } else if (event is ToolResultEvent) {
            notifyListeners();
          } else if (event is ErrorEvent) {
            _errorMessage = event.error;
            notifyListeners();
          }
        },
        onError: (e) {
          _errorMessage = '对话异常: $e';
          if (!completer.isCompleted) completer.complete();
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
        cancelOnError: true,
      );

      await completer.future;
    } catch (e) {
      _errorMessage = '对话异常: $e';
    } finally {
      _chatSubscription = null;
      _isChatStreaming = false;
      _currentStreamingThoughts = '';
      _currentStreamingContent = '';
      await refreshSessions();
      notifyListeners();
    }
  }

  Future<void> _handleSlashCommand(String command) async {
    final parts = command.split(' ');
    final cmd = parts[0].toLowerCase();
    final args = parts.skip(1).join(' ').trim();

    switch (cmd) {
      case '/help':
        _harness.addInfoMessage('''快捷指令说明：
• /preset <名称> : 切换当前 Agent 预设 (例如 /preset V5)
• /skill <名称> : 按需加载并执行专业技能 (例如 /skill danbooru-tags)
• /params : 查看工作台当前生效的全部生图参数
• /nai <提示词> [--landscape|--portrait|--square|--wallpaper] : 快速生成插画
• /upscale [2|4] : 超分放大当前图片
• /tag <关键词> : 查询 Danbooru 官方标签联想
• /account : 查询账号订阅等级与 V5 专属体力池
• /clear : 清空对话历史''');
        notifyListeners();
        break;

      case '/params':
        final costStatus = _params.isOpusFree
            ? '符合 Opus 免费区间 (0 Anlas)'
            : '超出免费区间 (将消耗点数)';
        _harness.addInfoMessage('''工作台当前生图参数：
• 正向提示词: ${_params.prompt.isEmpty ? '(空)' : _params.prompt}
• 负向提示词: ${_params.negativePrompt.isEmpty ? '(空)' : _params.negativePrompt}
• 绘图模型: ${_params.model.label} (${_params.model.id})
• 画面尺寸: ${_params.width}x${_params.height}
• 采样步数: ${_params.steps} 步
• CFG 强度: ${_params.scale} (Rescale: ${_params.cfgRescale})
• 采样算法: ${_params.sampler.label} (${_params.sampler.id})
• 噪声调度: ${_params.noiseSchedule.label} (${_params.noiseSchedule.id})
• 随机种子: ${_params.seed == -1 ? '随机 (-1)' : _params.seed}
• Opus 状态: $costStatus''');
        notifyListeners();
        break;

      case '/preset':
        if (args.isEmpty) {
          final listStr = presets
              .map((p) => '• ${p.name} (${p.id})')
              .join('\n');
          _harness.addInfoMessage('可用预设列表：\n$listStr\n用法: /preset <预设名称或ID>');
        } else {
          final target = presets.firstWhere(
            (p) =>
                p.id.toLowerCase() == args.toLowerCase() ||
                p.name.toLowerCase().contains(args.toLowerCase()),
            orElse: () => currentPreset,
          );
          selectPreset(target);
        }
        notifyListeners();
        break;

      case '/skill':
        if (args.isEmpty) {
          final listStr = availableSkills
              .map((s) => '• ${s.id}: ${s.name}')
              .join('\n');
          _harness.addInfoMessage('可用技能列表：\n$listStr\n用法: /skill <技能名称或ID>');
        } else {
          final skill = _skillRegistry.get(args);
          if (skill != null) {
            _harness.addInfoMessage(
              '【Skill 已载入】${skill.name}\n${skill.description}\n\n${skill.systemPrompt}',
            );
          } else {
            _harness.addInfoMessage('未找到技能 "$args"，输入 /skill 查看可用技能。');
          }
        }
        notifyListeners();
        break;

      case '/clear':
        _harness.clearMessages();
        _sessionModelUsage = {};
        await refreshSessions();
        notifyListeners();
        break;

      case '/account':
        await refreshAccountInfo();
        if (_accountInfo != null) {
          final info = _accountInfo!;
          _harness.addInfoMessage(
            '''NovelAI 账号状态：
• 订阅等级: ${info.tierName}
• V5 专属体力池: ${info.staminaPercent.toStringAsFixed(1)}%
• 可用 Anlas: ${info.totalAnlas} (赠送: ${info.fixedAnlas}, 购买: ${info.purchasedAnlas})''',
          );
        } else {
          _harness.addInfoMessage('查询账号信息失败，请检查 API Key 设置。');
        }
        notifyListeners();
        break;

      case '/tag':
        if (args.isEmpty) {
          _harness.addInfoMessage('用法: /tag <关键词> (例如: /tag silver)');
          notifyListeners();
          return;
        }
        final tags = await _repository.suggestTags(
          apiKey: _config.novelAiKey,
          query: args,
        );
        if (tags.isEmpty) {
          _harness.addInfoMessage('未找到与 "$args" 相关的标签。');
        } else {
          final listStr = tags
              .take(8)
              .map((t) => '• ${t.tag} (${t.count})')
              .join('\n');
          _harness.addInfoMessage('标签联想建议 ("$args"):\n$listStr');
        }
        notifyListeners();
        break;

      case '/upscale':
        final scale = int.tryParse(args) ?? 4;
        await upscaleSelected(scale: scale);
        _harness.addInfoMessage('已执行 ${scale}x 放大');
        notifyListeners();
        break;

      case '/nai':
        if (args.isEmpty) {
          _harness.addInfoMessage('用法: /nai <提示词>');
          notifyListeners();
          return;
        }

        String prompt = args;
        int w = _params.width;
        int h = _params.height;

        if (prompt.contains('--landscape')) {
          prompt = prompt.replaceAll('--landscape', '').trim();
          w = 1216;
          h = 832;
        } else if (prompt.contains('--portrait')) {
          prompt = prompt.replaceAll('--portrait', '').trim();
          w = 832;
          h = 1216;
        } else if (prompt.contains('--square')) {
          prompt = prompt.replaceAll('--square', '').trim();
          w = 1024;
          h = 1024;
        } else if (prompt.contains('--wallpaper')) {
          prompt = prompt.replaceAll('--wallpaper', '').trim();
          w = 1920;
          h = 1088;
        }

        _params = _params.copyWith(prompt: prompt, width: w, height: h);
        await generateImage();
        if (_selectedImage != null) {
          _harness.addInfoMessage(
            '插画已生成: ${_selectedImage!.localFilePath ?? '完成'}\n尺寸: ${w}x$h, 种子: ${_selectedImage!.seed}',
          );
        }
        notifyListeners();
        break;

      default:
        _harness.addInfoMessage('未知指令 "$cmd"，输入 /help 查看可用指令。');
        notifyListeners();
    }
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// 呈现 AI 提问卡片 (内嵌于 AgentCard 对话流中)
  Future<List<String>?> _presentQuestionsToUser(
    List<AgentQuestion> questions,
  ) async {
    final completer = Completer<List<String>?>();
    _activeQuestionPrompt = AgentQuestionPrompt(
      questions: questions,
      completer: completer,
    );
    notifyListeners();

    try {
      final answers = await completer.future;
      return answers;
    } finally {
      _activeQuestionPrompt = null;
      notifyListeners();
    }
  }

  /// 付费生图申请确认 (内嵌于对话流，纯选择按钮，禁止自定义文本框)
  Future<bool> _confirmPaidGeneration({
    required NaiGenerationParams params,
    required List<String> reasons,
  }) async {
    final reasonText = reasons.join('、');
    final answer = await _presentQuestionsToUser([
      AgentQuestion(
        header: '点数消耗申请',
        question: '本次生图参数（$reasonText）超出了 Opus 免费区间，将消耗 Anlas 点数。是否确认生成？',
        allowCustomInput: false,
        options: const [
          AgentQuestionOption(label: '确认生成', description: '使用当前参数直接生图并扣除点数'),
          AgentQuestionOption(label: '取消生图', description: '取消本次生成，调整参数至免费区间'),
        ],
      ),
    ]);

    if (answer == null || answer.isEmpty) return false;
    return answer.first.contains('确认生成');
  }

  /// 记录一次模型响应的 Token 用量: 会话内聚合 + 持久化账本
  void _recordModelUsage(TokenUsage usage) {
    final providerId = _harness.providerLabel ?? 'unknown';
    final modelId = _harness.provider?.modelId ?? 'unknown';
    final key = '$providerId/$modelId';
    _sessionModelUsage[key] = (_sessionModelUsage[key] ?? const TokenUsage())
        .add(usage);
    _usageLedger.record(
      key: 'usage_${DateTime.now().microsecondsSinceEpoch}',
      provider: providerId,
      model: modelId,
      usage: usage,
    );
    notifyListeners();
  }

  void clearStatus() {
    _statusMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _paramSaveDebounceTimer?.cancel();
    _chatSubscription?.cancel();
    unawaited(_sessionLog.flush());
    super.dispose();
  }
}
