import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:novelai_harness/core/harness/providers/openai_provider.dart';
import 'package:novelai_harness/core/harness/providers/openai_responses.dart';
import 'package:novelai_harness/core/harness/tools/agent_tool.dart';
import 'package:novelai_harness/core/harness/types.dart';

const _png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4';

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

List<HarnessEvent> _parseSse(List<Map<String, dynamic>> events) {
  final parser = OpenAiResponsesStreamParser();
  return [for (final event in events) ...parser.add(event), ...parser.finish()];
}

List<ToolCall> _toolCalls(List<HarnessEvent> events) =>
    events.whereType<ToolCallEvent>().map((event) => event.toolCall).toList();

void main() {
  group('Responses 请求体', () {
    test('系统提示、对话、工具和采样参数按 Responses 形状写出', () {
      final body = OpenAiResponses.buildRequestBody(
        model: ' gpt-5 ',
        temperature: 0.4,
        topP: 0.9,
        maxTokens: 128,
        stream: true,
        reasoningEffort: 'high',
        previousResponseId: ' resp_prev ',
        messages: [
          AgentMessage(
            id: 's1',
            role: AgentRole.system,
            content: 'You are helpful.',
          ),
          AgentMessage(id: 's2', role: AgentRole.system, content: 'Be terse.'),
          AgentMessage(
            id: 'u1',
            role: AgentRole.user,
            content: 'Look',
            images: const [AgentMessageImage(base64: _png)],
          ),
          AgentMessage(
            id: 'a1',
            role: AgentRole.assistant,
            content: 'Calling',
            toolCalls: const [
              ToolCall(id: 'call_1', name: 'lookup', arguments: {'q': 'x'}),
            ],
          ),
          AgentMessage(
            id: 't1',
            role: AgentRole.tool,
            toolCallId: 'call_1',
            toolName: 'lookup',
            content: 'found',
            imageBase64: _png,
          ),
          AgentMessage(id: 'a2', role: AgentRole.assistant, content: 'Done'),
        ],
        tools: const [_LookupTool()],
      );

      expect(body['model'], 'gpt-5');
      expect(body['instructions'], 'You are helpful.\n\nBe terse.');
      expect(body.containsKey('messages'), isFalse);
      expect(body.containsKey('max_tokens'), isFalse);
      expect(body.containsKey('reasoning_effort'), isFalse);
      expect(body['max_output_tokens'], 128);
      expect(body['temperature'], 0.4);
      expect(body['top_p'], 0.9);
      expect(body['stream'], isTrue);
      expect(body['reasoning'], {'effort': 'high'});
      expect(body['previous_response_id'], 'resp_prev');
      expect(body['tool_choice'], 'auto');

      final tool = (body['tools'] as List).single as Map;
      expect(tool['type'], 'function');
      expect(tool['name'], 'lookup');
      expect(tool['description'], 'Look up a value.');
      expect(tool.containsKey('function'), isFalse);
      expect((tool['parameters'] as Map)['required'], ['q']);

      final input = (body['input'] as List).cast<Map<String, dynamic>>();
      expect(input.map((item) => item['role'] ?? item['type']).toList(), [
        'user',
        'assistant',
        'function_call',
        'function_call_output',
        'user',
        'assistant',
      ]);
      expect(input.first['content'], [
        {'type': 'input_text', 'text': 'Look'},
        {'type': 'input_image', 'image_url': 'data:image/png;base64,$_png'},
      ]);
      expect(input[1]['content'], [
        {'type': 'output_text', 'text': 'Calling'},
      ]);
      expect(input[2], {
        'type': 'function_call',
        'call_id': 'call_1',
        'name': 'lookup',
        'arguments': '{"q":"x"}',
      });
      expect(input[3], {
        'type': 'function_call_output',
        'call_id': 'call_1',
        'output': 'found',
      });
      final imageTurn = (input[4]['content'] as List).cast<Map>();
      expect(imageTurn.first['text'], '以下是前面工具结果附带的图片，请直接查看。');
      expect(imageTurn[1]['type'], 'input_text');
      expect(imageTurn[2], {
        'type': 'input_image',
        'image_url': 'data:image/png;base64,$_png',
      });
      expect(input.last['content'], [
        {'type': 'output_text', 'text': 'Done'},
      ]);
      for (final item in input) {
        expect(item['role'], isNot('system'));
        expect(item['role'], isNot('developer'));
      }
    });

    test('未持有上一轮响应 id 时不发明 previous_response_id，空采样字段不写出', () {
      final body = OpenAiResponses.buildRequestBody(
        model: 'gpt-5',
        messages: [AgentMessage(id: 'u', role: AgentRole.user, content: 'Hi')],
        tools: const [],
      );

      expect(body.containsKey('previous_response_id'), isFalse);
      expect(body.containsKey('max_output_tokens'), isFalse);
      expect(body.containsKey('max_tokens'), isFalse);
      expect(body.containsKey('top_p'), isFalse);
      expect(body.containsKey('stream'), isFalse);
      expect(body.containsKey('reasoning'), isFalse);
      expect(body.containsKey('tools'), isFalse);
      expect(body.containsKey('tool_choice'), isFalse);
      expect(body.containsKey('messages'), isFalse);
      expect(body['temperature'], isNull);
      expect(body['input'], [
        {
          'role': 'user',
          'content': [
            {'type': 'input_text', 'text': 'Hi'},
          ],
        },
      ]);
    });

    test('tool_choice 从嵌套 function 收成扁平 name', () {
      expect(OpenAiResponses.mapToolChoice('required'), 'required');
      expect(
        OpenAiResponses.mapToolChoice({
          'type': 'function',
          'function': {'name': 'lookup'},
        }),
        {'type': 'function', 'name': 'lookup'},
      );

      final body = OpenAiResponses.buildRequestBody(
        model: 'gpt-5',
        messages: const [],
        tools: const [_LookupTool()],
        toolChoice: {
          'type': 'function',
          'function': {'name': 'lookup'},
        },
      );
      expect(body['tool_choice'], {'type': 'function', 'name': 'lookup'});
    });

    test('developer 提示进入 instructions，图片 URL 写成字符串', () {
      final encoded = OpenAiResponses.encodeChatMessages([
        {'role': 'developer', 'content': 'Be precise.'},
        {'role': 'system', 'content': 'Stay brief.'},
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': 'see'},
            {'type': 'image_url', 'image_url': 'https://example.com/a.png'},
            {
              'type': 'image_url',
              'image_url': {'url': 'data:image/png;base64,$_png'},
            },
          ],
        },
        {
          'role': 'assistant',
          'content': 'ok',
          'tool_calls': [
            {
              'id': 'call_9',
              'type': 'function',
              'function': {'name': 'lookup', 'arguments': '{"q":"x"}'},
            },
          ],
        },
      ]);

      expect(encoded.instructions, 'Be precise.\n\nStay brief.');
      expect(encoded.input[0]['content'], [
        {'type': 'input_text', 'text': 'see'},
        {'type': 'input_image', 'image_url': 'https://example.com/a.png'},
        {'type': 'input_image', 'image_url': 'data:image/png;base64,$_png'},
      ]);
      expect(encoded.input[2], {
        'type': 'function_call',
        'call_id': 'call_9',
        'name': 'lookup',
        'arguments': '{"q":"x"}',
      });
    });

    test('提示词工具模式把协议放进 instructions，不发送原生 tools', () {
      final body = OpenAiResponses.buildRequestBody(
        model: 'gpt-5',
        promptToolUse: true,
        stream: true,
        messages: [
          AgentMessage(id: 's', role: AgentRole.system, content: 'rules'),
          AgentMessage(
            id: 'u',
            role: AgentRole.user,
            content: 'question',
            images: const [
              AgentMessageImage(base64: _png, mimeType: 'image/jpeg'),
            ],
          ),
        ],
        tools: const [_LookupTool()],
      );

      expect(body.containsKey('tools'), isFalse);
      expect(body.containsKey('tool_choice'), isFalse);
      expect(body['instructions'], contains('rules'));
      expect(body['instructions'], contains('Look up a value.'));
      final user = (body['input'] as List).single as Map;
      expect(user['role'], 'user');
      expect(user['content'], [
        {'type': 'input_text', 'text': 'question'},
        {'type': 'input_image', 'image_url': 'data:image/jpeg;base64,$_png'},
      ]);
    });
  });

  group('Responses 非流式解析', () {
    test('收集正文、工具调用、思考摘要和 input/output tokens', () {
      final parsed = OpenAiResponses.parseResponse({
        'id': 'resp_1',
        'output': [
          {
            'type': 'reasoning',
            'summary': [
              {'type': 'summary_text', 'text': 'think'},
              {'type': 'summary_text', 'text': ' more'},
            ],
          },
          {
            'type': 'message',
            'role': 'assistant',
            'content': [
              {'type': 'output_text', 'text': 'Hello'},
              {'type': 'output_text', 'text': ' world'},
            ],
          },
          {
            'type': 'function_call',
            'call_id': 'call_1',
            'name': 'lookup',
            'arguments': '{"q":"x"}',
          },
        ],
        'usage': {
          'input_tokens': 20,
          'output_tokens': 4,
          'input_tokens_details': {'cached_tokens': 5},
        },
      });

      expect(parsed.failed, isFalse);
      expect(parsed.text, 'Hello world');
      expect(parsed.reasoning, 'think more');
      expect(parsed.toolCalls, hasLength(1));
      expect(parsed.toolCalls.single.id, 'call_1');
      expect(parsed.toolCalls.single.name, 'lookup');
      expect(parsed.toolCalls.single.arguments, {'q': 'x'});
      expect(parsed.usage?.input, 15);
      expect(parsed.usage?.output, 4);
      expect(parsed.usage?.cacheRead, 5);
      expect(parsed.usage?.cacheReadReported, isTrue);
    });

    test('没有缓存明细时按 input_tokens 原值计入', () {
      final usage = OpenAiResponses.parseUsage({
        'input_tokens': 12,
        'output_tokens': 3,
      });
      expect(usage?.input, 12);
      expect(usage?.output, 3);
      expect(usage?.cacheReadReported, isFalse);
    });

    test('顶层 error 与 failed 状态返回错误文本', () {
      final missing = OpenAiResponses.parseResponse({
        'error': {
          'message': 'input is required',
          'type': 'invalid_request_error',
        },
      });
      expect(missing.failed, isTrue);
      expect(missing.error, 'input is required');
      expect(missing.transientError, isFalse);
      expect(missing.text, isEmpty);

      final failed = OpenAiResponses.parseResponse({
        'status': 'failed',
        'error': {'code': 'server_error', 'message': 'boom'},
      });
      expect(failed.error, 'boom');
      expect(failed.transientError, isTrue);
    });
  });

  group('Responses 流式解析', () {
    test('文本、思考摘要和完成用量', () {
      final events = _parseSse([
        {
          'type': 'response.reasoning_summary_text.delta',
          'output_index': 0,
          'delta': 'think',
        },
        {
          'type': 'response.output_text.delta',
          'output_index': 1,
          'delta': 'Hi',
        },
        {
          'type': 'response.completed',
          'response': {
            'usage': {'input_tokens': 3, 'output_tokens': 1},
            'output': [
              {
                'type': 'reasoning',
                'summary': [
                  {'type': 'summary_text', 'text': 'think'},
                ],
              },
              {
                'type': 'message',
                'content': [
                  {'type': 'output_text', 'text': 'Hi'},
                ],
              },
            ],
          },
        },
      ]);

      expect(events.whereType<ThoughtDeltaEvent>().map((e) => e.delta), [
        'think',
      ]);
      expect(events.whereType<ContentDeltaEvent>().map((e) => e.delta), ['Hi']);
      final usage = events.whereType<UsageEvent>().single.usage;
      expect(usage.input, 3);
      expect(usage.output, 1);
    });

    test('output_item 与 arguments delta 组装工具调用，完成事件不重复', () {
      final parser = OpenAiResponsesStreamParser();
      expect(
        parser.add({
          'type': 'response.output_item.added',
          'output_index': 1,
          'item': {
            'type': 'function_call',
            'id': 'fc_1',
            'call_id': 'call_1',
            'name': 'lookup',
            'arguments': '',
          },
        }),
        isEmpty,
      );
      parser.add({
        'type': 'response.function_call_arguments.delta',
        'output_index': 1,
        'item_id': 'fc_1',
        'delta': '{"q":',
      });
      final done = parser.add({
        'type': 'response.output_item.done',
        'output_index': 1,
        'item': {
          'type': 'function_call',
          'id': 'fc_1',
          'call_id': 'call_1',
          'name': 'lookup',
          'arguments': '{"q":"x"}',
        },
      });
      final completed = parser.add({
        'type': 'response.completed',
        'response': {
          'output': [
            {
              'type': 'function_call',
              'call_id': 'call_1',
              'name': 'lookup',
              'arguments': '{"q":"x"}',
            },
          ],
          'usage': {'input_tokens': 8, 'output_tokens': 2},
        },
      });
      final tail = parser.finish();

      expect(_toolCalls(done).single.arguments, {'q': 'x'});
      expect(_toolCalls(completed), isEmpty);
      expect(_toolCalls(tail), isEmpty);
      expect(tail.whereType<UsageEvent>().single.usage.input, 8);
      expect(parser.finish().whereType<UsageEvent>(), isEmpty);
    });

    test('done 没带完整参数时拼接 arguments delta', () {
      final events = _parseSse([
        {
          'type': 'response.output_item.added',
          'output_index': 0,
          'item': {
            'type': 'function_call',
            'call_id': 'call_2',
            'name': 'lookup',
            'arguments': '',
          },
        },
        {
          'type': 'response.function_call_arguments.delta',
          'output_index': 0,
          'delta': '{"q":"y"}',
        },
        {
          'type': 'response.output_item.done',
          'output_index': 0,
          'item': {
            'type': 'function_call',
            'call_id': 'call_2',
            'name': 'lookup',
            'arguments': '',
          },
        },
      ]);

      expect(_toolCalls(events).single.arguments, {'q': 'y'});
    });

    test('只有 response.completed 时仍能读出正文、思考和工具', () {
      final events = _parseSse([
        {
          'type': 'response.completed',
          'response': {
            'output': [
              {
                'type': 'reasoning',
                'summary': [
                  {'type': 'summary_text', 'text': 'because'},
                ],
              },
              {
                'type': 'message',
                'content': [
                  {'type': 'output_text', 'text': 'Answer'},
                ],
              },
              {
                'type': 'function_call',
                'call_id': 'call_3',
                'name': 'lookup',
                'arguments': '{"q":"z"}',
              },
            ],
            'usage': {'input_tokens': 1, 'output_tokens': 1},
          },
        },
      ]);

      expect(events.whereType<ThoughtDeltaEvent>().single.delta, 'because');
      expect(events.whereType<ContentDeltaEvent>().single.delta, 'Answer');
      expect(_toolCalls(events).single.arguments, {'q': 'z'});
      expect(events.whereType<UsageEvent>(), hasLength(1));
    });

    test('SSE event 名可补上缺失的 type', () {
      final parser = OpenAiResponsesStreamParser();
      final events = parser.add({
        'delta': 'Hi',
      }, eventType: 'response.output_text.delta');
      expect(events.whereType<ContentDeltaEvent>().single.delta, 'Hi');
    });

    test('response.failed 与 error 事件', () {
      final failed = _parseSse([
        {
          'type': 'response.failed',
          'response': {
            'status': 'failed',
            'error': {'code': 'server_error', 'message': 'boom'},
          },
        },
      ]);
      final error = failed.whereType<ErrorEvent>().single;
      expect(error.error, 'boom');
      expect(error.transient, isTrue);

      final invalid = _parseSse([
        {'type': 'error', 'message': 'input is required'},
      ]);
      final invalidError = invalid.whereType<ErrorEvent>().single;
      expect(invalidError.error, 'input is required');
      expect(invalidError.transient, isFalse);
    });
  });

  group('Responses 提供商接线', () {
    test('流式响应走 Responses 请求体，Chat Completions 仍发送 messages', () async {
      final bodies = <Map<String, dynamic>>[];
      final client = MockClient.streaming((request, body) async {
        bodies.add(
          jsonDecode(utf8.decode(await body.toBytes())) as Map<String, dynamic>,
        );
        final isResponses = request.url.path.endsWith('/responses');
        final payload = isResponses
            ? 'event: response.reasoning_summary_text.delta\n'
                  'data: ${jsonEncode({'type': 'response.reasoning_summary_text.delta', 'delta': 'why'})}\n'
                  '\n'
                  'event: response.output_text.delta\n'
                  'data: ${jsonEncode({'type': 'response.output_text.delta', 'delta': 'Hi'})}\n'
                  '\n'
                  'event: response.completed\n'
                  'data: ${jsonEncode({
                    'type': 'response.completed',
                    'response': {
                      'usage': {'input_tokens': 4, 'output_tokens': 2},
                      'output': [
                        {
                          'type': 'message',
                          'content': [
                            {'type': 'output_text', 'text': 'Hi'},
                          ],
                        },
                      ],
                    },
                  })}\n'
            : 'data: ${jsonEncode({
                    'choices': [
                      {
                        'delta': {'content': 'chat'},
                      },
                    ],
                  })}\n'
                  'data: [DONE]\n';
        return http.StreamedResponse(
          http.ByteStream.fromBytes(utf8.encode(payload)),
          200,
        );
      });

      final responses = OpenAiCompatibleProvider(
        baseUrl: 'https://api.test/v1/responses',
        apiKey: 'test-key',
        model: 'gpt-5',
        reasoning: true,
        thinkingEffort: 'high',
        client: client,
      );
      final responseEvents = await responses
          .streamChat(
            messages: [
              AgentMessage(id: 's', role: AgentRole.system, content: 'rules'),
              AgentMessage(id: 'u', role: AgentRole.user, content: 'Hi'),
            ],
            tools: const [_LookupTool()],
          )
          .toList();

      final chat = OpenAiCompatibleProvider(
        baseUrl: 'https://api.test/v1',
        apiKey: 'test-key',
        model: 'gpt-5',
        reasoning: true,
        thinkingEffort: 'high',
        client: client,
      );
      await chat
          .streamChat(messages: const [], tools: const [_LookupTool()])
          .toList();

      expect(bodies, hasLength(2));
      final responsesBody = bodies.first;
      expect(responsesBody.containsKey('messages'), isFalse);
      expect(responsesBody.containsKey('max_tokens'), isFalse);
      expect(responsesBody['instructions'], 'rules');
      expect(responsesBody['input'], isA<List>());
      expect(responsesBody['stream'], isTrue);
      expect(responsesBody['reasoning'], {'effort': 'high'});
      expect(responsesBody.containsKey('previous_response_id'), isFalse);
      expect((responsesBody['tools'] as List).single['name'], 'lookup');
      expect(
        (responsesBody['tools'] as List).single.containsKey('function'),
        isFalse,
      );
      expect(responseEvents.whereType<ThoughtDeltaEvent>().single.delta, 'why');
      expect(responseEvents.whereType<ContentDeltaEvent>().single.delta, 'Hi');
      expect(responseEvents.whereType<UsageEvent>().single.usage.output, 2);

      final chatBody = bodies.last;
      expect(chatBody.containsKey('messages'), isTrue);
      expect(chatBody.containsKey('input'), isFalse);
      expect(chatBody['reasoning_effort'], 'high');
      expect(chatBody.containsKey('reasoning'), isFalse);
      expect((chatBody['tools'] as List).single['function'], isA<Map>());
    });

    test('非流式 JSON 与错误对象都能解析', () async {
      var call = 0;
      final client = MockClient.streaming((request, body) async {
        call++;
        final payload = call == 1
            ? jsonEncode({
                'output': [
                  {
                    'type': 'message',
                    'content': [
                      {'type': 'output_text', 'text': 'plain'},
                    ],
                  },
                  {
                    'type': 'function_call',
                    'call_id': 'call_1',
                    'name': 'lookup',
                    'arguments': '{"q":"x"}',
                  },
                ],
                'usage': {'input_tokens': 6, 'output_tokens': 2},
              })
            : jsonEncode({
                'error': {
                  'message': 'contents field is required',
                  'type': 'invalid_request_error',
                },
              });
        return http.StreamedResponse(
          http.ByteStream.fromBytes(utf8.encode(payload)),
          200,
        );
      });
      final provider = OpenAiCompatibleProvider(
        baseUrl: 'https://proxy.test/v1/responses',
        apiKey: 'test-key',
        model: 'gpt-5',
        client: client,
      );

      final ok = await provider
          .streamChat(
            messages: [
              AgentMessage(id: 'u', role: AgentRole.user, content: 'go'),
            ],
            tools: const [],
          )
          .toList();
      expect(ok.whereType<ContentDeltaEvent>().single.delta, 'plain');
      expect(ok.whereType<ToolCallEvent>().single.toolCall.name, 'lookup');
      expect(ok.whereType<UsageEvent>().single.usage.input, 6);
      expect(ok.whereType<ErrorEvent>(), isEmpty);

      final bad = await provider
          .streamChat(messages: const [], tools: const [])
          .toList();
      final error = bad.whereType<ErrorEvent>().single;
      expect(error.error, 'contents field is required');
      expect(error.transient, isFalse);
    });
  });
}
