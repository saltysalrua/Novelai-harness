import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// 二维操作面的拖动入口，使用与单轴滚动相同的起拖阈值。
///
/// Flutter 默认 Pan 的 touch slop 是横/纵向 Drag 的两倍，嵌套在
/// PageView 或 ListView 时会先被祖先识别成翻页/滚动。本组件只在
/// 自身命中区域参与竞争，不关闭外层滚动，也不在按下时抢占点击。
class AppPanGestureRegion extends StatelessWidget {
  final Widget child;
  final GestureTapUpCallback? onTapUp;
  final GestureDragDownCallback? onPanDown;
  final GestureDragStartCallback? onPanStart;
  final GestureDragUpdateCallback? onPanUpdate;
  final GestureDragEndCallback? onPanEnd;
  final GestureDragCancelCallback? onPanCancel;
  final HitTestBehavior behavior;

  const AppPanGestureRegion({
    super.key,
    required this.child,
    this.onTapUp,
    this.onPanDown,
    this.onPanStart,
    this.onPanUpdate,
    this.onPanEnd,
    this.onPanCancel,
    this.behavior = HitTestBehavior.opaque,
  });

  @override
  Widget build(BuildContext context) => RawGestureDetector(
    behavior: behavior,
    gestures: {
      if (onTapUp != null)
        TapGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
              TapGestureRecognizer.new,
              (recognizer) => recognizer
                ..gestureSettings = MediaQuery.gestureSettingsOf(context)
                ..onTapUp = onTapUp,
            ),
      _SurfacePanRecognizer:
          GestureRecognizerFactoryWithHandlers<_SurfacePanRecognizer>(
            _SurfacePanRecognizer.new,
            (recognizer) => recognizer
              ..gestureSettings = MediaQuery.gestureSettingsOf(context)
              ..dragStartBehavior = DragStartBehavior.down
              ..onDown = onPanDown
              ..onStart = onPanStart
              ..onUpdate = onPanUpdate
              ..onEnd = onPanEnd
              ..onCancel = onPanCancel,
          ),
    },
    child: child,
  );
}

class _SurfacePanRecognizer extends PanGestureRecognizer {
  @override
  void handleEvent(PointerEvent event) {
    if (event is! PointerCancelEvent) {
      super.handleEvent(event);
      return;
    }
    // Drag 已被接受后，Flutter 会把 PointerCancel 送到 onEnd；
    // 操作面取消必须丢弃预览，不能被业务误当成松手提交。
    final end = onEnd;
    onEnd = (_) => onCancel?.call();
    try {
      super.handleEvent(event);
    } finally {
      onEnd = end;
    }
  }

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) =>
      globalDistanceMoved.abs() >
      computeHitSlop(pointerDeviceKind, gestureSettings);
}
