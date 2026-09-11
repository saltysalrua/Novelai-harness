import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../data/services/config_service.dart';
import '../../../../data/models/nai_generation_params.dart';
import '../../../../data/services/image_save_path_service.dart';
import '../../../../data/services/tag_dictionary_service.dart';
import '../../../../data/services/tag_dictionary_update_service.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../core/context_l10n.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_action_button.dart';
import '../../../core/widgets/app_color_picker_dialog.dart';
import '../../../core/widgets/app_dropdown.dart';
import '../../../core/widgets/app_section_header.dart';
import '../../../core/widgets/app_setting_tile.dart';
import 'settings_shared.dart';
import 'image_save_template_settings.dart';

/// General 页草稿状态 (父级 SettingsDialog 持有，保存时统一聚合)
class GeneralSettingsDraft {
  GeneralSettingsDraft(AppConfig config)
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
      opusFreeMode = config.opusFreeMode,
      themeMode = config.themeMode,
      accentMode = config.accentMode,
      accentVariant = config.accentVariant,
      accentSeedColor = config.accentSeedColor,
      localePreference = config.localePreference,
      uiZoom = config.uiZoom,
      enableStreamPreview = config.enableStreamPreview,
      enableTagAutocomplete = config.enableTagAutocomplete,
      showTagTranslations = config.showTagTranslations,
      showTagCategoryColors = config.showTagCategoryColors,
      enableTagDictionaryAutoUpdate = config.enableTagDictionaryAutoUpdate,
      enableImagePersistence = config.enableImagePersistence,
      maxPersistentImages = config.maxPersistentImages,
      autoSaveImages = config.autoSaveImages,
      comfyUiEnabled = config.comfyUiEnabled;

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
  bool comfyUiEnabled;

  /// 主题模式偏好 (跟随系统/亮色/深色)，保存时由 SettingsDialog 聚合进 AppConfig
  AppThemeModePreference themeMode;

  /// 主题强调色来源 (默认蓝/跟随图片/手动种子)，保存时聚合进 AppConfig
  AppAccentMode accentMode;

  /// MD3 取色方案 (强调色非默认时生效)，保存时聚合进 AppConfig
  AppAccentVariant accentVariant;

  /// 手动模式种子色 (#RRGGBB 文本，null = 未指定)，保存时聚合进 AppConfig
  String? accentSeedColor;

  /// 语言偏好 (跟随系统/中文/English)，保存时由 SettingsDialog 聚合进 AppConfig
  AppLocalePreference localePreference;

  /// 全局 UI 缩放 (浏览器式整体缩放)，保存时聚合进 AppConfig
  double uiZoom;
  bool enableStreamPreview;
  bool enableTagAutocomplete;
  bool showTagTranslations;
  bool showTagCategoryColors;
  bool enableTagDictionaryAutoUpdate;
  bool enableImagePersistence;
  int maxPersistentImages;
  bool autoSaveImages;

  void dispose() {
    naiKeyController.dispose();
    anySearchKeyController.dispose();
    saveDirController.dispose();
    saveTemplateController.dispose();
    comfyBaseUrlController.dispose();
    comfyPromptNodeController.dispose();
    comfyResolutionNodeController.dispose();
    comfyParamsNodeController.dispose();
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

  TagDictMeta? _dictMeta;
  bool _dictUpdating = false;
  String _dictStatus = '';

  @override
  void initState() {
    super.initState();
    _refreshDictInfo();
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

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 600;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            isNarrow ? 14 : 28,
            8,
            isNarrow ? 14 : 28,
            20,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          AppSectionHeader(title: l10n.settingsSectionAppearance),
          AppSettingTile(
            title: l10n.settingsThemeMode,
            subtitle: l10n.settingsThemeModeSubtitle,
            control: AppDropdown.simple(
              value: _draft.themeMode,
              items: AppThemeModePreference.values,
              labelOf: (mode) => switch (mode) {
                AppThemeModePreference.system => l10n.themeModeSystem,
                AppThemeModePreference.light => l10n.themeModeLight,
                AppThemeModePreference.dark => l10n.themeModeDark,
              },
              width: 130,
              onChanged: (mode) => setState(() => _draft.themeMode = mode),
            ),
          ),
          AppSettingTile(
            title: l10n.settingsAccentSource,
            subtitle: l10n.settingsAccentSourceSubtitle,
            control: AppDropdown.simple(
              value: _draft.accentMode,
              items: AppAccentMode.values,
              labelOf: (mode) => switch (mode) {
                AppAccentMode.defaultBlue => l10n.accentModeDefault,
                AppAccentMode.adaptive => l10n.accentModeAdaptive,
                AppAccentMode.manual => l10n.accentModeManual,
              },
              width: 130,
              onChanged: (mode) => setState(() => _draft.accentMode = mode),
            ),
          ),
          AppSettingTile(
            title: l10n.settingsAccentSeed,
            subtitle: l10n.settingsAccentSeedSubtitle,
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
                setState(() {
                  _draft.accentSeedColor = seedColorText(picked.toARGB32());
                  _draft.accentMode = AppAccentMode.manual;
                });
              },
            ),
          ),
          AppSettingTile(
            title: l10n.settingsAccentVariant,
            subtitle: l10n.settingsAccentVariantSubtitle,
            control: AppDropdown.simple(
              value: _draft.accentVariant,
              items: AppAccentVariant.values,
              labelOf: (variant) => switch (variant) {
                AppAccentVariant.tonalSpot => l10n.accentVariantTonalSpot,
                AppAccentVariant.vibrant => l10n.accentVariantVibrant,
                AppAccentVariant.expressive => l10n.accentVariantExpressive,
                AppAccentVariant.content => l10n.accentVariantContent,
                AppAccentVariant.neutral => l10n.accentVariantNeutral,
                AppAccentVariant.monochrome => l10n.accentVariantMonochrome,
                AppAccentVariant.rainbow => l10n.accentVariantRainbow,
                AppAccentVariant.fruitSalad => l10n.accentVariantFruitSalad,
              },
              width: 170,
              onChanged: (variant) =>
                  setState(() => _draft.accentVariant = variant),
            ),
          ),
          AppSettingTile(
            title: l10n.settingsLanguage,
            subtitle: l10n.settingsLanguageSubtitle,
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
                  setState(() => _draft.localePreference = locale),
            ),
          ),
          AppSettingTile(
            title: l10n.settingsUiZoom,
            subtitle: l10n.settingsUiZoomSubtitle,
            control: AppDropdown<double>.simple(
              value: _draft.uiZoom,
              items: const [0.8, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75],
              labelOf: (zoom) => '${(zoom * 100).round()}%',
              width: 110,
              onChanged: (zoom) => setState(() => _draft.uiZoom = zoom),
            ),
          ),
          const SizedBox(height: 12),
          AppSectionHeader(title: l10n.settingsSectionNovelaiService),
          AppSettingTile(
            title: l10n.settingsApiKeyTitle,
            subtitle: l10n.settingsApiKeySubtitle,
            control: SettingsKeyField(
              controller: _draft.naiKeyController,
              hintText: 'pst-...',
            ),
          ),
          AppSettingTile(
            title: l10n.settingsSaveDirTitle,
            subtitle: l10n.settingsSaveDirSubtitle,
            control: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 36,
                      child: TextField(
                        controller: _draft.saveDirController,
                        style: const TextStyle(fontSize: 12),
                        decoration: InputDecoration(
                          hintText: l10n.settingsSaveDirHint,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  AppActionButton(
                    icon: Icons.folder_open_rounded,
                    label: l10n.settingsChooseButton,
                    onPressed: _pickDirectory,
                  ),
                ],
              ),
            ),
          ),
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
            subtitle: _draft.autoSaveImages
                ? l10n.settingsAutoSaveSubtitleOn
                : l10n.settingsAutoSaveSubtitleOff,
            value: _draft.autoSaveImages,
            onChanged: (val) => setState(() => _draft.autoSaveImages = val),
          ),
          AppSettingTile.switchTile(
            title: l10n.settingsStreamPreviewTitle,
            subtitle: l10n.settingsStreamPreviewSubtitle,
            value: _draft.enableStreamPreview,
            onChanged: (val) =>
                setState(() => _draft.enableStreamPreview = val),
          ),
          AppSettingTile.switchTile(
            title: l10n.settingsImagePersistenceTitle,
            subtitle: l10n.settingsImagePersistenceSubtitle,
            value: _draft.enableImagePersistence,
            onChanged: (val) =>
                setState(() => _draft.enableImagePersistence = val),
          ),
          if (_draft.enableImagePersistence)
            AppSettingTile(
              title: l10n.settingsMaxImagesTitle,
              subtitle: l10n.settingsMaxImagesSubtitle,
              control: AppDropdown.simple(
                value:
                    [20, 50, 100, 200, 500].contains(_draft.maxPersistentImages)
                    ? _draft.maxPersistentImages
                    : 50,
                items: const [20, 50, 100, 200, 500],
                labelOf: (count) => l10n.settingsImageCount(count),
                width: 110,
                onChanged: (count) =>
                    setState(() => _draft.maxPersistentImages = count),
              ),
            ),
          const SizedBox(height: 12),
          AppSectionHeader(title: l10n.settingsSectionWebSearch),
          AppSettingTile(
            title: l10n.settingsAnySearchKeyTitle,
            subtitle: l10n.settingsAnySearchKeySubtitle,
            control: SettingsKeyField(
              controller: _draft.anySearchKeyController,
              hintText: 'as_sk-...',
            ),
          ),
          const SizedBox(height: 12),
          AppSectionHeader(title: l10n.settingsSectionComfy),
          AppSettingTile.switchTile(
            title: l10n.settingsComfyEnabledTitle,
            subtitle: l10n.settingsComfyEnabledDesc,
            value: _draft.comfyUiEnabled,
            onChanged: (val) => setState(() => _draft.comfyUiEnabled = val),
          ),
          if (_draft.comfyUiEnabled) ...[
            AppSettingTile(
              title: l10n.settingsComfyBaseUrlTitle,
              control: SettingsKeyField(
                controller: _draft.comfyBaseUrlController,
                hintText: l10n.settingsComfyBaseUrlHint,
              ),
            ),
            AppSettingTile(
              title: l10n.settingsComfyNodeIdsTitle,
              subtitle: l10n.settingsComfyNodeIdsHint,
              control: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SizedBox(
                    width: 220,
                    child: TextField(
                      controller: _draft.comfyPromptNodeController,
                      style: const TextStyle(fontSize: 12),
                      decoration: InputDecoration(
                        hintText: l10n.settingsComfyPromptNodeHint,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: 220,
                    child: TextField(
                      controller: _draft.comfyResolutionNodeController,
                      style: const TextStyle(fontSize: 12),
                      decoration: InputDecoration(
                        hintText: l10n.settingsComfyResolutionNodeHint,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: 220,
                    child: TextField(
                      controller: _draft.comfyParamsNodeController,
                      style: const TextStyle(fontSize: 12),
                      decoration: InputDecoration(
                        hintText: l10n.settingsComfyParamsNodeHint,
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
          const SizedBox(height: 12),
          AppSectionHeader(title: l10n.settingsSectionTagAutocomplete),
          AppSettingTile.switchTile(
            title: l10n.settingsTagAutocompleteTitle,
            subtitle: l10n.settingsTagAutocompleteSubtitle,
            value: _draft.enableTagAutocomplete,
            onChanged: (val) =>
                setState(() => _draft.enableTagAutocomplete = val),
          ),
          AppSettingTile(
            title: l10n.settingsDictUpdateTitle,
            subtitle: _dictUpdating
                ? _dictStatus
                : (_dictStatus.isNotEmpty ? _dictStatus : _dictInfoText(l10n)),
            control: _dictUpdating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : AppActionButton(
                    icon: Icons.cloud_download_rounded,
                    label: l10n.settingsDictUpdateNowButton,
                    onPressed: _updateDictionary,
                  ),
          ),
          AppSettingTile.switchTile(
            title: l10n.settingsDictAutoCheckTitle,
            subtitle: l10n.settingsDictAutoCheckSubtitle,
            value: _draft.enableTagDictionaryAutoUpdate,
            onChanged: (val) =>
                setState(() => _draft.enableTagDictionaryAutoUpdate = val),
          ),
          AppSettingTile.switchTile(
            title: l10n.settingsTagTranslationsTitle,
            subtitle: l10n.settingsTagTranslationsSubtitle,
            value: _draft.showTagTranslations,
            onChanged: (val) =>
                setState(() => _draft.showTagTranslations = val),
          ),
          AppSettingTile.switchTile(
            title: l10n.settingsTagColorsTitle,
            subtitle: l10n.settingsTagColorsSubtitle,
            value: _draft.showTagCategoryColors,
            onChanged: (val) =>
                setState(() => _draft.showTagCategoryColors = val),
          ),
          const SizedBox(height: 12),
          AppSectionHeader(title: l10n.settingsSectionProtection),
          AppSettingTile.switchTile(
            title: l10n.settingsOpusTitle,
            subtitle: l10n.settingsOpusSubtitle,
            value: _draft.opusFreeMode,
            onChanged: (val) => setState(() => _draft.opusFreeMode = val),
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

  const _AccentSeedSwatch({required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Tooltip(
      message: context.l10n.settingsAccentSeed,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
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
