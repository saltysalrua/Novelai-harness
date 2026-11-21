import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/app_motion.dart';
import '../theme/theme_context_extensions.dart';

/// 在布局阶段 (`persistentCallbacks`) 中挂载循环动画时，将 `controller.repeat()`
/// 推迟到帧末再启动，避免在 `SliverMultiBoxAdaptorElement.createChild` 阶段直接触发帧调度。
/// 仅启动 Ticker 而不替换子树，确保不会在 KeepAlive/SelectionArea 下产生未布局节点。
void _startRepeatSafely({
  required AnimationController controller,
  required bool isPending,
  required VoidCallback markPending,
  required VoidCallback clearPending,
  required bool Function() canRepeat,
}) {
  if (controller.isAnimating) return;
  if (SchedulerBinding.instance.schedulerPhase ==
      SchedulerPhase.persistentCallbacks) {
    if (isPending) return;
    markPending();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      clearPending();
      if (canRepeat() && !controller.isAnimating) {
        controller.repeat();
      }
    });
  } else {
    controller.repeat();
  }
}

/// 若 [enableBlur] 为 true 且 [sigma] 大于阈值，则包裹高斯模糊滤镜；
/// 否则直接透传 [child]，避免静态态产生额外的 `saveLayer` 开销。
Widget _maybeBlur({
  required bool enableBlur,
  required double sigma,
  required Widget child,
}) {
  if (!enableBlur || sigma <= 0.05) {
    return child;
  }
  final clamped = sigma.clamp(0.0, 24.0);
  return ImageFiltered(
    imageFilter: ImageFilter.blur(sigmaX: clamped, sigmaY: clamped),
    child: child,
  );
}

/// 图标原地切换动效 (`09-icon-swap`)
///
/// 适用场景：同一槽位内两个图标的交替切换 (展开/收起、播放/暂停、复制/已复制)。
/// 动画特征：250ms `easeInOut`，缩微比例 `0.25 -> 1.0` + 淡入淡出 + 可选 2px 轻模糊。
class AppIconSwap extends StatelessWidget {
  /// 当前展示的图标组件 (建议附带唯一 [Key]；或直接传入 [swapKey])
  final Widget child;

  /// 可选切换标识；非空时自动为 [child] 包装 `ValueKey(swapKey)`
  final Object? swapKey;

  /// 过渡时长，默认 [AppMotionDurations.fast] (250ms)
  final Duration duration;

  /// 缓动曲线，默认 [AppMotionCurves.inOut]
  final Curve curve;

  /// 起始缩放比例，默认 [AppMotionScales.iconSwapStart] (0.25)
  final double startScale;

  /// 模糊半径，默认 [AppMotionBlurs.small] (2.0)
  final double blurSigma;

  /// 是否在切换过程中叠加轻量模糊，默认 true
  final bool enableBlur;

  /// 对齐方式，默认 [Alignment.center]
  final AlignmentGeometry alignment;

  const AppIconSwap({
    super.key,
    required this.child,
    this.swapKey,
    this.duration = AppMotionDurations.fast,
    this.curve = AppMotionCurves.inOut,
    this.startScale = AppMotionScales.iconSwapStart,
    this.blurSigma = AppMotionBlurs.small,
    this.enableBlur = true,
    this.alignment = Alignment.center,
  });

  @override
  Widget build(BuildContext context) {
    final reduceMotion = AppMotion.shouldReduceMotion(context);
    final effectiveDuration = reduceMotion ? Duration.zero : duration;
    final keyedChild = swapKey != null
        ? KeyedSubtree(key: ValueKey<Object?>(swapKey), child: child)
        : child;

    return AnimatedSwitcher(
      duration: effectiveDuration,
      reverseDuration: effectiveDuration,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: alignment,
          children: [
            ...previousChildren,
            ?currentChild,
          ],
        );
      },
      transitionBuilder: (targetChild, animation) {
        if (reduceMotion) return targetChild;
        return AnimatedBuilder(
          animation: animation,
          builder: (context, innerChild) {
            final t = curve.transform(animation.value).clamp(0.0, 1.0);
            final scale = startScale + (1.0 - startScale) * t;
            final sigma = blurSigma * (1.0 - t);
            return Opacity(
              opacity: t,
              child: Transform.scale(
                scale: scale,
                child: _maybeBlur(
                  enableBlur: enableBlur,
                  sigma: sigma,
                  child: innerChild!,
                ),
              ),
            );
          },
          child: targetChild,
        );
      },
      child: keyedChild,
    );
  }
}

/// 文本状态原地切换动效 (`04-text-states-swap`)
///
/// 适用场景：状态标签原地更新 ("生成中…" -> "已完成"、"保存" -> "已保存")。
/// 动画特征：150ms `easeInOut`，旧文本向上退场 (-4px)，新文本从下方滑入 (+4px)，
/// 搭配透明度过渡与可选 2px 轻模糊。
class AppTextSwap extends StatelessWidget {
  /// 当前展示的文本内容
  final String text;

  /// 文本样式
  final TextStyle? style;

  /// 文本对齐方式
  final TextAlign? textAlign;

  /// 最大行数
  final int? maxLines;

  /// 溢出处理方式
  final TextOverflow? overflow;

  /// 切换时长，默认 [AppMotionDurations.quick] (150ms)
  final Duration duration;

  /// 缓动曲线，默认 [AppMotionCurves.inOut]
  final Curve curve;

  /// 垂直滑移距离，默认 [AppMotionDistances.micro] (4.0)
  final double distance;

  /// 模糊半径，默认 [AppMotionBlurs.small] (2.0)
  final double blurSigma;

  /// 是否启用轻量模糊，默认 true
  final bool enableBlur;

  /// 容器对齐方式，默认 [Alignment.centerLeft]
  final AlignmentGeometry alignment;

  const AppTextSwap({
    super.key,
    required this.text,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.duration = AppMotionDurations.quick,
    this.curve = AppMotionCurves.inOut,
    this.distance = AppMotionDistances.micro,
    this.blurSigma = AppMotionBlurs.small,
    this.enableBlur = true,
    this.alignment = Alignment.centerLeft,
  });

  @override
  Widget build(BuildContext context) {
    final reduceMotion = AppMotion.shouldReduceMotion(context);
    final effectiveDuration = reduceMotion ? Duration.zero : duration;
    final activeKey = ValueKey<String>(text);

    return AnimatedSwitcher(
      duration: effectiveDuration,
      reverseDuration: effectiveDuration,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: alignment,
          children: [
            ...previousChildren,
            ?currentChild,
          ],
        );
      },
      transitionBuilder: (targetChild, animation) {
        if (reduceMotion) return targetChild;
        final isIncoming = targetChild.key == activeKey;
        return AnimatedBuilder(
          animation: animation,
          builder: (context, innerChild) {
            final t = curve.transform(animation.value).clamp(0.0, 1.0);
            final dy = isIncoming
                ? distance * (1.0 - t)
                : -distance * (1.0 - t);
            final sigma = blurSigma * (1.0 - t);
            return Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, dy),
                child: _maybeBlur(
                  enableBlur: enableBlur,
                  sigma: sigma,
                  child: innerChild!,
                ),
              ),
            );
          },
          child: targetChild,
        );
      },
      child: Text(
        text,
        key: activeKey,
        style: style,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: overflow,
      ),
    );
  }
}

/// 数字逐位弹出动效 (`02-number-pop-in`)
///
/// 适用场景：Anlas 点数余额、计数器、参数数值更新。
/// 动画特征：每个字符独立入场，默认末尾两位按 70ms 步长交错延迟；
/// 空间位移使用 [AppMotionCurves.digitPop] 弹性过冲，透明度和模糊使用安全平滑曲线。
class AppNumberPopIn extends StatefulWidget {
  /// 待展示的数字或格式化字符串 (如 `"1,280"`、`"24"`)
  final String value;

  /// 文本样式
  final TextStyle? style;

  /// 单个字符动画时长，默认 [AppMotionDurations.numberPopIn] (500ms)
  final Duration duration;

  /// 交错延迟步长，默认 [AppMotionDurations.numberStagger] (70ms)
  final Duration staggerDelay;

  /// 入场位移距离，默认 [AppMotionDistances.base] (8.0)
  final double distance;

  /// 单位方向向量，默认 `Offset(0, 1)` (从下方升起)
  final Offset direction;

  /// 模糊半径，默认 [AppMotionBlurs.small] (2.0)
  final double blurSigma;

  /// 是否启用模糊，默认 true
  final bool enableBlur;

  /// 空间位移曲线，默认 [AppMotionCurves.digitPop] (仅限空间变换)
  final Curve spatialCurve;

  /// 是否仅对末尾两位字符做交错延迟 (对齐原配方小数/尾数节奏)；为 false 时全部逐位交错
  final bool staggerTrailingOnly;

  /// 首次挂载时是否播放入场动画，默认 false
  final bool animateOnMount;

  const AppNumberPopIn({
    super.key,
    required this.value,
    this.style,
    this.duration = AppMotionDurations.numberPopIn,
    this.staggerDelay = AppMotionDurations.numberStagger,
    this.distance = AppMotionDistances.base,
    this.direction = const Offset(0, 1),
    this.blurSigma = AppMotionBlurs.small,
    this.enableBlur = true,
    this.spatialCurve = AppMotionCurves.digitPop,
    this.staggerTrailingOnly = true,
    this.animateOnMount = false,
  });

  @override
  State<AppNumberPopIn> createState() => _AppNumberPopInState();
}

class _AppNumberPopInState extends State<AppNumberPopIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _reduceMotion = false;

  int get _charCount => widget.value.runes.length;

  int _staggerUnitsForIndex(int index, int total) {
    if (total <= 1) return 0;
    if (widget.staggerTrailingOnly) {
      if (index == total - 2) return 1;
      if (index == total - 1) return 2;
      return 0;
    }
    return index;
  }

  Duration _computeTotalDuration(int total) {
    if (total <= 1) return widget.duration;
    final maxUnits = widget.staggerTrailingOnly ? 2 : (total - 1);
    return widget.duration + widget.staggerDelay * maxUnits;
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _computeTotalDuration(_charCount),
      value: widget.animateOnMount ? 0.0 : 1.0,
    );
    if (widget.animateOnMount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_reduceMotion) {
          _controller.value = 1.0;
        } else {
          _controller.forward(from: 0.0);
        }
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = AppMotion.shouldReduceMotion(context);
    if (_reduceMotion) {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(covariant AppNumberPopIn oldWidget) {
    super.didUpdateWidget(oldWidget);
    final totalDuration = _computeTotalDuration(_charCount);
    if (_controller.duration != totalDuration) {
      _controller.duration = totalDuration;
    }
    if (oldWidget.value != widget.value) {
      if (_reduceMotion) {
        _controller.value = 1.0;
      } else {
        _controller.forward(from: 0.0);
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
    if (_reduceMotion) {
      return Text(widget.value, style: widget.style);
    }

    final chars = [
      for (final rune in widget.value.runes) String.fromCharCode(rune),
    ];
    final totalMs = _computeTotalDuration(chars.length).inMilliseconds;
    final charMs = widget.duration.inMilliseconds;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            for (var i = 0; i < chars.length; i++)
              _buildDigit(chars[i], i, chars.length, totalMs, charMs),
          ],
        );
      },
    );
  }

  Widget _buildDigit(
    String ch,
    int index,
    int total,
    int totalMs,
    int charMs,
  ) {
    final delayMs =
        _staggerUnitsForIndex(index, total) *
        widget.staggerDelay.inMilliseconds;
    final double rawT;
    if (totalMs <= 0 || charMs <= 0) {
      rawT = 1.0;
    } else {
      final elapsedMs = _controller.value * totalMs - delayMs;
      rawT = (elapsedMs / charMs).clamp(0.0, 1.0);
    }

    // 空间变换允许过冲曲线；透明度与模糊严格限制在 [0, 1]
    final spatialT = widget.spatialCurve.transform(rawT);
    final safeT = AppMotionCurves.smoothOut.transform(rawT).clamp(0.0, 1.0);
    final dx = widget.direction.dx * widget.distance * (1.0 - spatialT);
    final dy = widget.direction.dy * widget.distance * (1.0 - spatialT);
    final sigma = widget.blurSigma * (1.0 - safeT);

    return Opacity(
      opacity: safeT,
      child: Transform.translate(
        offset: Offset(dx, dy),
        child: _maybeBlur(
          enableBlur: widget.enableBlur,
          sigma: sigma,
          child: Text(ch, style: widget.style),
        ),
      ),
    );
  }
}

/// 卡片/容器尺寸平滑自适应动效 (`01-card-resize`)
///
/// 适用场景：紧凑 <-> 展开态卡片、状态条动态伸缩。
/// 动画特征：300ms `smoothOut` 曲线平滑插值宽高。
class AppCardResize extends StatelessWidget {
  /// 子组件
  final Widget child;

  /// 缩放时长，默认 [AppMotionDurations.cardResize] (300ms)
  final Duration duration;

  /// 缓动曲线，默认 [AppMotionCurves.smoothOut]
  final Curve curve;

  /// 尺寸变换锚点，默认 [Alignment.topCenter]
  final AlignmentGeometry alignment;

  /// 裁剪方式，默认 [Clip.hardEdge]
  final Clip clipBehavior;

  const AppCardResize({
    super.key,
    required this.child,
    this.duration = AppMotionDurations.cardResize,
    this.curve = AppMotionCurves.smoothOut,
    this.alignment = Alignment.topCenter,
    this.clipBehavior = Clip.hardEdge,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: AppMotion.resolveDuration(context, duration),
      curve: curve,
      alignment: alignment,
      clipBehavior: clipBehavior,
      child: child,
    );
  }
}

/// 条件面板滑动揭示动效 (`07-panel-reveal`)
///
/// 适用场景：条件展开的详情面板、高级参数子区、内联抽屉。
/// 动画特征：开启 400ms / 收起 350ms `smoothOut`，组合尺寸裁剪、位移、淡入淡出与可选 2px 轻模糊。
class AppPanelReveal extends StatefulWidget {
  /// 面板是否可见
  final bool visible;

  /// 面板内容
  final Widget child;

  /// 展开时长，默认 [AppMotionDurations.panelOpen] (400ms)
  final Duration openDuration;

  /// 收起时长，默认 [AppMotionDurations.panelClose] (350ms)
  final Duration closeDuration;

  /// 缓动曲线，默认 [AppMotionCurves.smoothOut]
  final Curve curve;

  /// 垂直滑入距离，默认 [AppMotionDistances.large] (30.0)
  final double slideOffset;

  /// 模糊半径，默认 [AppMotionBlurs.small] (2.0)
  final double blurSigma;

  /// 是否启用模糊，默认 true
  final bool enableBlur;

  /// 是否同步动画化高度/宽度因子，默认 true
  final bool animateSize;

  /// 收起时是否保留内部子树 State，默认 false
  final bool maintainState;

  /// 展开方向轴，默认 [Axis.vertical]
  final Axis axis;

  /// 对齐方式，默认 [Alignment.topCenter]
  final AlignmentGeometry alignment;

  const AppPanelReveal({
    super.key,
    required this.visible,
    required this.child,
    this.openDuration = AppMotionDurations.panelOpen,
    this.closeDuration = AppMotionDurations.panelClose,
    this.curve = AppMotionCurves.smoothOut,
    this.slideOffset = AppMotionDistances.large,
    this.blurSigma = AppMotionBlurs.small,
    this.enableBlur = true,
    this.animateSize = true,
    this.maintainState = false,
    this.axis = Axis.vertical,
    this.alignment = Alignment.topCenter,
  });

  @override
  State<AppPanelReveal> createState() => _AppPanelRevealState();
}

class _AppPanelRevealState extends State<AppPanelReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.openDuration,
      reverseDuration: widget.closeDuration,
      value: widget.visible ? 1.0 : 0.0,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = AppMotion.shouldReduceMotion(context);
    if (_reduceMotion) {
      _controller.value = widget.visible ? 1.0 : 0.0;
    }
  }

  @override
  void didUpdateWidget(covariant AppPanelReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.duration = widget.openDuration;
    _controller.reverseDuration = widget.closeDuration;
    if (oldWidget.visible != widget.visible) {
      if (_reduceMotion) {
        _controller.value = widget.visible ? 1.0 : 0.0;
      } else if (widget.visible) {
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
    if (_reduceMotion) {
      if (!widget.visible && !widget.maintainState) {
        return const SizedBox.shrink();
      }
      return Visibility(
        visible: widget.visible,
        maintainState: widget.maintainState,
        child: widget.child,
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, innerChild) {
        if (_controller.isDismissed && !widget.visible) {
          if (!widget.maintainState) {
            return const SizedBox.shrink();
          }
          return Offstage(
            offstage: true,
            child: TickerMode(enabled: false, child: innerChild ?? widget.child),
          );
        }

        final t = widget.curve.transform(_controller.value).clamp(0.0, 1.0);
        final offset = widget.axis == Axis.vertical
            ? Offset(0, widget.slideOffset * (1.0 - t))
            : Offset(widget.slideOffset * (1.0 - t), 0);
        final sigma = widget.blurSigma * (1.0 - t);

        Widget result = Opacity(
          opacity: t,
          child: Transform.translate(
            offset: offset,
            child: _maybeBlur(
              enableBlur: widget.enableBlur,
              sigma: sigma,
              child: innerChild!,
            ),
          ),
        );

        if (widget.animateSize) {
          result = ClipRect(
            child: Align(
              alignment: widget.alignment,
              heightFactor: widget.axis == Axis.vertical ? t : null,
              widthFactor: widget.axis == Axis.horizontal ? t : null,
              child: result,
            ),
          );
        }

        return result;
      },
      child: widget.child,
    );
  }
}

/// 方向感知左右侧滑切页动效 (`08-page-side-by-side`)
///
/// 适用场景：设置页分栏切换、向导步骤页、列表 <-> 详情视图切换。
/// 根据 [index] 增减自动判定前进或后退方向，仅对当前新页做轻量入场滑入与透明度收拢，
/// 不叠放旧页避免透明底输入框产生文字残影。
class AppPageSideBySide extends StatefulWidget {
  /// 当前页面索引 (用于计算切换方向)
  final int index;

  /// 当前索引对应的页面内容
  final Widget child;

  /// 滑动与淡入时长，默认 [AppMotionDurations.quick] (150ms)
  final Duration duration;

  /// 缓动曲线，默认 [AppMotionCurves.smoothOut]
  final Curve curve;

  /// 水平位移距离，默认 [AppMotionDistances.base] (8.0)
  final double slideDistance;

  /// 模糊半径，默认 [AppMotionBlurs.medium] (3.0)
  final double blurSigma;

  /// 是否启用跨页模糊 (整页高频重建场景默认关闭以避免大图层 saveLayer 开销)
  final bool enableBlur;

  /// 叠放对齐方式，默认 [Alignment.topCenter] (保留兼容参数)
  final AlignmentGeometry alignment;

  const AppPageSideBySide({
    super.key,
    required this.index,
    required this.child,
    this.duration = AppMotionDurations.quick,
    this.curve = AppMotionCurves.smoothOut,
    this.slideDistance = AppMotionDistances.base,
    this.blurSigma = AppMotionBlurs.medium,
    this.enableBlur = false,
    this.alignment = Alignment.topCenter,
  });

  @override
  State<AppPageSideBySide> createState() => _AppPageSideBySideState();
}

class _AppPageSideBySideState extends State<AppPageSideBySide>
    with SingleTickerProviderStateMixin {
  static const double _enterStartOpacity = 0.78;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: 1.0,
  );
  bool _reduceMotion = false;
  int _direction = 1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = AppMotion.shouldReduceMotion(context);
    if (_reduceMotion) _controller.value = 1.0;
  }

  @override
  void didUpdateWidget(covariant AppPageSideBySide oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.duration != oldWidget.duration) {
      _controller.duration = widget.duration;
    }
    if (widget.index != oldWidget.index) {
      _direction = widget.index > oldWidget.index ? 1 : -1;
      if (_reduceMotion) {
        _controller.value = 1.0;
      } else {
        _controller.forward(from: 0.0);
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
    final keyedChild = KeyedSubtree(
      key: ValueKey<int>(widget.index),
      child: widget.child,
    );
    if (_reduceMotion) {
      return ClipRect(child: keyedChild);
    }

    return ClipRect(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, innerChild) {
          final t = widget.curve.transform(_controller.value).clamp(0.0, 1.0);
          final opacity = _enterStartOpacity + (1.0 - _enterStartOpacity) * t;
          final dx = _direction * widget.slideDistance * (1.0 - t);
          final sigma = widget.blurSigma * (1.0 - t);
          return Opacity(
            opacity: opacity,
            child: Transform.translate(
              offset: Offset(dx, 0),
              child: _maybeBlur(
                enableBlur: widget.enableBlur,
                sigma: sigma,
                child: innerChild!,
              ),
            ),
          );
        },
        child: keyedChild,
      ),
    );
  }
}

/// 文本流光扫掠动效 (`15-shimmer-text`)
///
/// 适用场景："生成中…"、"正在分析提示词…" 等需要持续生命感的进行中文案。
/// 动画特征：2000ms 线性 `ShaderMask` 高光带扫掠；减弱动态效果开启时自动退化为静态文本。
class AppShimmerText extends StatefulWidget {
  /// 展示文本
  final String text;

  /// 文本样式
  final TextStyle? style;

  /// 底色 (默认取主题 `textMuted`)
  final Color? baseColor;

  /// 高光扫掠色 (默认取主题 `textPrimary`)
  final Color? highlightColor;

  /// 单轮扫掠周期，默认 [AppMotionDurations.shimmer] (2000ms)
  final Duration duration;

  /// 高光带宽度占总宽比例 (0.05 ~ 0.8)，默认 0.28
  final double bandWidth;

  /// 是否开启流光动画；false 时静默渲染纯底色文本
  final bool enabled;

  /// 文本对齐方式
  final TextAlign? textAlign;

  /// 最大行数
  final int? maxLines;

  /// 溢出处理方式
  final TextOverflow? overflow;

  const AppShimmerText({
    super.key,
    required this.text,
    this.style,
    this.baseColor,
    this.highlightColor,
    this.duration = AppMotionDurations.shimmer,
    this.bandWidth = 0.28,
    this.enabled = true,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });

  @override
  State<AppShimmerText> createState() => _AppShimmerTextState();
}

class _AppShimmerTextState extends State<AppShimmerText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _reduceMotion = false;
  bool _pendingRepeat = false;

  bool get _shouldAnimate => widget.enabled && !_reduceMotion;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = AppMotion.shouldReduceMotion(context);
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant AppShimmerText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      _controller.duration = widget.duration;
    }
    if (oldWidget.enabled != widget.enabled ||
        oldWidget.duration != widget.duration) {
      _syncTicker();
    }
  }

  void _syncTicker() {
    if (_shouldAnimate) {
      _startRepeatSafely(
        controller: _controller,
        isPending: _pendingRepeat,
        markPending: () => _pendingRepeat = true,
        clearPending: () => _pendingRepeat = false,
        canRepeat: () => mounted && _shouldAnimate,
      );
    } else {
      _pendingRepeat = false;
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
    final effectiveBase = widget.baseColor ?? colors.textMuted;
    final effectiveHighlight = widget.highlightColor ?? colors.textPrimary;

    if (!_shouldAnimate) {
      return Text(
        widget.text,
        style: (widget.style ?? const TextStyle()).copyWith(
          color: effectiveBase,
        ),
        textAlign: widget.textAlign,
        maxLines: widget.maxLines,
        overflow: widget.overflow,
      );
    }

    final halfBand = (widget.bandWidth.clamp(0.05, 0.8)) / 2.0;

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final center = -halfBand + _controller.value * (1.0 + halfBand * 2.0);
          final start = center - halfBand;
          final end = center + halfBand;
          return ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) {
              return LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [effectiveBase, effectiveHighlight, effectiveBase],
                stops: [start, center, end],
              ).createShader(bounds);
            },
            child: child,
          );
        },
        child: Text(
          widget.text,
          style: (widget.style ?? const TextStyle()).copyWith(
            color: Colors.white,
          ),
          textAlign: widget.textAlign,
          maxLines: widget.maxLines,
          overflow: widget.overflow,
        ),
      ),
    );
  }
}

/// AI 思考阶段状态播报动效 (`28-thinking-states`)
///
/// 适用场景：Agent 推理/工具调用实时状态行 ("分析构图…" -> "检索标签…" -> "生成中…")。
/// 组合 [AppShimmerText] 持续扫掠与 [AppTextSwap] 垂直微滑动切换。
class AppThinkingStatus extends StatelessWidget {
  /// 当前状态文案
  final String status;

  /// 文本样式
  final TextStyle? style;

  /// 底色
  final Color? baseColor;

  /// 流光高亮色
  final Color? highlightColor;

  /// 流光周期，默认 [AppMotionDurations.shimmer] (2000ms)
  final Duration shimmerDuration;

  /// 状态切换时长，默认 [AppMotionDurations.thinkSwap] (150ms)
  final Duration swapDuration;

  /// 切换滑移距离，默认 [AppMotionDistances.base] (8.0)
  final double slideDistance;

  /// 模糊半径，默认 [AppMotionBlurs.small] (2.0)
  final double blurSigma;

  /// 是否启用切换模糊，默认 true
  final bool enableBlur;

  /// 是否持续流光，默认 true
  final bool shimmering;

  /// 对齐方式，默认 [Alignment.centerLeft]
  final AlignmentGeometry alignment;

  /// 最大行数
  final int? maxLines;

  /// 溢出处理
  final TextOverflow? overflow;

  const AppThinkingStatus({
    super.key,
    required this.status,
    this.style,
    this.baseColor,
    this.highlightColor,
    this.shimmerDuration = AppMotionDurations.shimmer,
    this.swapDuration = AppMotionDurations.thinkSwap,
    this.slideDistance = AppMotionDistances.base,
    this.blurSigma = AppMotionBlurs.small,
    this.enableBlur = true,
    this.shimmering = true,
    this.alignment = Alignment.centerLeft,
    this.maxLines,
    this.overflow,
  });

  @override
  Widget build(BuildContext context) {
    final reduceMotion = AppMotion.shouldReduceMotion(context);
    final effectiveSwap = reduceMotion ? Duration.zero : swapDuration;
    final activeKey = ValueKey<String>(status);

    return AnimatedSwitcher(
      duration: effectiveSwap,
      reverseDuration: effectiveSwap,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: alignment,
          children: [
            ...previousChildren,
            ?currentChild,
          ],
        );
      },
      transitionBuilder: (targetChild, animation) {
        if (reduceMotion) return targetChild;
        final isIncoming = targetChild.key == activeKey;
        return AnimatedBuilder(
          animation: animation,
          builder: (context, innerChild) {
            final t = AppMotionCurves.inOut
                .transform(animation.value)
                .clamp(0.0, 1.0);
            final dy = isIncoming
                ? slideDistance * (1.0 - t)
                : -slideDistance * (1.0 - t);
            final sigma = blurSigma * (1.0 - t);
            return Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, dy),
                child: _maybeBlur(
                  enableBlur: enableBlur,
                  sigma: sigma,
                  child: innerChild!,
                ),
              ),
            );
          },
          child: targetChild,
        );
      },
      child: AppShimmerText(
        key: activeKey,
        text: status,
        style: style,
        baseColor: baseColor,
        highlightColor: highlightColor,
        duration: shimmerDuration,
        enabled: shimmering,
        maxLines: maxLines,
        overflow: overflow,
      ),
    );
  }
}

/// 完成确认动态勾选图标 (`10-success-check`)
///
/// 适用场景：保存成功、导出完成、复制/上传完成确认反馈。
/// 动画特征：500ms 路径描边绘制 (延迟 80ms 启动) + 淡入 + 轻量缩放与 Y 轴微弹跳。
class AppSuccessCheck extends StatefulWidget {
  /// 是否展示
  final bool visible;

  /// 变更此键值可在保持 [visible] 为 true 时重播入场动效
  final Object? replayKey;

  /// 图标尺寸 (正方形边长)，默认 24.0
  final double size;

  /// 描边颜色 (默认取主题 `success`)
  final Color? color;

  /// 线条粗细，默认 2.4
  final double strokeWidth;

  /// 主动画时长，默认 [AppMotionDurations.verySlow] (500ms)
  final Duration duration;

  /// 路径绘制延迟，默认 [AppMotionDurations.micro] (80ms)
  final Duration pathDelay;

  /// 垂直微弹跳入场偏移，默认 6.0
  final double bobDistance;

  /// 是否绘制外圈圆环，默认 false
  final bool showCircle;

  /// 挂载时若 [visible] 为 true 是否直接播放动画，默认 true
  final bool animateOnMount;

  const AppSuccessCheck({
    super.key,
    this.visible = true,
    this.replayKey,
    this.size = 24.0,
    this.color,
    this.strokeWidth = 2.4,
    this.duration = AppMotionDurations.verySlow,
    this.pathDelay = AppMotionDurations.micro,
    this.bobDistance = 6.0,
    this.showCircle = false,
    this.animateOnMount = true,
  });

  @override
  State<AppSuccessCheck> createState() => _AppSuccessCheckState();
}

class _AppSuccessCheckState extends State<AppSuccessCheck>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _reduceMotion = false;

  Duration get _totalDuration => widget.duration + widget.pathDelay;

  @override
  void initState() {
    super.initState();
    final initialVal = widget.visible
        ? (widget.animateOnMount ? 0.0 : 1.0)
        : 0.0;
    _controller = AnimationController(
      vsync: this,
      duration: _totalDuration,
      value: initialVal,
    );
    if (widget.visible && widget.animateOnMount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_reduceMotion) {
          _controller.value = 1.0;
        } else {
          _controller.forward(from: 0.0);
        }
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = AppMotion.shouldReduceMotion(context);
    if (_reduceMotion && widget.visible) {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(covariant AppSuccessCheck oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller.duration != _totalDuration) {
      _controller.duration = _totalDuration;
    }
    if (widget.visible &&
        (!oldWidget.visible || widget.replayKey != oldWidget.replayKey)) {
      if (_reduceMotion) {
        _controller.value = 1.0;
      } else {
        _controller.forward(from: 0.0);
      }
    } else if (!widget.visible && oldWidget.visible) {
      _controller.value = 0.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible) {
      return SizedBox.square(dimension: widget.size);
    }

    final effectiveColor = widget.color ?? context.colors.success;

    if (_reduceMotion) {
      return SizedBox.square(
        dimension: widget.size,
        child: CustomPaint(
          painter: _SuccessCheckPainter(
            progress: 1.0,
            color: effectiveColor,
            strokeWidth: widget.strokeWidth,
            showCircle: widget.showCircle,
          ),
        ),
      );
    }

    final totalMs = _totalDuration.inMilliseconds;
    final delayFrac = totalMs > 0
        ? (widget.pathDelay.inMilliseconds / totalMs).clamp(0.0, 0.9)
        : 0.0;
    final mainEndFrac = totalMs > 0
        ? (widget.duration.inMilliseconds / totalMs).clamp(0.1, 1.0)
        : 1.0;

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final v = _controller.value;
          final mainRaw = (v / mainEndFrac).clamp(0.0, 1.0);
          final safeT = AppMotionCurves.smoothOut
              .transform(mainRaw)
              .clamp(0.0, 1.0);
          final bobT = AppMotionCurves.toggleBounce.transform(mainRaw);
          final pathRaw = delayFrac < 1.0
              ? ((v - delayFrac) / (1.0 - delayFrac)).clamp(0.0, 1.0)
              : 1.0;
          final pathT = AppMotionCurves.smoothOut
              .transform(pathRaw)
              .clamp(0.0, 1.0);

          final scale = 0.84 + 0.16 * safeT;
          final dy = widget.bobDistance * (1.0 - bobT);

          return Opacity(
            opacity: safeT,
            child: Transform.translate(
              offset: Offset(0, dy),
              child: Transform.scale(
                scale: scale,
                child: SizedBox.square(
                  dimension: widget.size,
                  child: CustomPaint(
                    painter: _SuccessCheckPainter(
                      progress: pathT,
                      color: effectiveColor,
                      strokeWidth: widget.strokeWidth,
                      showCircle: widget.showCircle,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SuccessCheckPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double strokeWidth;
  final bool showCircle;

  const _SuccessCheckPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
    required this.showCircle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (showCircle) {
      final radius = (size.shortestSide - strokeWidth) / 2.0;
      canvas.drawCircle(
        Offset(size.width / 2, size.height / 2),
        radius,
        paint..color = color.withValues(alpha: 0.25),
      );
      paint.color = color;
    }

    if (progress <= 0.0) return;

    final path = Path()
      ..moveTo(size.width * 0.22, size.height * 0.52)
      ..lineTo(size.width * 0.42, size.height * 0.72)
      ..lineTo(size.width * 0.78, size.height * 0.30);

    if (progress >= 1.0) {
      canvas.drawPath(path, paint);
      return;
    }

    for (final metric in path.computeMetrics()) {
      final extracted = metric.extractPath(0.0, metric.length * progress);
      canvas.drawPath(extracted, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SuccessCheckPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.showCircle != showCircle;
  }
}

/// 错误晃动控制器 (供 [AppErrorShake] 命令式触发)
class AppErrorShakeController extends ChangeNotifier {
  int _count = 0;

  /// 当前触发计数
  int get count => _count;

  /// 触发一次水平错误晃动
  void shake() {
    _count++;
    notifyListeners();
  }
}

/// 分段贝塞尔水平错误晃动容器 (`12-error-state-shake`)
///
/// 适用场景：表单校验失败、密码/密钥错误、重名提示、非法输入阻断反馈。
/// 动画特征：四段独立 `smoothOut` 曲线分段 (80ms -> 80ms -> 60ms -> 60ms，共 280ms)，
/// 支持通过递增 [trigger] 或调用 [AppErrorShakeController.shake] 随时重播。
class AppErrorShake extends StatefulWidget {
  /// 被包裹的目标组件 (如输入框或按钮)
  final Widget child;

  /// 声明式触发计数器；每当值变大 (且 > 0) 或变化 (非 0) 时重播晃动
  final int trigger;

  /// 可选命令式控制器
  final AppErrorShakeController? controller;

  /// 主摆幅距离，默认 [AppMotionDistances.small] (6.0)
  final double distance;

  /// 二次回弹距离，默认 [AppMotionDistances.shakeOvershoot] (4.0)
  final double overshoot;

  /// 主摆幅单段时长，默认 [AppMotionDurations.shakeLegA] (80ms)
  final Duration legADuration;

  /// 恢复段单段时长，默认 [AppMotionDurations.shakeLegB] (60ms)
  final Duration legBDuration;

  /// 每段使用的缓动曲线，默认 [AppMotionCurves.smoothOut]
  final Curve segmentCurve;

  const AppErrorShake({
    super.key,
    required this.child,
    this.trigger = 0,
    this.controller,
    this.distance = AppMotionDistances.small,
    this.overshoot = AppMotionDistances.shakeOvershoot,
    this.legADuration = AppMotionDurations.shakeLegA,
    this.legBDuration = AppMotionDurations.shakeLegB,
    this.segmentCurve = AppMotionCurves.smoothOut,
  });

  @override
  State<AppErrorShake> createState() => _AppErrorShakeState();
}

class _AppErrorShakeState extends State<AppErrorShake>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late Animation<double> _offsetAnim;
  bool _reduceMotion = false;

  Duration get _totalDuration =>
      widget.legADuration * 2 + widget.legBDuration * 2;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: _totalDuration,
    );
    _rebuildSequence();
    widget.controller?.addListener(_onControllerShake);
  }

  void _rebuildSequence() {
    final wA = widget.legADuration.inMilliseconds.toDouble().clamp(1.0, 1000.0);
    final wB = widget.legBDuration.inMilliseconds.toDouble().clamp(1.0, 1000.0);
    final curveTween = CurveTween(curve: widget.segmentCurve);
    _offsetAnim = _animController.drive(
      TweenSequence<double>([
        TweenSequenceItem(
          tween: Tween(begin: 0.0, end: widget.distance).chain(curveTween),
          weight: wA,
        ),
        TweenSequenceItem(
          tween: Tween(
            begin: widget.distance,
            end: -widget.distance,
          ).chain(curveTween),
          weight: wA,
        ),
        TweenSequenceItem(
          tween: Tween(
            begin: -widget.distance,
            end: widget.overshoot,
          ).chain(curveTween),
          weight: wB,
        ),
        TweenSequenceItem(
          tween: Tween(begin: widget.overshoot, end: 0.0).chain(curveTween),
          weight: wB,
        ),
      ]),
    );
  }

  void _onControllerShake() {
    _playShake();
  }

  void _playShake() {
    if (_reduceMotion) return;
    _animController.forward(from: 0.0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = AppMotion.shouldReduceMotion(context);
    if (_reduceMotion && _animController.isAnimating) {
      _animController.reset();
    }
  }

  @override
  void didUpdateWidget(covariant AppErrorShake oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_onControllerShake);
      widget.controller?.addListener(_onControllerShake);
    }
    if (oldWidget.legADuration != widget.legADuration ||
        oldWidget.legBDuration != widget.legBDuration ||
        oldWidget.distance != widget.distance ||
        oldWidget.overshoot != widget.overshoot ||
        oldWidget.segmentCurve != widget.segmentCurve) {
      _animController.duration = _totalDuration;
      _rebuildSequence();
    }
    if (widget.trigger != oldWidget.trigger && widget.trigger != 0) {
      _playShake();
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onControllerShake);
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_reduceMotion) return widget.child;
    return AnimatedBuilder(
      animation: _offsetAnim,
      builder: (context, child) {
        final dx = _animController.isAnimating ? _offsetAnim.value : 0.0;
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: widget.child,
    );
  }
}

/// 交错上升揭示动效 (`18-texts-reveal`)
///
/// 适用场景：空状态主副标题、引导步骤、分步卡片列表入场。
/// 动画特征：按 [index] * [staggerDelay] 延迟后 500ms 升起淡入 (12px + 可选 3px 模糊)；
/// 退场解耦为静默 200ms 纯淡出 (无反向位移与交错)。
class AppStaggerReveal extends StatefulWidget {
  /// 子组件
  final Widget child;

  /// 在同组中的顺序索引 (0 起)
  final int index;

  /// 是否可见；切换为 false 时执行静默淡出
  final bool visible;

  /// 入场时长，默认 [AppMotionDurations.verySlow] (500ms)
  final Duration duration;

  /// 单步交错延迟，默认 [AppMotionDurations.stagger] (40ms)
  final Duration staggerDelay;

  /// 退场淡出时长，默认 [AppMotionDurations.staggerExit] (200ms)
  final Duration exitDuration;

  /// 垂直上升距离，默认 [AppMotionDistances.medium] (12.0)
  final double distance;

  /// 模糊半径，默认 [AppMotionBlurs.medium] (3.0)
  final double blurSigma;

  /// 是否在入场时叠加模糊，默认 false
  final bool enableBlur;

  /// 缓动曲线，默认 [AppMotionCurves.smoothOut]
  final Curve curve;

  /// 最大交错索引上限，防止超长列表等待过久，默认 12
  final int maxStaggerIndex;

  const AppStaggerReveal({
    super.key,
    required this.child,
    this.index = 0,
    this.visible = true,
    this.duration = AppMotionDurations.verySlow,
    this.staggerDelay = AppMotionDurations.stagger,
    this.exitDuration = AppMotionDurations.staggerExit,
    this.distance = AppMotionDistances.medium,
    this.blurSigma = AppMotionBlurs.medium,
    this.enableBlur = false,
    this.curve = AppMotionCurves.smoothOut,
    this.maxStaggerIndex = 12,
  });

  @override
  State<AppStaggerReveal> createState() => _AppStaggerRevealState();
}

class _AppStaggerRevealState extends State<AppStaggerReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _delayTimer;
  bool _reduceMotion = false;
  bool _exiting = false;

  @override
  void initState() {
    super.initState();
    final skipInitialEnter =
        widget.visible &&
        widget.duration == Duration.zero &&
        widget.staggerDelay == Duration.zero;
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
      reverseDuration: widget.exitDuration,
      value: skipInitialEnter ? 1.0 : 0.0,
    );
    if (widget.visible && !skipInitialEnter) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.visible) _scheduleEnter();
      });
    }
  }

  void _scheduleEnter() {
    _delayTimer?.cancel();
    _exiting = false;
    if (_reduceMotion) {
      _controller.value = 1.0;
      return;
    }
    final clampedIndex = widget.index.clamp(0, widget.maxStaggerIndex);
    final delay = widget.staggerDelay * clampedIndex;
    if (delay == Duration.zero) {
      _controller.forward(from: 0.0);
    } else {
      _delayTimer = Timer(delay, () {
        if (mounted && widget.visible) {
          _controller.forward(from: 0.0);
        }
      });
    }
  }

  void _playExit() {
    _delayTimer?.cancel();
    if (_reduceMotion) {
      _controller.value = 0.0;
      return;
    }
    _exiting = true;
    _controller.reverse();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = AppMotion.shouldReduceMotion(context);
    if (_reduceMotion) {
      _delayTimer?.cancel();
      _controller.value = widget.visible ? 1.0 : 0.0;
    }
  }

  @override
  void didUpdateWidget(covariant AppStaggerReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.duration = widget.duration;
    _controller.reverseDuration = widget.exitDuration;
    if (widget.visible != oldWidget.visible) {
      if (widget.visible) {
        _scheduleEnter();
      } else {
        _playExit();
      }
    }
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_reduceMotion) {
      return widget.visible ? widget.child : const SizedBox.shrink();
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        if (_exiting) {
          final fade = Curves.easeOut
              .transform(_controller.value)
              .clamp(0.0, 1.0);
          return Opacity(opacity: fade, child: child);
        }
        final t = widget.curve.transform(_controller.value).clamp(0.0, 1.0);
        final dy = widget.distance * (1.0 - t);
        final sigma = widget.blurSigma * (1.0 - t);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, dy),
            child: _maybeBlur(
              enableBlur: widget.enableBlur,
              sigma: sigma,
              child: child!,
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// 桌面端元素悬停微抬升与回弹动效 (`11-avatar-group-hover` 风格)
///
/// 适用场景：标签胶囊、工具按钮、头像/缩略图条目悬停反馈。
/// 动画特征：方向感知曲线——悬停进入使用平滑 `smoothOut`，移出使用 `bounceStrong` 回弹；
/// 严格仅作用于空间位移与缩放，不用于透明度或颜色插值。
class AppHoverLift extends StatefulWidget {
  /// 子组件
  final Widget child;

  /// 悬停垂直偏移 (负值向上抬升)，默认 [AppMotionDistances.avatarLift] (-4.0)
  final double lift;

  /// 悬停缩放比例，默认 [AppMotionScales.avatarHover] (1.05)
  final double hoverScale;

  /// 过渡时长，默认 [AppMotionDurations.avatarHover] (320ms)
  final Duration duration;

  /// 移入缓动曲线，默认 [AppMotionCurves.smoothOut]
  final Curve easeIn;

  /// 移出回弹曲线，默认 [AppMotionCurves.bounceStrong] (仅限空间变换)
  final Curve easeOut;

  /// 可选点击回调
  final VoidCallback? onTap;

  /// 鼠标指针样式，默认有 [onTap] 时为 [SystemMouseCursors.click]
  final MouseCursor? cursor;

  /// 是否启用抬升动效，默认 true
  final bool enabled;

  const AppHoverLift({
    super.key,
    required this.child,
    this.lift = AppMotionDistances.avatarLift,
    this.hoverScale = AppMotionScales.avatarHover,
    this.duration = AppMotionDurations.avatarHover,
    this.easeIn = AppMotionCurves.smoothOut,
    this.easeOut = AppMotionCurves.bounceStrong,
    this.onTap,
    this.cursor,
    this.enabled = true,
  });

  @override
  State<AppHoverLift> createState() => _AppHoverLiftState();
}

class _AppHoverLiftState extends State<AppHoverLift>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  CurvedAnimation? _curved;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _updateCurvedAnimation();
  }

  void _updateCurvedAnimation() {
    _curved?.dispose();
    _curved = CurvedAnimation(
      parent: _controller,
      curve: widget.easeIn,
      reverseCurve: widget.easeOut.flipped,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = AppMotion.shouldReduceMotion(context);
    if (_reduceMotion) {
      _controller.value = 0.0;
    }
  }

  @override
  void didUpdateWidget(covariant AppHoverLift oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      _controller.duration = widget.duration;
    }
    if (oldWidget.easeIn != widget.easeIn ||
        oldWidget.easeOut != widget.easeOut) {
      _updateCurvedAnimation();
    }
    if (!widget.enabled && _controller.value != 0.0) {
      _controller.value = 0.0;
    }
  }

  @override
  void dispose() {
    _curved?.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _setHovered(bool hovered) {
    if (!widget.enabled || _reduceMotion) return;
    if (hovered) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final effectiveCursor =
        widget.cursor ??
        (widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer);

    Widget content = widget.child;
    if (widget.onTap != null) {
      content = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: content,
      );
    }

    if (!widget.enabled || _reduceMotion) {
      return MouseRegion(cursor: effectiveCursor, child: content);
    }

    final curved = _curved!;
    return MouseRegion(
      cursor: effectiveCursor,
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: AnimatedBuilder(
        animation: curved,
        builder: (context, child) {
          final t = curved.value;
          final dy = widget.lift * t;
          final scale = 1.0 + (widget.hoverScale - 1.0) * t;
          return Transform.translate(
            offset: Offset(0, dy),
            child: Transform.scale(scale: scale, child: child),
          );
        },
        child: content,
      ),
    );
  }
}

/// 4x4 点阵加载器动效模式 (`31-matrix-loader`)
enum AppMatrixDotVariant {
  /// 逐列横向扫描
  scan,

  /// 错位闪烁
  twinkle,

  /// 外环顺时针绕行 (中心 4 点保持稳定)
  orbit,

  /// 中心向外脉冲
  pulse,
}

/// 4x4 微型点阵加载指示器 (`31-matrix-loader`)
///
/// 适用场景：状态栏内联加载、紧凑按钮内指示、表格单元等待态。
/// 相比传统旋转 Spinner 更克制安静；全部绘制在单个 `CustomPainter` 内完成，零 Widget 帧重建。
class AppMatrixDotLoader extends StatefulWidget {
  /// 动效模式，默认 [AppMatrixDotVariant.scan]
  final AppMatrixDotVariant variant;

  /// 是否省略四角点位呈现圆角点阵，默认 false
  final bool rounded;

  /// 单个圆点/方点边长，默认 2.0
  final double dotSize;

  /// 点与点之间的间距，默认 2.0
  final double gap;

  /// 静息点颜色 (默认取主题 `borderHover`)
  final Color? baseColor;

  /// 激活高亮颜色 (默认取主题 `primary`)
  final Color? activeColor;

  /// 完整周期时长，默认 [AppMotionDurations.matrixCycle] (1200ms)
  final Duration cycleDuration;

  /// 脉冲缓动曲线，默认 [AppMotionCurves.inOut]
  final Curve curve;

  const AppMatrixDotLoader({
    super.key,
    this.variant = AppMatrixDotVariant.scan,
    this.rounded = false,
    this.dotSize = 2.0,
    this.gap = 2.0,
    this.baseColor,
    this.activeColor,
    this.cycleDuration = AppMotionDurations.matrixCycle,
    this.curve = AppMotionCurves.inOut,
  });

  @override
  State<AppMatrixDotLoader> createState() => _AppMatrixDotLoaderState();
}

class _AppMatrixDotLoaderState extends State<AppMatrixDotLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _reduceMotion = false;
  bool _pendingRepeat = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.cycleDuration,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = AppMotion.shouldReduceMotion(context);
    if (_reduceMotion) {
      _pendingRepeat = false;
      _controller.stop();
      _controller.value = 0.25;
    } else {
      _startRepeatSafely(
        controller: _controller,
        isPending: _pendingRepeat,
        markPending: () => _pendingRepeat = true,
        clearPending: () => _pendingRepeat = false,
        canRepeat: () => mounted && !_reduceMotion,
      );
    }
  }

  @override
  void didUpdateWidget(covariant AppMatrixDotLoader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cycleDuration != widget.cycleDuration) {
      _controller.duration = widget.cycleDuration;
      if (!_reduceMotion) {
        _startRepeatSafely(
          controller: _controller,
          isPending: _pendingRepeat,
          markPending: () => _pendingRepeat = true,
          clearPending: () => _pendingRepeat = false,
          canRepeat: () => mounted && !_reduceMotion,
        );
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
    final base = widget.baseColor ?? colors.borderHover;
    final active = widget.activeColor ?? colors.primary;
    final totalSide = widget.dotSize * 4 + widget.gap * 3;

    return RepaintBoundary(
      child: SizedBox.square(
        dimension: totalSide,
        child: CustomPaint(
          painter: _MatrixDotPainter(
            phase: _controller,
            variant: widget.variant,
            rounded: widget.rounded,
            dotSize: widget.dotSize,
            gap: widget.gap,
            baseColor: base,
            activeColor: active,
            curve: widget.curve,
            reduceMotion: _reduceMotion,
          ),
        ),
      ),
    );
  }
}

class _MatrixDotPainter extends CustomPainter {
  static const List<int> _corners = [0, 3, 12, 15];
  static const List<int> _ring = [1, 2, 7, 11, 14, 13, 8, 4];
  static const List<int> _inner = [5, 6, 9, 10];
  static const List<int> _twinkleOrder = [
    7,
    2,
    11,
    5,
    14,
    9,
    0,
    12,
    3,
    15,
    6,
    10,
    13,
    1,
    8,
    4,
  ];

  final Animation<double> phase;
  final AppMatrixDotVariant variant;
  final bool rounded;
  final double dotSize;
  final double gap;
  final Color baseColor;
  final Color activeColor;
  final Curve curve;
  final bool reduceMotion;

  const _MatrixDotPainter({
    required this.phase,
    required this.variant,
    required this.rounded,
    required this.dotSize,
    required this.gap,
    required this.baseColor,
    required this.activeColor,
    required this.curve,
    required this.reduceMotion,
  }) : super(repaint: phase);

  double _pulseIntensity(double localPhase) {
    // 对齐 31-matrix-loader 关键帧: 0% -> base, 15% -> active, 45% -> base, 100% -> base
    final p = localPhase - localPhase.floorToDouble();
    if (p <= 0.15) {
      return curve.transform((p / 0.15).clamp(0.0, 1.0)).clamp(0.0, 1.0);
    }
    if (p <= 0.45) {
      return (1.0 - curve.transform(((p - 0.15) / 0.30).clamp(0.0, 1.0)))
          .clamp(0.0, 1.0);
    }
    return 0.0;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final step = dotSize + gap;
    final radius = Radius.circular(dotSize * 0.25);
    final currentPhase = phase.value;

    for (var idx = 0; idx < 16; idx++) {
      if (rounded && _corners.contains(idx)) continue;

      final row = idx ~/ 4;
      final col = idx % 4;
      double intensity;

      if (reduceMotion) {
        intensity = _inner.contains(idx) ? 0.65 : 0.2;
      } else {
        switch (variant) {
          case AppMatrixDotVariant.scan:
            final delayFrac = col / 10.0;
            intensity = _pulseIntensity(currentPhase - delayFrac + 1.0);
          case AppMatrixDotVariant.twinkle:
            final delayFrac = _twinkleOrder[idx] / 16.0;
            intensity = _pulseIntensity(currentPhase - delayFrac + 1.0);
          case AppMatrixDotVariant.orbit:
            final ringIndex = _ring.indexOf(idx);
            if (ringIndex == -1) {
              intensity = 0.0;
            } else {
              final delayFrac = ringIndex / 8.0;
              intensity = _pulseIntensity(currentPhase - delayFrac + 1.0);
            }
          case AppMatrixDotVariant.pulse:
            final delayFrac = _inner.contains(idx) ? 0.0 : 0.16;
            intensity = _pulseIntensity(currentPhase - delayFrac + 1.0);
        }
      }

      paint.color = Color.lerp(baseColor, activeColor, intensity) ?? baseColor;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(col * step, row * step, dotSize, dotSize),
        radius,
      );
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MatrixDotPainter oldDelegate) {
    return oldDelegate.phase != phase ||
        oldDelegate.variant != variant ||
        oldDelegate.rounded != rounded ||
        oldDelegate.dotSize != dotSize ||
        oldDelegate.gap != gap ||
        oldDelegate.baseColor != baseColor ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.curve != curve ||
        oldDelegate.reduceMotion != reduceMotion;
  }
}

/// 弹出标准模态对话框 (`06-modal`)
///
/// 打开耗时 250ms、关闭耗时 150ms，使用 [AppMotionCurves.smoothOut] 曲线，
/// 配合 `0.96 -> 1.0` 缩放与淡入淡出。减弱动态效果开启时自动退化为无动画即时切换。
Future<T?> showAppModalDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  String? barrierLabel,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
  Duration openDuration = AppMotionDurations.modalOpen,
  Duration closeDuration = AppMotionDurations.modalClose,
  double startScale = AppMotionScales.modal,
  Curve curve = AppMotionCurves.smoothOut,
}) {
  final reduceMotion = AppMotion.shouldReduceMotion(context);
  final effectiveBarrierColor =
      barrierColor ?? Colors.black.withValues(alpha: 0.5);
  final effectiveBarrierLabel =
      barrierLabel ??
      MaterialLocalizations.of(context).modalBarrierDismissLabel;

  return Navigator.of(context, rootNavigator: useRootNavigator).push<T>(
    _AppModalDialogRoute<T>(
      builder: builder,
      barrierDismissible: barrierDismissible,
      barrierColor: effectiveBarrierColor,
      barrierLabel: effectiveBarrierLabel,
      settings: routeSettings,
      openDuration: reduceMotion ? Duration.zero : openDuration,
      closeDuration: reduceMotion ? Duration.zero : closeDuration,
      startScale: startScale,
      curve: curve,
      reduceMotion: reduceMotion,
    ),
  );
}

class _AppModalDialogRoute<T> extends PopupRoute<T> {
  final WidgetBuilder builder;
  final Duration openDuration;
  final Duration closeDuration;
  final double startScale;
  final Curve curve;
  final bool reduceMotion;

  @override
  final bool barrierDismissible;

  @override
  final Color? barrierColor;

  @override
  final String? barrierLabel;

  _AppModalDialogRoute({
    required this.builder,
    required this.barrierDismissible,
    required this.barrierColor,
    required this.barrierLabel,
    required this.openDuration,
    required this.closeDuration,
    required this.startScale,
    required this.curve,
    required this.reduceMotion,
    super.settings,
  });

  @override
  Duration get transitionDuration => openDuration;

  @override
  Duration get reverseTransitionDuration => closeDuration;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return SafeArea(child: builder(context));
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (reduceMotion || AppMotion.shouldReduceMotion(context)) {
      return child;
    }
    return AnimatedBuilder(
      animation: animation,
      builder: (context, innerChild) {
        final t = curve.transform(animation.value).clamp(0.0, 1.0);
        final scale = startScale + (1.0 - startScale) * t;
        return Opacity(
          opacity: t,
          child: Transform.scale(scale: scale, child: innerChild),
        );
      },
      child: child,
    );
  }
}

/// 模态风格页面路由 (`06-modal`)
///
/// 适用场景：全屏详情查看、图片大图编辑弹窗页、引导式子页面。
/// 打开耗时 250ms / 关闭耗时 150ms，`0.96 -> 1.0` 缩放 + 淡入淡出 + `smoothOut` 曲线。
class AppModalPageRoute<T> extends PageRoute<T> {
  /// 页面构建器
  final WidgetBuilder builder;

  /// 打开过渡时长，默认 [AppMotionDurations.modalOpen] (250ms)
  final Duration openDuration;

  /// 关闭过渡时长，默认 [AppMotionDurations.modalClose] (150ms)
  final Duration closeDuration;

  /// 起始缩放比例，默认 [AppMotionScales.modal] (0.96)
  final double startScale;

  /// 缓动曲线，默认 [AppMotionCurves.smoothOut]
  final Curve curve;

  @override
  final bool opaque;

  @override
  final bool barrierDismissible;

  @override
  final Color? barrierColor;

  @override
  final String? barrierLabel;

  @override
  final bool maintainState;

  AppModalPageRoute({
    required this.builder,
    this.openDuration = AppMotionDurations.modalOpen,
    this.closeDuration = AppMotionDurations.modalClose,
    this.startScale = AppMotionScales.modal,
    this.curve = AppMotionCurves.smoothOut,
    this.opaque = true,
    this.barrierDismissible = false,
    this.barrierColor,
    this.barrierLabel,
    this.maintainState = true,
    super.settings,
    super.fullscreenDialog = false,
  });

  bool get _reduceMotion {
    final navContext = navigator?.context;
    return navContext != null && MediaQuery.disableAnimationsOf(navContext);
  }

  @override
  Duration get transitionDuration =>
      _reduceMotion ? Duration.zero : openDuration;

  @override
  Duration get reverseTransitionDuration =>
      _reduceMotion ? Duration.zero : closeDuration;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return builder(context);
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (AppMotion.shouldReduceMotion(context)) {
      return child;
    }
    return AnimatedBuilder(
      animation: animation,
      builder: (context, innerChild) {
        final t = curve.transform(animation.value).clamp(0.0, 1.0);
        final scale = startScale + (1.0 - startScale) * t;
        return Opacity(
          opacity: t,
          child: Transform.scale(scale: scale, child: innerChild),
        );
      },
      child: child,
    );
  }
}
