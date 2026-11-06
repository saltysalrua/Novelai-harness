import 'package:flutter/material.dart';
import '../../../core/context_l10n.dart';
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
    final l10n = context.l10n;
    final params = viewModel.params;
    final isEnabled = params.applyFixedPrompts;

    return AppCard(
      padding: EdgeInsets.zero,
      borderColor: isEnabled
          ? colors.borderDefault
          : colors.borderDefault.withValues(alpha: 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BannedWordsSection(viewModel: viewModel),
          Divider(height: 1, thickness: 1, color: colors.borderSubtle),
          Opacity(
            opacity: isEnabled ? 1.0 : 0.55,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _AffixFieldHeader(
                  badge: l10n.promptsPrefixBadge,
                  title: l10n.affixPrefixTitle,
                ),
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
                _AffixFieldHeader(
                  badge: l10n.promptsSuffixBadge,
                  title: l10n.affixSuffixTitle,
                ),
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
        ],
      ),
    );
  }
}

/// 固定词缀页上的违禁词开关和词表。原文留在编辑框，只在组装请求时去掉。
class _BannedWordsSection extends StatefulWidget {
  final StudioViewModel viewModel;

  const _BannedWordsSection({required this.viewModel});

  @override
  State<_BannedWordsSection> createState() => _BannedWordsSectionState();
}

class _BannedWordsSectionState extends State<_BannedWordsSection> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.viewModel.params.bannedWords,
    );
  }

  @override
  void didUpdateWidget(covariant _BannedWordsSection oldWidget) {
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
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
                    const SizedBox(height: 2),
                    Text(
                      l10n.bannedWordsSubtitle,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.35,
                        color: colors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                enabled ? l10n.charPromptEnabled : l10n.charPromptDisabled,
                style: TextStyle(
                  fontSize: 12,
                  color: enabled ? colors.primary : colors.textMuted,
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
                    value: enabled,
                    activeTrackColor: colors.primary,
                    onChanged: (val) => widget.viewModel.updateParams(
                      params.copyWith(stripBannedWords: val),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (enabled) ...[
            const SizedBox(height: 8),
            TextField(
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
          ],
        ],
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
