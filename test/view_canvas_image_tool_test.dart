import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/core/harness/tools/canvas_view_tool.dart';
import 'package:novelai_harness/data/models/novelai_models.dart';

/// 用离屏绘制生成一张纯色测试 PNG
Future<Uint8List> makeTestPng(int width, int height, int colorValue) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = ui.Color(colorValue),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('renderImageWithCharacterOverlay 覆盖层渲染', () {
    test('V5 自由定位: 输出为合法 PNG 且保留原始尺寸', () async {
      final png = await makeTestPng(320, 480, 0xFF3366AA);
      final params = NaiGenerationParams(
        prompt: 'test',
        model: NaiModel.v5Full,
        characterPrompts: [
          NaiCharacterPrompt.create(
            name: '左少女',
            prompt: 'girl, blue hair',
            negativePrompt: '',
          ),
          NaiCharacterPrompt.create(name: '右少年', prompt: 'boy, red hair'),
        ],
      );

      final result = await renderImageWithCharacterOverlay(
        png,
        params,
        maxDimension: 1536,
      );

      expect(result.overlayApplied, isTrue);
      expect(result.width, 320);
      expect(result.height, 480);
      // PNG 魔数
      expect(result.bytes[0], 0x89);
      expect(result.bytes.sublist(1, 4), [0x50, 0x4E, 0x47]);
    });

    test('V4 网格定位: 超长边压缩到上限', () async {
      final png = await makeTestPng(2048, 2048, 0xFF222222);
      final params = NaiGenerationParams(
        prompt: 'test',
        model: NaiModel.v4Full,
        characterPrompts: [
          NaiCharacterPrompt.create(name: 'A', prompt: 'girl'),
        ],
      );

      final result = await renderImageWithCharacterOverlay(
        png,
        params,
        maxDimension: 1024,
      );

      expect(result.width, 1024);
      expect(result.height, 1024);
    });

    test('性别锚点配色推导', () {
      final female = resolveCharacterAnchorDisplay(
        NaiCharacterPrompt.create(name: '角色 1', prompt: 'girl, blue hair'),
      );
      expect(female.color, const ui.Color(0xFFEC4899));
      expect(female.label, 'girl');

      final male = resolveCharacterAnchorDisplay(
        NaiCharacterPrompt.create(name: '角色 2', prompt: 'boy, red hair'),
      );
      expect(male.color, const ui.Color(0xFF3B82F6));

      final other = resolveCharacterAnchorDisplay(
        NaiCharacterPrompt.create(name: '守卫', prompt: 'knight, armor'),
      );
      expect(other.color, const ui.Color(0xFF8B5CF6));
      expect(other.label, '守卫');
    });
  });

  group('ViewCanvasImageTool 工具执行', () {
    test('非多模态模型直接拒绝', () async {
      final png = await makeTestPng(64, 64, 0xFF00FF00);
      final tool = ViewCanvasImageTool(
        getHistory: () => [
          NaiGeneratedImage(
            id: '1',
            bytes: png,
            params: const NaiGenerationParams(prompt: ''),
            createdAt: DateTime.now(),
            seed: 100,
            isOpusFree: false,
          ),
        ],
        isModelMultimodal: () => false,
      );

      final result = await tool.execute('t1', {});
      expect(result.isError, isTrue);
      expect(result.content, contains('不支持图像输入'));
      expect(result.imageBase64, isNull);
    });

    test('画板无历史图片时报错', () async {
      final tool = ViewCanvasImageTool(
        getHistory: () => [],
        isModelMultimodal: () => true,
      );

      final result = await tool.execute('t1', {});
      expect(result.isError, isTrue);
      expect(result.content, contains('没有已生成的图片历史'));
    });

    test('索引越界时返回明确的有效范围提示', () async {
      final png = await makeTestPng(64, 64, 0xFF00FF00);
      final history = [
        NaiGeneratedImage(
          id: 'img_newest',
          bytes: png,
          params: const NaiGenerationParams(prompt: 'latest'),
          createdAt: DateTime.now(),
          seed: 100,
          isOpusFree: false,
        ),
        NaiGeneratedImage(
          id: 'img_older',
          bytes: png,
          params: const NaiGenerationParams(prompt: 'older'),
          createdAt: DateTime.now().subtract(const Duration(minutes: 1)),
          seed: 101,
          isOpusFree: false,
        ),
      ];

      final tool = ViewCanvasImageTool(
        getHistory: () => history,
        isModelMultimodal: () => true,
      );

      final negResult = await tool.execute('t1', {'index': -1});
      expect(negResult.isError, isTrue);
      expect(negResult.content, contains('索引 -1 超出范围'));
      expect(negResult.content, contains('有效索引范围为 0 到 1'));

      final outResult = await tool.execute('t2', {'index': 2});
      expect(outResult.isError, isTrue);
      expect(outResult.content, contains('索引 2 超出范围'));
      expect(outResult.content, contains('有效索引范围为 0 到 1'));
    });

    test('默认 index 0 获取最新图片，index 1 获取次新图片', () async {
      final pngLatest = await makeTestPng(64, 64, 0xFFFF0000);
      final pngOlder = await makeTestPng(64, 64, 0xFF0000FF);
      final history = [
        NaiGeneratedImage(
          id: 'img_newest',
          bytes: pngLatest,
          params: const NaiGenerationParams(prompt: 'newest prompt'),
          createdAt: DateTime.now(),
          seed: 11111,
          isOpusFree: false,
        ),
        NaiGeneratedImage(
          id: 'img_older',
          bytes: pngOlder,
          params: const NaiGenerationParams(prompt: 'older prompt'),
          createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
          seed: 22222,
          isOpusFree: false,
        ),
      ];

      final tool = ViewCanvasImageTool(
        getHistory: () => history,
        isModelMultimodal: () => true,
      );

      // 1. 默认 index 为 0 (最新)
      final resLatest = await tool.execute('t1', {'with_overlay': false});
      expect(resLatest.isError, isFalse);
      expect(resLatest.imageBase64, base64Encode(pngLatest));
      expect(resLatest.content, contains('索引: 0, 最新生成'));
      expect(resLatest.content, contains('11111'));

      // 2. 显式指定 index 为 1 (次新)
      final resOlder = await tool.execute('t2', {
        'index': 1,
        'with_overlay': false,
      });
      expect(resOlder.isError, isFalse);
      expect(resOlder.imageBase64, base64Encode(pngOlder));
      expect(resOlder.content, contains('索引: 1, 从新到旧第 2 张'));
      expect(resOlder.content, contains('22222'));

      // 3. 字符串 index 容错解析
      final resStringIndex = await tool.execute('t3', {
        'index': '1',
        'with_overlay': false,
      });
      expect(resStringIndex.isError, isFalse);
      expect(resStringIndex.imageBase64, base64Encode(pngOlder));
    });

    test('with_overlay=false 返回原图字节 (PNG)', () async {
      final png = await makeTestPng(64, 64, 0xFF00FF00);
      final tool = ViewCanvasImageTool(
        getHistory: () => [
          NaiGeneratedImage(
            id: '1',
            bytes: png,
            params: const NaiGenerationParams(prompt: ''),
            createdAt: DateTime.now(),
            seed: 100,
            isOpusFree: false,
          ),
        ],
        isModelMultimodal: () => true,
      );

      final result = await tool.execute('t1', {'with_overlay': false});
      expect(result.isError, isFalse);
      expect(result.imageMimeType, 'image/png');
      expect(result.imageBase64, base64Encode(png));
      expect(result.content, isNot(contains('覆盖层')));
      expect(result.content, contains('图片尺寸: 64x64'));
    });

    test('带角色提示词时叠加覆盖层并附带图片', () async {
      final png = await makeTestPng(200, 300, 0xFFABABAB);
      final params = NaiGenerationParams(
        prompt: 'test',
        model: NaiModel.v5Full,
        characterPrompts: [
          NaiCharacterPrompt.create(name: '主角', prompt: 'girl, silver hair'),
        ],
      );
      final tool = ViewCanvasImageTool(
        getHistory: () => [
          NaiGeneratedImage(
            id: '1',
            bytes: png,
            params: params,
            createdAt: DateTime.now(),
            seed: 99999,
            isOpusFree: false,
          ),
        ],
        isModelMultimodal: () => true,
      );

      final result = await tool.execute('t1', {});
      expect(result.isError, isFalse);
      expect(result.content, contains('已叠加角色位置覆盖层'));
      expect(result.content, contains('启用角色: 1 个'));

      // 附件为合法 PNG base64，且与原图不同 (覆盖了锚点)
      final attached = base64Decode(result.imageBase64!);
      expect(attached[0], 0x89);
      expect(attached.sublist(1, 4), [0x50, 0x4E, 0x47]);
      expect(listEquals(attached, png), isFalse);
    });
  });
}
