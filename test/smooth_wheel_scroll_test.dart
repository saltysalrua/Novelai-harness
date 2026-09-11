import 'dart:async' show unawaited;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/ui/core/widgets/smooth_scroll_controller.dart';

Widget _buildList(SmoothWheelScrollController controller) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: 400,
        child: ListView.builder(
          controller: controller,
          itemCount: 100,
          itemBuilder: (_, index) =>
              SizedBox(height: 100, child: Text('$index')),
        ),
      ),
    ),
  );
}

/// 在列表中心派发一次滚轮事件 (scrollDelta.dy > 0 为向下滚动)
Future<void> _sendWheel(WidgetTester tester, double dy) async {
  final center = tester.getCenter(find.byType(ListView));
  await tester.sendEventToBinding(
    PointerScrollEvent(
      position: center,
      scrollDelta: Offset(0, dy),
      kind: PointerDeviceKind.mouse,
    ),
  );
  await tester.pump();
}

void main() {
  for (final direction in [1.0, -1.0]) {
    testWidgets('快速反向滚轮立即从当前位置转向 (direction=$direction)', (tester) async {
      final controller = SmoothWheelScrollController(initialScrollOffset: 2000);
      addTearDown(controller.dispose);
      await tester.pumpWidget(_buildList(controller));
      await _sendWheel(tester, 600 * direction);
      await tester.pump(const Duration(milliseconds: 16));
      final before = controller.offset;
      await _sendWheel(tester, -80 * direction);
      await tester.pump(const Duration(milliseconds: 32));
      expect((controller.offset - before) * direction, lessThan(0));
      await tester.pumpAndSettle();
      expect(controller.offset, closeTo(before - 80 * direction, 0.5));
    });
  }

  testWidgets('减少动画设置使滚轮即时定位', (tester) async {
    final controller = SmoothWheelScrollController();
    addTearDown(controller.dispose);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(_buildList(controller));
    await _sendWheel(tester, 120);
    expect(controller.offset, 120);
    expect(controller.position.isScrollingNotifier.value, isFalse);
  });

  testWidgets('单次滚轮事件平滑滑动到目标像素', (tester) async {
    final controller = SmoothWheelScrollController();
    await tester.pumpWidget(_buildList(controller));

    await _sendWheel(tester, 120);
    expect(controller.position.pixels, closeTo(0, 0.1));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(controller.position.pixels, closeTo(120, 0.1));
    controller.dispose();
  });

  testWidgets('连续滚轮事件从上次滑行目标累加', (tester) async {
    final controller = SmoothWheelScrollController();
    await tester.pumpWidget(_buildList(controller));

    await _sendWheel(tester, 120);
    await tester.pump(const Duration(milliseconds: 50)); // 第一次滑行未满
    await _sendWheel(tester, 120); // 第二次应从 240 目标续加，而非当前像素
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(controller.position.pixels, closeTo(240, 0.5));
    controller.dispose();
  });

  testWidgets('外部 animateTo 顶替滑行后，滚轮不得沿用幻影累计目标', (tester) async {
    final controller = SmoothWheelScrollController();
    await tester.pumpWidget(_buildList(controller));

    // 1. 滚轮向下滑行 (目标 120)，滑行中 (未满 160ms)
    await _sendWheel(tester, 120);
    await tester.pump(const Duration(milliseconds: 50));

    // 2. 程序化 animateTo 顶替滚轮滑行 (模拟发送消息后 200ms 跟随动画)
    unawaited(
      controller.animateTo(
        3000,
        duration: const Duration(milliseconds: 250),
        curve: Curves.linear,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100)); // 外部动画进行中

    // 3. 用户此时滚轮向上：必须从「当前真实像素」起步，
    //    严禁沿用旧滚轮目标 120 累加出 40 这类幻影目标造成瞬移
    await _sendWheel(tester, -80);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    // 未修复时最终位置 ≈ 40 (120-80)；修复后应为外部动画当前值附近再 -80，
    // 远大于 500
    expect(controller.position.pixels, greaterThan(500));
    expect(controller.position.pixels, lessThan(3000));
    controller.dispose();
  });

  testWidgets('外部 jumpTo 后滚轮从真实像素起步', (tester) async {
    final controller = SmoothWheelScrollController();
    await tester.pumpWidget(_buildList(controller));

    await _sendWheel(tester, 120);
    await tester.pump(const Duration(milliseconds: 50)); // 滑行中
    controller.jumpTo(2000); // 外部瞬移终止滑行
    await tester.pump();

    await _sendWheel(tester, 120);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(controller.position.pixels, closeTo(2120, 0.5));
    controller.dispose();
  });

  testWidgets('滚轮到底部边界时目标被钳制不越界', (tester) async {
    final controller = SmoothWheelScrollController();
    await tester.pumpWidget(_buildList(controller));

    for (var i = 0; i < 5; i++) {
      await _sendWheel(tester, 100000);
      await tester.pump(const Duration(milliseconds: 200));
    }
    await tester.pumpAndSettle();
    expect(
      controller.position.pixels,
      closeTo(controller.position.maxScrollExtent, 0.1),
    );
    controller.dispose();
  });
}
