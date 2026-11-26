import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:novelai_harness/core/harness/agent_harness.dart';
import 'package:novelai_harness/core/harness/mcp/mcp_client.dart';
import 'package:novelai_harness/core/harness/mcp/mcp_manager.dart';
import 'package:novelai_harness/core/harness/mcp/mcp_models.dart';
import 'package:novelai_harness/core/harness/presets/agent_preset.dart';
import 'package:novelai_harness/core/harness/providers/google_interactions_provider.dart';
import 'package:novelai_harness/core/harness/providers/openai_provider.dart';
import 'package:novelai_harness/core/harness/providers/prompt_cache_policy.dart';
import 'package:novelai_harness/core/harness/tools/agent_tool.dart';
import 'package:novelai_harness/core/harness/tools/character_prompt_tools.dart';
import 'package:novelai_harness/core/harness/tools/describe_tools_tool.dart';
import 'package:novelai_harness/core/harness/tools/pipeline_tool.dart';
import 'package:novelai_harness/core/harness/types.dart';
import 'package:novelai_harness/data/models/novelai_models.dart';

import 'agent_harness_test.dart' show MockLlmProvider;

class _DummyTagSearchTool extends AgentTool {
  _DummyTagSearchTool()
    : super(
        name: 'danbooru_search_tags',
        label: 'Danbooru 语义搜词',
        description: 'search tags',
        parameters: const {
          'type': 'object',
          'properties': {
            'query': {'type': 'string'},
          },
          'required': ['query'],
        },
      );

  @override
  Future<ToolResult> execute(
    String toolCallId,
    Map<String, dynamic> args,
  ) async {
    return ToolResult(
      toolCallId: toolCallId,
      content:
          '语义搜词 "${args['query']}" 结果：\n'
          '- silver_hair (银发) [热度: 100k]\n'
          '- moonlit_night (月夜) [热度: 20k]\n'
          '- extra_noise (噪音)',
    );
  }
}

class _DummyCaptureTool extends AgentTool {
  Map<String, dynamic>? lastArgs;
  final String? returnImage;

  _DummyCaptureTool({
    required super.name,
    required super.label,
    this.returnImage,
  }) : super(
         description: 'capture args',
         parameters: const {
           'type': 'object',
           'properties': {
             'prompt': {'type': 'string'},
           },
         },
       );

  @override
  Future<ToolResult> execute(
    String toolCallId,
    Map<String, dynamic> args,
  ) async {
    lastArgs = args;
    return ToolResult(
      toolCallId: toolCallId,
      content: 'captured: ${args['prompt'] ?? 'ok'}',
      imageBase64: returnImage,
    );
  }
}

void main() {
  group('RunPipelineTool & DescribeToolsTool', () {
    test('pipeline chains vars.join, @step.tags, filters, and enforces whitelist', () async {
      final searchTool = _DummyTagSearchTool();
      final updateTool = _DummyCaptureTool(
        name: 'update_studio_parameters',
        label: '修改参数',
      );
      final blockedTool = _DummyCaptureTool(
        name: 'novelai_upscale',
        label: '图像放大',
      );
      final registry = ToolRegistry()
        ..registerAll([searchTool, updateTool, blockedTool]);
      final pipeline = RunPipelineTool(
        registry: registry,
        isToolAllowed: (name) => name != 'novelai_upscale',
      );
      registry.register(pipeline);

      // 1. 合法编排：搜词 -> silent 过滤 -> vars.join 拼装 -> 写入工作台
      final result = await pipeline.execute('call_1', {
        'vars': {
          'subject': ['1girl', 'solo'],
        },
        'steps': [
          {
            'id': 'search',
            'tool': 'danbooru_search_tags',
            'args': {'query': 'silver hair'},
            'filter': {'max_lines': 3, 'silent': true},
          },
          {
            'id': 'skipped',
            'tool': 'update_studio_parameters',
            'when': false,
            'args': {'prompt': 'should_not_run'},
          },
          {
            'id': 'apply',
            'tool': 'update_studio_parameters',
            'args': {
              'prompt': {
                'join': [', ', '@vars.subject', '@search.tags'],
              },
            },
          },
        ],
        'return_steps': ['last'],
      });

      expect(result.isError, isFalse);
      expect(
        updateTool.lastArgs?['prompt'],
        '1girl, solo, silver_hair, moonlit_night',
      );
      expect(result.content, contains('[apply] update_studio_parameters:'));
      expect(result.content, isNot(contains('extra_noise')));

      // 2. 越权拒绝
      final denied = await pipeline.execute('call_2', {
        'steps': [
          {'tool': 'novelai_upscale', 'args': {}},
        ],
      });
      expect(denied.isError, isTrue);
      expect(denied.content, contains('未在当前预设中启用'));

      // 3. 禁止递归调用 run_pipeline
      final recursive = await pipeline.execute('call_3', {
        'steps': [
          {'tool': 'run_pipeline', 'args': {'steps': []}},
        ],
      });
      expect(recursive.isError, isTrue);
      expect(recursive.content, contains('不允许递归'));
    });

    test('pipeline preserves returned image from inner step', () async {
      final imgTool = _DummyCaptureTool(
        name: 'view_canvas_image',
        label: '查看画板图片',
        returnImage: 'base64_img_data',
      );
      final registry = ToolRegistry()..register(imgTool);
      final pipeline = RunPipelineTool(registry: registry);

      final result = await pipeline.execute('img_call', {
        'steps': [
          {'id': 'view', 'tool': 'view_canvas_image', 'args': {}},
        ],
      });
      expect(result.isError, isFalse);
      expect(result.imageBase64, 'base64_img_data');
    });

    test('describe_tools returns only allowed tool schemas', () async {
      final registry = ToolRegistry()
        ..registerAll([
          _DummyTagSearchTool(),
          _DummyCaptureTool(name: 'novelai_upscale', label: '图像放大'),
        ]);
      final describe = DescribeToolsTool(
        registry: registry,
        isToolAllowed: (name) => name == 'danbooru_search_tags',
      );

      final res = await describe.execute('d1', {
        'names': ['danbooru_search_tags', 'novelai_upscale'],
      });
      expect(res.isError, isFalse);
      expect(res.content, contains('danbooru_search_tags'));
      expect(res.content, contains('未找到或未启用的工具：novelai_upscale'));

      // 纯匹配时返回 JSON 对象而非裸数组，避免网关映射到 Gemini Struct 时报 cannot start list
      final pure = await describe.execute('d2', {
        'names': ['danbooru_search_tags'],
      });
      final decoded = jsonDecode(pure.content);
      expect(decoded, isA<Map<String, dynamic>>());
      expect((decoded as Map<String, dynamic>)['tools'], isA<List>());
    });
  });

  group('AgentHarness Dual-Track Compact Surface & Cache Stability', () {
    test(
      'compactToolSurface sends only primary tools while secondary tools stay indexed and runnable via run_pipeline',
      () async {
        final registry = ToolRegistry();
        final updateTool = _DummyCaptureTool(
          name: 'update_studio_parameters',
          label: '修改参数',
        );
        final searchTool = _DummyTagSearchTool();
        registry.registerAll([updateTool, searchTool]);

        late AgentHarness harness;
        final sentToolNames = <List<String>>[];
        String? capturedSystem;
        var turn = 0;
        final provider = MockLlmProvider((messages, tools) {
          turn++;
          capturedSystem = messages.first.content;
          sentToolNames.add(tools.map((t) => t.name).toList());
          if (turn == 1) {
            return [
              ToolCallEvent(
                const ToolCall(
                  id: 'p1',
                  name: 'run_pipeline',
                  arguments: {
                    'steps': [
                      {
                        'id': 's',
                        'tool': 'danbooru_search_tags',
                        'args': {'query': 'silver hair'},
                      },
                      {
                        'id': 'u',
                        'tool': 'update_studio_parameters',
                        'args': {'prompt': '@s.tags'},
                      },
                    ],
                  },
                ),
              ),
            ];
          }
          return [ContentDeltaEvent('已完成同步。')];
        });

        harness = AgentHarness(
          tools: registry,
          provider: provider,
          initialPreset: const AgentPreset(
            id: 'compact-test',
            name: 'Compact',
            description: '',
            systemPrompt: 'base system',
            enabledToolNames: [
              'update_studio_parameters',
              'danbooru_search_tags',
              'run_pipeline',
              'describe_tools',
            ],
          ),
        )..compactToolSurface = true;

        registry.register(
          RunPipelineTool(
            registry: registry,
            isToolAllowed: harness.isToolExecutionAllowed,
          ),
        );
        registry.register(
          DescribeToolsTool(
            registry: registry,
            isToolAllowed: harness.isToolExecutionAllowed,
          ),
        );

        await harness.send('画银发少女').toList();

        expect(sentToolNames, hasLength(2));
        expect(
          sentToolNames[0],
          unorderedEquals([
            'update_studio_parameters',
            'run_pipeline',
            'describe_tools',
          ]),
        );
        expect(sentToolNames[1], equals(sentToolNames[0]));
        expect(capturedSystem, contains('<secondary_tools>'));
        expect(
          capturedSystem,
          contains('danbooru_search_tags(query): Danbooru 语义搜词'),
        );
        expect(
          updateTool.lastArgs?['prompt'],
          'silver_hair, moonlit_night, extra_noise',
        );
        harness.dispose();
      },
    );

    test(
      'context_notes are appended after history to preserve KV prefix cache',
      () async {
        List<AgentMessage> captured = [];
        final h = AgentHarness(
          tools: ToolRegistry(),
          provider: MockLlmProvider((messages, _) {
            captured = messages;
            return [ContentDeltaEvent('ok')];
          }),
        );
        h.restoreMessages([
          AgentMessage(id: 'u1', role: AgentRole.user, content: 'first user'),
          AgentMessage(
            id: 'a1',
            role: AgentRole.assistant,
            content: 'first assistant',
          ),
        ]);
        h.memory.addNote('角色保持短发');

        await h.send('second user').toList();
        final rolesAndIds = captured.map((m) => m.id).toList();
        expect(rolesAndIds.first, 'system_prompt');
        expect(rolesAndIds.indexOf('u1'), 1);
        expect(rolesAndIds.indexOf('a1'), 2);
        expect(rolesAndIds.last, 'context_notes');
        h.dispose();
      },
    );
  });

  group('Provider Cache & Safety Filter Improvements', () {
    test('PromptCachePolicy auto enables anthropic mode for api.anthropic.com', () {
      final policy = PromptCachePolicy(
        config: const LlmCacheConfig(),
        endpoint: Uri.parse('https://api.anthropic.com/v1/messages'),
        model: 'claude-sonnet-4',
      );
      expect(policy.mode, LlmCacheMode.anthropic);
    });

    test(
      'OpenAiCompatibleProvider applies cache hints when streaming is false and detects content_filter without 3x retry',
      () async {
        late Map<String, dynamic> capturedBody;
        var calls = 0;
        final provider = OpenAiCompatibleProvider(
          baseUrl: 'https://api.openai.com/v1',
          apiKey: 'test-key',
          model: 'gpt-test',
          streaming: false,
          client: MockClient.streaming((req, stream) async {
            calls++;
            capturedBody =
                jsonDecode(utf8.decode(await stream.toBytes()))
                    as Map<String, dynamic>;
            return http.StreamedResponse(
              Stream.value(
                utf8.encode(
                  jsonEncode({
                    'choices': [
                      {
                        'finish_reason': 'content_filter',
                        'message': {'role': 'assistant', 'content': ''},
                      },
                    ],
                  }),
                ),
              ),
              200,
            );
          }),
        );

        final h = AgentHarness(
          tools: ToolRegistry(),
          provider: provider,
          retryBaseDelay: Duration.zero,
        );
        final events = await h.send('hello').toList();
        expect(capturedBody['prompt_cache_key'], isNull); // no recorder -> null
        expect(capturedBody.containsKey('stream_options'), isFalse);
        expect(calls, 1);
        expect(
          events.whereType<ErrorEvent>().single.error,
          contains('content_filter'),
        );
        h.dispose();

        // Also verify prompt_cache_key is sent on non-streaming when provided
        final eventsDirect = await provider
            .streamChat(messages: [], tools: [], promptCacheKey: 'sess-1')
            .toList();
        expect(capturedBody['prompt_cache_key'], 'sess-1');
        expect(eventsDirect.whereType<ErrorEvent>(), hasLength(1));
      },
    );

    test(
      'OpenAiCompatibleProvider streaming content_filter emits non-transient error',
      () async {
        var calls = 0;
        final provider = OpenAiCompatibleProvider(
          baseUrl: 'https://proxy.example/v1',
          apiKey: 'test-key',
          model: 'gemini-test',
          client: MockClient.streaming((req, stream) async {
            calls++;
            final sse =
                'data: ${jsonEncode({
                  'choices': [
                    {'delta': {}, 'finish_reason': 'content_filter'},
                  ],
                  'usage': {'prompt_tokens': 50, 'completion_tokens': 0},
                })}\n\n'
                'data: [DONE]\n\n';
            return http.StreamedResponse(Stream.value(utf8.encode(sse)), 200);
          }),
        );
        final h = AgentHarness(
          tools: ToolRegistry(),
          provider: provider,
          retryBaseDelay: Duration.zero,
        );
        final events = await h.send('test').toList();
        expect(calls, 1);
        expect(
          events.whereType<ErrorEvent>().single.error,
          contains('content_filter'),
        );
        expect(events.whereType<UsageEvent>().single.usage.input, 50);
        h.dispose();
      },
    );

    test(
      'GoogleInteractionsProvider passes temperature, drops foreign affinity headers on official host, and surfaces incomplete SSE status',
      () async {
        late Map<String, dynamic> capturedBody;
        late Map<String, String> capturedHeaders;
        var calls = 0;

        final provider = GoogleInteractionsProvider(
          apiKey: 'goog-key',
          modelId: 'gemini-4-hydrogen',
          cacheConfig: const LlmCacheConfig(affinity: LlmCacheAffinity.openai),
          client: MockClient.streaming((req, stream) async {
            calls++;
            capturedHeaders = req.headers;
            capturedBody =
                jsonDecode(utf8.decode(await stream.toBytes()))
                    as Map<String, dynamic>;
            final sse =
                'event: interaction.completed\n'
                'data: ${jsonEncode({
                  'interaction': {
                    'status': 'incomplete',
                    'incomplete_reason': 'SAFETY',
                    'usage': {'total_input_tokens': 80, 'total_output_tokens': 0},
                  },
                })}\n\n';
            return http.StreamedResponse(Stream.value(utf8.encode(sse)), 200);
          }),
        );

        final h = AgentHarness(
          tools: ToolRegistry(),
          provider: provider,
          retryBaseDelay: Duration.zero,
        );
        final events = await h.send('test', temperature: 0.9).toList();
        expect(capturedBody['generation_config']['temperature'], 0.9);
        expect(capturedHeaders.containsKey('session_id'), isFalse);
        expect(calls, 1);
        expect(
          events.whereType<ErrorEvent>().single.error,
          contains('SAFETY'),
        );
        expect(events.whereType<UsageEvent>().single.usage.input, 80);
        h.dispose();
      },
    );

    test('character prompt tools notify onCustomPositionUsed when coordinates are passed', () async {
      var characters = <NaiCharacterPrompt>[];
      var customCoordsTriggered = 0;
      final add = NovelAiAddCharacterPromptTool(
        getCharacterPrompts: () => characters,
        updateCharacterPrompts: (value) => characters = value,
        onCustomPositionUsed: () => customCoordsTriggered++,
      );
      final res = await add.execute('c1', {
        'prompt': 'girl, blue hair',
        'position_x': 0.3,
        'position_y': 0.5,
      });
      expect(res.isError, isFalse);
      expect(customCoordsTriggered, 1);
      expect(res.content, contains('自定义定位'));
    });

    test(
      'proxied Gemini model IDs attach thought_signature, clamp effort, and detect SAFETY/refusal across protocols',
      () async {
        // 1. OpenAI chat proxy with google/gemini-3-pro: clamps xhigh->high and replays dummy thought_signature
        late Map<String, dynamic> chatBody;
        var chatCalls = 0;
        final chatProxy = OpenAiCompatibleProvider(
          baseUrl: 'https://proxy.example/v1/chat/completions',
          apiKey: 'proxy-key',
          model: 'google/gemini-3-pro',
          reasoning: true,
          thinkingEffort: 'xhigh',
          client: MockClient.streaming((req, stream) async {
            chatCalls++;
            chatBody =
                jsonDecode(utf8.decode(await stream.toBytes()))
                    as Map<String, dynamic>;
            final sse =
                'data: ${jsonEncode({
                  'choices': [
                    {'delta': {}, 'finish_reason': 'SAFETY'},
                  ],
                })}\n\n'
                'data: [DONE]\n\n';
            return http.StreamedResponse(Stream.value(utf8.encode(sse)), 200);
          }),
        );
        final chatEvents = await chatProxy
            .streamChat(
              messages: [
                AgentMessage(id: 'u1', role: AgentRole.user, content: 'hi'),
                AgentMessage(
                  id: 'a1',
                  role: AgentRole.assistant,
                  toolCalls: const [
                    ToolCall(id: 'call_1', name: 't', arguments: {}),
                  ],
                ),
                AgentMessage(
                  id: 't1',
                  role: AgentRole.tool,
                  toolCallId: 'call_1',
                  toolName: 't',
                  content: 'ok',
                ),
              ],
              tools: [],
            )
            .toList();
        expect(chatCalls, 1);
        expect(chatBody['reasoning_effort'], 'high');
        final replayedTc =
            (chatBody['messages'] as List)[1]['tool_calls'][0] as Map;
        expect(
          replayedTc['extra_content']['google']['thought_signature'],
          'skip_thought_signature_validator',
        );
        expect(
          chatEvents.whereType<ErrorEvent>().single.error,
          contains('SAFETY'),
        );

        // 2. OpenAI chat streaming delta.refusal is surfaced as non-transient error
        final refusalProxy = OpenAiCompatibleProvider(
          baseUrl: 'https://proxy.example/v1/chat/completions',
          apiKey: 'proxy-key',
          model: '[渠道]gemini-2.5-pro',
          client: MockClient.streaming((req, stream) async {
            final sse =
                'data: ${jsonEncode({
                  'choices': [
                    {
                      'delta': {'refusal': 'policy blocked'},
                      'finish_reason': 'stop',
                    },
                  ],
                })}\n\n'
                'data: [DONE]\n\n';
            return http.StreamedResponse(Stream.value(utf8.encode(sse)), 200);
          }),
        );
        final hRefusal = AgentHarness(
          tools: ToolRegistry(),
          provider: refusalProxy,
          retryBaseDelay: Duration.zero,
        );
        final refusalEvents = await hRefusal.send('hi').toList();
        expect(
          refusalEvents.whereType<ErrorEvent>().single.error,
          contains('policy blocked'),
        );
        hRefusal.dispose();

        // 3. Anthropic /messages proxy surfaces message_delta stop_reason refusal without retries
        var anthropicCalls = 0;
        final anthropicProxy = OpenAiCompatibleProvider(
          baseUrl: 'https://proxy.example/v1/messages',
          apiKey: 'proxy-key',
          model: 'google/gemini-3-pro',
          client: MockClient.streaming((req, stream) async {
            anthropicCalls++;
            final sse =
                'event: message_start\n'
                'data: ${jsonEncode({'type': 'message_start', 'message': {}})}\n\n'
                'event: message_delta\n'
                'data: ${jsonEncode({
                  'type': 'message_delta',
                  'delta': {'stop_reason': 'refusal'},
                  'usage': {'input_tokens': 20, 'output_tokens': 0},
                })}\n\n'
                'event: message_stop\n'
                'data: ${jsonEncode({'type': 'message_stop'})}\n\n';
            return http.StreamedResponse(Stream.value(utf8.encode(sse)), 200);
          }),
        );
        final hAnthropic = AgentHarness(
          tools: ToolRegistry(),
          provider: anthropicProxy,
          retryBaseDelay: Duration.zero,
        );
        final anthropicEvents = await hAnthropic.send('hi').toList();
        expect(anthropicCalls, 1);
        expect(
          anthropicEvents.whereType<ErrorEvent>().single.error,
          contains('拒绝'),
        );
        hAnthropic.dispose();
      },
    );
  });

  group('MCP protocol and CodeMode integration', () {
    test('parseMcpServersJson parses standard mcpServers format and round-trips', () {
      const raw = '''
      {
        "mcpServers": {
          "context7": {
            "url": "https://mcp.context7.com/mcp",
            "headers": {"Authorization": "Bearer secret"}
          },
          "local-fs": {
            "command": "npx",
            "args": ["-y", "@modelcontextprotocol/server-filesystem", "D:/Work"],
            "env": {"NODE_ENV": "production"}
          }
        }
      }
      ''';
      final servers = McpServerConfig.parseMcpServersJson(raw);
      expect(servers, hasLength(2));
      expect(servers[0].id, 'context7');
      expect(servers[0].transport, McpTransportType.http);
      expect(servers[0].headers['Authorization'], 'Bearer secret');
      expect(servers[1].id, 'local-fs');
      expect(servers[1].transport, McpTransportType.stdio);
      expect(servers[1].args, hasLength(3));

      final encoded = McpServerConfig.encodeMcpServersJson(servers);
      final reparsed = McpServerConfig.parseMcpServersJson(encoded);
      expect(reparsed.map((s) => s.id), ['context7', 'local-fs']);
    });

    test('HttpMcpClient handles Streamable HTTP JSON, SSE and Mcp-Session-Id', () async {
      String? capturedSessionHeader;
      final mockClient = MockClient((req) async {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        final method = body['method'] as String;
        final id = body['id'];
        if (method == 'initialize') {
          return http.Response(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': id,
              'result': {'protocolVersion': '2025-03-26'},
            }),
            200,
            headers: {
              'content-type': 'application/json',
              'mcp-session-id': 'sess_123',
            },
          );
        }
        if (method == 'notifications/initialized') {
          return http.Response('', 202);
        }
        capturedSessionHeader = req.headers['Mcp-Session-Id'];
        if (method == 'tools/list') {
          // 模拟 text/event-stream SSE 响应
          final sse =
              'event: message\n'
              'data: ${jsonEncode({
                'jsonrpc': '2.0',
                'id': id,
                'result': {
                  'tools': [
                    {
                      'name': 'search_docs',
                      'description': 'Search documentation',
                      'inputSchema': {
                        'type': 'object',
                        'properties': {
                          'q': {'type': 'string'},
                        },
                        'required': ['q'],
                      },
                    },
                  ],
                },
              })}\n\n';
          return http.Response(
            sse,
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        }
        if (method == 'tools/call') {
          return http.Response(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': id,
              'result': {
                'content': [
                  {'type': 'text', 'text': 'doc result: flutter'},
                ],
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('not found', 404);
      });

      final client = HttpMcpClient(
        config: const McpServerConfig(
          id: 'docs',
          name: 'Docs MCP',
          transport: McpTransportType.http,
          url: 'https://example.com/mcp',
        ),
        client: mockClient,
      );

      final tools = await client.listTools();
      expect(capturedSessionHeader, 'sess_123');
      expect(tools, hasLength(1));
      expect(tools.single.exposedName, 'mcp_docs_search_docs');

      final callResult = await client.callTool('search_docs', {'q': 'flutter'});
      expect(callResult.isError, isFalse);
      expect(callResult.text, 'doc result: flutter');
      await client.close();
    });

    test('MCP tools stay in CodeMode secondary surface and execute via run_pipeline', () async {
      final registry = ToolRegistry();
      final mcpTool = McpAgentTool(
        descriptor: const McpToolDescriptor(
          serverId: 'docs',
          serverName: 'Docs',
          originalName: 'lookup',
          exposedName: 'mcp_docs_lookup',
          description: 'Lookup reference docs',
          inputSchema: {
            'type': 'object',
            'properties': {
              'topic': {'type': 'string'},
            },
            'required': ['topic'],
          },
        ),
        invoke: (args) async =>
            McpCallResult(text: 'found: ${args['topic']}'),
      );
      registry.register(mcpTool);

      final sentTopLevelTools = <List<String>>[];
      String? capturedSystem;
      var turn = 0;
      final provider = MockLlmProvider((messages, tools) {
        turn++;
        capturedSystem = messages.first.content;
        sentTopLevelTools.add(tools.map((t) => t.name).toList());
        if (turn == 1) {
          return [
            ToolCallEvent(
              const ToolCall(
                id: 'mcp_pipe',
                name: 'run_pipeline',
                arguments: {
                  'steps': [
                    {
                      'id': 'doc',
                      'tool': 'mcp_docs_lookup',
                      'args': {'topic': 'lighting'},
                    },
                  ],
                },
              ),
            ),
          ];
        }
        return [ContentDeltaEvent('done')];
      });

      final harness = AgentHarness(
        tools: registry,
        provider: provider,
        initialPreset: const AgentPreset(
          id: 'mcp-preset',
          name: 'MCP Test',
          description: '',
          systemPrompt: 'sys',
          enabledToolNames: ['run_pipeline', 'describe_tools'],
          allowMcpTools: true,
        ),
      )..compactToolSurface = true;

      registry.register(
        RunPipelineTool(
          registry: registry,
          isToolAllowed: harness.isToolExecutionAllowed,
        ),
      );
      registry.register(
        DescribeToolsTool(
          registry: registry,
          isToolAllowed: harness.isToolExecutionAllowed,
        ),
      );

      final events = await harness.send('查光照文档').toList();
      expect(sentTopLevelTools.first, isNot(contains('mcp_docs_lookup')));
      expect(capturedSystem, contains('<secondary_tools>'));
      expect(capturedSystem, contains('mcp_docs_lookup(topic)'));
      final toolResult = events.whereType<ToolResultEvent>().single;
      expect(toolResult.result.isError, isFalse);
      expect(toolResult.result.content, contains('found: lighting'));

      // 关闭 allowMcpTools 时拒绝调用
      harness.setPreset(
        harness.currentPreset.copyWith(allowMcpTools: false),
      );
      expect(harness.isToolExecutionAllowed('mcp_docs_lookup'), isFalse);
      harness.dispose();
    });
  });
}
