import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:novelai_harness/core/harness/providers/openai_provider.dart';
import 'package:novelai_harness/core/harness/tools/agent_tool.dart';
import 'package:novelai_harness/core/harness/types.dart';
import 'package:novelai_harness/data/models/llm_models.dart';
import 'package:novelai_harness/data/services/config_service.dart';
import 'package:novelai_harness/ui/features/settings/widgets/models_settings_tab.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
        },
      );

  @override
  Future<ToolResult> execute(
    String toolCallId,
    Map<String, dynamic> args,
  ) async => ToolResult(toolCallId: toolCallId, content: 'ok');
}

http.StreamedResponse _json(Object body, {int status = 200}) {
  return http.StreamedResponse(
    http.ByteStream.fromBytes(utf8.encode(jsonEncode(body))),
    status,
    headers: {'content-type': 'application/json'},
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('流式开关配置', () {
    test('默认开启，旧配置补成开启，关闭状态可往返', () {
      const fresh = LlmProviderConfig(
        id: 'relay',
        name: 'Relay',
        models: [LlmModelConfig(id: 'm', name: 'M')],
      );
      expect(fresh.streaming, isTrue);

      final legacy = Map<String, dynamic>.from(fresh.toJson())
        ..remove('streaming');
      expect(LlmProviderConfig.fromJson(legacy).streaming, isTrue);

      final off = fresh.copyWith(streaming: false);
      final restored = LlmProviderConfig.fromJson(off.toJson());
      expect(restored.streaming, isFalse);
      expect(restored.copyWith(name: 'new').streaming, isFalse);
    });

    test('设置草稿按供应商保存，并写入配置', () async {
      SharedPreferences.setMockInitialValues({});
      final on = const LlmProviderConfig(
        id: 'on',
        name: 'On',
        models: [LlmModelConfig(id: 'm', name: 'M')],
      );
      final off = on.copyWith(id: 'off', name: 'Off', streaming: false);
      final draft = ModelsSettingsDraft(
        AppConfig(llmProviders: [on, off], activeLlmProviderId: 'on'),
      );
      expect(draft.streaming, isTrue);
      draft.switchProvider('off');
      expect(draft.streaming, isFalse);
      draft.streaming = true;
      draft.syncFromForm();
      draft.switchProvider('on');
      draft.streaming = false;
      draft.syncFromForm();

      final service = ConfigService();
      await service.saveConfig(
        AppConfig(llmProviders: draft.providers, activeLlmProviderId: 'off'),
      );
      final restored = await service.loadConfig();
      expect(
        restored.llmProviders.firstWhere((p) => p.id == 'on').streaming,
        isFalse,
      );
      expect(
        restored.llmProviders.firstWhere((p) => p.id == 'off').streaming,
        isTrue,
      );
      draft.dispose();
    });
  });

  group('关闭流式后的请求与解析', () {
    test('Chat Completions 发送 stream:false 并解析正文、思考、签名和工具', () async {
      late Map<String, dynamic> body;
      final provider = OpenAiCompatibleProvider(
        baseUrl: 'https://api.test/v1/chat/completions',
        apiKey: 'test-key',
        model: 'gpt-test',
        streaming: false,
        client: MockClient.streaming((request, bodyStream) async {
          body =
              jsonDecode(await bodyStream.bytesToString())
                  as Map<String, dynamic>;
          return _json({
            'choices': [
              {
                'finish_reason': 'tool_calls',
                'message': {
                  'content': '<think>标签思考</think>可见回答',
                  'reasoning_content': '字段思考',
                  'tool_calls': [
                    {
                      'id': 'call_1',
                      'type': 'function',
                      'function': {
                        'name': 'lookup',
                        'arguments': '{"q":"cat"}',
                      },
                      'extra_content': {
                        'google': {'thought_signature': 'sig_chat'},
                      },
                    },
                  ],
                },
              },
            ],
            'usage': {'prompt_tokens': 11, 'completion_tokens': 4},
          });
        }),
      );

      final events = await provider
          .streamChat(
            messages: [
              AgentMessage(id: 'u', role: AgentRole.user, content: 'hi'),
            ],
            tools: const [_LookupTool()],
          )
          .toList();

      expect(body['stream'], isFalse);
      expect(body.containsKey('stream_options'), isFalse);
      expect(
        events.whereType<ThoughtDeltaEvent>().map((e) => e.delta).join(),
        '字段思考标签思考',
      );
      expect(
        events.whereType<ContentDeltaEvent>().map((e) => e.delta).join(),
        '可见回答',
      );
      expect(
        events.whereType<ThoughtSignatureEvent>().single.signature,
        'sig_chat',
      );
      final call = events.whereType<ToolCallEvent>().single.toolCall;
      expect(call.id, 'call_1');
      expect(call.arguments, {'q': 'cat'});
      expect(call.thoughtSignature, 'sig_chat');
      expect(events.whereType<UsageEvent>().single.usage.input, 11);
      expect(events.whereType<ErrorEvent>(), isEmpty);
    });

    test('Chat Completions 解析拒绝、残缺参数和错误对象', () async {
      Future<List<HarnessEvent>> send(Object response) {
        final provider = OpenAiCompatibleProvider(
          baseUrl: 'https://api.test/v1/chat/completions',
          apiKey: 'test-key',
          model: 'gpt-test',
          streaming: false,
          client: MockClient.streaming(
            (request, bodyStream) async => _json(response),
          ),
        );
        return provider
            .streamChat(messages: const [], tools: const [_LookupTool()])
            .toList();
      }

      final refusal = await send({
        'choices': [
          {
            'message': {'content': null, 'refusal': '不能回答'},
            'finish_reason': 'stop',
          },
        ],
      });
      expect(refusal.whereType<ErrorEvent>().single.error, contains('不能回答'));

      final broken = await send({
        'choices': [
          {
            'message': {
              'content': '一半',
              'tool_calls': [
                {
                  'id': 'call_bad',
                  'function': {'name': 'lookup', 'arguments': '{"q":'},
                },
              ],
            },
          },
        ],
      });
      expect(
        broken.whereType<ContentDeltaEvent>().map((e) => e.delta).join(),
        '一半',
      );
      expect(broken.whereType<ToolCallEvent>(), isEmpty);
      expect(
        broken.whereType<ErrorEvent>().single.error,
        contains('不是合法 JSON'),
      );

      final failed = await send({
        'error': {
          'message': 'overloaded',
          'type': 'overloaded_error',
          'code': 503,
        },
      });
      final error = failed.whereType<ErrorEvent>().single;
      expect(error.error, 'overloaded');
      expect(error.transient, isTrue);
    });

    test('Responses 发送 stream:false 并回放加密推理', () async {
      late Map<String, dynamic> body;
      final provider = OpenAiCompatibleProvider(
        baseUrl: 'https://api.test/v1/responses',
        apiKey: 'test-key',
        model: 'gpt-5',
        reasoning: true,
        thinkingEffort: 'low',
        streaming: false,
        client: MockClient.streaming((request, bodyStream) async {
          body =
              jsonDecode(await bodyStream.bytesToString())
                  as Map<String, dynamic>;
          return _json({
            'output': [
              {
                'type': 'reasoning',
                'id': 'rs_off',
                'encrypted_content': 'enc_off',
                'summary': [
                  {'type': 'summary_text', 'text': '先想'},
                ],
              },
              {
                'type': 'function_call',
                'call_id': 'call_9',
                'name': 'lookup',
                'arguments': '{"q":"x"}',
              },
            ],
            'usage': {'input_tokens': 6, 'output_tokens': 2},
          });
        }),
      );
      final events = await provider
          .streamChat(
            messages: [
              AgentMessage(id: 'u', role: AgentRole.user, content: 'go'),
            ],
            tools: const [_LookupTool()],
          )
          .toList();

      expect(body['stream'], isFalse);
      expect(body['store'], isFalse);
      expect(body['include'], ['reasoning.encrypted_content']);
      final record = events
          .whereType<ReasoningSnapshotEvent>()
          .single
          .records
          .single;
      expect(record.id, 'rs_off');
      expect(record.encryptedContent, 'enc_off');
      expect(events.whereType<ThoughtDeltaEvent>().single.delta, '先想');
      expect(events.whereType<ToolCallEvent>().single.toolCall.id, 'call_9');
      expect(events.whereType<UsageEvent>().single.usage.output, 2);
    });

    test('Responses 非流式拒绝和不完整响应变成错误', () async {
      Future<String> errorOf(Object response) async {
        final provider = OpenAiCompatibleProvider(
          baseUrl: 'https://api.test/v1/responses',
          apiKey: 'test-key',
          model: 'gpt-5',
          streaming: false,
          client: MockClient.streaming(
            (request, bodyStream) async => _json(response),
          ),
        );
        final events = await provider
            .streamChat(messages: const [], tools: const [])
            .toList();
        return events.whereType<ErrorEvent>().single.error;
      }

      expect(
        await errorOf({
          'output': [
            {
              'type': 'message',
              'content': [
                {'type': 'refusal', 'refusal': '不行'},
              ],
            },
          ],
        }),
        contains('不行'),
      );
      expect(
        await errorOf({
          'status': 'incomplete',
          'incomplete_details': {'reason': 'max_output_tokens'},
        }),
        contains('max_output_tokens'),
      );
    });

    test('Anthropic 发送 stream:false 并保留 thinking 签名', () async {
      late Map<String, dynamic> body;
      final provider = OpenAiCompatibleProvider(
        baseUrl: 'https://api.anthropic.com/v1/messages',
        apiKey: 'test-key',
        model: 'claude-sonnet-5',
        reasoning: true,
        thinkingEffort: 'low',
        streaming: false,
        client: MockClient.streaming((request, bodyStream) async {
          body =
              jsonDecode(await bodyStream.bytesToString())
                  as Map<String, dynamic>;
          return _json({
            'stop_reason': 'tool_use',
            'content': [
              {'type': 'thinking', 'thinking': '先推理', 'signature': 'sig_live'},
              {'type': 'redacted_thinking', 'data': 'redacted_live'},
              {'type': 'text', 'text': '好'},
              {
                'type': 'tool_use',
                'id': 'toolu_1',
                'name': 'lookup',
                'input': {'q': 'x'},
              },
            ],
            'usage': {'input_tokens': 8, 'output_tokens': 3},
          });
        }),
      );
      final events = await provider
          .streamChat(
            messages: [
              AgentMessage(id: 'u', role: AgentRole.user, content: 'go'),
            ],
            tools: const [_LookupTool()],
          )
          .toList();

      expect(body['stream'], isFalse);
      expect(body.containsKey('temperature'), isFalse);
      final records = events.whereType<ReasoningSnapshotEvent>().single.records;
      expect(records[0].signature, 'sig_live');
      expect(records[0].plaintext, '先推理');
      expect(records[1].redactedData, 'redacted_live');
      expect(
        events.whereType<ThoughtSignatureEvent>().single.signature,
        'sig_live',
      );
      expect(
        events.whereType<ContentDeltaEvent>().map((e) => e.delta).join(),
        '好',
      );
      expect(events.whereType<ToolCallEvent>().single.toolCall.arguments, {
        'q': 'x',
      });
      expect(events.whereType<UsageEvent>().single.usage.input, 8);
    });

    test('Anthropic 非流式拒绝和残缺工具参数变成错误', () async {
      Future<List<HarnessEvent>> send(Object response) {
        final provider = OpenAiCompatibleProvider(
          baseUrl: 'https://api.anthropic.com/v1/messages',
          apiKey: 'test-key',
          model: 'claude-sonnet-5',
          streaming: false,
          client: MockClient.streaming(
            (request, bodyStream) async => _json(response),
          ),
        );
        return provider
            .streamChat(messages: const [], tools: const [])
            .toList();
      }

      final refusal = await send({
        'stop_reason': 'refusal',
        'content': [
          {'type': 'thinking', 'thinking': '不想', 'signature': 'sig'},
        ],
      });
      expect(refusal.whereType<ErrorEvent>().single.error, contains('拒绝'));
      expect(refusal.whereType<ToolCallEvent>(), isEmpty);

      final broken = await send({
        'stop_reason': 'max_tokens',
        'content': [
          {
            'type': 'tool_use',
            'id': 'toolu_bad',
            'name': 'lookup',
            'input': '{"q":',
          },
        ],
      });
      expect(broken.whereType<ToolCallEvent>(), isEmpty);
      expect(
        broken.whereType<ErrorEvent>().single.error,
        contains('不是合法 JSON'),
      );
    });

    test('Google Interactions 关闭流式后解析 thought 与函数签名', () async {
      late Map<String, dynamic> body;
      late Map<String, String> headers;
      final provider = OpenAiCompatibleProvider(
        baseUrl:
            'https://generativelanguage.googleapis.com/v1beta/interactions',
        apiKey: 'goog-key',
        model: 'gemini-4-argon',
        reasoning: true,
        streaming: false,
        client: MockClient.streaming((request, bodyStream) async {
          headers = request.headers;
          body =
              jsonDecode(await bodyStream.bytesToString())
                  as Map<String, dynamic>;
          return _json({
            'status': 'completed',
            'output': [
              {
                'type': 'thought',
                'signature': 'thought_sig',
                'summary': [
                  {'type': 'text', 'text': '想一下'},
                ],
              },
              {
                'type': 'function_call',
                'id': 'fc_1',
                'name': 'lookup',
                'arguments': {'q': 'x'},
                'thought_signature': 'fc_sig',
              },
              {
                'type': 'model_output',
                'content': [
                  {'type': 'text', 'text': '好'},
                ],
              },
            ],
            'usage': {
              'total_input_tokens': 10,
              'total_output_tokens': 4,
              'total_thought_tokens': 2,
            },
          });
        }),
      );
      final events = await provider
          .streamChat(
            messages: [
              AgentMessage(id: 'u', role: AgentRole.user, content: 'go'),
            ],
            tools: const [_LookupTool()],
          )
          .toList();

      expect(body['stream'], isFalse);
      expect(headers['accept'], 'application/json');
      expect(
        events.whereType<ThoughtDeltaEvent>().map((e) => e.delta).join(),
        '想一下',
      );
      expect(
        events.whereType<ThoughtSignatureEvent>().map((e) => e.signature),
        contains('thought_sig'),
      );
      final call = events.whereType<ToolCallEvent>().single.toolCall;
      expect(call.thoughtSignature, 'fc_sig');
      expect(call.arguments, {'q': 'x'});
      expect(
        events.whereType<ContentDeltaEvent>().map((e) => e.delta).join(),
        '好',
      );
      final usage = events.whereType<UsageEvent>().single.usage;
      expect(usage.input, 10);
      expect(usage.output, 6);
    });

    test('Google Interactions 非流式不完整响应变成错误并保留用量', () async {
      final provider = OpenAiCompatibleProvider(
        baseUrl:
            'https://generativelanguage.googleapis.com/v1beta/interactions',
        apiKey: 'goog-key',
        model: 'gemini-4-argon',
        streaming: false,
        client: MockClient.streaming(
          (request, bodyStream) async => _json({
            'status': 'incomplete',
            'incomplete_reason': 'max_tokens',
            'usage': {'total_input_tokens': 3, 'total_output_tokens': 1},
          }),
        ),
      );
      final events = await provider
          .streamChat(messages: const [], tools: const [])
          .toList();
      expect(
        events.whereType<ErrorEvent>().single.error,
        contains('max_tokens'),
      );
      expect(events.whereType<ToolCallEvent>(), isEmpty);
      expect(events.whereType<UsageEvent>().single.usage.input, 3);
    });
  });
}
