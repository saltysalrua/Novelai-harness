import 'package:flutter/foundation.dart'
    show DoubleProperty, FlagProperty, ValueNotifier;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// 双指捏合手势更新详情。
///
/// [scale] 为相对当前基线 (手势开始或手指组合变化时重建) 的累计缩放；
/// [localFocalPoint] 为双指中点在识别器宿主组件局部坐标系的位置；
/// [focalDelta] 为相邻两次更新间的中点位移；[pointerCount] 为当前参与
/// 手势的手指数量 (手指组合发生变化时基线会被重建，消费方应在
/// [pointerCount] 变化帧跳过变换、只重置自身基准)。
class TwoFingerScaleUpdateDetails {
  const TwoFingerScaleUpdateDetails({
    required this.scale,
    required this.localFocalPoint,
    required this.focalDelta,
    required this.pointerCount,
  });

  final double scale;
  final Offset localFocalPoint;
  final Offset focalDelta;
  final int pointerCount;
}

/// 仅双指生效的捏合识别器。
///
/// 与通用 [ScaleGestureRecognizer] 不同，本识别器在双指指距变化超过
/// [kTouchSlop] 之前绝不接受竞技场，单指拖拽完全让位给外层
/// ListView / PageView 等滚动容器，因此可安全嵌套在可滚动列表的
/// 列表项中而不劫持滚动。识别到捏合后双指中点的移动作为平移透出，
/// 实现捏合缩放 + 双指平移两种语义。
class TwoFingerScaleGestureRecognizer extends OneSequenceGestureRecognizer {
  TwoFingerScaleGestureRecognizer({
    this.onStarted,
    this.onUpdated,
    this.onEnded,
    super.debugOwner,
    super.supportedDevices,
  });

  /// 捏合手势开始 (指距首次越过判定阈值)，参数为起始双指中点
  ValueChanged<Offset>? onStarted;

  /// 捏合手势更新
  ValueChanged<TwoFingerScaleUpdateDetails>? onUpdated;

  /// 捏合手势结束 (手指少于两根)
  VoidCallback? onEnded;

  /// 参与基线计算的两根手指 (按落下顺序取最早两根)
  final Map<int, Offset> _pointers = <int, Offset>{};
  final List<int> _pointerOrder = <int>[];

  double _initialSpan = 0.0;
  Offset _lastFocal = Offset.zero;
  bool _started = false;

  int get _pinchPointerCount => _pointerOrder.length;

  Offset _focalOfTrackedPair() {
    final a = _pointers[_pointerOrder[0]]!;
    final b = _pointers[_pointerOrder[1]]!;
    return Offset((a.dx + b.dx) / 2.0, (a.dy + b.dy) / 2.0);
  }

  double _spanOfTrackedPair() {
    final a = _pointers[_pointerOrder[0]]!;
    final b = _pointers[_pointerOrder[1]]!;
    return (a - b).distance;
  }

  /// 手指组合变化时重建缩放与平移基准，避免跳变
  void _rebuildBaseline() {
    if (_pinchPointerCount < 2) {
      _initialSpan = 0.0;
      return;
    }
    _initialSpan = _spanOfTrackedPair();
    _lastFocal = _focalOfTrackedPair();
  }

  void _endGesture() {
    if (!_started) return;
    _started = false;
    onEnded?.call();
  }

  @override
  void addAllowedPointer(PointerDownEvent event) {
    startTrackingPointer(event.pointer, event.transform);
    _pointers[event.pointer] = event.localPosition;
    _pointerOrder.add(event.pointer);
    // 捏合进行中落下的第三根手指只重建基准，不打断手势
    _rebuildBaseline();
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) {
      if (!_pointers.containsKey(event.pointer)) return;
      _pointers[event.pointer] = event.localPosition;
      if (_pinchPointerCount < 2) return;

      final span = _spanOfTrackedPair();
      if (!_started) {
        if (_initialSpan > 0.0 && (span - _initialSpan).abs() > kTouchSlop) {
          _started = true;
          // 接管竞技场：外层滚动手势被拒绝，捏合期间列表不再滚动
          resolve(GestureDisposition.accepted);
          _rebuildBaseline();
          onStarted?.call(_lastFocal);
        }
        return;
      }

      final scale = _initialSpan > 0.0 ? span / _initialSpan : 1.0;
      final focal = _focalOfTrackedPair();
      if (scale.isFinite) {
        onUpdated?.call(
          TwoFingerScaleUpdateDetails(
            scale: scale,
            localFocalPoint: focal,
            focalDelta: focal - _lastFocal,
            pointerCount: _pinchPointerCount,
          ),
        );
        _lastFocal = focal;
      }
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      _removePointer(event.pointer);
    }
  }

  void _removePointer(int pointer) {
    if (!_pointers.containsKey(pointer)) return;
    _pointers.remove(pointer);
    _pointerOrder.remove(pointer);
    stopTrackingPointer(pointer);
    if (_started) {
      if (_pinchPointerCount < 2) {
        _endGesture();
      } else {
        _rebuildBaseline();
      }
    } else {
      _rebuildBaseline();
    }
  }

  @override
  void acceptGesture(int pointer) {}

  @override
  void rejectGesture(int pointer) {
    // 竞技场被外层滚动等手势夺走：未开始的捏合静默让位；
    // 进行中的捏合因丢失手指而终止
    if (_pointers.containsKey(pointer)) {
      _pointers.remove(pointer);
      _pointerOrder.remove(pointer);
      stopTrackingPointer(pointer);
      if (_started && _pinchPointerCount < 2) {
        _endGesture();
      } else {
        _rebuildBaseline();
      }
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _endGesture();
    _pointers.clear();
    _pointerOrder.clear();
    _initialSpan = 0.0;
  }

  @override
  void dispose() {
    _pointers.clear();
    _pointerOrder.clear();
    super.dispose();
  }

  @override
  String get debugDescription => 'two finger scale';

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DoubleProperty('initialSpan', _initialSpan));
    properties.add(FlagProperty('started', value: _started, ifTrue: 'started'));
  }
}

/// 双指捏合手势原子组件：包装任意内容，在触摸屏上以双指捏合缩放、
/// 双指平移回调驱动，单指交互完全透传给外层手势 (滚动、点按等)。
///
/// 无业务状态、纯回调驱动，可复用于滚动列表内的卡片局部缩放。
class TwoFingerScale extends StatelessWidget {
  const TwoFingerScale({
    super.key,
    this.onStarted,
    this.onUpdated,
    this.onEnded,
    this.behavior = HitTestBehavior.opaque,
    required this.child,
  });

  /// 捏合开始回调 (参数为起始双指中点)
  final ValueChanged<Offset>? onStarted;

  /// 捏合更新回调 (含累计缩放、双指中点与其位移)
  final ValueChanged<TwoFingerScaleUpdateDetails>? onUpdated;

  /// 捏合结束回调
  final VoidCallback? onEnded;

  /// 命中测试行为，默认 [HitTestBehavior.opaque] 保证卡片内任何位置
  /// 都能起手双指捏合
  final HitTestBehavior behavior;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      excludeFromSemantics: true,
      behavior: behavior,
      gestures: <Type, GestureRecognizerFactory>{
        TwoFingerScaleGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<
              TwoFingerScaleGestureRecognizer
            >(
              TwoFingerScaleGestureRecognizer.new,
              (instance) {
                instance
                  ..onStarted = onStarted
                  ..onUpdated = onUpdated
                  ..onEnded = onEnded;
              },
            ),
      },
      child: child,
    );
  }
}

/// 卡片内双指捏合缩放容器：包装任意内容，触摸屏上双指捏合原地缩放，
/// 双指同步移动平移 (带无空边钳制)；单指点按/滚动/双击等交互完全透传，
/// 不劫持外层 ListView / PageView 的滚动手势。
///
/// 高频变换由内部 [ValueNotifier] 局部驱动，捏合过程不重建外层 Widget。
/// 缩回 [minScale] 附近时自动归位；松手保持当前缩放状态。
class TwoFingerPinchZoom extends StatefulWidget {
  const TwoFingerPinchZoom({
    super.key,
    this.minScale = 1.0,
    this.maxScale = 6.0,
    required this.child,
  });

  /// 最小缩放 (默认 1.0：不缩小，只放大)
  final double minScale;

  /// 最大缩放
  final double maxScale;

  final Widget child;

  @override
  State<TwoFingerPinchZoom> createState() => _TwoFingerPinchZoomState();
}

class _TwoFingerPinchZoomState extends State<TwoFingerPinchZoom> {
  final ValueNotifier<Matrix4> _matrix = ValueNotifier(Matrix4.identity());
  int _pointerCount = 0;
  double _lastScale = 1.0;
  Offset _lastFocal = Offset.zero;

  @override
  void dispose() {
    _matrix.dispose();
    super.dispose();
  }

  void _handleStarted(Offset startFocal) {
    _pointerCount = 2;
    _lastScale = 1.0;
    _lastFocal = startFocal;
  }

  void _handleUpdated(TwoFingerScaleUpdateDetails details, Size size) {
    // 手指组合变化：识别器已重建基线，本帧只重置自身基准，不施加跳变
    if (details.pointerCount != _pointerCount) {
      _pointerCount = details.pointerCount;
      _lastScale = details.scale;
      _lastFocal = details.localFocalPoint;
      return;
    }

    final current = _matrix.value;
    final incremental = details.scale / _lastScale;
    _lastScale = details.scale;
    if (!incremental.isFinite || incremental <= 0.0) return;

    final targetScale = (current.storage[0] * incremental).clamp(
      widget.minScale,
      widget.maxScale,
    );

    // 缩回最小倍时直接归位，避免残偏移
    if (targetScale <= widget.minScale + 0.001) {
      _matrix.value = Matrix4.identity();
      _lastFocal = details.localFocalPoint;
      return;
    }

    // 上次焦点下的内容点在缩放后跟随当前焦点：焦点锚定公式同时实现
    // 捏合缩放与双指平移 (与全屏大图灯箱同构)
    final scenePoint = MatrixUtils.transformPoint(
      Matrix4.inverted(current),
      _lastFocal,
    );
    final next = Matrix4.identity()
      ..storage[0] = targetScale
      ..storage[5] = targetScale
      ..storage[10] = 1.0
      ..storage[12] = details.localFocalPoint.dx - scenePoint.dx * targetScale
      ..storage[13] = details.localFocalPoint.dy - scenePoint.dy * targetScale
      ..storage[15] = 1.0;
    _lastFocal = details.localFocalPoint;

    _matrix.value = _clampPan(next, size);
  }

  /// 平移钳制：缩放后的内容始终覆盖满卡片，不出空边
  Matrix4 _clampPan(Matrix4 m, Size size) {
    final s = m.storage[0];
    final rangeX = (s - 1.0) * size.width;
    final rangeY = (s - 1.0) * size.height;
    if (rangeX <= 0.0 && rangeY <= 0.0) return Matrix4.identity();
    final clamped = Matrix4.copy(m);
    clamped.storage[12] = m.storage[12].clamp(-rangeX, 0.0);
    clamped.storage[13] = m.storage[13].clamp(-rangeY, 0.0);
    return clamped;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final contentSize = constraints.biggest;
        return TwoFingerScale(
          onStarted: _handleStarted,
          onUpdated: (details) => _handleUpdated(details, contentSize),
          child: ValueListenableBuilder<Matrix4>(
            valueListenable: _matrix,
            builder: (context, matrix, child) =>
                Transform(transform: matrix, child: child),
            child: widget.child,
          ),
        );
      },
    );
  }
}