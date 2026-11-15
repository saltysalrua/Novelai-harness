import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show
        RenderBox,
        RenderSliverMultiBoxAdaptor,
        SliverMultiBoxAdaptorParentData;

import '../theme/theme_context_extensions.dart';

/// 自研稳定滚动条（不依赖 Flutter 原生 RawScrollbar / ScrollbarPainter）：
///
/// 针对变高懒加载消息列表在渲染、流式增长与滚动过程中原生滚动条上下乱跳的问题：
/// 1. 记忆已布局子项真实高度 + 锁定未访问项基准高度，避免局部高消息进出缓存区引发总高度剧变；
/// 2. 滚动过程采用方向单调增量进度推进，静止/流式重排期间锁定视觉位置，杜绝反向回跳；
/// 3. 握把拖拽时视觉位置 1:1 紧贴指针，同时以拖拽起点固定倍率增量驱动滚动位置。
class StableScrollbar extends StatefulWidget {
  final ScrollController controller;
  final Widget child;
  final Color? thumbColor;
  final double? thickness;
  final Radius? radius;

  const StableScrollbar({
    super.key,
    required this.controller,
    required this.child,
    this.thumbColor,
    this.thickness,
    this.radius,
  });

  @override
  State<StableScrollbar> createState() => StableScrollbarState();
}

class StableScrollbarState extends State<StableScrollbar>
    with SingleTickerProviderStateMixin {
  static const double _trackPaddingTop = 4.0;
  static const double _trackPaddingBottom = 4.0;
  static const double _rightMargin = 2.0;
  static const double _minThumbExtent = 24.0;
  static const double _defaultThickness = 6.0;
  static const Radius _defaultRadius = Radius.circular(4.0);
  static const Duration _fadeDuration = Duration(milliseconds: 160);
  static const Duration _fadeDelay = Duration(milliseconds: 900);

  late final AnimationController _fadeController;
  final _ThumbPaintNotifier _paintNotifier = _ThumbPaintNotifier();
  Timer? _fadeTimer;

  // 子项高度记忆与稳定度量状态
  final Map<int, double> _itemHeights = {};
  RenderSliverMultiBoxAdaptor? _lastSliver;
  int _childCount = 0;
  int _lastChildCount = 0;
  double _unvisitedItemExtent = 0.0;
  bool _hasAnchoredInitialExtent = false;

  bool _isScrollable = false;
  bool _hasInitializedMetrics = false;
  double _visualProgress = 0.0;
  double _visualThumbExtent = _minThumbExtent;
  double _lastPixels = 0.0;
  double _lastViewportDimension = 0.0;

  // 视口与握把几何缓存
  double _viewportWidth = 0.0;
  double _trackLength = 0.0;
  double _effectiveThickness = _defaultThickness;
  Rect? _cachedThumbRect;
  bool _postFrameSyncScheduled = false;

  // 滚动/悬停/拖拽状态
  bool _isUserScrolling = false;
  bool _hoveringStrip = false;
  bool _hoveringThumb = false;
  bool _isDraggingThumb = false;
  int? _activeDragPointer;
  double _dragStartPointerY = 0.0;
  double _dragStartThumbOffset = 0.0;
  double _dragThumbOffset = 0.0;
  double _dragThumbExtent = _minThumbExtent;
  double _scrollPerTrackPixel = 1.0;
  Drag? _incrementalDrag;

  /// 当前握把在 StableScrollbar 局部坐标系下的矩形 (不可滚动时为 null)
  Rect? get thumbRect => _cachedThumbRect;

  /// 判断 StableScrollbar 局部坐标是否命中握把交互热区
  bool hitTestThumb(Offset localPosition) {
    final rect = _cachedThumbRect;
    if (rect == null || !_isScrollable) return false;
    final hitStripWidth = _hitStripWidthFor(_effectiveThickness);
    final hitRect = Rect.fromLTRB(
      math.min(rect.left - 6.0, math.max(0.0, _viewportWidth - hitStripWidth)),
      rect.top - 4.0,
      _viewportWidth,
      rect.bottom + 4.0,
    );
    return hitRect.contains(localPosition);
  }

  double _hitStripWidthFor(double thickness) => math.max(16.0, thickness + 10.0);

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: _fadeDuration,
      value: 0.0,
    );
    widget.controller.addListener(_onControllerNotification);
    _schedulePostFrameSync();
  }

  @override
  void didUpdateWidget(covariant StableScrollbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerNotification);
      widget.controller.addListener(_onControllerNotification);
      _resetTrackedContent();
    }
    _schedulePostFrameSync();
  }

  @override
  void dispose() {
    _fadeTimer?.cancel();
    widget.controller.removeListener(_onControllerNotification);
    _incrementalDrag?.cancel();
    _incrementalDrag = null;
    _fadeController.dispose();
    _paintNotifier.dispose();
    super.dispose();
  }

  void _resetTrackedContent() {
    _incrementalDrag?.cancel();
    _incrementalDrag = null;
    _isDraggingThumb = false;
    _activeDragPointer = null;
    _lastSliver = null;
    _itemHeights.clear();
    _childCount = 0;
    _lastChildCount = 0;
    _hasAnchoredInitialExtent = false;
    _hasInitializedMetrics = false;
    _visualProgress = 0.0;
    _cachedThumbRect = null;
    _isScrollable = false;
  }

  void _onControllerNotification() {
    if (!mounted) return;
    // ScrollPosition.setPixels 会先触发 controller listener，再派发 ScrollUpdateNotification。
    // 推迟到帧末同步，避免提前吞掉 _lastPixels 差值并兼顾 attach/detach 场景。
    _schedulePostFrameSync();
  }

  void _schedulePostFrameSync() {
    if (_postFrameSyncScheduled) return;
    _postFrameSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _postFrameSyncScheduled = false;
      if (!mounted) return;
      _syncMetrics(fromScrollUpdate: false);
    });
  }

  void _showScrollbar({bool autoFade = true}) {
    _fadeTimer?.cancel();
    if (_fadeController.value < 1.0 &&
        _fadeController.status != AnimationStatus.forward) {
      _fadeController.forward();
    }
    if (autoFade && !_isDraggingThumb && !_hoveringStrip) {
      _scheduleFadeOut();
    }
  }

  void _scheduleFadeOut() {
    _fadeTimer?.cancel();
    if (_isDraggingThumb || _hoveringStrip || _isUserScrolling) return;
    _fadeTimer = Timer(_fadeDelay, () {
      if (!mounted || _isDraggingThumb || _hoveringStrip || _isUserScrolling) {
        return;
      }
      _fadeController.reverse();
    });
  }

  (RenderSliverMultiBoxAdaptor, int?)? _findSliverInfo(ScrollPosition pos) {
    final scrollContext = pos.context;
    if (scrollContext is! ScrollableState || !scrollContext.mounted) {
      return null;
    }
    RenderSliverMultiBoxAdaptor? sliver;
    int? childCount;
    void visit(Element element) {
      if (sliver != null) return;
      final widget = element.widget;
      if (widget is SliverMultiBoxAdaptorWidget) {
        final ro = element.renderObject;
        if (ro is RenderSliverMultiBoxAdaptor) {
          sliver = ro;
          childCount = widget.delegate.estimatedChildCount;
          return;
        }
      }
      element.visitChildElements(visit);
    }

    scrollContext.context.visitChildElements(visit);
    final found = sliver;
    if (found == null) return null;
    return (found, childCount);
  }

  void _clearGeometry() {
    final wasScrollable = _isScrollable;
    _isScrollable = false;
    _hasInitializedMetrics = false;
    _visualProgress = 0.0;
    _cachedThumbRect = null;
    _paintNotifier.notify();
    if (wasScrollable && mounted) {
      setState(() {});
    }
  }

  void _syncMetrics({required bool fromScrollUpdate}) {
    if (!mounted || !widget.controller.hasClients) {
      _clearGeometry();
      return;
    }
    final positions = widget.controller.positions;
    if (positions.length != 1) {
      _clearGeometry();
      return;
    }
    final pos = positions.first;
    if (!pos.hasContentDimensions || !pos.hasPixels) {
      _clearGeometry();
      return;
    }

    final minExtent = pos.minScrollExtent;
    final maxExtent = pos.maxScrollExtent;
    final pixels = pos.pixels.clamp(minExtent, maxExtent).toDouble();
    final viewport = pos.viewportDimension;
    final scrollRange = maxExtent - minExtent;

    if (viewport <= 0 || scrollRange <= 0.5 || _trackLength <= 0) {
      _clearGeometry();
      return;
    }

    final trackExtent = math.max(
      1.0,
      _trackLength - _trackPaddingTop - _trackPaddingBottom,
    );

    // 1. 采集可见及缓存窗口内子项真实高度，列表实例变更 (如切换会话) 时清空记忆
    final sliverInfo = _findSliverInfo(pos);
    final sliver = sliverInfo?.$1;
    final estimatedChildCount = sliverInfo?.$2;
    if (!identical(sliver, _lastSliver)) {
      _lastSliver = sliver;
      _itemHeights.clear();
      _childCount = 0;
      _lastChildCount = 0;
      _hasAnchoredInitialExtent = false;
      _hasInitializedMetrics = false;
    }

    if (sliver != null) {
      final count = estimatedChildCount ?? 0;
      if (count != _childCount) {
        _childCount = count;
        _itemHeights.removeWhere((index, _) => index >= count);
      }
      RenderBox? node = sliver.firstChild;
      while (node != null) {
        final data = node.parentData;
        if (data is SliverMultiBoxAdaptorParentData && data.index != null) {
          _itemHeights[data.index!] = node.size.height;
        }
        node = sliver.childAfter(node);
      }
      if (_itemHeights.isNotEmpty && !_hasAnchoredInitialExtent) {
        final sum = _itemHeights.values.fold<double>(0.0, (a, b) => a + b);
        _unvisitedItemExtent = sum / _itemHeights.length;
        _hasAnchoredInitialExtent = true;
      }
    }

    // 2. 计算稳定总内容高度与候选握把长度
    final double stableTotalExtent;
    if (_childCount > 0 &&
        _itemHeights.isNotEmpty &&
        _hasAnchoredInitialExtent) {
      final knownSum = _itemHeights.values.fold<double>(0.0, (a, b) => a + b);
      final unvisitedCount = math.max(0, _childCount - _itemHeights.length);
      stableTotalExtent = math.max(
        viewport + 1.0,
        knownSum + unvisitedCount * _unvisitedItemExtent + 24.0,
      );
    } else {
      stableTotalExtent = viewport + scrollRange;
    }

    final rawThumbExtent = (trackExtent * (viewport / stableTotalExtent))
        .clamp(math.min(_minThumbExtent, trackExtent), trackExtent)
        .toDouble();

    final childCountChanged = _childCount != _lastChildCount;
    final viewportChanged = (viewport - _lastViewportDimension).abs() > 1.0;

    if (!_isDraggingThumb) {
      if (!_hasInitializedMetrics) {
        _visualThumbExtent = rawThumbExtent;
      } else if (childCountChanged ||
          viewportChanged ||
          (!_isUserScrolling &&
              (rawThumbExtent - _visualThumbExtent).abs() > 10.0)) {
        _visualThumbExtent = rawThumbExtent;
      }
    }

    // 3. 方向单调进度推进 (拖拽期间视觉握把由指针 1:1 控制，此处仅更新基准像素)
    if (_isDraggingThumb) {
      _lastPixels = pixels;
      _lastViewportDimension = viewport;
      _lastChildCount = _childCount;
      _recomputeThumbRect();
      _paintNotifier.notify();
      return;
    }

    if (!_hasInitializedMetrics) {
      if (pos.extentAfter <= 1.0) {
        _visualProgress = 1.0;
      } else if (pixels <= minExtent + 0.5) {
        _visualProgress = 0.0;
      } else {
        _visualProgress = ((pixels - minExtent) / scrollRange).clamp(0.0, 1.0);
      }
      _hasInitializedMetrics = true;
    } else if (pixels <= minExtent + 0.5) {
      _visualProgress = 0.0;
    } else if (pos.extentAfter <= 1.0) {
      _visualProgress = 1.0;
    } else if (!fromScrollUpdate &&
        !_isUserScrolling &&
        _visualProgress >= 0.98 &&
        pos.extentAfter <= 64.0) {
      // 流式输出贴底跟随时帧间 extentAfter 可能有瞬态毛刺，锁定底部不回弹
      _visualProgress = 1.0;
    } else if (fromScrollUpdate) {
      final delta = pixels - _lastPixels;
      if (delta > 0.05) {
        final remainingPixels = math.max(delta, maxExtent - _lastPixels);
        final next =
            _visualProgress +
            (1.0 - _visualProgress) * (delta / remainingPixels);
        _visualProgress = math.max(_visualProgress, next).clamp(0.0, 1.0);
      } else if (delta < -0.05) {
        final upDelta = -delta;
        final elapsedPixels = math.max(upDelta, _lastPixels - minExtent);
        final next = _visualProgress - _visualProgress * (upDelta / elapsedPixels);
        _visualProgress = math.min(_visualProgress, next).clamp(0.0, 1.0);
      }
    }

    _lastPixels = pixels;
    _lastViewportDimension = viewport;
    _lastChildCount = _childCount;

    final wasScrollable = _isScrollable;
    _isScrollable = true;
    _recomputeThumbRect();
    _paintNotifier.notify();
    if (!wasScrollable && mounted) {
      setState(() {});
    }
  }

  void _recomputeThumbRect() {
    if (!_isScrollable || _trackLength <= 0 || _viewportWidth <= 0) {
      _cachedThumbRect = null;
      return;
    }
    final trackExtent = math.max(
      1.0,
      _trackLength - _trackPaddingTop - _trackPaddingBottom,
    );
    final thumbExtent = (_isDraggingThumb ? _dragThumbExtent : _visualThumbExtent)
        .clamp(1.0, trackExtent);
    final maxThumbOffset = math.max(0.0, trackExtent - thumbExtent);
    final thumbOffset = _isDraggingThumb
        ? _dragThumbOffset.clamp(0.0, maxThumbOffset)
        : (_visualProgress.clamp(0.0, 1.0) * maxThumbOffset);
    _cachedThumbRect = Rect.fromLTWH(
      math.max(0.0, _viewportWidth - _rightMargin - _effectiveThickness),
      _trackPaddingTop + thumbOffset,
      _effectiveThickness,
      thumbExtent,
    );
  }

  bool _onNotification(Notification notification) {
    if (notification is ScrollNotification && notification.depth == 0) {
      if (notification is ScrollStartNotification) {
        _isUserScrolling = true;
        _showScrollbar();
      } else if (notification is ScrollUpdateNotification) {
        _showScrollbar();
        _syncMetrics(fromScrollUpdate: true);
      } else if (notification is ScrollEndNotification) {
        _isUserScrolling = false;
        _syncMetrics(fromScrollUpdate: false);
        _scheduleFadeOut();
      }
    } else if (notification is ScrollMetricsNotification &&
        notification.depth == 0) {
      _syncMetrics(fromScrollUpdate: false);
    }
    return false;
  }

  void _handleStripPointerDown(PointerDownEvent event) {
    if (!_isScrollable || !widget.controller.hasClients) return;
    if (event.kind == PointerDeviceKind.mouse &&
        (event.buttons & kPrimaryMouseButton) == 0) {
      return;
    }
    final pos = widget.controller.position;
    if (!pos.hasContentDimensions || !pos.hasPixels) return;

    final rect = _cachedThumbRect;
    final y = event.localPosition.dy;
    final hitThumb =
        rect != null && y >= rect.top - 4.0 && y <= rect.bottom + 4.0;

    if (!hitThumb) {
      _showScrollbar();
      if (rect != null) {
        final step = pos.viewportDimension * 0.8;
        final target = (y < rect.top ? pos.pixels - step : pos.pixels + step)
            .clamp(pos.minScrollExtent, pos.maxScrollExtent)
            .toDouble();
        widget.controller.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      }
      return;
    }

    _activeDragPointer = event.pointer;
    _isDraggingThumb = true;
    _showScrollbar(autoFade: false);

    final trackExtent = math.max(
      1.0,
      _trackLength - _trackPaddingTop - _trackPaddingBottom,
    );
    _dragThumbExtent = _visualThumbExtent.clamp(1.0, trackExtent);
    final maxThumbOffset = math.max(1.0, trackExtent - _dragThumbExtent);
    _dragStartThumbOffset = (_visualProgress.clamp(0.0, 1.0) * maxThumbOffset);
    _dragThumbOffset = _dragStartThumbOffset;
    _dragStartPointerY = y;

    final scrollRange = math.max(0.0, pos.maxScrollExtent - pos.minScrollExtent);
    _scrollPerTrackPixel = scrollRange > 0 ? scrollRange / maxThumbOffset : 1.0;

    _incrementalDrag?.cancel();
    _incrementalDrag = pos.drag(
      DragStartDetails(
        localPosition: event.localPosition,
        globalPosition: event.position,
      ),
      () => _incrementalDrag = null,
    );
    _recomputeThumbRect();
    _paintNotifier.notify();
  }

  void _handleStripPointerMove(PointerMoveEvent event) {
    if (!_isDraggingThumb || event.pointer != _activeDragPointer) return;
    if (!widget.controller.hasClients) return;

    final trackExtent = math.max(
      1.0,
      _trackLength - _trackPaddingTop - _trackPaddingBottom,
    );
    final maxThumbOffset = math.max(0.0, trackExtent - _dragThumbExtent);
    final prevThumbOffset = _dragThumbOffset;
    final nextThumbOffset =
        (_dragStartThumbOffset + (event.localPosition.dy - _dragStartPointerY))
            .clamp(0.0, maxThumbOffset)
            .toDouble();
    final effectiveTrackDelta = nextThumbOffset - prevThumbOffset;

    _dragThumbOffset = nextThumbOffset;
    _visualProgress = maxThumbOffset > 0
        ? (nextThumbOffset / maxThumbOffset).clamp(0.0, 1.0)
        : 0.0;
    _recomputeThumbRect();
    _paintNotifier.notify();

    final drag = _incrementalDrag;
    if (drag != null && effectiveTrackDelta != 0.0) {
      final pos = widget.controller.position;
      final reversed = axisDirectionIsReversed(pos.axisDirection);
      final requested =
          effectiveTrackDelta * _scrollPerTrackPixel * (reversed ? -1 : 1);
      final target = (pos.pixels + requested).clamp(
        pos.minScrollExtent,
        pos.maxScrollExtent,
      );
      final delta = (target - pos.pixels) * (reversed ? 1 : -1);
      drag.update(
        DragUpdateDetails(
          localPosition: event.localPosition,
          globalPosition: event.position,
          delta: Offset(0, delta),
          primaryDelta: delta,
        ),
      );
    }
  }

  void _finishThumbDrag({required bool cancelled, Offset? localPosition}) {
    if (!_isDraggingThumb) return;
    _isDraggingThumb = false;
    _activeDragPointer = null;

    final drag = _incrementalDrag;
    _incrementalDrag = null;
    if (cancelled) {
      drag?.cancel();
    } else {
      drag?.end(
        DragEndDetails(
          localPosition: localPosition ?? Offset.zero,
          primaryVelocity: 0,
        ),
      );
    }

    if (widget.controller.hasClients) {
      final pos = widget.controller.position;
      if (pos.hasContentDimensions && pos.hasPixels) {
        if (pos.extentAfter <= 1.0) {
          _visualProgress = 1.0;
        } else if (pos.pixels <= pos.minScrollExtent + 0.5) {
          _visualProgress = 0.0;
        }
        _lastPixels = pos.pixels.clamp(pos.minScrollExtent, pos.maxScrollExtent);
      }
    }

    _recomputeThumbRect();
    _paintNotifier.notify();
    _scheduleFadeOut();
  }

  void _handleStripPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !widget.controller.hasClients) return;
    final pos = widget.controller.position;
    final delta = pos.axis == Axis.vertical
        ? event.scrollDelta.dy
        : event.scrollDelta.dx;
    if (delta == 0.0) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (resolved) {
      if (!mounted || !widget.controller.hasClients) return;
      final scrollEvent = resolved as PointerScrollEvent;
      final p = widget.controller.position;
      final d = p.axis == Axis.vertical
          ? scrollEvent.scrollDelta.dy
          : scrollEvent.scrollDelta.dx;
      p.pointerScroll(d);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = ScrollbarTheme.of(context);
    final colors = context.colors;
    final thickness =
        widget.thickness ?? theme.thickness?.resolve({}) ?? _defaultThickness;
    final radius = widget.radius ?? theme.radius ?? _defaultRadius;
    final baseThumbColor =
        widget.thumbColor ??
        theme.thumbColor?.resolve({}) ??
        colors.borderHover;
    final hitStripWidth = _hitStripWidthFor(thickness);

    return NotificationListener<Notification>(
      onNotification: _onNotification,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final sizeChanged =
              constraints.maxWidth != _viewportWidth ||
              constraints.maxHeight != _trackLength ||
              thickness != _effectiveThickness;
          _viewportWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : 0.0;
          _trackLength = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : 0.0;
          _effectiveThickness = thickness;
          if (sizeChanged) {
            _recomputeThumbRect();
            _schedulePostFrameSync();
          }

          return Stack(
            children: [
              widget.child,
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _StableScrollbarPainter(
                      repaint: Listenable.merge([
                        _fadeController,
                        _paintNotifier,
                      ]),
                      thumbRectProvider: () => _cachedThumbRect,
                      opacityProvider: () => _fadeController.value,
                      isActiveProvider: () =>
                          _isDraggingThumb || _hoveringThumb,
                      baseColor: baseThumbColor,
                      radius: radius,
                    ),
                  ),
                ),
              ),
              if (_isScrollable)
                Positioned(
                  top: 0,
                  bottom: 0,
                  right: 0,
                  width: hitStripWidth,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.basic,
                    onEnter: (_) {
                      _hoveringStrip = true;
                      _showScrollbar(autoFade: false);
                    },
                    onHover: (event) {
                      final rect = _cachedThumbRect;
                      final y = event.localPosition.dy;
                      final overThumb =
                          rect != null &&
                          y >= rect.top - 4.0 &&
                          y <= rect.bottom + 4.0;
                      if (overThumb != _hoveringThumb) {
                        _hoveringThumb = overThumb;
                        _paintNotifier.notify();
                      }
                    },
                    onExit: (_) {
                      _hoveringStrip = false;
                      if (_hoveringThumb) {
                        _hoveringThumb = false;
                        _paintNotifier.notify();
                      }
                      _scheduleFadeOut();
                    },
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: _handleStripPointerDown,
                      onPointerMove: _handleStripPointerMove,
                      onPointerUp: (event) {
                        if (event.pointer == _activeDragPointer) {
                          _finishThumbDrag(
                            cancelled: false,
                            localPosition: event.localPosition,
                          );
                        }
                      },
                      onPointerCancel: (event) {
                        if (event.pointer == _activeDragPointer) {
                          _finishThumbDrag(cancelled: true);
                        }
                      },
                      onPointerSignal: _handleStripPointerSignal,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ThumbPaintNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}

class _StableScrollbarPainter extends CustomPainter {
  final Rect? Function() thumbRectProvider;
  final double Function() opacityProvider;
  final bool Function() isActiveProvider;
  final Color baseColor;
  final Radius radius;

  _StableScrollbarPainter({
    required Listenable repaint,
    required this.thumbRectProvider,
    required this.opacityProvider,
    required this.isActiveProvider,
    required this.baseColor,
    required this.radius,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = thumbRectProvider();
    final opacity = opacityProvider();
    if (rect == null || opacity <= 0.001) return;

    final active = isActiveProvider();
    final targetAlpha = active
        ? (baseColor.a + 0.22).clamp(0.0, 0.72)
        : baseColor.a;
    final paint = Paint()
      ..color = baseColor.withValues(alpha: targetAlpha * opacity)
      ..style = PaintingStyle.fill;

    canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), paint);
  }

  @override
  bool shouldRepaint(covariant _StableScrollbarPainter oldDelegate) {
    return oldDelegate.baseColor != baseColor || oldDelegate.radius != radius;
  }
}
