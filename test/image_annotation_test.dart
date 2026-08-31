import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/data/models/novelai_models.dart';
import 'package:novelai_harness/data/repositories/novelai_repository.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ImageAnnotation Model Tests', () {
    test('ImageAnnotation.rect coordinates and BBox conversions', () {
      final ann = ImageAnnotation.rect(
        id: 'ann-1',
        normalizedRect: const Rect.fromLTWH(0.2, 0.1, 0.4, 0.5),
        note: '主角发型高光修改',
        colorIndex: 0,
      );

      expect(ann.type, AnnotationType.rect);
      expect(ann.rect, const Rect.fromLTWH(0.2, 0.1, 0.4, 0.5));
      expect(ann.point, isNull);
      expect(ann.note, '主角发型高光修改');

      // BBox: [ymin, xmin, ymax, xmax] in 0.0~1.0 scale
      final bbox = ann.toBBox();
      expect(bbox, [0.1, 0.2, 0.6, 0.6]);

      // Pixel rect conversion: 1000x2000
      final pxRect = ann.toPixelRect(1000, 2000);
      expect(pxRect, isNotNull);
      expect(pxRect!.left, 200);
      expect(pxRect.top, 200);
      expect(pxRect.width, 400);
      expect(pxRect.height, 1000);

      final summary = ann.formatCoordinateSummary(1000, 2000);
      expect(summary, contains('选区'));
      expect(summary, contains('200, 200, 600, 1200'));
    });

    test('ImageAnnotation.point coordinates and conversions', () {
      final ann = ImageAnnotation.point(
        id: 'ann-2',
        normalizedPoint: const Offset(0.35, 0.75),
        note: '此处增加蝴蝶结饰品',
        colorIndex: 1,
      );

      expect(ann.type, AnnotationType.point);
      expect(ann.point, const Offset(0.35, 0.75));
      expect(ann.rect, isNull);

      final pxPoint = ann.toPixelPoint(1000, 800);
      expect(pxPoint, isNotNull);
      expect(pxPoint!.dx, 350);
      expect(pxPoint.dy, 600);

      final summary = ann.formatCoordinateSummary(1000, 800);
      expect(summary, contains('锚点 [x: 35.0%, y: 75.0%]'));
    });

    test('ImageAnnotation.global conversions', () {
      final ann = ImageAnnotation.global(
        id: 'ann-3',
        note: '画面整体色调调亮并增加丁达尔光',
        colorIndex: 2,
      );

      expect(ann.type, AnnotationType.global);
      expect(ann.rect, isNull);
      expect(ann.point, isNull);

      final summary = ann.formatCoordinateSummary(832, 1216);
      expect(summary, '整图批注');
    });

    test('JSON round-trip serialization', () {
      final originalList = [
        ImageAnnotation.rect(
          id: 'r1',
          normalizedRect: const Rect.fromLTWH(0.123, 0.456, 0.3, 0.4),
          note: 'Box note',
          colorIndex: 3,
        ),
        ImageAnnotation.point(
          id: 'p1',
          normalizedPoint: const Offset(0.789, 0.101),
          note: 'Point note',
          colorIndex: 4,
        ),
        ImageAnnotation.global(id: 'g1', note: 'Global note', colorIndex: 5),
      ];

      for (final original in originalList) {
        final json = original.toJson();
        final restored = ImageAnnotation.fromJson(json);

        expect(restored.id, original.id);
        expect(restored.type, original.type);
        expect(restored.note, original.note);
        expect(restored.colorIndex, original.colorIndex);

        if (original.rect != null) {
          expect(restored.rect!.left, closeTo(original.rect!.left, 0.001));
          expect(restored.rect!.top, closeTo(original.rect!.top, 0.001));
          expect(restored.rect!.width, closeTo(original.rect!.width, 0.001));
          expect(restored.rect!.height, closeTo(original.rect!.height, 0.001));
        }

        if (original.point != null) {
          expect(restored.point!.dx, closeTo(original.point!.dx, 0.001));
          expect(restored.point!.dy, closeTo(original.point!.dy, 0.001));
        }
      }
    });

    test('CanvasNoteNode and CanvasBoardData serialization and connections', () {
      final note = const CanvasNoteNode(
        id: 'note-1',
        text: '修改背景为星空夜景',
        offset: Offset(500, 300),
        width: 220,
        colorIndex: 2,
        targetImageId: 'main-img-1',
        targetAnnotationId: 'ann-1',
      );

      expect(note.isConnected, isTrue);
      expect(note.colorIndex, 2);

      final json = note.toJson();
      final restored = CanvasNoteNode.fromJson(json);
      expect(restored.id, 'note-1');
      expect(restored.text, '修改背景为星空夜景');
      expect(restored.offset.dx, 500);
      expect(restored.offset.dy, 300);
      expect(restored.targetImageId, 'main-img-1');
      expect(restored.targetAnnotationId, 'ann-1');
      expect(restored.isConnected, isTrue);

      final disconnected = restored.copyWith(clearConnection: true);
      expect(disconnected.isConnected, isFalse);
      expect(disconnected.targetImageId, isNull);
    });
  });

  group('NaiGeneratedImage & Repository Annotation Persistence Tests', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('nai_ann_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'updateImageAnnotations updates memory and image_history.json',
      () async {
        final repo = NovelAiRepository();
        final dummyBytes = Uint8List.fromList([
          137,
          80,
          78,
          71,
          13,
          10,
          26,
          10,
        ]); // PNG magic header

        final initialFile = File(p.join(tempDir.path, 'img_test_1.png'));
        await initialFile.writeAsBytes(dummyBytes);

        final initialImage = NaiGeneratedImage(
          id: 'img-test-1',
          bytes: dummyBytes,
          localFilePath: initialFile.path,
          params: const NaiGenerationParams(prompt: '1girl, masterpiece'),
          seed: 1234567,
          isOpusFree: true,
          createdAt: DateTime.now(),
        );

        // 1. 保存图片到历史
        repo.addImageForTesting(initialImage);
        await repo.savePersistedHistory(saveDir: tempDir.path, enabled: true);

        expect(repo.history.length, 1);
        expect(repo.history.first.annotations, isEmpty);

        // 2. 为该图片添加批注
        final annotations = [
          ImageAnnotation.rect(
            id: 'a1',
            normalizedRect: const Rect.fromLTWH(0.1, 0.2, 0.3, 0.4),
            note: '修改眼睛颜色为琥珀色',
            colorIndex: 0,
          ),
          ImageAnnotation.global(id: 'a2', note: '整体背景增加落樱花瓣', colorIndex: 1),
        ];

        final updated = await repo.updateImageAnnotations(
          imageId: 'img-test-1',
          annotations: annotations,
          saveDir: tempDir.path,
          enablePersistence: true,
        );

        expect(updated, isNotNull);
        expect(updated!.annotations.length, 2);
        expect(updated.annotations[0].note, '修改眼睛颜色为琥珀色');
        expect(updated.annotations[1].note, '整体背景增加落樱花瓣');
        expect(repo.history.first.annotations.length, 2);

        // 3. 模拟应用重启，重新实例化 Repository 并加载历史
        final repo2 = NovelAiRepository();
        await repo2.loadPersistedHistory(saveDir: tempDir.path);

        expect(repo2.history.length, 1);
        final restored = repo2.history.first;
        expect(restored.id, 'img-test-1');
        expect(restored.annotations.length, 2);
        expect(restored.annotations[0].id, 'a1');
        expect(restored.annotations[0].note, '修改眼睛颜色为琥珀色');
        expect(restored.annotations[1].id, 'a2');
        expect(restored.annotations[1].note, '整体背景增加落樱花瓣');
      },
    );

    test(
      'importReferenceImage imports external image and persists to history',
      () async {
        final repo = NovelAiRepository();
        final dummyBytes = Uint8List.fromList([
          137,
          80,
          78,
          71,
          13,
          10,
          26,
          10,
          0,
          0,
        ]);

        final imported = await repo.importReferenceImage(
          bytes: dummyBytes,
          width: 800,
          height: 1200,
          saveDir: tempDir.path,
          originalFileName: 'my_reference_character.png',
          enablePersistence: true,
        );

        expect(imported.isImportedReference, isTrue);
        expect(imported.params.width, 800);
        expect(imported.params.height, 1200);
        expect(imported.params.prompt, '导入参考图');
        expect(repo.history.length, 1);
        expect(repo.history.first.id, imported.id);

        // 重新加载验证
        final repo2 = NovelAiRepository();
        await repo2.loadPersistedHistory(saveDir: tempDir.path);

        expect(repo2.history.length, 1);
        expect(repo2.history.first.isImportedReference, isTrue);
        expect(repo2.history.first.params.prompt, '导入参考图');
      },
    );
  });
}
