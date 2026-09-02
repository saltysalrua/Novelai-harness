import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:novelai_harness/data/models/novelai_models.dart';
import 'package:novelai_harness/data/services/llm_model_fetcher.dart';
import 'package:novelai_harness/data/services/models_dev_catalog.dart';

/// models.dev 目录样例数据 (节选自真实 api.json 结构)
final Map<String, dynamic> sampleCatalog = {
  'openai': {
    'models': {
      'gpt-4o': {
        'name': 'GPT-4o',
        'reasoning': false,
        'limit': {'context': 128000, 'output': 16384},
        'modalities': {
          'input': ['text', 'image'],
          'output': ['text'],
        },
      },
      'o3': {
        'name': 'o3',
        'reasoning': true,
        'reasoning_options': [
          {
            'type': 'effort',
            'values': ['low', 'medium', 'high'],
          },
        ],
        'limit': {'context': 200000, 'output': 100000},
      },
    },
  },
  'openrouter': {
    'models': {
      'deepseek/deepseek-v3.1-terminus': {
        'name': 'DeepSeek V3.1 Terminus',
        'reasoning': true,
        'reasoning_options': [
          {'type': 'toggle'},
        ],
        'limit': {'context': 163840, 'output': 32768},
        'modalities': {
          'input': ['text'],
          'output': ['text'],
        },
      },
    },
  },
  'openai-image': {
    'models': {
      'gpt-image-1': {
        'name': 'GPT Image 1',
        'modalities': {
          'input': ['text'],
          'output': ['image'],
        },
      },
      'text-embedding-3-large': {
        'name': 'Text Embedding 3 Large',
        'modalities': {
          'input': ['text'],
          'output': ['embedding'],
        },
      },
      'gpt-4o-image-edit': {
        'name': 'GPT-4o Image Edit',
        'modalities': {
          'input': ['text', 'image'],
          'output': ['text', 'image'],
        },
      },
    },
  },
};

ModelsDevCatalog buildCatalog() => ModelsDevCatalog(
  client: MockClient(
    (request) async => http.Response(jsonEncode(sampleCatalog), 200),
  ),
);

void main() {
  group('ModelsDevCatalog.buildIndex', () {
    test('解析模型能力与思考等级', () {
      final index = ModelsDevCatalog.buildIndex(sampleCatalog);

      final gpt4o = index['gpt-4o']!.first;
      expect(gpt4o.providerId, 'openai');
      expect(gpt4o.name, 'GPT-4o');
      expect(gpt4o.reasoning, isFalse);
      expect(gpt4o.input, ['text', 'image']);
      expect(gpt4o.contextWindow, 128000);
      expect(gpt4o.maxTokens, 16384);

      final o3 = index['o3']!.first;
      expect(o3.reasoning, isTrue);
      expect(o3.thinkingLevels, [
        ThinkingEffort.low,
        ThinkingEffort.medium,
        ThinkingEffort.high,
      ]);
      expect(o3.contextWindow, 200000);

      // 供应商前缀形式也可裸名命中
      expect(index['deepseek-v3.1-terminus'], isNotNull);

      // 纯图像输出模型也索引，并携带 imageOutput 能力 (绘图模型识别)
      final gptImage = index['gpt-image-1']!.first;
      expect(gptImage.imageOutput, isTrue);
      expect(gptImage.input, ['text']);

      // 文本+图像双输出模型带 imageOutput 能力
      final imageEdit = index['gpt-4o-image-edit']!.first;
      expect(imageEdit.imageOutput, isTrue);
      expect(imageEdit.input, ['text', 'image']);

      // gpt-4o 纯文本输出不带图像输出能力
      expect(gpt4o.imageOutput, isFalse);

      // embedding 等专用模型仍然不索引
      expect(index['text-embedding-3-large'], isNull);
    });

    test('candidateKeys 逐级放宽', () {
      expect(
        ModelsDevCatalog.candidateKeys('deepseek-r1:14b'),
        contains('deepseek-r1'),
      );
      expect(
        ModelsDevCatalog.candidateKeys('gpt-4o-2024-08-06'),
        contains('gpt-4o'),
      );
      expect(
        ModelsDevCatalog.candidateKeys('openai/gpt-4o'),
        contains('gpt-4o'),
      );
      expect(
        ModelsDevCatalog.candidateKeys('DeepSeek/deepseek-v3.1-Terminus'),
        contains('deepseek-v3.1-terminus'),
      );
    });
  });

  group('ModelsDevCatalog.lookup', () {
    test('精确与模糊匹配', () async {
      final catalog = buildCatalog();
      final gpt4o = await catalog.lookup('gpt-4o');
      expect(gpt4o?.name, 'GPT-4o');

      final dated = await catalog.lookup('gpt-4o-2024-08-06');
      expect(dated?.name, 'GPT-4o');

      final prefixed = await catalog.lookup('deepseek/deepseek-v3.1-terminus');
      expect(prefixed?.name, 'DeepSeek V3.1 Terminus');
      expect(prefixed?.reasoning, isTrue);
      expect(prefixed?.contextWindow, 163840);

      expect(await catalog.lookup('totally-unknown-model'), isNull);
    });

    test('目录加载失败时静默返回 null', () async {
      final catalog = ModelsDevCatalog(
        client: MockClient(
          (request) async => http.Response('server error', 500),
        ),
      );
      expect(await catalog.lookup('gpt-4o'), isNull);
    });
  });

  group('LlmModelFetcher.fetchRemoteModels', () {
    test('OpenRouter 原生元数据优先，models.dev 补齐，启发式兜底', () async {
      final fetcher = LlmModelFetcher(
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'data': [
                {
                  'id': 'openai/gpt-4o',
                  'name': 'GPT-4o (openrouter)',
                  'architecture': {
                    'input_modalities': ['text', 'image'],
                  },
                  'context_length': 128000,
                  'top_provider': {'max_completion_tokens': 16384},
                },
                {
                  'id': 'deepseek/deepseek-v3.1-terminus',
                  'name': 'DeepSeek V3.1 Terminus (openrouter)',
                },
                {'id': 'mystery-model'},
              ],
            }),
            200,
          ),
        ),
        modelsDevCatalog: buildCatalog(),
      );

      final result = await fetcher.fetchRemoteModels(
        baseUrl: 'https://openrouter.ai/api/v1',
        protocol: LlmProtocol.openAiChat,
        apiKey: '',
      );

      expect(result.models.length, 3);
      expect(result.enrichedCount, 2);

      final gpt4o = result.models.firstWhere((m) => m.id == 'openai/gpt-4o');
      expect(gpt4o.isMultimodal, isTrue);
      expect(gpt4o.contextWindow, 128000);
      expect(gpt4o.maxTokens, 16384);
      expect(gpt4o.name, 'GPT-4o (openrouter)');

      final deepseek = result.models.firstWhere(
        (m) => m.id == 'deepseek/deepseek-v3.1-terminus',
      );
      expect(deepseek.reasoning, isTrue);
      expect(deepseek.contextWindow, 163840);
      expect(deepseek.maxTokens, 32768);
      expect(deepseek.temperature, 0.6);

      // 未知模型回退启发式默认值
      final mystery = result.models.firstWhere((m) => m.id == 'mystery-model');
      expect(mystery.reasoning, isFalse);
      expect(mystery.contextWindow, 128000);
      expect(mystery.temperature, 0.7);
    });

    test('合并既有配置：保留用户名称温度，追加本地自定义模型', () async {
      final fetcher = LlmModelFetcher(
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'data': [
                {'id': 'openai/gpt-4o'},
              ],
            }),
            200,
          ),
        ),
        modelsDevCatalog: buildCatalog(),
      );

      final existing = [
        LlmModelConfig(
          id: 'openai/gpt-4o',
          name: '我的定制 GPT',
          temperature: 0.3,
          contextWindow: 1000,
        ),
        const LlmModelConfig(
          id: 'my-custom-model',
          name: '本地自定义',
          temperature: 0.5,
        ),
      ];

      final result = await fetcher.fetchRemoteModels(
        baseUrl: 'https://openrouter.ai/api/v1',
        protocol: LlmProtocol.openAiChat,
        apiKey: '',
        existingModels: existing,
      );

      expect(result.models.length, 2);
      final gpt4o = result.models.firstWhere((m) => m.id == 'openai/gpt-4o');
      // 用户设置保留，能力被远端刷新
      expect(gpt4o.name, '我的定制 GPT');
      expect(gpt4o.temperature, 0.3);
      expect(gpt4o.contextWindow, 128000);
      expect(gpt4o.isMultimodal, isTrue);

      // 远端不存在的本地自定义模型被追加保留
      final custom = result.models.firstWhere((m) => m.id == 'my-custom-model');
      expect(custom.name, '本地自定义');
      expect(custom.temperature, 0.5);
    });

    test('models.dev 不可用时回退启发式判断', () async {
      final failingCatalog = ModelsDevCatalog(
        client: MockClient((request) async => http.Response('oops', 500)),
      );
      final fetcher = LlmModelFetcher(
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'data': [
                {'id': 'deepseek-reasoner'},
              ],
            }),
            200,
          ),
        ),
        modelsDevCatalog: failingCatalog,
      );

      final result = await fetcher.fetchRemoteModels(
        baseUrl: 'https://api.deepseek.com/v1',
        protocol: LlmProtocol.openAiChat,
        apiKey: '',
      );

      expect(result.enrichedCount, 0);
      final model = result.models.single;
      expect(model.reasoning, isTrue);
      expect(model.supportedThinkingLevels, [ThinkingEffort.high]);
      expect(model.contextWindow, 64000);
    });

    test('Ollama /api/tags 格式解析', () async {
      final fetcher = LlmModelFetcher(
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'models': [
                {'name': 'llama3.3:latest', 'model': 'llama3.3:latest'},
              ],
            }),
            200,
          ),
        ),
        modelsDevCatalog: buildCatalog(),
      );

      final result = await fetcher.fetchRemoteModels(
        baseUrl: 'http://localhost:11434',
        protocol: LlmProtocol.openAiChat,
        apiKey: '',
      );

      final model = result.models.single;
      expect(model.id, 'llama3.3:latest');
      expect(model.reasoning, isFalse);
      expect(model.contextWindow, 128000);
    });
  });
}
