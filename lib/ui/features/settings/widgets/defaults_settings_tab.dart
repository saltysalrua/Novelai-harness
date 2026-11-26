import 'package:flutter/material.dart';
import '../../../../core/harness/presets/agent_preset.dart';
import '../../../../data/models/novelai_models.dart';
import '../../../../data/models/prompt_library_models.dart';
import '../../../../data/services/config_service.dart';
import '../../../core/context_l10n.dart';
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
  DefaultsSettingsDraft(AppConfig config)
    : model = config.defaultModel,
      sampler = config.defaultSampler,
      noiseSchedule = config.defaultNoiseSchedule,
      steps = config.defaultSteps,
      scale = config.defaultScale,
      agentMaxTurns = config.agentMaxTurns,
      compactionEnabled = config.agentCompactionEnabled,
      backgroundCompaction = config.agentBackgroundCompaction,
      persistentImages = config.agentPersistentImages,
      compactionProviderId = config.compactionProviderId,
      compactionModelId = config.compactionModelId,
      inboxOrganizerProviderId = config.inboxOrganizerProviderId,
      inboxOrganizerModelId = config.inboxOrganizerModelId,
      inboxAutoRerunPreview = config.inboxAutoRerunPreview,
      inboxOrganizerExcludedCategories = List<String>.from(
        config.inboxOrganizerExcludedCategories,
      ),
      inboxOrganizerPresetId = config.inboxOrganizerPresetId,
      inboxOrganizerCustomInstructions =
          config.inboxOrganizerCustomInstructions;

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
  String compactionProviderId;
  String compactionModelId;
  String inboxOrganizerProviderId;
  String inboxOrganizerModelId;
  bool inboxAutoRerunPreview;
  List<String> inboxOrganizerExcludedCategories;
  String inboxOrganizerPresetId;
  String inboxOrganizerCustomInstructions;
}

/// Defaults 页：启动出厂默认生图模型、采样算法与步数引导
///
/// 阶段 3 垂直切片：旧 SettingsCard/SettingsDropdown/步进器/散落 Slider
/// 全部替换为原子组件 (AppSettingTile + AppDropdown + AppNumberSlider)。
class DefaultsSettingsTab extends StatefulWidget {
  final DefaultsSettingsDraft draft;

  final List<LlmProviderConfig> Function()? getProviders;
  final List<AgentPreset> Function()? getPresets;

  const DefaultsSettingsTab({
    super.key,
    required this.draft,
    this.getProviders,
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final hPad = constraints.maxWidth > 984
            ? (constraints.maxWidth - 920) / 2
            : (constraints.maxWidth < 560 ? 16.0 : 32.0);
        return SingleChildScrollView(
          controller: _scrollController,
          padding: EdgeInsets.fromLTRB(hPad, 16, hPad, 24),
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
              onChanged: (m) => setState(() => _draft.model = m),
            ),
          ),
          AppSettingTile(
            title: l10n.settingsDefaultSamplerTitle,
            control: AppDropdown.simple(
              value: _draft.sampler,
              items: NaiSampler.values,
              labelOf: (s) => s.label,
              width: 170,
              onChanged: (s) => setState(() => _draft.sampler = s),
            ),
          ),
          AppSettingTile(
            title: l10n.settingsDefaultNoiseScheduleTitle,
            control: AppDropdown.simple(
              value: _draft.noiseSchedule,
              items: NoiseSchedule.values,
              labelOf: (n) => n.label,
              width: 170,
              onChanged: (n) => setState(() => _draft.noiseSchedule = n),
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
              onChanged: (v) => setState(() => _draft.steps = v),
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
              onChanged: (v) => setState(() => _draft.scale = v),
            ),
          ),

          const SizedBox(height: AppSpacing.lg),
          AppSectionHeader(title: l10n.settingsSectionContextManagement),
          AppSettingTile.switchTile(
            title: l10n.settingsAutoCompaction,
            value: _draft.compactionEnabled,
            onChanged: (v) => setState(() => _draft.compactionEnabled = v),
          ),
          AppSettingTile.switchTile(
            title: l10n.settingsBackgroundCompaction,
            value: _draft.backgroundCompaction,
            onChanged: _draft.compactionEnabled
                ? (v) => setState(() => _draft.backgroundCompaction = v)
                : null,
          ),
          AppSettingTile.switchTile(
            title: l10n.settingsAgentPersistentImages,
            value: _draft.persistentImages,
            onChanged: (v) => setState(() => _draft.persistentImages = v),
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
              onChanged: (id) => setState(() {
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
                    setState(() => _draft.compactionModelId = id),
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
              onChanged: (id) => setState(() {
                _draft.inboxOrganizerProviderId = id;
                _draft.inboxOrganizerModelId = '';
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
                onChanged: (id) =>
                    setState(() => _draft.inboxOrganizerModelId = id),
              ),
            ),
          ),
          AppSettingTile.switchTile(
            title: l10n.libraryInboxOrganizerAutoRerunTitle,
            subtitle: l10n.libraryInboxOrganizerAutoRerunSubtitle,
            value: _draft.inboxAutoRerunPreview,
            onChanged: (v) => setState(() => _draft.inboxAutoRerunPreview = v),
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
                setState(
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
                  setState(() => _draft.inboxOrganizerPresetId = id),
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
                contentPadding: const EdgeInsets.all(10),
              ),
              onChanged: (val) =>
                  _draft.inboxOrganizerCustomInstructions = val.trim(),
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
              onChanged: (v) => setState(() => _draft.agentMaxTurns = v),
            ),
          ),
        ],
      ),
    );
      },
    );
  }
}
