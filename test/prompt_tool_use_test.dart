import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:novelai_harness/core/harness/agent_harness.dart';
import 'package:novelai_harness/core/harness/presets/agent_preset.dart';
import 'package:novelai_harness/core/harness/providers/openai_provider.dart';
import 'package:novelai_harness/core/harness/providers/prompt_tool_codec.dart';
import 'package:novelai_harness/core/harness/providers/tool_call_ids.dart';
import 'package:novelai_harness/core/harness/tools/agent_tool.dart';
import 'package:novelai_harness/core/harness/types.dart';
import 'package:novelai_harness/data/models/llm_models.dart';
import 'package:novelai_harness/data/services/config_service.dart';
import 'package:novelai_harness/ui/features/settings/widgets/models_settings_tab.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _EchoTool extends AgentTool {
  _EchoTool()
    : super(
        name: 'echo',
        label: 'Echo',
        description: 'Echo text.',
        parameters: const {
          'type': 'object',
          'properties': {
            'text': {'type': 'string'},
          },
          'required': ['text'],
        },
      );
  int executions = 0;
  @override
  Future<ToolResult> execute(
    String toolCallId,
    Map<String, dynamic> args,
  ) async {
    executions++;
    return ToolResult(toolCallId: toolCallId, content: '${args['text']}');
  }
}

String _call(String text, {String name = 'echo'}) =>
    '<tool_call>${jsonEncode({
      'name': name,
      'arguments': {'text': text},
    })}</tool_call>';

http.StreamedResponse _sse(
  List<Map<String, Object?>> deltas, {
  bool done = true,
  String? reason,
}) {
  final chunks = [
    for (final delta in deltas)
      {
        'choices': [
          {'delta': delta},
        ],
      },
    if (reason != null)
      {
        'choices': [
          {'delta': <String, Object?>{}, 'finish_reason': reason},
        ],
      },
    {
      'choices': [],
      'usage': {'prompt_tokens': 100, 'completion_tokens': 20},
    },
  ];
  final text =
      '${chunks.map((c) => 'data: ${jsonEncode(c)}\n').join()}${done ? 'data: [DONE]\n' : ''}';
  return http.StreamedResponse(
    http.ByteStream.fromBytes(utf8.encode(text)),
    200,
  );
}

OpenAiCompatibleProvider _provider(http.Client client, {bool prompt = true}) =>
    OpenAiCompatibleProvider(
      baseUrl: 'https://relay.test/v1',
      apiKey: 'test',
      model: 'claude-test',
      promptToolUse: prompt,
      client: client,
    );

void main() {
  final tool = _EchoTool();

  test('供应商配置默认原生，开关往返/切换/持久化不丢失', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    const legacy = LlmProviderConfig(
      id: 'relay',
      name: 'Relay',
      models: [LlmModelConfig(id: 'claude', name: 'Claude')],
    );
    expect(legacy.promptToolUse, isFalse);
    expect(
      LlmProviderConfig.fromJson(
        legacy.toJson()..remove('promptToolUse'),
      ).promptToolUse,
      isFalse,
    );
    final enabled = legacy.copyWith(promptToolUse: true);
    expect(
      LlmProviderConfig.fromJson(
        enabled.toJson(),
      ).copyWith(name: 'new').promptToolUse,
      isTrue,
    );
    final draft = ModelsSettingsDraft(
      AppConfig(
        llmProviders: [
          enabled,
          legacy.copyWith(id: 'other'),
        ],
        activeLlmProviderId: 'relay',
      ),
    );
    expect(draft.promptToolUse, isTrue);
    draft.switchProvider('other');
    expect(draft.promptToolUse, isFalse);
    draft.promptToolUse = true;
    draft.syncFromForm();
    draft.switchProvider('relay');
    expect(draft.promptToolUse, isTrue);
    final service = ConfigService();
    await service.saveConfig(
      AppConfig(llmProviders: draft.providers, activeLlmProviderId: 'other'),
    );
    final restored = await service.loadConfig();
    expect(restored.activeLlmProvider.promptToolUse, isTrue);
    draft.dispose();
  });

  test('Claude 重复 ID 请求修复，结果按原 ID 与工具名配对，历史不变', () {
    const calls = [
      ToolCall(id: 'duplicate', name: 'echo', arguments: {}),
      ToolCall(id: 'duplicate', name: 'other', arguments: {}),
      ToolCall(id: '', name: 'echo', arguments: {}),
      ToolCall(id: 'call_harness_0', name: 'echo', arguments: {}),
    ];
    final messages = [
      AgentMessage(id: 'a', role: AgentRole.assistant, toolCalls: calls),
      AgentMessage(
        id: 'r2',
        role: AgentRole.tool,
        toolCallId: 'duplicate',
        toolName: 'other',
      ),
      AgentMessage(
        id: 'r1',
        role: AgentRole.tool,
        toolCallId: 'duplicate',
        toolName: 'echo',
      ),
      AgentMessage(
        id: 'r3',
        role: AgentRole.tool,
        toolCallId: '',
        toolName: 'echo',
      ),
      AgentMessage(
        id: 'r4',
        role: AgentRole.tool,
        toolCallId: 'call_harness_0',
        toolName: 'echo',
      ),
      AgentMessage(
        id: 'b',
        role: AgentRole.assistant,
        toolCalls: [calls.first],
      ),
      AgentMessage(
        id: 'r5',
        role: AgentRole.tool,
        toolCallId: 'duplicate',
        toolName: 'echo',
      ),
    ];
    final fixed = normalizeToolCallIds(messages);
    final ids = fixed
        .where((m) => m.role == AgentRole.assistant)
        .expand((m) => m.toolCalls!)
        .map((c) => c.id)
        .toList();
    expect(ids.toSet(), hasLength(5));
    expect(ids[3], 'call_harness_0');
    expect(fixed.skip(1).take(4).map((m) => m.toolCallId), [
      ids[1],
      ids[0],
      ids[2],
      ids[3],
    ]);
    expect(fixed.last.toolCallId, ids.last);
    expect(messages.first.toolCalls![1].id, 'duplicate');
    expect(
      normalizeToolCallIds(messages).map((m) => m.toolCallId),
      fixed.map((m) => m.toolCallId),
    );
  });

  test('原生 SSE 同一回复重复 ID 及历史重复 ID 都获得唯一配对 ID', () async {
    Map<String, dynamic>? body;
    final provider = _provider(
      MockClient.streaming((req, stream) async {
        body =
            jsonDecode(utf8.decode(await stream.toBytes()))
                as Map<String, dynamic>;
        return _sse([
          {
            'tool_calls': [
              for (var i = 0; i < 2; i++)
                {
                  'index': i,
                  'id': 'duplicate',
                  'function': {'name': 'echo', 'arguments': '{"text":"$i"}'},
                },
            ],
          },
        ]);
      }),
      prompt: false,
    );
    final events = await provider
        .streamChat(
          messages: [
            AgentMessage(
              id: 'a',
              role: AgentRole.assistant,
              toolCalls: const [
                ToolCall(id: 'duplicate', name: 'echo', arguments: {}),
                ToolCall(id: 'duplicate', name: 'echo', arguments: {}),
              ],
            ),
            AgentMessage(
              id: 'r1',
              role: AgentRole.tool,
              toolCallId: 'duplicate',
            ),
            AgentMessage(
              id: 'r2',
              role: AgentRole.tool,
              toolCallId: 'duplicate',
            ),
          ],
          tools: [tool],
        )
        .toList();
    expect(body!['tools'], hasLength(1));
    final history = body!['messages'] as List<dynamic>;
    final calls = (history.first as Map)['tool_calls'] as List<dynamic>;
    final historyIds = calls.map((c) => (c as Map)['id']).toSet();
    expect(historyIds, hasLength(2));
    expect((history[1] as Map)['tool_call_id'], (calls[0] as Map)['id']);
    expect((history[2] as Map)['tool_call_id'], (calls[1] as Map)['id']);
    final newIds = events
        .whereType<ToolCallEvent>()
        .map((e) => e.toolCall.id)
        .toSet();
    expect(newIds, hasLength(2));
    expect(newIds.intersection(historyIds), isEmpty);
  });

  test('请求无原生工具字段，历史结果转用户文本并保留图片', () async {
    Map<String, dynamic>? body;
    final provider = _provider(
      MockClient.streaming((req, stream) async {
        body =
            jsonDecode(utf8.decode(await stream.toBytes()))
                as Map<String, dynamic>;
        return _sse([
          {'content': 'ok'},
        ]);
      }),
    );
    final events = await provider
        .streamChat(
          messages: [
            AgentMessage(
              id: 's',
              role: AgentRole.system,
              content: 'original rules',
            ),
            AgentMessage(
              id: 'a',
              role: AgentRole.assistant,
              content: '查一下',
              toolCalls: const [
                ToolCall(id: 'old', name: 'echo', arguments: {'text': 'x'}),
              ],
            ),
            AgentMessage(
              id: 't',
              role: AgentRole.tool,
              toolCallId: 'old',
              toolName: 'echo',
              content: 'result',
              imageBase64: 'aW1n',
            ),
            AgentMessage(
              id: 'u',
              role: AgentRole.user,
              content: 'question',
              images: const [AgentMessageImage(base64: 'dXNlcg==')],
            ),
          ],
          tools: [tool],
        )
        .toList();
    expect(events.whereType<ErrorEvent>(), isEmpty);
    expect(body!.containsKey('tools'), isFalse);
    expect(body!.containsKey('tool_choice'), isFalse);
    final messages = (body!['messages'] as List).cast<Map<String, dynamic>>();
    expect(messages.first['content'], startsWith('original rules'));
    expect(messages.first['content'], contains('Echo text.'));
    expect(messages[1]['content'], contains(_call('x')));
    for (final message in messages) {
      expect(message['role'], isNot('tool'));
      expect(message.containsKey('tool_calls'), isFalse);
      expect(message.containsKey('tool_call_id'), isFalse);
    }
    final result = messages[2]['content'] as List;
    expect(messages[2]['role'], 'user');
    expect((result[0] as Map)['text'], contains('"name":"echo"'));
    expect((result[1] as Map)['image_url'], {
      'url': 'data:image/png;base64,aW1n',
    });
    expect(messages.last['content'], hasLength(2));
  });

  test('跨每个字符分片，多调用/嵌套/转义及参数内闭标签仍正确解析', () async {
    final text = '先查\n${_call('x </tool_call> \\ "中文"')}\n${_call('y')}\n';
    final provider = _provider(
      MockClient.streaming(
        (req, body) async => _sse([
          for (final rune in text.runes) {'content': String.fromCharCode(rune)},
        ]),
      ),
    );
    final events = await provider
        .streamChat(messages: [], tools: [tool])
        .toList();
    expect(events.whereType<ErrorEvent>(), isEmpty);
    expect(
      events.whereType<ContentDeltaEvent>().map((e) => e.delta).join(),
      '先查\n\n\n',
    );
    expect(
      events.whereType<ToolCallEvent>().map(
        (e) => e.toolCall.arguments['text'],
      ),
      ['x </tool_call> \\ "中文"', 'y'],
    );
    expect(events.whereType<UsageEvent>(), hasLength(1));
  });

  test('思考、围栏、行内、引用和裸 JSON 示例都不会触发工具', () async {
    final call = _call('example');
    final text =
        '```json\n$call\n```\n````markdown\n```\n$call\n```\n````\n'
        '~~~json\n$call\n~~~\n    $call\n\t$call\n'
        '`$call`\n> $call\n解释 $call\n{"name":"echo","arguments":{}}';
    final provider = _provider(
      MockClient.streaming(
        (req, body) async => _sse([
          {'reasoning_content': call},
          {'content': '\u003cthink\u003e$call\u003c/think\u003e'},
          for (final rune in text.runes) {'content': String.fromCharCode(rune)},
        ]),
      ),
    );
    final events = await provider
        .streamChat(messages: [], tools: [tool])
        .toList();
    expect(events.whereType<ErrorEvent>(), isEmpty);
    expect(events.whereType<ToolCallEvent>(), isEmpty);
    expect(
      events.whereType<ContentDeltaEvent>().map((e) => e.delta).join(),
      text,
    );
    expect(
      events.whereType<ThoughtDeltaEvent>().map((e) => e.delta).join(),
      '$call$call',
    );
  });

  for (final broken in [
    '<tool_call>{"name":"echo","arguments":',
    '<tool_call>{"name":"echo","arguments":[]}</tool_call>',
    '<tool_call>{"name":"echo","arguments":{bad}}</tool_call>',
    _call('x', name: 'forbidden'),
    '${_call('valid')}\n${_call('x', name: 'forbidden')}',
  ]) {
    test('格式损坏/未开放工具不会提交任何调用: $broken', () async {
      final provider = _provider(
        MockClient.streaming(
          (req, body) async => _sse([
            {'content': broken},
          ]),
        ),
      );
      final events = await provider
          .streamChat(messages: [], tools: [tool])
          .toList();
      expect(events.whereType<ToolCallEvent>(), isEmpty);
      expect(events.whereType<ErrorEvent>().single.transient, isFalse);
      expect(events.whereType<UsageEvent>(), hasLength(1));
    });
  }

  for (final reason in [null, 'length', 'content_filter']) {
    test('断流或非正常结束不提交调用 ($reason)', () async {
      final provider = _provider(
        MockClient.streaming(
          (req, body) async => _sse(
            [
              {'content': _call('x')},
            ],
            done: false,
            reason: reason,
          ),
        ),
      );
      final events = await provider
          .streamChat(messages: [], tools: [tool])
          .toList();
      expect(events.whereType<ToolCallEvent>(), isEmpty);
      expect(events.whereType<ErrorEvent>(), hasLength(1));
      expect(events.whereType<UsageEvent>(), hasLength(1));
    });
  }

  test('64 KiB 限额按单块 UTF-8 字节而非总回复计算', () async {
    for (final (text, valid) in [
      ('${_call('a' * 40000)}\n${_call('b' * 40000)}\n${'x' * 70000}', true),
      (_call('中' * 30000), false),
    ]) {
      final provider = _provider(
        MockClient.streaming(
          (request, body) async => _sse([
            {'content': text},
          ]),
        ),
      );
      final events = await provider
          .streamChat(messages: [], tools: [tool])
          .toList();
      expect(events.whereType<ToolCallEvent>(), hasLength(valid ? 2 : 0));
      expect(events.whereType<ErrorEvent>(), hasLength(valid ? 0 : 1));
      expect(events.whereType<UsageEvent>(), hasLength(1));
    }
  });

  test('协议额外文本纳入 Harness 初始上下文估算', () {
    AgentHarness makeHarness(bool prompt) => AgentHarness(
      tools: ToolRegistry()..register(tool),
      provider: _provider(
        MockClient((request) async => http.Response('', 200)),
        prompt: prompt,
      ),
      initialPreset: const AgentPreset(
        id: 'test',
        name: 'Test',
        description: '',
        systemPrompt: '',
        enabledToolNames: ['echo'],
      ),
    );
    expect(
      makeHarness(true).contextUsage.tokens,
      greaterThan(makeHarness(false).contextUsage.tokens),
    );
  });

  test('普通文本实时输出；无可用工具时拒绝调用', () async {
    final parser = PromptToolStreamParser([tool]);
    expect(parser.add('实时正文').single.delta, '实时正文');
    final provider = _provider(
      MockClient.streaming(
        (req, body) async => _sse([
          {'content': _call('x')},
        ]),
      ),
    );
    final events = await provider.streamChat(messages: [], tools: []).toList();
    expect(events.whereType<ToolCallEvent>(), isEmpty);
    expect(events.whereType<ErrorEvent>(), hasLength(1));
  });

  test('Harness 实际执行工具、回传结果、下一轮回答与达到上限收尾', () async {
    final echo = _EchoTool();
    final bodies = <Map<String, dynamic>>[];
    final provider = _provider(
      MockClient.streaming((req, stream) async {
        bodies.add(
          jsonDecode(utf8.decode(await stream.toBytes()))
              as Map<String, dynamic>,
        );
        return _sse([
          {'content': bodies.length == 1 ? _call('真实结果') : '最终回答'},
        ]);
      }),
    );
    final harness = AgentHarness(
      tools: ToolRegistry()..register(echo),
      provider: provider,
      initialPreset: const AgentPreset(
        id: 'test',
        name: 'Test',
        description: '',
        systemPrompt: '',
        enabledToolNames: ['echo'],
      ),
    )..maxTurns = 1;
    final events = await harness.send('查一下').toList();
    expect(events.whereType<ErrorEvent>(), isEmpty);
    expect(echo.executions, 1);
    expect(events.whereType<ToolResultEvent>().single.result.content, '真实结果');
    expect(events.whereType<TurnEndEvent>().last.finalMessage.content, '最终回答');
    expect(bodies, hasLength(2));
    expect(bodies.last.containsKey('tools'), isFalse);
    final messages = (bodies.last['messages'] as List)
        .cast<Map<String, dynamic>>();
    expect(messages.first['content'], contains('本轮没有可用工具'));
    expect(
      messages.any((m) => '${m['content']}'.contains('"content":"真实结果"')),
      isTrue,
    );
  });
}
