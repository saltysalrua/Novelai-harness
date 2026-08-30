import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../view_models/studio_view_model.dart';

/// 全局固定词缀面板：总开关 + Prefix / Suffix 前后置词编辑。
/// 在提示词页底部常驻，并以灰底容器形式在编辑卡下方快捷展开。
class FixedAffixesPanel extends StatelessWidget {
  final StudioViewModel viewModel;
  final TextEditingController prefixController;
  final TextEditingController suffixController;

  const FixedAffixesPanel({
    super.key,
    required this.viewModel,
    required this.prefixController,
    required this.suffixController,
  });

  @override
  Widget build(BuildContext context) {
    final params = viewModel.params;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Fixed Affixes',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
                letterSpacing: -0.2,
              ),
            ),
            Row(
              children: [
                Text(
                  params.applyFixedPrompts ? '已启用' : '已停用',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: params.applyFixedPrompts
                        ? AppTheme.notionBlue
                        : AppTheme.textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  height: 22,
                  width: 38,
                  child: FittedBox(
                    fit: BoxFit.fill,
                    child: Switch(
                      value: params.applyFixedPrompts,
                      activeTrackColor: AppTheme.notionBlue,
                      onChanged: (val) => viewModel.updateParams(
                        params.copyWith(applyFixedPrompts: val),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        _AffixField(
          label: 'Prefix (前置词)',
          hintText: '<artist>\n0.7::artist_name::, year 2026...',
          controller: prefixController,
          minLines: 2,
          maxLines: 6,
          onChanged: (val) =>
              viewModel.updateParams(params.copyWith(prefixPrompt: val)),
        ),
        const SizedBox(height: 10),
        _AffixField(
          label: 'Suffix (后缀词)',
          hintText: 'very aesthetic, masterpiece...',
          controller: suffixController,
          minLines: 2,
          maxLines: 4,
          onChanged: (val) =>
              viewModel.updateParams(params.copyWith(suffixPrompt: val)),
        ),
      ],
    );
  }
}

/// 固定词缀输入区 (标签 + 白底输入容器)
class _AffixField extends StatelessWidget {
  final String label;
  final String hintText;
  final TextEditingController controller;
  final int minLines;
  final int maxLines;
  final ValueChanged<String> onChanged;

  const _AffixField({
    required this.label,
    required this.hintText,
    required this.controller,
    required this.minLines,
    required this.maxLines,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.pureWhite,
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            border: Border.all(color: AppTheme.border),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: TextField(
            controller: controller,
            minLines: minLines,
            maxLines: maxLines,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: AppTheme.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: const TextStyle(
                fontSize: 12,
                color: AppTheme.textMuted,
              ),
              contentPadding: EdgeInsets.zero,
              isDense: true,
              border: InputBorder.none,
            ),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
