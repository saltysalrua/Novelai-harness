import 'package:flutter/material.dart';
import '../../../../data/models/llm_cache_config.dart';
import '../../../core/context_l10n.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_dropdown.dart';
import '../../../core/widgets/app_setting_tile.dart';
import '../../../core/widgets/app_transitions.dart';
import 'settings_shared.dart';

/// 模型缓存表单；无业务状态，复用统一设置卡片与下拉组件。
///
/// [embedded] 为 true 时采用 Notion 无框轻底内嵌行布局，避免在弹窗内叠加多层卡片边框。
class ModelCacheSettings extends StatelessWidget {
  final LlmCacheConfig value;
  final ValueChanged<LlmCacheConfig> onChanged;
  final bool embedded;

  const ModelCacheSettings({
    super.key,
    required this.value,
    required this.onChanged,
    this.embedded = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final modeDropdown = AppDropdown<LlmCacheMode>.simple(
      value: value.mode,
      items: LlmCacheMode.values,
      width: 160,
      isExpanded: true,
      labelOf: (mode) => switch (mode) {
        LlmCacheMode.auto => l10n.settingsCacheModeAuto,
        LlmCacheMode.off => l10n.settingsCacheModeOff,
        LlmCacheMode.openai => 'OpenAI',
        LlmCacheMode.anthropic => 'Anthropic',
      },
      onChanged: (mode) => onChanged(value.copyWith(mode: mode)),
    );

    final retentionDropdown = AppDropdown<LlmCacheRetention>.simple(
      value: value.retention,
      items: LlmCacheRetention.values,
      width: 160,
      isExpanded: true,
      labelOf: (retention) => switch (retention) {
        LlmCacheRetention.short => l10n.settingsCacheRetentionShort,
        LlmCacheRetention.long => l10n.settingsCacheRetentionLong,
      },
      onChanged: (retention) =>
          onChanged(value.copyWith(retention: retention)),
    );

    final affinityDropdown = AppDropdown<LlmCacheAffinity>.simple(
      value: value.affinity,
      items: LlmCacheAffinity.values,
      width: 160,
      isExpanded: true,
      labelOf: (affinity) => switch (affinity) {
        LlmCacheAffinity.off => l10n.settingsCacheAffinityOff,
        LlmCacheAffinity.openai => 'OpenAI',
        LlmCacheAffinity.openrouter => 'OpenRouter',
      },
      onChanged: (affinity) =>
          onChanged(value.copyWith(affinity: affinity)),
    );

    if (!embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSettingTile(title: l10n.settingsCacheMode, control: modeDropdown),
          AppPanelReveal(
            visible: value.mode != LlmCacheMode.off,
            enableBlur: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppSettingTile(
                  title: l10n.settingsCacheRetention,
                  control: retentionDropdown,
                ),
                AppSettingTile(
                  title: l10n.settingsCacheAffinity,
                  control: affinityDropdown,
                ),
              ],
            ),
          ),
        ],
      );
    }

    return SettingsSoftContainer(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _EmbeddedRow(label: l10n.settingsCacheMode, control: modeDropdown),
          AppPanelReveal(
            visible: value.mode != LlmCacheMode.off,
            enableBlur: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppSpacing.sm),
                _EmbeddedRow(
                  label: l10n.settingsCacheRetention,
                  control: retentionDropdown,
                ),
                const SizedBox(height: AppSpacing.sm),
                _EmbeddedRow(
                  label: l10n.settingsCacheAffinity,
                  control: affinityDropdown,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmbeddedRow extends StatelessWidget {
  final String label;
  final Widget control;

  const _EmbeddedRow({required this.label, required this.control});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 12.5, color: colors.textPrimary),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        control,
      ],
    );
  }
}
