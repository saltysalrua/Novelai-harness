import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import '../theme/theme_context_extensions.dart';

/// 统一搜索与过滤输入框组件 (Search Field)
///
/// 代码证据出处：
/// - `prompt_library_view.dart:366-395` (提示词库检索框)
/// - `tag_browser_dialog.dart:123-165` (Danbooru 词库检索弹窗输入框)
/// - `models_settings_tab.dart:910-940` (LLM 模型列表过滤框)
/// - `agent_session_list_view.dart:25-50` (历史对话列表检索框)
///
/// 核心职责：
/// 统一高度 (34px)、放大镜搜索前缀、内容非空时自动出现的一键清空叉号按钮，
/// 内置防抖机制 (Debounce)，消灭业务层重复配置 `TextField + InputDecoration + Timer`。
class AppSearchField extends StatefulWidget {
  /// 外部绑定的控制器；若为空则在内部管理
  final TextEditingController? controller;

  /// 占位引导文案
  final String hintText;

  /// 搜索输入变化回调 (支持防抖)
  final ValueChanged<String>? onChanged;

  /// 提交搜索回调 (按下回车)
  final ValueChanged<String>? onSubmitted;

  /// 清空按钮触发回调
  final VoidCallback? onClear;

  /// 防抖间隔时间，默认为 250ms；若设为 [Duration.zero] 则实时同步
  final Duration debounceDuration;

  /// 控件高度，默认 34.0
  final double height;

  /// 文本字号，默认 12.5
  final double fontSize;

  /// 是否自动获取焦点，默认 false
  final bool autofocus;

  /// 外部 FocusNode
  final FocusNode? focusNode;

  /// 圆角大小，默认 [AppRadius.md] (8px)
  final double radius;

  const AppSearchField({
    super.key,
    this.controller,
    this.hintText = '搜索...',
    this.onChanged,
    this.onSubmitted,
    this.onClear,
    this.debounceDuration = const Duration(milliseconds: 250),
    this.height = 34.0,
    this.fontSize = 12.5,
    this.autofocus = false,
    this.focusNode,
    this.radius = AppRadius.md,
  });

  @override
  State<AppSearchField> createState() => _AppSearchFieldState();
}

class _AppSearchFieldState extends State<AppSearchField> {
  late TextEditingController _controller;
  Timer? _debounceTimer;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    _hasText = _controller.text.isNotEmpty;
    _controller.addListener(_handleTextChange);
  }

  @override
  void didUpdateWidget(covariant AppSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      if (oldWidget.controller == null) {
        _controller.removeListener(_handleTextChange);
        _controller.dispose();
      } else {
        oldWidget.controller!.removeListener(_handleTextChange);
      }

      _controller = widget.controller ?? TextEditingController();
      _hasText = _controller.text.isNotEmpty;
      _controller.addListener(_handleTextChange);
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.removeListener(_handleTextChange);
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _handleTextChange() {
    final nowHasText = _controller.text.isNotEmpty;
    if (_hasText != nowHasText) {
      setState(() {
        _hasText = nowHasText;
      });
    }

    if (widget.onChanged != null) {
      if (widget.debounceDuration == Duration.zero) {
        widget.onChanged!(_controller.text);
      } else {
        _debounceTimer?.cancel();
        _debounceTimer = Timer(widget.debounceDuration, () {
          if (mounted) {
            widget.onChanged!(_controller.text);
          }
        });
      }
    }
  }

  void _handleClear() {
    _debounceTimer?.cancel();
    _controller.clear();
    widget.onClear?.call();
    widget.onChanged?.call('');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return SizedBox(
      height: widget.height,
      child: TextField(
        controller: _controller,
        autofocus: widget.autofocus,
        focusNode: widget.focusNode,
        style: TextStyle(
          fontSize: widget.fontSize,
          color: colors.textPrimary,
        ),
        textAlignVertical: TextAlignVertical.center,
        decoration: InputDecoration(
          hintText: widget.hintText,
          hintStyle: TextStyle(
            fontSize: widget.fontSize,
            color: colors.textMuted,
          ),
          filled: true,
          fillColor: colors.cardBackground,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
          prefixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 34),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 16,
            color: colors.textMuted,
          ),
          suffixIconConstraints: const BoxConstraints(minWidth: 28, minHeight: 34),
          suffixIcon: _hasText
              ? IconButton(
                  icon: const Icon(Icons.close_rounded, size: 14),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  splashRadius: 14,
                  color: colors.textSecondary,
                  tooltip: '清空输入',
                  onPressed: _handleClear,
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(widget.radius),
            borderSide: BorderSide(color: colors.borderDefault),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(widget.radius),
            borderSide: BorderSide(color: colors.borderDefault),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(widget.radius),
            borderSide: BorderSide(color: colors.primary, width: 1.5),
          ),
        ),
        onSubmitted: (val) {
          _debounceTimer?.cancel();
          widget.onSubmitted?.call(val);
        },
      ),
    );
  }
}
