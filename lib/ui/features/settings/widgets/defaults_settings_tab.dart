import 'package:flutter/material.dart';
import '../../../../data/models/novelai_models.dart';
import '../../../../data/services/config_service.dart';
import '../../../core/context_l10n.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_dropdown.dart';
import '../../../core/widgets/app_number_slider.dart';
import '../../../core/widgets/app_section_header.dart';
import '../../../core/widgets/app_setting_tile.dart';

/// Defaults 页草稿状态 (父级 SettingsDialog 持有，保存时统一聚合)
class DefaultsSettingsDraft {
  DefaultsSettingsDraft(AppConfig config)
    : model = config.defaultModel,
      sampler = config.defaultSampler,
      noiseSchedule = config.defaultNoiseSchedule,
      steps = config.defaultSteps,
      scale = config.defaultScale,
      agentMaxTurns = config.agentMaxTurns;

  NaiModel model;
  NaiSampler sampler;
  NoiseSchedule noiseSchedule;
  int steps;
  double scale;

  /// Agent 单次对话最大工具调用轮数 (1..100)
  int agentMaxTurns;
}

/// Defaults 页：启动出厂默认生图模型、采样算法与步数引导
///
/// 阶段 3 垂直切片：旧 SettingsCard/SettingsDropdown/步进器/散落 Slider
/// 全部替换为原子组件 (AppSettingTile + AppDropdown + AppNumberSlider)。
class DefaultsSettingsTab extends StatefulWidget {
  final DefaultsSettingsDraft draft;

  const DefaultsSettingsTab({super.key, required this.draft});

  @override
  State<DefaultsSettingsTab> createState() => _DefaultsSettingsTabState();
}

class _DefaultsSettingsTabState extends State<DefaultsSettingsTab> {
  DefaultsSettingsDraft get _draft => widget.draft;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 8, 28, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeader(title: l10n.settingsSectionModelAndSampler),
          AppSettingTile(
            title: l10n.settingsDefaultModelTitle,
            subtitle: l10n.settingsDefaultModelSubtitle,
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
            subtitle: l10n.settingsDefaultSamplerSubtitle,
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
            subtitle: l10n.settingsDefaultNoiseScheduleSubtitle,
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
            subtitle: l10n.settingsDefaultStepsSubtitle,
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
            subtitle: l10n.settingsDefaultScaleSubtitle(
              _draft.scale.toStringAsFixed(1),
            ),
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
          AppSectionHeader(title: l10n.settingsSectionAgentLoop),
          AppSettingTile(
            title: l10n.settingsAgentMaxTurnsTitle,
            subtitle: l10n.settingsAgentMaxTurnsSubtitle,
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
  }
}
