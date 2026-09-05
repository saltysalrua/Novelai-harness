import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/context_l10n.dart';
import '../../../core/widgets/app_resize_divider.dart';
import 'prompt_edit_actions.dart';
import 'tag_autocomplete_overlay.dart';

/// 提示词输入区域垂直调节手柄
///
/// 放置在文本区域下方，支持鼠标上下拖拽改变高度，双击快速重置到默认高度。
class PromptResizeHandle extends StatelessWidget {
  final ValueChanged<double> onDelta;
  final VoidCallback? onReset;
  final VoidCallback? onDragEnd;
  final String? tooltip;

  const PromptResizeHandle({
    super.key,
    required this.onDelta,
    this.onReset,
    this.onDragEnd,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return AppResizeDivider(
      axis: Axis.vertical,
      onDelta: onDelta,
      onReset: onReset,
      onDragEnd: onDragEnd,
      tooltip: tooltip ?? context.maybeL10n?.promptResizeTooltip ?? '',
      hitThickness: 12.0,
      initialHandleSize: 28.0,
      expandedHandleSize: 42.0,
      handleThickness: 3.5,
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

  /// 初始高度 (持久化加载的高度，若为 null 则使用 defaultHeight)
  final double? initialHeight;

  /// 高度提交回调 (拖拽结束或双击重置时触发，供外层持久化)
  final ValueChanged<double>? onHeightChanged;

  /// 最小与最大高度限制
  final double minHeight;
  final double maxHeight;

  /// 拖拽手柄提示文案
  final String? resizeTooltip;

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
    this.initialHeight,
    this.onHeightChanged,
    this.minHeight = 44,
    this.maxHeight = 400,
    this.resizeTooltip,
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
  late final ValueNotifier<double> _height;
  double? _pendingHeight;
  late FocusNode _focusNode;
  bool _internalFocusNode = false;

  @override
  void initState() {
    super.initState();
    _height = ValueNotifier(
      (widget.initialHeight ?? widget.defaultHeight).clamp(
        widget.minHeight,
        widget.maxHeight,
      ),
    );
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
    if (widget.initialHeight != null &&
        widget.initialHeight != oldWidget.initialHeight) {
      _pendingHeight = null;
      _height.value = widget.initialHeight!.clamp(
        widget.minHeight,
        widget.maxHeight,
      );
    } else if (oldWidget.defaultHeight != widget.defaultHeight &&
        widget.initialHeight == null) {
      _pendingHeight = null;
      _height.value = widget.defaultHeight.clamp(
        widget.minHeight,
        widget.maxHeight,
      );
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
    _height.dispose();
    if (_internalFocusNode) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  void _applyDelta(double delta) {
    final newHeight = (_height.value + delta).clamp(
      widget.minHeight,
      widget.maxHeight,
    );
    if ((newHeight - _height.value).abs() > 0.01) {
      _height.value = newHeight;
      _pendingHeight = newHeight;
    }
  }

  void _commitHeight() {
    final height = _pendingHeight;
    _pendingHeight = null;
    if (height != null) widget.onHeightChanged?.call(height);
  }

  void _reset() {
    final target = widget.defaultHeight.clamp(
      widget.minHeight,
      widget.maxHeight,
    );
    if ((target - _height.value).abs() > 0.01) {
      _height.value = target;
      _pendingHeight = target;
      _commitHeight();
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget inputField = Padding(
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
          const SingleActivator(LogicalKeyboardKey.slash, control: true): () =>
              PromptEditActions.toggleDisabled(
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
        ValueListenableBuilder<double>(
          valueListenable: _height,
          child: inputField,
          builder: (context, height, child) =>
              SizedBox(height: height, child: child),
        ),
        PromptResizeHandle(
          tooltip: widget.resizeTooltip,
          onDelta: _applyDelta,
          onReset: _reset,
          onDragEnd: _commitHeight,
        ),
      ],
    );
  }
}
