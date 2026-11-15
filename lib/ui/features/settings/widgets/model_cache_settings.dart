import 'package:flutter/material.dart';
import '../../../../data/models/llm_cache_config.dart';
import '../../../core/context_l10n.dart';
import '../../../core/widgets/app_dropdown.dart';
import '../../../core/widgets/app_setting_tile.dart';

/// 模型缓存表单；无业务状态，复用统一设置卡片与下拉组件。
class ModelCacheSettings extends StatelessWidget {
  final LlmCacheConfig value;
  final ValueChanged<LlmCacheConfig> onChanged;

  const ModelCacheSettings({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSettingTile(
          title: l10n.settingsCacheMode,
          control: AppDropdown<LlmCacheMode>.simple(
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
          ),
        ),
        if (value.mode != LlmCacheMode.off) ...[
          AppSettingTile(
            title: l10n.settingsCacheRetention,
            control: AppDropdown<LlmCacheRetention>.simple(
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
            ),
          ),
          AppSettingTile(
            title: l10n.settingsCacheAffinity,
            control: AppDropdown<LlmCacheAffinity>.simple(
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
            ),
          ),
        ],
      ],
    );
  }
}
