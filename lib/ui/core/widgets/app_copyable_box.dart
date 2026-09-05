import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_tokens.dart';
import '../theme/theme_context_extensions.dart';

/// 统一只读内容展示容器 (AppCopyableBox)
///
/// 代码证据出处：
/// - `metadata_reader_dialog.dart:345-416` (_buildPromptBlock 提示词块与顶部复制按钮)
/// - `prompt_combo_card.dart:192-260` (正向/负向提示词预览区，带 'UC:' 前缀徽标)
/// - `inpaint_page.dart:610-657` (_buildReusedPromptPreview 复用主提示词预览区)
/// - `agent_chat_messages.dart:276-296` (智能体工具调用输出只读块)
///
/// 核心职责：
/// 统一只读提示词、脚本输出与文本展示容器，
/// 集成顶部标头行、前缀微标 (如 UC:)、右侧一键复制到剪贴板、高度限制及 SelectableText。
class AppCopyableBox extends StatefulWidget {
  /// 容器主体文本内容
  final String content;

  /// 顶部标头标题 (可选)
  final String? title;

  /// 顶部标头图标 (可选)
  final IconData? icon;

  /// 内容前缀微标 (如 'UC:' 负面提示词标签，可选)
  final String? prefixBadge;

  /// 前缀微标颜色 (默认使用警示色或主题主色)
  final Color? prefixBadgeColor;

  /// 最大高度限制；超出时支持内部纵向滚动
  final double? maxHeight;

  /// 最多展示行数；为 null 时自适应展开或受 [maxHeight] 限制
  final int? maxLines;

  /// 自定义复制回调；若未指定则自动复制 [content] 到系统剪贴板并给出已复制提示
  final VoidCallback? onCopy;

  /// 复制按钮提示文本，默认 '复制'
  final String copyLabel;

  /// 是否显示顶部标头行的复制按钮，默认 true
  final bool showCopyButton;

  /// 是否支持文本划选，默认 true
  final bool selectable;

  /// 文本字号，默认 12
  final double fontSize;

  /// 自定义背景色 (未指定时默认使用 [AppColorsExtension.mutedBackground])
  final Color? backgroundColor;

  /// 自定义边框颜色
  final Color? borderColor;

  /// 圆角大小，默认 [AppRadius.md] (8.0)
  final double radius;

  /// 内容区域内边距，默认 10.0
  final EdgeInsetsGeometry padding;

  const AppCopyableBox({
    super.key,
    required this.content,
    this.title,
    this.icon,
    this.prefixBadge,
    this.prefixBadgeColor,
    this.maxHeight,
    this.maxLines,
    this.onCopy,
    this.copyLabel = '复制',
    this.showCopyButton = true,
    this.selectable = true,
    this.fontSize = 12,
    this.backgroundColor,
    this.borderColor,
    this.radius = AppRadius.md,
    this.padding = const EdgeInsets.all(10.0),
  });

  @override
  State<AppCopyableBox> createState() => _AppCopyableBoxState();
}

class _AppCopyableBoxState extends State<AppCopyableBox> {
  bool _isCopied = false;
  Timer? _copiedTimer;

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }

  Future<void> _handleCopy() async {
    if (widget.onCopy != null) {
      widget.onCopy!();
    } else {
      await Clipboard.setData(ClipboardData(text: widget.content));
    }

    if (!mounted) return;
    setState(() => _isCopied = true);
    _copiedTimer?.cancel();
    _copiedTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) {
        setState(() => _isCopied = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasHeader = widget.title != null || widget.showCopyButton;

    final effectiveBg =
        widget.backgroundColor ?? colors.mutedBackground.withValues(alpha: 0.6);
    final effectiveBorder = widget.borderColor ?? colors.borderDefault;
    final badgeColor = widget.prefixBadgeColor ?? colors.error;

    Widget textWidget;
    final textStyle = TextStyle(
      fontSize: widget.fontSize,
      height: 1.42,
      color: colors.textPrimary,
    );

    if (widget.selectable && widget.maxLines == null) {
      textWidget = SelectableText(widget.content, style: textStyle);
    } else {
      textWidget = Text(
        widget.content,
        maxLines: widget.maxLines,
        overflow: widget.maxLines != null ? TextOverflow.ellipsis : null,
        style: textStyle,
      );
    }

    if (widget.prefixBadge != null && widget.prefixBadge!.isNotEmpty) {
      textWidget = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.prefixBadge!,
            style: TextStyle(
              fontSize: widget.fontSize - 1.0,
              fontWeight: FontWeight.w700,
              color: badgeColor,
              height: 1.42,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(child: textWidget),
        ],
      );
    }

    Widget contentBox = Container(
      width: double.infinity,
      padding: widget.padding,
      decoration: BoxDecoration(
        color: effectiveBg,
        borderRadius: BorderRadius.circular(widget.radius),
        border: Border.all(color: effectiveBorder),
      ),
      child: textWidget,
    );

    if (widget.maxHeight != null) {
      contentBox = ConstrainedBox(
        constraints: BoxConstraints(maxHeight: widget.maxHeight!),
        child: SingleChildScrollView(child: contentBox),
      );
    }

    if (!hasHeader) {
      return contentBox;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon, size: 14, color: colors.textSecondary),
                  const SizedBox(width: 6),
                ],
                if (widget.title != null)
                  Text(
                    widget.title!,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
              ],
            ),
            if (widget.showCopyButton)
              InkWell(
                onTap: _handleCopy,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _isCopied
                        ? colors.success.withValues(alpha: 0.12)
                        : colors.primaryTint,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isCopied ? Icons.check_rounded : Icons.copy_rounded,
                        size: 12,
                        color: _isCopied ? colors.success : colors.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _isCopied ? '已复制' : widget.copyLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _isCopied ? colors.success : colors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        contentBox,
      ],
    );
  }
}
