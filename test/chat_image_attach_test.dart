import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/core/harness/agent_harness.dart';
import 'package:novelai_harness/core/harness/presets/agent_preset.dart';
import 'package:novelai_harness/core/harness/providers/llm_provider.dart';
import 'package:novelai_harness/core/harness/session_recorder.dart';
import 'package:novelai_harness/core/harness/tools/agent_tool.dart';
import 'package:novelai_harness/core/harness/types.dart';
import 'package:novelai_harness/data/services/session_log_service.dart';
import 'package:novelai_harness/ui/features/studio/widgets/agent_chat_messages.dart';
import 'package:novelai_harness/ui/features/studio/widgets/chat_image_attachment.dart';

/// 1x1 透明 PNG
const String _tinyPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

class _MockLlmProvider implements LlmProvider {
  List<AgentMessage>? lastMessages;

  @override
  String get modelId => 'mock-model';

  @override
  Stream<HarnessEvent> streamChat({
    required List<AgentMessage> messages,
    required List<AgentTool> tools,
    double temperature = 0.7,
    String? promptCacheKey,
  }) async* {
    lastMessages = messages;
    yield ContentDeltaEvent('收到图片');
  }
}

class _MockSessionRecorder implements SessionRecorder {
  final List<AgentMessage> recorded = [];

  @override
  String? get sessionId => null;

  @override
  void recordMessage(AgentMessage message, {String? provider, String? model}) {
    recorded.add(message);
  }

  @override
  void recordModelChange(String provider, String modelId) {}

  @override
  void recordThinkingLevelChange(String level) {}

  @override
  void startNewSession() {}

  @override
  void rewindToMessageCount(int keepCount) {}
}

void main() {
  group('AgentMessage 用户图片多模态序列化', () {
    test('toOpenAiJson 携带图片时 content 为 text + image_url 块数组', () {
      final msg = AgentMessage(
        id: 'u1',
        role: AgentRole.user,
        content: '看这张图',
        images: [
          const AgentMessageImage(base64: _tinyPngBase64),
          const AgentMessageImage(base64: 'AAAA', mimeType: 'image/jpeg'),
        ],
      );

      final json = msg.toOpenAiJson();
      final content = json['content'];
      expect(content, isA<List<dynamic>>());
      final blocks = content as List<dynamic>;
      expect(blocks.length, 3);
      expect(blocks[0], {'type': 'text', 'text': '看这张图'});
      expect(blocks[1], {
        'type': 'image_url',
        'image_url': {'url': 'data:image/png;base64,$_tinyPngBase64'},
      });
      expect(blocks[2], {
        'type': 'image_url',
        'image_url': {'url': 'data:image/jpeg;base64,AAAA'},
      });
    });

    test('空文本纯图片消息只发送 image_url 块', () {
      final msg = AgentMessage(
        id: 'u2',
        role: AgentRole.user,
        content: '',
        images: [const AgentMessageImage(base64: _tinyPngBase64)],
      );

      final blocks = msg.toOpenAiJson()['content'] as List<dynamic>;
      expect(blocks.length, 1);
      expect(blocks.first['type'], 'image_url');
    });

    test('无图片用户消息保持纯字符串 content', () {
      final msg = AgentMessage(id: 'u3', role: AgentRole.user, content: '你好');
      expect(msg.toOpenAiJson()['content'], '你好');
    });

    test('copyWith 透传 images', () {
      final img = const AgentMessageImage(base64: 'AAAA');
      final msg = AgentMessage(
        id: 'u4',
        role: AgentRole.user,
        content: '',
        images: [img],
      ).copyWith(content: '补充文字');
      expect(msg.images.length, 1);
      expect(msg.content, '补充文字');
    });
  });

  group('AgentHarness 图片附件发送', () {
    test('send 携带图片进入用户消息并透传给 Provider', () async {
      final provider = _MockLlmProvider();
      final recorder = _MockSessionRecorder();
      final harness = AgentHarness(
        tools: ToolRegistry(),
        provider: provider,
        recorder: recorder,
        initialPreset: AgentPreset(
          id: 'p',
          name: 'p',
          description: 'p',
          systemPrompt: 'You are a test.',
        ),
      );

      final events = await harness
          .send(
            '看这张图',
            images: [const AgentMessageImage(base64: _tinyPngBase64)],
          )
          .toList();

      expect(events.whereType<ContentDeltaEvent>(), isNotEmpty);

      // 用户消息被记录且带图片
      final userMsg = recorder.recorded.firstWhere(
        (m) => m.role == AgentRole.user,
      );
      expect(userMsg.images.length, 1);
      expect(userMsg.images.first.mimeType, 'image/png');

      // Provider 收到的上下文里用户消息是多模态数组
      final providerUserMsg = provider.lastMessages!.firstWhere(
        (m) => m.role == AgentRole.user,
      );
      final blocks = providerUserMsg.toOpenAiJson()['content'] as List<dynamic>;
      expect(blocks.any((b) => b['type'] == 'image_url'), isTrue);
    });

    test('纯图片空文本消息允许发送', () async {
      final provider = _MockLlmProvider();
      final recorder = _MockSessionRecorder();
      final harness = AgentHarness(
        tools: ToolRegistry(),
        provider: provider,
        recorder: recorder,
        initialPreset: AgentPreset(
          id: 'p',
          name: 'p',
          description: 'p',
          systemPrompt: 'You are a test.',
        ),
      );

      await harness
          .send('', images: [const AgentMessageImage(base64: _tinyPngBase64)])
          .toList();

      final userMsg = recorder.recorded.firstWhere(
        (m) => m.role == AgentRole.user,
      );
      expect(userMsg.content, '');
      expect(userMsg.images.length, 1);
    });

    test('空文本且无图片时不发送', () async {
      final provider = _MockLlmProvider();
      final harness = AgentHarness(
        tools: ToolRegistry(),
        provider: provider,
        initialPreset: AgentPreset(
          id: 'p',
          name: 'p',
          description: 'p',
          systemPrompt: 'You are a test.',
        ),
      );

      final events = await harness.send('   ').toList();
      expect(events, isEmpty);
      expect(provider.lastMessages, isNull);
    });
  });

  group('SessionLogService 图片附件落盘与恢复', () {
    late Directory tempDir;
    late SessionLogService service;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('nai_img_session_test');
      service = SessionLogService();
      await service.init(baseDir: tempDir.path);
    });

    tearDown(() async {
      await service.flush();
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    test('用户图片消息 JSONL 往返恢复', () async {
      service.recordMessage(
        AgentMessage(
          id: 'u1',
          role: AgentRole.user,
          content: '按这张图画',
          images: [
            const AgentMessageImage(base64: _tinyPngBase64),
            const AgentMessageImage(base64: 'AAAA', mimeType: 'image/jpeg'),
          ],
        ),
      );
      service.recordMessage(
        AgentMessage(id: 'a1', role: AgentRole.assistant, content: '好的'),
      );
      await service.flush();

      final snapshot = service.loadLatestSession();
      expect(snapshot, isNotNull);
      final restored = snapshot!.messages;
      expect(restored.length, 2);

      final restoredUser = restored.first;
      expect(restoredUser.role, AgentRole.user);
      expect(restoredUser.content, '按这张图画');
      expect(restoredUser.images.length, 2);
      expect(restoredUser.images.first.base64, _tinyPngBase64);
      expect(restoredUser.images.first.mimeType, 'image/png');
      expect(restoredUser.images[1].mimeType, 'image/jpeg');

      // 落盘行确实是 image 内容块形态
      final lines = await File(service.currentSessionFile!.path).readAsLines();
      final userLine = lines
          .skip(1)
          .map((l) => jsonDecode(l) as Map<String, dynamic>)
          .firstWhere((e) => e['type'] == 'message');
      final content = (userLine['message'] as Map)['content'] as List<dynamic>;
      expect(content.first['type'], 'text');
      expect(content[1]['type'], 'image');
      expect(content[1]['data'], _tinyPngBase64);
    });

    test('无图片用户消息落盘格式不变', () async {
      service.recordMessage(
        AgentMessage(id: 'u1', role: AgentRole.user, content: '纯文本'),
      );
      await service.flush();

      final snapshot = service.loadLatestSession();
      expect(snapshot!.messages.single.content, '纯文本');
      expect(snapshot.messages.single.images, isEmpty);
    });
  });

  group('用户消息图片渲染', () {
    testWidgets('UserMessageRow 渲染文本与图片缩略图', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AgentChatMessageItem(
              message: AgentMessage(
                id: 'u1',
                role: AgentRole.user,
                content: '看这张图',
                images: const [AgentMessageImage(base64: _tinyPngBase64)],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('看这张图'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
    });
  });

  group('probeImageHeaderSize 文件头同步解析', () {
    test('PNG IHDR 宽高 (大端)', () {
      final bytes = Uint8List.fromList([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // 签名
        0x00, 0x00, 0x00, 0x0D, // IHDR 长度
        0x49, 0x48, 0x44, 0x52, // 'IHDR'
        0x00, 0x00, 0x03, 0x40, // width = 832
        0x00, 0x00, 0x04, 0xC0, // height = 1216
        0x08, 0x06, 0x00, 0x00, 0x00, // 位深/颜色类型等
      ]);
      final size = probeImageHeaderSize(bytes);
      expect(size, isNotNull);
      expect(size!.width, 832);
      expect(size.height, 1216);
    });

    test('真实 base64 PNG (1x1 透明图) 解析', () {
      final size = probeImageHeaderSize(base64Decode(_tinyPngBase64));
      expect(size, isNotNull);
      expect(size!.width, 1);
      expect(size.height, 1);
    });

    test('JPEG SOF 段宽高 (跳过前置段)', () {
      final bytes = Uint8List.fromList([
        0xFF, 0xD8, // SOI
        0xFF, 0xE0, 0x00, 0x10, // APP0 段，长度 16
        ...List.filled(14, 0x00), // APP0 载荷
        0xFF, 0xC0, 0x00, 0x0B, // SOF0 段
        0x08, // 精度
        0x02, 0x58, // height = 600
        0x03, 0x20, // width = 800
        0x03, // 通道数
        0x01, 0x11, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01, // 采样
      ]);
      final size = probeImageHeaderSize(bytes);
      expect(size, isNotNull);
      expect(size!.width, 800);
      expect(size.height, 600);
    });

    test('GIF 逻辑屏幕宽高 (小端)', () {
      final bytes = Uint8List.fromList([
        0x47, 0x49, 0x46, 0x38, 0x39, 0x61, // 'GIF89a'
        0x20, 0x03, // width = 800
        0x58, 0x02, // height = 600
        0x00, 0x00,
      ]);
      final size = probeImageHeaderSize(bytes);
      expect(size, isNotNull);
      expect(size!.width, 800);
      expect(size.height, 600);
    });

    test('WebP VP8X 画布宽高 (24 位小端减一)', () {
      final bytes = Uint8List.fromList([
        0x52, 0x49, 0x46, 0x46, 0x00, 0x00, 0x00, 0x00, // 'RIFF' + 长度
        0x57, 0x45, 0x42, 0x50, // 'WEBP'
        0x56, 0x50, 0x38, 0x58, // 'VP8X'
        0x0A, 0x00, 0x00, 0x00, // 块长度 10
        0x00, // flags
        0x00, 0x00, 0x00, // reserved
        0x3F, 0x03, 0x00, // width - 1 = 831
        0xBF, 0x04, 0x00, // height - 1 = 1215
      ]);
      final size = probeImageHeaderSize(bytes);
      expect(size, isNotNull);
      expect(size!.width, 832);
      expect(size.height, 1216);
    });

    test('非图片字节与空数据返回 null', () {
      expect(probeImageHeaderSize(Uint8List(0)), isNull);
      expect(probeImageHeaderSize(Uint8List.fromList([1, 2, 3, 4, 5])), isNull);
    });
  });

  group('工具结果图片渲染', () {
    testWidgets('ToolResultBlock 以 AspectRatio 预留图片高度', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AgentChatMessageItem(
                message: AgentMessage(
                  id: 't1',
                  role: AgentRole.tool,
                  toolName: 'view_canvas_image',
                  content: '已查看画板图片',
                  imageBase64: _tinyPngBase64,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // 文件头解析成功 → 存在 AspectRatio 预留布局，滚动不跳动
      expect(find.byType(AspectRatio), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
    });
  });
}
