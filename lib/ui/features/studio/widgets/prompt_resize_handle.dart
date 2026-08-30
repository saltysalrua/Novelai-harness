import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

/// 提示词输入区域垂直调节手柄
///
/// 放置在文本区域下方，支持鼠标上下拖拽改变高度，双击快速重置到默认高度。
class PromptResizeHandle extends StatefulWidget {
  final ValueChanged<double> onDelta;
  final VoidCallback? onReset;
  final String tooltip;

  const PromptResizeHandle({
    super.key,
    required this.onDelta,
    this.onReset,
    this.tooltip = '上下拖动调节高度 (双击重置)',
  });

  @override
  State<PromptResizeHandle> createState() => _PromptResizeHandleState();
}

class _PromptResizeHandleState extends State<PromptResizeHandle> {
  bool _isHovered = false;
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeUpDown,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: (_) => setState(() => _isDragging = true),
          onVerticalDragEnd: (_) => setState(() => _isDragging = false),
          onVerticalDragCancel: () => setState(() => _isDragging = false),
          onVerticalDragUpdate: (details) => widget.onDelta(details.delta.dy),
          onDoubleTap: widget.onReset,
          child: Container(
            height: 12,
            alignment: Alignment.center,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: _isHovered || _isDragging ? 42 : 28,
              height: 3.5,
              decoration: BoxDecoration(
                color: _isDragging
                    ? AppTheme.notionBlue
                    : (_isHovered
                          ? AppTheme.notionBlue.withValues(alpha: 0.6)
                          : AppTheme.borderHover),
                borderRadius: BorderRadius.circular(AppTheme.radiusPill),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 可拖拽调高的文本输入区：固定高度输入框 + 底部调节手柄一体化封装。
///
/// 高度状态由组件内部持有，拖动增减、双击重置；当 [defaultHeight] 变化
/// (如布局模式切换) 时自动重置到新的默认高度。主提示词、角色提示词、
/// 角色负面词、前置/后置词缀五处输入区共用本组件。
class ResizableTextField extends StatefulWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hintText;

  /// 默认高度 (双击重置目标)
  final double defaultHeight;

  /// 最小与最大高度限制
  final double minHeight;
  final double maxHeight;

  /// 拖拽手柄提示文案
  final String resizeTooltip;

  /// 输入框文字与占位文字样式
  final TextStyle? style;
  final TextStyle? hintStyle;

  /// 输入框内边距
  final EdgeInsets padding;

  const ResizableTextField({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.hintText,
    required this.defaultHeight,
    this.minHeight = 44,
    this.maxHeight = 400,
    this.resizeTooltip = '拖动调整高度 (双击重置)',
    this.style,
    this.hintStyle,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
  });

  @override
  State<ResizableTextField> createState() => _ResizableTextFieldState();
}

class _ResizableTextFieldState extends State<ResizableTextField> {
  late double _height;

  @override
  void initState() {
    super.initState();
    _height = widget.defaultHeight;
  }

  @override
  void didUpdateWidget(covariant ResizableTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 布局模式切换导致默认高度变化时，重置到新默认值
    if (oldWidget.defaultHeight != widget.defaultHeight) {
      _height = widget.defaultHeight;
    }
  }

  void _applyDelta(double delta) {
    setState(() {
      _height = (_height + delta).clamp(widget.minHeight, widget.maxHeight);
    });
  }

  void _reset() {
    setState(() => _height = widget.defaultHeight);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: _height,
          child: Padding(
            padding: widget.padding,
            child: TextField(
              controller: widget.controller,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: widget.style,
              decoration: InputDecoration(
                isDense: true,
                hintText: widget.hintText,
                hintStyle: widget.hintStyle,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
              onChanged: widget.onChanged,
            ),
          ),
        ),
        PromptResizeHandle(
          tooltip: widget.resizeTooltip,
          onDelta: _applyDelta,
          onReset: _reset,
        ),
      ],
    );
  }
}
