import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/data/models/novelai_models.dart';
import 'package:novelai_harness/data/repositories/novelai_repository.dart';
import 'package:novelai_harness/ui/features/studio/view_models/studio_view_model.dart';
import 'package:novelai_harness/ui/features/studio/widgets/image_stream_view.dart';

final kTestPngBytes = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
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

  group('CanvasStreamController.scrollToItem Tests', () {
    testWidgets('centers a far off-screen history image (two-phase scroll)',
        (tester) async {
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
      final centerY =
          box.localToGlobal(Offset(0, box.size.height / 2)).dy;
      // 600px 视口的中心是 300；允许 8px 容差
      expect((centerY - 300).abs(), lessThan(8),
          reason: '目标图应垂直居中，而不是只露出顶部');
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
      final centerY =
          box.localToGlobal(Offset(0, box.size.height / 2)).dy;
      expect((centerY - 300).abs(), lessThan(8));
    });
  });
}
