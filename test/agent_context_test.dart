import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/core/harness/agent_harness.dart';
import 'package:novelai_harness/core/harness/presets/agent_preset.dart';
import 'package:novelai_harness/core/harness/providers/llm_provider.dart';
import 'package:novelai_harness/core/harness/tools/agent_tool.dart';
import 'package:novelai_harness/core/harness/tools/context_memory_tool.dart';
import 'package:novelai_harness/core/harness/types.dart';

import 'agent_harness_test.dart' show MockLlmProvider;

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
}
