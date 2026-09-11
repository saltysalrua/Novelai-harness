import 'dart:convert';
import '../agent_harness.dart';
import '../types.dart';
import 'agent_tool.dart';

/// 笔记写入与请求侧释放统一经 Harness 状态入口，原始历史只读。
///
/// 所有写操作都同时接受单数与复数参数 (`text`/`texts`、`id`/`ids`)，
/// 一次调用即可处理多条笔记或复数回复，避免逐条往返。
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
            'read_reply 按编号分页读取原文。'
            '批量操作请直接用 ids / texts 数组一次清理复数条目，不要逐条多次调用。'
            '笔记最多64条，每条2000字符。',
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
            'text': {'type': 'string', 'description': '单条笔记内容'},
            'texts': {
              'type': 'array',
              'items': {'type': 'string'},
              'description': '批量保存的多条笔记内容（与 text 可并用）',
            },
            'id': {
              'type': 'integer',
              'minimum': 1,
              'description': '单个笔记ID或回复编号',
            },
            'ids': {
              'type': 'array',
              'items': {'type': 'integer', 'minimum': 1},
              'description':
                  '批量条目列表：delete_note 为笔记ID，forget_reply / read_reply 为回复编号'
                  '（与 id 可并用，一次调用处理多条）',
            },
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
          content = _addNotes(args);
        case 'delete_note':
          content = _deleteNotes(args);
        case 'forget_reply':
          final ids = _resolveIds(args);
          if (ids.isEmpty) throw ArgumentError('需要回复编号 id 或 ids');
          content = harness.forgetReplies(ids);
        case 'read_reply':
          content = _readReplies(args, offset);
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

  /// 汇总 `text` 与 `texts` 两个参数并逐条保存，单条失败不影响其余
  String _addNotes(Map<String, dynamic> args) {
    final texts = <String>[];
    if (args['text'] != null) {
      final raw = args['text'];
      if (raw is! String) throw ArgumentError('text 必须是字符串');
      texts.add(raw);
    }
    final many = args['texts'];
    if (many != null) {
      if (many is! List) throw ArgumentError('texts 必须是字符串数组');
      for (final item in many) {
        if (item is! String) throw ArgumentError('texts 必须是字符串数组');
        texts.add(item);
      }
    }
    if (texts.isEmpty) throw ArgumentError('需要 text 或 texts');

    final saved = <int>[];
    final failed = <String>[];
    for (final text in texts) {
      try {
        saved.add(harness.memory.addNote(text));
      } catch (error) {
        failed.add('$error');
      }
    }
    if (saved.isEmpty) throw StateError(failed.first);
    harness.memoryChanged();
    final buffer = StringBuffer('已保存笔记 ${saved.map((n) => '#$n').join('、')}');
    if (failed.isNotEmpty) {
      buffer.write('；${failed.length} 条失败：${failed.first}');
    }
    return buffer.toString();
  }

  /// 批量删除笔记，全部不存在时按错误返回
  String _deleteNotes(Map<String, dynamic> args) {
    final ids = _resolveIds(args);
    if (ids.isEmpty) throw ArgumentError('需要笔记 id 或 ids');
    final removed = harness.memory.deleteNotes(ids);
    if (removed.isEmpty) {
      throw ArgumentError('笔记不存在：${ids.map((i) => '#$i').join('、')}');
    }
    harness.memoryChanged();
    final missing = ids.where((i) => !removed.contains(i)).toList();
    final buffer = StringBuffer('已删除笔记 ${removed.map((i) => '#$i').join('、')}');
    if (missing.isNotEmpty) {
      buffer.write('；未找到 ${missing.map((i) => '#$i').join('、')}');
    }
    return buffer.toString();
  }

  /// 按编号读取回复原文，支持一次读取复数回复
  String _readReplies(Map<String, dynamic> args, int offset) {
    final ids = _resolveIds(args);
    if (ids.isEmpty) throw ArgumentError('需要回复编号 id 或 ids');
    final missing = <int>[];
    final blocks = <String>[];
    for (final id in ids) {
      final text = _replyText(id);
      if (text == null) {
        missing.add(id);
        continue;
      }
      blocks.add(
        ids.length == 1 ? '回复 #$id 原文:\n$text' : '===== 回复 #$id =====\n$text',
      );
    }
    if (blocks.isEmpty) {
      throw ArgumentError('回复不存在：${missing.map((i) => '#$i').join('、')}');
    }
    final full = blocks.join('\n\n');
    if (offset > full.length) {
      throw ArgumentError('offset 超出原文长度 ${full.length}');
    }
    final end = (offset + 8000).clamp(0, full.length);
    return '${full.substring(offset, end)}\n[字符 $offset～$end / ${full.length}]'
        '${missing.isEmpty ? '' : '\n未找到：${missing.map((i) => '#$i').join('、')}'}';
  }

  /// 单条回复的完整原文 (正文 + 工具调用 + 工具结果)，不存在时返回 null
  String? _replyText(int id) {
    final message = harness.messages
        .where((m) => m.replyNumber == id)
        .firstOrNull;
    if (message == null) return null;
    final calls = message.toolCalls ?? const <ToolCall>[];
    final callIds = calls.map((c) => c.id).toSet();
    final results = harness.messages
        .where(
          (m) => m.role == AgentRole.tool && callIds.contains(m.toolCallId),
        )
        .map((m) => m.content)
        .join('\n');
    return [
      message.content,
      ...calls.map((c) => jsonEncode(c.toOpenAiJson())),
      if (results.isNotEmpty) results,
    ].join('\n');
  }

  /// 汇总 `id` 与 `ids` 两个参数为去重升序的正整数列表
  List<int> _resolveIds(Map<String, dynamic> args) {
    final result = <int>{};
    if (args['id'] != null) result.add(_asPositiveInt(args['id'], 'id'));
    final many = args['ids'];
    if (many != null) {
      if (many is! List) throw ArgumentError('ids 必须是整数数组');
      for (final item in many) {
        result.add(_asPositiveInt(item, 'ids'));
      }
    }
    return result.toList()..sort();
  }

  static int _asPositiveInt(Object? raw, String key) {
    final value = switch (raw) {
      final int v => v,
      final num v => v.toInt(),
      final String v => int.tryParse(v.trim()) ?? -1,
      _ => -1,
    };
    if (value < 1) throw ArgumentError('$key 必须是正整数（或正整数数组）');
    return value;
  }
}
