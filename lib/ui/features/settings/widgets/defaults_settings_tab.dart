import 'package:flutter/material.dart';
import '../../../../core/harness/presets/agent_preset.dart';
import '../../../../data/models/novelai_models.dart';
import '../../../../data/models/prompt_library_models.dart';
import '../../../../data/services/config_service.dart';
import '../../../core/context_l10n.dart';
import '../../../core/l10n/model_label_l10n.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_dropdown.dart';
import '../../../core/widgets/app_number_slider.dart';
import '../../../core/widgets/app_section_header.dart';
import '../../../core/widgets/app_setting_tile.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/app_transitions.dart';
import '../../../core/widgets/smooth_scroll_controller.dart';
import '../../studio/widgets/prompt_inbox_organizer_panel.dart';
import 'settings_shared.dart';

/// Defaults 页草稿状态 (父级 SettingsDialog 持有，保存时统一聚合)
class DefaultsSettingsDraft {
  DefaultsSettingsDraft(AppConfig config, {this.onChanged})
    : model = config.defaultModel,
      sampler = config.defaultSampler,
      noiseSchedule = config.defaultNoiseSchedule,
      steps = config.defaultSteps,
      scale = config.defaultScale,
      agentMaxTurns = config.agentMaxTurns,
      compactionEnabled = config.agentCompactionEnabled,
      backgroundCompaction = config.agentBackgroundCompaction,
      persistentImages = config.agentPersistentImages,
      retainedHistoryImages = config.agentRetainedHistoryImages,
      compactionProviderId = config.compactionProviderId,
      compactionModelId = config.compactionModelId,
      inboxOrganizerProviderId = config.inboxOrganizerProviderId,
      inboxOrganizerModelId = config.inboxOrganizerModelId,
      inboxOrganizerThinkingEffort = config.inboxOrganizerThinkingEffort,
      inboxAutoRerunPreview = config.inboxAutoRerunPreview,
      inboxOrganizerExcludedCategories = List<String>.from(
        config.inboxOrganizerExcludedCategories,
      ),
      inboxOrganizerPresetId = config.inboxOrganizerPresetId,
      inboxOrganizerCustomInstructions =
          config.inboxOrganizerCustomInstructions;

  final VoidCallback? onChanged;

  void notifyChanged() => onChanged?.call();

  NaiModel model;
  NaiSampler sampler;
  NoiseSchedule noiseSchedule;
  int steps;
  double scale;

  /// Agent 单次对话最大工具调用轮数 (1..100)
  int agentMaxTurns;
  bool compactionEnabled;
  bool backgroundCompaction;
  bool persistentImages;
  int retainedHistoryImages;
  String compactionProviderId;
  String compactionModelId;
  String inboxOrganizerProviderId;
  String inboxOrganizerModelId;
  String inboxOrganizerThinkingEffort;
  bool inboxAutoRerunPreview;
  List<String> inboxOrganizerExcludedCategories;
  String inboxOrganizerPresetId;
  String inboxOrganizerCustomInstructions;
}

enum _ImageRetentionMode { perTurn, recentCache, always }

/// Defaults 页：启动出厂默认生图模型、采样算法与步数引导
///
/// 阶段 3 垂直切片：旧 SettingsCard/SettingsDropdown/步进器/散落 Slider
/// 全部替换为原子组件 (AppSettingTile + AppDropdown + AppNumberSlider)。
class DefaultsSettingsTab extends StatefulWidget {
  final DefaultsSettingsDraft draft;

  final List<LlmProviderConfig> Function()? getProviders;
  final String Function()? getActiveProviderId;
  final List<AgentPreset> Function()? getPresets;

  const DefaultsSettingsTab({
    super.key,
    required this.draft,
    this.getProviders,
    this.getActiveProviderId,
    this.getPresets,
  });

  @override
  State<DefaultsSettingsTab> createState() => _DefaultsSettingsTabState();
}

class _DefaultsSettingsTabState extends State<DefaultsSettingsTab> {
  DefaultsSettingsDraft get _draft => widget.draft;
  late final SmoothWheelScrollController _scrollController =
      SmoothWheelScrollController();
  late final TextEditingController _organizerInstructionsController =
      TextEditingController(text: _draft.inboxOrganizerCustomInstructions);

  void _mutateDraft(VoidCallback fn) {
    setState(fn);
    _draft.notifyChanged();
  }

  /// 解析当前实际用于后台整理的模型配置（未指定时回落到当前主模型）。
  LlmModelConfig? _resolveEffectiveOrganizerModel(
    List<LlmProviderConfig> providers,
  ) {
    if (providers.isEmpty) return null;
    final providerId = _draft.inboxOrganizerProviderId.trim();
    final modelId = _draft.inboxOrganizerModelId.trim();
    if (providerId.isNotEmpty && modelId.isNotEmpty) {
      final matchedProvider = providers
          .where((p) => p.id == providerId)
          .firstOrNull;
      final matchedModel = matchedProvider?.models
          .where((m) => m.id == modelId)
          .firstOrNull;
      if (matchedModel != null) return matchedModel;
    }
    final activeProviderId = widget.getActiveProviderId?.call() ?? '';
    final activeProvider = providers
        .where((p) => p.id == activeProviderId)
        .firstOrNull ??
        providers.first;
    return activeProvider.activeModel;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _organizerInstructionsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.colors;
    final providers =
        widget.getProviders?.call() ?? const <LlmProviderConfig>[];
    final presets = widget.getPresets?.call() ?? const <AgentPreset>[];
    final validOrganizerPresetId =
        presets.any((p) => p.id == _draft.inboxOrganizerPresetId)
        ? _draft.inboxOrganizerPresetId
        : '';
    final summaryProvider = providers
        .where((p) => p.id == _draft.compactionProviderId)
        .firstOrNull;
    final models = summaryProvider?.models ?? const <LlmModelConfig>[];
    final organizerProvider = providers
        .where((p) => p.id == _draft.inboxOrganizerProviderId)
        .firstOrNull;
    final organizerModels =
        organizerProvider?.models ?? const <LlmModelConfig>[];
    final effectiveOrganizerModel = _resolveEffectiveOrganizerModel(providers);
    final organizerThinkingLevels =
        effectiveOrganizerModel?.availableThinkingLevels ??
        const <ThinkingEffort>[];
    final validOrganizerEffortId =
        organizerThinkingLevels.any(
          (level) => level.id == _draft.inboxOrganizerThinkingEffort,
        )
        ? _draft.inboxOrganizerThinkingEffort
        : '';
    final defaultEffortLabel = effectiveOrganizerModel != null &&
            effectiveOrganizerModel.supportsThinking
        ? '${l10n.libraryInboxOrganizerThinkingEffortDefault} (${thinkingEffortLabelOf(l10n, effectiveOrganizerModel.defaultThinkingEffort)})'
        : l10n.libraryInboxOrganizerThinkingEffortDefault;
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
          AppSectionHeader(title: l10n.settingsSectionModelAndSampler),
          AppSettingTile(
            title: l10n.settingsDefaultModelTitle,
            control: AppDropdown.simple(
              value: _draft.model,
              items: NaiModel.values,
              labelOf: (m) => m.label,
              width: 170,
              onChanged: (m) => _mutateDraft(() => _draft.model = m),
            ),
          ),
          AppSettingTile(
            title: l10n.settingsDefaultSamplerTitle,
            control: AppDropdown.simple(
              value: _draft.sampler,
              items: NaiSampler.values,
              labelOf: (s) => s.label,
              width: 170,
              onChanged: (s) => _mutateDraft(() => _draft.sampler = s),
            ),
          ),
          AppSettingTile(
            title: l10n.settingsDefaultNoiseScheduleTitle,
            control: AppDropdown.simple(
              value: _draft.noiseSchedule,
              items: NoiseSchedule.values,
              labelOf: (n) => n.label,
              width: 170,
              onChanged: (n) => _mutateDraft(() => _draft.noiseSchedule = n),
            ),
          ),

          const SizedBox(height: AppSpacing.lg),
          AppSectionHeader(title: l10n.settingsSectionDefaultStepsAndScale),
          AppSettingTile(
            title: l10n.settingsDefaultStepsTitle,
            control: const SizedBox.shrink(),
            bottomChild: AppNumberSlider.integer(
              value: _draft.steps,
              min: 1,
              max: 50,
              onChanged: (v) => _mutateDraft(() => _draft.steps = v),
            ),
          ),
          AppSettingTile(
            title: l10n.settingsDefaultScaleTitle,
            control: const SizedBox.shrink(),
            bottomChild: AppNumberSlider(
              value: _draft.scale,
              min: 1.0,
              max: 20.0,
              fractionDigits: 1,
              step: 0.5,
              onChanged: (v) => _mutateDraft(() => _draft.scale = v),
            ),
          ),

          const SizedBox(height: AppSpacing.lg),
          AppSectionHeader(title: l10n.settingsSectionContextManagement),
          AppSettingTile.switchTile(
            title: l10n.settingsAutoCompaction,
            value: _draft.compactionEnabled,
            onChanged: (v) => _mutateDraft(() => _draft.compactionEnabled = v),
          ),
          AppSettingTile.switchTile(
            title: l10n.settingsBackgroundCompaction,
            value: _draft.backgroundCompaction,
            onChanged: _draft.compactionEnabled
                ? (v) => _mutateDraft(() => _draft.backgroundCompaction = v)
                : null,
          ),
          AppSettingTile(
            title: l10n.settingsAgentImageRetentionTitle,
            control: AppDropdown<_ImageRetentionMode>.simple(
              value: _draft.persistentImages
                  ? _ImageRetentionMode.always
                  : (_draft.retainedHistoryImages > 0
                        ? _ImageRetentionMode.recentCache
                        : _ImageRetentionMode.perTurn),
              items: _ImageRetentionMode.values,
              width: 190,
              labelOf: (mode) => switch (mode) {
                _ImageRetentionMode.perTurn =>
                  l10n.settingsAgentImageRetentionPerTurn,
                _ImageRetentionMode.recentCache =>
                  l10n.settingsAgentImageRetentionRecentCache,
                _ImageRetentionMode.always =>
                  l10n.settingsAgentImageRetentionAlways,
              },
              onChanged: (mode) => _mutateDraft(() {
                switch (mode) {
                  case _ImageRetentionMode.perTurn:
                    _draft.persistentImages = false;
                    _draft.retainedHistoryImages = 0;
                  case _ImageRetentionMode.recentCache:
                    _draft.persistentImages = false;
                    if (_draft.retainedHistoryImages <= 0) {
                      _draft.retainedHistoryImages = 3;
                    }
                  case _ImageRetentionMode.always:
                    _draft.persistentImages = true;
                }
              }),
            ),
          ),
          AppPanelReveal(
            visible:
                !_draft.persistentImages && _draft.retainedHistoryImages > 0,
            enableBlur: false,
            child: AppSettingTile(
              title: l10n.settingsAgentRetainedImageCountTitle,
              control: const SizedBox.shrink(),
              bottomChild: AppNumberSlider.integer(
                value: _draft.retainedHistoryImages.clamp(1, 10),
                min: 1,
                max: 10,
                onChanged: (v) =>
                    _mutateDraft(() => _draft.retainedHistoryImages = v),
              ),
            ),
          ),
          AppSettingTile(
            title: l10n.settingsCompactionProvider,
            control: AppDropdown.simple(
              value: summaryProvider?.id ?? '',
              items: ['', ...providers.map((p) => p.id)],
              width: 170,
              labelOf: (id) => id.isEmpty
                  ? l10n.settingsFollowMainModel
                  : providers.firstWhere((p) => p.id == id).name,
              onChanged: (id) => _mutateDraft(() {
                _draft.compactionProviderId = id;
                _draft.compactionModelId = '';
              }),
            ),
          ),
          AppPanelReveal(
            visible: summaryProvider != null,
            enableBlur: false,
            child: AppSettingTile(
              title: l10n.settingsCompactionModel,
              control: AppDropdown.simple(
                value: models.any((m) => m.id == _draft.compactionModelId)
                    ? _draft.compactionModelId
                    : '',
                items: ['', ...models.map((m) => m.id)],
                width: 170,
                labelOf: (id) => id.isEmpty
                    ? l10n.settingsFollowMainModel
                    : models.firstWhere((m) => m.id == id).name,
                onChanged: (id) =>
                    _mutateDraft(() => _draft.compactionModelId = id),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppSectionHeader(title: l10n.settingsSectionInboxOrganizer),
          AppSettingTile(
            title: l10n.libraryInboxOrganizerProviderTitle,
            control: AppDropdown.simple(
              value: organizerProvider?.id ?? '',
              items: ['', ...providers.map((p) => p.id)],
              width: 170,
              labelOf: (id) => id.isEmpty
                  ? l10n.settingsFollowMainModel
                  : providers.firstWhere((p) => p.id == id).name,
              onChanged: (id) => _mutateDraft(() {
                _draft.inboxOrganizerProviderId = id;
                _draft.inboxOrganizerModelId = '';
                _draft.inboxOrganizerThinkingEffort = '';
              }),
            ),
          ),
          AppPanelReveal(
            visible: organizerProvider != null,
            enableBlur: false,
            child: AppSettingTile(
              title: l10n.libraryInboxOrganizerModelTitle,
              control: AppDropdown.simple(
                value:
                    organizerModels.any(
                      (m) => m.id == _draft.inboxOrganizerModelId,
                    )
                    ? _draft.inboxOrganizerModelId
                    : '',
                items: ['', ...organizerModels.map((m) => m.id)],
                width: 170,
                labelOf: (id) => id.isEmpty
                    ? l10n.settingsFollowMainModel
                    : organizerModels.firstWhere((m) => m.id == id).name,
                onChanged: (id) => _mutateDraft(() {
                  _draft.inboxOrganizerModelId = id;
                  final nextModel = _resolveEffectiveOrganizerModel(providers);
                  if (nextModel == null ||
                      !nextModel.availableThinkingLevels.any(
                        (e) => e.id == _draft.inboxOrganizerThinkingEffort,
                      )) {
                    _draft.inboxOrganizerThinkingEffort = '';
                  }
                }),
              ),
            ),
          ),
          AppPanelReveal(
            visible: organizerThinkingLevels.isNotEmpty,
            enableBlur: false,
            child: AppSettingTile(
              title: l10n.libraryInboxOrganizerThinkingEffortTitle,
              control: AppDropdown<String>.simple(
                value: validOrganizerEffortId,
                items: ['', ...organizerThinkingLevels.map((e) => e.id)],
                width: 170,
                labelOf: (id) => id.isEmpty
                    ? defaultEffortLabel
                    : thinkingEffortLabelOf(l10n, ThinkingEffort.fromId(id)),
                onChanged: (id) => _mutateDraft(
                  () => _draft.inboxOrganizerThinkingEffort = id,
                ),
              ),
            ),
          ),
          AppSettingTile.switchTile(
            title: l10n.libraryInboxOrganizerAutoRerunTitle,
            subtitle: l10n.libraryInboxOrganizerAutoRerunSubtitle,
            value: _draft.inboxAutoRerunPreview,
            onChanged: (v) =>
                _mutateDraft(() => _draft.inboxAutoRerunPreview = v),
          ),
          AppSettingTile(
            title: l10n.libraryInboxOrganizerCategoriesTitle,
            subtitle: l10n.libraryInboxOrganizerCategoriesHint,
            control: const SizedBox.shrink(),
            bottomChild: PromptOrganizerCategorySelector(
              excludedCategories: _draft.inboxOrganizerExcludedCategories
                  .toSet(),
              onToggleCategory: (category) {
                final next = _draft.inboxOrganizerExcludedCategories.toSet();
                if (next.contains(category)) {
                  next.remove(category);
                } else {
                  final remaining = PromptComboCategories.defaults
                      .where((c) => !next.contains(c) && c != category)
                      .length;
                  if (remaining == 0) {
                    showAppToast(
                      context,
                      message: l10n.libraryInboxOrganizerAtLeastOneCategory,
                      tone: AppToastTone.warning,
                    );
                    return;
                  }
                  next.add(category);
                }
                _mutateDraft(
                  () => _draft.inboxOrganizerExcludedCategories = next.toList(
                    growable: false,
                  ),
                );
              },
            ),
          ),
          AppSettingTile(
            title: l10n.libraryInboxOrganizerPresetTitle,
            control: AppDropdown.simple(
              value: validOrganizerPresetId,
              items: ['', ...presets.map((p) => p.id)],
              width: 170,
              labelOf: (id) => id.isEmpty
                  ? l10n.libraryInboxOrganizerPresetDefault
                  : presets.firstWhere((p) => p.id == id).name,
              onChanged: (id) =>
                  _mutateDraft(() => _draft.inboxOrganizerPresetId = id),
            ),
          ),
          AppSettingTile(
            title: l10n.libraryInboxOrganizerCustomInstructionsTitle,
            control: const SizedBox.shrink(),
            bottomChild: TextField(
              controller: _organizerInstructionsController,
              minLines: 2,
              maxLines: 5,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: colors.textPrimary,
              ),
              decoration: settingsSoftInputDecoration(
                context,
                hintText: l10n.libraryInboxOrganizerCustomInstructionsHint,
                fillColor: colors.cardBackground,
                contentPadding: const EdgeInsets.all(10),
              ),
              onChanged: (val) {
                _draft.inboxOrganizerCustomInstructions = val.trim();
                _draft.notifyChanged();
              },
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppSectionHeader(title: l10n.settingsSectionAgentLoop),
          AppSettingTile(
            title: l10n.settingsAgentMaxTurnsTitle,
            control: const SizedBox.shrink(),
            bottomChild: AppNumberSlider.integer(
              value: _draft.agentMaxTurns,
              min: 1,
              max: 100,
              onChanged: (v) => _mutateDraft(() => _draft.agentMaxTurns = v),
            ),
          ),
        ],
      ),
    );
      },
    );
  }
}
