import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../view_models/studio_view_model.dart';
import 'prompt_resize_handle.dart';

/// 全局固定词缀一体化编辑卡内容 (由 PromptExtensionDeck 的 Fixed Affixes 页挂载)。
/// Prefix / Suffix 前后置词编辑区支持独立垂直拖拽调节高度。
class FixedAffixesCardContent extends StatelessWidget {
  final StudioViewModel viewModel;
  final TextEditingController prefixController;
  final TextEditingController suffixController;

  static const double _defaultPrefixHeight = 88.0;
  static const double _defaultSuffixHeight = 64.0;

  const FixedAffixesCardContent({
    super.key,
    required this.viewModel,
    required this.prefixController,
    required this.suffixController,
  });

  @override
  Widget build(BuildContext context) {
    final params = viewModel.params;
    final isEnabled = params.applyFixedPrompts;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.pureWhite,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(
          color: isEnabled
              ? AppTheme.border
              : AppTheme.border.withValues(alpha: 0.5),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Opacity(
        opacity: isEnabled ? 1.0 : 0.55,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _AffixFieldHeader(badge: 'PREFIX', title: '前置词 (放置于主提示词最前)'),
            const Divider(
              height: 1,
              thickness: 1,
              color: AppTheme.borderSubtle,
            ),
            ResizableTextField(
              controller: prefixController,
              onChanged: (val) =>
                  viewModel.updateParams(params.copyWith(prefixPrompt: val)),
              hintText: '<artist>\n0.7::artist_name::, year 2026...',
              defaultHeight: _defaultPrefixHeight,
              minHeight: 44,
              maxHeight: 400,
              resizeTooltip: '拖动调整前置词高度 (双击重置)',
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.48,
                color: AppTheme.textPrimary,
              ),
              hintStyle: const TextStyle(
                fontSize: 13,
                height: 1.48,
                color: AppTheme.textMuted,
              ),
            ),
            _AffixFieldHeader(badge: 'SUFFIX', title: '后缀词 (放置于主提示词最后)'),
            const Divider(
              height: 1,
              thickness: 1,
              color: AppTheme.borderSubtle,
            ),
            ResizableTextField(
              controller: suffixController,
              onChanged: (val) =>
                  viewModel.updateParams(params.copyWith(suffixPrompt: val)),
              hintText: 'very aesthetic, masterpiece...',
              defaultHeight: _defaultSuffixHeight,
              minHeight: 38,
              maxHeight: 300,
              resizeTooltip: '拖动调整后缀词高度 (双击重置)',
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.48,
                color: AppTheme.textPrimary,
              ),
              hintStyle: const TextStyle(
                fontSize: 13,
                height: 1.48,
                color: AppTheme.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Prefix / Suffix 区块标头 (灰底 + 蓝色徽标)
class _AffixFieldHeader extends StatelessWidget {
  final String badge;
  final String title;

  const _AffixFieldHeader({required this.badge, required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.surfaceElevated,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
            decoration: BoxDecoration(
              color: AppTheme.skyTint,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              badge,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppTheme.notionBlue,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
