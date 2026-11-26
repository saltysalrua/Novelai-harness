import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../data/services/config_service.dart';
import '../../../core/context_l10n.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_action_button.dart';
import '../../../core/widgets/app_icon_button.dart';
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

/// 全局设置整页视图：左侧导航 + 右侧配置详情 + 底部保存栏
///
/// 各标签页持有独立的草稿状态 (Draft)，由本壳统一创建、装配与聚合保存；
/// AppPageStack 首次激活时懒构建标签页，轻量过渡并保留输入与滚动状态。
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

  late final GeneralSettingsDraft _generalDraft;
  late final ModelsSettingsDraft _modelsDraft;
  late final PresetsSettingsDraft _presetsDraft;
  late final DefaultsSettingsDraft _defaultsDraft;

  /// 页面缓存、隐藏页焦点/Ticker 隔离统一由 AppPageStack 管理。
  late final List<Widget Function()> _tabBuilders;

  @override
  void initState() {
    super.initState();
    final cfg = widget.viewModel.config;
    _generalDraft = GeneralSettingsDraft(cfg);
    _modelsDraft = ModelsSettingsDraft(cfg);
    _presetsDraft = PresetsSettingsDraft(cfg);
    _defaultsDraft = DefaultsSettingsDraft(cfg);

    // 每页自行包裹滚动容器 (含原外层 28/8/28/20 内边距)，弹窗壳不再统一包 SingleChildScrollView
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
      ),
      () => BillSettingsTab(viewModel: widget.viewModel),
    ];
  }

  @override
  void dispose() {
    _generalDraft.dispose();
    _modelsDraft.dispose();
    _presetsDraft.dispose();
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
      compactionProviderId: _defaultsDraft.compactionProviderId,
      compactionModelId: _defaultsDraft.compactionModelId,
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
        backgroundColor: colors.cardBackground,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showCustomTitleBar) const CustomTitleBar(),
            Expanded(
              child: SafeArea(
                top: !showCustomTitleBar,
                bottom: isNarrow,
                child: isNarrow
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildContentHeader(context, isNarrow: true),
                          _buildHorizontalTabs(context),
                          Expanded(
                            child: AppPageStack(
                              index: _activeTabIndex,
                              itemCount: _tabBuilders.length,
                              itemBuilder: (context, index) =>
                                  _tabBuilders[index](),
                            ),
                          ),
                          _buildFooter(context, isNarrow: true),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 1. 左侧贯穿导航栏
                          _buildSidebar(context),

                          // 2. 右侧配置详情内容区
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildContentHeader(context, isNarrow: false),
                                Expanded(
                                  child: AppPageStack(
                                    index: _activeTabIndex,
                                    itemCount: _tabBuilders.length,
                                    itemBuilder: (context, index) =>
                                        _tabBuilders[index](),
                                  ),
                                ),
                                _buildFooter(context, isNarrow: false),
                              ],
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

  /// 窄屏顶部横向滚动分类胶囊栏 (复用 AppSegmentedPillBar，与全应用观感一致)
  Widget _buildHorizontalTabs(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;

    return Container(
      decoration: BoxDecoration(
        color: colors.elevatedBackground,
        border: Border(bottom: BorderSide(color: colors.borderDefault)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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

  /// 左侧导航栏
  Widget _buildSidebar(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: colors.elevatedBackground,
        border: Border(right: BorderSide(color: colors.borderDefault)),
      ),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: AppNavTile(
        title: label,
        icon: icon,
        isSelected: _activeTabIndex == index,
        onTap: () => setState(() => _activeTabIndex = index),
      ),
    );
  }

  /// 右侧顶部标头
  Widget _buildContentHeader(BuildContext context, {required bool isNarrow}) {
    final colors = context.colors;
    final l10n = context.l10n;
    final title = _settingsTabLabel(l10n, _activeTabIndex);

    return Container(
      padding: EdgeInsets.fromLTRB(
        isNarrow ? 12 : 32,
        isNarrow ? 12 : 18,
        isNarrow ? 12 : 24,
        12,
      ),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        border: Border(bottom: BorderSide(color: colors.borderSubtle)),
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
          else ...[
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
            AppIconButton(
              icon: Icons.close_rounded,
              size: 30,
              iconSize: 18,
              variant: AppIconButtonVariant.ghost,
              tooltip: l10n.close,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ],
      ),
    );
  }

  /// 底部操作栏
  Widget _buildFooter(BuildContext context, {required bool isNarrow}) {
    final colors = context.colors;
    final l10n = context.l10n;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isNarrow ? 16 : 32,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        border: Border(top: BorderSide(color: colors.borderSubtle)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          AppActionButton(
            label: l10n.cancel,
            variant: AppActionButtonVariant.ghost,
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 10),
          AppActionButton(
            label: l10n.settingsSaveButton,
            variant: AppActionButtonVariant.primary,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            onPressed: _handleSave,
          ),
        ],
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
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
              borderRadius: BorderRadius.circular(AppRadius.md),
              hoverColor: Colors.transparent,
              splashColor: colors.primaryTint.withValues(alpha: 0.3),
              child: Container(
                padding: widget.padding,
                decoration: BoxDecoration(
                  color: _isHovered
                      ? colors.mutedBackground.withValues(alpha: 0.7)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.md),
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
