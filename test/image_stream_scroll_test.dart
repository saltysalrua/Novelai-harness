import 'dart:typed_data';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/data/models/novelai_models.dart';
import 'package:novelai_harness/data/repositories/novelai_repository.dart';
import 'package:novelai_harness/l10n/app_localizations.dart';
import 'package:novelai_harness/ui/core/widgets/two_finger_scale.dart';
import 'package:novelai_harness/ui/features/studio/view_models/studio_view_model.dart';
import 'package:novelai_harness/ui/features/studio/widgets/image_stream_view.dart';

final kTestPngBytes = Uint8List.fromList([
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

NaiGeneratedImage _image(String id) => NaiGeneratedImage(
  id: id,
  bytes: kTestPngBytes,
  params: const NaiGenerationParams(prompt: 'p', width: 832, height: 1216),
  seed: 1,
  isOpusFree: true,
  createdAt: DateTime.now(),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('连续画板滚轮滑行期间不通知全局，停止后才同步选中图', (tester) async {
    final repo = NovelAiRepository();
    final vm = StudioViewModel(repository: repo);
    final controller = CanvasStreamController();
    addTearDown(vm.dispose);
    addTearDown(controller.dispose);
    for (var i = 0; i < 12; i++) {
      repo.addImageForTesting(_image('scroll-$i'));
    }
    vm.selectImage(vm.gallery.first);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: vm,
            builder: (_, _) =>
                ImageStreamView(viewModel: vm, controller: controller),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final firstId = vm.selectedImage!.id;
    var notifications = 0;
    vm.addListener(() => notifications++);
    final list = find.byType(ListView);
    for (var i = 0; i < 4; i++) {
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(list),
          scrollDelta: const Offset(0, 400),
          kind: PointerDeviceKind.mouse,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 32));
      expect(notifications, 0);
      expect(vm.selectedImage!.id, firstId);
    }
    expect(controller.scrollController.offset, greaterThan(600));
    await tester.pumpAndSettle();
    expect(vm.selectedImage!.id, isNot(firstId));
    expect(notifications, 1);
    expect(tester.takeException(), isNull);
  });

  for (final kind in ['mounted', 'lazy', 'silent']) {
    testWidgets('history $kind anchoring never scrolls the outer mobile page', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(430, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = NovelAiRepository();
      final vm = StudioViewModel(repository: repo);
      final controller = CanvasStreamController();
      final pages = PageController(initialPage: 1);
      addTearDown(vm.dispose);
      addTearDown(controller.dispose);
      addTearDown(pages.dispose);
      for (var i = 0; i < 12; i++) {
        repo.addImageForTesting(_image('mobile-$i'));
      }
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PageView(
              controller: pages,
              children: [
                const ColoredBox(color: Colors.red),
                Row(
                  children: [
                    Expanded(
                      child: ImageStreamView(
                        viewModel: vm,
                        controller: controller,
                      ),
                    ),
                    const SizedBox(width: 120),
                  ],
                ),
                const SizedBox.shrink(),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final index = kind == 'lazy' ? vm.gallery.length - 1 : 1;
      final target = vm.gallery[index];
      expect(
        controller.keyFor(target.id).currentContext,
        kind == 'lazy' ? isNull : isNotNull,
      );
      if (kind == 'silent') {
        controller.anchorToItemSilently(target.id);
      } else {
        controller.scrollToItem(index, target.id);
      }
      // 不只检查动画结束：原 bug 正是在中间帧把参数卡拉入后又缩回。
      for (var frame = 0; frame < 60; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(pages.page, closeTo(1, 0.0001), reason: '$kind frame=$frame');
      }
      expect(controller.scrollController.offset, greaterThan(0));
      expect(controller.isAdjustingAnchor, isFalse);
      final box =
          controller.keyFor(target.id).currentContext!.findRenderObject()
              as RenderBox;
      expect(
        box.localToGlobal(Offset(0, box.size.height / 2)).dy,
        closeTo(350, 8),
      );
      expect(tester.takeException(), isNull);
    });
  }

  group('CanvasStreamController.scrollToItem Tests', () {
    testWidgets('centers a far off-screen history image (two-phase scroll)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repo = NovelAiRepository();
      final vm = StudioViewModel(repository: repo);
      for (var i = 0; i < 6; i++) {
        repo.addImageForTesting(_image('img-$i'));
      }
      vm.selectImage(vm.gallery.first);

      final controller = CanvasStreamController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: ImageStreamView(viewModel: vm, controller: controller),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 目标图远在懒加载缓存之外 (尚未构建)，触发估算+二次居中路径
      final target = vm.gallery.last;
      final targetIndex = vm.gallery.indexWhere((g) => g.id == target.id);
      controller.scrollToItem(targetIndex, target.id);
      await tester.pumpAndSettle();

      final ctx = controller.keyFor(target.id).currentContext;
      expect(ctx, isNotNull, reason: '目标卡片应已完成挂载');
      final box = ctx!.findRenderObject() as RenderBox;
      final centerY = box.localToGlobal(Offset(0, box.size.height / 2)).dy;
      // 600px 视口的中心是 300；允许 8px 容差
      expect((centerY - 300).abs(), lessThan(8), reason: '目标图应垂直居中，而不是只露出顶部');
    });

    testWidgets('centers an already-built history image', (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repo = NovelAiRepository();
      final vm = StudioViewModel(repository: repo);
      for (var i = 0; i < 6; i++) {
        repo.addImageForTesting(_image('img-$i'));
      }
      vm.selectImage(vm.gallery.first);

      final controller = CanvasStreamController();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: ImageStreamView(viewModel: vm, controller: controller),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 紧邻视口内 (已构建) 的图：单次 ensureVisible 即居中
      final target = vm.gallery[1];
      final targetIndex = vm.gallery.indexWhere((g) => g.id == target.id);
      controller.scrollToItem(targetIndex, target.id);
      await tester.pumpAndSettle();

      final ctx = controller.keyFor(target.id).currentContext;
      expect(ctx, isNotNull);
      final box = ctx!.findRenderObject() as RenderBox;
      final centerY = box.localToGlobal(Offset(0, box.size.height / 2)).dy;
      expect((centerY - 300).abs(), lessThan(8));
    });
  });

  group('画板卡片双指捏合缩放 (触摸)', () {
    testWidgets('双指捏合卡内缩放，单指滚动不劫持', (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repo = NovelAiRepository();
      final vm = StudioViewModel(repository: repo);
      final controller = CanvasStreamController();
      addTearDown(vm.dispose);
      addTearDown(controller.dispose);
      for (var i = 0; i < 4; i++) {
        repo.addImageForTesting(_image('pinch-$i'));
      }
      vm.selectImage(vm.gallery.first);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: vm,
              builder: (_, _) =>
                  ImageStreamView(viewModel: vm, controller: controller),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final zoomable = find.byType(TwoFingerPinchZoom);
      expect(zoomable, findsWidgets);
      final cardCenter = tester.getCenter(zoomable.first);

      Matrix4 transformOf() => tester
          .widget<Transform>(
            find
                .descendant(of: zoomable.first, matching: find.byType(Transform))
                .first,
          )
          .transform;

      // 双指对拉捏合放大卡内内容
      final g1 = await tester.startGesture(cardCenter + const Offset(-50, 0));
      final g2 = await tester.startGesture(cardCenter + const Offset(50, 0));
      await g1.moveBy(const Offset(-60, 0));
      await g2.moveBy(const Offset(60, 0));
      await tester.pump();

      final zoomed = transformOf();
      expect(zoomed.storage[0], greaterThan(1.2), reason: '双指捏合应放大卡片内容');

      await g1.up();
      await g2.up();
      await tester.pumpAndSettle();

      // 单指纵向拖拽仍然是列表滚动，卡片缩放状态不被干扰；分步小位移
      // 保证拖拽识别器接受竞技场后仍有移动事件计入滚动
      final offsetBefore = controller.scrollController.offset;
      final single = await tester.startGesture(cardCenter);
      for (var i = 0; i < 10; i++) {
        await single.moveBy(const Offset(0, -10));
      }
      await tester.pump();
      await single.up();
      await tester.pumpAndSettle();
      expect(
        controller.scrollController.offset,
        greaterThan(offsetBefore),
        reason: '单指拖拽应继续滚动画板列表',
      );
      expect(transformOf().storage[0], greaterThan(1.0), reason: '卡片保持捏合后的缩放状态');
      expect(tester.takeException(), isNull);
    });
  });
}
