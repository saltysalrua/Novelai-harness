import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/data/models/novelai_models.dart';
import 'package:novelai_harness/l10n/app_localizations.dart';
import 'package:novelai_harness/ui/core/theme/ui_zoom_controller.dart';
import 'package:novelai_harness/ui/features/studio/widgets/image_lightbox.dart';

Matrix4 _lightboxTransform(WidgetTester tester) => tester
    .widget<Transform>(
      find.descendant(
        of: find.byType(ImageLightboxDialog),
        matching: find.byType(Transform),
      ),
    )
    .transform
    .clone();

Future<void> _scroll(
  WidgetTester tester,
  double delta, {
  PointerDeviceKind kind = PointerDeviceKind.mouse,
  Offset position = const Offset(100, 100),
}) => tester.sendEventToBinding(
  PointerScrollEvent(
    kind: kind,
    position: position,
    scrollDelta: Offset(0, delta),
  ),
);

void _expectPoint(Offset actual, Offset expected) {
  expect(actual.dx, closeTo(expected.dx, 0.001));
  expect(actual.dy, closeTo(expected.dy, 0.001));
}

void _expectMatrix(Matrix4 actual, Matrix4 expected) {
  for (var index = 0; index < 16; index++) {
    expect(actual.storage[index], closeTo(expected.storage[index], 0.001));
  }
}

void main() {
  // A tiny 1x1 transparent PNG
  final sampleBytes = Uint8List.fromList([
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    0x00,
    0x00,
    0x00,
    0x0D,
    0x49,
    0x48,
    0x44,
    0x52,
    0x00,
    0x00,
    0x00,
    0x01,
    0x00,
    0x00,
    0x00,
    0x01,
    0x08,
    0x06,
    0x00,
    0x00,
    0x00,
    0x1F,
    0x15,
    0xC4,
    0x89,
    0x00,
    0x00,
    0x00,
    0x0A,
    0x49,
    0x44,
    0x41,
    0x54,
    0x78,
    0x9C,
    0x63,
    0x00,
    0x01,
    0x00,
    0x00,
    0x05,
    0x00,
    0x01,
    0x0D,
    0x0A,
    0x2D,
    0xB4,
    0x00,
    0x00,
    0x00,
    0x00,
    0x49,
    0x45,
    0x4E,
    0x44,
    0xAE,
    0x42,
    0x60,
    0x82,
  ]);

  final testImage = NaiGeneratedImage(
    id: 'test_1',
    bytes: sampleBytes,
    params: const NaiGenerationParams(
      prompt: 'masterpiece, 1girl',
      width: 1024,
      height: 1024,
    ),
    seed: 123456789,
    createdAt: DateTime.now(),
    isOpusFree: true,
  );

  testWidgets(
    'ImageLightboxDialog renders without old info banner text and has close button',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showImageLightbox(context, testImage),
                child: const Text('Open Lightbox'),
              ),
            ),
          ),
        ),
      );

      // Open lightbox
      await tester.tap(find.text('Open Lightbox'));
      await tester.pumpAndSettle();

      // Verify old info banner text is NOT present
      expect(find.textContaining('可使用滚轮自由缩放与拖拽平移'), findsNothing);
      expect(find.textContaining('种子: 123456789'), findsNothing);

      // Verify close button is present
      final closeBtn = find.byTooltip('关闭大图展示');
      expect(closeBtn, findsOneWidget);

      // Tap close button and verify lightbox is dismissed
      await tester.tap(closeBtn);
      await tester.pumpAndSettle();

      expect(find.byType(ImageLightboxDialog), findsNothing);
    },
  );

  testWidgets('ImageLightboxDialog double tap zooms to 2x and resets to 1x', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ImageLightboxDialog(bytes: testImage.uint8Bytes)),
      ),
    );
    await tester.pumpAndSettle();

    final viewport = find.byType(ImageLightboxDialog);

    // Initial scale is 1.0
    expect(_lightboxTransform(tester).entry(0, 0), closeTo(1.0, 0.001));

    // Double tap to zoom
    await tester.tap(viewport);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(viewport);
    await tester.pumpAndSettle();

    expect(_lightboxTransform(tester).entry(0, 0), closeTo(2.0, 0.001));

    // Double tap again to reset
    await tester.tap(viewport);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(viewport);
    await tester.pumpAndSettle();

    expect(_lightboxTransform(tester).entry(0, 0), closeTo(1.0, 0.001));
  });

  testWidgets('PointerScrollEvent zooms centered on viewport', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ImageLightboxDialog(bytes: testImage.uint8Bytes)),
      ),
    );
    await tester.pumpAndSettle();

    // Scroll up (zoom in) with mouse at non-center location (100, 100)
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(const Offset(100, 100)));
    await tester.sendEventToBinding(
      pointer.scroll(const Offset(0, -100), timeStamp: Duration.zero),
    );
    await tester.pumpAndSettle();

    final matrix = _lightboxTransform(tester);
    final scaleAfterZoomIn = matrix.entry(0, 0);
    expect(scaleAfterZoomIn, greaterThan(1.0));

    // Viewport center is at (400, 300)
    // The transformation should keep (400, 300) invariant
    final tx = matrix.storage[12];
    final ty = matrix.storage[13];
    // Center point after transform should remain at (400, 300):
    final worldCenterX = (400 - tx) / scaleAfterZoomIn;
    final worldCenterY = (300 - ty) / scaleAfterZoomIn;
    expect(worldCenterX, closeTo(400.0, 0.1));
    expect(worldCenterY, closeTo(300.0, 0.1));
  });

  testWidgets('repeated zoom out continues below the fitted image size', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ImageLightboxDialog()));
    await tester.pumpAndSettle();
    await _scroll(tester, 100);
    await tester.pumpAndSettle();
    final firstScale = _lightboxTransform(tester).entry(0, 0);
    expect(firstScale, lessThan(1));

    await _scroll(tester, 100);
    await tester.pumpAndSettle();
    expect(_lightboxTransform(tester).entry(0, 0), lessThan(firstScale));
  });

  testWidgets('double tap keeps the viewport center fixed', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ImageLightboxDialog()));
    await tester.pumpAndSettle();
    final center = tester.getCenter(find.byType(ImageLightboxDialog));

    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(center);
    await tester.pumpAndSettle();

    final matrix = _lightboxTransform(tester);
    expect(matrix.getMaxScaleOnAxis(), closeTo(2, 0.001));
    _expectPoint(MatrixUtils.transformPoint(matrix, center), center);
  });

  testWidgets('trackpad scroll only zooms without an extra pan', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ImageLightboxDialog()));
    await tester.pumpAndSettle();
    final center = tester.getCenter(find.byType(ImageLightboxDialog));

    await _scroll(tester, -100, kind: PointerDeviceKind.trackpad);
    await tester.pumpAndSettle();

    final matrix = _lightboxTransform(tester);
    expect(matrix.getMaxScaleOnAxis(), greaterThan(1));
    _expectPoint(MatrixUtils.transformPoint(matrix, center), center);
  });

  testWidgets('wheel zoom after a fling has no stale pan animation', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ImageLightboxDialog()));
    await tester.pumpAndSettle();
    final center = tester.getCenter(find.byType(ImageLightboxDialog));

    await tester.flingFrom(const Offset(200, 200), const Offset(120, 70), 1600);
    await tester.pump();
    final anchor = MatrixUtils.transformPoint(
      Matrix4.inverted(_lightboxTransform(tester)),
      center,
    );
    await _scroll(tester, -100);
    for (var frame = 0; frame < 12; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      _expectPoint(
        MatrixUtils.transformPoint(_lightboxTransform(tester), anchor),
        center,
      );
    }
    await tester.pumpAndSettle();
  });

  testWidgets('wheel animation is continuous and accumulates rapid input', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ImageLightboxDialog()));
    await tester.pumpAndSettle();
    final center = tester.getCenter(find.byType(ImageLightboxDialog));
    for (var tick = 0; tick < 3; tick++) {
      final before = _lightboxTransform(tester);
      await _scroll(tester, -30);
      await tester.pump();
      // 改目标不能先跳到上一轮动画的终点。
      _expectMatrix(_lightboxTransform(tester), before);
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        _lightboxTransform(tester).entry(0, 0),
        greaterThan(before.entry(0, 0)),
      );
    }
    var previous = _lightboxTransform(tester).entry(0, 0);
    for (var frame = 0; frame < 10; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      final matrix = _lightboxTransform(tester);
      expect(matrix.entry(0, 0), greaterThanOrEqualTo(previous));
      _expectPoint(MatrixUtils.transformPoint(matrix, center), center);
      previous = matrix.entry(0, 0);
    }
    expect(previous, closeTo(math.exp(0.3), 0.001));

    await _scroll(tester, 90);
    await tester.pumpAndSettle();
    _expectMatrix(_lightboxTransform(tester), Matrix4.identity());
  });

  testWidgets('reversing the wheel immediately reverses the animation', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ImageLightboxDialog()));
    await tester.pumpAndSettle();
    await _scroll(tester, -180);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    final before = _lightboxTransform(tester).entry(0, 0);
    expect(before, greaterThan(1));
    await _scroll(tester, 30);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(_lightboxTransform(tester).entry(0, 0), lessThan(before));
    await tester.pumpAndSettle();
  });

  testWidgets('zoom limits preserve the anchor and allow immediate reversal', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ImageLightboxDialog()));
    await tester.pumpAndSettle();
    final center = tester.getCenter(find.byType(ImageLightboxDialog));
    for (final (delta, limit) in [(600.0, 0.2), (-600.0, 10.0)]) {
      for (var tick = 0; tick < 12; tick++) {
        await _scroll(tester, delta);
        await tester.pumpAndSettle();
        final matrix = _lightboxTransform(tester);
        expect(matrix.storage.every((value) => value.isFinite), isTrue);
        expect(matrix.entry(0, 0), inInclusiveRange(0.2, 10));
        _expectPoint(MatrixUtils.transformPoint(matrix, center), center);
      }
      expect(_lightboxTransform(tester).entry(0, 0), closeTo(limit, 0.001));
    }
    await _scroll(tester, 30);
    await tester.pumpAndSettle();
    expect(_lightboxTransform(tester).entry(0, 0), lessThan(10));
  });

  testWidgets('new drag cancels zoom and remains draggable below 1x', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ImageLightboxDialog()));
    await tester.pumpAndSettle();
    await _scroll(tester, 180);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    final before = _lightboxTransform(tester);
    expect(before.entry(0, 0), lessThan(1));

    // 缩小后仍可从图片外的空白处拖拽，按下就停止未完成的动画。
    final drag = await tester.startGesture(const Offset(60, 80));
    await tester.pump(const Duration(milliseconds: 200));
    _expectMatrix(_lightboxTransform(tester), before);
    await drag.moveBy(const Offset(40, 20));
    await tester.pump();
    final started = _lightboxTransform(tester);
    await drag.moveBy(const Offset(20, 10));
    await tester.pump();
    final moved = _lightboxTransform(tester);
    expect(moved.entry(0, 0), closeTo(before.entry(0, 0), 0.001));
    _expectPoint(
      Offset(
        moved.entry(0, 3) - started.entry(0, 3),
        moved.entry(1, 3) - started.entry(1, 3),
      ),
      const Offset(20, 10),
    );
    await drag.cancel();
    await tester.pumpAndSettle();
    _expectMatrix(_lightboxTransform(tester), moved);
  });

  testWidgets('touch pinch preserves its focal point through finger changes', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ImageLightboxDialog()));
    await tester.pumpAndSettle();
    final first = await tester.startGesture(const Offset(200, 250), pointer: 1);
    final second = await tester.startGesture(
      const Offset(400, 250),
      pointer: 2,
    );
    await first.moveBy(const Offset(-40, 0));
    await second.moveBy(const Offset(40, 0));
    await tester.pump();
    const focalPoint = Offset(300, 250);
    final before = _lightboxTransform(tester);
    final anchor = MatrixUtils.transformPoint(
      Matrix4.inverted(before),
      focalPoint,
    );
    await first.moveBy(const Offset(-30, 0));
    await second.moveBy(const Offset(30, 0));
    await tester.pump();
    final pinched = _lightboxTransform(tester);
    expect(pinched.entry(0, 0), greaterThan(before.entry(0, 0)));
    _expectPoint(MatrixUtils.transformPoint(pinched, anchor), focalPoint);

    await second.up();
    await tester.pump();
    _expectMatrix(_lightboxTransform(tester), pinched);
    await first.moveBy(const Offset(20, 10));
    await tester.pump();
    final rebased = _lightboxTransform(tester);
    await first.moveBy(const Offset(10, 5));
    await tester.pump();
    final panned = _lightboxTransform(tester);
    expect(panned.entry(0, 0), closeTo(pinched.entry(0, 0), 0.001));
    _expectPoint(
      Offset(
        panned.entry(0, 3) - rebased.entry(0, 3),
        panned.entry(1, 3) - rebased.entry(1, 3),
      ),
      const Offset(10, 5),
    );
    await first.up();
    await tester.pumpAndSettle();
    _expectMatrix(_lightboxTransform(tester), panned);
  });

  testWidgets('short touch pinch works in a phone lightbox route', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => GestureDetector(
            onDoubleTap: () => showImageLightbox(context, testImage),
            child: const ColoredBox(color: Colors.white),
          ),
        ),
      ),
    );
    await tester.tapAt(const Offset(195, 400));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(const Offset(195, 400));
    await tester.pumpAndSettle();
    expect(find.byType(ImageLightboxDialog), findsOneWidget);

    const focal = Offset(195, 400);
    final first = await tester.startGesture(focal - const Offset(70, 0));
    final second = await tester.startGesture(focal + const Offset(70, 0));
    // 手机短距离捏合：不能把整段有效双指动作都吞作单指起拖阈值。
    for (var frame = 0; frame < 10; frame++) {
      await first.moveBy(const Offset(-1, 0));
      await second.moveBy(const Offset(1, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    final enlarged = _lightboxTransform(tester);
    expect(enlarged.entry(0, 0), closeTo(160 / 140, 0.001));
    _expectPoint(MatrixUtils.transformPoint(enlarged, focal), focal);
    // 同一次手势能立即反向缩小，不需要重新跨越阈值。
    await first.moveBy(const Offset(10, 0));
    await second.moveBy(const Offset(-10, 0));
    await tester.pump();
    _expectMatrix(_lightboxTransform(tester), Matrix4.identity());
    await first.up();
    await second.up();
    await tester.pumpAndSettle();
    expect(find.byType(ImageLightboxDialog), findsOneWidget);
  });

  testWidgets('native trackpad pan zoom preserves the moving focal point', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ImageLightboxDialog()));
    await tester.pumpAndSettle();
    const start = Offset(300, 250);
    final trackpad = TestPointer(4, PointerDeviceKind.trackpad);
    await tester.sendEventToBinding(trackpad.panZoomStart(start));
    await tester.sendEventToBinding(
      trackpad.panZoomUpdate(start, pan: const Offset(30, 10), scale: 1.2),
    );
    await tester.pump();
    final before = _lightboxTransform(tester);
    final anchor = MatrixUtils.transformPoint(
      Matrix4.inverted(before),
      start + const Offset(30, 10),
    );
    await tester.sendEventToBinding(
      trackpad.panZoomUpdate(start, pan: const Offset(40, 20), scale: 1.4),
    );
    await tester.pump();
    final after = _lightboxTransform(tester);
    expect(after.entry(0, 0), greaterThan(before.entry(0, 0)));
    _expectPoint(
      MatrixUtils.transformPoint(after, anchor),
      start + const Offset(40, 20),
    );
    await tester.sendEventToBinding(trackpad.panZoomEnd());
    await tester.pumpAndSettle();
    _expectMatrix(_lightboxTransform(tester), after);
  });

  testWidgets('OS scale signal uses local coordinates under application zoom', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => AppUiZoomScope(zoom: 1.25, child: child!),
        home: const ImageLightboxDialog(),
      ),
    );
    await tester.pumpAndSettle();
    await _scroll(tester, 100);
    await tester.pumpAndSettle();
    final before = _lightboxTransform(tester);
    // 应用 125% 缩放后，窗口坐标 (250, 200) 对应局部 (200, 160)。
    const localAnchor = Offset(200, 160);
    final scenePoint = MatrixUtils.transformPoint(
      Matrix4.inverted(before),
      localAnchor,
    );
    await tester.sendEventToBinding(
      const PointerScaleEvent(position: Offset(250, 200), scale: 1.2),
    );
    await tester.pumpAndSettle();
    final after = _lightboxTransform(tester);
    expect(after.entry(0, 0), closeTo(before.entry(0, 0) * 1.2, 0.001));
    _expectPoint(MatrixUtils.transformPoint(after, scenePoint), localAnchor);
  });

  testWidgets('double tap resets a shrunk and panned image to fit', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ImageLightboxDialog()));
    await tester.pumpAndSettle();
    await _scroll(tester, 200);
    await tester.pumpAndSettle();
    await tester.dragFrom(const Offset(100, 100), const Offset(80, 50));
    await tester.pumpAndSettle();
    final viewport = find.byType(ImageLightboxDialog);
    await tester.tap(viewport);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(viewport);
    await tester.pumpAndSettle();
    _expectMatrix(_lightboxTransform(tester), Matrix4.identity());
  });

  testWidgets('image loading preserves zoom and closing cancels animation', (
    tester,
  ) async {
    final loaded = Completer<Uint8List?>();
    await tester.pumpWidget(
      MaterialApp(home: ImageLightboxDialog(loader: () => loaded.future)),
    );
    await tester.pump();
    await _scroll(tester, -100);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));
    final before = _lightboxTransform(tester);
    loaded.complete(sampleBytes);
    await tester.pumpAndSettle();
    _expectMatrix(_lightboxTransform(tester), before);
    final image = tester.widget<Image>(find.byType(Image));
    await _scroll(tester, -100);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(identical(tester.widget<Image>(find.byType(Image)), image), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'ImageLightboxDialog renders localized close tooltip in en and zh',
    (tester) async {
      // English
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ImageLightboxDialog(bytes: testImage.uint8Bytes),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Close full size view'), findsOneWidget);

      // Chinese
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ImageLightboxDialog(bytes: testImage.uint8Bytes),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('关闭大图展示'), findsOneWidget);
    },
  );
}
