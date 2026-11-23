import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_motion.dart';
import '../theme/app_tokens.dart';
import '../theme/theme_context_extensions.dart';

/// 弹簧回弹开关控件 (`27-toggle`)
///
/// 适用场景：设置页开关行、参数面板布尔选项。
/// 动画特征：
/// - 滑块以 350ms `toggleBounce` 弹簧曲线横向穿梭并伴随轻微过冲；
/// - 轨道颜色按 150ms `smoothOut` 平滑交叉渐变；
/// - 首次挂载直接处于目标状态，不触发多余回弹动画；减弱动态效果开启时即时切换。
class AppSwitch extends StatefulWidget {
  /// 当前开关状态
  final bool value;

  /// 状态变更回调；为 null 时呈禁用态
  final ValueChanged<bool>? onChanged;

  /// 轨道宽度，默认 38.0
  final double width;

  /// 轨道高度，默认 22.0
  final double height;

  /// 开启态轨道颜色 (默认取主题 `primary`)
  final Color? activeColor;

  /// 关闭态轨道颜色 (默认取主题 `mutedBackground`)
  final Color? inactiveColor;

  /// 滑块颜色 (默认纯白)
  final Color? thumbColor;

  /// 无障碍语义标签
  final String? semanticLabel;

  const AppSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.width = 38.0,
    this.height = 22.0,
    this.activeColor,
    this.inactiveColor,
    this.thumbColor,
    this.semanticLabel,
  });

  @override
  State<AppSwitch> createState() => _AppSwitchState();
}

class _AppSwitchState extends State<AppSwitch>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _thumbCurve;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppMotionDurations.medium,
      value: widget.value ? 1.0 : 0.0,
    );
    _thumbCurve = CurvedAnimation(
      parent: _controller,
      curve: AppMotionCurves.toggleBounce,
      reverseCurve: AppMotionCurves.toggleBounce.flipped,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = AppMotion.shouldReduceMotion(context);
    if (_reduceMotion) {
      _controller.value = widget.value ? 1.0 : 0.0;
    }
  }

  @override
  void didUpdateWidget(covariant AppSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      if (_reduceMotion) {
        _controller.value = widget.value ? 1.0 : 0.0;
      } else if (widget.value) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _thumbCurve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = widget.onChanged != null;
    final activeTrack = widget.activeColor ?? colors.primary;
    final inactiveTrack = widget.inactiveColor ?? colors.mutedBackground;
    final inactiveThumb = widget.thumbColor ?? Colors.white;
    final activeThumb =
        widget.thumbColor ??
        (widget.activeColor == null ? colors.onPrimary : Colors.white);

    final thumbDiameter = (widget.height - 4.0).clamp(10.0, widget.height);
    final travel = (widget.width - thumbDiameter - 4.0).clamp(
      0.0,
      widget.width,
    );

    Widget control = Semantics(
      toggled: widget.value,
      enabled: enabled,
      label: widget.semanticLabel,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? () => widget.onChanged!(!widget.value) : null,
          child: Opacity(
            opacity: enabled ? 1.0 : 0.5,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final colorT = AppMotionCurves.smoothOut
                    .transform(_controller.value)
                    .clamp(0.0, 1.0);
                final trackColor =
                    Color.lerp(inactiveTrack, activeTrack, colorT) ??
                    inactiveTrack;
                final borderColor =
                    Color.lerp(
                      colors.borderDefault,
                      activeTrack.withValues(alpha: 0.0),
                      colorT,
                    ) ??
                    colors.borderDefault;
                final thumbFill =
                    Color.lerp(inactiveThumb, activeThumb, colorT) ??
                    inactiveThumb;
                final thumbLeft = 2.0 + travel * _thumbCurve.value;

                return Container(
                  width: widget.width,
                  height: widget.height,
                  decoration: BoxDecoration(
                    color: trackColor,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    border: Border.all(color: borderColor, width: 1),
                  ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.centerLeft,
                    children: [
                      Positioned(
                        left: thumbLeft,
                        child: Container(
                          width: thumbDiameter,
                          height: thumbDiameter,
                          decoration: BoxDecoration(
                            color: thumbFill,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.16),
                                blurRadius: 3,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );

    return control;
  }
}

/// 路径描边复选框 (`25-checkbox-check`)
///
/// 适用场景：多选列表、参数启用复选框、同意条款确认框。
/// 动画特征：方框背景 150ms 填充，勾选路径 350ms 描边绘出；取消勾选时 150ms 快速收回。
class AppCheckbox extends StatefulWidget {
  /// 当前勾选状态
  final bool value;

  /// 状态变更回调；为 null 时呈禁用态
  final ValueChanged<bool>? onChanged;

  /// 方框边长，默认 18.0
  final double size;

  /// 圆角半径，默认 5.0
  final double borderRadius;

  /// 选中填充色 (默认取主题 `primary`)
  final Color? activeColor;

  /// 未选中边框色 (默认取主题 `borderHover`)
  final Color? borderColor;

  /// 勾选对勾颜色 (默认纯白)
  final Color? checkColor;

  /// 可选右侧文本标签
  final String? label;

  /// 标签文本样式
  final TextStyle? labelStyle;

  /// 无障碍语义标签
  final String? semanticLabel;

  const AppCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.size = 18.0,
    this.borderRadius = 5.0,
    this.activeColor,
    this.borderColor,
    this.checkColor,
    this.label,
    this.labelStyle,
    this.semanticLabel,
  });

  @override
  State<AppCheckbox> createState() => _AppCheckboxState();
}

class _AppCheckboxState extends State<AppCheckbox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppMotionDurations.medium,
      reverseDuration: AppMotionDurations.quick,
      value: widget.value ? 1.0 : 0.0,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = AppMotion.shouldReduceMotion(context);
    if (_reduceMotion) {
      _controller.value = widget.value ? 1.0 : 0.0;
    }
  }

  @override
  void didUpdateWidget(covariant AppCheckbox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      if (_reduceMotion) {
        _controller.value = widget.value ? 1.0 : 0.0;
      } else if (widget.value) {
        _controller.forward();
      } else {
        _controller.reverse();
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
    final enabled = widget.onChanged != null;
    final activeBg = widget.activeColor ?? colors.primary;
    final inactiveBorder = widget.borderColor ?? colors.borderHover;
    final strokeColor =
        widget.checkColor ??
        (widget.activeColor == null ? colors.onPrimary : Colors.white);
    final boxDuration = AppMotion.resolveDuration(
      context,
      AppMotionDurations.quick,
    );

    final box = AnimatedContainer(
      duration: boxDuration,
      curve: AppMotionCurves.smoothOut,
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: widget.value ? activeBg : colors.cardBackground,
        borderRadius: BorderRadius.circular(widget.borderRadius),
        border: Border.all(
          color: widget.value ? activeBg : inactiveBorder,
          width: 1.5,
        ),
      ),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = AppMotionCurves.smoothOut
              .transform(_controller.value)
              .clamp(0.0, 1.0);
          return CustomPaint(
            painter: _CheckboxCheckPainter(
              progress: t,
              color: strokeColor,
              strokeWidth: (widget.size * 0.12).clamp(1.6, 2.6),
            ),
          );
        },
      ),
    );

    Widget content = box;
    if (widget.label != null && widget.label!.isNotEmpty) {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          box,
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              widget.label!,
              style:
                  widget.labelStyle ??
                  TextStyle(fontSize: 13, color: colors.textPrimary),
            ),
          ),
        ],
      );
    }

    return Semantics(
      checked: widget.value,
      enabled: enabled,
      label: widget.semanticLabel ?? widget.label,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? () => widget.onChanged!(!widget.value) : null,
          child: Opacity(opacity: enabled ? 1.0 : 0.5, child: content),
        ),
      ),
    );
  }
}

class _CheckboxCheckPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double strokeWidth;

  const _CheckboxCheckPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.0) return;

    final path = Path()
      ..moveTo(size.width * 0.22, size.height * 0.53)
      ..lineTo(size.width * 0.42, size.height * 0.74)
      ..lineTo(size.width * 0.78, size.height * 0.28);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (progress >= 1.0) {
      canvas.drawPath(path, paint);
      return;
    }

    for (final metric in path.computeMetrics()) {
      canvas.drawPath(
        metric.extractPath(0.0, metric.length * progress),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CheckboxCheckPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

/// 收藏/点赞微弹跳按钮 (`23-like-button`)
///
/// 适用场景：画廊收藏、提示词模板点赞、快捷标记。
/// 动画特征：点亮时填充色 150ms 渐变 + 图标 `1.0 -> 0.82 -> 1.0` 过冲弹跳 + 8 粒放射微粒子；
/// 取消点赞时静默退回，不触发粒子庆祝。
class AppLikeButton extends StatefulWidget {
  /// 当前是否已点亮/收藏
  final bool liked;

  /// 点击切换回调
  final ValueChanged<bool>? onChanged;

  /// 图标尺寸，默认 20.0
  final double size;

  /// 点亮后颜色 (默认取主题 `coral`)
  final Color? likedColor;

  /// 未点亮颜色 (默认取主题 `textMuted`)
  final Color? unlikedColor;

  /// 可选右侧文案
  final String? label;

  /// 是否在点亮时播放粒子散射，默认 true
  final bool showParticles;

  /// 无障碍语义标签
  final String? semanticLabel;

  const AppLikeButton({
    super.key,
    required this.liked,
    required this.onChanged,
    this.size = 20.0,
    this.likedColor,
    this.unlikedColor,
    this.label,
    this.showParticles = true,
    this.semanticLabel,
  });

  @override
  State<AppLikeButton> createState() => _AppLikeButtonState();
}

class _AppLikeButtonState extends State<AppLikeButton>
    with SingleTickerProviderStateMixin {
  static const Cubic _likePopCurve = Cubic(0.34, 1.96, 0.64, 1.0);
  late final AnimationController _controller;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
      value: 1.0,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = AppMotion.shouldReduceMotion(context);
    if (_reduceMotion && _controller.isAnimating) {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(covariant AppLikeButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.liked && widget.liked && !_reduceMotion) {
      _controller.forward(from: 0.0);
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
    final enabled = widget.onChanged != null;
    final activeColor = widget.likedColor ?? colors.coral;
    final inactiveColor = widget.unlikedColor ?? colors.textMuted;
    final fillDuration = AppMotion.resolveDuration(
      context,
      AppMotionDurations.quick,
    );

    final iconWidget = AnimatedSwitcher(
      duration: fillDuration,
      child: Icon(
        widget.liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        key: ValueKey<bool>(widget.liked),
        size: widget.size,
        color: widget.liked ? activeColor : inactiveColor,
      ),
    );

    final Widget animatedIcon = _reduceMotion
        ? iconWidget
        : RepaintBoundary(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final v = _controller.value;
                // 前 350ms 执行图标微缩弹跳 (1.0 -> 0.82 -> 1.0)
                final popFrac = (v / (350.0 / 600.0)).clamp(0.0, 1.0);
                final double scale;
                if (!_controller.isAnimating || popFrac >= 1.0) {
                  scale = 1.0;
                } else if (popFrac < 0.30) {
                  final downT = popFrac / 0.30;
                  scale = 1.0 - 0.18 * downT;
                } else {
                  final upT = (popFrac - 0.30) / 0.70;
                  scale = 0.82 + 0.18 * _likePopCurve.transform(upT);
                }

                return Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    if (widget.showParticles && _controller.isAnimating)
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _LikeParticlePainter(
                            progress: v,
                            color: activeColor,
                            maxRadius: widget.size,
                          ),
                        ),
                      ),
                    Transform.scale(scale: scale, child: child),
                  ],
                );
              },
              child: iconWidget,
            ),
          );

    Widget content = animatedIcon;
    if (widget.label != null && widget.label!.isNotEmpty) {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          animatedIcon,
          const SizedBox(width: AppSpacing.xs + 2),
          Text(
            widget.label!,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: widget.liked ? activeColor : colors.textSecondary,
            ),
          ),
        ],
      );
    }

    return Semantics(
      button: true,
      selected: widget.liked,
      enabled: enabled,
      label: widget.semanticLabel ?? widget.label,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? () => widget.onChanged!(!widget.liked) : null,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: content,
          ),
        ),
      ),
    );
  }
}

class _LikeParticlePainter extends CustomPainter {
  final double progress;
  final Color color;
  final double maxRadius;

  const _LikeParticlePainter({
    required this.progress,
    required this.color,
    required this.maxRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.0 || progress >= 1.0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final t = Curves.easeOut.transform(progress).clamp(0.0, 1.0);
    final double opacity;
    if (progress < 0.2) {
      opacity = (progress / 0.2).clamp(0.0, 1.0);
    } else {
      opacity = (1.0 - (progress - 0.2) / 0.8).clamp(0.0, 1.0);
    }

    final paint = Paint()
      ..color = color.withValues(alpha: opacity)
      ..style = PaintingStyle.fill;

    for (var i = 0; i < 8; i++) {
      final angle = (i * math.pi / 4.0) - math.pi / 8.0;
      final distScale = i.isEven ? 1.0 : 0.82;
      final dist = maxRadius * distScale * t;
      final radius = (i.isEven ? 1.6 : 1.2) * (1.0 - 0.4 * t);
      final pos = Offset(
        center.dx + math.cos(angle) * dist,
        center.dy + math.sin(angle) * dist,
      );
      canvas.drawCircle(pos, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _LikeParticlePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.maxRadius != maxRadius;
  }
}
