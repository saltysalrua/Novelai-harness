import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/data/models/novelai_models.dart';
import 'package:novelai_harness/data/repositories/novelai_repository.dart';
import 'package:novelai_harness/ui/features/studio/view_models/studio_view_model.dart';
import 'package:novelai_harness/ui/features/studio/widgets/image_canvas_actions.dart';

final kTestPngBytes = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StudioViewModel.deleteImageFromHistory Tests', () {
    test('deletes image and selects adjacent image or null when empty', () async {
      final repo = NovelAiRepository();
      final vm = StudioViewModel(repository: repo);

      final img1 = NaiGeneratedImage(
        id: 'img-1',
        bytes: kTestPngBytes,
        params: const NaiGenerationParams(prompt: 'prompt 1', width: 832, height: 1216),
        seed: 101,
        isOpusFree: true,
        createdAt: DateTime.now(),
      );
      final img2 = NaiGeneratedImage(
        id: 'img-2',
        bytes: kTestPngBytes,
        params: const NaiGenerationParams(prompt: 'prompt 2', width: 832, height: 1216),
        seed: 102,
        isOpusFree: true,
        createdAt: DateTime.now(),
      );

      repo.addImageForTesting(img1);
      repo.addImageForTesting(img2);
      expect(vm.gallery.length, equals(2));

      // 默认选中第一张
      vm.selectImage(img2);
      expect(vm.selectedImage?.id, equals('img-2'));

      // 删除当前选中的图片
      await vm.deleteImageFromHistory('img-2');
      expect(vm.gallery.length, equals(1));
      expect(vm.selectedImage?.id, equals('img-1'));
      expect(vm.statusMessage, equals('已从历史记录删除图片'));

      // 删除最后一张图片
      await vm.deleteImageFromHistory('img-1');
      expect(vm.gallery.isEmpty, isTrue);
      expect(vm.selectedImage, isNull);
    });

    test('synchronizes board data image nodes when deleting', () async {
      final repo = NovelAiRepository();
      final vm = StudioViewModel(repository: repo);

      final mainImg = NaiGeneratedImage(
        id: 'main-img',
        bytes: kTestPngBytes,
        params: const NaiGenerationParams(prompt: 'main', width: 832, height: 1216),
        seed: 1,
        isOpusFree: true,
        createdAt: DateTime.now(),
      );
      final refImg = NaiGeneratedImage(
        id: 'ref-img',
        bytes: kTestPngBytes,
        params: const NaiGenerationParams(prompt: 'ref', width: 832, height: 1216),
        seed: 2,
        isOpusFree: true,
        createdAt: DateTime.now(),
      );

      repo.addImageForTesting(refImg);
      repo.addImageForTesting(mainImg);
      vm.selectImage(mainImg);

      // 进入批注模式初始化大画布
      vm.setAnnotatingImage(true);
      vm.addImageNodeToBoard(refImg);

      expect(vm.boardData.imageNodes.length, equals(2));

      // 删除参考图
      await vm.deleteImageFromHistory('ref-img');
      expect(vm.boardData.imageNodes.length, equals(1));
      expect(vm.boardData.imageNodes.first.image.id, equals('main-img'));
    });
  });

  group('showImageContextMenu UI Widget Tests', () {
    testWidgets('shows context menu with 从历史记录删除 and clicking it invokes deletion', (tester) async {
      final repo = NovelAiRepository();
      final vm = StudioViewModel(repository: repo);

      final testImage = NaiGeneratedImage(
        id: 'test-img',
        bytes: kTestPngBytes,
        params: const NaiGenerationParams(prompt: 'test prompt', width: 832, height: 1216),
        seed: 999,
        isOpusFree: true,
        createdAt: DateTime.now(),
      );

      repo.addImageForTesting(testImage);
      vm.selectImage(testImage);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showImageContextMenu(
                    context,
                    position: const Offset(100, 100),
                    viewModel: vm,
                    image: testImage,
                  );
                },
                child: const Text('Open Context Menu'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Context Menu'));
      await tester.pumpAndSettle();

      // 验证菜单项存在且包含从历史记录删除
      expect(find.text('查看大图'), findsOneWidget);
      expect(find.text('从历史记录删除'), findsOneWidget);

      // 点击从历史记录删除
      await tester.tap(find.text('从历史记录删除'));
      await tester.pumpAndSettle();

      // 菜单关闭，图片已删除
      expect(find.text('从历史记录删除'), findsNothing);
      expect(vm.gallery.isEmpty, isTrue);
      expect(vm.selectedImage, isNull);
      expect(find.text('已从历史记录删除图片'), findsOneWidget);
    });
  });
}
