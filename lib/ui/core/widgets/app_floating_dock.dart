import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import '../theme/theme_context_extensions.dart';

/// 统一浮动操作坞与悬浮工具栏容器 (Floating Dock / Floating Toolbar)
///
/// 代码证据出处：
/// - `generate_dock.dart:63-75` (画板底部生成操作坞)
/// - `board_toolbar.dart:40-55` (画板顶部漫游/便利贴工具条)
/// - `inpaint_canvas_overlay.dart:767-780` (局部修复底部悬浮操作坞)
/// - `freeform_annotation_board.dart:430-445` (自由便签悬浮工具栏)
///
/// 核心职责：
/// 统一悬浮工具条的背景层级、边框、自适应立体阴影与圆角标尺，可选毛玻璃质感，
/// 消除业务层重复拼接 `BoxDecoration` 与硬编码阴影。
class AppFloatingDock extends StatelessWidget {
  /// 坞内子组件 (通常为 Row 或 Column 组合的工具项)
  final Widget child;

  /// 内边距，默认为 [AppSpacing.sm] (8px)
  final EdgeInsetsGeometry padding;

  /// 外边距，默认为空
  final EdgeInsetsGeometry? margin;

  /// 圆角半径，默认为 [AppRadius.md] (8px)
  final double radius;

  /// 自定义阴影；若未提供则使用 [context.shadowElevated] (亮暗自适应)
  final List<BoxShadow>? shadows;

  /// 自定义背景色；若未提供则使用 [AppColorsExtension.cardBackground]
  final Color? backgroundColor;

  /// 自定义边框颜色；若未提供则使用 [AppColorsExtension.borderDefault]
  final Color? borderColor;

  /// 是否启用毛玻璃背景模糊效果
  final bool enableBlur;

  /// 毛玻璃模糊 Sigma，默认 12.0
  final double blurSigma;

  const AppFloatingDock({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.sm),
    this.margin,
    this.radius = AppRadius.md,
    this.shadows,
    this.backgroundColor,
    this.borderColor,
    this.enableBlur = false,
    this.blurSigma = 12.0,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final effectiveBg = backgroundColor ?? colors.cardBackground;
    final effectiveBorder = borderColor ?? colors.borderDefault;
    final effectiveShadows = shadows ?? context.shadowElevated;
    final borderRadius = BorderRadius.circular(radius);

    Widget content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: enableBlur ? effectiveBg.withValues(alpha: 0.88) : effectiveBg,
        borderRadius: borderRadius,
        border: Border.all(color: effectiveBorder),
        boxShadow: effectiveShadows,
      ),
      child: child,
    );

    if (enableBlur) {
      content = ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: content,
        ),
      );
    }

    if (margin != null) {
      content = Padding(padding: margin!, child: content);
    }

    return content;
  }
}
