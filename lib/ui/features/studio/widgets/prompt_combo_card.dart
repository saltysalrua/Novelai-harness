import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../data/models/prompt_library_models.dart';
import '../../../../data/services/prompt_image_probe.dart';
import '../../../core/context_l10n.dart';
import '../../../core/l10n/model_label_l10n.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/app_transitions.dart';
import '../../../core/widgets/context_menu.dart';

/// 词库词组合瀑布流卡片：
/// - 图片按原始比例完整呈现 (`BoxFit.contain` + 真实宽高比)，零裁切、零留白边框
/// - 无预览图时自动收起为紧凑文本卡，不占空块
/// - 全卡无内部分隔线、无描边按钮堆砌
class PromptComboCard extends StatelessWidget {
  static const int _previewDecodeMaxSide = 560;

  final PromptComboEntry combo;
  final void Function(bool replace, bool asCharacter) onApply;
  final void Function(bool replace)? onApplyStyle;
  final VoidCallback? onSendToAgent;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  /// 是否挂载图片解码 (瀑布流视口惰性裁剪用，默认为 true)
  final bool loadImage;

  /// 窄屏/多列高密度模式：缩减内边距与字号，将操作区拆分为「应用」与「分类+工具」两行以避免按钮挤压截断。
  final bool compact;

  const PromptComboCard({
    super.key,
    required this.combo,
    required this.onApply,
    this.onApplyStyle,
    this.onSendToAgent,
    required this.onEdit,
    required this.onDelete,
    this.loadImage = true,
    this.compact = false,
  });

  void _copyToClipboard(BuildContext context) {
    final String text;
    if (combo.isStyle) {
      final parts = <String>[
        if (combo.prefixPrompt.trim().isNotEmpty)
          'Prefix: ${combo.prefixPrompt.trim()}',
        if (combo.suffixPrompt.trim().isNotEmpty)
          'Suffix: ${combo.suffixPrompt.trim()}',
        if (combo.prompt.trim().isNotEmpty) 'Prompt: ${combo.prompt.trim()}',
        if (combo.negativePrompt.trim().isNotEmpty)
          'Negative: ${combo.negativePrompt.trim()}',
      ];
      text = parts.join('\n');
    } else if (combo.isCharacter && combo.negativePrompt.isNotEmpty) {
      text = 'Prompt: ${combo.prompt}\nNegative: ${combo.negativePrompt}';
    } else {
      text = combo.prompt;
    }
    Clipboard.setData(ClipboardData(text: text));
    showAppToast(
      context,
      message: context.l10n.libraryCardCopiedPrompt(combo.title),
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
        if (combo.isStyle) ...[
          ContextMenuItem(
            icon: Icons.palette_outlined,
            label: l10n.libraryMenuApplyStyleReplace,
            onTap: () => onApplyStyle != null
                ? onApplyStyle!(true)
                : onApply(true, false),
          ),
          ContextMenuItem(
            icon: Icons.add_outlined,
            label: l10n.libraryMenuApplyStyleAppend,
            onTap: () => onApplyStyle != null
                ? onApplyStyle!(false)
                : onApply(false, false),
          ),
          ContextMenuItem(
            icon: Icons.playlist_add_outlined,
            label: l10n.libraryMenuAppendToPrompt,
            onTap: () => onApply(false, false),
          ),
        ] else ...[
          ContextMenuItem(
            icon: Icons.add_outlined,
            label: l10n.libraryMenuAppendToPrompt,
            onTap: () => onApply(false, false),
          ),
          ContextMenuItem(
            icon: Icons.swap_horiz_outlined,
            label: l10n.libraryMenuReplacePrompt,
            onTap: () => onApply(true, false),
          ),
          if (combo.isCharacter)
            ContextMenuItem(
              icon: Icons.person_add_alt_1_outlined,
              label: l10n.libraryMenuAddAsCharacter,
              onTap: () => onApply(false, true),
            ),
          if (combo.isCharacter && onSendToAgent != null)
            ContextMenuItem(
              icon: Icons.chat_bubble_outline_rounded,
              label: l10n.libraryMenuSendToAgent,
              onTap: onSendToAgent!,
            ),
        ],
        const ContextMenuDivider(),
        ContextMenuItem(
          icon: Icons.copy_outlined,
          label: l10n.libraryMenuCopyPrompt,
          onTap: () => _copyToClipboard(context),
        ),
        ContextMenuItem(
          icon: Icons.edit_outlined,
          label: l10n.libraryMenuEdit,
          onTap: onEdit,
        ),
        ContextMenuItem(
          icon: Icons.delete_outline,
          label: l10n.delete,
          onTap: onDelete,
        ),
      ],
    );
  }

  Widget _buildTitle(BuildContext context) {
    final colors = context.colors;
    return Tooltip(
      message: combo.title,
      child: Text(
        combo.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: compact ? 12.5 : 13.5,
          fontWeight: FontWeight.w600,
          color: colors.textPrimary,
        ),
      ),
    );
  }

  Widget _buildPromptSnippet(BuildContext context, {required bool hasNegative}) {
    final colors = context.colors;
    final summary = combo.displayPromptSummary;
    final tooltipText = !combo.isStyle && hasNegative
        ? '$summary\nUC: ${combo.negativePrompt}'
        : summary;
    return Tooltip(
      message: tooltipText,
      child: Text(
        summary,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: compact ? 10.5 : 11.5,
          height: compact ? 1.32 : 1.38,
          color: colors.textMuted,
        ),
      ),
    );
  }

  Widget _buildApplyPills(BuildContext context, {required bool isChar}) {
    final colors = context.colors;
    final l10n = context.l10n;
    if (combo.isStyle) {
      return Row(
        children: [
          Flexible(
            child: _SoftActionPill(
              icon: Icons.palette_outlined,
              label: l10n.libraryCardApplyStyle,
              backgroundColor: colors.primaryTint,
              foregroundColor: colors.primary,
              compact: compact,
              onTap: () => onApplyStyle != null
                  ? onApplyStyle!(true)
                  : onApply(false, false),
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        Flexible(
          flex: 3,
          child: _SoftActionPill(
            icon: Icons.bolt_outlined,
            label: l10n.libraryCardApply,
            backgroundColor: colors.primaryTint,
            foregroundColor: colors.primary,
            compact: compact,
            onTap: () => onApply(false, false),
          ),
        ),
        if (isChar) ...[
          const SizedBox(width: 4),
          Flexible(
            flex: 2,
            child: _SoftActionPill(
              icon: Icons.person_add_alt_1_outlined,
              label: l10n.libraryCardAddCharacter,
              tooltip: l10n.libraryCardAddAsCharacterTooltip,
              backgroundColor: colors.errorSurface,
              foregroundColor: colors.error,
              compact: compact,
              onTap: () => onApply(false, true),
            ),
          ),
          if (onSendToAgent != null) ...[
            const SizedBox(width: 4),
            _SoftIconPill(
              icon: Icons.chat_bubble_outline_rounded,
              tooltip: l10n.libraryCardSendToAgentTooltip,
              backgroundColor: colors.primaryTint,
              foregroundColor: colors.primary,
              onTap: onSendToAgent!,
            ),
          ],
        ],
      ],
    );
  }

  List<Widget> _buildUtilityActions(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final btnSize = compact ? 22.0 : 24.0;
    final iconSize = compact ? 13.0 : 14.0;
    return [
      _ComboCopyButton(
        tooltip: l10n.libraryMenuCopyPrompt,
        size: btnSize,
        iconSize: iconSize,
        onCopy: () => _copyToClipboard(context),
      ),
      const SizedBox(width: 2),
      AppIconButton(
        icon: Icons.edit_outlined,
        tooltip: l10n.libraryMenuEdit,
        size: btnSize,
        iconSize: iconSize,
        radius: AppRadius.sm,
        iconColor: colors.textSecondary,
        variant: AppIconButtonVariant.ghost,
        onPressed: onEdit,
      ),
      const SizedBox(width: 2),
      AppIconButton(
        icon: Icons.delete_outline,
        tooltip: l10n.delete,
        size: btnSize,
        iconSize: iconSize,
        radius: AppRadius.sm,
        iconColor: colors.error.withValues(alpha: 0.85),
        variant: AppIconButtonVariant.ghost,
        onPressed: onDelete,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final isChar = combo.isCharacter;
    final hasNegative = isChar && combo.negativePrompt.trim().isNotEmpty;
    final rawPath = combo.previewImagePath?.trim();
    final hasPreviewPath = rawPath != null && rawPath.isNotEmpty;
    final categoryLabel = _QuietCategoryLabel(
      label: comboCategoryLabelOf(l10n, combo.category),
      isCharacter: isChar,
      compact: compact,
    );

    return AppCard(
      onTap: onEdit,
      onContextMenu: (position) => _showContextMenu(context, position),
      radius: compact ? AppRadius.md : AppRadius.lg,
      borderColor: colors.borderSubtle,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasPreviewPath)
            _ComboNaturalImage(
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
                if (compact)
                  _buildTitle(context)
                else
                  Row(
                    children: [
                      Expanded(child: _buildTitle(context)),
                      const SizedBox(width: 8),
                      categoryLabel,
                    ],
                  ),
                SizedBox(height: compact ? 2 : 3),

                // 提示词摘要 (两行更清晰，悬停看完整)
                _buildPromptSnippet(context, hasNegative: hasNegative),
                SizedBox(height: compact ? 6 : 8),

                // 底部无边框操作区：紧凑两列模式下拆分为「应用」与「分类+工具」两行，避免挤压截断
                if (compact) ...[
                  _buildApplyPills(context, isChar: isChar),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: categoryLabel,
                        ),
                      ),
                      ..._buildUtilityActions(context),
                    ],
                  ),
                ] else
                  Row(
                    children: [
                      Expanded(child: _buildApplyPills(context, isChar: isChar)),
                      const SizedBox(width: 4),
                      ..._buildUtilityActions(context),
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

/// 按真实宽高比展示完整图片：零留白边框、零裁切；文件不存在时静默收起。
class _ComboNaturalImage extends StatefulWidget {
  final String path;
  final int decodeMaxSide;
  final bool loadImage;

  const _ComboNaturalImage({
    required this.path,
    required this.decodeMaxSide,
    required this.loadImage,
  });

  @override
  State<_ComboNaturalImage> createState() => _ComboNaturalImageState();
}

class _ComboNaturalImageState extends State<_ComboNaturalImage> {
  double? _aspectRatio;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _syncProbe();
  }

  @override
  void didUpdateWidget(covariant _ComboNaturalImage oldWidget) {
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

    // 已知精确比例时用 BoxFit.contain + 等比 AspectRatio，零留白且绝不裁切；
    // 极端超长/超宽比例被钳制到 [0.45, 2.2] 时同样保持 BoxFit.contain 展示全貌。
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
          if (wasSynchronouslyLoaded || frame != null) {
            return child;
          }
          return ColoredBox(color: colors.elevatedBackground);
        },
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
    );
  }
}

/// 极简无框分类文字标识 (仅以小圆点 + 文字呈现，不套外框)
class _QuietCategoryLabel extends StatelessWidget {
  final String label;
  final bool isCharacter;
  final bool compact;

  const _QuietCategoryLabel({
    required this.label,
    required this.isCharacter,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = isCharacter ? colors.error : colors.textMuted;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 74),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: compact ? 4.5 : 5,
            height: compact ? 4.5 : 5,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 10.5 : 11,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 无边框柔和动作胶囊
class _SoftActionPill extends StatefulWidget {
  final IconData icon;
  final String label;
  final String? tooltip;
  final Color backgroundColor;
  final Color foregroundColor;
  final bool compact;
  final VoidCallback onTap;

  const _SoftActionPill({
    required this.icon,
    required this.label,
    this.tooltip,
    required this.backgroundColor,
    required this.foregroundColor,
    this.compact = false,
    required this.onTap,
  });

  @override
  State<_SoftActionPill> createState() => _SoftActionPillState();
}

class _SoftActionPillState extends State<_SoftActionPill> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bg = _hovered
        ? widget.foregroundColor.withValues(alpha: 0.16)
        : widget.backgroundColor;

    Widget pill = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 24,
          padding: EdgeInsets.symmetric(horizontal: widget.compact ? 5 : 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: widget.compact ? 11 : 12,
                color: widget.foregroundColor,
              ),
              SizedBox(width: widget.compact ? 2 : 3),
              Flexible(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: widget.compact ? 10.5 : 11,
                    fontWeight: FontWeight.w600,
                    color: widget.foregroundColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (widget.tooltip != null) {
      pill = Tooltip(message: widget.tooltip!, child: pill);
    }
    return pill;
  }
}

/// 紧凑无边框动作图标胶囊 (用于角色卡「发送到助手」等辅助动作)
class _SoftIconPill extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final Color backgroundColor;
  final Color foregroundColor;
  final VoidCallback onTap;

  const _SoftIconPill({
    required this.icon,
    required this.tooltip,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.onTap,
  });

  @override
  State<_SoftIconPill> createState() => _SoftIconPillState();
}

class _SoftIconPillState extends State<_SoftIconPill> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bg = _hovered
        ? widget.foregroundColor.withValues(alpha: 0.16)
        : widget.backgroundColor;

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(widget.icon, size: 13, color: widget.foregroundColor),
          ),
        ),
      ),
    );
  }
}

class _ComboCopyButton extends StatefulWidget {
  final String tooltip;
  final double size;
  final double iconSize;
  final VoidCallback onCopy;

  const _ComboCopyButton({
    required this.tooltip,
    this.size = 24.0,
    this.iconSize = 14.0,
    required this.onCopy,
  });

  @override
  State<_ComboCopyButton> createState() => _ComboCopyButtonState();
}

class _ComboCopyButtonState extends State<_ComboCopyButton> {
  bool _copied = false;
  bool _hovered = false;
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  void _handleTap() {
    widget.onCopy();
    _resetTimer?.cancel();
    setState(() => _copied = true);
    _resetTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: _handleTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: AppMotion.resolveDuration(
              context,
              AppMotionDurations.quick,
            ),
            curve: AppMotionCurves.smoothOut,
            width: widget.size,
            height: widget.size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _copied
                  ? colors.success.withValues(alpha: 0.14)
                  : (_hovered ? colors.mutedBackground : null),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: AppIconSwap(
              swapKey: _copied,
              enableBlur: false,
              child: _copied
                  ? AppSuccessCheck(size: widget.iconSize, color: colors.success)
                  : Icon(
                      Icons.copy_outlined,
                      size: widget.iconSize,
                      color: colors.textSecondary,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
