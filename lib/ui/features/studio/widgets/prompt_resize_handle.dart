import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_theme.dart';
import 'prompt_edit_actions.dart';
import 'tag_autocomplete_overlay.dart';

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

/// 可拖拽调高的文本输入区：固定高度输入框 + 底部调节手柄 + 自动补全浮窗 + 快捷键一体化封装。
///
/// 支持快捷键：
/// - `Ctrl + Up`: 增强光标所在标签权重 `{}`
/// - `Ctrl + Down`: 减弱光标所在标签权重 `[]`
/// - `Ctrl + /`: 切换光标所在标签禁用 `~tag~`
/// - `Ctrl + Shift + F`: 格式化与美化提示词
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

  /// 外部传入的 FocusNode (可选)
  final FocusNode? focusNode;

  /// 是否启用 Danbooru 自动补全悬浮窗
  final bool enableAutocomplete;

  /// 补全建议项中是否显示中文释义
  final bool showTranslation;

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
    this.focusNode,
    this.enableAutocomplete = true,
    this.showTranslation = true,
  });

  @override
  State<ResizableTextField> createState() => _ResizableTextFieldState();
}

class _ResizableTextFieldState extends State<ResizableTextField> {
  late double _height;
  late FocusNode _focusNode;
  bool _internalFocusNode = false;

  @override
  void initState() {
    super.initState();
    _height = widget.defaultHeight;
    if (widget.focusNode != null) {
      _focusNode = widget.focusNode!;
    } else {
      _focusNode = FocusNode();
      _internalFocusNode = true;
    }
  }

  @override
  void didUpdateWidget(covariant ResizableTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.defaultHeight != widget.defaultHeight) {
      _height = widget.defaultHeight;
    }
    if (oldWidget.focusNode != widget.focusNode) {
      if (_internalFocusNode) {
        _focusNode.dispose();
        _internalFocusNode = false;
      }
      if (widget.focusNode != null) {
        _focusNode = widget.focusNode!;
      } else {
        _focusNode = FocusNode();
        _internalFocusNode = true;
      }
    }
  }

  @override
  void dispose() {
    if (_internalFocusNode) {
      _focusNode.dispose();
    }
    super.dispose();
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
    Widget inputField = SizedBox(
      height: _height,
      child: Padding(
        padding: widget.padding,
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(
              LogicalKeyboardKey.arrowUp,
              control: true,
            ): () => PromptEditActions.adjustWeight(
              widget.controller,
              widget.onChanged,
              up: true,
            ),
            const SingleActivator(
              LogicalKeyboardKey.arrowDown,
              control: true,
            ): () => PromptEditActions.adjustWeight(
              widget.controller,
              widget.onChanged,
              up: false,
            ),
            const SingleActivator(
              LogicalKeyboardKey.slash,
              control: true,
            ): () => PromptEditActions.toggleDisabled(
              widget.controller,
              widget.onChanged,
            ),
            const SingleActivator(
              LogicalKeyboardKey.keyF,
              control: true,
              shift: true,
            ): () => PromptEditActions.formatPrompt(
              widget.controller,
              widget.onChanged,
            ),
          },
          child: TextField(
            controller: widget.controller,
            focusNode: _focusNode,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            style: widget.style,
            decoration: InputDecoration(
              isDense: true,
              hintText: widget.hintText,
              hintStyle: widget.hintStyle,
              contentPadding: EdgeInsets.zero,
              filled: false,
              hoverColor: Colors.transparent,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
            onChanged: widget.onChanged,
          ),
        ),
      ),
    );

    if (widget.enableAutocomplete) {
      inputField = TagAutocompleteAnchor(
        controller: widget.controller,
        focusNode: _focusNode,
        onChanged: widget.onChanged,
        showTranslation: widget.showTranslation,
        child: inputField,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        inputField,
        PromptResizeHandle(
          tooltip: widget.resizeTooltip,
          onDelta: _applyDelta,
          onReset: _reset,
        ),
      ],
    );
  }
}
