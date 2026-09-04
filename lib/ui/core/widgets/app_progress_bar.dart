import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import '../theme/theme_context_extensions.dart';

/// 统一圆角微型进度条 (AppProgressBar)
///
/// 代码证据出处：
/// - `studio_shared.dart:251-270` (TokenProgressBar 提示词 Token 占用进度条，3px 蓝底)
/// - `generate_dock.dart:143-150` (V5 体力条，5px 绿/橙/红三色阈值预警)
///
/// 核心职责：
/// 统一极简圆角 `LinearProgressIndicator` 封装，支持 2~6px 细高度、
/// 圆角抗锯齿切边与基于百分比阈值的动态语义着色 (绿/橙/红)，消灭重复拼装。
class AppProgressBar extends StatelessWidget {
  /// 当前进度比例 (0.0 ~ 1.0)
  final double value;

  /// 进度条高度，默认 4.0 (常用规格 2.0 ~ 6.0)
  final double height;

  /// 圆角半径，默认 [AppRadius.pill]
  final double radius;

  /// 自定义进度条前景色 (指定后优先使用，不使用阈值着色)
  final Color? color;

  /// 自定义进度条背景轨道颜色
  final Color? backgroundColor;

  /// 是否启用基于百分比的绿/橙/红三色阈值预警着色，默认 false
  final bool useThresholdColors;

  /// 是否反转阈值颜色语义，默认 false。
  /// - 为 false 时 (余量/剩余体力模式)：>=80% 绿，30~80% 橙，<30% 红；
  /// - 为 true 时 (占用量/Token 容量模式)：>=90% 红，70~90% 橙，<70% 蓝/绿。
  final bool invertThresholds;

  /// 完全自定义的颜色计算函数 (可选)
  final Color Function(double value)? colorResolver;

  const AppProgressBar({
    super.key,
    required this.value,
    this.height = 4.0,
    this.radius = AppRadius.pill,
    this.color,
    this.backgroundColor,
    this.useThresholdColors = false,
    this.invertThresholds = false,
    this.colorResolver,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final clampedValue = value.clamp(0.0, 1.0);

    Color resolvedColor;
    if (color != null) {
      resolvedColor = color!;
    } else if (colorResolver != null) {
      resolvedColor = colorResolver!(clampedValue);
    } else if (useThresholdColors) {
      if (invertThresholds) {
        resolvedColor = clampedValue >= 0.90
            ? colors.error
            : (clampedValue >= 0.70 ? colors.warning : colors.primary);
      } else {
        resolvedColor = clampedValue >= 0.80
            ? colors.success
            : (clampedValue >= 0.30 ? colors.warning : colors.error);
      }
    } else {
      resolvedColor = colors.primary;
    }

    final resolvedBgColor =
        backgroundColor ?? colors.mutedBackground.withValues(alpha: 0.8);

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: LinearProgressIndicator(
        value: clampedValue,
        minHeight: height,
        backgroundColor: resolvedBgColor,
        valueColor: AlwaysStoppedAnimation<Color>(resolvedColor),
      ),
    );
  }
}
