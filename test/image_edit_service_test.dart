import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:novelai_harness/data/services/image_edit_service.dart';
import 'package:novelai_harness/data/services/llm_model_fetcher.dart';

/// 构造一个仅满足魔数校验的假 PNG 字节 (looksLikeImage 只查文件头)
Uint8List fakePngBytes() => Uint8List.fromList([
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  1,
  2,
  3,
  4,
  5,
  6,
  7,
  8,
]);

Uint8List fakeJpegBytes() =>
    Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);

Map<String, dynamic> chatBody({required dynamic message}) => {
  'choices': [
    {'message': message},
  ],
};

void main() {
  group('ImageEditService.chatCompletionsEndpoint', () {
    test('基础 URL 拼接 /chat/completions', () {
      expect(
        ImageEditService.chatCompletionsEndpoint('https://api.example.com/v1'),
        'https://api.example.com/v1/chat/completions',
      );
      expect(
        ImageEditService.chatCompletionsEndpoint('https://api.example.com/v1/'),
        'https://api.example.com/v1/chat/completions',
      );
      expect(
        ImageEditService.chatCompletionsEndpoint(
          'https://api.example.com/v1/chat/completions',
        ),
        'https://api.example.com/v1/chat/completions',
      );
      expect(ImageEditService.chatCompletionsEndpoint(''), '');
    });
  });

  group('ImageEditService.looksLikeImage', () {
    test('识别 PNG / JPEG / WebP / GIF 魔数，拒绝随机字节', () {
      expect(ImageEditService.looksLikeImage(fakePngBytes()), isTrue);
      expect(ImageEditService.looksLikeImage(fakeJpegBytes()), isTrue);
      expect(
        ImageEditService.looksLikeImage(
          Uint8List.fromList([
            0x52,
            0x49,
            0x46,
            0x46,
            0,
            0,
            0,
            0,
            0x57,
            0x45,
            0x42,
            0x50,
          ]),
        ),
        isTrue,
      );
      expect(
        ImageEditService.looksLikeImage(
          Uint8List.fromList([0x47, 0x49, 0x46, 0x38, 1, 2, 3, 4, 5, 6, 7, 8]),
        ),
        isTrue,
      );
      expect(
        ImageEditService.looksLikeImage(
          Uint8List.fromList(List.filled(20, 0x41)),
        ),
        isFalse,
      );
      expect(
        ImageEditService.looksLikeImage(Uint8List.fromList([1, 2, 3])),
        isFalse,
      );
    });
  });

  group('ImageEditService.editImage', () {
    test('请求体带 modalities 与图片 data URL，解析 message.images 数组', () async {
      final png = fakePngBytes();
      http.Request? captured;
      final service = ImageEditService(
        client: MockClient((request) async {
          captured = request;
          final body = chatBody(
            message: {
              'content': '已按指令修改完成',
              'images': [
                {
                  'type': 'image_url',
                  'image_url': {
                    'url': 'data:image/png;base64,${base64Encode(png)}',
                  },
                },
              ],
            },
          );
          return http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
        }),
      );

      final result = await service.editImage(
        baseUrl: 'https://api.example.com/v1',
        apiKey: 'sk-test',
        modelId: 'gemini-2.5-flash-image',
        prompt: '把背景换成海滩',
        imageBytes: fakeJpegBytes(),
      );

      expect(result.imageBytes, png);
      expect(result.textReply, '已按指令修改完成');

      // 请求体校验：model / modalities / data URL / 鉴权头
      final sent = jsonDecode(captured!.body) as Map<String, dynamic>;
      expect(sent['model'], 'gemini-2.5-flash-image');
      expect(sent['modalities'], ['image', 'text']);
      // 未选比例/分辨率时相关字段不写入
      expect(sent.containsKey('aspect_ratio'), isFalse);
      expect(sent.containsKey('image_config'), isFalse);
      expect(sent.containsKey('size'), isFalse);
      final content = (sent['messages'] as List).first['content'] as List;
      expect(content.first['type'], 'text');
      expect(content.first['text'], '把背景换成海滩');
      expect(
        (content.last['image_url'] as Map)['url'] as String,
        startsWith('data:image/png;base64,'),
      );
      expect(captured!.headers['Authorization'], 'Bearer sk-test');
    });

    test('生图比例与分辨率按多写法写入请求体', () async {
      final png = fakePngBytes();
      http.Request? captured;
      final service = ImageEditService(
        client: MockClient((request) async {
          captured = request;
          final body = chatBody(
            message: {
              'images': [
                {
                  'type': 'image_url',
                  'image_url': {
                    'url':
                        'data:image/png;base64,${base64Encode(fakePngBytes())}',
                  },
                },
              ],
            },
          );
          return http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
        }),
      );

      await service.editImage(
        baseUrl: 'https://api.example.com/v1',
        apiKey: '',
        modelId: 'gemini-3.1-flash-image',
        prompt: '重绘成 16:9 宽幅夜景',
        imageBytes: png,
        aspectRatio: '16:9',
        imageResolution: '2K',
      );

      final sent = jsonDecode(captured!.body) as Map<String, dynamic>;
      expect(sent['aspect_ratio'], '16:9');
      expect(sent['size'], '16:9');
      expect(sent['image_config'], {
        'aspect_ratio': '16:9',
        'image_size': '2K',
      });

      // 仅分辨率无比例时：只写 image_config.image_size
      await service.editImage(
        baseUrl: 'https://api.example.com/v1',
        apiKey: '',
        modelId: 'gemini-3.1-flash-image',
        prompt: '提高分辨率',
        imageBytes: png,
        imageResolution: '4K',
      );
      final sent2 = jsonDecode(captured!.body) as Map<String, dynamic>;
      expect(sent2.containsKey('aspect_ratio'), isFalse);
      expect(sent2.containsKey('size'), isFalse);
      expect(sent2['image_config'], {'image_size': '4K'});
    });

    test('解析 content 字符串内嵌 markdown base64 图片', () async {
      final png = fakePngBytes();
      final dataUrl = 'data:image/png;base64,${base64Encode(png)}';
      final service = ImageEditService(
        client: MockClient((request) async {
          final body = chatBody(
            message: {'content': '修改好了\n![image]($dataUrl)\n请查收'},
          );
          return http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
        }),
      );

      final result = await service.editImage(
        baseUrl: 'https://api.example.com/v1',
        apiKey: '',
        modelId: 'nano-banana',
        prompt: '改成夜景',
        imageBytes: fakeJpegBytes(),
      );

      expect(result.imageBytes, png);
      // 文字回复剥掉 markdown 图片后剩余文本
      expect(result.textReply, '修改好了\n\n请查收');
    });

    test('解析 content 内容块数组中的 image_url 块', () async {
      final png = fakePngBytes();
      final service = ImageEditService(
        client: MockClient((request) async {
          final body = chatBody(
            message: {
              'content': [
                {'type': 'text', 'text': '已完成编辑'},
                {
                  'type': 'image_url',
                  'image_url': {
                    'url': 'data:image/png;base64,${base64Encode(png)}',
                  },
                },
              ],
            },
          );
          return http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
        }),
      );

      final result = await service.editImage(
        baseUrl: 'https://api.example.com/v1',
        apiKey: '',
        modelId: 'gpt-image-1',
        prompt: '增加一条河流',
        imageBytes: fakePngBytes(),
      );

      expect(result.imageBytes, png);
      expect(result.textReply, '已完成编辑');
    });

    test('http 临时链接自动下载取回字节', () async {
      final png = fakePngBytes();
      final service = ImageEditService(
        client: MockClient((request) async {
          if (request.method == 'GET') {
            expect(
              request.url.toString(),
              'https://cdn.example.com/tmp/img.png',
            );
            return http.Response.bytes(png, 200);
          }
          final body = chatBody(
            message: {
              'content': '![image](https://cdn.example.com/tmp/img.png)',
            },
          );
          return http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
        }),
      );

      final result = await service.editImage(
        baseUrl: 'https://api.example.com/v1',
        apiKey: '',
        modelId: 'seedream-4',
        prompt: '重绘整图',
        imageBytes: fakePngBytes(),
      );

      expect(result.imageBytes, png);
    });

    test('无图片返回时抛出带模型文字回复的错误', () async {
      final service = ImageEditService(
        client: MockClient((request) async {
          final body = chatBody(message: {'content': '我无法处理这张图片'});
          return http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
        }),
      );

      await expectLater(
        service.editImage(
          baseUrl: 'https://api.example.com/v1',
          apiKey: '',
          modelId: 'gemini-2.5-flash-image',
          prompt: '修改',
          imageBytes: fakePngBytes(),
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('我无法处理这张图片'),
          ),
        ),
      );
    });

    test('HTTP 429 触发单次重试后成功', () async {
      final png = fakePngBytes();
      var callCount = 0;
      final service = ImageEditService(
        retryDelay: const Duration(milliseconds: 1),
        client: MockClient((request) async {
          callCount++;
          if (callCount == 1) {
            return http.Response.bytes(utf8.encode('rate limited'), 429);
          }
          final body = chatBody(
            message: {
              'images': [
                {
                  'type': 'image_url',
                  'image_url': {
                    'url': 'data:image/png;base64,${base64Encode(png)}',
                  },
                },
              ],
            },
          );
          return http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
        }),
      );

      final result = await service.editImage(
        baseUrl: 'https://api.example.com/v1',
        apiKey: '',
        modelId: 'gemini-2.5-flash-image',
        prompt: '修改',
        imageBytes: fakePngBytes(),
      );

      expect(result.imageBytes, png);
      expect(callCount, 2);
    });

    test('服务端错误信息透传到异常文本', () async {
      final service = ImageEditService(
        client: MockClient((request) async {
          return http.Response(
            jsonEncode({
              'error': {'message': 'model not found: nano-banana'},
            }),
            404,
          );
        }),
      );

      await expectLater(
        service.editImage(
          baseUrl: 'https://api.example.com/v1',
          apiKey: '',
          modelId: 'nano-banana',
          prompt: '修改',
          imageBytes: fakePngBytes(),
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            allOf(contains('404'), contains('model not found')),
          ),
        ),
      );
    });
  });

  group('LlmModelFetcher.detectImageOutputCapability', () {
    test('识别常见绘图 / 图像编辑模型 ID', () {
      const imageModelIds = [
        'gemini-2.5-flash-image',
        'gemini-2.5-flash-image-preview',
        'nano-banana',
        'google/gemini-2.5-flash-image',
        'gpt-image-1',
        'dall-e-3',
        'seedream-4.0',
        'seededit-3.0',
        'qwen-image-edit',
        'qwen-image',
        'flux-kontext-max',
        'imagen-4.0-generate',
        'gemini-2.0-flash-preview-image-generation',
      ];
      for (final id in imageModelIds) {
        expect(
          LlmModelFetcher.detectImageOutputCapability(id),
          isTrue,
          reason: id,
        );
      }
    });

    test('vision 多模态模型不误判为绘图模型', () {
      const visionOnlyIds = [
        'gpt-4o',
        'gpt-4o-mini',
        'claude-3-5-sonnet',
        'qwen-vl-max',
        'pixtral-large',
        'deepseek-chat',
        'deepseek-reasoner',
      ];
      for (final id in visionOnlyIds) {
        expect(
          LlmModelFetcher.detectImageOutputCapability(id),
          isFalse,
          reason: id,
        );
      }
    });
  });
}
