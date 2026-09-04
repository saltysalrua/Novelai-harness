import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_tokens.dart';
import '../theme/theme_context_extensions.dart';

/// 统一两端对齐键值参数行 (AppKeyValueRow)
///
/// 代码证据出处：
/// - `inpaint_page.dart:568-586` (_buildInfoRow 局部修复几何参数行)
/// - `metadata_reader_dialog.dart:430-480` (参数属性网格行)
/// - `bill_settings_tab.dart:110-149` (账单用量明细数据行)
/// - `canvas_overlays.dart:34-88` (尺寸与种子信息展示行)
///
/// 核心职责：
/// 统一两端对齐的 Label-Value 对展示，
/// 支持可选标签色、主色高亮强调、等宽字体、悬停提示及点击复制。
class AppKeyValueRow extends StatefulWidget {
  /// 属性标签名 (左侧文本)
  final String label;

  /// 属性数值/内容 (右侧文本)
  final String value;

  /// 标签文字颜色；未指定时默认使用 [AppColorsExtension.textSecondary]
  final Color? labelColor;

  /// 数值文字颜色；未指定时默认使用 [AppColorsExtension.textPrimary]
  final Color? valueColor;

  /// 是否启用主色强调值，默认 false
  final bool isPrimaryHighlight;

  /// 是否采用等宽字体 (适合尺寸、种子、Hash、Token 等格式)，默认 false
  final bool isMonospace;

  /// 是否允许点击复制数值到剪贴板，默认 false
  final bool copyable;

  /// 自定义点击事件 (若提供了则点击整行触发)
  final VoidCallback? onTap;

  /// 自定义复制事件 (若提供了且启用了 copyable 则点击复制触发)
  final VoidCallback? onCopy;

  /// 悬停提示文字 (可选)
  final String? tooltip;

  /// 字号大小，默认 11.5
  final double fontSize;

  /// 内边距，默认上下 4.0
  final EdgeInsetsGeometry padding;

  /// 尾部附加小组件 (如单位、图标等，可选)
  final Widget? trailing;

  const AppKeyValueRow({
    super.key,
    required this.label,
    required this.value,
    this.labelColor,
    this.valueColor,
    this.isPrimaryHighlight = false,
    this.isMonospace = false,
    this.copyable = false,
    this.onTap,
    this.onCopy,
    this.tooltip,
    this.fontSize = 11.5,
    this.padding = const EdgeInsets.symmetric(vertical: 4.0),
    this.trailing,
  });

  @override
  State<AppKeyValueRow> createState() => _AppKeyValueRowState();
}

class _AppKeyValueRowState extends State<AppKeyValueRow> {
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
      await Clipboard.setData(ClipboardData(text: widget.value));
    }

    if (!mounted) return;
    setState(() => _isCopied = true);
    _copiedTimer?.cancel();
    _copiedTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) {
        setState(() => _isCopied = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final resolvedLabelColor = widget.labelColor ?? colors.textSecondary;
    final resolvedValueColor = widget.isPrimaryHighlight
        ? colors.primary
        : (widget.valueColor ?? colors.textPrimary);

    final valueStyle = TextStyle(
      fontSize: widget.fontSize,
      fontFamily: widget.isMonospace ? 'monospace' : null,
      fontWeight: FontWeight.w600,
      color: _isCopied ? colors.success : resolvedValueColor,
    );

    Widget row = Padding(
      padding: widget.padding,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            widget.label,
            style: TextStyle(
              fontSize: widget.fontSize,
              color: resolvedLabelColor,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    widget.value,
                    style: valueStyle,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                  ),
                ),
                if (_isCopied) ...[
                  const SizedBox(width: 4),
                  Icon(
                    Icons.check_rounded,
                    size: widget.fontSize,
                    color: colors.success,
                  ),
                ] else if (widget.copyable) ...[
                  const SizedBox(width: 4),
                  Icon(
                    Icons.copy_rounded,
                    size: widget.fontSize - 1,
                    color: colors.textMuted.withValues(alpha: 0.6),
                  ),
                ],
                if (widget.trailing != null) ...[
                  const SizedBox(width: 4),
                  widget.trailing!,
                ],
              ],
            ),
          ),
        ],
      ),
    );

    final isInteractive = widget.copyable || widget.onTap != null;

    if (isInteractive) {
      row = InkWell(
        onTap: () {
          widget.onTap?.call();
          if (widget.copyable) {
            _handleCopy();
          }
        },
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: row,
      );
    }

    final effectiveTooltip =
        widget.tooltip ??
        (widget.copyable ? (_isCopied ? '已复制' : '点击复制') : null);

    if (effectiveTooltip != null) {
      row = Tooltip(message: effectiveTooltip, child: row);
    }

    return row;
  }
}
