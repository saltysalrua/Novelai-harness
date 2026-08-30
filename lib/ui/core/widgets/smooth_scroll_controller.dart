import 'dart:async' show unawaited;

import 'package:flutter/widgets.dart';

/// 平滑滚轮滚动控制器：重写 [ScrollPosition.pointerScroll]，
/// 把 Windows 桌面端鼠标滚轮默认的"逐格瞬移"改为短时长 animateTo 滑动。
///
/// 原理：Scrollable 收到 PointerScrollEvent 后调用 position.pointerScroll，
/// 默认实现直接 forcePixels 瞬移一格 (~53px)。本控制器替换为 160ms
/// easeOutCubic 滑动；连续滚动时从"当前滑行目标"累加并重新发起新滑动，
/// 得到连续滑行手感。拖拽滚动条等手势不受影响 (DragScrollActivity 时回退默认)。
class SmoothWheelScrollController extends ScrollController {
  SmoothWheelScrollController({super.initialScrollOffset, super.debugLabel});

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return _SmoothWheelScrollPosition(
      physics: physics,
      context: context,
      oldPosition: oldPosition,
      initialPixels: initialScrollOffset,
      keepScrollOffset: keepScrollOffset,
      debugLabel: debugLabel,
    );
  }
}

class _SmoothWheelScrollPosition extends ScrollPositionWithSingleContext {
  _SmoothWheelScrollPosition({
    required super.physics,
    required super.context,
    super.oldPosition,
    double? initialPixels,
    super.keepScrollOffset,
    super.debugLabel,
  }) {
    if (!hasPixels && initialPixels != null) {
      correctPixels(initialPixels);
    }
  }

  /// 单次滚轮滑动的时长与曲线
  static const Duration _glideDuration = Duration(milliseconds: 160);

  /// 上次滚轮滑行的目标像素 (仅在 DrivenScrollActivity 滑行期间有效)
  double? _wheelTarget;

  @override
  void pointerScroll(double delta) {
    if (delta == 0.0) {
      super.pointerScroll(delta);
      return;
    }
    if (!haveDimensions) return;
    if (!physics.shouldAcceptUserOffset(this)) return;

    // 拖拽手势 (滚动条拖动等) 进行中时退回默认逐格滚动，避免打断用户手势
    if (activity is DragScrollActivity) {
      super.pointerScroll(delta);
      return;
    }

    // 滑行中: 从上次目标继续累加；静止: 从当前像素起步
    final bool gliding = activity is DrivenScrollActivity;
    final double base = gliding ? (_wheelTarget ?? pixels) : pixels;
    final double target = (base + delta)
        .clamp(minScrollExtent, maxScrollExtent)
        .toDouble();
    _wheelTarget = target;

    if (!gliding && target == pixels) return;
    goIdle();
    unawaited(
      animateTo(target, duration: _glideDuration, curve: Curves.easeOutCubic),
    );
  }
}
