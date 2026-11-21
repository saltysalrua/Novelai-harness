import 'dart:io';

import 'package:flutter/material.dart';
import '../../../../data/models/prompt_library_models.dart';
import '../../../../data/services/prompt_image_probe.dart';
import '../../../core/context_l10n.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_autocomplete_panel.dart';

/// 悬浮在 Agent 输入框上方的词库角色 `@` 补全面板
class CharacterMentionPanel extends StatelessWidget {
  final List<PromptComboEntry> entries;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final ValueChanged<int>? onHovered;

  const CharacterMentionPanel({
    super.key,
    required this.entries,
    required this.selectedIndex,
    required this.onSelected,
    this.onHovered,
  });

  static const double rowHeight = 40.0;
  static const int maxVisibleRows = 6;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final rowDuration = AppMotion.resolveDuration(
      context,
      AppMotionDurations.micro,
    );

    return AppAutocompletePanel<PromptComboEntry>(
      items: entries,
      selectedIndex: selectedIndex,
      maxHeight: rowHeight * maxVisibleRows + 28,
      padding: const EdgeInsets.only(bottom: 4),
      onSelect: (item) => onSelected(entries.indexOf(item)),
      onHover: onHovered,
      itemBuilder: (context, entry, index, isSelected) {
        final previewPath = entry.previewImagePath?.trim();
        final hasValidPreview =
            previewPath != null &&
            previewPath.isNotEmpty &&
            !PromptImageProbe.isKnownMissing(previewPath);
        final snippet = entry.tags.isNotEmpty
            ? entry.tags.join(', ')
            : entry.prompt;

        final row = AnimatedContainer(
          duration: rowDuration,
          curve: AppMotionCurves.smoothOut,
          height: rowHeight,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          color: isSelected
              ? colors.primary.withValues(alpha: 0.08)
              : colors.primary.withValues(alpha: 0.0),
          child: Row(
            children: [
              AnimatedContainer(
                duration: rowDuration,
                curve: AppMotionCurves.smoothOut,
                width: 3,
                height: 20,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: isSelected ? colors.primary : null,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              _MentionAvatar(
                previewPath: hasValidPreview ? previewPath : null,
              ),
              const SizedBox(width: 8),
              Flexible(
                flex: 3,
                child: Text(
                  entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 4,
                child: Text(
                  snippet,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: colors.textMuted),
                ),
              ),
            ],
          ),
        );

        if (index == 0) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
                child: Text(
                  l10n.chatCharacterMentionHeader,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: colors.textMuted,
                  ),
                ),
              ),
              row,
            ],
          );
        }
        return row;
      },
    );
  }
}

class _MentionAvatar extends StatelessWidget {
  final String? previewPath;

  const _MentionAvatar({required this.previewPath});

  @override
  Widget build(BuildContext context) {
    final path = previewPath;
    if (path != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: SizedBox(
          width: 24,
          height: 24,
          child: Image(
            image: ResizeImage(
              FileImage(File(path)),
              width: 64,
              height: 64,
              policy: ResizeImagePolicy.fit,
            ),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _fallbackIcon(context),
          ),
        ),
      );
    }
    return _fallbackIcon(context);
  }

  Widget _fallbackIcon(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: colors.errorSurface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Icon(Icons.person_outline_rounded, size: 14, color: colors.error),
    );
  }
}
