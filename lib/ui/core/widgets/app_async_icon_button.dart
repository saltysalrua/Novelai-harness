import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import '../theme/theme_context_extensions.dart';
import 'app_icon_button.dart';

/// 统一带异步加载与拦截连击指示的图标按钮 (AppAsyncIconButton)
///
/// 代码证据出处：
/// - `generate_dock.dart:215-241` (_RefreshButton 账号体力点数刷新键)
/// - `agent_chat_input_bar.dart:525-557` (发送/流式响应终止键)
///
/// 核心职责：
/// 在 `isLoading == true` 时平滑将图标过渡为 14~16px 的微型 `CircularProgressIndicator` (strokeWidth: 2)，
/// 自动拦截重复连击与并发触发，支持四套与 [AppIconButton] 统一的视觉变体。
class AppAsyncIconButton extends StatefulWidget {
  /// 是否正在异步执行/加载中
  final bool isLoading;

  /// 常态展示的图标
  final IconData icon;

  /// 点击事件；[isLoading] 为 true 时自动忽略点击以拦截连击
  final VoidCallback? onPressed;

  /// 常态悬停提示文本 (可选)
  final String? tooltip;

  /// 加载中悬停提示文本 (可选)
  final String? loadingTooltip;

  /// 按钮外观尺寸 (方形边长)，默认 28.0
  final double size;

  /// 图标大小；若未指定则自动按 [size] 的 0.54 等比缩放
  final double? iconSize;

  /// 微型进度指示器直径，默认 14.0
  final double loadingIndicatorSize;

  /// 进度条线条粗细，默认 2.0
  final double loadingStrokeWidth;

  /// 视觉变体，默认 [AppIconButtonVariant.outlined]
  final AppIconButtonVariant variant;

  /// 自定义图标颜色
  final Color? iconColor;

  /// 自定义加载指示器颜色 (默认对齐图标颜色或品牌主色)
  final Color? loadingColor;

  /// 自定义背景色
  final Color? backgroundColor;

  /// 自定义边框颜色
  final Color? borderColor;

  /// 圆角大小，默认 [AppRadius.md] (8.0)
  final double radius;

  /// 是否启用按钮，默认 true
  final bool enabled;

  const AppAsyncIconButton({
    super.key,
    required this.isLoading,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.loadingTooltip,
    this.size = 28.0,
    this.iconSize,
    this.loadingIndicatorSize = 14.0,
    this.loadingStrokeWidth = 2.0,
    this.variant = AppIconButtonVariant.outlined,
    this.iconColor,
    this.loadingColor,
    this.backgroundColor,
    this.borderColor,
    this.radius = AppRadius.md,
    this.enabled = true,
  });

  @override
  State<AppAsyncIconButton> createState() => _AppAsyncIconButtonState();
}

class _AppAsyncIconButtonState extends State<AppAsyncIconButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isInteractive =
        widget.enabled && !widget.isLoading && widget.onPressed != null;

    final double effectiveIconSize =
        widget.iconSize ?? (widget.size * 0.54).clamp(12.0, 24.0);

    final (
      Color bg,
      Color border,
      Color fg,
      List<BoxShadow>? shadow,
    ) = switch (widget.variant) {
      AppIconButtonVariant.outlined => (
        widget.backgroundColor ?? colors.cardBackground,
        widget.borderColor ??
            (_isHovered && isInteractive
                ? colors.borderHover
                : colors.borderDefault),
        widget.iconColor ??
            (_isHovered && isInteractive
                ? colors.textPrimary
                : colors.textSecondary),
        isInteractive && _isHovered ? context.shadowSubtle : null,
      ),
      AppIconButtonVariant.elevated => (
        widget.backgroundColor ?? colors.cardBackground,
        widget.borderColor ?? colors.borderSubtle,
        widget.iconColor ??
            (_isHovered && isInteractive ? colors.primary : colors.textPrimary),
        isInteractive ? context.shadowSubtle : null,
      ),
      AppIconButtonVariant.primary => (
        widget.backgroundColor ??
            (_isHovered && isInteractive ? colors.primaryDark : colors.primary),
        widget.borderColor ?? Colors.transparent,
        widget.iconColor ?? Colors.white,
        isInteractive && _isHovered
            ? AppShadows.subtle(
                colors.primary,
                brightness: context.themeBrightness,
              )
            : null,
      ),
      AppIconButtonVariant.ghost => (
        widget.backgroundColor ??
            (_isHovered && isInteractive
                ? colors.mutedBackground
                : Colors.transparent),
        widget.borderColor ?? Colors.transparent,
        widget.iconColor ??
            (_isHovered && isInteractive
                ? colors.textPrimary
                : colors.textSecondary),
        null,
      ),
    };

    final effectiveBg = isInteractive || widget.isLoading
        ? bg
        : colors.mutedBackground.withValues(alpha: 0.5);
    final effectiveFg = isInteractive || widget.isLoading
        ? fg
        : colors.textMuted.withValues(alpha: 0.5);
    final effectiveBorder = isInteractive || widget.isLoading
        ? border
        : colors.borderSubtle;
    final effectiveLoadingColor =
        widget.loadingColor ??
        (widget.variant == AppIconButtonVariant.primary
            ? Colors.white
            : colors.primary);

    Widget innerContent = AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(scale: anim, child: child),
      ),
      child: widget.isLoading
          ? SizedBox(
              key: const ValueKey('loading'),
              width: widget.loadingIndicatorSize,
              height: widget.loadingIndicatorSize,
              child: CircularProgressIndicator(
                strokeWidth: widget.loadingStrokeWidth,
                valueColor: AlwaysStoppedAnimation<Color>(
                  effectiveLoadingColor,
                ),
              ),
            )
          : Icon(
              widget.icon,
              key: const ValueKey('icon'),
              size: effectiveIconSize,
              color: effectiveFg,
            ),
    );

    Widget button = InkWell(
      onTap: isInteractive ? widget.onPressed : null,
      borderRadius: BorderRadius.circular(widget.radius),
      hoverColor: Colors.transparent,
      splashColor: isInteractive
          ? colors.primaryTint.withValues(alpha: 0.3)
          : Colors.transparent,
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: effectiveBg,
          borderRadius: BorderRadius.circular(widget.radius),
          border: effectiveBorder != Colors.transparent
              ? Border.all(color: effectiveBorder)
              : null,
          boxShadow: shadow,
        ),
        alignment: Alignment.center,
        child: innerContent,
      ),
    );

    if (isInteractive) {
      button = MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: button,
      );
    }

    final currentTooltip = widget.isLoading
        ? (widget.loadingTooltip ?? widget.tooltip)
        : widget.tooltip;

    if (currentTooltip != null && currentTooltip.isNotEmpty) {
      button = Tooltip(message: currentTooltip, child: button);
    }

    return button;
  }
}
