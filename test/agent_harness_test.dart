import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/core/harness/agent_harness.dart';
import 'package:novelai_harness/core/harness/presets/agent_preset.dart';
import 'package:novelai_harness/core/harness/providers/llm_provider.dart';
import 'package:novelai_harness/core/harness/session_recorder.dart';
import 'package:novelai_harness/core/harness/tools/agent_tool.dart';
import 'package:novelai_harness/core/harness/types.dart';

class MockLlmProvider implements LlmProvider {
  final List<HarnessEvent> Function(
    List<AgentMessage> messages,
    List<AgentTool> tools,
  )
  onStream;

  /// 最近一次 streamChat 收到的缓存路由键 (透传验证用)
  String? lastPromptCacheKey;

  /// streamChat 总调用次数 (重试验证用)
  int callCount = 0;

  /// 每次 streamChat 收到的工具列表快照 (收尾轮无工具验证用)
  final List<List<AgentTool>> receivedToolSets = [];

  MockLlmProvider(this.onStream);

  @override
  String get modelId => 'mock-model';

  @override
  Stream<HarnessEvent> streamChat({
    required List<AgentMessage> messages,
    required List<AgentTool> tools,
    double temperature = 0.7,
    String? promptCacheKey,
  }) async* {
    lastPromptCacheKey = promptCacheKey;
    callCount++;
    receivedToolSets.add(tools);
    final events = onStream(messages, tools);
    for (final event in events) {
      yield event;
    }
  }
}

class MockSessionRecorder implements SessionRecorder {
  final String? fixedSessionId;
  final List<AgentMessage> recorded = [];

  MockSessionRecorder(this.fixedSessionId);

  @override
  String? get sessionId => fixedSessionId;

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

class TestEchoTool extends AgentTool {
  TestEchoTool()
    : super(
        name: 'echo_test',
        label: 'Echo Test',
        description: 'Echoes back the input',
        parameters: {
          'type': 'object',
          'properties': {
            'text': {'type': 'string'},
          },
          'required': ['text'],
        },
      );

  @override
  Future<ToolResult> execute(
    String toolCallId,
    Map<String, dynamic> args,
  ) async {
    return ToolResult(toolCallId: toolCallId, content: 'Echo: ${args['text']}');
  }
}

/// 返回附带图片的测试工具 (验证工具结果图片的折叠行为)
class TestImageEchoTool extends AgentTool {
  TestImageEchoTool()
    : super(
        name: 'echo_test',
        label: 'Echo Image Test',
        description: 'Echoes back the input with an image',
        parameters: {
          'type': 'object',
          'properties': {
            'text': {'type': 'string'},
          },
          'required': ['text'],
        },
      );

  @override
  Future<ToolResult> execute(
    String toolCallId,
    Map<String, dynamic> args,
  ) async {
    return ToolResult(
      toolCallId: toolCallId,
      content: 'Echo: ${args['text']}',
      imageBase64: 'dG9vbF9pbWFnZQ==',
    );
  }
}

void main() {
  group('AgentHarness Loop Tests', () {
    late ToolRegistry tools;
    late AgentHarness harness;

    setUp(() {
      tools = ToolRegistry();
      tools.register(TestEchoTool());
    });

    test('AgentHarness simple chat response without tools', () async {
      final provider = MockLlmProvider((messages, tools) {
        return [
          ThoughtDeltaEvent('Thinking about response...'),
          ContentDeltaEvent('Hello! How can I help you?'),
        ];
      });

      harness = AgentHarness(tools: tools, provider: provider);
      final events = await harness.send('Hi').toList();

      expect(events.any((e) => e is ThoughtDeltaEvent), isTrue);
      expect(events.any((e) => e is ContentDeltaEvent), isTrue);
      expect(events.any((e) => e is TurnEndEvent), isTrue);
      expect(harness.messages.length, equals(2)); // user + assistant
      expect(
        harness.messages.last.content,
        equals('Hello! How can I help you?'),
      );
      expect(
        harness.messages.last.thoughts,
        equals('Thinking about response...'),
      );
    });

    test('AgentHarness executes tool call and completes loop', () async {
      int turn = 0;
      final provider = MockLlmProvider((messages, tools) {
        turn++;
        if (turn == 1) {
          // 第一轮返回工具调用
          return [
            ToolCallEvent(
              const ToolCall(
                id: 'call_1',
                name: 'echo_test',
                arguments: {'text': 'world'},
              ),
            ),
          ];
        } else {
          // 第二轮根据工具结果返回总结
          return [ContentDeltaEvent('Tool execution completed.')];
        }
      });

      harness = AgentHarness(tools: tools, provider: provider);
      final events = await harness.send('Echo test').toList();

      expect(events.any((e) => e is ToolCallEvent), isTrue);
      expect(events.any((e) => e is ToolResultEvent), isTrue);
      expect(events.any((e) => e is TurnEndEvent), isTrue);
      // messages: 1. UserMsg, 2. AsstMsg (with toolCalls), 3. ToolMsg (Echo: world), 4. AsstMsg (Tool execution completed.)
      expect(harness.messages.length, equals(4));
    });

    test('每轮工具循环均以 TurnStartEvent 开场 (流式缓冲复位契约)', () async {
      int turn = 0;
      final provider = MockLlmProvider((messages, tools) {
        turn++;
        if (turn == 1) {
          return [
            ContentDeltaEvent('第一轮正文'),
            ToolCallEvent(
              const ToolCall(
                id: 'call_round',
                name: 'echo_test',
                arguments: {'text': 'x'},
              ),
            ),
          ];
        }
        return [ContentDeltaEvent('第二轮正文')];
      });

      harness = AgentHarness(tools: tools, provider: provider);
      final events = await harness.send('multi').toList();

      // 模拟 ViewModel 消费行为：TurnStartEvent 时复位流式缓冲
      String buffer = '';
      for (final e in events) {
        if (e is TurnStartEvent) {
          buffer = '';
        } else if (e is ContentDeltaEvent) {
          buffer += e.delta;
        }
      }

      // 两轮各自发出 TurnStartEvent，缓冲里只留最近一轮的正文，
      // 不会把第一轮文本残留拼接成“重复语句”
      expect(events.whereType<TurnStartEvent>().length, equals(2));
      expect(buffer, equals('第二轮正文'));
      expect(harness.messages.last.content, equals('第二轮正文'));
      // 两轮分别落盘为独立 assistant 消息，内容不重复
      final round1 = harness.messages.where(
        (m) => m.role == AgentRole.assistant && m.content == '第一轮正文',
      );
      expect(round1, isNotEmpty);
    });

    test(
      'buildSystemPrompt injects preset prompt and available_skills XML',
      () {
        final harness = AgentHarness(tools: tools);
        final prompt = harness.buildSystemPrompt(BuiltinPresets.v5Architect);

        expect(prompt, startsWith('你是由 NovelAI Harness 驱动'));
        expect(prompt, contains('<available_skills>'));
        expect(prompt, contains('<name>v5-architect</name>'));
        expect(prompt, contains('load_skill'));
      },
    );

    test(
      'AgentHarness passes recorder sessionId as prompt cache key',
      () async {
        final provider = MockLlmProvider((messages, tools) {
          return [ContentDeltaEvent('OK')];
        });
        final recorder = MockSessionRecorder('session-uuid-1234');

        harness = AgentHarness(
          tools: tools,
          provider: provider,
          recorder: recorder,
        );
        await harness.send('Hi').toList();

        expect(provider.lastPromptCacheKey, equals('session-uuid-1234'));
      },
    );

    test(
      'AgentHarness injects available_skills XML and filters tools',
      () async {
        List<AgentMessage>? capturedMessages;
        List<AgentTool>? capturedTools;

        final provider = MockLlmProvider((messages, tools) {
          capturedMessages = messages;
          capturedTools = tools;
          return [ContentDeltaEvent('Done')];
        });

        final testPreset = AgentPreset(
          id: 'test_preset',
          name: 'Test Preset',
          description: '',
          systemPrompt: 'System Instruction',
          enabledSkillIds: ['v5-architect'],
          enabledToolNames: ['echo_test'],
          allowedModifiableParams: [],
        );

        harness = AgentHarness(
          tools: tools,
          provider: provider,
          initialPreset: testPreset,
        );
        await harness.send('Hi').toList();

        expect(capturedMessages, isNotNull);
        final sysMsg = capturedMessages!.firstWhere(
          (m) => m.role == AgentRole.system,
        );
        expect(sysMsg.content, contains('<available_skills>'));
        expect(sysMsg.content, contains('v5-architect'));

        expect(capturedTools, isNotNull);
        expect(capturedTools!.any((t) => t.name == 'echo_test'), isTrue);
      },
    );

    test(
      'rewindToMessage truncates in-memory messages list accurately',
      () async {
        harness = AgentHarness(tools: tools);
        harness.restoreMessages([
          AgentMessage(id: 'm1', role: AgentRole.user, content: 'Q1'),
          AgentMessage(id: 'm2', role: AgentRole.assistant, content: 'A1'),
          AgentMessage(id: 'm3', role: AgentRole.user, content: 'Q2'),
          AgentMessage(id: 'm4', role: AgentRole.assistant, content: 'A2'),
        ]);

        expect(harness.messages.length, equals(4));

        // 回溯至 m2 (保留 m1, m2)
        final success = harness.rewindToMessage('m2');
        expect(success, isTrue);
        expect(harness.messages.length, equals(2));
        expect(harness.messages.map((m) => m.id), equals(['m1', 'm2']));

        // 不存在的 ID 返回 false
        expect(harness.rewindToMessage('non_existent'), isFalse);
      },
    );

    test('setMessages replaces all messages', () {
      harness = AgentHarness(tools: tools);
      harness.restoreMessages([
        AgentMessage(id: 'old', role: AgentRole.user, content: 'Old'),
      ]);
      expect(harness.messages.length, equals(1));

      harness.setMessages([
        AgentMessage(id: 'new_1', role: AgentRole.user, content: 'New 1'),
        AgentMessage(id: 'new_2', role: AgentRole.assistant, content: 'New 2'),
      ]);
      expect(harness.messages.length, equals(2));
      expect(harness.messages.first.content, equals('New 1'));
    });
  });

  group('Agent 长程轮数与自动重试', () {
    late ToolRegistry tools;

    setUp(() {
      tools = ToolRegistry();
      tools.register(TestEchoTool());
    });

    /// 构建零退避的测试 harness
    AgentHarness buildHarness(
      MockLlmProvider provider, {
      int? maxTurns,
      AgentPreset? preset,
    }) {
      return AgentHarness(
        tools: tools,
        provider: provider,
        maxTurns: maxTurns ?? 30,
        retryBaseDelay: Duration.zero,
        initialPreset: preset,
      );
    }

    test('瞬态错误自动指数退避重试并最终成功', () async {
      int calls = 0;
      final provider = MockLlmProvider((messages, toolList) {
        calls++;
        if (calls == 1) {
          return [const ErrorEvent('HTTP 429', transient: true)];
        }
        return [ContentDeltaEvent('重试后成功')];
      });
      final harness = buildHarness(provider);
      final events = await harness.send('Hi').toList();

      // 首次失败后发出 RetryEvent，第二次尝试成功
      expect(provider.callCount, equals(2));
      final retries = events.whereType<RetryEvent>().toList();
      expect(retries.length, equals(1));
      expect(retries.first.attempt, equals(2));
      expect(retries.first.reason, contains('429'));
      // 重试前 TurnStartEvent 重发，流式气泡复位
      expect(events.whereType<TurnStartEvent>().length, equals(2));
      // 无 ErrorEvent (可重试错误不直接透传)
      expect(events.whereType<ErrorEvent>(), isEmpty);
      expect(events.any((e) => e is TurnEndEvent), isTrue);
      expect(harness.messages.last.content, equals('重试后成功'));
    });

    test('非瞬态错误不重试，直接终止并保留用户消息', () async {
      final provider = MockLlmProvider((messages, toolList) {
        return [const ErrorEvent('HTTP 401 未授权')];
      });
      final harness = buildHarness(provider);
      final events = await harness.send('Hi').toList();

      expect(provider.callCount, equals(1));
      expect(events.whereType<RetryEvent>(), isEmpty);
      final errors = events.whereType<ErrorEvent>().toList();
      expect(errors.length, equals(1));
      expect(errors.first.error, contains('401'));
      // 半截内容不落盘：仅保留用户消息
      expect(
        harness.messages.where((m) => m.role == AgentRole.assistant),
        isEmpty,
      );
    });

    test('瞬态错误重试预算耗尽后报错终止', () async {
      final provider = MockLlmProvider((messages, toolList) {
        return [const ErrorEvent('网络请求异常: connection reset', transient: true)];
      });
      final harness = buildHarness(provider);
      final events = await harness.send('Hi').toList();

      // 默认 3 次尝试预算全部用完
      expect(provider.callCount, equals(3));
      expect(events.whereType<RetryEvent>().length, equals(2));
      final errors = events.whereType<ErrorEvent>().toList();
      expect(errors.length, equals(1));
      expect(errors.first.error, contains('连续 3 次'));
    });

    test('空响应占用重试预算，再次尝试成功', () async {
      int calls = 0;
      final provider = MockLlmProvider((messages, toolList) {
        calls++;
        if (calls == 1) return const [];
        return [ContentDeltaEvent('有内容了')];
      });
      final harness = buildHarness(provider);
      final events = await harness.send('Hi').toList();

      expect(provider.callCount, equals(2));
      final retries = events.whereType<RetryEvent>().toList();
      expect(retries.length, equals(1));
      expect(retries.first.reason, contains('空响应'));
      expect(events.any((e) => e is TurnEndEvent), isTrue);
      expect(harness.messages.last.content, equals('有内容了'));
    });

    test('工具轮数达到上限后注入收尾提示并强制无工具总结', () async {
      // 预设需显式开放 echo_test，否则工具白名单为空，首轮即无工具可用
      final testPreset = AgentPreset(
        id: 'loop_test_preset',
        name: 'Loop Test',
        description: '',
        systemPrompt: 'System',
        enabledToolNames: ['echo_test'],
      );
      final provider = MockLlmProvider((messages, toolList) {
        // 前两轮持续请求工具；收尾轮 (无工具可用) 给出最终回答
        if (toolList.isEmpty) {
          return [ContentDeltaEvent('这是最终总结。')];
        }
        return [
          ToolCallEvent(
            const ToolCall(
              id: 'call_loop',
              name: 'echo_test',
              arguments: {'text': 'x'},
            ),
          ),
        ];
      });
      final harness = buildHarness(provider, maxTurns: 2, preset: testPreset);
      final events = await harness.send('loop').toList();

      // 两轮工具 + 一轮收尾总结
      expect(provider.callCount, equals(3));
      // 前两轮工具可用，收尾轮工具列表必须为空 (强制总结)
      expect(provider.receivedToolSets.first, isNotEmpty);
      expect(provider.receivedToolSets[1], isNotEmpty);
      expect(provider.receivedToolSets.last, isEmpty);
      // 注入了轮数上限收尾提示 (user 角色)
      final nudge = harness.messages.firstWhere(
        (m) => m.role == AgentRole.user && m.content.contains('最大工具调用轮数上限'),
      );
      expect(nudge.content, contains('不要再调用任何工具'));
      // 对话以收尾回答结束，而不是悬挂的工具结果
      expect(harness.messages.last.role, equals(AgentRole.assistant));
      expect(harness.messages.last.content, equals('这是最终总结。'));
      expect(events.any((e) => e is TurnEndEvent), isTrue);
      // 收尾提示位于最后一个工具结果之后
      final nudgeIdx = harness.messages.indexOf(nudge);
      final lastToolResultIdx = harness.messages.lastIndexWhere(
        (m) => m.role == AgentRole.tool,
      );
      expect(nudgeIdx, greaterThan(lastToolResultIdx));
    });

    test('默认最大轮数为 30 且可通过配置覆盖', () {
      final provider = MockLlmProvider((m, t) => const []);
      final harness = AgentHarness(tools: tools, provider: provider);
      expect(harness.maxTurns, equals(30));
      expect(harness.maxRetryAttempts, equals(3));

      harness.maxTurns = 50;
      expect(harness.maxTurns, equals(50));
    });
  });

  group('图片一次性展示与占位符', () {
    late ToolRegistry tools;

    setUp(() {
      tools = ToolRegistry();
      tools.register(TestEchoTool());
    });

    test('用户图片只在本轮请求可见，后续轮次折叠为固定占位符', () async {
      final receivedBatches = <List<AgentMessage>>[];
      final provider = MockLlmProvider((messages, toolList) {
        receivedBatches.add(messages);
        return [ContentDeltaEvent('OK')];
      });
      final harness = AgentHarness(tools: tools, provider: provider);

      const img = AgentMessageImage(base64: 'aGk=');
      await harness.send('看这张图', images: [img]).toList();

      // 本轮请求：用户消息携带原图
      final firstUser = receivedBatches.first.firstWhere(
        (m) => m.role == AgentRole.user && m.content == '看这张图',
      );
      expect(firstUser.images.length, equals(1));
      expect(firstUser.images.first.base64, equals('aGk='));

      // 下一轮：旧图片折叠为固定占位符，不再发送图片数据
      await harness.send('再来一张').toList();
      final oldUser = receivedBatches.last.firstWhere(
        (m) => m.content.contains('看这张图'),
      );
      expect(oldUser.images, isEmpty);
      expect(oldUser.content, contains('图片附件已折叠'));

      // 占位文本必须逐字稳定 (保证提示缓存前缀不被击穿)
      await harness.send('第三张').toList();
      final again = receivedBatches.last.firstWhere(
        (m) => m.content.contains('看这张图'),
      );
      expect(again.content, equals(oldUser.content));

      // 会话消息流仍保留原图 (仅请求折叠)
      final storedUser = harness.messages.firstWhere(
        (m) => m.content == '看这张图',
      );
      expect(storedUser.images.length, equals(1));
    });

    test('工具结果图片同轮各次请求均可见，跨轮后折叠', () async {
      final receivedBatches = <List<AgentMessage>>[];
      int turn = 0;
      final provider = MockLlmProvider((messages, toolList) {
        receivedBatches.add(messages);
        turn++;
        if (turn == 1) {
          return [
            ToolCallEvent(
              const ToolCall(
                id: 'call_img',
                name: 'echo_test',
                arguments: {'text': 'x'},
              ),
            ),
          ];
        }
        return [ContentDeltaEvent('看完图片了')];
      });
      // 本测试需要返回图片的工具，单独构建注册表
      final imageTools = ToolRegistry()..register(TestImageEchoTool());
      final harness = AgentHarness(
        tools: imageTools,
        provider: provider,
        retryBaseDelay: Duration.zero,
        initialPreset: AgentPreset(
          id: 'p',
          name: 'P',
          description: '',
          systemPrompt: 'S',
          enabledToolNames: ['echo_test'],
        ),
      );

      await harness.send('看看结果').toList();

      // 同一轮的第二轮请求：工具结果携带图片 (本轮内可见)
      final toolMsg = receivedBatches[1].firstWhere(
        (m) => m.role == AgentRole.tool,
      );
      expect(toolMsg.imageBase64, isNotNull);

      // 下一轮发送：工具结果图片折叠为占位符
      await harness.send('继续').toList();
      final oldTool = receivedBatches.last.firstWhere(
        (m) => m.role == AgentRole.tool,
      );
      expect(oldTool.imageBase64, isNull);
      expect(oldTool.content, contains('图片附件已折叠'));

      // 会话消息流仍保留工具图片
      final storedTool = harness.messages.firstWhere(
        (m) => m.role == AgentRole.tool,
      );
      expect(storedTool.imageBase64, isNotNull);
    });

    test('恢复的历史消息图片不会重新发送 (启动续接场景)', () async {
      final receivedBatches = <List<AgentMessage>>[];
      final provider = MockLlmProvider((messages, toolList) {
        receivedBatches.add(messages);
        return [ContentDeltaEvent('OK')];
      });
      final harness = AgentHarness(tools: tools, provider: provider);
      harness.restoreMessages([
        AgentMessage(
          id: 'old_user',
          role: AgentRole.user,
          content: '昨天的图',
          images: const [AgentMessageImage(base64: 'b2xk')],
        ),
      ]);

      await harness.send('新问题').toList();

      final oldUser = receivedBatches.first.firstWhere(
        (m) => m.content.contains('昨天的图'),
      );
      expect(oldUser.images, isEmpty);
      expect(oldUser.content, contains('图片附件已折叠'));
    });
  });

  group('上下文自动压缩', () {
    late ToolRegistry tools;

    setUp(() {
      tools = ToolRegistry();
      tools.register(TestEchoTool());
    });

    /// 生成指定长度的填充文本
    String pad(int len) => 'x' * len;

    MockLlmProvider buildCompactionProvider(
      List<List<AgentMessage>> receivedBatches,
    ) {
      return MockLlmProvider((messages, toolList) {
        receivedBatches.add(messages);
        // 摘要请求 (包含 <conversation> 标签) 返回结构化摘要
        if (messages.any((m) => m.content.contains('<conversation>'))) {
          return [ContentDeltaEvent('## 目标\n生成一张插画\n## 关键上下文\n- 提示词: 1girl')];
        }
        return [ContentDeltaEvent('好的，继续')];
      });
    }

    test('上下文超过窗口阈值时自动压缩并注入摘要替身', () async {
      final receivedBatches = <List<AgentMessage>>[];
      final provider = buildCompactionProvider(receivedBatches);
      final harness =
          AgentHarness(
              tools: tools,
              provider: provider,
              initialPreset: AgentPreset(
                id: 'p',
                name: 'P',
                description: '',
                systemPrompt: 'S',
              ),
            )
            ..contextWindowTokens = 3000
            ..compactionReserveTokens = 1000
            ..compactionKeepRecentTokens = 100;

      // 预置一段超阈值的历史 (每条 400 字符 ≈ 100 tokens)
      harness.restoreMessages([
        AgentMessage(id: 'm1', role: AgentRole.user, content: pad(400)),
        AgentMessage(id: 'm2', role: AgentRole.assistant, content: pad(400)),
        AgentMessage(id: 'm3', role: AgentRole.user, content: pad(400)),
        AgentMessage(id: 'm4', role: AgentRole.assistant, content: pad(400)),
      ]);

      final events = await harness.send('新问题').toList();

      // 自动压缩已触发并发出事件
      final compaction = events.whereType<CompactionEvent>().toList();
      expect(compaction, isNotEmpty);
      expect(compaction.first.summary, contains('生成一张插画'));
      expect(harness.isCompacted, isTrue);

      // 主请求携带摘要替身与近期窗口，且不再携带被压缩的旧消息
      final mainRequest = receivedBatches.firstWhere(
        (b) => b.any((m) => m.content.contains('新问题')),
      );
      expect(mainRequest.any((m) => m.content.contains('更早内容的压缩摘要')), isTrue);
      // m1 (被压缩) 不应出现在请求里；m4 (保留窗口) 与新问题应在
      expect(mainRequest.any((m) => m.id == 'm1'), isFalse);
      expect(mainRequest.any((m) => m.id == 'm4'), isTrue);
      expect(
        mainRequest.any((m) => m.role == AgentRole.user && m.content == '新问题'),
        isTrue,
      );

      // 原始消息仍完整保留在消息流中
      expect(harness.messages.any((m) => m.id == 'm1'), isTrue);
      expect(harness.messages.length, equals(6)); // 4 历史 + user + assistant
    });

    test('强制压缩保留最后一轮 user 对话，后续请求携带摘要', () async {
      final receivedBatches = <List<AgentMessage>>[];
      final provider = buildCompactionProvider(receivedBatches);
      final harness = AgentHarness(
        tools: tools,
        provider: provider,
        initialPreset: AgentPreset(
          id: 'p',
          name: 'P',
          description: '',
          systemPrompt: 'S',
        ),
      );
      harness.restoreMessages([
        AgentMessage(id: 'm1', role: AgentRole.user, content: '第一问'),
        AgentMessage(id: 'm2', role: AgentRole.assistant, content: '第一答'),
        AgentMessage(id: 'm3', role: AgentRole.user, content: '第二问'),
        AgentMessage(id: 'm4', role: AgentRole.assistant, content: '第二答'),
      ]);

      final evt = await harness.compactContext(force: true);
      expect(evt, isNotNull);
      expect(harness.isCompacted, isTrue);
      expect(harness.messages.length, equals(4));

      final events = await harness.send('第三问').toList();
      expect(events.whereType<CompactionEvent>(), isEmpty);
      // 第三问轮次：请求里应有 m3/m4 + 摘要替身，无 m1/m2
      final mainRequest = receivedBatches.firstWhere(
        (b) => b.any((m) => m.content.contains('第三问')),
      );
      expect(mainRequest.any((m) => m.id == 'm1'), isFalse);
      expect(mainRequest.any((m) => m.id == 'm2'), isFalse);
      expect(mainRequest.any((m) => m.id == 'm3'), isTrue);
      expect(mainRequest.any((m) => m.id == 'm4'), isTrue);
      expect(mainRequest.any((m) => m.content.contains('更早内容的压缩摘要')), isTrue);
    });

    test('摘要生成失败时放弃压缩，不破坏现有上下文', () async {
      final provider = MockLlmProvider((messages, toolList) {
        if (messages.any((m) => m.content.contains('<conversation>'))) {
          return [const ErrorEvent('摘要接口异常')];
        }
        return [ContentDeltaEvent('回答')];
      });
      final harness = AgentHarness(tools: tools, provider: provider)
        ..contextWindowTokens = 1000
        ..compactionReserveTokens = 500
        ..compactionKeepRecentTokens = 50;
      harness.restoreMessages([
        AgentMessage(id: 'm1', role: AgentRole.user, content: pad(400)),
        AgentMessage(id: 'm2', role: AgentRole.assistant, content: pad(400)),
        AgentMessage(id: 'm3', role: AgentRole.user, content: pad(400)),
        AgentMessage(id: 'm4', role: AgentRole.assistant, content: pad(400)),
      ]);

      final evt = await harness.compactContext(force: true);
      expect(evt, isNull);
      expect(harness.isCompacted, isFalse);
      expect(harness.messages.length, equals(4));
    });

    test('回溯到压缩窗口之外时重置压缩状态', () async {
      final provider = buildCompactionProvider([]);
      final harness = AgentHarness(tools: tools, provider: provider);
      harness.restoreMessages([
        AgentMessage(id: 'm1', role: AgentRole.user, content: '第一问'),
        AgentMessage(id: 'm2', role: AgentRole.assistant, content: '第一答'),
        AgentMessage(id: 'm3', role: AgentRole.user, content: '第二问'),
        AgentMessage(id: 'm4', role: AgentRole.assistant, content: '第二答'),
      ]);

      final evt = await harness.compactContext(force: true);
      expect(evt, isNotNull);
      expect(harness.isCompacted, isTrue);

      // 回溯到 m2 (保留前两条，落在压缩窗口之外) → 压缩状态重置
      expect(harness.rewindToMessage('m2'), isTrue);
      expect(harness.isCompacted, isFalse);
      expect(harness.messages.length, equals(2));
    });

    test('单一轮次对话无法压缩 (无更早内容)', () async {
      final provider = buildCompactionProvider([]);
      final harness = AgentHarness(tools: tools, provider: provider);
      harness.restoreMessages([
        AgentMessage(id: 'm1', role: AgentRole.user, content: '唯一一问'),
      ]);
      final evt = await harness.compactContext(force: true);
      expect(evt, isNull);
      expect(harness.isCompacted, isFalse);
    });
  });
}
