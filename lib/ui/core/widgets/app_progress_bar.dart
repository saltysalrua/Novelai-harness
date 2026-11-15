import 'package:flutter/material.dart';
import '../theme/app_motion.dart';
import '../theme/app_tokens.dart';
import '../theme/theme_context_extensions.dart';

/// 统一圆角微型进度条 (AppProgressBar)
///
/// 代码证据出处：
/// - `studio_shared.dart:251-270` (TokenProgressBar 提示词 Token 占用进度条，3px 蓝底)
/// - `generate_dock.dart:143-150` (V5 体力条，5px 绿/橙/红三色阈值预警)
///
/// 核心职责：
/// 统一极简圆角进度条封装，支持 2~6px 细高度、圆角抗锯齿切边、
/// 确定态数值平滑插值 (`smoothOut`)、不定态流光扫掠 (`15-shimmer-text` 风格)
/// 与基于百分比阈值的动态语义着色 (绿/橙/红)，同时安全适配减弱动画设置。
class AppProgressBar extends StatelessWidget {
  /// 当前进度比例 (0.0 ~ 1.0)；传 null 时进入不定态流光模式
  final double? value;

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
    this.value,
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
    final resolvedBgColor =
        backgroundColor ?? colors.mutedBackground.withValues(alpha: 0.8);

    if (value == null) {
      final indeterminateColor = color ?? colors.primary;
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: _IndeterminateShimmerTrack(
          height: height,
          color: indeterminateColor,
          backgroundColor: resolvedBgColor,
        ),
      );
    }

    final clampedValue = value!.clamp(0.0, 1.0);

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

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: clampedValue),
        duration: AppMotion.resolveDuration(context, AppMotionDurations.fast),
        curve: AppMotionCurves.smoothOut,
        builder: (context, animatedValue, _) {
          return LinearProgressIndicator(
            value: animatedValue.clamp(0.0, 1.0),
            minHeight: height,
            backgroundColor: resolvedBgColor,
            valueColor: AlwaysStoppedAnimation<Color>(resolvedColor),
          );
        },
      ),
    );
  }
}

class _IndeterminateShimmerTrack extends StatefulWidget {
  final double height;
  final Color color;
  final Color backgroundColor;

  const _IndeterminateShimmerTrack({
    required this.height,
    required this.color,
    required this.backgroundColor,
  });

  @override
  State<_IndeterminateShimmerTrack> createState() =>
      _IndeterminateShimmerTrackState();
}

class _IndeterminateShimmerTrackState extends State<_IndeterminateShimmerTrack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppMotionDurations.shimmer,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = AppMotion.shouldReduceMotion(context);
    if (_reduceMotion) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_reduceMotion) {
      return Container(
        height: widget.height,
        color: Color.alphaBlend(
          widget.color.withValues(alpha: 0.45),
          widget.backgroundColor,
        ),
      );
    }

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          const halfBand = 0.24;
          final center = -halfBand + _controller.value * (1.0 + halfBand * 2.0);
          final beginX = (center - halfBand) * 2.0 - 1.0;
          final endX = (center + halfBand) * 2.0 - 1.0;

          return SizedBox(
            height: widget.height,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: widget.backgroundColor,
                gradient: LinearGradient(
                  begin: Alignment(beginX, 0),
                  end: Alignment(endX, 0),
                  colors: [
                    widget.backgroundColor,
                    widget.color.withValues(alpha: 0.65),
                    widget.color,
                    widget.color.withValues(alpha: 0.65),
                    widget.backgroundColor,
                  ],
                  stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
