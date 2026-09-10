import 'dart:convert';
import '../agent_harness.dart';
import '../types.dart';
import 'agent_tool.dart';

/// 笔记写入与请求侧释放统一经 Harness 状态入口，原始历史只读。
class ContextMemoryTool extends AgentTool {
  final AgentHarness harness;
  ContextMemoryTool(this.harness)
    : super(
        name: 'context_memory',
        label: '上下文与笔记',
        description:
            '管理本会话记忆。list 列出笔记和回复编号；add_note 保存必要结论；'
            'delete_note 删除过期笔记；forget_reply 释放旧回复及工具结果的请求上下文'
            '（不删除历史，不允许释放当前轮或已进入摘要的回复）；'
            'read_reply 按编号分页读取原文。笔记最多64条，每条2000字符。',
        parameters: const {
          'type': 'object',
          'properties': {
            'action': {
              'type': 'string',
              'enum': [
                'list',
                'add_note',
                'delete_note',
                'forget_reply',
                'read_reply',
              ],
            },
            'text': {'type': 'string', 'description': '笔记内容'},
            'id': {'type': 'integer', 'minimum': 1, 'description': '笔记ID或回复编号'},
            'offset': {
              'type': 'integer',
              'minimum': 0,
              'description': '列表条目/原文字符起点',
            },
          },
          'required': ['action'],
          'additionalProperties': false,
        },
      );

  @override
  Future<ToolResult> execute(
    String toolCallId,
    Map<String, dynamic> args,
  ) async {
    try {
      if (!harness.currentPreset.isToolEnabled(name)) {
        throw StateError('当前预设未开放上下文记忆工具');
      }
      final id = args['id'];
      final offset = args['offset'] ?? 0;
      if (offset is! int || offset < 0) throw ArgumentError('offset 必须是非负整数');
      final String content;
      switch (args['action']) {
        case 'list':
          final replies = harness.messages
              .where((m) => m.replyNumber != null)
              .toList();
          content = jsonEncode({
            'notes': {
              for (final e in harness.memory.notes.entries) '${e.key}': e.value,
            },
            'contextTokensEstimated': harness.contextUsage.tokens,
            'replies': [
              for (final m in replies.skip(offset).take(50))
                {
                  'number': m.replyNumber,
                  'forgotten': harness.memory.forgottenReplies.contains(
                    m.replyNumber,
                  ),
                  'preview': m.content.substring(
                    0,
                    m.content.length.clamp(0, 100),
                  ),
                },
            ],
            'totalReplies': replies.length,
          });
        case 'add_note':
          final text = args['text'];
          if (text is! String) throw ArgumentError('需要 text');
          final noteId = harness.memory.addNote(text);
          harness.memoryChanged();
          content = '已保存笔记 #$noteId';
        case 'delete_note':
          if (id is! int || !harness.memory.deleteNote(id)) {
            throw ArgumentError('笔记不存在');
          }
          harness.memoryChanged();
          content = '已删除笔记 #$id';
        case 'forget_reply':
          if (id is! int) throw ArgumentError('需要回复编号 id');
          content = harness.forgetReply(id);
        case 'read_reply':
          if (id is! int) throw ArgumentError('需要回复编号 id');
          final message = harness.messages
              .where((m) => m.replyNumber == id)
              .firstOrNull;
          if (message == null) throw ArgumentError('回复不存在');
          final calls = message.toolCalls ?? const <ToolCall>[];
          final callIds = calls.map((c) => c.id).toSet();
          final text =
              '回复 #$id 原文:\n${message.content}\n'
              '${calls.map((c) => jsonEncode(c.toOpenAiJson())).join('\n')}\n'
              '${harness.messages.where((m) => m.role == AgentRole.tool && callIds.contains(m.toolCallId)).map((m) => m.content).join('\n')}';
          if (offset > text.length) {
            throw ArgumentError('offset 超出原文长度 ${text.length}');
          }
          final end = (offset + 8000).clamp(0, text.length);
          content =
              '${text.substring(offset, end)}\n[字符 $offset～$end / ${text.length}]';
        default:
          throw ArgumentError('未知 action');
      }
      return ToolResult(
        toolCallId: toolCallId,
        toolName: name,
        content: content,
      );
    } catch (error) {
      return ToolResult(
        toolCallId: toolCallId,
        toolName: name,
        content: '$error',
        isError: true,
      );
    }
  }
}
