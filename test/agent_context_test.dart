import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/core/harness/agent_harness.dart';
import 'package:novelai_harness/core/harness/presets/agent_preset.dart';
import 'package:novelai_harness/core/harness/providers/llm_provider.dart';
import 'package:novelai_harness/core/harness/reply_marker.dart';
import 'package:novelai_harness/core/harness/tools/agent_tool.dart';
import 'package:novelai_harness/core/harness/tools/context_memory_tool.dart';
import 'package:novelai_harness/core/harness/types.dart';

import 'agent_harness_test.dart' show MockLlmProvider, TestEchoTool;

class _SummaryProvider implements LlmProvider {
  final started = Completer<void>();
  final release = Completer<void>();
  int calls = 0;
  @override
  String get modelId => 'summary-model';
  @override
  Stream<HarnessEvent> streamChat({
    required List<AgentMessage> messages,
    required List<AgentTool> tools,
    double temperature = 0.7,
    String? promptCacheKey,
  }) async* {
    calls++;
    expect(tools, isEmpty);
    if (!started.isCompleted) started.complete();
    await release.future;
    yield ContentDeltaEvent('旧任务摘要');
    yield UsageEvent(const TokenUsage(input: 100, output: 10));
  }
}

AgentHarness _harness({LlmProvider? provider}) => AgentHarness(
  tools: ToolRegistry(),
  provider: provider ?? MockLlmProvider((_, _) => [ContentDeltaEvent('答复')]),
  initialPreset: const AgentPreset(
    id: 'test',
    name: 'test',
    description: '',
    systemPrompt: 'system',
    enabledSkillIds: [],
    enabledToolNames: ['context_memory'],
  ),
);

List<AgentMessage> _history({int length = 4000}) => [
  AgentMessage(id: 'u1', role: AgentRole.user, content: 'a' * length),
  AgentMessage(id: 'a1', role: AgentRole.assistant, content: 'b' * length),
  AgentMessage(id: 'u2', role: AgentRole.user, content: 'recent user'),
  AgentMessage(id: 'a2', role: AgentRole.assistant, content: 'recent answer'),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('后台请求超时保留上下文且关闭进行中标识', () async {
    final summary = _SummaryProvider();
    final h = _harness()
      ..compactionProvider = summary
      ..compactionTimeout = const Duration(milliseconds: 20);
    h.restoreMessages(_history());
    expect(await h.compactContext(force: true), isNull);
    expect(h.contextUsage.compacting, isFalse);
    expect(h.contextUsage.error, contains('压缩失败'));
    expect(h.compactionSummary, isNull);
    summary.release.complete();
    h.dispose();
  });

  test('压缩用量独立回调，未开启记忆工具不可越权写入', () async {
    final h = _harness();
    h.restoreMessages(_history());
    String? billedModel;
    h.compactionProvider = MockLlmProvider(
      (_, _) => [
        ContentDeltaEvent('摘要'),
        UsageEvent(const TokenUsage(input: 100, output: 10)),
      ],
    );
    h.onCompactionUsage = (usage, model) {
      billedModel = model;
      expect(usage.total, 110);
    };
    expect(await h.compactContext(force: true), isNotNull);
    expect(billedModel, 'mock-model');
    h.setPreset(
      const AgentPreset(
        id: 'restricted',
        name: 'restricted',
        description: '',
        systemPrompt: '',
        enabledToolNames: [],
      ),
    );
    final result = await ContextMemoryTool(
      h,
    ).execute('x', {'action': 'add_note', 'text': '越权'});
    expect(result.isError, isTrue);
    expect(h.memory.notes, isEmpty);
    h.dispose();
  });

  test('实际用量不重复累计系统开销，中文估算不是 chars/4', () async {
    final h = _harness(
      provider: MockLlmProvider(
        (_, _) => [
          ContentDeltaEvent('答复'),
          UsageEvent(const TokenUsage(input: 700, cacheRead: 200, output: 100)),
        ],
      ),
    );
    await h.send('问').toList();
    expect(h.contextUsage.tokens, 1000);
    h.memory.addNote('中文' * 100);
    h.memoryChanged();
    expect(h.contextUsage.tokens, greaterThan(200));
    expect(h.contextUsage.tokens, lessThan(1000));
    h.dispose();
  });

  test('自动后台压缩不阻塞主回复，压缩模型独立且单飞', () async {
    final summary = _SummaryProvider();
    final h = _harness()
      ..contextWindowTokens = 3300
      ..compactionReserveTokens = 300
      ..compactionKeepRecentTokens = 100
      ..compactionProvider = summary;
    h.restoreMessages(_history());
    final events = await h.send('新任务').toList();
    expect(events.whereType<TurnEndEvent>(), hasLength(1));
    await summary.started.future;
    expect(h.contextUsage.compacting, isTrue);
    final pending = h.compactContext(force: true);
    expect(summary.calls, 1);
    summary.release.complete();
    expect(await pending, isNotNull);
    await Future<void>.delayed(Duration.zero);
    expect(h.contextUsage.compacting, isFalse);
    expect(h.compactionSummary, '旧任务摘要');
    expect(h.messages.last.content, '答复');
    h.dispose();
  });

  test('切换会话或回溯会取消旧后台任务，晚到结果不得提交', () async {
    for (final rewind in [false, true]) {
      final summary = _SummaryProvider();
      final h = _harness()..compactionProvider = summary;
      h.restoreMessages(_history());
      final pending = h.compactContext(force: true);
      await summary.started.future;
      if (rewind) {
        h.rewindToMessage('a1');
      } else {
        h.setMessages([]);
      }
      summary.release.complete();
      expect(await pending, isNull);
      expect(h.compactionSummary, isNull);
      expect(h.contextUsage.compacting, isFalse);
      h.dispose();
    }
  });

  test('压缩错误保留原文；到达硬阈值不发送超窗主请求', () async {
    var mainCalls = 0;
    final h =
        _harness(
            provider: MockLlmProvider((_, _) {
              mainCalls++;
              return [ContentDeltaEvent('答复')];
            }),
          )
          ..contextWindowTokens = 1000
          ..compactionKeepRecentTokens = 100
          ..compactionProvider = MockLlmProvider(
            (_, _) => [const ErrorEvent('失败')],
          );
    h.restoreMessages(_history());
    final events = await h.send('新任务').toList();
    expect(mainCalls, 0);
    expect(events.whereType<ErrorEvent>(), isNotEmpty);
    expect(h.compactionSummary, isNull);
    expect(h.contextUsage.error, contains('压缩失败'));
    expect(h.messages, hasLength(5));
    h.dispose();
  });

  test('笔记增删、编号释放与原文读取保持工具调用完整', () async {
    List<AgentMessage> request = [];
    final h = _harness(
      provider: MockLlmProvider((messages, _) {
        request = messages;
        return [ContentDeltaEvent('新答复')];
      }),
    );
    h.restoreMessages([
      AgentMessage(id: 'u1', role: AgentRole.user, content: '不可删除的用户约束'),
      AgentMessage(
        id: 'a1',
        role: AgentRole.assistant,
        content: '旧回复',
        toolCalls: [const ToolCall(id: 'call', name: 'test', arguments: {})],
      ),
      AgentMessage(
        id: 't1',
        role: AgentRole.tool,
        toolCallId: 'call',
        content: '旧工具结果',
      ),
      AgentMessage(id: 'u2', role: AgentRole.user, content: '新任务'),
    ]);
    final tool = ContextMemoryTool(h);
    expect(
      (await tool.execute('x', {'action': 'add_note', 'text': '重要结论'})).isError,
      isFalse,
    );
    expect(
      (await tool.execute('x', {'action': 'forget_reply', 'id': 1})).isError,
      isFalse,
    );
    await h.send('继续').toList();
    expect(request.any((m) => m.id == 't1'), isFalse);
    expect(request.firstWhere((m) => m.id == 'a1').toolCalls, isNull);
    expect(request.any((m) => m.content.contains('重要结论')), isTrue);
    expect(request.any((m) => m.content == '不可删除的用户约束'), isTrue);
    expect(h.messages.any((m) => m.content == '旧工具结果'), isTrue);
    final read = await tool.execute('x', {'action': 'read_reply', 'id': 1});
    expect(read.content, contains('旧工具结果'));
    // 工具结果不得带 [回复 #N] 标记形态，避免它在对话气泡里以标记样式露面
    expect(read.content.contains('[回复 #'), isFalse);
    expect(h.messages.last.replyNumber, 2);
    expect(
      (await tool.execute('x', {'action': 'delete_note', 'id': 1})).isError,
      isFalse,
    );
    expect(h.memory.notes, isEmpty);
    expect(
      (await tool.execute('x', {'action': 'forget_reply', 'id': 2})).isError,
      isTrue,
    );
    expect(
      (await tool.execute('x', {'action': 'delete_note', 'id': 99})).isError,
      isTrue,
    );
    h.dispose();
  });

  test('批量清理：ids 一次释放复数回复、复数笔记与复数读取', () async {
    final h = _harness();
    h.restoreMessages([
      AgentMessage(id: 'u1', role: AgentRole.user, content: '第一轮要求'),
      AgentMessage(id: 'a1', role: AgentRole.assistant, content: '旧回复一'),
      AgentMessage(id: 'u2', role: AgentRole.user, content: '第二轮要求'),
      AgentMessage(id: 'a2', role: AgentRole.assistant, content: '旧回复二'),
      AgentMessage(id: 'u3', role: AgentRole.user, content: '当前轮要求'),
    ]);
    final tool = ContextMemoryTool(h);

    // 复数笔记一次保存
    final added = await tool.execute('x', {
      'action': 'add_note',
      'texts': ['结论甲', '结论乙'],
    });
    expect(added.isError, isFalse);
    expect(h.memory.notes.length, 2);
    expect(added.content, contains('#1'));
    expect(added.content, contains('#2'));

    // 复数读取：一次拿到两条回复的原文
    final read = await tool.execute('x', {
      'action': 'read_reply',
      'ids': [1, 2],
    });
    expect(read.isError, isFalse);
    expect(read.content, contains('旧回复一'));
    expect(read.content, contains('旧回复二'));

    // 复数释放：不存在的编号只作为部分失败提示，不阻断本次调用
    final forgotten = await tool.execute('x', {
      'action': 'forget_reply',
      'ids': [1, 2, 99],
    });
    expect(forgotten.isError, isFalse);
    expect(h.memory.forgottenReplies, containsAll(<int>[1, 2]));
    expect(forgotten.content, contains('#99'));

    // 复数删除：仍保留编号与不存在的部分提示
    final removed = await tool.execute('x', {
      'action': 'delete_note',
      'ids': [1, 2],
    });
    expect(removed.isError, isFalse);
    expect(h.memory.notes, isEmpty);

    // 全部失败（不存在或已进入摘要）的批量释放仍按错误返回
    final allBlocked = await tool.execute('x', {
      'action': 'forget_reply',
      'ids': [98, 99],
    });
    expect(allBlocked.isError, isTrue);
    expect(allBlocked.content, contains('没有可释放的回复'));

    // 全部不存在的批量删除同样报错
    final missing = await tool.execute('x', {
      'action': 'delete_note',
      'ids': [42, 43],
    });
    expect(missing.isError, isTrue);
    h.dispose();
  });

  test('请求侧回复编号只保留一层，入库剥离模型回显', () async {
    List<AgentMessage> request = [];
    final h = _harness(
      provider: MockLlmProvider((messages, _) {
        request = messages;
        return [ContentDeltaEvent('[回复 #9]\n[回复 #9]\n正文')];
      }),
    );
    h.restoreMessages([
      AgentMessage(id: 'u1', role: AgentRole.user, content: '问'),
      AgentMessage(
        id: 'a1',
        role: AgentRole.assistant,
        content: '[回复 #1]\n[回复 #1]\n旧正文',
      ),
    ]);
    expect(h.messages.firstWhere((m) => m.id == 'a1').content, '旧正文');
    await h.send('继续').toList();
    final old = request.firstWhere((m) => m.id == 'a1');
    expect(RegExp(r'\[回复 #').allMatches(old.content).length, 1);
    expect(old.content, '[回复 #1]\n旧正文');
    expect(h.messages.last.content, '正文');
    expect(h.messages.last.replyNumber, 2);
    h.dispose();
  });

  test('正文任意位置的回复标记都被全量剥离 (变体/加粗/缺括号)', () {
    expect(ReplyMarker.strip('[回复 #1]\n正文'), '正文');
    expect(ReplyMarker.strip('[回复 #1]\n\n[回复 #1]\n正文'), '正文');
    expect(ReplyMarker.strip('正文\n[回复 #2]\n更多'), '正文\n\n更多');
    expect(ReplyMarker.strip('**[回复 #3]** 正文'), '正文');
    expect(ReplyMarker.strip('[回复#4]正文'), '正文');
    expect(ReplyMarker.strip('[回复 #5'), '');
    expect(ReplyMarker.strip('先看[回复 #9]再回答'), '先看再回答');
    expect(ReplyMarker.strip('没有标记的正文 #5'), '没有标记的正文 #5');
    // AgentHarness 上的同名静态方法保持向后兼容
    expect(AgentHarness.stripReplyMarkers('[回复 #1]\n正文'), '正文');
  });

  test('标记被切碎后剩下的孤立右括号也一并清掉 (仅括号数失衡时)', () {
    expect(ReplyMarker.strip(']\n正文'), '正文');
    expect(ReplyMarker.strip('正文]'), '正文');
    expect(ReplyMarker.strip(']** 正文'), '正文');
    expect(ReplyMarker.strip('**[回复 #7]** 好的]'), '好的');
    // 成对括号的正常正文不能被动，包括 Markdown 链接与引用
    expect(ReplyMarker.strip('参考 [3]'), '参考 [3]');
    expect(ReplyMarker.strip('见 [文档](https://x.y)'), '见 [文档](https://x.y)');
    expect(ReplyMarker.strip('正文**'), '正文**');
    expect(ReplyMarker.strip('- [x] 已完成\n- [ ] 未完成'), '- [x] 已完成\n- [ ] 未完成');
  });

  test('恢复旧会话时清洗正文里任意位置的回复标记', () {
    final h = _harness();
    h.restoreMessages([
      AgentMessage(id: 'u1', role: AgentRole.user, content: '问'),
      AgentMessage(
        id: 'a1',
        role: AgentRole.assistant,
        content: '[回复 #1]正文\n[回复 #1]\n[回复 #1]更多',
      ),
    ]);
    expect(h.messages[1].content, '正文\n\n更多');
    h.dispose();
  });

  test('流式增量与落库正文都不留回复标记残渣 (任意分块方式)', () async {
    // 流式与整段剥离的分工：
    // - 带右括号的完整标记：任何时候都可即时剥；
    // - 「[回复 #7」这类缺括号形态：只有确定后面不会再补上括号时才能剥，
    //   否则晚到的「]」会变成孤立残渣（旧版就是在这里漏出「]」的）。
    Future<(String, String)> run(List<String> chunks) async {
      final h = _harness(
        provider: MockLlmProvider(
          (_, _) => [for (final c in chunks) ContentDeltaEvent(c)],
        ),
      );
      final events = await h.send('hi').toList();
      final streamed = events
          .whereType<ContentDeltaEvent>()
          .map((e) => e.delta)
          .join();
      final stored = h.messages.last.content;
      h.dispose();
      return (streamed, stored);
    }

    const cases = <List<String>, String>{
      ['[回复 #7]\n好的']: '好的',
      ['[回复 #7', ']', '\n好的']: '好的',
      ['[回', '复 #7]', '\n好的']: '好的',
      ['[回复 #7 ', '好的']: '好的',
      ['好的[回复 #7]']: '好的',
      ['好的', '[回复 #7', ']']: '好的',
      ['**[回复 #7', ']**', ' 好的']: '好的',
      ['[回复 #3]', '\n一\n', '[回复 #4', ']', '\n二']: '一\n\n二',
      ['[回复　＃１２]\n好的']: '好的',
      ['[回', '复 #7]\n好的，继续', '[回复 #8]', '完成']: '好的，继续完成',
      // 被流截断的半个标记：整段丢弃
      ['说明', '[回复 #12']: '说明',
      // 尾部的 `**` 是正常 Markdown，不能被当成残标吃掉
      ['正文**']: '正文**',
      // 切碎后只剩孤立右括号的残渣也不能漏
      ['好的[回复 #7', ']']: '好的',
      ['[回复 #8', ']', '\n结尾]']: '结尾',
    };

    for (final entry in cases.entries) {
      final (streamed, stored) = await run(entry.key);
      expect(streamed, entry.value, reason: '流式: ${entry.key}');
      expect(stored, entry.value, reason: '落库: ${entry.key}');
    }
  });

  test('多轮工具调用下标记不增殖：每个助手回复在请求侧只带一层标记', () async {
    final tools = ToolRegistry()..register(TestEchoTool());
    final snapshots = <List<AgentMessage>>[];
    final provider = MockLlmProvider((messages, _) {
      snapshots.add(messages);
      if (snapshots.length <= 3) {
        return [
          ContentDeltaEvent('[回复 #99]\n干活[回复 #99]\n'),
          ToolCallEvent(
            ToolCall(
              id: 'call_${snapshots.length}',
              name: 'echo_test',
              arguments: {'text': 'x'},
            ),
          ),
        ];
      }
      return [ContentDeltaEvent('[回复 #99]\n[回复 #99]\n最终答复')];
    });
    final h = AgentHarness(
      tools: tools,
      provider: provider,
      initialPreset: const AgentPreset(
        id: 'test',
        name: 'test',
        description: '',
        systemPrompt: 'system',
        enabledSkillIds: [],
        enabledToolNames: ['echo_test'],
      ),
    );
    final events = await h.send('开始').toList();

    // UI 侧：流式增量与落库正文都不含标记
    final streamed = events
        .whereType<ContentDeltaEvent>()
        .map((e) => e.delta)
        .join();
    expect(streamed.contains('回复 #'), isFalse);
    for (final m in h.messages) {
      expect(m.content.contains('回复 #'), isFalse, reason: m.id);
    }

    // 请求侧：每个助手回复恰好一层注入标记，不会越叠越多
    final marker = RegExp(r'\[回复 #\d+\]');
    for (final request in snapshots) {
      final assistants = request
          .where((m) => m.role == AgentRole.assistant)
          .toList();
      for (final m in assistants) {
        expect(
          marker.allMatches(m.content).length,
          1,
          reason: '回复 #${m.replyNumber}: ${m.content}',
        );
      }
    }
    h.dispose();
  });
}
