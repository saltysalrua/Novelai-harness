import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/core/harness/types.dart';
import 'package:novelai_harness/ui/features/studio/view_models/chat_checkpoints.dart';

AgentMessage _msg(
  String id,
  AgentRole role, {
  String content = '',
  DateTime? at,
}) => AgentMessage(id: id, role: role, content: content, createdAt: at);

void main() {
  group('extractChatCheckpoints', () {
    test('空消息流返回空列表', () {
      expect(extractChatCheckpoints([]), isEmpty);
    });

    test('按用户消息切分轮次并归入随后的 assistant/tool 消息', () {
      final t0 = DateTime(2026, 1, 1, 10, 0, 0);
      final messages = [
        _msg('u1', AgentRole.user, content: '第一问', at: t0),
        _msg('a1', AgentRole.assistant, content: '正在思考', at: t0),
        _msg(
          'tool1',
          AgentRole.tool,
          content: 'ok',
          at: t0.add(const Duration(seconds: 1)),
        ),
        _msg('a2', AgentRole.assistant, content: '回答一', at: t0),
        _msg('u2', AgentRole.user, content: '第二问', at: t0),
        _msg('a3', AgentRole.assistant, content: '回答二', at: t0),
      ];

      final checkpoints = extractChatCheckpoints(messages);

      expect(checkpoints.length, 2);
      expect(checkpoints[0].index, 1);
      expect(checkpoints[0].userMessage.id, 'u1');
      // 同轮内多条 assistant 取最后一条
      expect(checkpoints[0].assistantMessage?.id, 'a2');
      expect(checkpoints[0].toolMessages.map((m) => m.id), ['tool1']);
      expect(checkpoints[1].index, 2);
      expect(checkpoints[1].userMessage.id, 'u2');
      expect(checkpoints[1].assistantMessage?.id, 'a3');
      expect(checkpoints[1].toolMessages, isEmpty);
    });

    test('连续两条用户消息各自成轮', () {
      final t0 = DateTime(2026, 1, 1, 10, 0, 0);
      final messages = [
        _msg('u1', AgentRole.user, content: '被打中止的问题', at: t0),
        _msg('u2', AgentRole.user, content: '重新问', at: t0),
        _msg('a1', AgentRole.assistant, content: '答', at: t0),
      ];

      final checkpoints = extractChatCheckpoints(messages);

      expect(checkpoints.length, 2);
      expect(checkpoints[0].userMessage.id, 'u1');
      expect(checkpoints[0].assistantMessage, isNull);
      expect(checkpoints[1].userMessage.id, 'u2');
      expect(checkpoints[1].assistantMessage?.id, 'a1');
    });

    test('开头游离的非用户消息不计入任何轮次', () {
      final t0 = DateTime(2026, 1, 1, 10, 0, 0);
      final messages = [
        _msg('a0', AgentRole.assistant, content: '游离回答', at: t0),
        _msg('u1', AgentRole.user, content: '问题', at: t0),
        _msg('a1', AgentRole.assistant, content: '答', at: t0),
      ];

      final checkpoints = extractChatCheckpoints(messages);

      expect(checkpoints.length, 1);
      expect(checkpoints[0].userMessage.id, 'u1');
      expect(checkpoints[0].assistantMessage?.id, 'a1');
    });

    test('只有用户消息没有回复也能成轮 (流式中途)', () {
      final t0 = DateTime(2026, 1, 1, 10, 0, 0);
      final messages = [_msg('u1', AgentRole.user, content: '生成中', at: t0)];

      final checkpoints = extractChatCheckpoints(messages);

      expect(checkpoints.length, 1);
      expect(checkpoints[0].userMessage.id, 'u1');
      expect(checkpoints[0].assistantMessage, isNull);
      expect(checkpoints[0].toolMessages, isEmpty);
    });
  });
}
