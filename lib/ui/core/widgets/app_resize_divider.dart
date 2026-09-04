import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import '../theme/theme_context_extensions.dart';

/// 统一可拖拽分割调节手柄 (AppResizeDivider)
///
/// 代码证据出处：
/// - `resizable_split_view.dart:125-170` (_buildDivider 双栏/三栏横向分割拖拽条)
/// - `prompt_resize_handle.dart:10-67` (PromptResizeHandle 提示词输入区纵向调节手柄)
///
/// 核心职责：
/// 参数化方向 `Axis.horizontal | Axis.vertical`，统一 28px→42px 鼠标悬停伸缩动效、
/// `SystemMouseCursors` 方向光标、双击重置回调及统一拖拽手势生命周期。
class AppResizeDivider extends StatefulWidget {
  /// 拖拽方向；[Axis.vertical] 为上下拉伸，[Axis.horizontal] 为左右拉伸
  final Axis axis;

  /// 拖拽位移更新回调 (传入对应轴向的 delta)
  final ValueChanged<double> onDelta;

  /// 双击重置回调 (可选)
  final VoidCallback? onReset;

  /// 拖拽开始回调 (可选)
  final VoidCallback? onDragStart;

  /// 拖拽结束回调 (可选)
  final VoidCallback? onDragEnd;

  /// 悬停提示文案 (可选)
  final String? tooltip;

  /// 交互热区厚度 (即垂直时的 height 或水平时的 width)，默认 12.0
  final double hitThickness;

  /// 默认手柄指示条长度，默认 28.0
  final double initialHandleSize;

  /// 悬停/拖拽展开时的指示条长度，默认 42.0
  final double expandedHandleSize;

  /// 手柄指示条厚度，默认 3.5
  final double handleThickness;

  const AppResizeDivider({
    super.key,
    this.axis = Axis.vertical,
    required this.onDelta,
    this.onReset,
    this.onDragStart,
    this.onDragEnd,
    this.tooltip,
    this.hitThickness = 12.0,
    this.initialHandleSize = 28.0,
    this.expandedHandleSize = 42.0,
    this.handleThickness = 3.5,
  });

  @override
  State<AppResizeDivider> createState() => _AppResizeDividerState();
}

class _AppResizeDividerState extends State<AppResizeDivider> {
  bool _isHovered = false;
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isVertical = widget.axis == Axis.vertical;

    final defaultTooltip = isVertical ? '上下拖动调节高度 (双击重置)' : '左右拖动调整宽度 (双击重置)';

    final cursor = isVertical
        ? SystemMouseCursors.resizeUpDown
        : SystemMouseCursors.resizeLeftRight;

    final isActive = _isHovered || _isDragging;
    final handleLength = isActive
        ? widget.expandedHandleSize
        : widget.initialHandleSize;

    final handleColor = _isDragging
        ? colors.primary
        : (_isHovered
              ? colors.primary.withValues(alpha: 0.65)
              : colors.borderHover);

    Widget handle = Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: isVertical ? handleLength : widget.handleThickness,
        height: isVertical ? widget.handleThickness : handleLength,
        decoration: BoxDecoration(
          color: handleColor,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
      ),
    );

    Widget content = Container(
      width: isVertical ? null : widget.hitThickness,
      height: isVertical ? widget.hitThickness : null,
      alignment: Alignment.center,
      color: Colors.transparent,
      child: handle,
    );

    content = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTap: widget.onReset,
      onVerticalDragStart: isVertical
          ? (_) {
              setState(() => _isDragging = true);
              widget.onDragStart?.call();
            }
          : null,
      onVerticalDragUpdate: isVertical
          ? (details) => widget.onDelta(details.delta.dy)
          : null,
      onVerticalDragEnd: isVertical
          ? (_) {
              setState(() => _isDragging = false);
              widget.onDragEnd?.call();
            }
          : null,
      onVerticalDragCancel: isVertical
          ? () {
              setState(() => _isDragging = false);
              widget.onDragEnd?.call();
            }
          : null,
      onHorizontalDragStart: !isVertical
          ? (_) {
              setState(() => _isDragging = true);
              widget.onDragStart?.call();
            }
          : null,
      onHorizontalDragUpdate: !isVertical
          ? (details) => widget.onDelta(details.delta.dx)
          : null,
      onHorizontalDragEnd: !isVertical
          ? (_) {
              setState(() => _isDragging = false);
              widget.onDragEnd?.call();
            }
          : null,
      onHorizontalDragCancel: !isVertical
          ? () {
              setState(() => _isDragging = false);
              widget.onDragEnd?.call();
            }
          : null,
      child: content,
    );

    content = MouseRegion(
      cursor: cursor,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: content,
    );

    final tooltipMsg = widget.tooltip ?? defaultTooltip;
    if (tooltipMsg.isNotEmpty) {
      content = Tooltip(
        message: tooltipMsg,
        waitDuration: const Duration(milliseconds: 600),
        child: content,
      );
    }

    return content;
  }
}
