import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

const double _kEdgeScrollMaxStep = 8;
const double _kEdgeScrollMinSpeed = 80;
const double _kEdgeScrollMaxSpeed = 500;

double _edgeScrollStep(double overshoot, double seconds) {
  final speed = (overshoot * 14).clamp(
    _kEdgeScrollMinSpeed,
    _kEdgeScrollMaxSpeed,
  );
  return math.min(_kEdgeScrollMaxStep, speed * seconds);
}

/// 文本框自身仍可滚轮、拖滚动条，但拒绝光标 `showOnScreen` 的隐式滚动。
///
/// 拖选越过边缘时，框架会按「每个指针事件一行」把视口 `jumpTo`，
/// 并在帧末用 `animateTo` 重启动画。速度随指针离边缘的距离暴涨，
/// 视口就一帧一顿地抽搐，选区也停在半路。关掉隐式滚动后，
/// 由 [StableEdgeSelection] 按封顶速度自己滚。
class StableSelectionScrollPhysics extends ScrollPhysics {
  const StableSelectionScrollPhysics({super.parent});

  @override
  StableSelectionScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return StableSelectionScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  bool get allowImplicitScrolling => false;
}

/// 指针按住并越出盒子边缘时，沿 [axis] 以封顶速度滚动 [controller]，
/// 并把选区延伸到新露出的文本。指针停在边缘外也会继续，直到内容尽头。
///
/// 拖选期间吞掉子树的 `showOnScreen`，避免请求继续冒泡到外层列表或
/// PageView，和盒子自己的滚动对打。
class StableEdgeSelection extends StatefulWidget {
  final ScrollController controller;
  final Axis axis;
  final Widget child;

  const StableEdgeSelection({
    super.key,
    required this.controller,
    required this.child,
    this.axis = Axis.vertical,
  });

  @override
  State<StableEdgeSelection> createState() => _StableEdgeSelectionState();
}

class _StableEdgeSelectionState extends State<StableEdgeSelection>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  int? _pointer;
  Offset? _position;
  int? _anchorOffset;
  Duration _lastTick = Duration.zero;
  bool _blockShowOnScreen = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _stopTracking();
    _ticker.dispose();
    super.dispose();
  }

  void _stopTracking() {
    if (_pointer != null) {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    }
    _pointer = null;
    _position = null;
    _anchorOffset = null;
    _ticker.stop();
    _setBlocking(false);
  }

  /// 直接改渲染对象，不 setState。拖选中重建 TextField 会拆掉手势，
  /// 选区停在半路。
  void _setBlocking(bool value) {
    if (_blockShowOnScreen == value) return;
    _blockShowOnScreen = value;
    if (!mounted) return;
    final render = context.findRenderObject();
    render?.visitChildren((child) {
      if (child is _RenderShowOnScreenGate) child.block = value;
    });
  }

  bool _accepts(PointerDownEvent event) {
    return switch (event.kind) {
      PointerDeviceKind.touch ||
      PointerDeviceKind.stylus ||
      PointerDeviceKind.invertedStylus => true,
      PointerDeviceKind.mouse ||
      PointerDeviceKind.trackpad ||
      PointerDeviceKind.unknown => event.buttons == kPrimaryButton,
    };
  }

  void _onPointerDown(PointerDownEvent event) {
    if (!_accepts(event)) return;
    _stopTracking();
    _pointer = event.pointer;
    _position = event.position;
    _anchorOffset = _offsetAt(event.position);
    _lastTick = Duration.zero;
    _setBlocking(true);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    _ticker.start();
  }

  void _onPointer(PointerEvent event) {
    if (event.pointer != _pointer) return;
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      _stopTracking();
      return;
    }
    if (event is PointerMoveEvent || event is PointerHoverEvent) {
      _position = event.position;
    }
  }

  void _onTick(Duration elapsed) {
    final pointer = _position;
    final dt = elapsed - _lastTick;
    _lastTick = elapsed;
    if (!mounted || pointer == null || dt <= Duration.zero) return;

    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    final rect = Rect.fromPoints(
      box.localToGlobal(Offset.zero),
      box.localToGlobal(Offset(box.size.width, box.size.height)),
    );

    final overshoot = _overshoot(rect, pointer);
    if (overshoot == null) return;

    final seconds = dt.inMicroseconds / Duration.microsecondsPerSecond;
    final step = _edgeScrollStep(overshoot.distance, seconds);
    if (step <= 0) return;

    _scrollBy(overshoot.towardEnd ? step : -step);
    _extendSelection(rect, overshoot.towardEnd);
  }

  _EdgeOvershoot? _overshoot(Rect rect, Offset pointer) {
    final reversed = widget.controller.hasClients
        ? axisDirectionIsReversed(widget.controller.position.axisDirection)
        : false;
    if (widget.axis == Axis.vertical) {
      if (pointer.dy > rect.bottom) {
        return _EdgeOvershoot(
          distance: pointer.dy - rect.bottom,
          towardEnd: !reversed,
        );
      }
      if (pointer.dy < rect.top) {
        return _EdgeOvershoot(
          distance: rect.top - pointer.dy,
          towardEnd: reversed,
        );
      }
      return null;
    }
    if (pointer.dx > rect.right) {
      return _EdgeOvershoot(
        distance: pointer.dx - rect.right,
        towardEnd: !reversed,
      );
    }
    if (pointer.dx < rect.left) {
      return _EdgeOvershoot(
        distance: rect.left - pointer.dx,
        towardEnd: reversed,
      );
    }
    return null;
  }

  void _scrollBy(double delta) {
    final controller = widget.controller;
    if (!controller.hasClients || !controller.position.hasContentDimensions) {
      return;
    }
    final position = controller.position;
    final target = (position.pixels + delta)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if ((target - position.pixels).abs() < 0.5) return;
    position.jumpTo(target);
  }

  void _extendSelection(Rect rect, bool towardEnd) {
    final editable = _findEditableText(context as Element);
    if (editable == null || !editable.mounted) return;
    final render = editable.renderEditable;
    if (!render.attached || !render.hasSize) return;

    final edge = widget.axis == Axis.vertical
        ? Offset(rect.center.dx, towardEnd ? rect.bottom - 2 : rect.top + 2)
        : Offset(towardEnd ? rect.right - 2 : rect.left + 2, rect.center.dy);
    final value = editable.textEditingValue;
    var target = render.getPositionForPoint(edge).offset;
    final scroll = widget.controller;
    if (scroll.hasClients && scroll.position.hasContentDimensions) {
      final pixels = scroll.position.pixels;
      // 命中测试贴不住盒子内边距里的最后几个字符，滚到底后收到文档边界。
      if (towardEnd && pixels >= scroll.position.maxScrollExtent - 0.5) {
        target = value.text.length;
      } else if (!towardEnd &&
          pixels <= scroll.position.minScrollExtent + 0.5) {
        target = 0;
      }
    }
    final selection = value.selection;
    if (!selection.isValid) {
      final base = _anchorOffset ?? target;
      if (base == target) return;
      editable.userUpdateTextEditingValue(
        value.copyWith(
          selection: TextSelection(baseOffset: base, extentOffset: target),
        ),
        SelectionChangedCause.drag,
      );
      return;
    }
    if (target == selection.extentOffset) return;

    final base = selection.baseOffset;
    final nextDistance = (target - base).abs();
    final currentDistance = (selection.extentOffset - base).abs();
    if (nextDistance <= currentDistance) return;
    if (!selection.isCollapsed &&
        (target - base).sign != (selection.extentOffset - base).sign) {
      return;
    }

    editable.userUpdateTextEditingValue(
      value.copyWith(selection: selection.copyWith(extentOffset: target)),
      SelectionChangedCause.drag,
    );
  }

  int? _offsetAt(Offset global) {
    final editable = _findEditableText(context as Element);
    final render = editable?.renderEditable;
    if (editable == null ||
        render == null ||
        !render.attached ||
        !render.hasSize) {
      return null;
    }
    return render.getPositionForPoint(global).offset;
  }

  EditableTextState? _findEditableText(Element element) {
    EditableTextState? found;
    element.visitChildren((child) {
      if (found != null) return;
      if (child is StatefulElement && child.state is EditableTextState) {
        found = child.state as EditableTextState;
        return;
      }
      found = _findEditableText(child);
    });
    return found;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      child: _ShowOnScreenGate(block: _blockShowOnScreen, child: widget.child),
    );
  }
}

class _EdgeOvershoot {
  final double distance;
  final bool towardEnd;
  const _EdgeOvershoot({required this.distance, required this.towardEnd});
}

class _ShowOnScreenGate extends SingleChildRenderObjectWidget {
  final bool block;

  const _ShowOnScreenGate({required this.block, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderShowOnScreenGate(block: block);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderShowOnScreenGate renderObject,
  ) {
    renderObject.block = block;
  }
}

class _RenderShowOnScreenGate extends RenderProxyBox {
  _RenderShowOnScreenGate({required this._block});

  bool _block;
  set block(bool value) {
    if (_block == value) return;
    _block = value;
  }

  bool get block => _block;

  @override
  void showOnScreen({
    RenderObject? descendant,
    Rect? rect,
    Duration duration = Duration.zero,
    Curve curve = Curves.ease,
  }) {
    if (_block && descendant != null) return;
    super.showOnScreen(
      descendant: descendant,
      rect: rect,
      duration: duration,
      curve: curve,
    );
  }
}

/// 高度受限的只读文本：内部滚动不再把 `showOnScreen` 传给外层列表。
class BoundedSelectableText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final double maxHeight;

  const BoundedSelectableText({
    super.key,
    required this.text,
    required this.style,
    required this.maxHeight,
  });

  @override
  State<BoundedSelectableText> createState() => _BoundedSelectableTextState();
}

class _BoundedSelectableTextState extends State<BoundedSelectableText> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StableEdgeSelection(
      controller: _controller,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: widget.maxHeight),
        child: SingleChildScrollView(
          controller: _controller,
          physics: const StableSelectionScrollPhysics(),
          child: SelectableText(
            widget.text,
            style: widget.style,
            scrollPhysics: const StableSelectionScrollPhysics(),
          ),
        ),
      ),
    );
  }
}
