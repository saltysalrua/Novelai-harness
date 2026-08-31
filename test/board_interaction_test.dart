import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/data/models/novelai_models.dart';
import 'package:novelai_harness/data/repositories/novelai_repository.dart';
import 'package:novelai_harness/ui/features/studio/view_models/studio_view_model.dart';
import 'package:novelai_harness/ui/features/studio/widgets/board_image_card.dart';
import 'package:novelai_harness/ui/features/studio/widgets/board_note_card.dart';
import 'package:novelai_harness/ui/features/studio/widgets/freeform_annotation_board.dart';

/// 1x1 纯净有效 PNG 字节
final kBoardTestPngBytes = Uint8List.fromList([
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

NaiGeneratedImage _makeImage(
  String id, {
  List<ImageAnnotation> annotations = const [],
}) {
  return NaiGeneratedImage(
    id: id,
    bytes: kBoardTestPngBytes,
    params: const NaiGenerationParams(
      prompt: 'masterpiece',
      width: 832,
      height: 1216,
    ),
    seed: 7,
    isOpusFree: true,
    createdAt: DateTime.now(),
    annotations: annotations,
  );
}

Future<StudioViewModel> _pumpBoard(WidgetTester tester) async {
  final repo = NovelAiRepository();
  final vm = StudioViewModel(repository: repo);
  final img = _makeImage('img-main');
  repo.addImageForTesting(img);
  vm.selectImage(img);
  vm.setAnnotatingImage(true);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: vm,
          builder: (context, _) => SizedBox(
            width: 1000,
            height: 800,
            child: FreeformAnnotationBoard(viewModel: vm),
          ),
        ),
      ),
    ),
  );
  // 等待首帧 post-frame 回调完成初始居中
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  return vm;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FreeformAnnotationBoard 交互回归测试 (漫游/拖拽/删除/圈选)', () {
    testWidgets('左键拖拽空白区域直接漫游，无需切换工具', (tester) async {
      await _pumpBoard(tester);

      final interactiveViewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      final controller = interactiveViewer.transformationController!;
      final txBefore = controller.value.storage[12];

      // (100, 300) 位于主图卡片左侧的空白区域 (测试窗口 800x600)
      final gesture = await tester.startGesture(const Offset(100, 300));
      await gesture.moveBy(const Offset(40, 0));
      await gesture.moveBy(const Offset(40, 0));
      await gesture.up();
      await tester.pump();

      // 两次 moveBy 至少触发一次 onPanUpdate (接受事件可能带一次补偿更新)
      final txDelta = controller.value.storage[12] - txBefore;
      expect(
        txDelta,
        inInclusiveRange(40, 80),
        reason: '空白区域左键拖拽应直接平移视口 (constrained:false 命中修复)',
      );
    });

    testWidgets('拖拽图片卡片顶栏可移动卡片', (tester) async {
      final vm = await _pumpBoard(tester);
      final before = vm.boardData.imageNodes.first.offset;

      // 分步拖拽：首步必须超过 kPanSlop(36px) 才能赢得手势竞技场
      final headerCenter = tester.getCenter(find.text('主图 (当前生成图)'));
      final gesture = await tester.startGesture(headerCenter);
      await gesture.moveBy(const Offset(40, 20));
      await gesture.moveBy(const Offset(10, 10));
      await gesture.up();
      await tester.pump();

      final after = vm.boardData.imageNodes.first.offset;
      expect(after.dx - before.dx, inInclusiveRange(10, 50));
      expect(after.dy - before.dy, inInclusiveRange(10, 30));
    });

    testWidgets('圈选工具在图片上拖拽创建矩形选区批注', (tester) async {
      final vm = await _pumpBoard(tester);

      // (400, 300) 在主图卡片主体内；分步拖拽保证 onPanUpdate 触发
      final gesture = await tester.startGesture(const Offset(400, 300));
      await gesture.moveBy(const Offset(30, 30));
      await gesture.moveBy(const Offset(60, 60));
      await gesture.up();
      await tester.pump();

      final annotations = vm.boardData.imageNodes.first.annotations;
      expect(annotations.length, 1);
      expect(annotations.first.type, AnnotationType.rect);
      expect(annotations.first.rect, isNotNull);
      expect(annotations.first.rect!.width, greaterThan(0.1));
      expect(annotations.first.rect!.height, greaterThan(0.1));
    });

    testWidgets('便利贴可添加与删除', (tester) async {
      final vm = await _pumpBoard(tester);

      await tester.tap(find.text('+ 便利贴'));
      await tester.pump();
      expect(vm.boardData.noteNodes.length, 1);
      expect(find.byType(BoardNoteCard), findsOneWidget);

      final deleteIcon = find.descendant(
        of: find.byType(BoardNoteCard),
        matching: find.byIcon(Icons.close_rounded),
      );
      await tester.tap(deleteIcon);
      await tester.pump();

      expect(vm.boardData.noteNodes, isEmpty);
    });

    testWidgets('便利贴端口拉出连线可连接选区，落空不误断连接', (tester) async {
      final vm = await _pumpBoard(tester);

      // 在主图上添加一个选区批注 (自动生成一张相连便签)
      await vm.addAnnotationToImageNode(
        vm.boardData.imageNodes.first.id,
        ImageAnnotation.rect(
          normalizedRect: const Rect.fromLTWH(0.25, 0.25, 0.5, 0.4),
          colorIndex: 0,
        ),
      );
      await tester.pump();
      final annId = vm.boardData.imageNodes.first.annotations.first.id;
      expect(vm.boardData.noteNodes, hasLength(1));

      // 先断开连接，再通过拖线重新接上
      vm.disconnectNote(vm.boardData.noteNodes.single.id);
      await tester.pump();
      expect(vm.boardData.noteNodes.single.isConnected, isFalse);

      // 便签左侧端口位于便签左缘中部
      final noteTopLeft = tester.getTopLeft(find.byType(BoardNoteCard));
      final portCenter = noteTopLeft + const Offset(0, 14);

      // 选区中心在图片卡主体内 (顶部有 28px 顶栏)
      final imgTopLeft = tester.getTopLeft(find.byType(BoardImageCard));
      final imgNode = vm.boardData.imageNodes.first;
      final annCenter =
          imgTopLeft +
          const Offset(0, 28) +
          Offset(0.5 * imgNode.width, 0.45 * imgNode.height);

      final gesture = await tester.startGesture(portCenter);
      await gesture.moveBy(const Offset(-60, 0));
      await gesture.moveBy(annCenter - portCenter);
      await gesture.up();
      await tester.pump();

      final connected = vm.boardData.noteNodes.single;
      expect(connected.isConnected, isTrue);
      expect(connected.targetImageId, vm.boardData.imageNodes.first.id);
      expect(connected.targetAnnotationId, annId);

      // 再拉一次到画布空白处：本次连线取消，既有连接不被误断
      final gesture2 = await tester.startGesture(portCenter);
      await gesture2.moveBy(const Offset(-60, 0));
      await gesture2.moveBy(const Offset(-100, -150));
      await gesture2.up();
      await tester.pump();

      expect(vm.boardData.noteNodes.single.isConnected, isTrue);
    });

    testWidgets('参考图连线到主图选区：一对多 + 重复拖线断开 + 参考图不可建批注', (tester) async {
      final vm = await _pumpBoard(tester);

      // 在主图上添加一个选区批注 (自动生成相连便签)
      await vm.addAnnotationToImageNode(
        vm.boardData.imageNodes.first.id,
        ImageAnnotation.rect(
          normalizedRect: const Rect.fromLTWH(0.25, 0.25, 0.5, 0.4),
          colorIndex: 0,
        ),
      );
      await tester.pump();
      final annId = vm.boardData.imageNodes.first.annotations.first.id;

      // 添加参考图卡片 (放在主图右侧空白处，测试视口 800x600 内可见)
      vm.addImageNodeToBoard(
        _makeImage('img-ref'),
        position: const Offset(3334, 3290),
      );
      await tester.pump();
      final refCard = find.ancestor(
        of: find.textContaining('参考图'),
        matching: find.byType(BoardImageCard),
      );

      // 参考图是纯图片卡：在其上拖拽不会创建批注 (只会漫游视口)
      final refBodyPoint = tester.getTopLeft(refCard) + const Offset(120, 90);
      final gestureBody = await tester.startGesture(refBodyPoint);
      await gestureBody.moveBy(const Offset(60, 30));
      await gestureBody.moveBy(const Offset(20, 10));
      await gestureBody.up();
      await tester.pump();
      expect(vm.boardData.imageNodes.last.annotations, isEmpty);

      // 从参考图端口拉线到主图选区 → 建立参考图连线
      final mainTopLeft = tester.getTopLeft(find.byType(BoardImageCard).first);
      final imgNode = vm.boardData.imageNodes.first;
      final annCenter =
          mainTopLeft +
          const Offset(0, 28) +
          Offset(0.5 * imgNode.width, 0.45 * imgNode.height);
      final refPort = tester.getTopLeft(refCard) + const Offset(14, 14);

      final g1 = await tester.startGesture(refPort);
      await g1.moveBy(const Offset(60, 0));
      await g1.moveBy(annCenter - (refPort + const Offset(60, 0)));
      await g1.up();
      await tester.pump();

      expect(vm.boardData.imageLinks, hasLength(1));
      final link = vm.boardData.imageLinks.single;
      expect(link.sourceImageId, vm.boardData.imageNodes.last.id);
      expect(link.targetImageId, vm.boardData.imageNodes.first.id);
      expect(link.targetAnnotationId, annId);

      // 第二张便利贴也连到同一选区 → 一个选区一对多
      vm.addNoteNode(text: '一对多', position: const Offset(2774, 3290));
      await tester.pump();
      final note2Port =
          tester.getTopLeft(find.byType(BoardNoteCard).at(1)) +
          const Offset(0, 14);

      final g2 = await tester.startGesture(note2Port);
      await g2.moveBy(const Offset(-60, 0));
      await g2.moveBy(annCenter - (note2Port + const Offset(-60, 0)));
      await g2.up();
      await tester.pump();

      final connectedNotes = vm.boardData.noteNodes
          .where((n) => n.targetAnnotationId == annId)
          .toList();
      expect(connectedNotes, hasLength(2));

      // 再次从参考图拉线到同一选区 → 断开连线 (toggle)
      final g3 = await tester.startGesture(refPort);
      await g3.moveBy(const Offset(60, 0));
      await g3.moveBy(annCenter - (refPort + const Offset(60, 0)));
      await g3.up();
      await tester.pump();

      expect(vm.boardData.imageLinks, isEmpty);
    });

    testWidgets('选区可删除：✕ 按钮与 Delete 快捷键', (tester) async {
      final vm = await _pumpBoard(tester);

      await vm.addAnnotationToImageNode(
        vm.boardData.imageNodes.first.id,
        ImageAnnotation.rect(
          normalizedRect: const Rect.fromLTWH(0.25, 0.25, 0.3, 0.3),
          colorIndex: 0,
        ),
      );
      await tester.pump();
      expect(vm.boardData.imageNodes.first.annotations, hasLength(1));

      // 添加后即为选中态，选区右上角出现删除按钮
      expect(find.byTooltip('删除选区'), findsOneWidget);
      await tester.tap(find.byTooltip('删除选区'));
      await tester.pump();
      expect(vm.boardData.imageNodes.first.annotations, isEmpty);
      // 关联便签自动解绑
      expect(vm.boardData.noteNodes.single.isConnected, isFalse);

      // Delete 键路径：再建一个锚点批注后按 Delete 删除
      await vm.addAnnotationToImageNode(
        vm.boardData.imageNodes.first.id,
        ImageAnnotation.point(
          normalizedPoint: const Offset(0.5, 0.5),
          colorIndex: 1,
        ),
      );
      await tester.pump();
      expect(vm.boardData.imageNodes.first.annotations, hasLength(1));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(vm.boardData.imageNodes.first.annotations, isEmpty);
    });

    testWidgets('参考图卡片可删除，主图卡片没有删除键', (tester) async {
      final vm = await _pumpBoard(tester);
      vm.addImageNodeToBoard(
        _makeImage('img-ref'),
        position: const Offset(2800, 3200),
      );
      await tester.pump();
      expect(vm.boardData.imageNodes.length, 2);

      // 主图卡片不展示删除键
      final mainCard = find.ancestor(
        of: find.text('主图 (当前生成图)'),
        matching: find.byType(BoardImageCard),
      );
      expect(
        find.descendant(
          of: mainCard,
          matching: find.byIcon(Icons.close_rounded),
        ),
        findsNothing,
      );

      // 参考图卡片的删除键可移除卡片
      final refCard = find.ancestor(
        of: find.textContaining('参考图'),
        matching: find.byType(BoardImageCard),
      );
      await tester.tap(
        find.descendant(
          of: refCard,
          matching: find.byIcon(Icons.close_rounded),
        ),
      );
      await tester.pump();

      expect(vm.boardData.imageNodes.length, 1);
      expect(vm.boardData.imageNodes.first.isMain, isTrue);
    });
  });

  group('批注模式画布数据持久保留 (退出不清空)', () {
    test('退出批注保留画布，重进原样恢复；切换目标主图才重建', () {
      TestWidgetsFlutterBinding.ensureInitialized();
      final repo = NovelAiRepository();
      final vm = StudioViewModel(repository: repo);
      final img1 = _makeImage('img-a');
      final img2 = _makeImage('img-b');
      repo.addImageForTesting(img1);
      repo.addImageForTesting(img2);

      vm.selectImage(img1);
      vm.setAnnotatingImage(true);
      vm.addNoteNode(text: '保留我');
      expect(vm.boardData.noteNodes.length, 1);

      // 退出后重进：布局原样恢复
      vm.setAnnotatingImage(false);
      vm.setAnnotatingImage(true);
      expect(vm.boardData.noteNodes.map((n) => n.text), contains('保留我'));

      // 从右键菜单进入另一张图片的批注：画布重建，主图切换
      vm.setAnnotatingImage(true, targetImageId: 'img-b');
      expect(vm.boardData.noteNodes, isEmpty);
      expect(vm.boardData.imageNodes.first.image.id, 'img-b');
      expect(vm.boardData.imageNodes.first.isMain, isTrue);
    });

    test('批注模式下选图不再重置画布布局', () {
      TestWidgetsFlutterBinding.ensureInitialized();
      final repo = NovelAiRepository();
      final vm = StudioViewModel(repository: repo);
      final img1 = _makeImage('img-a');
      final img2 = _makeImage('img-b');
      repo.addImageForTesting(img1);
      repo.addImageForTesting(img2);

      vm.selectImage(img1);
      vm.setAnnotatingImage(true);
      final nodeBefore = vm.boardData.imageNodes.first;
      vm.addNoteNode(text: '布局锚点');

      // 批注模式下点击历史缩略图选图：画布不重置
      vm.selectImage(img2);
      expect(identical(vm.boardData.imageNodes.first, nodeBefore), isTrue);
      expect(vm.boardData.noteNodes.map((n) => n.text), contains('布局锚点'));
    });
  });
}
