import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/core/harness/agent_harness.dart';
import 'package:novelai_harness/core/harness/providers/llm_provider.dart';
import 'package:novelai_harness/core/harness/skills/skills.dart';
import 'package:novelai_harness/core/harness/tools/agent_tool.dart';
import 'package:novelai_harness/core/harness/types.dart';

class MockLlmProvider implements LlmProvider {
  final List<HarnessEvent> Function(List<AgentMessage> messages, List<AgentTool> tools) onStream;

  MockLlmProvider(this.onStream);

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
              'text': {'type': 'string'}
            },
            'required': ['text'],
          },
        );

  @override
  Future<ToolResult> execute(String toolCallId, Map<String, dynamic> args) async {
    return ToolResult(
      toolCallId: toolCallId,
      content: 'Echo: ${args['text']}',
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
      expect(harness.messages.last.content, equals('Hello! How can I help you?'));
      expect(harness.messages.last.thoughts, equals('Thinking about response...'));
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
          return [
            ContentDeltaEvent('Tool execution completed.'),
          ];
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
  });
}
