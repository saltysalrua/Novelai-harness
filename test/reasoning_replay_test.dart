import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:novelai_harness/core/harness/agent_harness.dart';
import 'package:novelai_harness/core/harness/presets/agent_preset.dart';
import 'package:novelai_harness/core/harness/providers/anthropic_messages.dart';
import 'package:novelai_harness/core/harness/providers/google_interactions_provider.dart';
import 'package:novelai_harness/core/harness/providers/llm_provider.dart';
import 'package:novelai_harness/core/harness/providers/openai_provider.dart';
import 'package:novelai_harness/core/harness/providers/openai_responses.dart';
import 'package:novelai_harness/core/harness/tools/agent_tool.dart';
import 'package:novelai_harness/core/harness/types.dart';
import 'package:novelai_harness/data/services/session_log_service.dart';

class _LookupTool extends AgentTool {
  const _LookupTool()
    : super(
        name: 'lookup',
        label: 'Lookup',
        description: 'Look up a value.',
        parameters: const {
          'type': 'object',
          'properties': {
            'q': {'type': 'string'},
          },
          'required': ['q'],
        },
      );

  @override
  Future<ToolResult> execute(
    String toolCallId,
    Map<String, dynamic> args,
  ) async => ToolResult(toolCallId: toolCallId, content: '${args['q']}');
}

class _EchoTool extends AgentTool {
  _EchoTool()
    : super(
        name: 'echo_test',
        label: 'Echo',
        description: 'Echo.',
        parameters: const {
          'type': 'object',
          'properties': {
            'text': {'type': 'string'},
          },
        },
      );

  @override
  Future<ToolResult> execute(
    String toolCallId,
    Map<String, dynamic> args,
  ) async => ToolResult(toolCallId: toolCallId, content: 'ok');
}

class _ScriptedProvider implements LlmProvider {
  final List<List<AgentMessage>> seen = [];
  final List<HarnessEvent> Function(List<AgentMessage> messages) script;

  _ScriptedProvider(this.script);

  @override
  String get modelId => 'mock-model';

  @override
  Stream<HarnessEvent> streamChat({
    required List<AgentMessage> messages,
    required List<AgentTool> tools,
    double temperature = 0.7,
    String? promptCacheKey,
  }) async* {
    seen.add(messages);
    for (final event in script(messages)) {
      yield event;
    }
  }
}

http.StreamedResponse _sse(List<Map<String, dynamic>> events) {
  final body = events.map((event) {
    final type = event['type'] ?? event['event'] ?? '';
    return 'event: $type\ndata: ${jsonEncode(event)}\n\n';
  }).join();
  return http.StreamedResponse(
    http.ByteStream.fromBytes(utf8.encode(body)),
    200,
    headers: {'content-type': 'text/event-stream'},
  );
}

http.StreamedResponse _json(Map<String, dynamic> body) {
  return http.StreamedResponse(
    http.ByteStream.fromBytes(utf8.encode(jsonEncode(body))),
    200,
    headers: {'content-type': 'application/json'},
  );
}

void main() {
  group('Responses 推理回放', () {
    test('开启推理时请求 encrypted_content，并保持 store=false', () {
      final body = OpenAiResponses.buildRequestBody(
        model: 'gpt-5',
        messages: [AgentMessage(id: 'u', role: AgentRole.user, content: 'Hi')],
        tools: const [],
        reasoningEffort: 'high',
        stream: true,
      );

      expect(body['include'], ['reasoning.encrypted_content']);
      expect(body['store'], isFalse);
      expect(body.containsKey('previous_response_id'), isFalse);
      expect(body['reasoning'], {'effort': 'high', 'summary': 'auto'});
    });

    test('推理项按原顺序放在对应助手消息和 function_call 之前', () {
      final body = OpenAiResponses.buildRequestBody(
        model: 'gpt-5',
        messages: [
          AgentMessage(id: 'u1', role: AgentRole.user, content: '画一张'),
          AgentMessage(
            id: 'a1',
            role: AgentRole.assistant,
            content: '好',
            thoughts: '这段可见思考不应再单独变成一项',
            reasoningRecords: const [
              ReasoningRecord(
                id: 'rs_enc',
                encryptedContent: 'enc_payload',
                summary: [
                  {'type': 'summary_text', 'text': '先看构图'},
                ],
              ),
              ReasoningRecord(
                summary: [
                  {'type': 'summary_text', 'text': '再看颜色'},
                ],
                content: [
                  {'type': 'reasoning_text', 'text': '明文推理'},
                ],
              ),
            ],
            toolCalls: const [
              ToolCall(id: 'call_1', name: 'lookup', arguments: {'q': 'cat'}),
            ],
          ),
          AgentMessage(
            id: 't1',
            role: AgentRole.tool,
            toolCallId: 'call_1',
            content: 'found',
          ),
          AgentMessage(id: 'a2', role: AgentRole.assistant, thoughts: '只有思考文本'),
        ],
        tools: const [_LookupTool()],
        reasoningEffort: 'medium',
      );

      final input = body['input'] as List;
      expect(input[0]['role'], 'user');
      expect(input[1], {
        'type': 'reasoning',
        'id': 'rs_enc',
        'encrypted_content': 'enc_payload',
        'summary': [
          {'type': 'summary_text', 'text': '先看构图'},
        ],
      });
      final plaintext = input[2] as Map<String, dynamic>;
      expect(plaintext.containsKey('id'), isFalse);
      expect(plaintext['type'], 'reasoning');
      expect(plaintext['content'], [
        {'type': 'reasoning_text', 'text': '明文推理'},
      ]);
      expect(plaintext['summary'], [
        {'type': 'summary_text', 'text': '再看颜色'},
      ]);
      expect(input[3]['role'], 'assistant');
      expect(input[4], {
        'type': 'function_call',
        'call_id': 'call_1',
        'name': 'lookup',
        'arguments': '{"q":"cat"}',
      });
      expect(input[5]['type'], 'function_call_output');
      final fallback = input[6] as Map<String, dynamic>;
      expect(fallback.containsKey('id'), isFalse);
      expect(fallback.containsKey('encrypted_content'), isFalse);
      expect(fallback['content'], [
        {'type': 'reasoning_text', 'text': '只有思考文本'},
      ]);
    });

    test('流式摘要之后仍保存 encrypted_content，且不重复、不编造 id', () {
      final parser = OpenAiResponsesStreamParser();
      final events = [
        ...parser.add({
          'type': 'response.reasoning_summary_text.delta',
          'output_index': 0,
          'delta': '先想',
        }),
        ...parser.add({
          'type': 'response.output_item.done',
          'output_index': 0,
          'item': {
            'type': 'reasoning',
            'id': 'rs_1',
            'encrypted_content': 'cipher',
            'summary': [
              {'type': 'summary_text', 'text': '先想'},
            ],
          },
        }),
        ...parser.add({
          'type': 'response.output_item.done',
          'output_index': 1,
          'item': {
            'type': 'reasoning',
            'content': [
              {'type': 'reasoning_text', 'text': '网关明文'},
            ],
          },
        }),
        ...parser.add({
          'type': 'response.completed',
          'response': {
            'output': [
              {
                'type': 'reasoning',
                'id': 'rs_1',
                'encrypted_content': 'cipher',
                'summary': [
                  {'type': 'summary_text', 'text': '先想'},
                ],
              },
              {
                'type': 'reasoning',
                'content': [
                  {'type': 'reasoning_text', 'text': '网关明文'},
                ],
              },
            ],
          },
        }),
        ...parser.finish(),
      ];

      expect(
        events.whereType<ThoughtDeltaEvent>().map((e) => e.delta).toList(),
        ['先想', '网关明文'],
      );
      final snapshot = events.whereType<ReasoningSnapshotEvent>().single;
      expect(snapshot.records, hasLength(2));
      expect(snapshot.records[0].id, 'rs_1');
      expect(snapshot.records[0].encryptedContent, 'cipher');
      expect(snapshot.records[1].id, isNull);
      expect(snapshot.records[1].plaintext, '网关明文');
      expect(snapshot.records[1].toResponsesItem()!.containsKey('id'), isFalse);
    });

    test('非流式响应保留推理项，下一轮工具循环会回放', () async {
      final bodies = <Map<String, dynamic>>[];
      final client = MockClient.streaming((request, bodyStream) async {
        bodies.add(
          jsonDecode(await bodyStream.bytesToString()) as Map<String, dynamic>,
        );
        if (bodies.length == 1) {
          return _json({
            'output': [
              {
                'type': 'reasoning',
                'id': 'rs_loop',
                'encrypted_content': 'loop_enc',
                'summary': [
                  {'type': 'summary_text', 'text': '调用工具前'},
                ],
              },
              {
                'type': 'function_call',
                'call_id': 'call_9',
                'name': 'lookup',
                'arguments': '{"q":"x"}',
              },
            ],
            'usage': {'input_tokens': 3, 'output_tokens': 2},
          });
        }
        return _json({
          'output': [
            {
              'type': 'message',
              'content': [
                {'type': 'output_text', 'text': 'done'},
              ],
            },
          ],
        });
      });
      final provider = OpenAiCompatibleProvider(
        baseUrl: 'https://api.test/v1/responses',
        apiKey: 'test-key',
        model: 'gpt-5',
        reasoning: true,
        thinkingEffort: 'low',
        client: client,
      );
      final first = await provider
          .streamChat(
            messages: [
              AgentMessage(id: 'u', role: AgentRole.user, content: 'go'),
            ],
            tools: const [_LookupTool()],
          )
          .toList();
      final snapshot = first.whereType<ReasoningSnapshotEvent>().single;
      final call = first.whereType<ToolCallEvent>().single.toolCall;

      await provider
          .streamChat(
            messages: [
              AgentMessage(id: 'u', role: AgentRole.user, content: 'go'),
              AgentMessage(
                id: 'a',
                role: AgentRole.assistant,
                thoughts: '调用工具前',
                reasoningRecords: snapshot.records,
                toolCalls: [call],
              ),
              AgentMessage(
                id: 't',
                role: AgentRole.tool,
                toolCallId: call.id,
                content: 'found',
              ),
            ],
            tools: const [_LookupTool()],
          )
          .toList();

      expect(bodies.first['include'], ['reasoning.encrypted_content']);
      expect(bodies.first['store'], isFalse);
      final replayed = (bodies[1]['input'] as List).cast<Map>();
      expect(replayed[1]['type'], 'reasoning');
      expect(replayed[1]['id'], 'rs_loop');
      expect(replayed[1]['encrypted_content'], 'loop_enc');
      expect(replayed[2]['type'], 'function_call');
      expect(replayed[2]['call_id'], 'call_9');
      expect(
        replayed.where((item) => item['type'] == 'reasoning'),
        hasLength(1),
      );
    });
  });

  group('Anthropic thinking 回放', () {
    test('thinking、redacted_thinking 原样位于 tool_use 之前，tool_result 紧随其后', () {
      final body = AnthropicMessages.buildRequestBody(
        model: 'claude-sonnet-5',
        messages: [
          AgentMessage(id: 's', role: AgentRole.system, content: '规则'),
          AgentMessage(id: 'u', role: AgentRole.user, content: '查一下'),
          AgentMessage(
            id: 'a',
            role: AgentRole.assistant,
            content: '我来查',
            thoughts: '不应覆盖结构化块',
            thoughtSignature: 'msg_sig_unused',
            reasoningRecords: const [
              ReasoningRecord(
                content: [
                  {'type': 'reasoning_text', 'text': '先推理'},
                ],
                signature: 'sig_thinking_1',
              ),
              ReasoningRecord(redactedData: 'redacted_blob'),
            ],
            toolCalls: const [
              ToolCall(id: 'toolu_1', name: 'lookup', arguments: {'q': 'cat'}),
            ],
          ),
          AgentMessage(
            id: 't',
            role: AgentRole.tool,
            toolCallId: 'toolu_1',
            toolName: 'lookup',
            content: 'found',
          ),
        ],
        tools: const [_LookupTool()],
        reasoning: true,
        thinkingEffort: 'high',
        temperature: 0.2,
      );

      expect(body.containsKey('temperature'), isFalse);
      expect(body['thinking'], {'type': 'enabled', 'budget_tokens': 16384});
      expect(body['max_tokens'], greaterThan(16384));
      expect(body['system'], '规则');
      final messages = body['messages'] as List;
      expect(messages[0]['role'], 'user');
      final assistant = messages[1]['content'] as List;
      expect(assistant[0], {
        'type': 'thinking',
        'thinking': '先推理',
        'signature': 'sig_thinking_1',
      });
      expect(assistant[1], {
        'type': 'redacted_thinking',
        'data': 'redacted_blob',
      });
      expect(assistant[2], {'type': 'text', 'text': '我来查'});
      expect(assistant[3], {
        'type': 'tool_use',
        'id': 'toolu_1',
        'name': 'lookup',
        'input': {'q': 'cat'},
      });
      expect(messages[2], {
        'role': 'user',
        'content': [
          {'type': 'tool_result', 'tool_use_id': 'toolu_1', 'content': 'found'},
        ],
      });
    });

    test('只有消息级签名时补到 thinking 块上，不改已有签名', () {
      final blocks = AnthropicMessages.assistantBlocks(
        AgentMessage(
          id: 'a',
          role: AgentRole.assistant,
          thoughts: '旧思考',
          thoughtSignature: 'kept_sig',
        ),
      );
      expect(blocks.single, {
        'type': 'thinking',
        'thinking': '旧思考',
        'signature': 'kept_sig',
      });
    });

    test('SSE 保留 signature 与 redacted_thinking，工具循环原样回放', () async {
      final bodies = <Map<String, dynamic>>[];
      final client = MockClient.streaming((request, bodyStream) async {
        bodies.add(
          jsonDecode(await bodyStream.bytesToString()) as Map<String, dynamic>,
        );
        if (bodies.length > 1) {
          return _sse([
            {
              'type': 'content_block_start',
              'index': 0,
              'content_block': {'type': 'text', 'text': ''},
            },
            {
              'type': 'content_block_delta',
              'index': 0,
              'delta': {'type': 'text_delta', 'text': 'done'},
            },
            {'type': 'message_stop'},
          ]);
        }
        return _sse([
          {
            'type': 'content_block_start',
            'index': 0,
            'content_block': {'type': 'thinking', 'thinking': ''},
          },
          {
            'type': 'content_block_delta',
            'index': 0,
            'delta': {'type': 'thinking_delta', 'thinking': '先推理'},
          },
          {
            'type': 'content_block_delta',
            'index': 0,
            'delta': {'type': 'signature_delta', 'signature': 'sig_live'},
          },
          {
            'type': 'content_block_start',
            'index': 1,
            'content_block': {
              'type': 'redacted_thinking',
              'data': 'redacted_live',
            },
          },
          {
            'type': 'content_block_start',
            'index': 2,
            'content_block': {
              'type': 'tool_use',
              'id': 'toolu_9',
              'name': 'lookup',
            },
          },
          {
            'type': 'content_block_delta',
            'index': 2,
            'delta': {'type': 'input_json_delta', 'partial_json': '{"q":"x"}'},
          },
          {'type': 'content_block_stop', 'index': 2},
          {
            'type': 'message_delta',
            'delta': {'stop_reason': 'tool_use'},
            'usage': {'output_tokens': 4},
          },
          {
            'type': 'message_start',
            'message': {
              'usage': {'input_tokens': 8, 'cache_read_input_tokens': 0},
            },
          },
          {'type': 'message_stop'},
        ]);
      });
      final provider = OpenAiCompatibleProvider(
        baseUrl: 'https://api.anthropic.com/v1/messages',
        apiKey: 'test-key',
        model: 'claude-sonnet-5',
        reasoning: true,
        thinkingEffort: 'medium',
        client: client,
      );
      final first = await provider
          .streamChat(
            messages: [
              AgentMessage(id: 'u', role: AgentRole.user, content: 'go'),
            ],
            tools: const [_LookupTool()],
          )
          .toList();
      final snapshot = first.whereType<ReasoningSnapshotEvent>().single;
      expect(snapshot.records[0].signature, 'sig_live');
      expect(snapshot.records[0].plaintext, '先推理');
      expect(snapshot.records[1].redactedData, 'redacted_live');
      expect(
        first.whereType<ThoughtSignatureEvent>().single.signature,
        'sig_live',
      );
      final call = first.whereType<ToolCallEvent>().single.toolCall;
      expect(call.arguments, {'q': 'x'});

      await provider
          .streamChat(
            messages: [
              AgentMessage(id: 'u', role: AgentRole.user, content: 'go'),
              AgentMessage(
                id: 'a',
                role: AgentRole.assistant,
                thoughts: '先推理',
                thoughtSignature: 'sig_live',
                reasoningRecords: snapshot.records,
                toolCalls: [call],
              ),
              AgentMessage(
                id: 't',
                role: AgentRole.tool,
                toolCallId: call.id,
                content: 'found',
              ),
            ],
            tools: const [_LookupTool()],
          )
          .toList();

      final replay = (bodies[1]['messages'] as List)[1]['content'] as List;
      expect(replay[0]['signature'], 'sig_live');
      expect(replay[0]['thinking'], '先推理');
      expect(replay[1], {'type': 'redacted_thinking', 'data': 'redacted_live'});
      expect(replay[2]['type'], 'tool_use');
      expect(
        (bodies[1]['messages'] as List)[2]['content'][0]['type'],
        'tool_result',
      );
      expect(bodies.first.containsKey('messages'), isTrue);
      expect(bodies.first.containsKey('input'), isFalse);
    });
  });

  group('Google Interactions thought signature', () {
    test('function_call 带回 thought_signature，thought 步骤仍在其前面', () {
      final body = GoogleInteractionsProvider.buildRequestBody(
        messages: [
          AgentMessage(id: 'u', role: AgentRole.user, content: 'draw'),
          AgentMessage(
            id: 'a',
            role: AgentRole.assistant,
            thoughts: '先前思考',
            thoughtSignature: 'thought_sig',
            toolCalls: const [
              ToolCall(
                id: 'fc_1',
                name: 'lookup',
                arguments: {'q': 'cat'},
                thoughtSignature: 'fc_sig',
              ),
              ToolCall(id: 'fc_2', name: 'lookup', arguments: {'q': 'dog'}),
            ],
          ),
        ],
        tools: const [_LookupTool()],
        modelId: 'gemini-4-argon',
        reasoning: true,
        thinkingEffort: 'medium',
        promptToolUse: false,
      );
      final input = body['input'] as List;
      final thoughtIndex = input.indexWhere(
        (step) => step is Map && step['type'] == 'thought',
      );
      final firstCall = input.indexWhere(
        (step) => step is Map && step['id'] == 'fc_1',
      );
      final secondCall = input.indexWhere(
        (step) => step is Map && step['id'] == 'fc_2',
      );
      expect(thoughtIndex, lessThan(firstCall));
      expect(input[thoughtIndex]['signature'], 'thought_sig');
      expect(input[firstCall]['thought_signature'], 'fc_sig');
      expect(input[secondCall].containsKey('thought_signature'), isFalse);
    });

    test('函数调用自己的 thought_signature 优先于 thought 步骤签名', () async {
      late Map<String, dynamic> captured;
      final client = MockClient.streaming((request, bodyStream) async {
        captured =
            jsonDecode(await bodyStream.bytesToString())
                as Map<String, dynamic>;
        return _sse([
          {
            'event': 'step.delta',
            'step_id': 's_thought',
            'delta': {
              'type': 'thought',
              'text': 'thinking',
              'signature': 'thought_sig',
            },
          },
          {
            'event': 'step.start',
            'step_id': 's_call',
            'step': {
              'type': 'function_call',
              'id': 'fc_9',
              'name': 'lookup',
              'arguments': {'q': 'x'},
              'thought_signature': 'fc_sig',
            },
          },
          {'event': 'interaction.completed', 'interaction': {}},
        ]);
      });
      final provider = OpenAiCompatibleProvider(
        baseUrl:
            'https://generativelanguage.googleapis.com/v1beta/interactions',
        apiKey: 'goog-key',
        model: 'gemini-4-argon',
        reasoning: true,
        client: client,
      );
      final events = await provider
          .streamChat(
            messages: [
              AgentMessage(id: 'u', role: AgentRole.user, content: 'go'),
            ],
            tools: const [],
          )
          .toList();
      final call = events.whereType<ToolCallEvent>().single.toolCall;
      expect(call.thoughtSignature, 'fc_sig');
      expect(
        events.whereType<ThoughtSignatureEvent>().map((e) => e.signature),
        contains('thought_sig'),
      );

      await provider
          .streamChat(
            messages: [
              AgentMessage(id: 'u', role: AgentRole.user, content: 'go'),
              AgentMessage(
                id: 'a',
                role: AgentRole.assistant,
                thoughts: 'thinking',
                thoughtSignature: 'thought_sig',
                toolCalls: [call],
              ),
              AgentMessage(
                id: 't',
                role: AgentRole.tool,
                toolCallId: call.id,
                toolName: 'lookup',
                content: 'ok',
              ),
            ],
            tools: const [],
          )
          .toList();
      final input = captured['input'] as List;
      final thought = input.singleWhere(
        (step) => step is Map && step['type'] == 'thought',
      );
      final functionCall = input.singleWhere(
        (step) => step is Map && step['type'] == 'function_call',
      );
      expect(thought['signature'], 'thought_sig');
      expect(functionCall['thought_signature'], 'fc_sig');
    });
  });

  group('Chat Completions 推理回放保持原样', () {
    test('DeepSeek reasoning_content 仍是思考原文', () async {
      late Map<String, dynamic> body;
      final client = MockClient.streaming((request, bodyStream) async {
        body =
            jsonDecode(await bodyStream.bytesToString())
                as Map<String, dynamic>;
        return _sse([
          {'type': 'chat', 'choices': []},
        ]);
      });
      // Chat SSE 上面的事件不会被当成 Responses。补一条空的 data 结束。
      final provider = OpenAiCompatibleProvider(
        baseUrl: 'https://api.deepseek.com/v1/chat/completions',
        apiKey: 'test-key',
        model: 'deepseek-chat',
        reasoning: true,
        thinkingEffort: 'high',
        thinkingParamFormat: 'deepseek',
        client: client,
      );
      await provider
          .streamChat(
            messages: [
              AgentMessage(id: 'u', role: AgentRole.user, content: 'hi'),
              AgentMessage(
                id: 'a',
                role: AgentRole.assistant,
                thoughts: '  原始思考  ',
                toolCalls: const [
                  ToolCall(id: 'call_1', name: 'lookup', arguments: {'q': 'a'}),
                ],
              ),
              AgentMessage(
                id: 't',
                role: AgentRole.tool,
                toolCallId: 'call_1',
                content: 'ok',
              ),
            ],
            tools: const [_LookupTool()],
          )
          .toList();

      expect(body.containsKey('input'), isFalse);
      expect(body.containsKey('include'), isFalse);
      final assistant = (body['messages'] as List)[1] as Map<String, dynamic>;
      expect(assistant['reasoning_content'], '  原始思考  ');
      expect(assistant.containsKey('reasoning'), isFalse);
    });
  });

  test('同一轮工具循环和下一轮用户消息都保留推理记录', () async {
    final record = const ReasoningRecord(
      id: 'rs_harness',
      encryptedContent: 'enc_harness',
      content: [
        {'type': 'reasoning_text', 'text': '工具前'},
      ],
    );
    final provider = _ScriptedProvider((messages) {
      final hasTool = messages.any((message) => message.role == AgentRole.tool);
      if (!hasTool) {
        return [
          ThoughtDeltaEvent('工具前'),
          ReasoningSnapshotEvent([record]),
          ToolCallEvent(
            const ToolCall(
              id: 'call_h',
              name: 'echo_test',
              arguments: {'text': 'a'},
            ),
          ),
        ];
      }
      return [ContentDeltaEvent('完成')];
    });
    final harness = AgentHarness(
      tools: ToolRegistry()..register(_EchoTool()),
      provider: provider,
      initialPreset: const AgentPreset(
        id: 'replay',
        name: 'Replay',
        description: '',
        systemPrompt: '',
        enabledToolNames: ['echo_test'],
      ),
    )..compactionEnabled = false;

    await harness.send('第一轮').toList();
    final loopRequest = provider.seen[1];
    final assistant = loopRequest.lastWhere(
      (message) => message.role == AgentRole.assistant,
    );
    expect(assistant.reasoningRecords.single.encryptedContent, 'enc_harness');
    expect(assistant.reasoningRecords.single.id, 'rs_harness');

    await harness.send('下一轮').toList();
    final later = provider.seen.last
        .where((message) => message.role == AgentRole.assistant)
        .first;
    expect(later.reasoningRecords.single.id, 'rs_harness');
    expect(later.thoughts, '工具前');
  });

  test('会话记录在原有 thinking/toolCall 之后保存并可恢复推理项', () async {
    final dir = await Directory.systemTemp.createTemp('reasoning_replay');
    final service = SessionLogService();
    await service.init(baseDir: dir.path);
    service.recordMessage(
      AgentMessage(
        id: 'a1',
        role: AgentRole.assistant,
        content: '',
        thoughts: '思考中...',
        thoughtSignature: 'sig_old',
        reasoningRecords: const [
          ReasoningRecord(
            id: 'rs_saved',
            encryptedContent: 'enc_saved',
            content: [
              {'type': 'reasoning_text', 'text': '明文'},
            ],
            signature: 'sig_block',
          ),
          ReasoningRecord(redactedData: 'redacted_saved'),
        ],
        toolCalls: const [
          ToolCall(
            id: 'call_1',
            name: 'generate_image',
            arguments: {'prompt': 'catgirl'},
          ),
        ],
      ),
    );
    await service.flush();
    final lines = service.currentSessionFile!
        .readAsLinesSync()
        .map((line) => jsonDecode(line) as Map<String, dynamic>)
        .toList();
    final message = lines
        .map((entry) => entry['message'])
        .whereType<Map<String, dynamic>>()
        .firstWhere((item) => item['role'] == 'assistant');
    final parts = message['content'] as List;
    expect(parts[0]['type'], 'thinking');
    expect(parts[0]['thinking'], '思考中...');
    expect(parts[1]['type'], 'toolCall');
    expect(parts.last['type'], 'reasoning');
    expect(parts.last['redacted_data'], 'redacted_saved');

    final restored = service.loadLatestSession()!.messages.single;
    expect(restored.thoughts, '思考中...');
    expect(restored.thoughtSignature, 'sig_old');
    expect(restored.reasoningRecords, hasLength(2));
    expect(restored.reasoningRecords.first.id, 'rs_saved');
    expect(restored.reasoningRecords.first.encryptedContent, 'enc_saved');
    expect(restored.reasoningRecords.first.signature, 'sig_block');
    expect(restored.reasoningRecords.last.redactedData, 'redacted_saved');
    await dir.delete(recursive: true);
  });

  test('上下文估算计入跨轮回放的推理项', () async {
    final provider = _ScriptedProvider((messages) => [
      ThoughtDeltaEvent('思考'),
      ContentDeltaEvent('好'),
    ]);
    final harness = AgentHarness(
      tools: ToolRegistry(),
      provider: provider,
      initialPreset: const AgentPreset(
        id: 'estimate',
        name: 'Estimate',
        description: '',
        systemPrompt: '',
        enabledToolNames: [],
      ),
    )..compactionEnabled = false;

    await harness.send('问').toList();
    final baseline = harness.contextUsage.tokens;

    // 直接注入一条带大体积加密推理项的历史消息，模拟旧会话恢复后的状态。
    final injected = AgentMessage(
      id: 'a_enc',
      role: AgentRole.assistant,
      content: '历史回复',
      reasoningRecords: const [
        ReasoningRecord(encryptedContent: 'QUJD'),
        ReasoningRecord(
          content: [
            {'type': 'reasoning_text', 'text': '明文推理'},
          ],
        ),
      ],
    );
    harness.restoreMessages([injected]);

    final after = harness.contextUsage.tokens;
    // 'QUJD' 4 字符 base64 → 3 字节 → 不足 1 token；明文 4 字符中文 → 1 token。
    // 历史回复正文 4 字符也 → 1 token。宽松断言增量大于零且包含两项内容即可。
    expect(after - baseline, greaterThan(0));
    // 换成更长的加密载荷后估算必须继续上涨，证明 base64 载荷被计入。
    final longPayload = 'A' * 4000;
    harness.restoreMessages([
      AgentMessage(
        id: 'a_enc2',
        role: AgentRole.assistant,
        content: '',
        reasoningRecords: [
          ReasoningRecord(encryptedContent: longPayload),
        ],
      ),
    ]);
    expect(
      harness.contextUsage.tokens - after,
      greaterThanOrEqualTo(700),
    );
  });
}
