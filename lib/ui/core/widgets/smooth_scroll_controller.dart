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

  /// 本控制器发起的滚轮滑行活动与累计目标 (成对记录)。
  /// 活动一旦被外部 animateTo/jumpTo 顶替，配对立即失效，
  /// 防止把过期目标误当滚轮基准造成视口瞬移。
  ScrollActivity? _glideActivity;

  /// 上次滚轮滑行的累计目标像素 (仅在 [_glideActivity] 存活期间有效)
  double? _wheelTarget;

  @override
  void beginActivity(ScrollActivity? newActivity) {
    // 任何新活动 (外部 animateTo/jumpTo/拖拽/惯性或滑行自然结束后的空闲)
    // 顶替旧配对时立即清理，杜绝废弃引用与幻影目标残留
    if (!identical(newActivity, _glideActivity)) {
      _glideActivity = null;
      _wheelTarget = null;
    }
    super.beginActivity(newActivity);
  }

  @override
  void pointerScroll(double delta) {
    if (delta == 0.0) {
      super.pointerScroll(delta);
      return;
    }
    if (!haveDimensions) return;
    if (!physics.shouldAcceptUserOffset(this)) return;

    // 尊重系统减少动画设置；拖拽时也不启动新的滑行活动。
    if (MediaQuery.disableAnimationsOf(context.storageContext) ||
        activity is DragScrollActivity) {
      super.pointerScroll(delta);
      return;
    }

    // 仅在「本控制器先前发起的滚轮滑行」尚未结束时才从累计目标续加。
    // 外部 animateTo (如发送消息后的底部跟随动画) 同样表现为
    // DrivenScrollActivity，误认会沿用早已过期的 _wheelTarget 幻影目标，
    // 把视口瞬移到完全无关的位置
    final bool gliding =
        activity is DrivenScrollActivity && identical(activity, _glideActivity);
    final pendingDistance = gliding ? (_wheelTarget ?? pixels) - pixels : 0.0;
    // 反向滚轮立即以当前位置为基准，丢弃尚未完成的旧方向位移，
    // 否则快速回拨仍会朝旧方向滑动，产生粘滞与输入延迟感。
    final reversing = pendingDistance * delta < 0;
    final double base = gliding && !reversing
        ? (_wheelTarget ?? pixels)
        : pixels;
    final double target = (base + delta)
        .clamp(minScrollExtent, maxScrollExtent)
        .toDouble();

    if (!gliding && target == pixels) return;

    goIdle();
    unawaited(
      animateTo(target, duration: _glideDuration, curve: Curves.easeOutCubic),
    );
    // animateTo 同步 beginActivity (会先把旧配对清为 null)，因此在调用后
    // 重新登记本次配对：滑行身份令牌 + 累计目标二者必须同写同清
    _wheelTarget = target;
    _glideActivity = activity;
  }
}
