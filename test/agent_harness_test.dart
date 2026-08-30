import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/core/harness/agent_harness.dart';
import 'package:novelai_harness/core/harness/presets/agent_preset.dart';
import 'package:novelai_harness/core/harness/providers/llm_provider.dart';
import 'package:novelai_harness/core/harness/skills/skills.dart';
import 'package:novelai_harness/core/harness/tools/agent_tool.dart';
import 'package:novelai_harness/core/harness/types.dart';

class MockLlmProvider implements LlmProvider {
  final List<HarnessEvent> Function(
    List<AgentMessage> messages,
    List<AgentTool> tools,
  )
  onStream;

  MockLlmProvider(this.onStream);

  @override
  String get modelId => 'mock-model';

  @override
  Stream<HarnessEvent> streamChat({
    required List<AgentMessage> messages,
    required List<AgentTool> tools,
    double temperature = 0.7,
  }) async* {
    final events = onStream(messages, tools);
    for (final event in events) {
      yield event;
    }
  }
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

    test('Skill switching updates current system prompt', () {
      harness = AgentHarness(tools: tools);
      expect(harness.currentSkill.id, equals('v5-architect'));

      harness.setSkill(BuiltinSkills.danbooruTagMaster);
      expect(harness.currentSkill.id, equals('danbooru-tags'));
    });

    test('AgentHarness injects available_skills XML and filters tools', () async {
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
      final sysMsg =
          capturedMessages!.firstWhere((m) => m.role == AgentRole.system);
      expect(sysMsg.content, contains('<available_skills>'));
      expect(sysMsg.content, contains('v5-architect'));

      expect(capturedTools, isNotNull);
      expect(capturedTools!.any((t) => t.name == 'echo_test'), isTrue);
    });

    test('rewindToMessage truncates in-memory messages list accurately', () async {
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
    });

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
}

