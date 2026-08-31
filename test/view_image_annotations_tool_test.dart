import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/core/harness/tools/annotation_tools.dart';
import 'package:novelai_harness/data/models/novelai_models.dart';

Future<Uint8List> createTestPngBytes({int width = 100, int height = 100}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(
    recorder,
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
  );
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFF4A90E2),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('renderImageWithAnnotationOverlay Tests', () {
    test('renders rect, point, and global annotations onto image bytes', () async {
      final baseBytes = await createTestPngBytes(width: 200, height: 200);
      final annotations = [
        ImageAnnotation.rect(
          id: 'r1',
          normalizedRect: const Rect.fromLTWH(0.1, 0.1, 0.4, 0.4),
          note: '修改上衣褶皱',
          colorIndex: 0,
        ),
        ImageAnnotation.point(
          id: 'p1',
          normalizedPoint: const Offset(0.7, 0.3),
          note: '增加发饰',
          colorIndex: 1,
        ),
        ImageAnnotation.global(
          id: 'g1',
          note: '整体提升对比度',
          colorIndex: 2,
        ),
      ];

      final result = await renderImageWithAnnotationOverlay(
        baseBytes,
        annotations,
      );

      expect(result.bytes, isNotEmpty);
      expect(result.width, 200);
      expect(result.height, 200);
      expect(result.overlayApplied, isTrue);
    });
  });

  group('ViewImageAnnotationsTool Tests', () {
    test('returns error when history is empty', () async {
      final tool = ViewImageAnnotationsTool(
        getHistory: () => [],
        isModelMultimodal: () => true,
      );

      final result = await tool.execute('call-1', {'index': 0});
      expect(result.isError, isTrue);
      expect(result.content, contains('没有已生成的图片历史'));
    });

    test('returns error when index is out of bounds', () async {
      final dummyBytes = await createTestPngBytes(width: 50, height: 50);
      final List<NaiGeneratedImage> history = [
        NaiGeneratedImage(
          id: 'img-1',
          bytes: dummyBytes,
          params: const NaiGenerationParams(prompt: 'test prompt'),
          seed: 1001,
          isOpusFree: true,
          createdAt: DateTime.now(),
        ),
      ];

      final tool = ViewImageAnnotationsTool(
        getHistory: () => history,
        isModelMultimodal: () => true,
      );

      final result = await tool.execute('call-2', {'index': 5});
      expect(result.isError, isTrue);
      expect(result.content, contains('超出范围'));
    });

    test('returns structured annotations and image attachment for multimodal model', () async {
      final dummyBytes = await createTestPngBytes(width: 800, height: 600);
      final annotations = [
        ImageAnnotation.rect(
          id: 'ann-1',
          normalizedRect: const Rect.fromLTWH(0.25, 0.25, 0.5, 0.5),
          note: '重绘面部表情为微笑',
          colorIndex: 0,
        ),
        ImageAnnotation.point(
          id: 'ann-2',
          normalizedPoint: const Offset(0.8, 0.8),
          note: '在此处添加水印签名',
          colorIndex: 1,
        ),
        ImageAnnotation.global(
          id: 'ann-3',
          note: '画风调整为赛璐璐上色',
          colorIndex: 2,
        ),
      ];

      final image = NaiGeneratedImage(
        id: 'img-1',
        bytes: dummyBytes,
        params: const NaiGenerationParams(
          prompt: '1girl, smiling',
          model: NaiModel.v5Full,
          width: 800,
          height: 600,
        ),
        seed: 888888,
        isOpusFree: true,
        createdAt: DateTime(2026, 8, 31, 14, 0),
        annotations: annotations,
      );

      final tool = ViewImageAnnotationsTool(
        getHistory: () => [image],
        isModelMultimodal: () => true,
      );

      final result = await tool.execute('call-3', {
        'index': 0,
        'with_image': true,
        'with_overlay': true,
      });

      expect(result.isError, isFalse);
      expect(result.toolName, 'view_image_annotations');
      expect(result.content, contains('【批注 1】[选区]'));
      expect(result.content, contains('重绘面部表情为微笑'));
      expect(result.content, contains('相对坐标'));
      expect(result.content, contains('像素位置'));
      expect(result.content, contains('【批注 2】[锚点]'));
      expect(result.content, contains('在此处添加水印签名'));
      expect(result.content, contains('【批注 3】[整图]'));
      expect(result.content, contains('画风调整为赛璐璐上色'));

      expect(result.imageBase64, isNotNull);
      expect(result.imageMimeType, 'image/png');
    });

    test('returns text-only when model is not multimodal', () async {
      final dummyBytes = await createTestPngBytes(width: 100, height: 100);
      final image = NaiGeneratedImage(
        id: 'img-1',
        bytes: dummyBytes,
        params: const NaiGenerationParams(prompt: 'test'),
        seed: 1234,
        isOpusFree: true,
        createdAt: DateTime.now(),
        annotations: [
          ImageAnnotation.global(note: '全球统一光影'),
        ],
      );

      final tool = ViewImageAnnotationsTool(
        getHistory: () => [image],
        isModelMultimodal: () => false,
      );

      final result = await tool.execute('call-4', {'index': 0});
      expect(result.isError, isFalse);
      expect(result.content, contains('全球统一光影'));
      expect(result.imageBase64, isNull);
    });
  });
}
