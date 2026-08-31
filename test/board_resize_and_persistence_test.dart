import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/data/models/novelai_models.dart';
import 'package:novelai_harness/data/repositories/novelai_repository.dart';
import 'package:novelai_harness/ui/features/studio/view_models/studio_view_model.dart';
import 'package:novelai_harness/ui/features/studio/widgets/freeform_annotation_board.dart';

/// 1x1 纯净有效 PNG 字节
final kResizeTestPngBytes = Uint8List.fromList([
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

NaiGeneratedImage _makeImage(String id) {
  return NaiGeneratedImage(
    id: id,
    bytes: kResizeTestPngBytes,
    params: const NaiGenerationParams(
      prompt: 'masterpiece',
      width: 832,
      height: 1216,
    ),
    seed: 7,
    isOpusFree: true,
    createdAt: DateTime.now(),
  );
}

Future<StudioViewModel> _pumpBoard(WidgetTester tester) async {
  // 变大测试窗口：默认 800x600 下主图右下角会被底部右侧浮动坞盖住
  tester.view.physicalSize = const Size(1200, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

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
            width: 1200,
            height: 1000,
            child: FreeformAnnotationBoard(viewModel: vm),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  return vm;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('大画布卡片缩放交互', () {
    testWidgets('图片卡片右下角手柄拖拽可调尺寸', (tester) async {
      final vm = await _pumpBoard(tester);
      final node = vm.boardData.imageNodes.first;
      expect(node.width, closeTo(328.4, 1.0));
      expect(node.height, 480.0);

      final handle = find.byTooltip('拖拽调节图片卡片大小 (按住 Shift 锁定宽高比)');
      expect(handle, findsOneWidget);

      // 分步拖拽：首步被手势竞技场吞为启动位移，后续步进才计入 delta
      final center = tester.getCenter(handle);
      final gesture = await tester.startGesture(center);
      await gesture.moveBy(const Offset(80, 40));
      await gesture.moveBy(const Offset(60, 30));
      await gesture.up();
      await tester.pump();

      final resized = vm.boardData.imageNodes.first;
      expect(resized.width, closeTo(node.width + 60, 2.0));
      expect(resized.height, closeTo(node.height + 30, 2.0));
    });

    testWidgets('便利贴右下角手柄拖拽可调宽高', (tester) async {
      final vm = await _pumpBoard(tester);

      await tester.tap(find.text('+ 便利贴'));
      await tester.pump();
      expect(vm.boardData.noteNodes, hasLength(1));
      final note = vm.boardData.noteNodes.single;
      expect(note.width, 220.0);
      expect(note.height, 132.0);

      final handle = find.byTooltip('拖拽调节便签大小');
      expect(handle, findsOneWidget);

      final center = tester.getCenter(handle);
      final gesture = await tester.startGesture(center);
      await gesture.moveBy(const Offset(80, 40));
      await gesture.moveBy(const Offset(60, 30));
      await gesture.up();
      await tester.pump();

      final resized = vm.boardData.noteNodes.single;
      expect(resized.width, closeTo(280.0, 2.0));
      expect(resized.height, closeTo(162.0, 2.0));
    });

    testWidgets('选中态矩形选区四角手柄拖拽可缩放', (tester) async {
      final vm = await _pumpBoard(tester);

      await vm.addAnnotationToImageNode(
        vm.boardData.imageNodes.first.id,
        ImageAnnotation.rect(
          normalizedRect: const Rect.fromLTWH(0.25, 0.25, 0.5, 0.4),
          colorIndex: 0,
        ),
      );
      await tester.pump();

      // 添加后即为选中态，四个角各有一个缩放手柄
      final handles = find.byTooltip('拖拽调节选区大小');
      expect(handles, findsNWidgets(4));

      // 第一个为左上角手柄 (值顺序 topLeft/topRight/bottomLeft/bottomRight)
      final center = tester.getCenter(handles.first);
      final gesture = await tester.startGesture(center);
      await gesture.moveBy(const Offset(-30, -20));
      await gesture.moveBy(const Offset(-10, -10));
      await gesture.up();
      await tester.pump();

      final rect = vm.boardData.imageNodes.first.annotations.first.rect!;
      // 左上角向左上拖拽：left/top 变小，宽高变大
      expect(rect.left, lessThan(0.24));
      expect(rect.top, lessThan(0.24));
      expect(rect.width, greaterThan(0.51));
      expect(rect.height, greaterThan(0.41));
      expect(rect.left, greaterThanOrEqualTo(0.0));
      expect(rect.top, greaterThanOrEqualTo(0.0));
    });

    testWidgets('未选中的选区不显示缩放手柄，点击选区后出现', (tester) async {
      final vm = await _pumpBoard(tester);

      await vm.addAnnotationToImageNode(
        vm.boardData.imageNodes.first.id,
        ImageAnnotation.rect(
          normalizedRect: const Rect.fromLTWH(0.25, 0.25, 0.5, 0.4),
          colorIndex: 0,
        ),
      );
      await tester.pump();
      expect(find.byTooltip('拖拽调节选区大小'), findsNWidgets(4));

      // 取消选中后手柄消失
      vm.selectAnnotationId(null);
      await tester.pump();
      expect(find.byTooltip('拖拽调节选区大小'), findsNothing);
    });
  });

  group('大画布布局持久化', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('nai_board_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('saveBoardLayout/loadBoardLayout 往返：节点尺寸/便签高度/连线/视口', () async {
      final repo = NovelAiRepository();
      final img = _makeImage('img-main');
      repo.addImageForTesting(img);

      final data = CanvasBoardData(
        imageNodes: [
          CanvasImageNode(
            id: 'main-img-main',
            image: img,
            offset: const Offset(3000, 3000),
            width: 328.4,
            height: 508.0,
            isMain: true,
          ),
        ],
        noteNodes: const [
          CanvasNoteNode(
            id: 'note-1',
            text: '调整这里',
            offset: Offset(3400, 3100),
            width: 264.0,
            height: 190.0,
            colorIndex: 2,
          ),
        ],
        imageLinks: const [],
        viewScale: 1.25,
        viewTx: 120.0,
        viewTy: -40.0,
      );

      await repo.saveBoardLayout(data, saveDir: tempDir.path);
      expect(File('${tempDir.path}/canvas_board.json').existsSync(), isTrue);

      final loaded = await repo.loadBoardLayout(saveDir: tempDir.path);
      expect(loaded, isNotNull);
      expect(loaded!.imageNodes, hasLength(1));
      expect(loaded.imageNodes.first.width, 328.4);
      expect(loaded.imageNodes.first.height, 508.0);
      expect(loaded.imageNodes.first.isMain, isTrue);
      expect(loaded.noteNodes.single.width, 264.0);
      expect(loaded.noteNodes.single.height, 190.0);
      expect(loaded.noteNodes.single.colorIndex, 2);
      expect(loaded.viewScale, 1.25);
      expect(loaded.viewTx, 120.0);
      expect(loaded.viewTy, -40.0);
      expect(loaded.hasSavedViewport, isTrue);
    });

    test('不在历史里的参考图按 board_refs 文件重建，孤立文件被清理', () async {
      final repo = NovelAiRepository();
      final refPath = repo.writeBoardReferenceImage(
        kResizeTestPngBytes,
        saveDir: tempDir.path,
        imageId: 'ref-abc-123',
        ext: '.png',
      );
      expect(refPath, isNotNull);
      expect(File(refPath!).existsSync(), isTrue);

      final refImage = NaiGeneratedImage(
        id: 'ref-abc-123',
        bytes: kResizeTestPngBytes,
        localFilePath: refPath,
        params: const NaiGenerationParams(
          prompt: '外部参考图.png',
          width: 512,
          height: 768,
        ),
        seed: 0,
        isOpusFree: false,
        createdAt: DateTime(2026, 1, 2),
        isImportedReference: true,
      );

      final data = CanvasBoardData(
        imageNodes: [
          CanvasImageNode(
            id: 'ref-ref-abc-123',
            image: refImage,
            offset: const Offset(3300, 3000),
            width: 226.0,
            height: 339.0,
          ),
        ],
        noteNodes: const [],
      );
      await repo.saveBoardLayout(data, saveDir: tempDir.path);

      // 新仓库 (无历史记录)：参考图按文件路径 + 元信息重建
      final repo2 = NovelAiRepository();
      final loaded = await repo2.loadBoardLayout(saveDir: tempDir.path);
      expect(loaded, isNotNull);
      expect(loaded!.imageNodes, hasLength(1));
      final node = loaded.imageNodes.first;
      expect(node.image.id, 'ref-abc-123');
      expect(node.image.localFilePath, refPath);
      expect(node.image.isImportedReference, isTrue);
      expect(node.image.params.width, 512);
      expect(node.image.params.height, 768);
      expect(node.width, 226.0);
      expect(node.height, 339.0);

      // 保存一个没有引用任何 board_refs 文件的布局 → 孤立文件被清理
      final emptyData = CanvasBoardData(imageNodes: [], noteNodes: []);
      await repo.saveBoardLayout(emptyData, saveDir: tempDir.path);
      expect(File(refPath).existsSync(), isFalse);
    });

    test('enabled=false 保存会删除布局文件与 board_refs 目录', () async {
      final repo = NovelAiRepository();
      final refPath = repo.writeBoardReferenceImage(
        kResizeTestPngBytes,
        saveDir: tempDir.path,
        imageId: 'ref-x',
      );
      expect(File(refPath!).existsSync(), isTrue);

      await repo.saveBoardLayout(
        CanvasBoardData(imageNodes: [], noteNodes: []),
        saveDir: tempDir.path,
        enabled: false,
      );
      expect(File('${tempDir.path}/canvas_board.json').existsSync(), isFalse);
      expect(File(refPath).existsSync(), isFalse);
      expect(Directory('${tempDir.path}/board_refs').existsSync(), isFalse);
    });

    test('空目录没有布局文件时返回 null', () async {
      final repo = NovelAiRepository();
      final loaded = await repo.loadBoardLayout(saveDir: tempDir.path);
      expect(loaded, isNull);
    });
  });

  group('Agent 工具写入口适配 (replaceImageAnnotations)', () {
    test('替换批注后解绑指向已删除批注的便签，保留仍存在的连接', () async {
      final repo = NovelAiRepository();
      final vm = StudioViewModel(repository: repo);
      final img = _makeImage('img-main');
      repo.addImageForTesting(img);
      vm.selectImage(img);
      vm.setAnnotatingImage(true);

      final nodeId = vm.boardData.imageNodes.first.id;
      await vm.addAnnotationToImageNode(
        nodeId,
        ImageAnnotation.rect(
          id: 'ann-1',
          normalizedRect: const Rect.fromLTWH(0.1, 0.1, 0.2, 0.2),
          colorIndex: 0,
        ),
      );
      await vm.addAnnotationToImageNode(
        nodeId,
        ImageAnnotation.rect(
          id: 'ann-2',
          normalizedRect: const Rect.fromLTWH(0.4, 0.4, 0.2, 0.2),
          note: '把这里的背景改成星空',
          colorIndex: 1,
        ),
      );

      expect(vm.boardData.noteNodes, hasLength(2));
      expect(vm.boardData.noteNodes.every((n) => n.isConnected), isTrue);

      // Agent 工具把批注列表替换为只剩 ann-1
      final ann1 = vm.boardData.imageNodes.first.annotations
          .where((a) => a.id == 'ann-1')
          .first;
      final ok = await vm.replaceImageAnnotations('img-main', [ann1]);
      expect(ok, isTrue);

      final notes = vm.boardData.noteNodes;
      expect(notes, hasLength(2));
      final note1 = notes.where((n) => n.targetAnnotationId == 'ann-1').first;
      final note2 = notes.where((n) => n.id == 'note-ann-2').first;
      expect(note1.isConnected, isTrue, reason: '仍存在的批注连接保留');
      expect(note2.isConnected, isFalse, reason: '已删除批注的便签被解绑');
      expect(note2.targetImageId, isNull);
      expect(note2.text, isNotEmpty, reason: '解绑后保留为自由便签');

      // 历史记录里的批注同步更新
      expect(repo.history.first.annotations.map((a) => a.id), ['ann-1']);
    });

    test('视口矩阵经 updateBoardViewport 更新并可恢复', () {
      TestWidgetsFlutterBinding.ensureInitialized();
      final repo = NovelAiRepository();
      final vm = StudioViewModel(repository: repo);
      final img = _makeImage('img-main');
      repo.addImageForTesting(img);
      vm.selectImage(img);
      vm.setAnnotatingImage(true);

      expect(vm.boardData.hasSavedViewport, isFalse);
      vm.updateBoardViewport(1.4, 250.0, -80.0);
      expect(vm.boardData.hasSavedViewport, isTrue);
      expect(vm.boardData.viewScale, 1.4);
      expect(vm.boardData.viewTx, 250.0);
      expect(vm.boardData.viewTy, -80.0);
    });
  });
}
