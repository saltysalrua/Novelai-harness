import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/data/models/novelai_models.dart';
import 'package:novelai_harness/data/repositories/novelai_repository.dart';
import 'package:novelai_harness/l10n/app_localizations.dart';
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

NaiGeneratedImage _image(String id, {String prompt = 'p'}) => NaiGeneratedImage(
  id: id,
  bytes: kTestPngBytes,
  params: NaiGenerationParams(prompt: prompt, width: 832, height: 1216),
  seed: 1,
  isOpusFree: true,
  createdAt: DateTime.now(),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StudioViewModel.clearImageHistory Tests', () {
    test('clears gallery, resets selection and syncs board nodes', () async {
      final repo = NovelAiRepository();
      final vm = StudioViewModel(repository: repo);

      final mainImg = _image('hist-1');
      final histImg2 = _image('hist-2');
      final externalRef = _image('ref-ext');

      repo.addImageForTesting(histImg2);
      repo.addImageForTesting(mainImg);
      vm.selectImage(mainImg);

      // 进入批注模式并放置一张不属于历史的外部参考卡片
      vm.setAnnotatingImage(true);
      vm.addImageNodeToBoard(externalRef);
      expect(vm.boardData.imageNodes.length, equals(2));

      await vm.clearImageHistory();

      expect(vm.gallery.isEmpty, isTrue);
      expect(vm.selectedImage, isNull);
      expect(vm.hasUnseenLatest, isFalse);
      expect(vm.statusMessage, equals('已清空历史记录'));

      // 大画布仅保留外部参考卡片，历史图节点 (含主图) 全部移除
      expect(vm.boardData.imageNodes.length, equals(1));
      expect(vm.boardData.imageNodes.first.image.id, equals('ref-ext'));
      expect(vm.boardData.imageNodes.first.isMain, isFalse);
    });

    test('is a no-op when history is already empty', () async {
      final repo = NovelAiRepository();
      final vm = StudioViewModel(repository: repo);

      await vm.clearImageHistory();
      expect(vm.gallery.isEmpty, isTrue);
      expect(vm.statusMessage, isNull);
    });
  });

  group('clear history context menu Tests', () {
    testWidgets('clears all history after confirmation and cancels safely',
        (tester) async {
      final repo = NovelAiRepository();
      final vm = StudioViewModel(repository: repo);

      final testImage = _image('test-img');
      repo.addImageForTesting(_image('other-img'));
      repo.addImageForTesting(testImage);
      vm.selectImage(testImage);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
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

      expect(find.text('清空历史记录'), findsOneWidget);

      // 点开清空项 -> 弹出确认框
      await tester.tap(find.text('清空历史记录'));
      await tester.pumpAndSettle();
      expect(find.text('取消'), findsOneWidget);
      expect(find.text('清空'), findsOneWidget);

      // 取消：历史保持不变
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(vm.gallery.length, equals(2));

      // 再次打开菜单并确认清空
      await tester.tap(find.text('Open Context Menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('清空历史记录'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('清空'));
      await tester.pumpAndSettle();

      expect(vm.gallery.isEmpty, isTrue);
      expect(vm.selectedImage, isNull);
      expect(find.text('已清空历史记录'), findsOneWidget);
    });
  });

  group('importReferenceImageFromBytes Tests', () {
    test('imported image lands as reference card, never as main image',
        () async {
      final repo = NovelAiRepository();
      final vm = StudioViewModel(repository: repo);

      final current = _image('current-main');
      repo.addImageForTesting(current);
      vm.selectImage(current);

      final imported = await vm.importReferenceImageFromBytes(
        kTestPngBytes,
        fileName: 'external.png',
      );

      expect(imported, isNotNull);
      expect(vm.isAnnotatingImage, isTrue);

      // 选中图不被劫持：仍是原来的当前图
      expect(vm.selectedImage?.id, equals('current-main'));

      // 主图位仍是当前生成图，导入图只是参考卡片
      final mainNode = vm.boardData.imageNodes
          .where((n) => n.isMain)
          .firstOrNull;
      expect(mainNode?.image.id, equals('current-main'));
      final refNode = vm.boardData.imageNodes
          .where((n) => n.image.id == imported!.id)
          .firstOrNull;
      expect(refNode, isNotNull);
      expect(refNode!.isMain, isFalse);

      // 导入图不进入生图历史
      expect(vm.gallery.length, equals(1));
    });

    test('import with empty gallery creates board with only the reference card',
        () async {
      final repo = NovelAiRepository();
      final vm = StudioViewModel(repository: repo);

      final imported = await vm.importReferenceImageFromBytes(
        kTestPngBytes,
        fileName: 'external.png',
      );

      expect(imported, isNotNull);
      expect(vm.isAnnotatingImage, isTrue);
      expect(vm.selectedImage, isNull);
      expect(vm.boardData.imageNodes.length, equals(1));
      expect(vm.boardData.imageNodes.first.image.id, equals(imported!.id));
      expect(vm.boardData.imageNodes.first.isMain, isFalse);
    });
  });
}
