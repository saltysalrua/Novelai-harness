import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:novelai_harness/core/harness/agent_harness.dart';
import 'package:novelai_harness/core/harness/presets/agent_preset.dart';
import 'package:novelai_harness/core/harness/providers/openai_provider.dart';
import 'package:novelai_harness/core/harness/tools/agent_tool.dart';
import 'package:novelai_harness/core/harness/tools/annotation_tools.dart';
import 'package:novelai_harness/core/harness/tools/canvas_view_tool.dart';
import 'package:novelai_harness/core/harness/types.dart';
import 'package:novelai_harness/data/models/novelai_models.dart';
import 'package:novelai_harness/data/repositories/novelai_repository.dart';
import 'package:novelai_harness/data/services/anlas_calculator.dart';

import 'view_canvas_image_tool_test.dart' show makeTestPng;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late Uint8List original;
  late NovelAiRepository restored;

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('canvas-tool-lazy-');
    original = await makeTestPng(320, 480, 0xFF112233);
    final rawPath = '${temp.path}/original.png';
    final exportPath = '${temp.path}/export.png';
    await File(rawPath).writeAsBytes(original);
    await File(
      exportPath,
    ).writeAsBytes(await makeTestPng(320, 480, 0xFFCC3344));
    final previous = NovelAiRepository();
    previous.addImageForTesting(
      NaiGeneratedImage(
        id: 'persisted-image',
        bytes: original,
        originalFilePath: rawPath,
        localFilePath: exportPath,
        params: const NaiGenerationParams(
          prompt: 'test',
          width: 832,
          height: 1216,
        ),
        createdAt: DateTime(2026, 10, 1),
        seed: 42,
        isOpusFree: true,
        annotations: [
          ImageAnnotation.global(id: 'note', note: '检查背景', colorIndex: 0),
        ],
      ),
    );
    await previous.savePersistedHistory(saveDir: temp.path);
    restored = NovelAiRepository();
    await restored.loadPersistedHistory(saveDir: temp.path);
    expect(restored.history, hasLength(1));
    expect(restored.history.single.bytes, isEmpty);
    expect(restored.history.single.thumbnailBytes, isNotEmpty);
  });
  tearDown(() => temp.deleteSync(recursive: true));

  test('重启恢复后的画板图片工具必须返回原图而非空附件', () async {
    final tool = ViewCanvasImageTool(
      getHistory: () => restored.history,
      loadImageBytes: restored.loadHistoryImageBytes,
      isModelMultimodal: () => true,
    );
    final result = await tool.execute('view-1', {
      'with_overlay': false,
      'full_resolution': true,
    });
    expect(result.isError, isFalse);
    expect(result.imageBase64, isNotEmpty);
    expect(base64Decode(result.imageBase64!), original);
    expect(result.content, contains('320x480'));
    expect(restored.history.single.bytes, isEmpty);
    expect(restored.lruImageCache['persisted-image'], original);
  });

  AgentTool tool(bool annotations, {CanvasImageBytesLoader? loader}) =>
      annotations
      ? ViewImageAnnotationsTool(
          getHistory: () => restored.history,
          loadImageBytes: loader ?? restored.loadHistoryImageBytes,
          isModelMultimodal: () => true,
        )
      : ViewCanvasImageTool(
          getHistory: () => restored.history,
          loadImageBytes: loader ?? restored.loadHistoryImageBytes,
          isModelMultimodal: () => true,
        );

  for (final annotations in [false, true]) {
    final label = annotations ? '批注工具' : '看图工具';
    test('$label 默认压缩/覆盖层读取懒加载原图，重复调用命中 LRU', () async {
      final viewer = tool(annotations);
      for (var i = 0; i < 2; i++) {
        final result = await viewer.execute('view-$i', {});
        expect(result.isError, isFalse);
        expect(result.imageBase64, isNotEmpty);
        final codec = await AnlasCalculator.decodeImageDimensions(
          base64Decode(result.imageBase64!),
        );
        expect(codec?.width, 320);
        expect(codec?.height, 480);
      }
      expect(restored.history.single.bytes, isEmpty);
      expect(restored.lruImageCache['persisted-image'], original);
    });

    for (final empty in [false, true]) {
      test('$label 原图${empty ? '为空文件' : '已删除'}时明确报错且不假报附件成功', () async {
        final file = File(restored.history.single.originalFilePath!);
        if (empty) {
          await file.writeAsBytes([]);
        } else {
          await file.delete();
        }
        expect(
          File(restored.history.single.localFilePath!).existsSync(),
          isTrue,
        );
        final result = await tool(annotations).execute('missing', {});
        expect(result.isError, isTrue);
        expect(result.imageBase64, isNull);
        expect(result.content, contains('本次没有图片附件'));
        expect(result.content, isNot(contains('图片已作为附件')));
      });
    }

    test('$label 懒加载异常转为工具错误，不能假报成功', () async {
      final result = await tool(
        annotations,
        loader: (_) async => throw StateError('read failed'),
      ).execute('failed', {});
      expect(result.isError, isTrue);
      expect(result.imageBase64, isNull);
    });
  }

  test('批注只读文本/非视觉模型不加载原图，也不因原图缺失丢失批注', () async {
    await File(restored.history.single.originalFilePath!).delete();
    var loadCount = 0;
    for (final multimodal in [true, false]) {
      final viewer = ViewImageAnnotationsTool(
        getHistory: () => restored.history,
        isModelMultimodal: () => multimodal,
        loadImageBytes: (_) async {
          loadCount++;
          throw StateError('must not load');
        },
      );
      final result = await viewer.execute('notes', {'with_image': !multimodal});
      expect(result.isError, isFalse);
      expect(result.content, contains('检查背景'));
      expect(result.imageBase64, isNull);
    }
    expect(loadCount, 0);
  });

  test('恢复后真实画板工具经 Harness 到 HTTP 请求确实附图，下一轮重新查看也可见', () async {
    final requests = <Map<String, dynamic>>[];
    final client = MockClient.streaming((request, stream) async {
      requests.add(
        jsonDecode(utf8.decode(await stream.toBytes())) as Map<String, dynamic>,
      );
      final delta = requests.length.isOdd
          ? {
              'tool_calls': [
                {
                  'index': 0,
                  'id': 'view_${requests.length}',
                  'function': {
                    'name': 'view_canvas_image',
                    'arguments':
                        '{"with_overlay":false,"full_resolution":true}',
                  },
                },
              ],
            }
          : {'content': 'done'};
      return http.StreamedResponse(
        http.ByteStream.fromBytes(
          utf8.encode(
            'data: ${jsonEncode({
              'choices': [
                {'delta': delta},
              ],
            })}\ndata: [DONE]\n',
          ),
        ),
        200,
      );
    });
    addTearDown(client.close);
    final harness = AgentHarness(
      provider: OpenAiCompatibleProvider(
        baseUrl: 'https://relay.test/v1',
        apiKey: 'test',
        model: 'claude-test',
        client: client,
      ),
      tools: ToolRegistry()..register(tool(false)),
      initialPreset: const AgentPreset(
        id: 'test',
        name: 'Test',
        description: '',
        systemPrompt: '',
        enabledToolNames: ['view_canvas_image'],
      ),
    );
    addTearDown(harness.dispose);
    for (var turn = 0; turn < 2; turn++) {
      final events = await harness.send('查看画板图片').toList();
      expect(events.whereType<ErrorEvent>(), isEmpty);
      expect(
        events.whereType<ToolResultEvent>().single.result.imageBase64,
        base64Encode(original),
      );
      final messages = requests.last['messages'] as List;
      final urls = <String>[];
      for (final message in messages.cast<Map<String, dynamic>>()) {
        if (message['role'] == 'tool') {
          expect(message['content'], isA<String>());
        }
        if (message['content'] case final List<Object?> blocks) {
          for (final block in blocks.whereType<Map<String, dynamic>>()) {
            if (block['image_url'] case final Map<String, dynamic> image) {
              expect(message['role'], 'user');
              urls.add(image['url'] as String);
            }
          }
        }
      }
      expect(urls, ['data:image/png;base64,${base64Encode(original)}']);
    }
    expect(requests, hasLength(4));
  });
}
