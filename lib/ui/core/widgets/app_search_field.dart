import 'dart:async';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import '../context_l10n.dart';
import '../theme/app_motion.dart';
import '../theme/app_tokens.dart';
import '../theme/theme_context_extensions.dart';
import 'app_transitions.dart';

/// 统一搜索与过滤输入框组件 (Search Field)
///
/// 代码证据出处：
/// - `prompt_library_view.dart:366-395` (提示词库检索框)
/// - `tag_browser_dialog.dart:123-165` (Danbooru 词库检索弹窗输入框)
/// - `models_settings_tab.dart:910-940` (LLM 模型列表过滤框)
/// - `agent_session_list_view.dart:25-50` (历史对话列表检索框)
///
/// 核心职责：
/// 统一高度 (34px)、放大镜搜索前缀、内容非空时通过 [AppIconSwap] (`09-icon-swap`)
/// 切出的一键清空叉号按钮与清零溶散动效 (`13-input-clear-dissolve`)，
/// 内置防抖机制 (Debounce)，消灭业务层重复配置 `TextField + InputDecoration + Timer`。
class AppSearchField extends StatefulWidget {
  /// 外部绑定的控制器；若为空则在内部管理
  final TextEditingController? controller;

  /// 占位引导文案
  final String? hintText;

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

  /// 文本字号，默认 13
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
    this.hintText,
    this.onChanged,
    this.onSubmitted,
    this.onClear,
    this.debounceDuration = const Duration(milliseconds: 250),
    this.height = 34.0,
    this.fontSize = 13,
    this.autofocus = false,
    this.focusNode,
    this.radius = AppRadius.md,
  });

  @override
  State<AppSearchField> createState() => _AppSearchFieldState();
}

class _AppSearchFieldState extends State<AppSearchField>
    with SingleTickerProviderStateMixin {
  static const Duration _dissolveTotal = Duration(milliseconds: 700);

  late TextEditingController _controller;
  late final AnimationController _clearController;
  Timer? _debounceTimer;
  bool _hasText = false;
  bool _reduceMotion = false;
  String _clearingText = '';

  bool get _isDissolving => _clearController.isAnimating;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    _hasText = _controller.text.isNotEmpty;
    _controller.addListener(_handleTextChange);
    _clearController =
        AnimationController(vsync: this, duration: _dissolveTotal)
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed && mounted) {
              setState(() => _clearingText = '');
            }
          });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = AppMotion.shouldReduceMotion(context);
    if (_reduceMotion && _clearController.isAnimating) {
      _clearController.stop();
      _clearController.value = 0.0;
      _clearingText = '';
    }
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
    _clearController.dispose();
    _controller.removeListener(_handleTextChange);
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _handleTextChange() {
    final nowHasText = _controller.text.isNotEmpty;
    if (nowHasText && _clearingText.isNotEmpty) {
      _clearController.stop();
      _clearController.value = 0.0;
      _clearingText = '';
    }
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
    final previousText = _controller.text;
    _debounceTimer?.cancel();
    _controller.clear();
    if (!_reduceMotion && previousText.isNotEmpty) {
      setState(() => _clearingText = previousText);
      _clearController.forward(from: 0.0);
    }
    widget.onClear?.call();
    widget.onChanged?.call('');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final effectiveHint =
        widget.hintText ?? context.maybeL10n?.commonSearchHint ?? '搜索…';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final showDissolveOverlay =
        !_reduceMotion && _clearingText.isNotEmpty && _isDissolving;

    final field = TextField(
      controller: _controller,
      autofocus: widget.autofocus,
      focusNode: widget.focusNode,
      style: TextStyle(fontSize: widget.fontSize, color: colors.textPrimary),
      textAlignVertical: TextAlignVertical.center,
      decoration: InputDecoration(
        hintText: showDissolveOverlay ? null : effectiveHint,
        hintStyle: TextStyle(
          fontSize: widget.fontSize,
          color: colors.textMuted,
        ),
        filled: true,
        fillColor: colors.cardBackground,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 0,
        ),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 32,
          minHeight: 34,
        ),
        prefixIcon: Icon(
          Icons.search_rounded,
          size: 16,
          color: colors.textMuted,
        ),
        suffixIconConstraints: const BoxConstraints(
          minWidth: 28,
          minHeight: 34,
        ),
        suffixIcon: AppIconSwap(
          swapKey: _hasText,
          enableBlur: false,
          child: _hasText
              ? IconButton(
                  key: const ValueKey('clear_btn'),
                  icon: const Icon(Icons.close_rounded, size: 14),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 24,
                    minHeight: 24,
                  ),
                  splashRadius: 14,
                  color: colors.textSecondary,
                  tooltip: context.maybeL10n?.commonClearInput ?? '清空输入',
                  onPressed: _handleClear,
                )
              : const SizedBox.square(
                  key: ValueKey('clear_empty'),
                  dimension: 24,
                ),
        ),
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
    );

    if (!showDissolveOverlay) {
      return SizedBox(height: widget.height, child: field);
    }

    return SizedBox(
      height: widget.height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          field,
          Positioned.fill(
            child: IgnorePointer(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(widget.radius),
                child: AnimatedBuilder(
                  animation: _clearController,
                  builder: (context, _) {
                    final elapsedMs =
                        _clearController.value * _dissolveTotal.inMilliseconds;
                    final textRaw = (elapsedMs / 400.0).clamp(0.0, 1.0);
                    final easeT = AppMotionCurves.smoothOut
                        .transform(textRaw)
                        .clamp(0.0, 1.0);

                    final outDy = AppMotionDistances.medium * easeT;
                    final outOpacity = (1.0 - easeT).clamp(0.0, 1.0);
                    final outSigma = AppMotionBlurs.small * easeT;

                    final inDy = -AppMotionDistances.medium * (1.0 - easeT);
                    final inOpacity = (0.55 + 0.45 * easeT).clamp(0.0, 1.0);
                    final inSigma = AppMotionBlurs.small * (1.0 - easeT);

                    // 底部光晕扫掠包络 (50ms 延迟 -> 15% 处达到峰值 -> 柔和消退)
                    double glowOpacity = 0.0;
                    if (elapsedMs > 50.0) {
                      final gp = ((elapsedMs - 50.0) / 650.0).clamp(0.0, 1.0);
                      const peakAt = 0.15;
                      final env = gp < peakAt
                          ? gp / peakAt
                          : 1.0 - (gp - peakAt) / (1.0 - peakAt);
                      glowOpacity = (env * (isDark ? 0.35 : 0.22)).clamp(
                        0.0,
                        1.0,
                      );
                    }

                    Widget clearedTextWidget = Text(
                      _clearingText,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: TextStyle(
                        fontSize: widget.fontSize,
                        color: colors.textPrimary,
                      ),
                    );
                    if (outSigma > 0.05) {
                      clearedTextWidget = ImageFiltered(
                        imageFilter: ImageFilter.blur(
                          sigmaX: outSigma,
                          sigmaY: outSigma,
                        ),
                        child: clearedTextWidget,
                      );
                    }

                    Widget placeholderWidget = Text(
                      effectiveHint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: widget.fontSize,
                        color: colors.textMuted,
                      ),
                    );
                    if (inSigma > 0.05) {
                      placeholderWidget = ImageFiltered(
                        imageFilter: ImageFilter.blur(
                          sigmaX: inSigma,
                          sigmaY: inSigma,
                        ),
                        child: placeholderWidget,
                      );
                    }

                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        if (glowOpacity > 0.005)
                          Align(
                            alignment: Alignment.bottomCenter,
                            child: Container(
                              height: 10,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: [
                                    colors.primary.withValues(
                                      alpha: glowOpacity,
                                    ),
                                    colors.primary.withValues(alpha: 0.0),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.only(left: 34, right: 30),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Opacity(
                              opacity: inOpacity,
                              child: Transform.translate(
                                offset: Offset(0, inDy),
                                child: placeholderWidget,
                              ),
                            ),
                          ),
                        ),
                        if (outOpacity > 0.005)
                          Padding(
                            padding: const EdgeInsets.only(left: 34, right: 30),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Opacity(
                                opacity: outOpacity,
                                child: Transform.translate(
                                  offset: Offset(0, outDy),
                                  child: clearedTextWidget,
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
