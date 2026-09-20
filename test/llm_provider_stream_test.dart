import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:novelai_harness/core/harness/agent_harness.dart';
import 'package:novelai_harness/core/harness/presets/agent_preset.dart';
import 'package:novelai_harness/core/harness/providers/openai_provider.dart';
import 'package:novelai_harness/core/harness/tools/agent_tool.dart';
import 'package:novelai_harness/core/harness/types.dart';
import 'package:novelai_harness/data/models/novelai_models.dart';

/// 内嵌思考标签 (与 openai_provider 的 _openThinkTag/_closeThinkTag 一致)
/// 用转义书写，避免源码出现裸标签干扰工具链
const String kOpenThinkTag = '\u003Cthink\u003E';
const String kCloseThinkTag = '\u003C\u002Fthink\u003E';

/// 构造一条 chat/completions SSE 流式响应
http.StreamedResponse _sse(List<Map<String, dynamic>> chunks) {
  final body =
      '${chunks.map((c) => 'data: ${jsonEncode(c)}\n').join()}data: [DONE]\n';
  return http.StreamedResponse(
    http.ByteStream.fromBytes(utf8.encode(body)),
    200,
  );
}

Map<String, dynamic> _delta(Map<String, dynamic> delta) => {
  'choices': [
    {'delta': delta},
  ],
};

OpenAiCompatibleProvider _provider(http.Client client) =>
    OpenAiCompatibleProvider(
      baseUrl: 'https://api.test/v1',
      apiKey: 'test-key',
      model: 'test-model',
      client: client,
    );

List<String> _thoughts(List<HarnessEvent> events) =>
    events.whereType<ThoughtDeltaEvent>().map((e) => e.delta).toList();

List<String> _contents(List<HarnessEvent> events) =>
    events.whereType<ContentDeltaEvent>().map((e) => e.delta).toList();

class _ProtocolEchoTool extends AgentTool {
  const _ProtocolEchoTool()
    : super(
        name: 'echo_protocol',
        label: 'Echo protocol',
        description: 'Echo a value for protocol tests.',
        parameters: const {
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
  ) async => ToolResult(toolCallId: toolCallId, content: '${args['text']}');
}

void main() {
  group('思考流字段解析', () {
    test('OpenRouter reasoning 字段解析为思考流', () async {
      final provider = _provider(
        MockClient.streaming(
          (req, body) async => _sse([
            _delta({'reasoning': '内心思考'}),
            _delta({'content': '最终回答'}),
          ]),
        ),
      );

      final events = await provider
          .streamChat(messages: [], tools: [])
          .toList();

      expect(_thoughts(events), equals(['内心思考']));
      expect(_contents(events), equals(['最终回答']));
    });

    test('DeepSeek reasoning_content 字段解析为思考流', () async {
      final provider = _provider(
        MockClient.streaming(
          (req, body) async => _sse([
            _delta({'reasoning_content': '推理中'}),
            _delta({'content': '答案'}),
          ]),
        ),
      );

      final events = await provider
          .streamChat(messages: [], tools: [])
          .toList();

      expect(_thoughts(events), equals(['推理中']));
      expect(_contents(events), equals(['答案']));
    });

    test('双字段同时回传时优先级短路，思考不重复 (对齐 pi)', () async {
      final provider = _provider(
        MockClient.streaming(
          (req, body) async => _sse([
            _delta({'reasoning_content': '同一段思考', 'reasoning': '同一段思考'}),
            _delta({'content': '正文'}),
          ]),
        ),
      );

      final events = await provider
          .streamChat(messages: [], tools: [])
          .toList();

      // 只取第一个非空字段，避免个别网关双字段回传同样内容
      expect(_thoughts(events), equals(['同一段思考']));
      expect(_contents(events), equals(['正文']));
    });

    test('reasoning_text 第三优先级字段也可解析', () async {
      final provider = _provider(
        MockClient.streaming(
          (req, body) async => _sse([
            _delta({'reasoning_text': '第三字段思考'}),
            _delta({'content': '正文'}),
          ]),
        ),
      );

      final events = await provider
          .streamChat(messages: [], tools: [])
          .toList();

      expect(_thoughts(events), equals(['第三字段思考']));
    });

    test('内嵌思考标签跨 chunk 拆分也能正确分流', () async {
      final provider = _provider(
        MockClient.streaming(
          (req, body) async => _sse([
            _delta({'content': '前缀'}),
            _delta({'content': kOpenThinkTag.substring(0, 4)}),
            _delta({'content': kOpenThinkTag.substring(4)}),
            _delta({'content': '思考文字'}),
            _delta({'content': kCloseThinkTag.substring(0, 4)}),
            _delta({'content': kCloseThinkTag.substring(4)}),
            _delta({'content': '正文'}),
          ]),
        ),
      );

      final events = await provider
          .streamChat(messages: [], tools: [])
          .toList();

      expect(_contents(events), equals(['前缀', '正文']));
      expect(_thoughts(events), equals(['思考文字']));
    });

    test('单个 chunk 内完整思考块与前后正文正确分流', () async {
      final chunk = 'A$kOpenThinkTag${'T'}$kCloseThinkTag${'B'}';
      final provider = _provider(
        MockClient.streaming(
          (req, body) async => _sse([
            _delta({'content': chunk}),
          ]),
        ),
      );

      final events = await provider
          .streamChat(messages: [], tools: [])
          .toList();

      expect(_contents(events), equals(['A', 'B']));
      expect(_thoughts(events), equals(['T']));
    });

    test('流结束时残缺标签片段按状态冲刷输出', () async {
      final provider = _provider(
        MockClient.streaming(
          (req, body) async => _sse([
            _delta({'content': '文字'}),
            _delta({'content': kOpenThinkTag.substring(0, 4)}),
          ]),
        ),
      );

      final events = await provider
          .streamChat(messages: [], tools: [])
          .toList();

      // 没等到完整标签出现，残缺片段按正文原文输出
      expect(_contents(events), equals(['文字', kOpenThinkTag.substring(0, 4)]));
      expect(_thoughts(events), isEmpty);
    });
  });

  group('DeepSeek 工具请求思考历史回传', () {
    final tool = const _ProtocolEchoTool();

    Future<Map<String, dynamic>> captureBody({
      required String baseUrl,
      required List<AgentMessage> messages,
      required List<AgentTool> tools,
      String? format,
      bool reasoning = true,
      String? effort = 'high',
    }) async {
      Map<String, dynamic>? captured;
      final provider = OpenAiCompatibleProvider(
        baseUrl: baseUrl,
        apiKey: 'test-key',
        model: 'test-model',
        reasoning: reasoning,
        thinkingEffort: effort,
        thinkingParamFormat: format,
        client: MockClient.streaming((request, body) async {
          captured =
              jsonDecode(utf8.decode(await body.toBytes()))
                  as Map<String, dynamic>;
          return _sse([
            _delta({'content': 'ok'}),
          ]);
        }),
      );

      await provider.streamChat(messages: messages, tools: tools).toList();
      return captured!;
    }

    test('流式工具续接和下一用户轮完整回传每个 assistant 的原始思考', () async {
      final bodies = <Map<String, dynamic>>[];
      final provider = OpenAiCompatibleProvider(
        baseUrl: 'https://api.deepseek.com/v1',
        apiKey: 'test-key',
        model: 'deepseek-flash',
        reasoning: true,
        thinkingEffort: 'high',
        client: MockClient.streaming((request, body) async {
          bodies.add(
            jsonDecode(utf8.decode(await body.toBytes()))
                as Map<String, dynamic>,
          );
          return switch (bodies.length) {
            1 => _sse([
              _delta({
                'reasoning_content': '  first tool thought\n',
                'tool_calls': [
                  {
                    'index': 0,
                    'id': 'call_1',
                    'type': 'function',
                    'function': {
                      'name': 'echo_protocol',
                      'arguments': '{"text":"one"}',
                    },
                  },
                ],
              }),
            ]),
            2 => _sse([
              _delta({'reasoning_content': '\tfinal thought  '}),
              _delta({'content': 'first answer'}),
            ]),
            _ => _sse([
              _delta({'reasoning_content': 'next thought'}),
              _delta({'content': 'next answer'}),
            ]),
          };
        }),
      );
      final registry = ToolRegistry()..register(tool);
      final harness = AgentHarness(
        tools: registry,
        provider: provider,
        initialPreset: const AgentPreset(
          id: 'protocol-test',
          name: 'Protocol test',
          description: '',
          systemPrompt: '',
          enabledToolNames: ['echo_protocol'],
        ),
      );

      await harness.send('first question').toList();
      await harness.send('later question').toList();

      expect(bodies, hasLength(3));
      for (final body in bodies) {
        expect(body['tools'], hasLength(1));
        expect(body.containsKey('tool_choice'), isFalse);
      }
      final continuationMessages = bodies[1]['messages'] as List<dynamic>;
      final firstAssistant = continuationMessages
          .whereType<Map<String, dynamic>>()
          .singleWhere((message) => message['role'] == 'assistant');
      expect(firstAssistant['content'], isA<String>());
      final toolResult = continuationMessages
          .whereType<Map<String, dynamic>>()
          .singleWhere((message) => message['role'] == 'tool');
      expect(toolResult['content'], 'one');
      expect(
        firstAssistant['reasoning_content'],
        equals('  first tool thought\n'),
      );

      final laterMessages = bodies[2]['messages'] as List<dynamic>;
      final assistants = laterMessages
          .whereType<Map<String, dynamic>>()
          .where((message) => message['role'] == 'assistant')
          .toList();
      expect(
        assistants.map((message) => message['reasoning_content']).toList(),
        equals(['  first tool thought\n', '\tfinal thought  ']),
      );
    });

    test('DeepSeek 无工具请求不发送 reasoning_content', () async {
      final body = await captureBody(
        baseUrl: 'https://api.deepseek.com/v1',
        messages: [
          AgentMessage(
            id: 'a1',
            role: AgentRole.assistant,
            content: 'answer',
            thoughts: 'stored thought',
          ),
        ],
        tools: const [],
      );

      final assistant = (body['messages'] as List<dynamic>).single as Map;
      expect(assistant.containsKey('reasoning_content'), isFalse);
    });

    test('显式 DeepSeek 格式的中转站回传现有思考且不臆造缺失思考', () async {
      final body = await captureBody(
        baseUrl: 'https://relay.example/v1',
        format: 'deepseek',
        messages: [
          AgentMessage(
            id: 'a1',
            role: AgentRole.assistant,
            content: 'with thought',
            thoughts: ' \n exact whitespace\t ',
          ),
          AgentMessage(
            id: 'a2',
            role: AgentRole.assistant,
            content: 'without thought',
          ),
        ],
        tools: [tool],
      );

      final assistants = (body['messages'] as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .toList();
      expect(
        assistants.first['reasoning_content'],
        equals(' \n exact whitespace\t '),
      );
      expect(assistants.last.containsKey('reasoning_content'), isFalse);
      expect(body.containsKey('tool_choice'), isFalse);
    });

    test('伪装 DeepSeek 后缀的第三方主机保持 OpenAI 请求形状', () async {
      final body = await captureBody(
        baseUrl: 'https://api.deepseek.com.evil.example/v1',
        messages: [
          AgentMessage(
            id: 'a1',
            role: AgentRole.assistant,
            content: 'answer',
            thoughts: 'private thought',
          ),
        ],
        tools: [tool],
      );

      final assistant = (body['messages'] as List<dynamic>).single as Map;
      expect(assistant.containsKey('reasoning_content'), isFalse);
      expect(body.containsKey('thinking'), isFalse);
      expect(body['reasoning_effort'], equals('high'));
      expect(body['tool_choice'], 'auto');
    });
  });

  group('思考参数请求格式 (对齐 pi thinkingFormat 兼容矩阵)', () {
    Map<String, dynamic>? capturedBody;

    OpenAiCompatibleProvider fmtProvider(
      String baseUrl, {
      bool reasoning = true,
      String? effort = 'high',
      String? format,
      String model = 'test-model',
    }) {
      final client = MockClient.streaming((req, body) async {
        capturedBody =
            jsonDecode(utf8.decode(await body.toBytes()))
                as Map<String, dynamic>;
        return _sse([
          _delta({'content': 'ok'}),
        ]);
      });
      return OpenAiCompatibleProvider(
        baseUrl: baseUrl,
        apiKey: 'test-key',
        model: model,
        reasoning: reasoning,
        thinkingEffort: effort,
        thinkingParamFormat: format,
        client: client,
      );
    }

    Future<Map<String, dynamic>> requestBody(
      OpenAiCompatibleProvider p, {
      double temperature = 0.7,
    }) async {
      await p
          .streamChat(messages: [], tools: [], temperature: temperature)
          .toList();
      return capturedBody!;
    }

    test('默认 OpenAI 格式: 开思考时发送 reasoning_effort', () async {
      final body = await requestBody(fmtProvider('https://api.test/v1'));
      expect(body['reasoning_effort'], equals('high'));
      expect(body.containsKey('thinking'), isFalse);
      expect(body.containsKey('reasoning'), isFalse);
    });

    test('默认 OpenAI 格式: 关思考时不发送任何思考字段', () async {
      final body = await requestBody(
        fmtProvider('https://api.test/v1', reasoning: false, effort: 'off'),
      );
      expect(body.containsKey('reasoning_effort'), isFalse);
      expect(body.containsKey('thinking'), isFalse);
    });

    test(
      'Gemini compatibility explicitly sends none when thinking is off',
      () async {
        final body = await requestBody(
          fmtProvider(
            'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions',
            reasoning: false,
            effort: 'none',
            model: 'gemini-2.5-flash',
          ),
        );

        expect(body['reasoning_effort'], 'none');
        expect(body.containsKey('thinking'), isFalse);
      },
    );

    for (final model in [
      'gemini-2.5-pro',
      'gemini-3-flash',
      'gemini-2.5-flash-image',
      'test-model',
    ]) {
      test('Gemini compatibility does not send none for $model', () async {
        final body = await requestBody(
          fmtProvider(
            'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions',
            reasoning: false,
            effort: 'none',
            model: model,
          ),
        );

        expect(body.containsKey('reasoning_effort'), isFalse);
      });
    }

    test('Official Anthropic Sonnet 5 omits temperature', () async {
      final body = await requestBody(
        fmtProvider(
          'https://api.anthropic.com/v1/chat/completions',
          reasoning: false,
          effort: null,
          model: 'claude-sonnet-5',
        ),
        temperature: 0.3,
      );

      expect(body.containsKey('temperature'), isFalse);
    });

    for (final (endpoint, model) in [
      (
        'https://anthropic-relay.example/v1/chat/completions',
        'claude-sonnet-5',
      ),
      (
        'https://api.anthropic.com/v1/chat/completions',
        'claude-haiku-4-5-20251001',
      ),
    ]) {
      test('Temperature remains for $endpoint $model', () async {
        final body = await requestBody(
          fmtProvider(endpoint, reasoning: false, effort: null, model: model),
          temperature: 0.3,
        );

        expect(body['temperature'], 0.3);
      });
    }

    test('模型不具备思考能力时不发送思考参数', () async {
      final body = await requestBody(
        fmtProvider('https://api.test/v1', reasoning: false, effort: null),
      );
      expect(body.containsKey('reasoning_effort'), isFalse);
      expect(body.containsKey('thinking'), isFalse);
      expect(body.containsKey('enable_thinking'), isFalse);
    });

    test(
      'DeepSeek 格式: thinking 开关 + reasoning_effort，关闭时显式 disabled',
      () async {
        final on = await requestBody(
          fmtProvider('https://api.deepseek.com/v1', format: 'deepseek'),
        );
        expect(on['thinking'], equals({'type': 'enabled'}));
        expect(on['reasoning_effort'], equals('high'));

        final off = await requestBody(
          fmtProvider(
            'https://api.deepseek.com/v1',
            reasoning: false,
            effort: 'off',
            format: 'deepseek',
          ),
        );
        expect(off['thinking'], equals({'type': 'disabled'}));
        expect(off.containsKey('reasoning_effort'), isFalse);
      },
    );

    test('DeepSeek 域名自动识别', () async {
      final body = await requestBody(
        fmtProvider('https://api.deepseek.com/v1'),
      );
      expect(body['thinking'], equals({'type': 'enabled'}));
    });

    test('Qwen 格式: enable_thinking 布尔开关', () async {
      final on = await requestBody(
        fmtProvider(
          'https://dashscope.aliyuncs.com/compatible-mode/v1',
          format: 'qwen',
        ),
      );
      expect(on['enable_thinking'], isTrue);
      expect(on['reasoning_effort'], equals('high'));

      final off = await requestBody(
        fmtProvider(
          'https://dashscope.aliyuncs.com/compatible-mode/v1',
          reasoning: false,
          effort: 'off',
          format: 'qwen',
        ),
      );
      expect(off['enable_thinking'], isFalse);
    });

    test(
      'Qwen Chat Template 格式: chat_template_kwargs 携带 preserve_thinking',
      () async {
        final body = await requestBody(
          fmtProvider('https://api.test/v1', format: 'qwen_chat_template'),
        );
        expect(
          body['chat_template_kwargs'],
          equals({'enable_thinking': true, 'preserve_thinking': true}),
        );
      },
    );

    test('Z.ai 格式: thinking + clear_thinking，关闭时 disabled', () async {
      final on = await requestBody(
        fmtProvider('https://api.z.ai/v1', format: 'zai'),
      );
      expect(
        on['thinking'],
        equals({'type': 'enabled', 'clear_thinking': false}),
      );

      final off = await requestBody(
        fmtProvider(
          'https://api.z.ai/v1',
          reasoning: false,
          effort: 'off',
          format: 'zai',
        ),
      );
      expect(off['thinking'], equals({'type': 'disabled'}));
    });

    test('OpenRouter 域名自动识别: 嵌套 reasoning.effort 对象', () async {
      final on = await requestBody(fmtProvider('https://openrouter.ai/api/v1'));
      expect(on['reasoning'], equals({'effort': 'high'}));

      final off = await requestBody(
        fmtProvider(
          'https://openrouter.ai/api/v1',
          reasoning: false,
          effort: 'off',
        ),
      );
      expect(off['reasoning'], equals({'effort': 'none'}));
    });

    test('Together 格式: reasoning.enabled 布尔对象', () async {
      final on = await requestBody(
        fmtProvider('https://api.together.xyz/v1', format: 'together'),
      );
      expect(on['reasoning'], equals({'enabled': true}));
      expect(on['reasoning_effort'], equals('high'));
    });

    test('LlmProviderConfig.thinkingParamFormat JSON 往返与旧配置兼容', () {
      const provider = LlmProviderConfig(
        id: 'p1',
        name: '测试',
        baseUrl: 'https://api.test/v1',
        apiKey: 'k',
        models: [LlmModelConfig(id: 'm1', name: 'M1')],
        thinkingParamFormat: ThinkingParamFormat.deepseek,
      );

      final restored = LlmProviderConfig.fromJson(provider.toJson());
      expect(
        restored.thinkingParamFormat,
        equals(ThinkingParamFormat.deepseek),
      );

      // 旧配置无该字段时回退 auto
      final legacy = LlmProviderConfig.fromJson({
        'id': 'p2',
        'name': '旧配置',
        'baseUrl': 'https://api.test/v1',
        'apiKey': 'k',
        'models': [
          {'id': 'm1', 'name': 'M1'},
        ],
      });
      expect(legacy.thinkingParamFormat, equals(ThinkingParamFormat.auto));

      // copyWith 透传
      expect(
        provider.copyWith(name: '改名').thinkingParamFormat,
        equals(ThinkingParamFormat.deepseek),
      );
    });
  });

  group('Ollama loopback authentication', () {
    test('Exact local compatibility endpoint accepts an empty key', () async {
      http.BaseRequest? captured;
      final provider = OpenAiCompatibleProvider(
        baseUrl: 'http://localhost:11434/v1/chat/completions',
        apiKey: '',
        model: 'llama3.3',
        client: MockClient.streaming((request, body) async {
          captured = request;
          return _sse([
            _delta({'content': 'local response'}),
          ]);
        }),
      );

      final events = await provider
          .streamChat(messages: [], tools: [])
          .toList();

      expect(_contents(events), ['local response']);
      expect(captured, isNotNull);
      expect(captured!.headers.containsKey('Authorization'), isFalse);
    });

    for (final endpoint in [
      'http://ollama.example:11434/v1/chat/completions',
      'http://localhost.example:11434/v1/chat/completions',
      'http://localhost:11435/v1/chat/completions',
      'http://localhost:11434/api/chat',
      'https://localhost:11434/v1/chat/completions',
    ]) {
      test('Empty key remains rejected for $endpoint', () async {
        var requestCount = 0;
        final provider = OpenAiCompatibleProvider(
          baseUrl: endpoint,
          apiKey: '',
          model: 'llama3.3',
          client: MockClient.streaming((request, body) async {
            requestCount++;
            return _sse([]);
          }),
        );

        final events = await provider
            .streamChat(messages: [], tools: [])
            .toList();

        expect(requestCount, 0);
        expect(
          events.whereType<ErrorEvent>().single.error,
          contains('API Key'),
        );
      });
    }
  });

  group('流式 usage 记账 (对齐 pi last-wins 语义)', () {
    test('逐 chunk 回传全量累计 usage 时只发一次 UsageEvent，取最后快照', () async {
      final provider = _provider(
        MockClient.streaming(
          (req, body) async => _sse([
            _delta({'content': '你'})
              ..['usage'] = {'prompt_tokens': 100000, 'completion_tokens': 1},
            _delta({'content': '好'})
              ..['usage'] = {'prompt_tokens': 100000, 'completion_tokens': 2},
            {
              'choices': <dynamic>[],
              'usage': {'prompt_tokens': 100000, 'completion_tokens': 3},
            },
          ]),
        ),
      );

      final events = await provider
          .streamChat(messages: [], tools: [])
          .toList();

      final usageEvents = events.whereType<UsageEvent>().toList();
      // 整条流只发一次，否则账本会按 chunk 数重复记账 (input 虚增数十倍)
      expect(usageEvents, hasLength(1));
      expect(usageEvents.single.usage.input, equals(100000));
      expect(usageEvents.single.usage.output, equals(3));
      expect(usageEvents.single.usage.total, equals(100003));
    });

    test('标准 include_usage 尾部空 choices chunk 正常记账', () async {
      final provider = _provider(
        MockClient.streaming(
          (req, body) async => _sse([
            _delta({'content': 'ok'}),
            {
              'choices': <dynamic>[],
              'usage': {
                'prompt_tokens': 42,
                'completion_tokens': 7,
                'prompt_tokens_details': {'cached_tokens': 20},
              },
            },
          ]),
        ),
      );

      final events = await provider
          .streamChat(messages: [], tools: [])
          .toList();

      final usageEvents = events.whereType<UsageEvent>().toList();
      expect(usageEvents, hasLength(1));
      expect(usageEvents.single.usage.input, equals(22));
      expect(usageEvents.single.usage.cacheRead, equals(20));
      expect(usageEvents.single.usage.output, equals(7));
    });

    test('Moonshot 风格 usage 藏在 choice 内也只取最后快照', () async {
      final provider = _provider(
        MockClient.streaming(
          (req, body) async => _sse([
            {
              'choices': [
                {
                  'delta': {'content': 'a'},
                  'usage': {'prompt_tokens': 10, 'completion_tokens': 1},
                },
              ],
            },
            {
              'choices': [
                {
                  'delta': {'content': 'b'},
                  'usage': {'prompt_tokens': 10, 'completion_tokens': 2},
                },
              ],
            },
          ]),
        ),
      );

      final events = await provider
          .streamChat(messages: [], tools: [])
          .toList();

      final usageEvents = events.whereType<UsageEvent>().toList();
      expect(usageEvents, hasLength(1));
      expect(usageEvents.single.usage.output, equals(2));
    });

    test('无任何 usage 字段的流不产生 UsageEvent', () async {
      final provider = _provider(
        MockClient.streaming(
          (req, body) async => _sse([
            _delta({'content': 'plain'}),
          ]),
        ),
      );

      final events = await provider
          .streamChat(messages: [], tools: [])
          .toList();

      expect(events.whereType<UsageEvent>(), isEmpty);
    });
  });
}
