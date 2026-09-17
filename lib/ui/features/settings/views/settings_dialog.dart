import 'package:flutter/material.dart';
import '../../../../data/services/config_service.dart';
import '../../../core/context_l10n.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_nav_tile.dart';
import '../../../core/widgets/app_page_stack.dart';
import '../../../core/widgets/app_segmented_controls.dart';
import '../../../../l10n/app_localizations.dart';
import '../../studio/view_models/studio_view_model.dart';
import '../widgets/bill_settings_tab.dart';
import '../widgets/defaults_settings_tab.dart';
import '../widgets/general_settings_tab.dart';
import '../widgets/image_save_template_settings.dart';
import '../widgets/models_settings_tab.dart';
import '../widgets/presets_settings_tab.dart';

/// 全局设置弹窗：左侧导航 + 右侧配置详情 + 底部保存栏
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
    final route = DialogRoute<AppConfig>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
      builder: (ctx) => SettingsDialog(viewModel: viewModel),
    );
    final config = await navigator.push<AppConfig>(route);
    // pop completes before the outgoing dialog is removed. Applying locale or
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
    Icons.layers_outlined,
    Icons.receipt_long_outlined,
  ];

  /// 分类文案 l10n 取词 (索引与 [_settingsTabIcons] 严格对齐)
  static String _settingsTabLabel(AppLocalizations l10n, int index) =>
      switch (index) {
        0 => l10n.settingsTabGeneral,
        1 => l10n.settingsTabModels,
        2 => l10n.settingsTabPresets,
        3 => l10n.settingsTabDefaults,
        4 => l10n.settingsTabBill,
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
      () =>
          PresetsSettingsTab(viewModel: widget.viewModel, draft: _presetsDraft),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(templateError)));
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
      localePreference: _generalDraft.localePreference,
      uiZoom: _generalDraft.uiZoom,
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
      comfyUiEnabled: _generalDraft.comfyUiEnabled,
      comfyUiBaseUrl: _generalDraft.comfyBaseUrlController.text.trim(),
      comfyUiPromptNodeId: _generalDraft.comfyPromptNodeController.text.trim(),
      comfyUiResolutionNodeId: _generalDraft.comfyResolutionNodeController.text
          .trim(),
      comfyUiParamsNodeId: _generalDraft.comfyParamsNodeController.text.trim(),
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

    final dialogWidth = isNarrow
        ? screenSize.width
        : (screenSize.width * 0.8).clamp(520.0, 1600.0);
    final dialogHeight = isNarrow
        ? screenSize.height
        : (screenSize.height * 0.8).clamp(400.0, 1200.0);
    final borderRadius = isNarrow ? 0.0 : 12.0;

    return Dialog(
      backgroundColor: colors.cardBackground,
      insetPadding: isNarrow
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        side: isNarrow
            ? BorderSide.none
            : BorderSide(color: colors.borderDefault),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: SizedBox(
          width: dialogWidth,
          height: dialogHeight,
          child: SafeArea(
            top: isNarrow,
            bottom: isNarrow,
            child: isNarrow
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildContentHeader(context),
                      _buildHorizontalTabs(context),
                      Expanded(
                        child: AppPageStack(
                          index: _activeTabIndex,
                          itemCount: _tabBuilders.length,
                          itemBuilder: (context, index) =>
                              _tabBuilders[index](),
                        ),
                      ),
                      _buildFooter(context),
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 1. 左侧导航栏 (Settings Categories)
                      _buildSidebar(context),

                      // 2. 右侧配置详情内容区
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // 右侧顶部标题栏与关闭按键
                            _buildContentHeader(context),

                            // 懒构建保活，切页只动画绘制层，不逐帧重建表单。
                            Expanded(
                              child: AppPageStack(
                                index: _activeTabIndex,
                                itemCount: _tabBuilders.length,
                                itemBuilder: (context, index) =>
                                    _tabBuilders[index](),
                              ),
                            ),

                            // 右侧底部保存 / 取消操作栏
                            _buildFooter(context),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
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
      width: 200,
      decoration: BoxDecoration(
        color: colors.elevatedBackground,
        border: Border(right: BorderSide(color: colors.borderDefault)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 顶部小标题
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
            child: Text(
              'SETTINGS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: colors.textMuted,
                letterSpacing: 0.8,
              ),
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
  Widget _buildContentHeader(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final (title, subtitle) = switch (_activeTabIndex) {
      0 => (l10n.settingsTabGeneral, l10n.settingsSubtitleGeneral),
      1 => (l10n.settingsTabModels, l10n.settingsSubtitleModels),
      2 => (l10n.settingsTabPresets, l10n.settingsSubtitlePresets),
      3 => (l10n.settingsTabDefaults, l10n.settingsSubtitleDefaults),
      4 => (l10n.settingsTabBill, l10n.settingsSubtitleBill),
      _ => (l10n.settings, ''),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 20, 20, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 13, color: colors.textSecondary),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close_rounded, size: 20, color: colors.textMuted),
            tooltip: l10n.close,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  /// 底部操作栏
  Widget _buildFooter(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.borderDefault)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              l10n.cancel,
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            onPressed: _handleSave,
            child: Text(
              l10n.settingsSaveButton,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
