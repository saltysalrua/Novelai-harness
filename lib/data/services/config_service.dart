import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/harness/presets/agent_preset.dart';
import '../../core/harness/skills/skills.dart';
import '../../core/harness/tools/agent_tool.dart';
import '../models/novelai_models.dart';

/// 全局配置数据模型
class AppConfig {
  // NovelAI 设置
  final String novelAiKey;
  final NaiModel defaultModel;
  final NaiSampler defaultSampler;
  final NoiseSchedule defaultNoiseSchedule;
  final ResolutionPreset defaultResolution;
  final int customWidth;
  final int customHeight;
  final int defaultSteps;
  final double defaultScale;
  final double defaultCfgRescale;
  final bool opusFreeMode;
  final bool enableStreamPreview;
  final bool enableTagAutocomplete;
  final bool showTagTranslations;
  final bool showTagCategoryColors;
  final bool enableTagDictionaryAutoUpdate;
  final String prefixPrompt;
  final String suffixPrompt;
  final String negativePrompt;
  final String saveDirectory;

  // LLM 设置 (多供应商配置)
  final List<LlmProviderConfig> llmProviders;
  final String activeLlmProviderId;

  // Agent 预设 (多预设配置)
  final List<AgentPreset> presets;
  final String activePresetId;

  // 自定义 Skill 库与自定义 Tool 库
  final List<Skill> customSkills;
  final List<CustomAgentTool> customTools;

  /// 当前激活的 LLM 供应商配置
  LlmProviderConfig get activeLlmProvider {
    final list = llmProviders.isNotEmpty
        ? llmProviders
        : LlmProviderConfig.defaultProviders;
    return list.firstWhere(
      (p) => p.id == activeLlmProviderId,
      orElse: () => list.first,
    );
  }

  /// 当前激活的 Agent 预设
  AgentPreset get activePreset {
    final list = presets.isNotEmpty ? presets : BuiltinPresets.all;
    return list.firstWhere(
      (p) => p.id == activePresetId,
      orElse: () => list.first,
    );
  }

  // 向后兼容快捷访问属性
  String get llmBaseUrl => activeLlmProvider.baseUrl;
  String get llmApiKey => activeLlmProvider.apiKey;
  String get llmModel => activeLlmProvider.model;
  double get llmTemperature => activeLlmProvider.temperature;

  const AppConfig({
    this.novelAiKey = '',
    this.defaultModel = NaiModel.v5Full,
    this.defaultSampler = NaiSampler.kEuler,
    this.defaultNoiseSchedule = NoiseSchedule.karras,
    this.defaultResolution = ResolutionPreset.portrait,
    this.customWidth = 832,
    this.customHeight = 1216,
    this.defaultSteps = 28,
    this.defaultScale = 5.0,
    this.defaultCfgRescale = 0.0,
    this.opusFreeMode = true,
    this.enableStreamPreview = true,
    this.enableTagAutocomplete = true,
    this.showTagTranslations = true,
    this.showTagCategoryColors = true,
    this.enableTagDictionaryAutoUpdate = true,
    this.prefixPrompt = '',
    this.suffixPrompt = '',
    this.negativePrompt = '',
    this.saveDirectory = '',
    this.llmProviders = const [],
    this.activeLlmProviderId = 'deepseek',
    this.presets = const [],
    this.activePresetId = 'v5-architect-preset',
    this.customSkills = const [],
    this.customTools = const [],
  });

  AppConfig copyWith({
    String? novelAiKey,
    NaiModel? defaultModel,
    NaiSampler? defaultSampler,
    NoiseSchedule? defaultNoiseSchedule,
    ResolutionPreset? defaultResolution,
    int? customWidth,
    int? customHeight,
    int? defaultSteps,
    double? defaultScale,
    double? defaultCfgRescale,
    bool? opusFreeMode,
    bool? enableStreamPreview,
    bool? enableTagAutocomplete,
    bool? showTagTranslations,
    bool? showTagCategoryColors,
    bool? enableTagDictionaryAutoUpdate,
    String? prefixPrompt,
    String? suffixPrompt,
    String? negativePrompt,
    String? saveDirectory,
    List<LlmProviderConfig>? llmProviders,
    String? activeLlmProviderId,
    List<AgentPreset>? presets,
    String? activePresetId,
    List<Skill>? customSkills,
    List<CustomAgentTool>? customTools,
    // 兼容老调用单字段设置
    String? llmBaseUrl,
    String? llmApiKey,
    String? llmModel,
    double? llmTemperature,
  }) {
    var updatedProviders = llmProviders ?? this.llmProviders;
    var targetActiveId = activeLlmProviderId ?? this.activeLlmProviderId;

    if (llmBaseUrl != null ||
        llmApiKey != null ||
        llmModel != null ||
        llmTemperature != null) {
      final currentList =
          (updatedProviders.isNotEmpty
                  ? updatedProviders
                  : LlmProviderConfig.defaultProviders)
              .toList();
      final index = currentList.indexWhere((p) => p.id == targetActiveId);
      if (index >= 0) {
        final current = currentList[index];
        currentList[index] = current.copyWith(
          baseUrl: llmBaseUrl,
          apiKey: llmApiKey,
          model: llmModel,
          temperature: llmTemperature,
        );
      }
      updatedProviders = currentList;
    }

    return AppConfig(
      novelAiKey: novelAiKey ?? this.novelAiKey,
      defaultModel: defaultModel ?? this.defaultModel,
      defaultSampler: defaultSampler ?? this.defaultSampler,
      defaultNoiseSchedule: defaultNoiseSchedule ?? this.defaultNoiseSchedule,
      defaultResolution: defaultResolution ?? this.defaultResolution,
      customWidth: customWidth ?? this.customWidth,
      customHeight: customHeight ?? this.customHeight,
      defaultSteps: defaultSteps ?? this.defaultSteps,
      defaultScale: defaultScale ?? this.defaultScale,
      defaultCfgRescale: defaultCfgRescale ?? this.defaultCfgRescale,
      opusFreeMode: opusFreeMode ?? this.opusFreeMode,
      enableStreamPreview: enableStreamPreview ?? this.enableStreamPreview,
      enableTagAutocomplete:
          enableTagAutocomplete ?? this.enableTagAutocomplete,
      showTagTranslations: showTagTranslations ?? this.showTagTranslations,
      showTagCategoryColors:
          showTagCategoryColors ?? this.showTagCategoryColors,
      enableTagDictionaryAutoUpdate:
          enableTagDictionaryAutoUpdate ?? this.enableTagDictionaryAutoUpdate,
      prefixPrompt: prefixPrompt ?? this.prefixPrompt,
      suffixPrompt: suffixPrompt ?? this.suffixPrompt,
      negativePrompt: negativePrompt ?? this.negativePrompt,
      saveDirectory: saveDirectory ?? this.saveDirectory,
      llmProviders: updatedProviders,
      activeLlmProviderId: targetActiveId,
      presets: presets ?? this.presets,
      activePresetId: activePresetId ?? this.activePresetId,
      customSkills: customSkills ?? this.customSkills,
      customTools: customTools ?? this.customTools,
    );
  }
}

/// 配置持久化与自适应加载服务
class ConfigService {
  static const String _keyNovelAiKey = 'novelai_key';
  static const String _keyModel = 'novelai_model';
  static const String _keySampler = 'novelai_sampler';
  static const String _keyNoiseSchedule = 'novelai_noise_schedule';
  static const String _keyResolution = 'novelai_resolution';
  static const String _keyCustomWidth = 'novelai_custom_width';
  static const String _keyCustomHeight = 'novelai_custom_height';
  static const String _keySteps = 'novelai_steps';
  static const String _keyScale = 'novelai_scale';
  static const String _keyCfgRescale = 'novelai_cfg_rescale';
  static const String _keyOpusFreeMode = 'novelai_opus_free_mode';
  static const String _keyEnableStreamPreview = 'novelai_enable_stream_preview';
  static const String _keyEnableTagAutocomplete =
      'novelai_enable_tag_autocomplete';
  static const String _keyShowTagTranslations = 'novelai_show_tag_translations';
  static const String _keyShowTagCategoryColors =
      'novelai_show_tag_category_colors';
  static const String _keyEnableTagDictAutoUpdate =
      'novelai_enable_tag_dictionary_auto_update';
  static const String _keyPrefix = 'novelai_prefix';
  static const String _keySuffix = 'novelai_suffix';
  static const String _keyNegative = 'novelai_negative';
  static const String _keySaveDir = 'novelai_save_dir';
  static const String _keyLastPrompt = 'novelai_last_prompt';
  static const String _keyApplyFixedPrompts = 'novelai_apply_fixed_prompts';
  static const String _keyCharacterPrompts = 'novelai_character_prompts';
  static const String _keyCharacterAiPosition = 'novelai_character_ai_position';

  // 页面布局持久化 Keys
  static const String _keySplitLeftWidth = 'novelai_layout_split_left_width';
  static const String _keySplitRightWidth = 'novelai_layout_split_right_width';
  static const String _keySidebarActiveTab = 'novelai_layout_sidebar_active_tab';
  static const String _keyPromptTabbedMode = 'novelai_layout_prompt_tabbed_mode';
  static const String _keyPromptActiveTab = 'novelai_layout_prompt_active_tab';
  static const String _keyDeckActiveTab = 'novelai_layout_deck_active_tab';
  static const String _keyCanvasHistoryOpen = 'novelai_layout_canvas_history_open';

  static const String _keyLlmBaseUrl = 'llm_base_url';
  static const String _keyLlmApiKey = 'llm_api_key';
  static const String _keyLlmModel = 'llm_model';
  static const String _keyLlmTemperature = 'llm_temperature';
  static const String _keyLlmProviders = 'llm_providers_json';
  static const String _keyActiveLlmProviderId = 'active_llm_provider_id';
  static const String _keyPresets = 'agent_presets_json';
  static const String _keyActivePresetId = 'active_preset_id';
  static const String _keyCustomSkills = 'agent_custom_skills_json';
  static const String _keyCustomTools = 'agent_custom_tools_json';

  /// 加载配置 (优先 SharedPreferences，首次启动尝试自动读取 ~/.pi/agent/novelai.json 与环境变量)
  Future<AppConfig> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();

    String naiKey = prefs.getString(_keyNovelAiKey) ?? '';
    String prefix = prefs.getString(_keyPrefix) ?? '';
    String suffix = prefs.getString(_keySuffix) ?? '';
    String negative = prefs.getString(_keyNegative) ?? '';
    String modelId = prefs.getString(_keyModel) ?? '';
    String samplerId = prefs.getString(_keySampler) ?? '';
    String scheduleId = prefs.getString(_keyNoiseSchedule) ?? '';
    String resKey = prefs.getString(_keyResolution) ?? '';
    int? customW = prefs.getInt(_keyCustomWidth);
    int? customH = prefs.getInt(_keyCustomHeight);
    int steps = prefs.getInt(_keySteps) ?? 28;
    double scale = prefs.getDouble(_keyScale) ?? 5.0;
    double rescale = prefs.getDouble(_keyCfgRescale) ?? 0.0;
    bool opusFree = prefs.getBool(_keyOpusFreeMode) ?? true;
    bool enableStream = prefs.getBool(_keyEnableStreamPreview) ?? true;
    bool enableTagAc = prefs.getBool(_keyEnableTagAutocomplete) ?? true;
    bool showTagTrans = prefs.getBool(_keyShowTagTranslations) ?? true;
    bool showTagCatColors = prefs.getBool(_keyShowTagCategoryColors) ?? true;
    bool enableTagDictAutoUpdate =
        prefs.getBool(_keyEnableTagDictAutoUpdate) ?? true;
    String saveDir = prefs.getString(_keySaveDir) ?? '';

    // 首次启动且无配置时，尝试自动读取本地 ~/.pi/agent/novelai.json
    if (naiKey.isEmpty) {
      final piConfig = _tryLoadLocalPiNovelAiJson();
      if (piConfig != null) {
        if (piConfig['apiKey'] is String) {
          naiKey = piConfig['apiKey'];
        }
        if (piConfig['prefixPrompt'] is String) {
          prefix = piConfig['prefixPrompt'];
        }
        if (piConfig['suffixPrompt'] is String) {
          suffix = piConfig['suffixPrompt'];
        }
        if (piConfig['negativePrompt'] is String) {
          negative = piConfig['negativePrompt'];
        }
        if (piConfig['defaultModel'] is String) {
          modelId = piConfig['defaultModel'];
        }
        if (piConfig['defaultSampler'] is String) {
          samplerId = piConfig['defaultSampler'];
        }
        if (piConfig['defaultNoiseSchedule'] is String) {
          scheduleId = piConfig['defaultNoiseSchedule'];
        }
        if (piConfig['defaultScale'] is num) {
          scale = (piConfig['defaultScale'] as num).toDouble();
        }
        if (piConfig['defaultCfgRescale'] is num) {
          rescale = (piConfig['defaultCfgRescale'] as num).toDouble();
        }
        if (piConfig['opusFreeMode'] is bool) {
          opusFree = piConfig['opusFreeMode'];
        }
      }
    }

    // 环境变量后备
    if (naiKey.isEmpty) {
      naiKey =
          Platform.environment['NOVELAI_API_KEY'] ??
          Platform.environment['NAI_API_KEY'] ??
          '';
    }

    // 确定默认保存目录
    if (saveDir.isEmpty) {
      saveDir = await _getDefaultSaveDirectory();
    }

    // LLM 多供应商配置加载与平滑迁移
    List<LlmProviderConfig> providers = [];
    final providersJson = prefs.getString(_keyLlmProviders);
    if (providersJson != null && providersJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(providersJson) as List<dynamic>;
        providers = decoded
            .map((e) => LlmProviderConfig.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {}
    }

    // 若无多供应商配置，读取旧单配置并构建初始供应商列表
    if (providers.isEmpty) {
      final legacyBase =
          prefs.getString(_keyLlmBaseUrl) ?? 'https://api.deepseek.com/v1';
      final legacyKey =
          prefs.getString(_keyLlmApiKey) ??
          Platform.environment['DEEPSEEK_API_KEY'] ??
          Platform.environment['OPENAI_API_KEY'] ??
          '';
      final legacyModel = prefs.getString(_keyLlmModel) ?? 'deepseek-chat';
      final legacyTemp = prefs.getDouble(_keyLlmTemperature) ?? 0.7;

      providers = [
        LlmProviderConfig(
          id: 'deepseek',
          name: 'DeepSeek',
          baseUrl: legacyBase,
          protocol: LlmProtocol.openAiChat,
          apiKey: legacyKey,
          activeModelId: legacyModel,
          models: [
            LlmModelConfig(
              id: legacyModel,
              name: legacyModel,
              temperature: legacyTemp,
            ),
            const LlmModelConfig(
              id: 'deepseek-reasoner',
              name: 'DeepSeek R1',
              reasoning: true,
              supportedThinkingLevels: [ThinkingEffort.high],
              temperature: 0.6,
            ),
          ],
        ),
        ...LlmProviderConfig.defaultProviders.where((p) => p.id != 'deepseek'),
      ];
    }

    final activeProviderId =
        prefs.getString(_keyActiveLlmProviderId) ?? providers.first.id;

    // Agent 预设配置加载
    List<AgentPreset> presets = [];
    final presetsJson = prefs.getString(_keyPresets);
    if (presetsJson != null && presetsJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(presetsJson) as List<dynamic>;
        presets = decoded
            .map((e) => AgentPreset.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {}
    }

    if (presets.isEmpty) {
      presets = List.of(BuiltinPresets.all);
    } else {
      // 内置预设以代码定义为唯一事实来源：按 id 用当前出厂定义覆盖磁盘上的
      // 旧副本 (否则新版本新增的工具/参数白名单永远进不了已保存的预设)，
      // 不存在的自动补充；用户自定义预设保持原样，修改内置预设请先复制。
      for (final builtin in BuiltinPresets.all) {
        final idx = presets.indexWhere((p) => p.id == builtin.id);
        if (idx >= 0) {
          presets[idx] = builtin;
        } else {
          presets.add(builtin);
        }
      }
    }

    final activePresetId =
        prefs.getString(_keyActivePresetId) ?? BuiltinPresets.v5Architect.id;

    // 自定义 Skills 加载
    List<Skill> customSkills = [];
    final customSkillsJson = prefs.getString(_keyCustomSkills);
    if (customSkillsJson != null && customSkillsJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(customSkillsJson) as List<dynamic>;
        customSkills = decoded
            .map((e) => Skill.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {}
    }

    // 自定义 Tools 加载
    List<CustomAgentTool> customTools = [];
    final customToolsJson = prefs.getString(_keyCustomTools);
    if (customToolsJson != null && customToolsJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(customToolsJson) as List<dynamic>;
        customTools = decoded
            .map((e) => CustomAgentTool.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {}
    }

    return AppConfig(
      novelAiKey: naiKey,
      defaultModel: modelId.isNotEmpty
          ? NaiModel.fromId(modelId)
          : NaiModel.v5Full,
      defaultSampler: samplerId.isNotEmpty
          ? NaiSampler.fromId(samplerId)
          : NaiSampler.kEuler,
      defaultNoiseSchedule: scheduleId.isNotEmpty
          ? NoiseSchedule.fromId(scheduleId)
          : NoiseSchedule.karras,
      defaultResolution: resKey.isNotEmpty
          ? ResolutionPreset.fromKey(resKey)
          : ResolutionPreset.portrait,
      customWidth: customW ?? 832,
      customHeight: customH ?? 1216,
      defaultSteps: steps,
      defaultScale: scale,
      defaultCfgRescale: rescale,
      opusFreeMode: opusFree,
      enableStreamPreview: enableStream,
      enableTagAutocomplete: enableTagAc,
      showTagTranslations: showTagTrans,
      showTagCategoryColors: showTagCatColors,
      enableTagDictionaryAutoUpdate: enableTagDictAutoUpdate,
      prefixPrompt: prefix,
      suffixPrompt: suffix,
      negativePrompt: negative,
      saveDirectory: saveDir,
      llmProviders: providers,
      activeLlmProviderId: activeProviderId,
      presets: presets,
      activePresetId: activePresetId,
      customSkills: customSkills,
      customTools: customTools,
    );
  }

  /// 保存配置
  Future<void> saveConfig(AppConfig config) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(_keyNovelAiKey, config.novelAiKey);
    await prefs.setString(_keyModel, config.defaultModel.id);
    await prefs.setString(_keySampler, config.defaultSampler.id);
    await prefs.setString(_keyNoiseSchedule, config.defaultNoiseSchedule.id);
    await prefs.setString(_keyResolution, config.defaultResolution.key);
    await prefs.setInt(_keyCustomWidth, config.customWidth);
    await prefs.setInt(_keyCustomHeight, config.customHeight);
    await prefs.setInt(_keySteps, config.defaultSteps);
    await prefs.setDouble(_keyScale, config.defaultScale);
    await prefs.setDouble(_keyCfgRescale, config.defaultCfgRescale);
    await prefs.setBool(_keyOpusFreeMode, config.opusFreeMode);
    await prefs.setBool(_keyEnableStreamPreview, config.enableStreamPreview);
    await prefs.setBool(
      _keyEnableTagAutocomplete,
      config.enableTagAutocomplete,
    );
    await prefs.setBool(_keyShowTagTranslations, config.showTagTranslations);
    await prefs.setBool(
      _keyShowTagCategoryColors,
      config.showTagCategoryColors,
    );
    await prefs.setBool(
      _keyEnableTagDictAutoUpdate,
      config.enableTagDictionaryAutoUpdate,
    );
    await prefs.setString(_keyPrefix, config.prefixPrompt);
    await prefs.setString(_keySuffix, config.suffixPrompt);
    await prefs.setString(_keyNegative, config.negativePrompt);
    await prefs.setString(_keySaveDir, config.saveDirectory);

    // 保存多供应商配置
    final providersJson = jsonEncode(
      config.llmProviders.map((p) => p.toJson()).toList(),
    );
    await prefs.setString(_keyLlmProviders, providersJson);
    await prefs.setString(_keyActiveLlmProviderId, config.activeLlmProviderId);

    // 保存 Agent 预设配置
    final presetsJson = jsonEncode(
      config.presets.map((p) => p.toJson()).toList(),
    );
    await prefs.setString(_keyPresets, presetsJson);
    await prefs.setString(_keyActivePresetId, config.activePresetId);

    // 保存自定义 Skills 与 Tools
    final customSkillsJson = jsonEncode(
      config.customSkills.map((s) => s.toJson()).toList(),
    );
    await prefs.setString(_keyCustomSkills, customSkillsJson);

    final customToolsJson = jsonEncode(
      config.customTools.map((t) => t.toJson()).toList(),
    );
    await prefs.setString(_keyCustomTools, customToolsJson);

    // 兼容保存活跃供应商基础字段
    final active = config.activeLlmProvider;
    await prefs.setString(_keyLlmBaseUrl, active.baseUrl);
    await prefs.setString(_keyLlmApiKey, active.apiKey);
    await prefs.setString(_keyLlmModel, active.model);
    await prefs.setDouble(_keyLlmTemperature, active.temperature);
  }

  /// 加载上次保存的草稿提示词
  Future<String> loadLastPrompt() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLastPrompt) ?? '';
  }

  /// 保存当前草稿提示词
  Future<void> saveLastPrompt(String prompt) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastPrompt, prompt);
  }

  /// 加载固定词缀开关状态
  Future<bool> loadApplyFixedPrompts() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyApplyFixedPrompts) ?? false;
  }

  /// 保存固定词缀开关状态
  Future<void> saveApplyFixedPrompts(bool apply) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyApplyFixedPrompts, apply);
  }

  /// 加载多角色提示词列表
  Future<List<NaiCharacterPrompt>> loadCharacterPrompts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyCharacterPrompts);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(NaiCharacterPrompt.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 保存多角色提示词列表
  Future<void> saveCharacterPrompts(List<NaiCharacterPrompt> characters) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _keyCharacterPrompts,
      jsonEncode(characters.map((c) => c.toJson()).toList()),
    );
  }

  /// 加载全局角色位置模式 (true = AI 自动布局，false = 自定义定位)
  Future<bool> loadCharacterAiPosition() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyCharacterAiPosition) ?? true;
  }

  /// 保存全局角色位置模式
  Future<void> saveCharacterAiPosition(bool aiPosition) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyCharacterAiPosition, aiPosition);
  }

  // --- 页面布局状态持久化 ---

  /// 加载分栏左右宽度
  Future<(double left, double right)> loadSplitWidths({
    double defaultLeft = 320.0,
    double defaultRight = 400.0,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final left = prefs.getDouble(_keySplitLeftWidth) ?? defaultLeft;
    final right = prefs.getDouble(_keySplitRightWidth) ?? defaultRight;
    return (left, right);
  }

  /// 保存分栏左右宽度
  Future<void> saveSplitWidths(double left, double right) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keySplitLeftWidth, left);
    await prefs.setDouble(_keySplitRightWidth, right);
  }

  /// 加载侧边栏激活标签
  Future<String> loadSidebarActiveTab({String defaultTab = 'parameters'}) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keySidebarActiveTab) ?? defaultTab;
  }

  /// 保存侧边栏激活标签
  Future<void> saveSidebarActiveTab(String tab) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySidebarActiveTab, tab);
  }

  /// 加载提示词管理模式 (true: 标签页, false: 垂直堆叠)
  Future<bool> loadPromptTabbedMode({bool defaultMode = false}) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyPromptTabbedMode) ?? defaultMode;
  }

  /// 保存提示词管理模式
  Future<void> savePromptTabbedMode(bool isTabbed) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyPromptTabbedMode, isTabbed);
  }

  /// 加载提示词标签页激活项 (0: Prompt, 1: Undesired Content)
  Future<int> loadPromptActiveTab({int defaultTab = 0}) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyPromptActiveTab) ?? defaultTab;
  }

  /// 保存提示词标签页激活项
  Future<void> savePromptActiveTab(int tab) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyPromptActiveTab, tab);
  }

  /// 加载提示词扩展甲板激活项 (0: Character Prompts, 1: Fixed Affixes)
  Future<int> loadDeckActiveTab({int defaultTab = 0}) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyDeckActiveTab) ?? defaultTab;
  }

  /// 保存提示词扩展甲板激活项
  Future<void> saveDeckActiveTab(int tab) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyDeckActiveTab, tab);
  }

  /// 加载画板历史侧栏展开状态
  Future<bool> loadCanvasHistoryOpen({bool defaultOpen = false}) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyCanvasHistoryOpen) ?? defaultOpen;
  }

  /// 保存画板历史侧栏展开状态
  Future<void> saveCanvasHistoryOpen(bool isOpen) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyCanvasHistoryOpen, isOpen);
  }

  Map<String, dynamic>? _tryLoadLocalPiNovelAiJson() {
    try {
      final home =
          Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
      if (home == null) return null;
      final configPath = p.join(home, '.pi', 'agent', 'novelai.json');
      final file = File(configPath);
      if (file.existsSync()) {
        final content = file.readAsStringSync();
        return jsonDecode(content) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  Future<String> _getDefaultSaveDirectory() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final outputDir = Directory(p.join(dir.path, 'NovelAI_Output'));
      if (!outputDir.existsSync()) {
        outputDir.createSync(recursive: true);
      }
      return outputDir.path;
    } catch (_) {
      return '';
    }
  }
}
