import 'dart:convert';
import 'dart:io';
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
}
