import 'dart:io';

import 'package:flutter/material.dart';
import '../../../../data/models/prompt_library_models.dart';
import '../../../../data/services/prompt_image_probe.dart';
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

    return AppAutocompletePanel<PromptComboEntry>(
      items: entries,
      selectedIndex: selectedIndex,
      maxHeight: rowHeight * maxVisibleRows + 8,
      padding: const EdgeInsets.all(4),
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

        return Container(
          height: rowHeight,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected ? colors.primaryTint : null,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            children: [
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
                    color: isSelected ? colors.primary : colors.textPrimary,
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
        borderRadius: BorderRadius.circular(AppRadius.sm + 2),
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
            gaplessPlayback: true,
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
        color: colors.primaryTint,
        borderRadius: BorderRadius.circular(AppRadius.sm + 2),
      ),
      child: Icon(Icons.person_outline_rounded, size: 14, color: colors.primary),
    );
  }
}
