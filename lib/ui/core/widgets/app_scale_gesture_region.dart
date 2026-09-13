import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// 看图/画板操作面的缩放入口：第二个触点落下即开始捏合，不吞掉短距离动作。
///
/// [multitouchOnly] 让单指继续交给子节点编辑或祖先滚动。不会抢夺已经
/// 赢得竞技场的单指手势；不用于需要保留双指滚动的普通列表。
class AppScaleGestureRegion extends StatelessWidget {
  final Widget child;
  final GestureScaleStartCallback? onScaleStart;
  final GestureScaleUpdateCallback? onScaleUpdate;
  final GestureScaleEndCallback? onScaleEnd;
  final GestureTapCallback? onTap;
  final GestureTapCallback? onDoubleTap;
  final bool multitouchOnly;

  const AppScaleGestureRegion({
    super.key,
    required this.child,
    this.onScaleStart,
    this.onScaleUpdate,
    this.onScaleEnd,
    this.onTap,
    this.onDoubleTap,
    this.multitouchOnly = false,
  });

  @override
  Widget build(BuildContext context) => RawGestureDetector(
    behavior: HitTestBehavior.opaque,
    gestures: {
      if (onTap != null)
        TapGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
              TapGestureRecognizer.new,
              (recognizer) => recognizer
                ..gestureSettings = MediaQuery.gestureSettingsOf(context)
                ..onTap = onTap,
            ),
      if (onDoubleTap != null)
        DoubleTapGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<DoubleTapGestureRecognizer>(
              DoubleTapGestureRecognizer.new,
              (recognizer) => recognizer
                ..gestureSettings = MediaQuery.gestureSettingsOf(context)
                ..onDoubleTap = onDoubleTap,
            ),
      _ImmediateMultitouchScaleRecognizer:
          GestureRecognizerFactoryWithHandlers<
            _ImmediateMultitouchScaleRecognizer
          >(
            _ImmediateMultitouchScaleRecognizer.new,
            (recognizer) => recognizer
              ..gestureSettings = MediaQuery.gestureSettingsOf(context)
              ..multitouchOnly = multitouchOnly
              ..onStart = onScaleStart
              ..onUpdate = (details) {
                if (!multitouchOnly || details.pointerCount >= 2) {
                  onScaleUpdate?.call(details);
                }
              }
              ..onEnd = onScaleEnd,
          ),
    },
    child: child,
  );
}

class _ImmediateMultitouchScaleRecognizer extends ScaleGestureRecognizer {
  bool multitouchOnly = false;

  @override
  void handleEvent(PointerEvent event) {
    // 必须先让 ScaleGestureRecognizer 记录新触点并重建 span/focal 基准，
    // 再接受竞技场，否则第二指的质心变化会被误算成缩放或平移。
    super.handleEvent(event);
    if (event is PointerDownEvent && pointerCount >= 2) {
      resolve(GestureDisposition.accepted);
    }
  }

  @override
  void resolve(GestureDisposition disposition) {
    if (multitouchOnly &&
        disposition == GestureDisposition.accepted &&
        pointerCount < 2) {
      return;
    }
    super.resolve(disposition);
  }
}
