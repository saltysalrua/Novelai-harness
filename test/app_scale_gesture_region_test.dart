import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/ui/core/widgets/app_scale_gesture_region.dart';

void main() {
  testWidgets('multitouch-only preserves child taps and ancestor scrolling', (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    var taps = 0;
    var scaleUpdates = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ListView(
          controller: scroll,
          children: [
            AppScaleGestureRegion(
              multitouchOnly: true,
              onScaleUpdate: (_) => scaleUpdates++,
              child: SizedBox(
                height: 400,
                child: TextButton(
                  onPressed: () => taps++,
                  child: const Text('tap'),
                ),
              ),
            ),
            const SizedBox(height: 1500),
          ],
        ),
      ),
    );
    await tester.tap(find.text('tap'));
    await tester.pumpAndSettle();
    expect(taps, 1);
    await tester.dragFrom(const Offset(200, 300), const Offset(0, -120));
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(0));
    expect(scaleUpdates, 0);
  });

  testWidgets('two stationary touches never trigger tap or double tap', (
    tester,
  ) async {
    var taps = 0;
    var doubleTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AppScaleGestureRegion(
          onTap: () => taps++,
          onDoubleTap: () => doubleTaps++,
          child: const SizedBox.expand(),
        ),
      ),
    );
    final first = await tester.startGesture(const Offset(200, 250));
    final second = await tester.startGesture(const Offset(220, 250));
    await first.up();
    await second.up();
    await tester.pumpAndSettle();
    expect(taps, 0);
    expect(doubleTaps, 0);
    await tester.tapAt(const Offset(200, 250));
    await tester.pump(const Duration(milliseconds: 400));
    expect(taps, 1);
  });

  testWidgets('multitouch cancels pending child drag and stops on cancel', (
    tester,
  ) async {
    var childDrags = 0;
    final scales = <double>[];
    await tester.pumpWidget(
      MaterialApp(
        home: AppScaleGestureRegion(
          multitouchOnly: true,
          onScaleUpdate: (details) => scales.add(details.scale),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (_) => childDrags++,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    final first = await tester.startGesture(const Offset(200, 250));
    await first.moveBy(const Offset(2, 0));
    final second = await tester.startGesture(const Offset(400, 250));
    await first.moveBy(const Offset(-4, 0));
    await second.moveBy(const Offset(4, 0));
    await tester.pump();
    expect(scales.last, greaterThan(1));
    expect(childDrags, 0);
    final updateCount = scales.length;
    await second.cancel();
    await first.moveBy(const Offset(80, 0));
    await first.up();
    await tester.pumpAndSettle();
    expect(scales, hasLength(updateCount));
    expect(childDrags, 0);

    // 取消后识别器可复用；新的单指仍交回子节点。
    final drag = await tester.startGesture(const Offset(200, 250));
    await drag.moveBy(const Offset(60, 0));
    await drag.moveBy(const Offset(40, 0));
    await drag.up();
    await tester.pumpAndSettle();
    expect(childDrags, greaterThan(0));
  });

  testWidgets('native trackpad is accepted in multitouch-only mode', (
    tester,
  ) async {
    final scales = <double>[];
    await tester.pumpWidget(
      MaterialApp(
        home: AppScaleGestureRegion(
          multitouchOnly: true,
          onScaleUpdate: (details) => scales.add(details.scale),
          child: const SizedBox.expand(),
        ),
      ),
    );
    const start = Offset(300, 250);
    final trackpad = TestPointer(5, PointerDeviceKind.trackpad);
    await tester.sendEventToBinding(trackpad.panZoomStart(start));
    await tester.sendEventToBinding(trackpad.panZoomUpdate(start, scale: 1.2));
    await tester.sendEventToBinding(trackpad.panZoomUpdate(start, scale: 1.4));
    await tester.sendEventToBinding(trackpad.panZoomEnd());
    await tester.pumpAndSettle();
    expect(scales.last, greaterThan(1));
    expect(tester.takeException(), isNull);
  });
}
