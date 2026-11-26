import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/harness/presets/agent_preset.dart';
import '../../../../data/models/llm_models.dart';
import '../../../../data/models/prompt_library_sync_models.dart';
import '../../../../data/services/config_service.dart';
import '../../../core/context_l10n.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_action_button.dart';
import '../../../core/widgets/app_icon_label.dart';
import '../../../core/widgets/app_nav_tile.dart';
import '../../../core/widgets/app_page_stack.dart';
import '../../../core/widgets/app_segmented_controls.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/app_transitions.dart';
import '../../../core/widgets/custom_title_bar.dart';
import '../../../../l10n/app_localizations.dart';
import '../../studio/view_models/studio_view_model.dart';
import '../widgets/bill_settings_tab.dart';
import '../widgets/defaults_settings_tab.dart';
import '../widgets/extensions_settings_tab.dart';
import '../widgets/general_settings_tab.dart';
import '../widgets/image_save_template_settings.dart';
import '../widgets/models_settings_tab.dart';
import '../widgets/presets_settings_tab.dart';

/// 全局设置整页视图：柔和圆润画布 + 左侧无框导航 + 右侧圆角卡片详情 + 按需悬浮保存坞
///
/// 各标签页持有独立的草稿状态 (Draft)，由本壳统一创建、装配与聚合保存；
/// AppPageStack 首次激活时懒构建标签页，轻量过渡并保留输入与滚动状态；
/// 仅在检测到未保存更改时于右下角浮现「放弃更改 / 保存设置」胶囊条。
class SettingsDialog extends StatefulWidget {
  final StudioViewModel viewModel;

  const SettingsDialog({super.key, required this.viewModel});

  static Future<void> show(
    BuildContext context,
    StudioViewModel viewModel,
  ) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    final capturedThemes = InheritedTheme.capture(
      from: context,
      to: navigator.context,
    );
    final route = AppModalPageRoute<AppConfig>(
      opaque: true,
      barrierDismissible: false,
      barrierColor: null,
      startScale: 0.985,
      builder: (ctx) =>
          capturedThemes.wrap(SettingsDialog(viewModel: viewModel)),
    );
    final config = await navigator.push<AppConfig>(route);
    // pop completes before the outgoing page is removed. Applying locale or
    // zoom changes during that transition can crash the macOS semantics bridge.
    await route.completed;
    if (config != null) await viewModel.updateConfig(config);
  }

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  /// 设置分类单一事实源 (图标)：桌面侧栏与窄屏顶部胶囊栏共用，
  /// 避免两处各抄一份导致新增分类漏改；文案经 [_settingsTabLabel] 接入 l10n。
  static const List<IconData> _settingsTabIcons = [
    Icons.tune_outlined,
    Icons.smart_toy_outlined,
    Icons.psychology_outlined,
    Icons.extension_outlined,
    Icons.layers_outlined,
    Icons.receipt_long_outlined,
  ];

  /// 分类文案 l10n 取词 (索引与 [_settingsTabIcons] 严格对齐)
  static String _settingsTabLabel(AppLocalizations l10n, int index) =>
      switch (index) {
        0 => l10n.settingsTabGeneral,
        1 => l10n.settingsTabModels,
        2 => l10n.settingsTabPresets,
        3 => l10n.settingsTabExtensions,
        4 => l10n.settingsTabDefaults,
        5 => l10n.settingsTabBill,
        _ => l10n.settings,
      };

  int _activeTabIndex = 0;
  int _draftGeneration = 0;
  final ValueNotifier<int> _draftRevision = ValueNotifier<int>(0);

  late GeneralSettingsDraft _generalDraft;
  late ModelsSettingsDraft _modelsDraft;
  late PresetsSettingsDraft _presetsDraft;
  late DefaultsSettingsDraft _defaultsDraft;

  /// 页面缓存、隐藏页焦点/Ticker 隔离统一由 AppPageStack 管理。
  late List<Widget Function()> _tabBuilders;

  AppConfig? _cachedBaseConfig;
  String _cachedBaseProvidersJson = '';
  String _cachedBasePresetsJson = '';
  String _cachedBaseActiveProviderId = '';
  String _cachedBaseActivePresetId = '';

  @override
  void initState() {
    super.initState();
    _initDrafts();
  }

  void _initDrafts() {
    final cfg = widget.viewModel.config;
    _generalDraft = GeneralSettingsDraft(cfg, onChanged: _onDraftChanged);
    _modelsDraft = ModelsSettingsDraft(cfg, onChanged: _onDraftChanged);
    _presetsDraft = PresetsSettingsDraft(cfg, onChanged: _onDraftChanged);
    _defaultsDraft = DefaultsSettingsDraft(cfg, onChanged: _onDraftChanged);

    // 每页自行包裹滚动容器，弹窗壳不再统一包 SingleChildScrollView
    _tabBuilders = [
      () => GeneralSettingsTab(draft: _generalDraft),
      () => ModelsSettingsTab(viewModel: widget.viewModel, draft: _modelsDraft),
      () => PresetsSettingsTab(
        viewModel: widget.viewModel,
        draft: _presetsDraft,
        onOpenExtensionsTab: () => setState(() => _activeTabIndex = 3),
      ),
      () => ExtensionsSettingsTab(
        viewModel: widget.viewModel,
        presetsDraft: _presetsDraft,
      ),
      () => DefaultsSettingsTab(
        draft: _defaultsDraft,
        getProviders: () => _modelsDraft.providers,
        getActiveProviderId: () => _modelsDraft.selectedProviderId,
        getPresets: () => _presetsDraft.presets,
      ),
      () => BillSettingsTab(viewModel: widget.viewModel),
    ];
  }

  void _disposeDrafts() {
    _generalDraft.dispose();
    _modelsDraft.dispose();
    _presetsDraft.dispose();
  }

  void _onDraftChanged() {
    if (!mounted) return;
    _draftRevision.value++;
  }

  void _handleDiscardChanges() {
    FocusManager.instance.primaryFocus?.unfocus();
    _disposeDrafts();
    _draftGeneration++;
    _initDrafts();
    setState(() {});
    _draftRevision.value++;
  }

  void _ensureBaseJsonCache(AppConfig base) {
    if (identical(_cachedBaseConfig, base)) return;
    _cachedBaseConfig = base;
    final baseProviders = base.llmProviders.isNotEmpty
        ? base.llmProviders
        : LlmProviderConfig.defaultProviders;
    _cachedBaseActiveProviderId =
        baseProviders.any((p) => p.id == base.activeLlmProviderId)
        ? base.activeLlmProviderId
        : baseProviders.first.id;
    _cachedBaseProvidersJson = jsonEncode(
      baseProviders.map((p) => p.toJson()).toList(growable: false),
    );
    final basePresets = base.presets.isNotEmpty
        ? base.presets
        : BuiltinPresets.all;
    _cachedBaseActivePresetId =
        basePresets.any((p) => p.id == base.activePresetId)
        ? base.activePresetId
        : basePresets.first.id;
    _cachedBasePresetsJson = jsonEncode(
      basePresets.map((p) => p.toJson()).toList(growable: false),
    );
  }

  /// 检测四个草稿页是否存在尚未保存的改动（与最新持久化 AppConfig 对比）。
  bool _hasUnsavedChanges() {
    final base = widget.viewModel.config;
    _ensureBaseJsonCache(base);

    // 1. General
    final normalizedSyncNamespace =
        _generalDraft.promptSyncNamespaceController.text.trim().isEmpty
        ? 'default'
        : _generalDraft.promptSyncNamespaceController.text.trim();
    final baseSyncNamespace = base.promptSyncNamespace.trim().isEmpty
        ? 'default'
        : base.promptSyncNamespace.trim();
    final baseSyncInterval = PromptLibrarySyncConfig(
      autoSyncIntervalMinutes: base.promptSyncAutoIntervalMinutes,
    ).normalizedAutoSyncIntervalMinutes;
    if (_generalDraft.naiKeyController.text.trim() != base.novelAiKey.trim() ||
        _generalDraft.anySearchKeyController.text.trim() !=
            base.anySearchApiKey.trim() ||
        _generalDraft.saveDirController.text.trim() !=
            base.saveDirectory.trim() ||
        _generalDraft.saveTemplateController.text.trim() !=
            base.imageSaveTemplate.trim() ||
        _generalDraft.opusFreeMode != base.opusFreeMode ||
        _generalDraft.themeMode != base.themeMode ||
        _generalDraft.accentMode != base.accentMode ||
        _generalDraft.accentVariant != base.accentVariant ||
        (_generalDraft.accentSeedColor ?? base.accentSeedColor) !=
            base.accentSeedColor ||
        _generalDraft.backgroundMode != base.backgroundMode ||
        _generalDraft.customLightBackgroundColor !=
            base.customLightBackgroundColor ||
        _generalDraft.customDarkBackgroundColor !=
            base.customDarkBackgroundColor ||
        _generalDraft.localePreference != base.localePreference ||
        _generalDraft.uiZoom != base.uiZoom ||
        _generalDraft.maxFrameRate != base.maxFrameRate ||
        _generalDraft.enableStreamPreview != base.enableStreamPreview ||
        _generalDraft.enableTagAutocomplete != base.enableTagAutocomplete ||
        _generalDraft.showTagTranslations != base.showTagTranslations ||
        _generalDraft.showTagCategoryColors != base.showTagCategoryColors ||
        _generalDraft.enableTagDictionaryAutoUpdate !=
            base.enableTagDictionaryAutoUpdate ||
        _generalDraft.enableImagePersistence != base.enableImagePersistence ||
        _generalDraft.maxPersistentImages != base.maxPersistentImages ||
        _generalDraft.autoSaveImages != base.autoSaveImages ||
        _generalDraft.androidGalleryExport != base.androidGalleryExport ||
        _generalDraft.androidExportTreeUri != base.androidExportTreeUri ||
        _generalDraft.rtxUpscaleScale != base.rtxUpscaleScale ||
        _generalDraft.comfyUiEnabled != base.comfyUiEnabled ||
        _generalDraft.comfyBaseUrlController.text.trim() !=
            base.comfyUiBaseUrl.trim() ||
        _generalDraft.comfyPromptNodeController.text.trim() !=
            base.comfyUiPromptNodeId.trim() ||
        _generalDraft.comfyResolutionNodeController.text.trim() !=
            base.comfyUiResolutionNodeId.trim() ||
        _generalDraft.comfyParamsNodeController.text.trim() !=
            base.comfyUiParamsNodeId.trim() ||
        _generalDraft.promptSyncEndpointController.text.trim() !=
            base.promptSyncEndpoint.trim() ||
        _generalDraft.promptSyncTokenController.text.trim() !=
            base.promptSyncToken.trim() ||
        normalizedSyncNamespace != baseSyncNamespace ||
        _generalDraft.promptSyncAutoEnabled != base.promptSyncAutoEnabled ||
        _generalDraft.promptSyncAutoIntervalMinutes != baseSyncInterval) {
      return true;
    }

    // 2. Defaults
    if (_defaultsDraft.model != base.defaultModel ||
        _defaultsDraft.sampler != base.defaultSampler ||
        _defaultsDraft.noiseSchedule != base.defaultNoiseSchedule ||
        _defaultsDraft.steps != base.defaultSteps ||
        _defaultsDraft.scale != base.defaultScale ||
        _defaultsDraft.agentMaxTurns.clamp(1, 100) !=
            base.agentMaxTurns.clamp(1, 100) ||
        _defaultsDraft.compactionEnabled != base.agentCompactionEnabled ||
        _defaultsDraft.backgroundCompaction != base.agentBackgroundCompaction ||
        _defaultsDraft.persistentImages != base.agentPersistentImages ||
        _defaultsDraft.retainedHistoryImages.clamp(0, 10) !=
            base.agentRetainedHistoryImages.clamp(0, 10) ||
        _defaultsDraft.compactionProviderId != base.compactionProviderId ||
        _defaultsDraft.compactionModelId != base.compactionModelId ||
        _defaultsDraft.inboxOrganizerProviderId !=
            base.inboxOrganizerProviderId ||
        _defaultsDraft.inboxOrganizerModelId != base.inboxOrganizerModelId ||
        _defaultsDraft.inboxOrganizerThinkingEffort !=
            base.inboxOrganizerThinkingEffort ||
        _defaultsDraft.inboxAutoRerunPreview != base.inboxAutoRerunPreview ||
        !listEquals(
          _defaultsDraft.inboxOrganizerExcludedCategories,
          base.inboxOrganizerExcludedCategories,
        ) ||
        _defaultsDraft.inboxOrganizerPresetId != base.inboxOrganizerPresetId ||
        _defaultsDraft.inboxOrganizerCustomInstructions !=
            base.inboxOrganizerCustomInstructions) {
      return true;
    }

    // 3. Models
    if (_modelsDraft.selectedProviderId != _cachedBaseActiveProviderId ||
        _modelsDraft.imageEditProviderId != base.imageEditProviderId ||
        _modelsDraft.imageEditModelId != base.imageEditModelId) {
      return true;
    }
    final candidateProvidersJson = jsonEncode(
      _modelsDraft
          .snapshotProviders()
          .map((p) => p.toJson())
          .toList(growable: false),
    );
    if (candidateProvidersJson != _cachedBaseProvidersJson) {
      return true;
    }

    // 4. Presets
    if (_presetsDraft.activePresetId != _cachedBaseActivePresetId) {
      return true;
    }
    final candidatePresetsJson = jsonEncode(
      _presetsDraft
          .snapshotPresets()
          .map((p) => p.toJson())
          .toList(growable: false),
    );
    if (candidatePresetsJson != _cachedBasePresetsJson) {
      return true;
    }

    return false;
  }

  @override
  void dispose() {
    _draftRevision.dispose();
    _disposeDrafts();
    super.dispose();
  }

  void _handleSave() {
    final templateError = ImageSaveTemplateSettings.errorTextOf(
      context,
      _generalDraft.saveTemplateError,
    );
    if (templateError != null) {
      setState(() => _activeTabIndex = 0);
      showAppToast(
        context,
        message: templateError,
        tone: AppToastTone.error,
      );
      return;
    }
    _modelsDraft.syncFromForm();
    _presetsDraft.syncFromForm();

    final newConfig = widget.viewModel.config.copyWith(
      novelAiKey: _generalDraft.naiKeyController.text.trim(),
      anySearchApiKey: _generalDraft.anySearchKeyController.text.trim(),
      saveDirectory: _generalDraft.saveDirController.text.trim(),
      imageSaveTemplate: _generalDraft.saveTemplateController.text.trim(),
      opusFreeMode: _generalDraft.opusFreeMode,
      themeMode: _generalDraft.themeMode,
      accentMode: _generalDraft.accentMode,
      accentVariant: _generalDraft.accentVariant,
      accentSeedColor:
          _generalDraft.accentSeedColor ??
          widget.viewModel.config.accentSeedColor,
      backgroundMode: _generalDraft.backgroundMode,
      customLightBackgroundColor: _generalDraft.customLightBackgroundColor,
      clearCustomLightBackgroundColor:
          _generalDraft.customLightBackgroundColor == null,
      customDarkBackgroundColor: _generalDraft.customDarkBackgroundColor,
      clearCustomDarkBackgroundColor:
          _generalDraft.customDarkBackgroundColor == null,
      localePreference: _generalDraft.localePreference,
      uiZoom: _generalDraft.uiZoom,
      maxFrameRate: _generalDraft.maxFrameRate,
      enableStreamPreview: _generalDraft.enableStreamPreview,
      enableTagAutocomplete: _generalDraft.enableTagAutocomplete,
      showTagTranslations: _generalDraft.showTagTranslations,
      showTagCategoryColors: _generalDraft.showTagCategoryColors,
      enableTagDictionaryAutoUpdate:
          _generalDraft.enableTagDictionaryAutoUpdate,
      enableImagePersistence: _generalDraft.enableImagePersistence,
      maxPersistentImages: _generalDraft.maxPersistentImages,
      autoSaveImages: _generalDraft.autoSaveImages,
      androidGalleryExport: _generalDraft.androidGalleryExport,
      androidExportTreeUri: _generalDraft.androidExportTreeUri,
      rtxUpscaleScale: _generalDraft.rtxUpscaleScale,
      comfyUiEnabled: _generalDraft.comfyUiEnabled,
      comfyUiBaseUrl: _generalDraft.comfyBaseUrlController.text.trim(),
      comfyUiPromptNodeId: _generalDraft.comfyPromptNodeController.text.trim(),
      comfyUiResolutionNodeId: _generalDraft.comfyResolutionNodeController.text
          .trim(),
      comfyUiParamsNodeId: _generalDraft.comfyParamsNodeController.text.trim(),
      promptSyncEndpoint: _generalDraft.promptSyncEndpointController.text
          .trim(),
      promptSyncToken: _generalDraft.promptSyncTokenController.text.trim(),
      promptSyncNamespace:
          _generalDraft.promptSyncNamespaceController.text.trim().isEmpty
          ? 'default'
          : _generalDraft.promptSyncNamespaceController.text.trim(),
      promptSyncAutoEnabled: _generalDraft.promptSyncAutoEnabled,
      promptSyncAutoIntervalMinutes:
          _generalDraft.promptSyncAutoIntervalMinutes,
      llmProviders: _modelsDraft.providers,
      activeLlmProviderId: _modelsDraft.selectedProviderId,
      imageEditProviderId: _modelsDraft.imageEditProviderId,
      imageEditModelId: _modelsDraft.imageEditModelId,
      presets: _presetsDraft.presets,
      activePresetId: _presetsDraft.activePresetId,
      defaultModel: _defaultsDraft.model,
      defaultSampler: _defaultsDraft.sampler,
      defaultNoiseSchedule: _defaultsDraft.noiseSchedule,
      defaultSteps: _defaultsDraft.steps,
      defaultScale: _defaultsDraft.scale,
      agentMaxTurns: _defaultsDraft.agentMaxTurns.clamp(1, 100),
      agentCompactionEnabled: _defaultsDraft.compactionEnabled,
      agentBackgroundCompaction: _defaultsDraft.backgroundCompaction,
      agentPersistentImages: _defaultsDraft.persistentImages,
      agentRetainedHistoryImages: _defaultsDraft.retainedHistoryImages.clamp(
        0,
        10,
      ),
      compactionProviderId: _defaultsDraft.compactionProviderId,
      compactionModelId: _defaultsDraft.compactionModelId,
      inboxOrganizerProviderId: _defaultsDraft.inboxOrganizerProviderId,
      inboxOrganizerModelId: _defaultsDraft.inboxOrganizerModelId,
      inboxOrganizerThinkingEffort: _defaultsDraft.inboxOrganizerThinkingEffort,
      inboxAutoRerunPreview: _defaultsDraft.inboxAutoRerunPreview,
      inboxOrganizerExcludedCategories:
          _defaultsDraft.inboxOrganizerExcludedCategories,
      inboxOrganizerPresetId: _defaultsDraft.inboxOrganizerPresetId,
      inboxOrganizerCustomInstructions:
          _defaultsDraft.inboxOrganizerCustomInstructions,
    );

    Navigator.of(context).pop(newConfig);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final screenSize = MediaQuery.sizeOf(context);
    final isNarrow = screenSize.width < 768;
    final showCustomTitleBar =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux);

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event.logicalKey != LogicalKeyboardKey.escape) {
          return KeyEventResult.ignored;
        }
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        // 内部输入框聚焦时首次 ESC 只退焦，不直接退出丢草稿
        final primary = FocusManager.instance.primaryFocus;
        final primaryContext = primary?.context;
        final bool editingText =
            primaryContext?.findAncestorStateOfType<EditableTextState>() !=
            null;
        if (editingText) {
          // 将焦点收回设置页根 Focus，既退出文本输入又保证再次按 ESC 可稳定返回
          node.requestFocus();
          return KeyEventResult.handled;
        }
        Navigator.of(context).pop();
        return KeyEventResult.handled;
      },
      child: Scaffold(
        backgroundColor: colors.canvasBackground,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showCustomTitleBar) const CustomTitleBar(),
            Expanded(
              child: SafeArea(
                top: !showCustomTitleBar,
                bottom: isNarrow,
                child: isNarrow
                    ? Stack(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildContentHeader(context, isNarrow: true),
                              _buildHorizontalTabs(context),
                              Expanded(
                                child: Container(
                                  margin: const EdgeInsets.fromLTRB(
                                    8,
                                    4,
                                    8,
                                    8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colors.cardBackground,
                                    borderRadius: BorderRadius.circular(
                                      AppRadius.xl,
                                    ),
                                    border: Border.all(
                                      color: colors.borderSubtle,
                                    ),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: AppPageStack(
                                    key: ValueKey<int>(_draftGeneration),
                                    index: _activeTabIndex,
                                    itemCount: _tabBuilders.length,
                                    itemBuilder: (context, index) =>
                                        _tabBuilders[index](),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          _buildFloatingSaveBar(context, isNarrow: true),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 1. 左侧无框画布导航栏 (零竖向硬分隔线)
                          _buildSidebar(context),

                          // 2. 右侧圆润白底主卡片 (与主工作台圆润视觉统一)
                          Expanded(
                            child: Container(
                              margin: const EdgeInsets.fromLTRB(0, 8, 8, 8),
                              decoration: BoxDecoration(
                                color: colors.cardBackground,
                                borderRadius: BorderRadius.circular(
                                  AppRadius.xl,
                                ),
                                border: Border.all(color: colors.borderSubtle),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Stack(
                                children: [
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      _buildContentHeader(
                                        context,
                                        isNarrow: false,
                                      ),
                                      Expanded(
                                        child: AppPageStack(
                                          key: ValueKey<int>(_draftGeneration),
                                          index: _activeTabIndex,
                                          itemCount: _tabBuilders.length,
                                          itemBuilder: (context, index) =>
                                              _tabBuilders[index](),
                                        ),
                                      ),
                                    ],
                                  ),
                                  _buildFloatingSaveBar(
                                    context,
                                    isNarrow: false,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 窄屏顶部横向滚动分类胶囊栏 (无分隔线，直接融入柔和画布底)
  Widget _buildHorizontalTabs(BuildContext context) {
    final l10n = context.l10n;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: AppSegmentedPillBar<int>(
        scrollable: true,
        variant: AppPillVariant.soft,
        selectedValue: _activeTabIndex,
        onValueChanged: (index) => setState(() => _activeTabIndex = index),
        items: [
          for (var i = 0; i < _settingsTabIcons.length; i++)
            AppSegmentedItem<int>(
              value: i,
              label: _settingsTabLabel(l10n, i),
              icon: _settingsTabIcons[i],
            ),
        ],
      ),
    );
  }

  /// 左侧导航栏 (融入 canvasBackground，无硬分隔线与边框)
  Widget _buildSidebar(BuildContext context) {
    final l10n = context.l10n;
    return SizedBox(
      width: 212,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
            child: _SettingsBackBar(
              title: l10n.settings,
              tooltip: l10n.close,
              onTap: () => Navigator.of(context).pop(),
            ),
          ),

          // 导航选项卡 (与窄屏顶部胶囊栏共用同一份分类清单)
          for (var i = 0; i < _settingsTabIcons.length; i++)
            _buildSidebarItem(
              index: i,
              icon: _settingsTabIcons[i],
              label: _settingsTabLabel(l10n, i),
            ),
        ],
      ),
    );
  }

  Widget _buildSidebarItem({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: AppNavTile(
        title: label,
        icon: icon,
        isSelected: _activeTabIndex == index,
        radius: AppRadius.lg,
        activeBackgroundColor: colors.primaryTint,
        activeBorderColor: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        onTap: () => setState(() => _activeTabIndex = index),
      ),
    );
  }

  /// 右侧顶部开放式标头 (零底部分隔线，移除重复的右上角关闭按钮)
  Widget _buildContentHeader(BuildContext context, {required bool isNarrow}) {
    final colors = context.colors;
    final l10n = context.l10n;
    final title = _settingsTabLabel(l10n, _activeTabIndex);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        isNarrow ? 12 : 32,
        isNarrow ? 10 : 22,
        isNarrow ? 12 : 32,
        isNarrow ? 8 : 10,
      ),
      child: Row(
        children: [
          if (isNarrow)
            Expanded(
              child: _SettingsBackBar(
                title: title,
                tooltip: l10n.close,
                fontSize: 18,
                iconSize: 18,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                onTap: () => Navigator.of(context).pop(),
              ),
            )
          else
            Expanded(
              child: AppTextSwap(
                text: title,
                distance: AppMotionDistances.micro,
                enableBlur: false,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                  letterSpacing: -0.3,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 按需浮现的右下角悬浮保存胶囊：仅存在未保存更改时平滑弹出，无更改时彻底隐藏。
  Widget _buildFloatingSaveBar(BuildContext context, {required bool isNarrow}) {
    final colors = context.colors;
    final l10n = context.l10n;
    final duration = AppMotion.resolveDuration(
      context,
      AppMotionDurations.fast,
    );

    return Positioned(
      right: isNarrow ? 20 : 28,
      bottom: isNarrow ? 20 : 22,
      child: ValueListenableBuilder<int>(
        valueListenable: _draftRevision,
        builder: (context, _, _) {
          final hasChanges = _hasUnsavedChanges();
          return IgnorePointer(
            ignoring: !hasChanges,
            child: AnimatedSlide(
              duration: duration,
              curve: AppMotionCurves.smoothOut,
              offset: hasChanges ? Offset.zero : const Offset(0, 0.35),
              child: AnimatedOpacity(
                duration: duration,
                curve: AppMotionCurves.smoothOut,
                opacity: hasChanges ? 1.0 : 0.0,
                child: Container(
                  key: const ValueKey('settings_floating_save_bar'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: colors.cardBackground,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    border: Border.all(color: colors.borderDefault),
                    boxShadow: context.shadowElevated,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppActionButton(
                        label: l10n.settingsDiscardChanges,
                        variant: AppActionButtonVariant.ghost,
                        radius: AppRadius.pill,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 9,
                        ),
                        onPressed: hasChanges ? _handleDiscardChanges : null,
                      ),
                      const SizedBox(width: 6),
                      AppActionButton(
                        label: l10n.settingsSaveButton,
                        variant: AppActionButtonVariant.primary,
                        radius: AppRadius.pill,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 9,
                        ),
                        onPressed: hasChanges ? _handleSave : null,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 整行可点击的设置页返回标题条：热区覆盖箭头与文字整条区域，图标与中文字形视觉居中对齐
class _SettingsBackBar extends StatefulWidget {
  final String title;
  final String tooltip;
  final VoidCallback onTap;
  final double fontSize;
  final double iconSize;
  final EdgeInsetsGeometry padding;

  const _SettingsBackBar({
    required this.title,
    required this.tooltip,
    required this.onTap,
    this.fontSize = 15,
    this.iconSize = 17,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
  });

  @override
  State<_SettingsBackBar> createState() => _SettingsBackBarState();
}

class _SettingsBackBarState extends State<_SettingsBackBar> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Semantics(
      container: true,
      button: true,
      label: widget.tooltip,
      child: Tooltip(
        message: widget.tooltip,
        excludeFromSemantics: true,
        child: Material(
          color: Colors.transparent,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _isHovered = true),
            onExit: (_) => setState(() => _isHovered = false),
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              hoverColor: Colors.transparent,
              splashColor: colors.primaryTint.withValues(alpha: 0.3),
              child: Container(
                padding: widget.padding,
                decoration: BoxDecoration(
                  color: _isHovered
                      ? colors.mutedBackground.withValues(alpha: 0.7)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child: AppIconLabel(
                  leading: Icon(
                    Icons.arrow_back_rounded,
                    size: widget.iconSize,
                    color: _isHovered
                        ? colors.textPrimary
                        : colors.textSecondary,
                  ),
                  label: widget.title,
                  gap: 10,
                  style: TextStyle(
                    fontSize: widget.fontSize,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
