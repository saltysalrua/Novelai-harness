import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/core/harness/agent_harness.dart';
import 'package:novelai_harness/core/harness/presets/agent_preset.dart';
import 'package:novelai_harness/core/harness/providers/llm_provider.dart';
import 'package:novelai_harness/core/harness/tools/agent_tool.dart';
import 'package:novelai_harness/core/harness/types.dart';

class _Provider implements LlmProvider {
  final Stream<HarnessEvent> Function() events;
  _Provider(this.events);
  @override
  String get modelId => 'mock';
  @override
  Stream<HarnessEvent> streamChat({
    required List<AgentMessage> messages,
    required List<AgentTool> tools,
    double temperature = 0.7,
    String? promptCacheKey,
  }) => events();
}

class _BlockedTool extends AgentTool {
  final started = Completer<void>();
  final result = Completer<ToolResult>();
  _BlockedTool()
    : super(name: 'blocked', label: 'blocked', description: '', parameters: {});
  @override
  Future<ToolResult> execute(String toolCallId, Map<String, dynamic> args) {
    started.complete();
    return result.future;
  }
}

void main() {
  test('首个流事件前也能中断', () async {
    var called = false;
    final harness = AgentHarness(
      tools: ToolRegistry(),
      provider: _Provider(() {
        called = true;
        return const Stream.empty();
      }),
    );
    final stream = harness.send('hello');
    harness.abort();
    await stream.drain<void>().timeout(const Duration(seconds: 1));
    expect(called, isFalse);
  });

  test('上游挂起时立即停止，保留半截正文，迟到输出不污染新会话', () async {
    final blocked = Completer<void>();
    final received = Completer<void>();
    Stream<HarnessEvent> source() async* {
      yield ContentDeltaEvent('半截');
      await blocked.future;
      yield ContentDeltaEvent('迟到文本');
    }

    final harness = AgentHarness(
      tools: ToolRegistry(),
      provider: _Provider(source),
    );
    final finished = harness.send('hello').forEach((event) {
      if (event is ContentDeltaEvent && !received.isCompleted) {
        received.complete();
      }
    });
    await received.future;
    harness.abort();
    await finished.timeout(const Duration(seconds: 1));
    expect(harness.messages.last.content, '半截');
    harness.setMessages([]);
    harness.provider = _Provider(() => Stream.value(ContentDeltaEvent('新回答')));
    await harness.send('new').drain<void>();
    blocked.complete();
    await Future<void>.delayed(Duration.zero);
    expect(harness.messages.map((m) => m.content), ['new', '新回答']);
  });

  test('取消工具等待并补齐工具结果，不等待已启动的外部操作', () async {
    final tool = _BlockedTool();
    final registry = ToolRegistry()..register(tool);
    final harness = AgentHarness(
      tools: registry,
      initialPreset: BuiltinPresets.v5Architect.copyWith(
        enabledToolNames: ['blocked'],
      ),
      provider: _Provider(
        () => Stream.value(
          ToolCallEvent(ToolCall(id: 'call', name: 'blocked', arguments: {})),
        ),
      ),
    );
    final finished = harness.send('tool').drain<void>();
    await tool.started.future.timeout(const Duration(seconds: 2));
    harness.abort();
    await finished.timeout(const Duration(seconds: 1));
    expect(harness.messages.last.role, AgentRole.tool);
    expect(harness.messages.last.toolCallId, 'call');
    expect(harness.messages.last.isError, isTrue);
    final count = harness.messages.length;
    tool.result.complete(ToolResult(toolCallId: 'call', content: '迟到结果'));
    await Future<void>.delayed(Duration.zero);
    expect(harness.messages.length, count);
  });

  test('中断退避不再发起重试', () async {
    var calls = 0;
    final retry = Completer<void>();
    final harness = AgentHarness(
      tools: ToolRegistry(),
      retryBaseDelay: const Duration(milliseconds: 50),
      provider: _Provider(() {
        calls++;
        return Stream.value(ErrorEvent('retry', transient: true));
      }),
    );
    final finished = harness.send('retry').forEach((event) {
      if (event is RetryEvent) retry.complete();
    });
    await retry.future;
    harness.abort();
    await finished.timeout(const Duration(seconds: 1));
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(calls, 1);
  });
}
