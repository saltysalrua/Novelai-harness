import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:novelai_harness/core/harness/providers/openai_provider.dart';
import 'package:novelai_harness/core/harness/providers/prompt_cache_policy.dart';
import 'package:novelai_harness/core/harness/types.dart';
import 'package:novelai_harness/data/models/llm_models.dart';

http.StreamedResponse _sse(
  List<Map<String, dynamic>> chunks,
) => http.StreamedResponse(
  Stream.value(
    utf8.encode(
      '${chunks.map((c) => 'data: ${jsonEncode(c)}\n\n').join()}data: [DONE]\n\n',
    ),
  ),
  200,
);

void main() {
  group('pi request cache compatibility', () {
    Future<(Map<String, dynamic>, Map<String, String>)> capture({
      String url = 'https://api.openai.com/v1',
      String model = 'gpt-test',
      String? session = 'session-123',
      LlmCacheConfig config = const LlmCacheConfig(),
    }) async {
      late Map<String, dynamic> body;
      late Map<String, String> headers;
      final p = OpenAiCompatibleProvider(
        baseUrl: url,
        apiKey: 'test-key',
        model: model,
        cacheConfig: config,
        client: MockClient.streaming((req, stream) async {
          body =
              jsonDecode(utf8.decode(await stream.toBytes()))
                  as Map<String, dynamic>;
          headers = req.headers;
          return _sse([]);
        }),
      );
      await p
          .streamChat(messages: [], tools: [], promptCacheKey: session)
          .toList();
      return (body, headers);
    }

    test(
      'direct OpenAI sends session key and usage but no long retention by default',
      () async {
        final (body, headers) = await capture();
        expect(body['prompt_cache_key'], 'session-123');
        expect(body['stream_options'], {'include_usage': true});
        expect(body, isNot(contains('prompt_cache_retention')));
        expect(headers, isNot(contains('session_id')));
      },
    );

    test(
      'unknown newapi and Gemini routes do not receive guessed cache parameters',
      () async {
        for (final url in [
          'https://proxy.example/v1',
          'https://api.openai.com.evil.test/v1',
          'https://example.test/api.openai.com',
        ]) {
          final (body, _) = await capture(url: url, model: 'gemini-test');
          expect(body, isNot(contains('prompt_cache_key')));
          expect(body, isNot(contains('prompt_cache_retention')));
        }
      },
    );

    test(
      'explicit compatible proxy supports long retention and affinity',
      () async {
        final (body, headers) = await capture(
          url: 'https://proxy.example/v1',
          config: const LlmCacheConfig(
            mode: LlmCacheMode.openai,
            retention: LlmCacheRetention.long,
            affinity: LlmCacheAffinity.openai,
          ),
        );
        expect(body['prompt_cache_key'], 'session-123');
        expect(body['prompt_cache_retention'], '24h');
        for (final key in [
          'session_id',
          'x-client-request-id',
          'x-session-affinity',
        ]) {
          expect(headers[key], 'session-123');
        }
      },
    );

    test('OpenRouter affinity is opt-in and uses only x-session-id', () async {
      final (body, headers) = await capture(
        url: 'https://openrouter.ai/api/v1',
        config: const LlmCacheConfig(affinity: LlmCacheAffinity.openrouter),
      );
      expect(body, isNot(contains('prompt_cache_key')));
      expect(headers['x-session-id'], 'session-123');
      expect(headers, isNot(contains('session_id')));
    });

    test(
      'off and missing session omit affinity; off omits cache hints',
      () async {
        final (body, headers) = await capture(
          config: const LlmCacheConfig(
            mode: LlmCacheMode.off,
            retention: LlmCacheRetention.long,
            affinity: LlmCacheAffinity.openai,
          ),
        );
        expect(body, isNot(contains('prompt_cache_key')));
        expect(body, isNot(contains('prompt_cache_retention')));
        expect(headers, isNot(contains('session_id')));
        final (without, noHeaders) = await capture(
          session: null,
          config: const LlmCacheConfig(affinity: LlmCacheAffinity.openai),
        );
        expect(without, isNot(contains('prompt_cache_key')));
        expect(noHeaders, isNot(contains('session_id')));
      },
    );

    test('Unicode key is clamped to 64 codepoints, not code units', () async {
      final (body, _) = await capture(session: List.filled(70, '😀').join());
      expect((body['prompt_cache_key'] as String).runes.length, 64);
    });

    test(
      'same session keeps serialized prefix and affinity stable across turns',
      () async {
        final (a, ah) = await capture(
          config: const LlmCacheConfig(affinity: LlmCacheAffinity.openai),
        );
        final (b, bh) = await capture(
          config: const LlmCacheConfig(affinity: LlmCacheAffinity.openai),
        );
        expect(jsonEncode(a), jsonEncode(b));
        expect(ah, bh);
      },
    );
  });

  group('Anthropic cache breakpoints match pi', () {
    Map<String, dynamic> body() => {
      'messages': [
        {'role': 'system', 'content': 'system instructions'},
        {'role': 'user', 'content': 'read file'},
        {
          'role': 'assistant',
          'content': '',
          'tool_calls': [
            {'id': 'call1'},
          ],
        },
        {
          'role': 'tool',
          'content': [
            {'type': 'text', 'text': 'result'},
            {
              'type': 'image_url',
              'image_url': {'url': 'data:image/png;base64,AA=='},
            },
          ],
          'tool_call_id': 'call1',
        },
      ],
      'tools': [
        {
          'type': 'function',
          'function': {'name': 'a'},
        },
        {
          'type': 'function',
          'function': {'name': 'b'},
        },
      ],
    };
    test(
      'auto OpenRouter Anthropic marks system, last tool and last conversation text',
      () {
        final payload = body();
        PromptCachePolicy(
          config: const LlmCacheConfig(),
          endpoint: Uri.parse('https://openrouter.ai/api/v1/chat/completions'),
          model: 'anthropic/claude-test',
        ).apply(payload, 's');
        final messages = payload['messages'] as List<dynamic>;
        expect(messages[0]['content'][0]['cache_control'], {
          'type': 'ephemeral',
        });
        expect(messages[1]['content'], 'read file');
        expect(messages.last['content'][0]['cache_control'], {
          'type': 'ephemeral',
        });
        expect(
          messages.last['content'][1].containsKey('cache_control'),
          isFalse,
        );
        final tools = payload['tools'] as List<dynamic>;
        expect(tools[0].containsKey('cache_control'), isFalse);
        expect(tools[1]['cache_control'], {'type': 'ephemeral'});
      },
    );
    test(
      'explicit Anthropic proxy long cache uses 1h; off preserves message shapes',
      () {
        final payload = body();
        PromptCachePolicy(
          config: const LlmCacheConfig(
            mode: LlmCacheMode.anthropic,
            retention: LlmCacheRetention.long,
          ),
          endpoint: Uri.parse('https://proxy.test/v1'),
          model: 'claude-test',
        ).apply(payload, null);
        expect((payload['tools'] as List).last['cache_control'], {
          'type': 'ephemeral',
          'ttl': '1h',
        });
        final disabled = body();
        final original = jsonEncode(disabled);
        PromptCachePolicy(
          config: const LlmCacheConfig(mode: LlmCacheMode.off),
          endpoint: Uri.parse('https://openrouter.ai/api/v1'),
          model: 'anthropic/claude-test',
        ).apply(disabled, 's');
        expect(jsonEncode(disabled), original);
      },
    );

    test(
      'native Anthropic /v1/messages marks top-level system and tool_result',
      () {
        final payload = <String, dynamic>{
          'system': 'system instructions',
          'messages': [
            {
              'role': 'user',
              'content': [
                {'type': 'text', 'text': 'read file'},
              ],
            },
            {
              'role': 'assistant',
              'content': [
                {
                  'type': 'tool_use',
                  'id': 'toolu_1',
                  'name': 'b',
                  'input': const <String, dynamic>{},
                },
              ],
            },
            {
              'role': 'user',
              'content': [
                {
                  'type': 'tool_result',
                  'tool_use_id': 'toolu_1',
                  'content': 'result',
                },
              ],
            },
          ],
          'tools': [
            {'name': 'a', 'input_schema': const <String, dynamic>{}},
            {'name': 'b', 'input_schema': const <String, dynamic>{}},
          ],
        };
        PromptCachePolicy(
          config: const LlmCacheConfig(),
          endpoint: Uri.parse('https://api.anthropic.com/v1/messages'),
          model: 'claude-sonnet-4-5',
        ).apply(payload, 's');
        expect(payload['system'], [
          {
            'type': 'text',
            'text': 'system instructions',
            'cache_control': {'type': 'ephemeral'},
          },
        ]);
        final tools = payload['tools'] as List<dynamic>;
        expect(tools[0].containsKey('cache_control'), isFalse);
        expect(tools[1]['cache_control'], {'type': 'ephemeral'});
        final messages = payload['messages'] as List<dynamic>;
        expect(messages.last['content'][0]['cache_control'], {
          'type': 'ephemeral',
        });
      },
    );
  });

  group('usage streaming and safe fallback', () {
    test(
      'choice.usage fallback works and top-level usage has priority',
      () async {
        final p = OpenAiCompatibleProvider(
          baseUrl: 'https://test.example/v1',
          apiKey: 'test-key',
          model: 'm',
          client: MockClient.streaming(
            (r, b) async => _sse([
              {
                'choices': [
                  {
                    'delta': {},
                    'usage': {'prompt_tokens': 100, 'cached_tokens': 80},
                  },
                ],
              },
              {
                'usage': {'prompt_tokens': 100, 'cached_tokens': 0},
                'choices': [
                  {
                    'delta': {},
                    'usage': {'prompt_tokens': 100, 'cached_tokens': 80},
                  },
                ],
              },
              {
                'usage': {'prompt_tokens': 200, 'cached_tokens': 100},
                'choices': [],
              },
            ]),
          ),
        );
        final events = (await p.streamChat(messages: [], tools: []).toList())
            .whereType<UsageEvent>()
            .toList();
        // 整条流只发一次 usage (逐 chunk last-wins，对齐 pi)：
        // 末尾快照同时验 top-level 优先于 choice.usage —— 若优先级颠倒
        // (choice 100/80 胜出) 会得到 cacheRead=80 / input=20
        expect(events, hasLength(1));
        expect(events.single.usage.input, 100);
        expect(events.single.usage.cacheRead, 100);
        expect(events.single.usage.output, 0);
      },
    );

    test('rejections are scoped by endpoint, model and field', () async {
      final requests = <Map<String, dynamic>>[];
      var reject = true;
      final client = MockClient.streaming((r, s) async {
        final body =
            jsonDecode(utf8.decode(await s.toBytes())) as Map<String, dynamic>;
        requests.add(body);
        if (reject && body.containsKey('prompt_cache_key')) {
          return http.StreamedResponse(
            Stream.value(
              utf8.encode('Unsupported parameter: prompt_cache_key'),
            ),
            400,
          );
        }
        return _sse([]);
      });
      Future<void> send(String host, String model) async {
        final p = OpenAiCompatibleProvider(
          baseUrl: 'https://$host/v1',
          apiKey: 'test-key',
          model: model,
          client: client,
          cacheConfig: const LlmCacheConfig(
            mode: LlmCacheMode.openai,
            retention: LlmCacheRetention.long,
          ),
        );
        await p
            .streamChat(messages: [], tools: [], promptCacheKey: 's')
            .toList();
      }

      await send('reject-cache.test', 'a');
      expect(requests.length, 2);
      expect(requests.last, isNot(contains('prompt_cache_key')));
      expect(requests.last['prompt_cache_retention'], '24h');
      reject = false;
      await send('reject-cache.test', 'a');
      expect(requests.last, isNot(contains('prompt_cache_key')));
      await send('other-cache.test', 'a');
      expect(requests.last['prompt_cache_key'], 's');
      await send('reject-cache.test', 'b');
      expect(requests.last['prompt_cache_key'], 's');
    });

    test(
      'invalid cache values are not treated as unsupported capabilities',
      () async {
        var calls = 0;
        final p = OpenAiCompatibleProvider(
          baseUrl: 'https://bad-value.test/v1',
          apiKey: 'test-key',
          model: 'm',
          cacheConfig: const LlmCacheConfig(mode: LlmCacheMode.openai),
          client: MockClient.streaming((r, s) async {
            calls++;
            return http.StreamedResponse(
              Stream.value(utf8.encode('prompt_cache_key has invalid length')),
              400,
            );
          }),
        );
        final events = await p
            .streamChat(messages: [], tools: [], promptCacheKey: 's')
            .toList();
        expect(calls, 1);
        expect(
          events.whereType<ErrorEvent>().single.error,
          contains('invalid length'),
        );
      },
    );
  });

  test('model cache config roundtrips and copyWith preserves user choices', () {
    const m = LlmModelConfig(
      id: 'm',
      name: 'm',
      cacheConfig: LlmCacheConfig(
        mode: LlmCacheMode.anthropic,
        retention: LlmCacheRetention.long,
        affinity: LlmCacheAffinity.openrouter,
      ),
    );
    final restored = LlmModelConfig.fromJson(
      m.toJson(),
    ).copyWith(name: 'edited');
    expect(restored.cacheConfig.toJson(), m.cacheConfig.toJson());
    expect(
      LlmModelConfig.fromJson({'id': 'old'}).cacheConfig.toJson(),
      const LlmCacheConfig().toJson(),
    );
    expect(LlmCacheConfig.fromJson({'mode': 'future'}).mode, LlmCacheMode.auto);
  });
}
