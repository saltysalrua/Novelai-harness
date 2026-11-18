import 'package:flutter/material.dart';

import '../../../../data/models/novelai_models.dart';
import '../../../core/context_l10n.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_dropdown.dart';
import '../../../core/widgets/app_tool_chip.dart';
import '../view_models/studio_view_model.dart';

/// 将内部质量词 / UC 预设键映射为本地化展示名称。
String promptPresetLabel(BuildContext context, String preset) =>
    switch (preset.toLowerCase()) {
      'standard' => context.l10n.presetLevelStandard,
      'light' => context.l10n.presetLevelLight,
      'heavy' => context.l10n.presetLevelHeavy,
      'human' || 'human focus' => context.l10n.presetLevelHuman,
      'none' || 'off' => context.l10n.presetLevelNone,
      _ => preset,
    };

/// 返回当前模型下有效的质量词预设键，不存在时回退为 `Standard`。
String resolveQualityPreset(NaiGenerationParams params) {
  final presets = NovelAiQualityTagsHelper.getAvailablePresets(params.model);
  return presets.contains(params.qualityPreset)
      ? params.qualityPreset
      : 'Standard';
}

/// 应用质量词预设并同步 qualityToggle 开关状态。
void applyPromptQualityPreset(StudioViewModel viewModel, String presetKey) {
  viewModel.updateParams(
    viewModel.params.copyWith(
      qualityPreset: presetKey,
      qualityToggle: presetKey != 'None',
    ),
  );
}

/// 应用官方 UC 排除词预设。
void applyPromptUcPreset(StudioViewModel viewModel, String presetKey) {
  viewModel.updateParams(viewModel.params.copyWith(ucPresetKey: presetKey));
}

/// 切换透明背景开关，并清理输入框中残留的 transparent / simple background 字样。
void togglePromptTransparentBg(
  StudioViewModel viewModel,
  TextEditingController promptController,
) {
  final params = viewModel.params;
  var p = promptController.text;
  if (p.contains('transparent background') ||
      p.contains('simple background')) {
    p = p.replaceAll(
      RegExp(r',?\s*transparent background', caseSensitive: false),
      '',
    );
    p = p.replaceAll(
      RegExp(r',?\s*simple background', caseSensitive: false),
      '',
    );
    p = p.replaceAll(RegExp(r',\s*,\s*'), ', ');
    p = p.replaceAll(RegExp(r',\s*$'), '').trim();
    promptController.text = p;
  }
  viewModel.updateParams(
    params.copyWith(prompt: p, transparentBg: !params.transparentBg),
  );
}

/// 正向提示词底部工具条：Transparent BG (仅 V5 模型) + Quality Tags 预设芯片。
/// ComfyUI 模式下质量预设与透明背景均不生效，返回 null。
Widget? buildPositivePromptToolbar(
  BuildContext context,
  StudioViewModel viewModel,
  TextEditingController promptController,
) {
  if (viewModel.isComfyUiMode) return null;
  final params = viewModel.params;
  final colors = context.colors;
  final l10n = context.l10n;

  final quality = AppDropdown<String>.simple(
    value: resolveQualityPreset(params),
    items: NovelAiQualityTagsHelper.getAvailablePresets(params.model),
    labelOf: (p) => '${l10n.promptsQualityTags}: ${promptPresetLabel(context, p)}',
    variant: AppDropdownVariant.chip,
    isExpanded: false,
    onChanged: (preset) => applyPromptQualityPreset(viewModel, preset),
  );
  final transparent = AppToolChip(
    isSelected: params.transparentBg,
    icon: params.transparentBg ? Icons.check_rounded : Icons.close_rounded,
    label: l10n.promptsTransparentBackground,
    height: 28,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    unselectedBackgroundColor: colors.canvasBackground,
    borderColor: colors.borderDefault,
    onTap: () => togglePromptTransparentBg(viewModel, promptController),
  );
  return Wrap(
    alignment: WrapAlignment.end,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 6,
    runSpacing: 6,
    children: [if (params.model.isV5) transparent, quality],
  );
}

/// 负面提示词底部工具条：UC Preset 预设芯片。
/// ComfyUI 模式与节约档模式下不生效，返回 null。
Widget? buildNegativePromptToolbar(
  BuildContext context,
  StudioViewModel viewModel,
) {
  final params = viewModel.params;
  if (viewModel.isComfyUiMode || params.isMediumEffort) return null;
  final presets = NovelAiUndesiredContentHelper.availablePresets;
  return Align(
    alignment: Alignment.centerRight,
    child: AppDropdown<String>.simple(
      value: presets.contains(params.ucPresetKey)
          ? params.ucPresetKey
          : presets.first,
      items: presets,
      labelOf: (p) =>
          '${context.l10n.promptsUcPreset}: ${promptPresetLabel(context, p)}',
      variant: AppDropdownVariant.chip,
      isExpanded: false,
      onChanged: (preset) => applyPromptUcPreset(viewModel, preset),
    ),
  );
}
