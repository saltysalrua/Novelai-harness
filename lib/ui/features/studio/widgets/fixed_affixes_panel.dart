import 'package:flutter/material.dart';
import '../../../core/context_l10n.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_badge.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_tool_chip.dart';
import '../../../core/widgets/app_transitions.dart';
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
    final l10n = context.l10n;
    final params = viewModel.params;
    final isEnabled = params.applyFixedPrompts;

    return AppCard(
      padding: EdgeInsets.zero,
      borderColor: isEnabled
          ? colors.borderDefault
          : colors.borderDefault.withValues(alpha: 0.5),
      child: AnimatedOpacity(
        duration: AppMotion.resolveDuration(
          context,
          AppMotionDurations.quick,
        ),
        curve: AppMotionCurves.smoothOut,
        opacity: isEnabled ? 1.0 : 0.55,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _AffixFieldHeader(badge: l10n.promptsPrefixBadge),
            Divider(height: 1, thickness: 1, color: colors.borderSubtle),
            ResizableTextField(
              controller: prefixController,
              onChanged: (val) => viewModel.updateParams(
                params.copyWith(prefixPrompt: val),
              ),
              hintText: '<artist>\n0.7::artist_name::, year 2026...',
              defaultHeight: _defaultPrefixHeight,
              initialHeight: viewModel.prefixPromptHeight,
              onHeightChanged: viewModel.updatePrefixPromptHeight,
              minHeight: 44,
              maxHeight: 400,
              resizeTooltip: l10n.affixResizePrefixTooltip,
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
            _AffixFieldHeader(badge: l10n.promptsSuffixBadge),
            Divider(height: 1, thickness: 1, color: colors.borderSubtle),
            ResizableTextField(
              controller: suffixController,
              onChanged: (val) => viewModel.updateParams(
                params.copyWith(suffixPrompt: val),
              ),
              hintText: 'very aesthetic, masterpiece...',
              defaultHeight: _defaultSuffixHeight,
              initialHeight: viewModel.suffixPromptHeight,
              onHeightChanged: viewModel.updateSuffixPromptHeight,
              minHeight: 38,
              maxHeight: 300,
              resizeTooltip: l10n.affixResizeSuffixTooltip,
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

/// 排除违禁词独立卡片 (置于提示词管理页底部；只影响返回给 Agent 的参数文本，不影响实际生图)
class BannedWordsCard extends StatefulWidget {
  final StudioViewModel viewModel;

  const BannedWordsCard({super.key, required this.viewModel});

  @override
  State<BannedWordsCard> createState() => _BannedWordsCardState();
}

class _BannedWordsCardState extends State<BannedWordsCard> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.viewModel.params.bannedWords,
    );
  }

  @override
  void didUpdateWidget(covariant BannedWordsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.viewModel.params.bannedWords;
    if (_controller.text != next) {
      _controller.text = next;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final params = widget.viewModel.params;
    final enabled = params.stripBannedWords;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.bannedWordsTitle,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      l10n.bannedWordsSubtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AppToolChip(
                icon: enabled ? Icons.check_rounded : Icons.close_rounded,
                label: enabled
                    ? l10n.charPromptEnabled
                    : l10n.charPromptDisabled,
                isSelected: enabled,
                height: 28,
                radius: 6,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                unselectedBackgroundColor: colors.canvasBackground,
                borderColor: colors.borderDefault,
                onTap: () => widget.viewModel.updateParams(
                  params.copyWith(stripBannedWords: !enabled),
                ),
              ),
            ],
          ),
          AppPanelReveal(
            visible: enabled,
            openDuration: AppMotionDurations.fast,
            closeDuration: AppMotionDurations.quick,
            slideOffset: AppMotionDistances.base,
            enableBlur: false,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextField(
                controller: _controller,
                minLines: 2,
                maxLines: 4,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: colors.textPrimary,
                ),
                decoration: InputDecoration(hintText: l10n.bannedWordsHint),
                onChanged: (val) => widget.viewModel.updateParams(
                  widget.viewModel.params.copyWith(bannedWords: val),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Prefix / Suffix 区块标头 (灰底 + 蓝色徽标)
class _AffixFieldHeader extends StatelessWidget {
  final String badge;

  const _AffixFieldHeader({required this.badge});

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
        ],
      ),
    );
  }
}
