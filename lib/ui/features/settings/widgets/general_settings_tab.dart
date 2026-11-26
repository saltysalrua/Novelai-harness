import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../data/models/prompt_library_sync_models.dart';
import '../../../../data/services/config_service.dart';
import '../../../../data/models/nai_generation_params.dart';
import '../../../../data/services/image_save_path_service.dart';
import '../../../../data/services/media_store_service.dart';
import '../../../../data/services/prompt_library_sync_service.dart';
import '../../../../data/services/tag_dictionary_service.dart';
import '../../../../data/services/tag_dictionary_update_service.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../core/context_l10n.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/md3_accent.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_action_button.dart';
import '../../../core/widgets/app_color_picker_dialog.dart';
import '../../../core/widgets/app_dropdown.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../../core/widgets/app_section_header.dart';
import '../../../core/widgets/app_setting_tile.dart';
import '../../../core/widgets/app_transitions.dart';
import '../../../core/widgets/smooth_scroll_controller.dart';
import 'settings_shared.dart';
import 'image_save_template_settings.dart';

/// General 页草稿状态 (父级 SettingsDialog 持有，保存时统一聚合)
class GeneralSettingsDraft {
  GeneralSettingsDraft(AppConfig config, {this.onChanged})
    : naiKeyController = TextEditingController(text: config.novelAiKey),
      anySearchKeyController = TextEditingController(
        text: config.anySearchApiKey,
      ),
      saveDirController = TextEditingController(text: config.saveDirectory),
      saveTemplateController = TextEditingController(
        text: config.imageSaveTemplate,
      ),
      _savePreviewContext = ImageSaveContext(
        params: NaiGenerationParams(
          prompt: 'sample',
          model: config.defaultModel,
          width: config.customWidth,
          height: config.customHeight,
          steps: config.defaultSteps,
          scale: config.defaultScale,
          sampler: config.defaultSampler,
          noiseSchedule: config.defaultNoiseSchedule,
        ),
        createdAt: DateTime.now(),
        seed: 123456,
      ),
      comfyBaseUrlController = TextEditingController(
        text: config.comfyUiBaseUrl,
      ),
      comfyPromptNodeController = TextEditingController(
        text: config.comfyUiPromptNodeId,
      ),
      comfyResolutionNodeController = TextEditingController(
        text: config.comfyUiResolutionNodeId,
      ),
      comfyParamsNodeController = TextEditingController(
        text: config.comfyUiParamsNodeId,
      ),
      promptSyncEndpointController = TextEditingController(
        text: config.promptSyncEndpoint,
      ),
      promptSyncTokenController = TextEditingController(
        text: config.promptSyncToken,
      ),
      promptSyncNamespaceController = TextEditingController(
        text: config.promptSyncNamespace,
      ),
      promptSyncAutoEnabled = config.promptSyncAutoEnabled,
      promptSyncAutoIntervalMinutes = PromptLibrarySyncConfig(
        autoSyncIntervalMinutes: config.promptSyncAutoIntervalMinutes,
      ).normalizedAutoSyncIntervalMinutes,
      opusFreeMode = config.opusFreeMode,
      themeMode = config.themeMode,
      accentMode = config.accentMode,
      accentVariant = config.accentVariant,
      accentSeedColor = config.accentSeedColor,
      backgroundMode = config.backgroundMode,
      customLightBackgroundColor = config.customLightBackgroundColor,
      customDarkBackgroundColor = config.customDarkBackgroundColor,
      localePreference = config.localePreference,
      uiZoom = config.uiZoom,
      maxFrameRate = config.maxFrameRate,
      enableStreamPreview = config.enableStreamPreview,
      enableTagAutocomplete = config.enableTagAutocomplete,
      showTagTranslations = config.showTagTranslations,
      showTagCategoryColors = config.showTagCategoryColors,
      enableTagDictionaryAutoUpdate = config.enableTagDictionaryAutoUpdate,
      enableImagePersistence = config.enableImagePersistence,
      maxPersistentImages = config.maxPersistentImages,
      autoSaveImages = config.autoSaveImages,
      androidGalleryExport = config.androidGalleryExport,
      androidExportTreeUri = config.androidExportTreeUri,
      androidExportFolderName = '',
      comfyUiEnabled = config.comfyUiEnabled,
      rtxUpscaleScale = config.rtxUpscaleScale {
    for (final controller in _textControllers) {
      controller.addListener(notifyChanged);
    }
  }

  final VoidCallback? onChanged;

  void notifyChanged() => onChanged?.call();

  List<TextEditingController> get _textControllers => [
    naiKeyController,
    anySearchKeyController,
    saveDirController,
    saveTemplateController,
    comfyBaseUrlController,
    comfyPromptNodeController,
    comfyResolutionNodeController,
    comfyParamsNodeController,
    promptSyncEndpointController,
    promptSyncTokenController,
    promptSyncNamespaceController,
  ];

  final TextEditingController naiKeyController;

  /// AnySearch 网络搜索 API Key (可选，空 = 匿名访问)
  final TextEditingController anySearchKeyController;
  final TextEditingController saveDirController;
  final TextEditingController saveTemplateController;
  final ImageSaveContext _savePreviewContext;

  ImageSaveTemplateError? get saveTemplateError =>
      ImageSavePathService.validate(saveTemplateController.text);

  String get saveTemplatePreview => ImageSavePathService.resolve(
    saveTemplateController.text,
    _savePreviewContext,
  );

  void insertSaveMacro(String macro) {
    if (macro.isEmpty) return;
    final value = saveTemplateController.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    saveTemplateController.value = TextEditingValue(
      text: value.text.replaceRange(start, end, '{$macro}'),
      selection: TextSelection.collapsed(offset: start + macro.length + 2),
    );
  }

  bool opusFreeMode;

  /// ComfyUI 模式：服务地址与目标节点 ID (保存时由 SettingsDialog 聚合)
  final TextEditingController comfyBaseUrlController;
  final TextEditingController comfyPromptNodeController;
  final TextEditingController comfyResolutionNodeController;
  final TextEditingController comfyParamsNodeController;
  final TextEditingController promptSyncEndpointController;
  final TextEditingController promptSyncTokenController;
  final TextEditingController promptSyncNamespaceController;
  bool promptSyncAutoEnabled;
  int promptSyncAutoIntervalMinutes;
  bool comfyUiEnabled;
  int rtxUpscaleScale;

  /// 主题模式偏好 (跟随系统/亮色/深色)，保存时由 SettingsDialog 聚合进 AppConfig
  AppThemeModePreference themeMode;

  /// 主题强调色来源 (默认蓝/跟随图片/手动种子)，保存时聚合进 AppConfig
  AppAccentMode accentMode;

  /// MD3 取色方案 (强调色非默认时生效)，保存时聚合进 AppConfig
  AppAccentVariant accentVariant;

  /// 手动模式种子色 (#RRGGBB 文本，null = 未指定)，保存时聚合进 AppConfig
  String? accentSeedColor;

  /// 背景色来源 (默认 Notion / 跟随强调色 / 自定义)，保存时聚合进 AppConfig
  AppBackgroundMode backgroundMode;

  /// 自定义亮色模式背景色 (#RRGGBB，null = 默认暖纸)
  String? customLightBackgroundColor;

  /// 自定义深色模式背景色 (#RRGGBB，null = 默认暗灰)
  String? customDarkBackgroundColor;

  /// 语言偏好 (跟随系统/中文/English)，保存时由 SettingsDialog 聚合进 AppConfig
  AppLocalePreference localePreference;

  /// 全局 UI 缩放 (浏览器式整体缩放)，保存时聚合进 AppConfig
  double uiZoom;

  /// 最大渲染帧率上限 (`0` = 不限制)，保存时聚合进 AppConfig
  int maxFrameRate;
  bool enableStreamPreview;
  bool enableTagAutocomplete;
  bool showTagTranslations;
  bool showTagCategoryColors;
  bool enableTagDictionaryAutoUpdate;
  bool enableImagePersistence;
  int maxPersistentImages;
  bool autoSaveImages;

  /// 安卓专用：自动保存的成品同步写入公共图片库 (MediaStore Pictures/NovelAI)
  bool androidGalleryExport;

  /// 安卓自选导出目录 SAF 树 URI (空 = 未选择，默认 Pictures/NovelAI)
  String androidExportTreeUri;

  /// 自选目录显示名 (选择器返回后填充，不入库、不持久化)
  String androidExportFolderName;

  void dispose() {
    for (final controller in _textControllers) {
      controller.removeListener(notifyChanged);
      controller.dispose();
    }
  }
}

/// General 页：主题模式、语言、NovelAI 服务凭证、本地存储、标签补全与保护开关
///
/// 阶段 3 垂直切片：旧 SettingsCard/SettingsDropdown/SettingsActionButton
/// 全部替换为原子组件 (AppSettingTile + AppDropdown + AppActionButton)。
///
/// 阶段 4A 多语言试点页：全部静态文案经 AppLocalizations 取词；
/// 词库更新服务的运行时状态消息 (阶段/结果文本) 属数据层产物，
/// 按 4A 边界决策原样透传，不在本批翻译。
class GeneralSettingsTab extends StatefulWidget {
  final GeneralSettingsDraft draft;

  const GeneralSettingsTab({super.key, required this.draft});

  @override
  State<GeneralSettingsTab> createState() => _GeneralSettingsTabState();
}

class _GeneralSettingsTabState extends State<GeneralSettingsTab> {
  GeneralSettingsDraft get _draft => widget.draft;
  late final SmoothWheelScrollController _scrollController =
      SmoothWheelScrollController();

  TagDictMeta? _dictMeta;
  bool _dictUpdating = false;
  String _dictStatus = '';
  bool _syncTesting = false;
  String _syncTestMessage = '';
  bool _syncTestOk = false;

  @override
  void initState() {
    super.initState();
    _refreshDictInfo();
    _refreshExportFolderName();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 启动时校验已选导出目录的授权与显示名 (授权被撤销则清空展示)。
  Future<void> _refreshExportFolderName() async {
    final mediaStore = MediaStoreService.instance;
    if (!mediaStore.isSupported || _draft.androidExportTreeUri.isEmpty) {
      return;
    }
    try {
      final info = await mediaStore.verifyExportDirectory(
        _draft.androidExportTreeUri,
      );
      if (!mounted) return;
      setState(() {
        _draft.androidExportFolderName = info?.name ?? '';
        if (info == null) _draft.androidExportTreeUri = '';
      });
    } catch (_) {
      // 校验失败不阻塞设置页；写入时原生侧会再火报错并回退默认图库
    }
  }

  void _mutateDraft(VoidCallback fn) {
    setState(fn);
    _draft.notifyChanged();
  }

  /// 唤起安卓系统目录选择器 (SAF)，选中后持久化读写授权。
  Future<void> _pickExportFolder() async {
    final mediaStore = MediaStoreService.instance;
    if (!mediaStore.isSupported) return;
    try {
      final info = await mediaStore.pickExportDirectory();
      if (!mounted || info == null) return;
      _mutateDraft(() {
        _draft.androidExportTreeUri = info.uri;
        _draft.androidExportFolderName = info.name;
      });
    } on MediaStoreException {
      if (mounted) {
        setState(() => _draft.androidExportFolderName = '');
      }
    }
  }

  Future<void> _clearExportFolder() async {
    _mutateDraft(() {
      _draft.androidExportTreeUri = '';
      _draft.androidExportFolderName = '';
    });
  }

  Future<void> _refreshDictInfo() async {
    final meta = await TagDictionaryUpdateService.instance.loadMeta();
    if (!mounted) return;
    setState(() => _dictMeta = meta);
  }

  Future<void> _updateDictionary() async {
    if (_dictUpdating) return;
    setState(() {
      _dictUpdating = true;
      _dictStatus = '';
    });
    try {
      final result = await TagDictionaryUpdateService.instance.updateNow(
        onStatus: (stage) {
          if (mounted) setState(() => _dictStatus = stage);
        },
      );
      if (!mounted) return;
      setState(() => _dictStatus = result.message);
      await _refreshDictInfo();
    } catch (e) {
      if (mounted) {
        // 错误原文属后端原始产物，按边界决策原样透传，仅翻译前缀
        setState(
          () => _dictStatus = AppLocalizations.of(
            context,
          ).dictUpdateFailed(e.toString()),
        );
      }
    } finally {
      if (mounted) setState(() => _dictUpdating = false);
    }
  }

  String _dictInfoText(AppLocalizations l10n) {
    final count = TagDictionaryService.instance.count;
    final meta = _dictMeta;
    if (meta != null) {
      final date = DateFormat('yyyy-MM-dd HH:mm').format(meta.installedAt);
      return l10n.dictOnlineInfo(meta.entryCount, date);
    }
    return count > 0 ? l10n.dictBuiltinInfo(count) : l10n.dictBuiltinLoading;
  }

  Future<void> _pickDirectory() async {
    final selected = await FilePicker.platform.getDirectoryPath();
    if (selected != null && selected.isNotEmpty && mounted) {
      setState(() => _draft.saveDirController.text = selected);
    }
  }

  Future<void> _testLibrarySync() async {
    if (_syncTesting) return;
    final l10n = context.l10n;
    setState(() {
      _syncTesting = true;
      _syncTestMessage = '';
    });
    try {
      final health = await PromptLibrarySyncService.instance.testConnection(
        PromptLibrarySyncConfig(
          endpoint: _draft.promptSyncEndpointController.text.trim(),
          token: _draft.promptSyncTokenController.text.trim(),
          namespace: _draft.promptSyncNamespaceController.text.trim(),
        ),
      );
      if (!mounted) return;
      setState(() {
        _syncTestOk = true;
        _syncTestMessage = l10n.librarySyncTestSuccess(
          health.activeEntries,
          health.imageCount,
          health.revision,
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _syncTestOk = false;
        _syncTestMessage = l10n.librarySyncTestFailed(e.toString());
      });
    } finally {
      if (mounted) setState(() => _syncTesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    return LayoutBuilder(
      builder: (context, constraints) {
        final hPad = constraints.maxWidth > 984
            ? (constraints.maxWidth - 920) / 2
            : (constraints.maxWidth < 560 ? 16.0 : 32.0);
        return SingleChildScrollView(
          controller: _scrollController,
          padding: EdgeInsets.fromLTRB(hPad, 12, hPad, 76),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppSectionHeader(title: l10n.settingsSectionAppearance),
              AppSettingTile(
                title: l10n.settingsThemeMode,
                control: AppDropdown.simple(
                  value: _draft.themeMode,
                  items: AppThemeModePreference.values,
                  labelOf: (mode) => switch (mode) {
                    AppThemeModePreference.system => l10n.themeModeSystem,
                    AppThemeModePreference.light => l10n.themeModeLight,
                    AppThemeModePreference.dark => l10n.themeModeDark,
                  },
                  width: 130,
                  onChanged: (mode) => _mutateDraft(() => _draft.themeMode = mode),
                ),
              ),
              AppSettingTile(
                title: l10n.settingsBackgroundMode,
                control: AppDropdown.simple(
                  value: _draft.backgroundMode,
                  items: AppBackgroundMode.values,
                  labelOf: (mode) => switch (mode) {
                    AppBackgroundMode.defaultNotion =>
                      l10n.backgroundModeDefault,
                    AppBackgroundMode.followAccent =>
                      l10n.backgroundModeFollowAccent,
                    AppBackgroundMode.custom => l10n.backgroundModeCustom,
                  },
                  width: 130,
                  onChanged: (mode) =>
                      _mutateDraft(() => _draft.backgroundMode = mode),
                ),
              ),
              AppPanelReveal(
                visible: _draft.backgroundMode == AppBackgroundMode.custom,
                enableBlur: false,
                child: Column(
                  children: [
                    if (_draft.themeMode != AppThemeModePreference.dark)
                      AppSettingTile(
                        title: _draft.themeMode == AppThemeModePreference.system
                            ? l10n.settingsBackgroundLightColor
                            : l10n.settingsBackgroundColor,
                        control: _BackgroundColorRow(
                          currentColor:
                              _seedColorOf(_draft.customLightBackgroundColor) ??
                              kLightBackgroundPresets.first,
                          defaultColor: kLightBackgroundPresets.first,
                          presets: kLightBackgroundPresets,
                          hasCustomValue:
                              _draft.customLightBackgroundColor != null,
                          tooltip: l10n.settingsBackgroundLightColor,
                          resetTooltip: l10n.settingsBackgroundReset,
                          onSelectPreset: (color) => _mutateDraft(() {
                            _draft.customLightBackgroundColor =
                                color.toARGB32() ==
                                    kLightBackgroundPresets.first.toARGB32()
                                ? null
                                : seedColorText(color.toARGB32());
                          }),
                          onPickCustom: () async {
                            final picked = await AppColorPickerDialog.show(
                              context,
                              title: l10n.settingsBackgroundLightColor,
                              initialColor:
                                  _seedColorOf(
                                    _draft.customLightBackgroundColor,
                                  ) ??
                                  kLightBackgroundPresets.first,
                              presets: kLightBackgroundPresets,
                            );
                            if (picked == null) return;
                            _mutateDraft(() {
                              _draft.customLightBackgroundColor = seedColorText(
                                picked.toARGB32(),
                              );
                            });
                          },
                          onReset: () => _mutateDraft(
                            () => _draft.customLightBackgroundColor = null,
                          ),
                        ),
                      ),
                    if (_draft.themeMode != AppThemeModePreference.light)
                      AppSettingTile(
                        title: _draft.themeMode == AppThemeModePreference.system
                            ? l10n.settingsBackgroundDarkColor
                            : l10n.settingsBackgroundColor,
                        control: _BackgroundColorRow(
                          currentColor:
                              _seedColorOf(_draft.customDarkBackgroundColor) ??
                              kDarkBackgroundPresets.first,
                          defaultColor: kDarkBackgroundPresets.first,
                          presets: kDarkBackgroundPresets,
                          hasCustomValue:
                              _draft.customDarkBackgroundColor != null,
                          tooltip: l10n.settingsBackgroundDarkColor,
                          resetTooltip: l10n.settingsBackgroundReset,
                          onSelectPreset: (color) => _mutateDraft(() {
                            _draft.customDarkBackgroundColor =
                                color.toARGB32() ==
                                    kDarkBackgroundPresets.first.toARGB32()
                                ? null
                                : seedColorText(color.toARGB32());
                          }),
                          onPickCustom: () async {
                            final picked = await AppColorPickerDialog.show(
                              context,
                              title: l10n.settingsBackgroundDarkColor,
                              initialColor:
                                  _seedColorOf(
                                    _draft.customDarkBackgroundColor,
                                  ) ??
                                  kDarkBackgroundPresets.first,
                              presets: kDarkBackgroundPresets,
                            );
                            if (picked == null) return;
                            _mutateDraft(() {
                              _draft.customDarkBackgroundColor = seedColorText(
                                picked.toARGB32(),
                              );
                            });
                          },
                          onReset: () => _mutateDraft(
                            () => _draft.customDarkBackgroundColor = null,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              AppSettingTile(
                title: l10n.settingsAccentSource,
                control: AppDropdown.simple(
                  value: _draft.accentMode,
                  items: AppAccentMode.values,
                  labelOf: (mode) => switch (mode) {
                    AppAccentMode.defaultBlue => l10n.accentModeDefault,
                    AppAccentMode.adaptive => l10n.accentModeAdaptive,
                    AppAccentMode.manual => l10n.accentModeManual,
                  },
                  width: 130,
                  onChanged: (mode) => _mutateDraft(() => _draft.accentMode = mode),
                ),
              ),
              AppPanelReveal(
                visible: _draft.accentMode == AppAccentMode.manual,
                enableBlur: false,
                child: AppSettingTile(
                  title: l10n.settingsAccentSeed,
                  control: _AccentSeedSwatch(
                    color:
                        _seedColorOf(_draft.accentSeedColor) ??
                        const Color(0xFF0075DE),
                    onTap: () async {
                      final picked = await AppColorPickerDialog.show(
                        context,
                        initialColor:
                            _seedColorOf(_draft.accentSeedColor) ??
                            const Color(0xFF0075DE),
                      );
                      if (picked == null) return;
                      _mutateDraft(() {
                        _draft.accentSeedColor = seedColorText(
                          picked.toARGB32(),
                        );
                        _draft.accentMode = AppAccentMode.manual;
                      });
                    },
                  ),
                ),
              ),
              AppPanelReveal(
                visible: _draft.accentMode != AppAccentMode.defaultBlue,
                enableBlur: false,
                child: AppSettingTile(
                  title: l10n.settingsAccentVariant,
                  control: AppDropdown.simple(
                    value: _draft.accentVariant,
                    items: AppAccentVariant.values,
                    labelOf: (variant) => switch (variant) {
                      AppAccentVariant.tonalSpot => l10n.accentVariantTonalSpot,
                      AppAccentVariant.vibrant => l10n.accentVariantVibrant,
                      AppAccentVariant.expressive =>
                        l10n.accentVariantExpressive,
                      AppAccentVariant.content => l10n.accentVariantContent,
                      AppAccentVariant.neutral => l10n.accentVariantNeutral,
                      AppAccentVariant.monochrome =>
                        l10n.accentVariantMonochrome,
                      AppAccentVariant.rainbow => l10n.accentVariantRainbow,
                      AppAccentVariant.fruitSalad =>
                        l10n.accentVariantFruitSalad,
                    },
                    width: 170,
                    onChanged: (variant) =>
                        _mutateDraft(() => _draft.accentVariant = variant),
                  ),
                ),
              ),
              AppSettingTile(
                title: l10n.settingsLanguage,
                control: AppDropdown.simple(
                  value: _draft.localePreference,
                  items: AppLocalePreference.values,
                  labelOf: (locale) => switch (locale) {
                    AppLocalePreference.system => l10n.localeSystem,
                    AppLocalePreference.zh => l10n.localeChinese,
                    AppLocalePreference.en => l10n.localeEnglish,
                  },
                  width: 150,
                  onChanged: (locale) =>
                      _mutateDraft(() => _draft.localePreference = locale),
                ),
              ),
              AppSettingTile(
                title: l10n.settingsUiZoom,
                control: AppDropdown<double>.simple(
                  value: _draft.uiZoom,
                  items: const [0.8, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75],
                  labelOf: (zoom) => '${(zoom * 100).round()}%',
                  width: 110,
                  onChanged: (zoom) => _mutateDraft(() => _draft.uiZoom = zoom),
                ),
              ),
              AppSettingTile(
                title: l10n.settingsFrameRateLimit,
                control: AppDropdown<int>.simple(
                  value:
                      ConfigService.supportedMaxFrameRates.contains(
                        _draft.maxFrameRate,
                      )
                      ? _draft.maxFrameRate
                      : 0,
                  items: ConfigService.supportedMaxFrameRates,
                  labelOf: (fps) => fps <= 0
                      ? l10n.frameRateUnlimited
                      : l10n.frameRateFpsOption(fps),
                  width: 170,
                  onChanged: (fps) =>
                      _mutateDraft(() => _draft.maxFrameRate = fps),
                ),
              ),
              const SizedBox(height: 12),
              AppSectionHeader(title: l10n.settingsSectionNovelaiService),
              AppSettingTile(
                title: l10n.settingsApiKeyTitle,
                control: SettingsKeyField(
                  controller: _draft.naiKeyController,
                  hintText: 'pst-...',
                  soft: true,
                  fillColor: context.colors.cardBackground,
                ),
              ),
              AppSettingTile(
                title: l10n.settingsSaveDirTitle,
                subtitle: isAndroid ? l10n.settingsAndroidSaveDirSubtitle : null,
                control: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 36,
                          child: TextField(
                            controller: _draft.saveDirController,
                            readOnly: isAndroid,
                            style: const TextStyle(fontSize: 12),
                            decoration: settingsSoftInputDecoration(
                              context,
                              hintText: l10n.settingsSaveDirHint,
                              readOnly: isAndroid,
                              fillColor: isAndroid
                                  ? null
                                  : context.colors.cardBackground,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (!isAndroid) ...[
                        const SizedBox(width: 8),
                        AppActionButton(
                          icon: Icons.folder_open_rounded,
                          label: l10n.settingsChooseButton,
                          onPressed: _pickDirectory,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (isAndroid) ...[
                AppSettingTile(
                  title: l10n.settingsExportFolderTitle,
                  subtitle: _draft.androidExportTreeUri.isEmpty
                      ? l10n.settingsExportFolderNone
                      : l10n.settingsExportFolderSelected(
                          _draft.androidExportFolderName,
                        ),
                  control: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppActionButton(
                        icon: Icons.folder_open_rounded,
                        label: l10n.settingsChooseButton,
                        onPressed: _pickExportFolder,
                      ),
                      if (_draft.androidExportTreeUri.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        AppActionButton(
                          icon: Icons.close_rounded,
                          label: l10n.settingsExportFolderClear,
                          onPressed: _clearExportFolder,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _draft.saveTemplateController,
                builder: (context, value, child) => ImageSaveTemplateSettings(
                  controller: _draft.saveTemplateController,
                  preview: _draft.saveTemplatePreview,
                  error: _draft.saveTemplateError,
                  onInsertMacro: _draft.insertSaveMacro,
                ),
              ),
              AppSettingTile.switchTile(
                title: l10n.settingsAutoSaveTitle,
                value: _draft.autoSaveImages,
                onChanged: (val) => _mutateDraft(() => _draft.autoSaveImages = val),
              ),
              if (isAndroid)
                AppSettingTile.switchTile(
                  title: l10n.settingsGalleryExportTitle,
                  value: _draft.androidGalleryExport,
                  onChanged: (val) =>
                      _mutateDraft(() => _draft.androidGalleryExport = val),
                ),
              AppSettingTile.switchTile(
                title: l10n.settingsStreamPreviewTitle,
                value: _draft.enableStreamPreview,
                onChanged: (val) =>
                    _mutateDraft(() => _draft.enableStreamPreview = val),
              ),
              AppSettingTile.switchTile(
                title: l10n.settingsImagePersistenceTitle,
                value: _draft.enableImagePersistence,
                onChanged: (val) =>
                    _mutateDraft(() => _draft.enableImagePersistence = val),
              ),
              AppPanelReveal(
                visible: _draft.enableImagePersistence,
                enableBlur: false,
                child: AppSettingTile(
                  title: l10n.settingsMaxImagesTitle,
                  control: AppDropdown.simple(
                    value:
                        [
                          20,
                          50,
                          100,
                          200,
                          500,
                        ].contains(_draft.maxPersistentImages)
                        ? _draft.maxPersistentImages
                        : 50,
                    items: const [20, 50, 100, 200, 500],
                    labelOf: (count) => l10n.settingsImageCount(count),
                    width: 110,
                    onChanged: (count) =>
                        _mutateDraft(() => _draft.maxPersistentImages = count),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (!kIsWeb &&
                  defaultTargetPlatform == TargetPlatform.windows) ...[
                AppSectionHeader(title: l10n.canvasActionRtxUpscale),
                AppSettingTile(
                  title: l10n.settingsRtxScaleTitle,
                  control: AppDropdown<int>.simple(
                    value: _draft.rtxUpscaleScale,
                    items: const [2, 4],
                    labelOf: (scale) => '$scale×',
                    width: 110,
                    onChanged: (scale) =>
                        _mutateDraft(() => _draft.rtxUpscaleScale = scale),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              AppSectionHeader(title: l10n.settingsSectionWebSearch),
              AppSettingTile(
                title: l10n.settingsAnySearchKeyTitle,
                control: SettingsKeyField(
                  controller: _draft.anySearchKeyController,
                  hintText: 'as_sk-...',
                  soft: true,
                  fillColor: context.colors.cardBackground,
                ),
              ),
              const SizedBox(height: 12),
              AppSectionHeader(title: l10n.settingsSectionLibrarySync),
              AppSettingTile(
                title: l10n.settingsLibrarySyncEndpointTitle,
                control: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 260),
                  child: SizedBox(
                    height: 36,
                    child: TextField(
                      controller: _draft.promptSyncEndpointController,
                      style: const TextStyle(fontSize: 12),
                      decoration: settingsSoftInputDecoration(
                        context,
                        hintText: l10n.settingsLibrarySyncEndpointHint,
                        fillColor: context.colors.cardBackground,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              AppSettingTile(
                title: l10n.settingsLibrarySyncTokenTitle,
                control: SettingsKeyField(
                  controller: _draft.promptSyncTokenController,
                  hintText: l10n.settingsLibrarySyncTokenHint,
                  width: 260,
                  soft: true,
                  fillColor: context.colors.cardBackground,
                ),
              ),
              AppSettingTile(
                title: l10n.settingsLibrarySyncNamespaceTitle,
                control: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 120,
                      height: 36,
                      child: TextField(
                        controller: _draft.promptSyncNamespaceController,
                        style: const TextStyle(fontSize: 12),
                        decoration: settingsSoftInputDecoration(
                          context,
                          hintText: l10n.settingsLibrarySyncNamespaceHint,
                          fillColor: context.colors.cardBackground,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    AppActionButton(
                      icon: _syncTestOk && _syncTestMessage.isNotEmpty
                          ? Icons.check_circle_outline_rounded
                          : Icons.network_check_rounded,
                      label: _syncTesting
                          ? l10n.librarySyncTesting
                          : l10n.librarySyncTestConnection,
                      isLoading: _syncTesting,
                      onPressed: _syncTesting ? null : _testLibrarySync,
                    ),
                  ],
                ),
                bottomChild: _syncTestMessage.isNotEmpty
                    ? Row(
                        children: [
                          Icon(
                            _syncTestOk
                                ? Icons.check_circle_outline_rounded
                                : Icons.error_outline_rounded,
                            size: 14,
                            color: _syncTestOk
                                ? context.colors.success
                                : context.colors.error,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _syncTestMessage,
                              style: TextStyle(
                                fontSize: 12,
                                color: _syncTestOk
                                    ? context.colors.success
                                    : context.colors.error,
                              ),
                            ),
                          ),
                        ],
                      )
                    : null,
              ),
              AppSettingTile.switchTile(
                title: l10n.settingsLibrarySyncAutoTitle,
                subtitle: l10n.settingsLibrarySyncAutoSubtitle,
                value: _draft.promptSyncAutoEnabled,
                onChanged: (val) =>
                    _mutateDraft(() => _draft.promptSyncAutoEnabled = val),
              ),
              AppPanelReveal(
                visible: _draft.promptSyncAutoEnabled,
                enableBlur: false,
                child: AppSettingTile(
                  title: l10n.settingsLibrarySyncAutoIntervalTitle,
                  control: AppDropdown<int>.simple(
                    value: _draft.promptSyncAutoIntervalMinutes,
                    items: PromptLibrarySyncConfig.allowedAutoSyncIntervals,
                    labelOf: (minutes) => minutes <= 0
                        ? l10n.librarySyncIntervalChangeOnly
                        : l10n.librarySyncIntervalMinutes(minutes),
                    variant: AppDropdownVariant.compact,
                    width: 180,
                    isExpanded: false,
                    onChanged: (val) => _mutateDraft(
                      () => _draft.promptSyncAutoIntervalMinutes = val,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              AppSectionHeader(title: l10n.settingsSectionComfy),
              AppSettingTile.switchTile(
                title: l10n.settingsComfyEnabledTitle,
                value: _draft.comfyUiEnabled,
                onChanged: (val) => _mutateDraft(() => _draft.comfyUiEnabled = val),
              ),
              AppPanelReveal(
                visible: _draft.comfyUiEnabled,
                enableBlur: false,
                child: Column(
                  children: [
                    AppSettingTile(
                      title: l10n.settingsComfyBaseUrlTitle,
                      control: SizedBox(
                        width: 280,
                        child: TextField(
                          controller: _draft.comfyBaseUrlController,
                          style: const TextStyle(fontSize: 12),
                          decoration: settingsSoftInputDecoration(
                            context,
                            hintText: l10n.settingsComfyBaseUrlHint,
                            fillColor: context.colors.cardBackground,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                          ),
                        ),
                      ),
                    ),
                    AppSettingTile(
                      title: l10n.settingsComfyNodeIdsTitle,
                      control: const SizedBox.shrink(),
                      bottomChild: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _draft.comfyPromptNodeController,
                              style: const TextStyle(fontSize: 12),
                              decoration: settingsSoftInputDecoration(
                                context,
                                hintText: l10n.settingsComfyPromptNodeHint,
                                fillColor: context.colors.cardBackground,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _draft.comfyResolutionNodeController,
                              style: const TextStyle(fontSize: 12),
                              decoration: settingsSoftInputDecoration(
                                context,
                                hintText: l10n.settingsComfyResolutionNodeHint,
                                fillColor: context.colors.cardBackground,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _draft.comfyParamsNodeController,
                              style: const TextStyle(fontSize: 12),
                              decoration: settingsSoftInputDecoration(
                                context,
                                hintText: l10n.settingsComfyParamsNodeHint,
                                fillColor: context.colors.cardBackground,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              AppSectionHeader(title: l10n.settingsSectionTagAutocomplete),
              AppSettingTile.switchTile(
                title: l10n.settingsTagAutocompleteTitle,
                value: _draft.enableTagAutocomplete,
                onChanged: (val) =>
                    _mutateDraft(() => _draft.enableTagAutocomplete = val),
              ),
              AppSettingTile(
                title: l10n.settingsDictUpdateTitle,
                subtitle: _dictUpdating
                    ? _dictStatus
                    : (_dictStatus.isNotEmpty
                          ? _dictStatus
                          : _dictInfoText(l10n)),
                control: AnimatedSwitcher(
                  duration: AppMotion.resolveDuration(
                    context,
                    AppMotionDurations.quick,
                  ),
                  switchInCurve: AppMotionCurves.smoothOut,
                  switchOutCurve: AppMotionCurves.smoothOut,
                  child: _dictUpdating
                      ? const Padding(
                          key: ValueKey<bool>(true),
                          padding: EdgeInsets.symmetric(horizontal: 6),
                          child: AppMatrixDotLoader(
                            dotSize: 2.5,
                            gap: 2.0,
                            variant: AppMatrixDotVariant.scan,
                          ),
                        )
                      : AppActionButton(
                          key: const ValueKey<bool>(false),
                          icon: Icons.cloud_download_rounded,
                          label: l10n.settingsDictUpdateNowButton,
                          onPressed: _updateDictionary,
                        ),
                ),
              ),
              AppSettingTile.switchTile(
                title: l10n.settingsDictAutoCheckTitle,
                value: _draft.enableTagDictionaryAutoUpdate,
                onChanged: (val) => _mutateDraft(
                  () => _draft.enableTagDictionaryAutoUpdate = val,
                ),
              ),
              AppSettingTile.switchTile(
                title: l10n.settingsTagTranslationsTitle,
                value: _draft.showTagTranslations,
                onChanged: (val) =>
                    _mutateDraft(() => _draft.showTagTranslations = val),
              ),
              AppSettingTile.switchTile(
                title: l10n.settingsTagColorsTitle,
                value: _draft.showTagCategoryColors,
                onChanged: (val) =>
                    _mutateDraft(() => _draft.showTagCategoryColors = val),
              ),
              const SizedBox(height: 12),
              AppSectionHeader(title: l10n.settingsSectionProtection),
              AppSettingTile.switchTile(
                title: l10n.settingsOpusTitle,
                value: _draft.opusFreeMode,
                onChanged: (val) => _mutateDraft(() => _draft.opusFreeMode = val),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 存储文本 (#RRGGBB) → Color；null/非法返回 null
Color? _seedColorOf(String? text) {
  final argb = parseSeedColorText(text);
  return argb == null ? null : Color(argb);
}

/// 种子色色块控件 (点击打开取色器)
///
/// 展示当前种子色 + 角标编辑图标，点击触发回调；
/// 无业务状态，取色器由调用方打开。
class _AccentSeedSwatch extends StatelessWidget {
  final Color color;
  final VoidCallback onTap;
  final String? tooltip;

  const _AccentSeedSwatch({
    required this.color,
    required this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Tooltip(
      message: tooltip ?? context.l10n.settingsAccentSeed,
      child: AppHoverLift(
        lift: -1.5,
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: AppMotion.resolveDuration(
              context,
              AppMotionDurations.quick,
            ),
            curve: AppMotionCurves.smoothOut,
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: colors.borderDefault),
            ),
            child: Align(
              alignment: Alignment.bottomRight,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: colors.cardBackground,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: colors.borderDefault),
                ),
                child: Icon(
                  Icons.colorize,
                  size: 10,
                  color: colors.textSecondary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 自定义背景色行控件：精选预设小色块 + 自定义取色器色块 + 恢复默认按钮
class _BackgroundColorRow extends StatelessWidget {
  final Color currentColor;
  final Color defaultColor;
  final List<Color> presets;
  final bool hasCustomValue;
  final String tooltip;
  final String resetTooltip;
  final ValueChanged<Color> onSelectPreset;
  final VoidCallback onPickCustom;
  final VoidCallback onReset;

  const _BackgroundColorRow({
    required this.currentColor,
    required this.defaultColor,
    required this.presets,
    required this.hasCustomValue,
    required this.tooltip,
    required this.resetTooltip,
    required this.onSelectPreset,
    required this.onPickCustom,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.end,
      children: [
        for (final preset in presets)
          GestureDetector(
            onTap: () => onSelectPreset(preset),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: AnimatedContainer(
                duration: AppMotion.resolveDuration(
                  context,
                  AppMotionDurations.quick,
                ),
                curve: AppMotionCurves.smoothOut,
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: preset,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(
                    color: currentColor.toARGB32() == preset.toARGB32()
                        ? colors.primary
                        : colors.borderDefault,
                    width: currentColor.toARGB32() == preset.toARGB32()
                        ? 2.0
                        : 1.0,
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(width: 2),
        _AccentSeedSwatch(
          color: currentColor,
          tooltip: tooltip,
          onTap: onPickCustom,
        ),
        if (hasCustomValue && currentColor.toARGB32() != defaultColor.toARGB32())
          AppIconButton(
            icon: Icons.refresh_rounded,
            size: 26,
            iconSize: 15,
            radius: AppRadius.sm,
            variant: AppIconButtonVariant.ghost,
            tooltip: resetTooltip,
            onPressed: onReset,
          ),
      ],
    );
  }
}
