import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/harness/presets/agent_preset.dart';
import '../../core/harness/skills/skills.dart';
import '../../core/harness/tools/agent_tool.dart';
import '../models/novelai_models.dart';
import 'image_storage_directory_service.dart';

/// 主题模式偏好 (跟随系统 / 亮色 / 深色)
///
/// 纯 Dart 枚举，不依赖 Flutter Material 的 [ThemeMode]；
/// 由 UI 层负责映射 (见 ui/core/theme/theme_mode_controller.dart)。
/// 阶段 3 颜色清洗完成前出厂默认锁定亮色，避免半黑半白视觉破损。
enum AppThemeModePreference { system, light, dark }

/// 存储字符串 → 枚举 (未知/缺失值一律回退亮色，保持旧行为)
AppThemeModePreference parseThemeModePreference(String? raw) => switch (raw) {
  'system' => AppThemeModePreference.system,
  'dark' => AppThemeModePreference.dark,
  _ => AppThemeModePreference.light,
};

/// 枚举 → 存储字符串
String themeModePreferenceStorage(AppThemeModePreference mode) =>
    switch (mode) {
      AppThemeModePreference.system => 'system',
      AppThemeModePreference.light => 'light',
      AppThemeModePreference.dark => 'dark',
    };

/// 语言偏好 (跟随系统 / 中文 / English)
///
/// 纯 Dart 枚举，不依赖 Flutter 的 [Locale]；
/// 由 UI 层负责映射 (见 ui/core/locale/app_locale_controller.dart)。
enum AppLocalePreference { system, zh, en }

/// 存储字符串 → 枚举 (未知/缺失值一律回退跟随系统，保持旧行为)
AppLocalePreference parseLocalePreference(String? raw) => switch (raw) {
  'zh' => AppLocalePreference.zh,
  'en' => AppLocalePreference.en,
  _ => AppLocalePreference.system,
};

/// 枚举 → 存储字符串
String localePreferenceStorage(AppLocalePreference locale) => switch (locale) {
  AppLocalePreference.system => 'system',
  AppLocalePreference.zh => 'zh',
  AppLocalePreference.en => 'en',
};

/// 主题强调色来源 (默认 Notion 蓝 / 跟随当前图片自适应 / 手动指定种子色)
///
/// 纯 Dart 枚举；种子色推导与主题注入见 ui/core/theme/md3_accent.dart。
enum AppAccentMode { defaultBlue, adaptive, manual }

/// 存储字符串 → 枚举 (未知/缺失值回退默认蓝，保持旧行为)
AppAccentMode parseAccentMode(String? raw) => switch (raw) {
  'adaptive' => AppAccentMode.adaptive,
  'manual' => AppAccentMode.manual,
  _ => AppAccentMode.defaultBlue,
};

/// 枚举 → 存储字符串
String accentModeStorage(AppAccentMode mode) => switch (mode) {
  AppAccentMode.defaultBlue => 'default',
  AppAccentMode.adaptive => 'adaptive',
  AppAccentMode.manual => 'manual',
};

/// MD3 动态取色方案 (与 material_color_utilities Variant 一一对应)
///
/// tonalSpot 为 Android 12/13 Material You 默认方案。
enum AppAccentVariant {
  tonalSpot,
  vibrant,
  expressive,
  content,
  neutral,
  monochrome,
  rainbow,
  fruitSalad,
}

/// 存储字符串 → 枚举 (未知/缺失值回退 tonalSpot)
AppAccentVariant parseAccentVariant(String? raw) => switch (raw) {
  'vibrant' => AppAccentVariant.vibrant,
  'expressive' => AppAccentVariant.expressive,
  'content' => AppAccentVariant.content,
  'neutral' => AppAccentVariant.neutral,
  'monochrome' => AppAccentVariant.monochrome,
  'rainbow' => AppAccentVariant.rainbow,
  'fruit_salad' => AppAccentVariant.fruitSalad,
  _ => AppAccentVariant.tonalSpot,
};

/// 枚举 → 存储字符串
String accentVariantStorage(AppAccentVariant variant) => switch (variant) {
  AppAccentVariant.tonalSpot => 'tonal_spot',
  AppAccentVariant.vibrant => 'vibrant',
  AppAccentVariant.expressive => 'expressive',
  AppAccentVariant.content => 'content',
  AppAccentVariant.neutral => 'neutral',
  AppAccentVariant.monochrome => 'monochrome',
  AppAccentVariant.rainbow => 'rainbow',
  AppAccentVariant.fruitSalad => 'fruit_salad',
};

/// 种子色存储文本 (#RRGGBB) → ARGB 整型；非法/空文本返回 null
int? parseSeedColorText(String? raw) {
  if (raw == null) return null;
  final hex = raw.startsWith('#') ? raw.substring(1) : raw;
  if (hex.length != 6) return null;
  final rgb = int.tryParse(hex, radix: 16);
  if (rgb == null) return null;
  return 0xFF000000 | rgb;
}

/// ARGB 整型 → 种子色存储文本 (#RRGGBB)；null 返回 null
String? seedColorText(int? argb) {
  if (argb == null) return null;
  return '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

/// 全局配置数据模型
class AppConfig {
  // NovelAI 设置
  final String novelAiKey;

  /// AnySearch 网络搜索 API Key (可选，空 = 匿名访问限流更低)
  final String anySearchApiKey;
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

  /// 主题模式偏好 (跟随系统/亮色/深色)，由 AppThemeModeController 映射到 MaterialApp
  final AppThemeModePreference themeMode;

  /// 主题强调色来源 (默认蓝/跟随图片/手动种子)，由 AppAccentController 映射到主题
  final AppAccentMode accentMode;

  /// MD3 取色方案 (accentMode 非 defaultBlue 时生效)
  final AppAccentVariant accentVariant;

  /// 手动模式下的种子色 (存储为 #RRGGBB 文本，null = 未指定)
  final String? accentSeedColor;

  /// 语言偏好 (跟随系统/中文/English)，由 AppLocaleController 映射到 MaterialApp
  final AppLocalePreference localePreference;

  /// 全局 UI 缩放系数 (浏览器式 Ctrl+=/- 整体缩放)，1.0 = 100%；
  /// 由 AppUiZoomController 在 MaterialApp 根节点 Transform 生效
  final double uiZoom;
  final bool enableStreamPreview;
  final bool enableTagAutocomplete;
  final bool showTagTranslations;
  final bool showTagCategoryColors;
  final bool enableTagDictionaryAutoUpdate;
  final bool enableImagePersistence;
  final int maxPersistentImages;

  /// 自动保存生成图片：开启时生图直接写入本地存储目录；
  /// 关闭时先生成到缓存目录 (无水印)，由用户在画板右下角手动保存
  final bool autoSaveImages;

  final String prefixPrompt;
  final String suffixPrompt;
  final String negativePrompt;
  final String saveDirectory;

  /// 相对于 saveDirectory 的目录/文件名宏模板；空串使用默认命名。
  final String imageSaveTemplate;
  final bool stripMetadata;
  final bool enableWatermark;
  final bool keepOriginalImage;
  final WatermarkConfig watermarkConfig;

  // ComfyUI 模式 (经 PromptToolkit AI Bridge 驱动本地/局域网 ComfyUI 生图)
  /// 是否启用 ComfyUI 模式：开启后生图改走 Bridge，
  /// 质量词/UC 预设拼接与 Token 上限计数全部旁路
  final bool comfyUiEnabled;

  /// ComfyUI 服务地址 (支持局域网地址，方便手机等设备连接)
  final String comfyUiBaseUrl;

  /// 目标节点 ID 覆盖 (空 = 自动取注册表第一个)
  final String comfyUiPromptNodeId;
  final String comfyUiResolutionNodeId;
  final String comfyUiParamsNodeId;

  /// ComfyUI 采样器 (空 = 跟随工作流，不下发；
  /// 可选值实时来自服务器 /object_info，如 euler / dpmpp_2m)
  final String comfyUiSampler;

  /// ComfyUI 噪声调度器 (空 = 跟随工作流，不下发；
  /// 如 normal / karras / exponential)
  final String comfyUiScheduler;

  // LLM 设置 (多供应商配置)
  final List<LlmProviderConfig> llmProviders;
  final String activeLlmProviderId;

  /// AI 整图编辑：绘图模型供应商与模型 ID (独立于对话 LLM，可为空 = 未配置)
  final String imageEditProviderId;
  final String imageEditModelId;

  /// Agent 单次对话最大工具调用轮数 (达到后自动收尾)
  final int agentMaxTurns;
  final bool agentCompactionEnabled;
  final bool agentBackgroundCompaction;
  final String compactionProviderId;
  final String compactionModelId;

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

  /// AI 整图编辑供应商 (未配置或找不到时返回 null)
  LlmProviderConfig? get imageEditProvider {
    if (imageEditProviderId.isEmpty || imageEditModelId.isEmpty) return null;
    final list = llmProviders.isNotEmpty
        ? llmProviders
        : LlmProviderConfig.defaultProviders;
    for (final p in list) {
      if (p.id == imageEditProviderId) return p;
    }
    return null;
  }

  /// AI 整图编辑模型配置 (供应商存在且模型列表里有对应模型时返回)
  LlmModelConfig? get imageEditModel {
    final provider = imageEditProvider;
    if (provider == null) return null;
    for (final m in provider.models) {
      if (m.id == imageEditModelId) return m;
    }
    return null;
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
  double get llmTemperature => activeLlmProvider.activeModel.temperature;

  const AppConfig({
    this.novelAiKey = '',
    this.anySearchApiKey = '',
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
    this.themeMode = AppThemeModePreference.light,
    this.accentMode = AppAccentMode.defaultBlue,
    this.accentVariant = AppAccentVariant.tonalSpot,
    this.accentSeedColor,
    this.localePreference = AppLocalePreference.system,
    this.uiZoom = 1.0,
    this.enableStreamPreview = true,
    this.enableTagAutocomplete = true,
    this.showTagTranslations = true,
    this.showTagCategoryColors = true,
    this.enableTagDictionaryAutoUpdate = true,
    this.enableImagePersistence = true,
    this.maxPersistentImages = 50,
    this.autoSaveImages = false,
    this.prefixPrompt = '',
    this.suffixPrompt = '',
    this.negativePrompt = '',
    this.saveDirectory = '',
    this.imageSaveTemplate = '',
    this.stripMetadata = false,
    this.enableWatermark = false,
    this.keepOriginalImage = false,
    this.watermarkConfig = const WatermarkConfig(),
    this.comfyUiEnabled = false,
    this.comfyUiBaseUrl = 'http://127.0.0.1:8188',
    this.comfyUiPromptNodeId = '',
    this.comfyUiResolutionNodeId = '',
    this.comfyUiParamsNodeId = '',
    this.comfyUiSampler = '',
    this.comfyUiScheduler = '',
    this.llmProviders = const [],
    this.activeLlmProviderId = 'deepseek',
    this.imageEditProviderId = '',
    this.imageEditModelId = '',
    this.agentMaxTurns = 30,
    this.agentCompactionEnabled = true,
    this.agentBackgroundCompaction = true,
    this.compactionProviderId = '',
    this.compactionModelId = '',

    this.presets = const [],
    this.activePresetId = 'v5-architect-preset',
    this.customSkills = const [],
    this.customTools = const [],
  });

  AppConfig copyWith({
    String? novelAiKey,
    String? anySearchApiKey,
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
    AppThemeModePreference? themeMode,
    AppAccentMode? accentMode,
    AppAccentVariant? accentVariant,
    String? accentSeedColor,
    AppLocalePreference? localePreference,
    double? uiZoom,
    bool? enableStreamPreview,
    bool? enableTagAutocomplete,
    bool? showTagTranslations,
    bool? showTagCategoryColors,
    bool? enableTagDictionaryAutoUpdate,
    bool? enableImagePersistence,
    int? maxPersistentImages,
    bool? autoSaveImages,
    String? prefixPrompt,
    String? suffixPrompt,
    String? negativePrompt,
    String? saveDirectory,
    String? imageSaveTemplate,
    bool? stripMetadata,
    bool? enableWatermark,
    bool? keepOriginalImage,
    WatermarkConfig? watermarkConfig,
    bool? comfyUiEnabled,
    String? comfyUiBaseUrl,
    String? comfyUiPromptNodeId,
    String? comfyUiResolutionNodeId,
    String? comfyUiParamsNodeId,
    String? comfyUiSampler,
    String? comfyUiScheduler,
    List<LlmProviderConfig>? llmProviders,
    String? activeLlmProviderId,
    String? imageEditProviderId,
    String? imageEditModelId,
    int? agentMaxTurns,
    bool? agentCompactionEnabled,
    bool? agentBackgroundCompaction,
    String? compactionProviderId,
    String? compactionModelId,

    List<AgentPreset>? presets,
    String? activePresetId,
    List<Skill>? customSkills,
    List<CustomAgentTool>? customTools,
  }) {
    var updatedProviders = llmProviders ?? this.llmProviders;
    var targetActiveId = activeLlmProviderId ?? this.activeLlmProviderId;

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
      themeMode: themeMode ?? this.themeMode,
      accentMode: accentMode ?? this.accentMode,
      accentVariant: accentVariant ?? this.accentVariant,
      accentSeedColor: accentSeedColor ?? this.accentSeedColor,
      localePreference: localePreference ?? this.localePreference,
      uiZoom: uiZoom ?? this.uiZoom,
      enableStreamPreview: enableStreamPreview ?? this.enableStreamPreview,
      enableTagAutocomplete:
          enableTagAutocomplete ?? this.enableTagAutocomplete,
      showTagTranslations: showTagTranslations ?? this.showTagTranslations,
      showTagCategoryColors:
          showTagCategoryColors ?? this.showTagCategoryColors,
      enableTagDictionaryAutoUpdate:
          enableTagDictionaryAutoUpdate ?? this.enableTagDictionaryAutoUpdate,
      enableImagePersistence:
          enableImagePersistence ?? this.enableImagePersistence,
      maxPersistentImages: maxPersistentImages ?? this.maxPersistentImages,
      autoSaveImages: autoSaveImages ?? this.autoSaveImages,
      prefixPrompt: prefixPrompt ?? this.prefixPrompt,
      suffixPrompt: suffixPrompt ?? this.suffixPrompt,
      negativePrompt: negativePrompt ?? this.negativePrompt,
      saveDirectory: saveDirectory ?? this.saveDirectory,
      imageSaveTemplate: imageSaveTemplate ?? this.imageSaveTemplate,
      stripMetadata: stripMetadata ?? this.stripMetadata,
      enableWatermark: enableWatermark ?? this.enableWatermark,
      keepOriginalImage: keepOriginalImage ?? this.keepOriginalImage,
      watermarkConfig: watermarkConfig ?? this.watermarkConfig,
      comfyUiEnabled: comfyUiEnabled ?? this.comfyUiEnabled,
      comfyUiBaseUrl: comfyUiBaseUrl ?? this.comfyUiBaseUrl,
      comfyUiPromptNodeId: comfyUiPromptNodeId ?? this.comfyUiPromptNodeId,
      comfyUiResolutionNodeId:
          comfyUiResolutionNodeId ?? this.comfyUiResolutionNodeId,
      comfyUiParamsNodeId: comfyUiParamsNodeId ?? this.comfyUiParamsNodeId,
      comfyUiSampler: comfyUiSampler ?? this.comfyUiSampler,
      comfyUiScheduler: comfyUiScheduler ?? this.comfyUiScheduler,
      llmProviders: updatedProviders,
      activeLlmProviderId: targetActiveId,
      anySearchApiKey: anySearchApiKey ?? this.anySearchApiKey,
      imageEditProviderId: imageEditProviderId ?? this.imageEditProviderId,
      imageEditModelId: imageEditModelId ?? this.imageEditModelId,
      agentMaxTurns: agentMaxTurns ?? this.agentMaxTurns,
      agentCompactionEnabled:
          agentCompactionEnabled ?? this.agentCompactionEnabled,
      agentBackgroundCompaction:
          agentBackgroundCompaction ?? this.agentBackgroundCompaction,
      compactionProviderId: compactionProviderId ?? this.compactionProviderId,
      compactionModelId: compactionModelId ?? this.compactionModelId,

      presets: presets ?? this.presets,
      activePresetId: activePresetId ?? this.activePresetId,
      customSkills: customSkills ?? this.customSkills,
      customTools: customTools ?? this.customTools,
    );
  }
}

/// 配置持久化与自适应加载服务
class ConfigService {
  ConfigService({ImageStorageDirectoryService? imageStorageDirectoryService})
    : _imageStorageDirectories =
          imageStorageDirectoryService ?? ImageStorageDirectoryService();

  final ImageStorageDirectoryService _imageStorageDirectories;

  /// 启动与设置变更共用：安卓需真实读写探测，失败回退应用文档目录。
  Future<String> resolveImageSaveDirectory(String configuredDirectory) =>
      _imageStorageDirectories.resolve(configuredDirectory);

  static const String _keyNovelAiKey = 'novelai_key';
  static const String _keyAnySearchApiKey = 'anysearch_api_key';
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
  static const String _keyThemeMode = 'novelai_theme_mode';
  static const String _keyAccentMode = 'novelai_accent_mode';
  static const String _keyAccentVariant = 'novelai_accent_variant';
  static const String _keyAccentSeedColor = 'novelai_accent_seed_color';
  static const String _keyLocalePreference = 'novelai_locale_preference';
  static const String _keyUiZoom = 'novelai_ui_zoom';
  static const String _keyEnableStreamPreview = 'novelai_enable_stream_preview';
  static const String _keyEnableTagAutocomplete =
      'novelai_enable_tag_autocomplete';
  static const String _keyShowTagTranslations = 'novelai_show_tag_translations';
  static const String _keyShowTagCategoryColors =
      'novelai_show_tag_category_colors';
  static const String _keyEnableTagDictAutoUpdate =
      'novelai_enable_tag_dictionary_auto_update';
  static const String _keyEnableImagePersistence =
      'novelai_enable_image_persistence';
  static const String _keyMaxPersistentImages = 'novelai_max_persistent_images';
  static const String _keyAutoSaveImages = 'novelai_auto_save_images';
  static const String _keyPrefix = 'novelai_prefix';
  static const String _keySuffix = 'novelai_suffix';
  static const String _keyNegative = 'novelai_negative';
  static const String _keySaveDir = 'novelai_save_dir';
  static const String _keyImageSaveTemplate = 'novelai_image_save_template';
  static const String _keyStripMetadata = 'novelai_strip_metadata';
  static const String _keyEnableWatermark = 'novelai_enable_watermark';
  static const String _keyKeepOriginalImage = 'novelai_keep_original_image';
  static const String _keyWatermarkConfig = 'novelai_watermark_config';
  // 完整工作台快照独立于设置页默认值；旧散项仅用于首次迁移。
  static const String _keyStudioParameters = 'novelai_studio_parameters';
  static const String _keyLastPrompt = 'novelai_last_prompt';
  static const String _keyApplyFixedPrompts = 'novelai_apply_fixed_prompts';
  static const String _keyCharacterPrompts = 'novelai_character_prompts';
  static const String _keyCharacterAiPosition = 'novelai_character_ai_position';
  static const String _keySeedMode = 'novelai_seed_mode';
  static const String _keySeedTiming = 'novelai_seed_timing';

  // ComfyUI 模式持久化 Keys
  static const String _keyComfyUiEnabled = 'novelai_comfyui_enabled';
  static const String _keyComfyUiBaseUrl = 'novelai_comfyui_base_url';
  static const String _keyComfyUiPromptNodeId =
      'novelai_comfyui_prompt_node_id';
  static const String _keyComfyUiResolutionNodeId =
      'novelai_comfyui_resolution_node_id';
  static const String _keyComfyUiParamsNodeId =
      'novelai_comfyui_params_node_id';
  static const String _keyComfyUiSampler = 'novelai_comfyui_sampler';
  static const String _keyComfyUiScheduler = 'novelai_comfyui_scheduler';

  // 页面布局持久化 Keys
  static const String _keySplitLeftWidth = 'novelai_layout_split_left_width';
  static const String _keySplitRightWidth = 'novelai_layout_split_right_width';
  static const String _keySidebarActiveTab =
      'novelai_layout_sidebar_active_tab';
  static const String _keyPromptTabbedMode =
      'novelai_layout_prompt_tabbed_mode';
  static const String _keyPromptActiveTab = 'novelai_layout_prompt_active_tab';
  static const String _keyDeckActiveTab = 'novelai_layout_deck_active_tab';
  static const String _keyCanvasHistoryOpen =
      'novelai_layout_canvas_history_open';

  // 提示词输入框高度持久化 Keys
  static const String _keyPromptHeightStacked =
      'novelai_layout_prompt_height_stacked';
  static const String _keyNegativeHeightStacked =
      'novelai_layout_negative_height_stacked';
  static const String _keyPromptHeightTabbed =
      'novelai_layout_prompt_height_tabbed';
  static const String _keyNegativeHeightTabbed =
      'novelai_layout_negative_height_tabbed';
  static const String _keyPrefixHeight = 'novelai_layout_prefix_height';
  static const String _keySuffixHeight = 'novelai_layout_suffix_height';
  static const String _keyCharacterPromptHeight =
      'novelai_layout_char_prompt_height';
  static const String _keyCharacterNegativeHeight =
      'novelai_layout_char_negative_height';

  // Agent 对话草稿输入持久化 Key
  static const String _keyChatDraft = 'novelai_chat_draft';

  // 窗口状态持久化 Keys
  static const String _keyWindowWidth = 'novelai_window_width';
  static const String _keyWindowHeight = 'novelai_window_height';
  static const String _keyWindowPosX = 'novelai_window_pos_x';
  static const String _keyWindowPosY = 'novelai_window_pos_y';
  static const String _keyWindowMaximized = 'novelai_window_maximized';

  static const String _keyLlmBaseUrl = 'llm_base_url';
  static const String _keyLlmApiKey = 'llm_api_key';
  static const String _keyLlmModel = 'llm_model';
  static const String _keyLlmTemperature = 'llm_temperature';
  static const String _keyLlmProviders = 'llm_providers_json';
  static const String _keyActiveLlmProviderId = 'active_llm_provider_id';
  static const String _keyImageEditProviderId = 'image_edit_provider_id';
  static const String _keyImageEditModelId = 'image_edit_model_id';
  static const String _keyAgentMaxTurns = 'novelai_agent_max_turns';
  static const String _keyAgentCompactionEnabled =
      'novelai_agent_compaction_enabled';
  static const String _keyAgentBackgroundCompaction =
      'novelai_agent_background_compaction';
  static const String _keyCompactionProviderId =
      'novelai_compaction_provider_id';
  static const String _keyCompactionModelId = 'novelai_compaction_model_id';
  static const String _keyPresets = 'agent_presets_json';
  static const String _keyActivePresetId = 'active_preset_id';
  static const String _keyCustomSkills = 'agent_custom_skills_json';
  static const String _keyCustomTools = 'agent_custom_tools_json';

  /// 加载配置 (优先 SharedPreferences，首次启动尝试自动读取 ~/.pi/agent/novelai.json 与环境变量)
  Future<AppConfig> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();

    String naiKey = prefs.getString(_keyNovelAiKey) ?? '';
    final String anySearchKey = prefs.getString(_keyAnySearchApiKey) ?? '';
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
    final themeMode = parseThemeModePreference(prefs.getString(_keyThemeMode));
    final accentMode = parseAccentMode(prefs.getString(_keyAccentMode));
    final accentVariant = parseAccentVariant(
      prefs.getString(_keyAccentVariant),
    );
    final accentSeedColor = prefs.getString(_keyAccentSeedColor);
    final localePref = parseLocalePreference(
      prefs.getString(_keyLocalePreference),
    );
    final uiZoom = clampUiZoom(prefs.getDouble(_keyUiZoom) ?? 1.0);
    bool enableStream = prefs.getBool(_keyEnableStreamPreview) ?? true;
    bool enableTagAc = prefs.getBool(_keyEnableTagAutocomplete) ?? true;
    bool showTagTrans = prefs.getBool(_keyShowTagTranslations) ?? true;
    bool showTagCatColors = prefs.getBool(_keyShowTagCategoryColors) ?? true;
    bool enableTagDictAutoUpdate =
        prefs.getBool(_keyEnableTagDictAutoUpdate) ?? true;
    bool enableImgPersist = prefs.getBool(_keyEnableImagePersistence) ?? true;
    int maxPersistImgs = prefs.getInt(_keyMaxPersistentImages) ?? 50;
    bool autoSaveImgs = prefs.getBool(_keyAutoSaveImages) ?? false;
    String saveDir = prefs.getString(_keySaveDir) ?? '';
    bool stripMeta = prefs.getBool(_keyStripMetadata) ?? false;
    bool enableWm = prefs.getBool(_keyEnableWatermark) ?? false;
    bool keepOrig = prefs.getBool(_keyKeepOriginalImage) ?? false;

    WatermarkConfig wmConfig = const WatermarkConfig();
    final wmConfigJson = prefs.getString(_keyWatermarkConfig);
    if (wmConfigJson != null && wmConfigJson.isNotEmpty) {
      try {
        wmConfig = WatermarkConfig.fromJson(jsonDecode(wmConfigJson));
        if (wmConfig.imagePath != null && wmConfig.imagePath!.isNotEmpty) {
          final f = File(wmConfig.imagePath!);
          if (f.existsSync()) {
            wmConfig = wmConfig.copyWith(imageBytes: f.readAsBytesSync());
          }
        }
      } catch (_) {}
    }

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

    // 修复安卓旧版本选中的不可写公共目录；将修正路径落盘，重启保持一致。
    final resolvedSaveDir = await resolveImageSaveDirectory(saveDir);
    if (resolvedSaveDir != saveDir) {
      saveDir = resolvedSaveDir;
      await prefs.setString(_keySaveDir, saveDir);
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
      final legacyTemp = prefs.getDouble(_keyLlmTemperature) ?? 1.0;

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

    // AI 整图编辑独立供应商与模型 (空 = 未配置)
    final imageEditProviderId = prefs.getString(_keyImageEditProviderId) ?? '';
    final imageEditModelId = prefs.getString(_keyImageEditModelId) ?? '';

    // Agent 单次对话最大工具轮数 (钳制在 1..100 防止脏数据)
    final storedMaxTurns = prefs.getInt(_keyAgentMaxTurns) ?? 30;
    final agentMaxTurns = storedMaxTurns.clamp(1, 100);

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

    // ComfyUI 模式配置加载
    final bool comfyEnabled = prefs.getBool(_keyComfyUiEnabled) ?? false;
    final String comfyBaseUrl =
        prefs.getString(_keyComfyUiBaseUrl) ?? 'http://127.0.0.1:8188';
    final String comfyPromptNodeId =
        prefs.getString(_keyComfyUiPromptNodeId) ?? '';
    final String comfyResolutionNodeId =
        prefs.getString(_keyComfyUiResolutionNodeId) ?? '';
    final String comfyParamsNodeId =
        prefs.getString(_keyComfyUiParamsNodeId) ?? '';
    final String comfySampler = prefs.getString(_keyComfyUiSampler) ?? '';
    final String comfyScheduler = prefs.getString(_keyComfyUiScheduler) ?? '';

    return AppConfig(
      novelAiKey: naiKey,
      anySearchApiKey: anySearchKey,
      imageSaveTemplate: prefs.getString(_keyImageSaveTemplate) ?? '',
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
      themeMode: themeMode,
      accentMode: accentMode,
      accentVariant: accentVariant,
      accentSeedColor: accentSeedColor,
      localePreference: localePref,
      uiZoom: uiZoom,
      enableStreamPreview: enableStream,
      enableTagAutocomplete: enableTagAc,
      showTagTranslations: showTagTrans,
      showTagCategoryColors: showTagCatColors,
      enableTagDictionaryAutoUpdate: enableTagDictAutoUpdate,
      enableImagePersistence: enableImgPersist,
      maxPersistentImages: maxPersistImgs,
      autoSaveImages: autoSaveImgs,
      prefixPrompt: prefix,
      suffixPrompt: suffix,
      negativePrompt: negative,
      saveDirectory: saveDir,
      stripMetadata: stripMeta,
      enableWatermark: enableWm,
      keepOriginalImage: keepOrig,
      watermarkConfig: wmConfig,
      comfyUiEnabled: comfyEnabled,
      comfyUiBaseUrl: comfyBaseUrl,
      comfyUiPromptNodeId: comfyPromptNodeId,
      comfyUiResolutionNodeId: comfyResolutionNodeId,
      comfyUiParamsNodeId: comfyParamsNodeId,
      comfyUiSampler: comfySampler,
      comfyUiScheduler: comfyScheduler,
      llmProviders: providers,
      activeLlmProviderId: activeProviderId,
      imageEditProviderId: imageEditProviderId,
      imageEditModelId: imageEditModelId,
      agentMaxTurns: agentMaxTurns,
      agentCompactionEnabled: prefs.getBool(_keyAgentCompactionEnabled) ?? true,
      agentBackgroundCompaction:
          prefs.getBool(_keyAgentBackgroundCompaction) ?? true,
      compactionProviderId: prefs.getString(_keyCompactionProviderId) ?? '',
      compactionModelId: prefs.getString(_keyCompactionModelId) ?? '',

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
    await prefs.setString(_keyAnySearchApiKey, config.anySearchApiKey);
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
    await prefs.setString(
      _keyThemeMode,
      themeModePreferenceStorage(config.themeMode),
    );
    await prefs.setString(_keyAccentMode, accentModeStorage(config.accentMode));
    await prefs.setString(
      _keyAccentVariant,
      accentVariantStorage(config.accentVariant),
    );
    if (config.accentSeedColor == null) {
      await prefs.remove(_keyAccentSeedColor);
    } else {
      await prefs.setString(_keyAccentSeedColor, config.accentSeedColor!);
    }
    await prefs.setString(
      _keyLocalePreference,
      localePreferenceStorage(config.localePreference),
    );
    await prefs.setDouble(_keyUiZoom, clampUiZoom(config.uiZoom));
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
    await prefs.setBool(
      _keyEnableImagePersistence,
      config.enableImagePersistence,
    );
    await prefs.setInt(_keyMaxPersistentImages, config.maxPersistentImages);
    await prefs.setBool(_keyAutoSaveImages, config.autoSaveImages);
    await prefs.setString(_keyPrefix, config.prefixPrompt);
    await prefs.setString(_keySuffix, config.suffixPrompt);
    await prefs.setString(_keyNegative, config.negativePrompt);
    await prefs.setString(_keySaveDir, config.saveDirectory);
    await prefs.setString(_keyImageSaveTemplate, config.imageSaveTemplate);
    await prefs.setBool(_keyStripMetadata, config.stripMetadata);
    await prefs.setBool(_keyEnableWatermark, config.enableWatermark);
    await prefs.setBool(_keyKeepOriginalImage, config.keepOriginalImage);
    await prefs.setString(
      _keyWatermarkConfig,
      jsonEncode(config.watermarkConfig.toJson()),
    );

    // 保存 ComfyUI 模式配置
    await prefs.setBool(_keyComfyUiEnabled, config.comfyUiEnabled);
    await prefs.setString(_keyComfyUiBaseUrl, config.comfyUiBaseUrl);
    await prefs.setString(_keyComfyUiPromptNodeId, config.comfyUiPromptNodeId);
    await prefs.setString(
      _keyComfyUiResolutionNodeId,
      config.comfyUiResolutionNodeId,
    );
    await prefs.setString(_keyComfyUiParamsNodeId, config.comfyUiParamsNodeId);
    await prefs.setString(_keyComfyUiSampler, config.comfyUiSampler);
    await prefs.setString(_keyComfyUiScheduler, config.comfyUiScheduler);

    // 保存多供应商配置
    final providersJson = jsonEncode(
      config.llmProviders.map((p) => p.toJson()).toList(),
    );
    await prefs.setString(_keyLlmProviders, providersJson);
    await prefs.setString(_keyActiveLlmProviderId, config.activeLlmProviderId);
    await prefs.setString(_keyImageEditProviderId, config.imageEditProviderId);
    await prefs.setString(_keyImageEditModelId, config.imageEditModelId);
    await prefs.setInt(_keyAgentMaxTurns, config.agentMaxTurns.clamp(1, 100));
    await prefs.setBool(
      _keyAgentCompactionEnabled,
      config.agentCompactionEnabled,
    );
    await prefs.setBool(
      _keyAgentBackgroundCompaction,
      config.agentBackgroundCompaction,
    );
    await prefs.setString(
      _keyCompactionProviderId,
      config.compactionProviderId,
    );
    await prefs.setString(_keyCompactionModelId, config.compactionModelId);

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
    await prefs.setString(_keyLlmModel, active.activeModel.id);
    await prefs.setDouble(_keyLlmTemperature, active.activeModel.temperature);
  }

  /// 恢复完整工作台参数。旧版本散项由调用方组成 fallback；缺失字段也沿用它。
  /// 修复只恢复可复用设置，不恢复绑定旧图片的选区、笔迹和蒙版包围盒。
  Future<({NaiGenerationParams generation, InpaintParams inpaint})>
  loadStudioParameters(NaiGenerationParams fallback) async {
    var generation = fallback;
    var inpaint = const InpaintParams();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.get(_keyStudioParameters);
    if (raw is! String || raw.isEmpty) {
      return (generation: generation, inpaint: inpaint);
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final savedGeneration = decoded['generation'];
        if (savedGeneration is Map<String, dynamic>) {
          try {
            generation = NaiGenerationParams.fromJson({
              ...fallback.toJson(),
              ...savedGeneration,
            });
          } catch (_) {
            // 损坏的生图快照不影响修复设置恢复。
          }
        }
        final savedInpaint = decoded['inpaint'];
        if (savedInpaint is Map<String, dynamic>) {
          inpaint = InpaintParams.fromJson({
            ...savedInpaint,
            'selectionRect': null,
            'brushStrokes': const [],
            'maskBounds': null,
          });
        }
      }
    } catch (_) {
      // 旧数据损坏或类型不匹配时回退，不阻塞工作台启动。
    }
    return (generation: generation, inpaint: inpaint);
  }

  /// 一次写入完整快照，避免多项异步保存只落盘一半。
  Future<void> saveStudioParameters(
    NaiGenerationParams generation,
    InpaintParams inpaint,
  ) async {
    final encoded = jsonEncode({
      'generation': generation.toJson(),
      'inpaint': inpaint
          .copyWith(
            clearSelectionRect: true,
            clearBrushStrokes: true,
            clearMaskBounds: true,
          )
          .toJson(),
    });
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(_keyStudioParameters, encoded)) {
      throw const FileSystemException('工作台参数保存失败');
    }
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

  /// 加载种子模式 (random, increase, fixed)
  Future<NaiSeedMode> loadSeedMode() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(_keySeedMode);
    return NaiSeedMode.fromId(str);
  }

  /// 保存种子模式
  Future<void> saveSeedMode(NaiSeedMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySeedMode, mode.id);
  }

  /// 加载种子生成控制时机 (before, after)
  Future<NaiSeedTiming> loadSeedTiming() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(_keySeedTiming);
    return NaiSeedTiming.fromId(str);
  }

  /// 保存种子生成控制时机
  Future<void> saveSeedTiming(NaiSeedTiming timing) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySeedTiming, timing.id);
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
  /// UI 缩放安全档位：钳到合法范围并防御 NaN/无穷 (损坏的持久化值回退 1.0)
  static double clampUiZoom(double value) {
    if (value.isNaN || value.isInfinite) return 1.0;
    return value.clamp(minUiZoom, maxUiZoom).toDouble();
  }

  /// UI 缩放合法范围 (80% ~ 175%)，与 AppUiZoomController 共用的单一事实源
  static const double minUiZoom = 0.8;
  static const double maxUiZoom = 1.75;

  /// 移动端首次启动的舒适缩放档位 (触控目标更易命中，仅作为初始种子)
  static const double mobileDefaultUiZoom = 1.25;

  /// 窗口最小可用尺寸单一事实源：`main.dart` 的 minimumSize 与窗口状态钳制共用，
  /// 两者必须一致，否则用户缩到小窗口后重启会被旧下限弹回大尺寸。
  static const double minWindowWidth = 360.0;
  static const double minWindowHeight = 500.0;

  /// 是否已存在用户显式设置的 UI 缩放 (用于移动端仅首次写入默认档位)
  Future<bool> hasStoredUiZoom() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_keyUiZoom);
  }

  Future<void> saveSplitWidths(double left, double right) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keySplitLeftWidth, left);
    await prefs.setDouble(_keySplitRightWidth, right);
  }

  /// 快捷键即时调整 UI 缩放时的单字段落盘 (不整包重写 config)
  Future<void> saveUiZoom(double zoom) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyUiZoom, clampUiZoom(zoom));
  }

  /// 加载侧边栏激活标签
  Future<String> loadSidebarActiveTab({
    String defaultTab = 'parameters',
  }) async {
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

  /// 加载提示词输入框高度
  Future<
    ({
      double promptStacked,
      double negativeStacked,
      double promptTabbed,
      double negativeTabbed,
      double prefix,
      double suffix,
      double characterPrompt,
      double characterNegative,
    })
  >
  loadPromptFieldHeights({
    double defaultPromptStacked = 116.0,
    double defaultNegativeStacked = 92.0,
    double defaultPromptTabbed = 212.0,
    double defaultNegativeTabbed = 212.0,
    double defaultPrefix = 88.0,
    double defaultSuffix = 64.0,
    double defaultCharacterPrompt = 72.0,
    double defaultCharacterNegative = 56.0,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    return (
      promptStacked:
          prefs.getDouble(_keyPromptHeightStacked) ?? defaultPromptStacked,
      negativeStacked:
          prefs.getDouble(_keyNegativeHeightStacked) ?? defaultNegativeStacked,
      promptTabbed:
          prefs.getDouble(_keyPromptHeightTabbed) ?? defaultPromptTabbed,
      negativeTabbed:
          prefs.getDouble(_keyNegativeHeightTabbed) ?? defaultNegativeTabbed,
      prefix: prefs.getDouble(_keyPrefixHeight) ?? defaultPrefix,
      suffix: prefs.getDouble(_keySuffixHeight) ?? defaultSuffix,
      characterPrompt:
          prefs.getDouble(_keyCharacterPromptHeight) ?? defaultCharacterPrompt,
      characterNegative:
          prefs.getDouble(_keyCharacterNegativeHeight) ??
          defaultCharacterNegative,
    );
  }

  /// 保存提示词输入框高度
  Future<void> savePromptFieldHeights({
    double? promptStacked,
    double? negativeStacked,
    double? promptTabbed,
    double? negativeTabbed,
    double? prefix,
    double? suffix,
    double? characterPrompt,
    double? characterNegative,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (promptStacked != null) {
      await prefs.setDouble(_keyPromptHeightStacked, promptStacked);
    }
    if (negativeStacked != null) {
      await prefs.setDouble(_keyNegativeHeightStacked, negativeStacked);
    }
    if (promptTabbed != null) {
      await prefs.setDouble(_keyPromptHeightTabbed, promptTabbed);
    }
    if (negativeTabbed != null) {
      await prefs.setDouble(_keyNegativeHeightTabbed, negativeTabbed);
    }
    if (prefix != null) {
      await prefs.setDouble(_keyPrefixHeight, prefix);
    }
    if (suffix != null) {
      await prefs.setDouble(_keySuffixHeight, suffix);
    }
    if (characterPrompt != null) {
      await prefs.setDouble(_keyCharacterPromptHeight, characterPrompt);
    }
    if (characterNegative != null) {
      await prefs.setDouble(_keyCharacterNegativeHeight, characterNegative);
    }
  }

  /// 加载 Agent 对话草稿输入文本
  Future<String> loadChatDraft() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyChatDraft) ?? '';
  }

  /// 保存 Agent 对话草稿输入文本
  Future<void> saveChatDraft(String draft) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyChatDraft, draft);
  }

  // --- 桌面窗口状态持久化 ---

  /// 加载窗口状态 (尺寸、位置、是否最大化)
  Future<
    ({
      double width,
      double height,
      double? posX,
      double? posY,
      bool isMaximized,
    })
  >
  loadWindowState({
    double defaultWidth = 1380.0,
    double defaultHeight = 860.0,
    double minWidth = minWindowWidth,
    double minHeight = minWindowHeight,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final w = prefs.getDouble(_keyWindowWidth) ?? defaultWidth;
    final h = prefs.getDouble(_keyWindowHeight) ?? defaultHeight;
    final posX = prefs.getDouble(_keyWindowPosX);
    final posY = prefs.getDouble(_keyWindowPosY);
    final isMaximized = prefs.getBool(_keyWindowMaximized) ?? false;

    final clampedW = w < minWidth ? minWidth : w;
    final clampedH = h < minHeight ? minHeight : h;

    return (
      width: clampedW,
      height: clampedH,
      posX: posX,
      posY: posY,
      isMaximized: isMaximized,
    );
  }

  /// 保存窗口正常尺寸与位置 (非最大化状态下)
  Future<void> saveWindowState({
    required double width,
    required double height,
    double? posX,
    double? posY,
    bool isMaximized = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyWindowWidth, width);
    await prefs.setDouble(_keyWindowHeight, height);
    if (posX != null) {
      await prefs.setDouble(_keyWindowPosX, posX);
    }
    if (posY != null) {
      await prefs.setDouble(_keyWindowPosY, posY);
    }
    await prefs.setBool(_keyWindowMaximized, isMaximized);
  }

  /// 保存窗口最大化状态
  Future<void> saveWindowMaximized(bool isMaximized) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyWindowMaximized, isMaximized);
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
}
