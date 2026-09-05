import 'dart:typed_data';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/data/models/novelai_models.dart';
import 'package:novelai_harness/l10n/app_localizations.dart';
import 'package:novelai_harness/ui/features/studio/widgets/image_lightbox.dart';

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

    final ivFinder = find.byType(InteractiveViewer);
    expect(ivFinder, findsOneWidget);
    final iv = tester.widget<InteractiveViewer>(ivFinder);
    expect(iv.scaleEnabled, isFalse);

    // Initial scale is 1.0
    expect(
      iv.transformationController?.value.getMaxScaleOnAxis(),
      closeTo(1.0, 0.001),
    );

    // Double tap to zoom
    await tester.tap(ivFinder);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(ivFinder);
    await tester.pumpAndSettle();

    expect(
      iv.transformationController?.value.getMaxScaleOnAxis(),
      closeTo(2.0, 0.001),
    );

    // Double tap again to reset
    await tester.tap(ivFinder);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(ivFinder);
    await tester.pumpAndSettle();

    expect(
      iv.transformationController?.value.getMaxScaleOnAxis(),
      closeTo(1.0, 0.001),
    );
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

    final ivFinder = find.byType(InteractiveViewer);
    final iv = tester.widget<InteractiveViewer>(ivFinder);

    // Scroll up (zoom in) with mouse at non-center location (100, 100)
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(const Offset(100, 100)));
    await tester.sendEventToBinding(
      pointer.scroll(const Offset(0, -100), timeStamp: Duration.zero),
    );
    await tester.pump();

    final scaleAfterZoomIn =
        iv.transformationController?.value.getMaxScaleOnAxis() ?? 1.0;
    expect(scaleAfterZoomIn, greaterThan(1.0));

    // Viewport center is at (400, 300)
    // The transformation should keep (400, 300) invariant
    final matrix = iv.transformationController!.value;
    final tx = matrix.storage[12];
    final ty = matrix.storage[13];
    // Center point after transform should remain at (400, 300):
    final worldCenterX = (400 - tx) / scaleAfterZoomIn;
    final worldCenterY = (300 - ty) / scaleAfterZoomIn;
    expect(worldCenterX, closeTo(400.0, 0.1));
    expect(worldCenterY, closeTo(300.0, 0.1));
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
