import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack;
import 'package:novelai_harness/data/models/novelai_models.dart';
import 'package:novelai_harness/data/services/novelai_service.dart';

void main() {
  group('NovelAiService Stream Generation Tests', () {
    /// 辅助函数：构造 4 字节大端长度前缀 + MessagePack 数据包
    Uint8List packMessage(Map<String, dynamic> data) {
      final packedBytes = msgpack.serialize(data);
      final len = packedBytes.length;
      final header = [
        (len >> 24) & 0xFF,
        (len >> 16) & 0xFF,
        (len >> 8) & 0xFF,
        len & 0xFF,
      ];
      return Uint8List.fromList([...header, ...packedBytes]);
    }

    test('解析正常多步去噪 intermediate 帧与 final 成品帧', () async {
      final dummyPng = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);

      final frame1 = packMessage({
        'event_type': 'intermediate',
        'step_ix': 0,
        'samp_ix': 0,
        'image': dummyPng,
      });

      final frame2 = packMessage({
        'event_type': 'intermediate',
        'step_ix': 13,
        'samp_ix': 0,
        'image': dummyPng,
      });

      final frame3 = packMessage({
        'event_type': 'final',
        'step_ix': 27,
        'samp_ix': 0,
        'image': dummyPng,
      });

      final fullPayload = Uint8List.fromList([...frame1, ...frame2, ...frame3]);

      final mockClient = MockClient.streaming((request, bodyStream) async {
        expect(request.url.path, '/ai/generate-image-stream');
        expect(request.headers['Accept'], 'application/x-msgpack');
        expect(request.headers['Authorization'], 'Bearer test-key');

        // 流式请求必须在 payload 中携带 stream=msgpack，否则服务端不输出中间帧
        final bodyBytes = await bodyStream.toBytes();
        final payload =
            jsonDecode(utf8.decode(bodyBytes)) as Map<String, dynamic>;
        expect(
          (payload['parameters'] as Map<String, dynamic>)['stream'],
          'msgpack',
        );

        final stream = Stream.value(fullPayload);
        return http.StreamedResponse(stream, 200);
      });

      final service = NovelAiService(httpClient: mockClient);
      const params = NaiGenerationParams(
        prompt: '1girl, masterpiece',
        steps: 28,
      );

      final progressEvents = await service
          .generateImageStream(apiKey: 'test-key', params: params)
          .toList();

      expect(progressEvents.length, 3);

      // Frame 1
      expect(progressEvents[0].isFinal, false);
      expect(progressEvents[0].currentStep, 1);
      expect(progressEvents[0].totalSteps, 28);
      expect(progressEvents[0].previewImage, dummyPng);

      // Frame 2
      expect(progressEvents[1].isFinal, false);
      expect(progressEvents[1].currentStep, 14);
      expect(progressEvents[1].totalSteps, 28);
      expect(progressEvents[1].progress, closeTo(14 / 28, 0.01));

      // Frame 3 (Final)
      expect(progressEvents[2].isFinal, true);
      expect(progressEvents[2].currentStep, 28);
      expect(progressEvents[2].totalSteps, 28);
      expect(progressEvents[2].progress, 1.0);
      expect(progressEvents[2].finalImage, dummyPng);
    });

    test('流结束但未收到任何成图数据时，显式产出 error 事件而非静默收场', () async {
      // 模拟服务端返回非 msgpack 分帧数据 (如 SSE 文本)，解析不出任何图像
      final garbage = utf8.encode('data: {"event_type":"intermediate"}\n\n');

      final mockClient = MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(Stream.value(garbage), 200);
      });

      final service = NovelAiService(httpClient: mockClient);
      const params = NaiGenerationParams(prompt: 'test prompt', steps: 28);

      final progressEvents = await service
          .generateImageStream(apiKey: 'test-key', params: params)
          .toList();

      expect(progressEvents.length, 1);
      expect(progressEvents[0].errorMessage, isNotNull);
      expect(progressEvents[0].isFinal, false);
    });

    test('V3 等不支持流式的旧模型自动降级为标准 ZIP 归档请求', () async {
      final dummyPng = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);
      final archive = Archive()
        ..addFile(ArchiveFile('image_0.png', dummyPng.length, dummyPng));
      final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive)!);

      final mockClient = MockClient.streaming((request, bodyStream) async {
        // 降级后应请求标准端点而非流式端点，且不带 stream 参数
        expect(request.url.path, '/ai/generate-image');
        final bodyBytes = await bodyStream.toBytes();
        final payload =
            jsonDecode(utf8.decode(bodyBytes)) as Map<String, dynamic>;
        expect(
          (payload['parameters'] as Map<String, dynamic>).containsKey('stream'),
          isFalse,
        );
        return http.StreamedResponse(Stream.value(zipBytes), 200);
      });

      final service = NovelAiService(httpClient: mockClient);
      const params = NaiGenerationParams(
        prompt: 'test prompt',
        model: NaiModel.v3,
        steps: 28,
      );

      final progressEvents = await service
          .generateImageStream(apiKey: 'test-key', params: params)
          .toList();

      expect(progressEvents.length, 1);
      expect(progressEvents[0].isFinal, true);
      expect(progressEvents[0].finalImage, dummyPng);
    });

    test('粘包与跨分片切包 (Chunk Splitting & Reassembly) 稳健解析', () async {
      final dummyPng = Uint8List.fromList([1, 2, 3, 4, 5]);

      final frame1 = packMessage({
        'event_type': 'intermediate',
        'step_ix': 5,
        'image': dummyPng,
      });

      final frame2 = packMessage({
        'event_type': 'final',
        'step_ix': 27,
        'image': dummyPng,
      });

      final fullData = Uint8List.fromList([...frame1, ...frame2]);

      // 将完整流刻意切成微小乱序分片：每次 3 字节
      final chunks = <Uint8List>[];
      for (int i = 0; i < fullData.length; i += 3) {
        final end = (i + 3 < fullData.length) ? i + 3 : fullData.length;
        chunks.add(fullData.sublist(i, end));
      }

      final mockClient = MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(Stream.fromIterable(chunks), 200);
      });

      final service = NovelAiService(httpClient: mockClient);
      const params = NaiGenerationParams(prompt: 'test prompt', steps: 28);

      final progressEvents = await service
          .generateImageStream(apiKey: 'test-key', params: params)
          .toList();

      expect(progressEvents.length, 2);
      expect(progressEvents[0].isFinal, false);
      expect(progressEvents[0].currentStep, 6);
      expect(progressEvents[1].isFinal, true);
      expect(progressEvents[1].finalImage, dummyPng);
    });

    test('服务端流正常结束但无显式 final 标记时，自动将最后一帧作为 final 成品图', () async {
      final dummyPng = Uint8List.fromList([10, 20, 30]);

      final frame1 = packMessage({
        'event_type': 'intermediate',
        'step_ix': 0,
        'image': dummyPng,
      });

      final frame2 = packMessage({
        'step_ix': 27,
        'data': dummyPng, // 使用 data 字段
      });

      final fullData = Uint8List.fromList([...frame1, ...frame2]);

      final mockClient = MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(Stream.value(fullData), 200);
      });

      final service = NovelAiService(httpClient: mockClient);
      const params = NaiGenerationParams(prompt: 'test prompt', steps: 28);

      final progressEvents = await service
          .generateImageStream(apiKey: 'test-key', params: params)
          .toList();

      expect(progressEvents.length, 3);
      expect(progressEvents[0].isFinal, false);
      expect(progressEvents[1].isFinal, false);
      expect(progressEvents[2].isFinal, true);
      expect(progressEvents[2].finalImage, dummyPng);
    });
  });
}
