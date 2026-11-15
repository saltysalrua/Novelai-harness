import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme/app_motion.dart';
import '../theme/app_tokens.dart';
import '../theme/theme_context_extensions.dart';

/// 骨架屏脉冲占位块 (`14-skeleton-reveal`)
///
/// 适用场景：列表行、模型卡片、图库缩略图与用户信息条加载中的占位骨架。
/// 动画特征：1000ms 周期在 `1.0` 与 [minOpacity] (默认 `0.5`) 之间呼吸脉冲；
/// 开启系统减弱动画或 [animate] 为 false 时静默渲染静态占位块。
class AppSkeletonBox extends StatefulWidget {
  /// 占位块宽度 (null 时随父约束自适应)
  final double? width;

  /// 占位块高度，默认 14.0
  final double height;

  /// 自定义圆角 (优先于 [radius])
  final BorderRadius? borderRadius;

  /// 圆角半径，默认 [AppRadius.sm] (4.0)
  final double radius;

  /// 填充色 (默认融合主题 `mutedBackground` 与 `borderDefault`)
  final Color? color;

  /// 脉冲最低不透明度，默认 0.5 (`--pulse-min`)
  final double minOpacity;

  /// 单轮脉冲周期，默认 [AppMotionDurations.skeletonPulse] (1000ms)
  final Duration pulseDuration;

  /// 是否启用脉冲呼吸动画，默认 true
  final bool animate;

  /// 盒体形状，默认 [BoxShape.rectangle]
  final BoxShape shape;

  const AppSkeletonBox({
    super.key,
    this.width,
    this.height = 14.0,
    this.borderRadius,
    this.radius = AppRadius.sm,
    this.color,
    this.minOpacity = 0.5,
    this.pulseDuration = AppMotionDurations.skeletonPulse,
    this.animate = true,
    this.shape = BoxShape.rectangle,
  });

  /// 便捷构造：圆形占位 (头像、图标位)
  const AppSkeletonBox.circle({
    super.key,
    required double size,
    this.color,
    this.minOpacity = 0.5,
    this.pulseDuration = AppMotionDurations.skeletonPulse,
    this.animate = true,
  }) : width = size,
       height = size,
       borderRadius = null,
       radius = 0,
       shape = BoxShape.circle;

  /// 便捷构造：全宽文本行占位
  const AppSkeletonBox.line({
    super.key,
    this.width = double.infinity,
    this.height = 12.0,
    this.borderRadius,
    this.radius = AppRadius.sm,
    this.color,
    this.minOpacity = 0.5,
    this.pulseDuration = AppMotionDurations.skeletonPulse,
    this.animate = true,
  }) : shape = BoxShape.rectangle;

  @override
  State<AppSkeletonBox> createState() => _AppSkeletonBoxState();
}

class _AppSkeletonBoxState extends State<AppSkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _reduceMotion = false;

  bool get _shouldAnimate => widget.animate && !_reduceMotion;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.pulseDuration,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = AppMotion.shouldReduceMotion(context);
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant AppSkeletonBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pulseDuration != widget.pulseDuration) {
      _controller.duration = widget.pulseDuration;
    }
    if (oldWidget.animate != widget.animate ||
        oldWidget.pulseDuration != widget.pulseDuration) {
      _syncTicker();
    }
  }

  void _syncTicker() {
    if (_shouldAnimate) {
      if (!_controller.isAnimating) {
        _controller.repeat();
      }
    } else {
      if (_controller.isAnimating) {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final resolvedColor =
        widget.color ??
        Color.lerp(colors.mutedBackground, colors.borderDefault, 0.45) ??
        colors.mutedBackground;

    final box = SizedBox(
      width: widget.width,
      height: widget.height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: resolvedColor,
          shape: widget.shape,
          borderRadius: widget.shape == BoxShape.circle
              ? null
              : (widget.borderRadius ?? BorderRadius.circular(widget.radius)),
        ),
      ),
    );

    if (!_shouldAnimate) {
      final staticOpacity = ((1.0 + widget.minOpacity) * 0.5).clamp(0.0, 1.0);
      return Opacity(opacity: staticOpacity, child: box);
    }

    final minOp = widget.minOpacity.clamp(0.0, 1.0);

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          // 0 -> 0.5 -> 1.0 平滑余弦呼吸 (1.0 -> minOp -> 1.0)
          final wave = 0.5 + 0.5 * math.cos(_controller.value * 2.0 * math.pi);
          final opacity = (minOp + (1.0 - minOp) * wave).clamp(0.0, 1.0);
          return Opacity(opacity: opacity, child: child);
        },
        child: box,
      ),
    );
  }
}

/// 骨架屏向真实内容的交叉溶解揭示容器 (`14-skeleton-reveal`)
///
/// 适用场景：数据异步就绪时从 [skeleton] 占位无缝交叉淡入到 [child] 真实内容。
/// 动画特征：400ms `easeInOut`，同步交叉透明度与可选 2px 轻模糊；
/// 复位为加载态 (`isLoaded: true -> false`) 默认即时跳回骨架避免反向卡顿；
/// 揭示完成后自动停止并卸载骨架子树释放动画 Ticker。
class AppSkeletonReveal extends StatefulWidget {
  /// 内容是否已加载就绪
  final bool isLoaded;

  /// 加载中展示的骨架占位布局
  final Widget skeleton;

  /// 加载完成后的真实内容组件
  final Widget child;

  /// 揭示过渡时长，默认 [AppMotionDurations.skeletonReveal] (400ms)
  final Duration duration;

  /// 缓动曲线，默认 [AppMotionCurves.inOut]
  final Curve curve;

  /// 交叉模糊半径，默认 [AppMotionBlurs.small] (2.0)
  final double blurSigma;

  /// 是否叠加交叉轻模糊，默认 true
  final bool enableBlur;

  /// 叠放对齐方式，默认 [Alignment.topLeft]
  final AlignmentGeometry alignment;

  /// 从已加载重置为加载中时是否播放反向动画，默认 false (即时复位)
  final bool animateReverse;

  const AppSkeletonReveal({
    super.key,
    required this.isLoaded,
    required this.skeleton,
    required this.child,
    this.duration = AppMotionDurations.skeletonReveal,
    this.curve = AppMotionCurves.inOut,
    this.blurSigma = AppMotionBlurs.small,
    this.enableBlur = true,
    this.alignment = Alignment.topLeft,
    this.animateReverse = false,
  });

  @override
  State<AppSkeletonReveal> createState() => _AppSkeletonRevealState();
}

class _AppSkeletonRevealState extends State<AppSkeletonReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
      value: widget.isLoaded ? 1.0 : 0.0,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = AppMotion.shouldReduceMotion(context);
    if (_reduceMotion) {
      _controller.value = widget.isLoaded ? 1.0 : 0.0;
    }
  }

  @override
  void didUpdateWidget(covariant AppSkeletonReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      _controller.duration = widget.duration;
    }
    if (oldWidget.isLoaded != widget.isLoaded) {
      if (_reduceMotion) {
        _controller.value = widget.isLoaded ? 1.0 : 0.0;
      } else if (widget.isLoaded) {
        _controller.forward(from: 0.0);
      } else if (widget.animateReverse) {
        _controller.reverse();
      } else {
        _controller.value = 0.0;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _applyOptionalBlur(double sigma, Widget target) {
    if (!widget.enableBlur || sigma <= 0.05) {
      return target;
    }
    final clamped = sigma.clamp(0.0, 24.0);
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: clamped, sigmaY: clamped),
      child: target,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_reduceMotion) {
      return widget.isLoaded ? widget.child : widget.skeleton;
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        if (_controller.isCompleted && widget.isLoaded) {
          return widget.child;
        }
        if (_controller.isDismissed && !widget.isLoaded) {
          return widget.skeleton;
        }

        final t = widget.curve.transform(_controller.value).clamp(0.0, 1.0);
        final skelOpacity = (1.0 - t).clamp(0.0, 1.0);
        final skelSigma = widget.blurSigma * t;
        final contentSigma = widget.blurSigma * (1.0 - t);

        return Stack(
          alignment: widget.alignment,
          children: [
            if (skelOpacity > 0.005)
              IgnorePointer(
                child: Opacity(
                  opacity: skelOpacity,
                  child: _applyOptionalBlur(skelSigma, widget.skeleton),
                ),
              ),
            Opacity(
              opacity: t,
              child: _applyOptionalBlur(contentSigma, widget.child),
            ),
          ],
        );
      },
    );
  }
}
