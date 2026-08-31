import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/data/models/novelai_models.dart';
import 'package:novelai_harness/data/repositories/novelai_repository.dart';
import 'package:novelai_harness/ui/features/studio/view_models/studio_view_model.dart';
import 'package:novelai_harness/ui/features/studio/widgets/annotation_history_strip.dart';
import 'package:novelai_harness/ui/features/studio/widgets/freeform_annotation_board.dart';

/// 1x1 纯净有效 PNG 字节数组
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

  group('FreeformAnnotationBoard UI Widget Tests', () {
    testWidgets('renders toolbar, main image card, sticky notes and actions',
        (tester) async {
      final repo = NovelAiRepository();
      final vm = StudioViewModel(repository: repo);

      final initialAnn = ImageAnnotation.rect(
        id: 'ann-1',
        normalizedRect: const Rect.fromLTWH(0.2, 0.2, 0.4, 0.4),
        note: '眼睛高光调整',
        colorIndex: 0,
      );

      final testImage = NaiGeneratedImage(
        id: 'img-board-1',
        bytes: kTestPngBytes,
        params: const NaiGenerationParams(
          prompt: 'masterpiece',
          width: 832,
          height: 1216,
        ),
        seed: 777,
        isOpusFree: true,
        createdAt: DateTime.now(),
        annotations: [initialAnn],
      );

      repo.addImageForTesting(testImage);
      vm.selectImage(testImage);
      vm.setAnnotatingImage(true);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: vm,
              builder: (context, _) => SizedBox(
                width: 1000,
                height: 800,
                child: FreeformAnnotationBoard(
                  viewModel: vm,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      // 验证顶部工具栏按键
      expect(find.text('漫游'), findsOneWidget);
      expect(find.text('圈选选区'), findsOneWidget);
      expect(find.text('图钉锚点'), findsOneWidget);
      expect(find.text('+ 便利贴'), findsOneWidget);
      expect(find.text('适应视口'), findsOneWidget);

      // 验证主图卡片标识
      expect(find.text('主图 (当前生成图)'), findsOneWidget);

      // 验证底部操作按钮
      expect(find.text('退出批注'), findsOneWidget);
      expect(find.text('发送全部批注到 AI'), findsOneWidget);

      // 点击 '+ 便利贴' 添加一张新便利贴
      await tester.tap(find.text('+ 便利贴'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      expect(vm.boardData.noteNodes.length, 2);
    });
  });

  group('AnnotationHistoryStrip UI Widget Tests', () {
    testWidgets('renders history list with count and thumbnails',
        (tester) async {
      final repo = NovelAiRepository();
      final vm = StudioViewModel(repository: repo);

      final testImage1 = NaiGeneratedImage(
        id: 'img-strip-1',
        bytes: kTestPngBytes,
        params: const NaiGenerationParams(prompt: '1girl'),
        seed: 111,
        isOpusFree: true,
        createdAt: DateTime.now(),
      );

      final testImage2 = NaiGeneratedImage(
        id: 'img-strip-2',
        bytes: kTestPngBytes,
        params: const NaiGenerationParams(prompt: '2girls'),
        seed: 222,
        isOpusFree: true,
        createdAt: DateTime.now(),
      );

      repo.addImageForTesting(testImage1);
      repo.addImageForTesting(testImage2);
      vm.selectImage(testImage1);
      vm.setAnnotatingImage(true);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: vm,
              builder: (context, _) => SizedBox(
                width: 120,
                height: 700,
                child: AnnotationHistoryStrip(
                  viewModel: vm,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      // 验证顶栏
      expect(find.textContaining('History'), findsOneWidget);
      expect(find.textContaining('2'), findsOneWidget); // 2 张历史图片

      // 验证 Draggable 缩略图存在
      expect(find.byType(Draggable<NaiGeneratedImage>), findsNWidgets(2));
    });
  });
}
