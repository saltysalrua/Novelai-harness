import 'dart:typed_data';
import 'dart:ui' show Rect;
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/core/harness/presets/agent_preset.dart';
import 'package:novelai_harness/core/harness/tools/annotation_tools.dart';
import 'package:novelai_harness/data/models/novelai_models.dart';

/// 1x1 纯净 PNG 字节 (供 add 工具离屏解码尺寸)
final kToolTestPngBytes = Uint8List.fromList([
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

NaiGeneratedImage _makeImage() {
  return NaiGeneratedImage(
    id: 'img-1',
    bytes: kToolTestPngBytes,
    params: const NaiGenerationParams(
      prompt: '1girl',
      width: 832,
      height: 1216,
    ),
    seed: 42,
    isOpusFree: true,
    createdAt: DateTime.now(),
    annotations: [
      ImageAnnotation.rect(
        id: 'ann-A',
        normalizedRect: const Rect.fromLTWH(0.1, 0.2, 0.3, 0.4),
        note: '旧选区',
        colorIndex: 0,
      ),
      ImageAnnotation.point(
        id: 'ann-B',
        normalizedPoint: const Offset(0.6, 0.7),
        note: '旧锚点',
        colorIndex: 1,
      ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Agent 批注增删改查工具四件套', () {
    test('add_image_annotation 按百分比坐标添加矩形选区', () async {
      var history = [_makeImage()];
      final tool = AddImageAnnotationTool(
        getHistory: () => history,
        writeAnnotations: (imageId, anns) async {
          if (imageId != 'img-1') return false;
          history = [
            history.first.copyWith(annotations: anns),
            ...history.skip(1),
          ];
          return true;
        },
      );

      final result = await tool.execute('t1', {
        'type': 'rect',
        'x': 10,
        'y': 20,
        'w': 30,
        'h': 40,
        'note': '修改发型高光',
      });

      expect(result.isError, isFalse);
      expect(result.content, contains('修改发型高光'));
      final anns = history.first.annotations;
      expect(anns.length, 3);
      final added = anns.last;
      expect(added.type, AnnotationType.rect);
      expect(added.rect!.left, closeTo(0.1, 0.001));
      expect(added.rect!.top, closeTo(0.2, 0.001));
      expect(added.rect!.width, closeTo(0.3, 0.001));
      expect(added.rect!.height, closeTo(0.4, 0.001));
      expect(added.note, '修改发型高光');
    });

    test('add_image_annotation 兼容 0~1 归一化坐标添加锚点', () async {
      var history = [_makeImage()];
      final tool = AddImageAnnotationTool(
        getHistory: () => history,
        writeAnnotations: (imageId, anns) async {
          history = [history.first.copyWith(annotations: anns)];
          return true;
        },
      );

      final result = await tool.execute('t2', {
        'type': 'point',
        'x': 0.5,
        'y': 0.75,
        'note': '增加蝴蝶结',
      });

      expect(result.isError, isFalse);
      final added = history.first.annotations.last;
      expect(added.type, AnnotationType.point);
      expect(added.point!.dx, closeTo(0.5, 0.001));
      expect(added.point!.dy, closeTo(0.75, 0.001));
    });

    test('add_image_annotation 缺坐标或索引越界返回错误', () async {
      final history = [_makeImage()];
      final tool = AddImageAnnotationTool(
        getHistory: () => history,
        writeAnnotations: (_, _) async => true,
      );

      final missing = await tool.execute('t3', {'type': 'rect'});
      expect(missing.isError, isTrue);
      expect(missing.content, contains('x/y/w/h'));

      final badIndex = await tool.execute('t4', {'type': 'global', 'index': 9});
      expect(badIndex.isError, isTrue);
      expect(badIndex.content, contains('超出范围'));
    });

    test('update_image_annotation 按编号修改文字与坐标', () async {
      var history = [_makeImage()];
      final tool = UpdateImageAnnotationTool(
        getHistory: () => history,
        writeAnnotations: (imageId, anns) async {
          history = [history.first.copyWith(annotations: anns)];
          return true;
        },
      );

      // 按编号 (1 起) 修改第一条批注的文字与坐标
      final result = await tool.execute('t5', {
        'index': 0,
        'annotation': 1,
        'note': '新选区意见',
        'x': 20,
        'y': 30,
        'w': 50,
        'h': 40,
      });

      expect(result.isError, isFalse);
      final updated = history.first.annotations.first;
      expect(updated.id, 'ann-A');
      expect(updated.note, '新选区意见');
      expect(updated.rect!.left, closeTo(0.2, 0.001));
      expect(updated.rect!.top, closeTo(0.3, 0.001));
      expect(updated.rect!.width, closeTo(0.5, 0.001));
      expect(updated.rect!.height, closeTo(0.4, 0.001));
      // 第二条批注不受影响
      expect(history.first.annotations[1].note, '旧锚点');
    });

    test('update_image_annotation 按 annotation_id 修改颜色', () async {
      var history = [_makeImage()];
      final tool = UpdateImageAnnotationTool(
        getHistory: () => history,
        writeAnnotations: (_, anns) async {
          history = [history.first.copyWith(annotations: anns)];
          return true;
        },
      );

      final result = await tool.execute('t6', {
        'annotation_id': 'ann-B',
        'color_index': 3,
      });

      expect(result.isError, isFalse);
      expect(history.first.annotations[1].colorIndex, 3);
      // 未提供 note 时保持原文字
      expect(history.first.annotations[1].note, '旧锚点');
    });

    test('remove_image_annotation 按编号删除指定批注', () async {
      var history = [_makeImage()];
      final tool = RemoveImageAnnotationTool(
        getHistory: () => history,
        writeAnnotations: (_, anns) async {
          history = [history.first.copyWith(annotations: anns)];
          return true;
        },
      );

      final result = await tool.execute('t7', {'index': 0, 'annotation': 1});
      expect(result.isError, isFalse);
      expect(history.first.annotations.length, 1);
      expect(history.first.annotations.first.id, 'ann-B');
    });

    test('clear_image_annotations 清空全部批注', () async {
      var history = [_makeImage()];
      final tool = ClearImageAnnotationsTool(
        getHistory: () => history,
        writeAnnotations: (_, anns) async {
          history = [history.first.copyWith(annotations: anns)];
          return true;
        },
      );

      final result = await tool.execute('t8', {'index': 0});
      expect(result.isError, isFalse);
      expect(history.first.annotations, isEmpty);

      // 再次清空不报错
      final again = await tool.execute('t9', {'index': 0});
      expect(again.isError, isFalse);
      expect(again.content, contains('无需清空'));
    });
  });

  group('PresetToolKeys 批注工具白名单', () {
    test('五个批注工具键均在内置常量表中', () {
      const annotationTools = [
        PresetToolKeys.viewImageAnnotations,
        PresetToolKeys.addImageAnnotation,
        PresetToolKeys.updateImageAnnotation,
        PresetToolKeys.removeImageAnnotation,
        PresetToolKeys.clearImageAnnotations,
      ];
      for (final key in annotationTools) {
        expect(
          PresetToolKeys.labels.containsKey(key),
          isTrue,
          reason: 'PresetToolKeys.labels 缺少 $key，预设无法放行该工具',
        );
      }
    });
  });
}
