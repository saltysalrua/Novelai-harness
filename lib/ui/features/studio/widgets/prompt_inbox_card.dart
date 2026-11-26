import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../../data/models/prompt_library_models.dart';
import '../../../../data/services/prompt_image_probe.dart';
import '../../../core/context_l10n.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/context_menu.dart';

/// 词库待整理区瀑布流卡片：
/// 展示暂存图片（按真实比例无裁切）、主提示词摘要、角色提示词数量与快捷整理入口。
class PromptInboxCard extends StatelessWidget {
  static const int _previewDecodeMaxSide = 560;

  final PromptInboxItem item;
  final VoidCallback onInspect;
  final VoidCallback onOrganizeWithAgent;
  final VoidCallback onManualConvert;
  final VoidCallback onDelete;
  final bool loadImage;
  final bool compact;

  const PromptInboxCard({
    super.key,
    required this.item,
    required this.onInspect,
    required this.onOrganizeWithAgent,
    required this.onManualConvert,
    required this.onDelete,
    this.loadImage = true,
    this.compact = false,
  });

  void _copyToClipboard(BuildContext context) {
    final text = item.toCopyableText();
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    showAppToast(
      context,
      message: context.l10n.libraryInboxCopiedPrompt,
      tone: AppToastTone.success,
      duration: const Duration(milliseconds: 1200),
    );
  }

  void _showContextMenu(BuildContext context, Offset position) {
    final l10n = context.l10n;
    showStudioContextMenu(
      context,
      position: position,
      actions: [
        ContextMenuItem(
          icon: Icons.auto_awesome_outlined,
          label: l10n.libraryInboxAskAgentOne,
          onTap: onOrganizeWithAgent,
        ),
        ContextMenuItem(
          icon: Icons.library_add_outlined,
          label: l10n.libraryInboxManualConvert,
          onTap: onManualConvert,
        ),
        const ContextMenuDivider(),
        if (item.toCopyableText().isNotEmpty)
          ContextMenuItem(
            icon: Icons.copy_outlined,
            label: l10n.libraryMenuCopyPrompt,
            onTap: () => _copyToClipboard(context),
          ),
        ContextMenuItem(
          icon: Icons.delete_outline,
          label: l10n.delete,
          isDestructive: true,
          onTap: onDelete,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final rawPath = item.imagePath?.trim();
    final hasImage = rawPath != null && rawPath.isNotEmpty;
    final timeText = DateFormat('MM-dd HH:mm').format(item.createdAt.toLocal());
    final fullText = item.toCopyableText();
    final summary = item.displaySummary;

    return AppCard(
      onTap: onInspect,
      onContextMenu: (pos) => _showContextMenu(context, pos),
      radius: compact ? AppRadius.md : AppRadius.lg,
      borderColor: colors.borderSubtle,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasImage)
            _InboxNaturalImage(
              path: rawPath,
              decodeMaxSide: _previewDecodeMaxSide,
              loadImage: loadImage,
            ),
          Padding(
            padding: compact
                ? const EdgeInsets.fromLTRB(8, 7, 8, 7)
                : const EdgeInsets.fromLTRB(12, 10, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      size: compact ? 11 : 12,
                      color: colors.textMuted,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        timeText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: compact ? 10.5 : 11,
                          fontWeight: FontWeight.w500,
                          color: colors.textMuted,
                        ),
                      ),
                    ),
                    if (item.hasCharacters) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colors.errorSurface,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: Text(
                          l10n.libraryInboxCharacterCount(
                            item.characterPrompts.length,
                          ),
                          style: TextStyle(
                            fontSize: compact ? 9.5 : 10,
                            fontWeight: FontWeight.w600,
                            color: colors.error,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (summary.isNotEmpty) ...[
                  SizedBox(height: compact ? 4 : 6),
                  Tooltip(
                    message: fullText.isNotEmpty ? fullText : summary,
                    child: Text(
                      summary,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: compact ? 10.5 : 11.5,
                        height: compact ? 1.32 : 1.38,
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                ],
                if (item.hasCharacters) ...[
                  const SizedBox(height: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: colors.elevatedBackground,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(color: colors.borderSubtle),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (
                          var i = 0;
                          i < item.characterPrompts.length && i < 2;
                          i++
                        ) ...[
                          if (i > 0) const SizedBox(height: 3),
                          Text(
                            '${item.characterPrompts[i].name.isNotEmpty ? item.characterPrompts[i].name : '#${i + 1}'}: '
                            '${item.characterPrompts[i].prompt}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: compact ? 10 : 10.5,
                              height: 1.3,
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                        if (item.characterPrompts.length > 2) ...[
                          const SizedBox(height: 2),
                          Text(
                            '+${item.characterPrompts.length - 2}',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w600,
                              color: colors.textMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                SizedBox(height: compact ? 6 : 8),
                Row(
                  children: [
                    Expanded(
                      child: _InboxActionPill(
                        icon: Icons.auto_awesome_outlined,
                        label: l10n.libraryInboxAskAgentOne,
                        compact: compact,
                        onTap: onOrganizeWithAgent,
                      ),
                    ),
                    const SizedBox(width: 4),
                    AppIconButton(
                      icon: Icons.library_add_outlined,
                      tooltip: l10n.libraryInboxManualConvert,
                      size: compact ? 26 : 28,
                      iconSize: compact ? 13.5 : 14.5,
                      radius: AppRadius.sm,
                      iconColor: colors.textSecondary,
                      variant: AppIconButtonVariant.ghost,
                      onPressed: onManualConvert,
                    ),
                    if (fullText.isNotEmpty) ...[
                      const SizedBox(width: 2),
                      AppIconButton(
                        icon: Icons.copy_outlined,
                        tooltip: l10n.libraryMenuCopyPrompt,
                        size: compact ? 26 : 28,
                        iconSize: compact ? 13.5 : 14.5,
                        radius: AppRadius.sm,
                        iconColor: colors.textSecondary,
                        variant: AppIconButtonVariant.ghost,
                        onPressed: () => _copyToClipboard(context),
                      ),
                    ],
                    const SizedBox(width: 2),
                    AppIconButton(
                      icon: Icons.delete_outline,
                      tooltip: l10n.delete,
                      size: compact ? 26 : 28,
                      iconSize: compact ? 13.5 : 14.5,
                      radius: AppRadius.sm,
                      iconColor: colors.error.withValues(alpha: 0.85),
                      variant: AppIconButtonVariant.ghost,
                      onPressed: onDelete,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InboxNaturalImage extends StatefulWidget {
  final String path;
  final int decodeMaxSide;
  final bool loadImage;

  const _InboxNaturalImage({
    required this.path,
    required this.decodeMaxSide,
    required this.loadImage,
  });

  @override
  State<_InboxNaturalImage> createState() => _InboxNaturalImageState();
}

class _InboxNaturalImageState extends State<_InboxNaturalImage> {
  double? _aspectRatio;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _syncProbe();
  }

  @override
  void didUpdateWidget(covariant _InboxNaturalImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _failed = false;
      _syncProbe();
    }
  }

  void _syncProbe() {
    if (PromptImageProbe.isKnownMissing(widget.path)) {
      _aspectRatio = null;
      _failed = true;
      return;
    }
    final cached = PromptImageProbe.getCachedAspectRatio(widget.path);
    if (cached != null) {
      _aspectRatio = cached;
      return;
    }
    _aspectRatio = null;
    PromptImageProbe.probeFile(widget.path).then((ratio) {
      if (!mounted) return;
      if (ratio == null) {
        setState(() => _failed = true);
      } else if (_aspectRatio != ratio) {
        setState(() => _aspectRatio = ratio);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return const SizedBox.shrink();
    final colors = context.colors;
    final ratio = (_aspectRatio ?? 1.0).clamp(0.45, 2.2);

    if (!widget.loadImage) {
      return AspectRatio(
        aspectRatio: ratio,
        child: ColoredBox(color: colors.elevatedBackground),
      );
    }

    return AspectRatio(
      aspectRatio: ratio,
      child: Image(
        image: ResizeImage(
          FileImage(File(widget.path)),
          width: widget.decodeMaxSide,
          height: widget.decodeMaxSide,
          policy: ResizeImagePolicy.fit,
        ),
        fit: BoxFit.contain,
        width: double.infinity,
        height: double.infinity,
        alignment: Alignment.center,
        gaplessPlayback: true,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded || frame != null) return child;
          return ColoredBox(color: colors.elevatedBackground);
        },
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
    );
  }
}

class _InboxActionPill extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool compact;
  final VoidCallback onTap;

  const _InboxActionPill({
    required this.icon,
    required this.label,
    required this.compact,
    required this.onTap,
  });

  @override
  State<_InboxActionPill> createState() => _InboxActionPillState();
}

class _InboxActionPillState extends State<_InboxActionPill> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseBg = Color.alphaBlend(colors.primaryTint, colors.cardBackground);
    final hoverBg = Color.alphaBlend(
      colors.primary.withValues(alpha: isDark ? 0.12 : 0.08),
      baseBg,
    );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppMotion.resolveDuration(
            context,
            AppMotionDurations.quick,
          ),
          curve: AppMotionCurves.smoothOut,
          height: 26,
          padding: EdgeInsets.symmetric(horizontal: widget.compact ? 6 : 8),
          decoration: BoxDecoration(
            color: _hovered ? hoverBg : baseBg,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: widget.compact ? 11.5 : 12.5,
                color: colors.primary,
              ),
              SizedBox(width: widget.compact ? 3 : 4),
              Flexible(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: widget.compact ? 10.5 : 11,
                    fontWeight: FontWeight.w600,
                    color: colors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
