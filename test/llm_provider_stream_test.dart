import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:novelai_harness/core/harness/providers/openai_provider.dart';
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

  group('思考参数请求格式 (对齐 pi thinkingFormat 兼容矩阵)', () {
    Map<String, dynamic>? capturedBody;

    OpenAiCompatibleProvider fmtProvider(
      String baseUrl, {
      bool reasoning = true,
      String? effort = 'high',
      String? format,
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
        model: 'test-model',
        reasoning: reasoning,
        thinkingEffort: effort,
        thinkingParamFormat: format,
        client: client,
      );
    }

    Future<Map<String, dynamic>> requestBody(OpenAiCompatibleProvider p) async {
      await p.streamChat(messages: [], tools: []).toList();
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
}
