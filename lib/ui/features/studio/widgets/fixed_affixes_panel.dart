import 'package:flutter/material.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_badge.dart';
import '../../../core/widgets/app_card.dart';
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
    final colors = context.colors;
    final params = viewModel.params;
    final isEnabled = params.applyFixedPrompts;

    return AppCard(
      padding: EdgeInsets.zero,
      borderColor: isEnabled
          ? colors.borderDefault
          : colors.borderDefault.withValues(alpha: 0.5),
      child: Opacity(
        opacity: isEnabled ? 1.0 : 0.55,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _AffixFieldHeader(badge: 'PREFIX', title: '前置词 (放置于主提示词最前)'),
            Divider(
              height: 1,
              thickness: 1,
              color: colors.borderSubtle,
            ),
            ResizableTextField(
              controller: prefixController,
              onChanged: (val) =>
                  viewModel.updateParams(params.copyWith(prefixPrompt: val)),
              hintText: '<artist>\n0.7::artist_name::, year 2026...',
              defaultHeight: _defaultPrefixHeight,
              initialHeight: viewModel.prefixPromptHeight,
              onHeightChanged: viewModel.updatePrefixPromptHeight,
              minHeight: 44,
              maxHeight: 400,
              resizeTooltip: '拖动调整前置词高度 (双击重置)',
              enableAutocomplete: viewModel.config.enableTagAutocomplete,
              showTranslation: viewModel.config.showTagTranslations,
              style: TextStyle(
                fontSize: 14,
                height: 1.48,
                color: colors.textPrimary,
              ),
              hintStyle: TextStyle(
                fontSize: 13,
                height: 1.48,
                color: colors.textMuted,
              ),
            ),
            const _AffixFieldHeader(badge: 'SUFFIX', title: '后缀词 (放置于主提示词最后)'),
            Divider(
              height: 1,
              thickness: 1,
              color: colors.borderSubtle,
            ),
            ResizableTextField(
              controller: suffixController,
              onChanged: (val) =>
                  viewModel.updateParams(params.copyWith(suffixPrompt: val)),
              hintText: 'very aesthetic, masterpiece...',
              defaultHeight: _defaultSuffixHeight,
              initialHeight: viewModel.suffixPromptHeight,
              onHeightChanged: viewModel.updateSuffixPromptHeight,
              minHeight: 38,
              maxHeight: 300,
              resizeTooltip: '拖动调整后缀词高度 (双击重置)',
              enableAutocomplete: viewModel.config.enableTagAutocomplete,
              showTranslation: viewModel.config.showTagTranslations,
              style: TextStyle(
                fontSize: 14,
                height: 1.48,
                color: colors.textPrimary,
              ),
              hintStyle: TextStyle(
                fontSize: 13,
                height: 1.48,
                color: colors.textMuted,
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
    final colors = context.colors;
    return Container(
      color: colors.elevatedBackground,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Row(
        children: [
          AppBadge(
            label: badge,
            variant: AppBadgeVariant.primary,
            shape: AppBadgeShape.rounded,
            fontSize: 10,
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              title,
              style: TextStyle(fontSize: 12, color: colors.textMuted),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
