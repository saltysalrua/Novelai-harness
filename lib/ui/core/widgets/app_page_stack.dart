import 'package:flutter/widgets.dart';

import '../theme/app_motion.dart';

/// 固定槽位的保活页面容器：未访问页懒构建，隐藏页复用上次 Widget，
/// 不随父级通知重复构建；再次显示时用最新参数更新，保留 State 与滚动位置。
///
/// 只对当前页面做入场动效 (`08-page-side-by-side`)，不同时绘制新旧两棵重页面。
/// 动画仅改变透明度和 8px 方向感知水平绘制位移，不逐帧重建页面；隐藏页禁用焦点与 Ticker。
/// 槽位含义应保持稳定。
class AppPageStack extends StatefulWidget {
  final int index;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  const AppPageStack({
    super.key,
    required this.index,
    required this.itemCount,
    required this.itemBuilder,
  }) : assert(itemCount > 0),
       assert(index >= 0 && index < itemCount);

  @override
  State<AppPageStack> createState() => _AppPageStackState();
}

class _AppPageStackState extends State<AppPageStack>
    with SingleTickerProviderStateMixin {
  static const double _enterStartOpacity = 0.78;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotionDurations.quick,
    value: 1,
  );
  late final Animation<double> _curved = _controller.drive(
    CurveTween(curve: AppMotionCurves.smoothOut),
  );
  late final Animation<double> _opacity = _controller.drive(
    Tween<double>(
      begin: _enterStartOpacity,
      end: 1.0,
    ).chain(CurveTween(curve: AppMotionCurves.smoothOut)),
  );
  final List<Widget?> _pages = [];
  bool _reduceMotion = false;
  int _direction = 1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = AppMotion.shouldReduceMotion(context);
    if (_reduceMotion) _controller.value = 1;
  }

  @override
  void didUpdateWidget(covariant AppPageStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      _direction = widget.index > oldWidget.index ? 1 : -1;
      if (_reduceMotion) {
        _controller.value = 1;
      } else {
        _controller.forward(from: 0);
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
    _pages.length = widget.itemCount;
    _pages[widget.index] = widget.itemBuilder(context, widget.index);

    final stack = IndexedStack(
      index: widget.index,
      sizing: StackFit.expand,
      children: [
        for (var i = 0; i < widget.itemCount; i++)
          TickerMode(
            enabled: i == widget.index,
            child: ExcludeFocus(
              excluding: i != widget.index,
              child: RepaintBoundary(
                child: _pages[i] ?? const SizedBox.shrink(),
              ),
            ),
          ),
      ],
    );

    return ClipRect(
      child: FadeTransition(
        opacity: _opacity,
        child: AnimatedBuilder(
          animation: _curved,
          builder: (context, child) {
            final dx =
                _direction * AppMotionDistances.base * (1.0 - _curved.value);
            return Transform.translate(offset: Offset(dx, 0), child: child);
          },
          child: stack,
        ),
      ),
    );
  }
}
