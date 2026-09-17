import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:novelai_harness/core/harness/providers/openai_provider.dart';
import 'package:novelai_harness/data/models/llm_models.dart';
import 'package:novelai_harness/data/services/config_service.dart';
import 'package:novelai_harness/data/services/llm_model_fetcher.dart';
import 'package:novelai_harness/data/services/models_dev_catalog.dart';
import 'package:novelai_harness/l10n/app_localizations.dart';
import 'package:novelai_harness/ui/core/theme/app_theme.dart';
import 'package:novelai_harness/ui/features/settings/widgets/model_profile_dialog.dart';
import 'package:novelai_harness/ui/features/studio/view_models/studio_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _legacyAnthropicIds = [
  'claude-3-7-sonnet-20250219',
  'claude-3-5-sonnet-20241022',
  'claude-3-5-haiku-20241022',
];

LlmProviderConfig _provider(String id) =>
    LlmProviderConfig.defaultProviders.singleWhere((p) => p.id == id);

Map<String, dynamic> _legacyAnthropicJson({
  String baseUrl = 'https://api.anthropic.com/v1',
}) => {
  'id': 'anthropic',
  'name': 'Anthropic',
  'baseUrl': baseUrl,
  'protocol': 'messages',
  'apiKey': 'synthetic-anthropic-key',
  'activeModelId': 'claude-3-7-sonnet-20250219',
  'thinkingParamFormat': 'auto',
  'models': [
    {
      'id': 'claude-3-7-sonnet-20250219',
      'name': 'Claude 3.7 Sonnet',
      'reasoning': true,
      'input': ['text', 'image'],
      'supportedThinkingLevels': ['low', 'medium', 'high'],
      'contextWindow': 200000,
      'maxTokens': 64000,
      'temperature': 0.31,
      'cacheConfig': {'mode': 'off', 'retention': 'short', 'affinity': 'off'},
    },
    {
      'id': 'claude-3-5-sonnet-20241022',
      'name': 'Claude 3.5 Sonnet',
      'contextWindow': 200000,
      'maxTokens': 8192,
      'temperature': 0.52,
    },
    {
      'id': 'claude-3-5-haiku-20241022',
      'name': 'Claude 3.5 Haiku',
      'contextWindow': 200000,
      'maxTokens': 8192,
      'temperature': 0.43,
      'cacheConfig': {
        'mode': 'anthropic',
        'retention': 'long',
        'affinity': 'off',
      },
    },
    {
      'id': 'private-claude-snapshot',
      'name': 'Private Claude Snapshot',
      'temperature': 0.77,
    },
  ],
};

Map<String, dynamic> _legacyGoogleJson({
  String baseUrl = 'https://generativelanguage.googleapis.com/v1beta/openai',
}) => {
  'id': 'google',
  'name': 'Google Gemini',
  'baseUrl': baseUrl,
  'protocol': 'openai',
  'apiKey': 'synthetic-google-key',
  'activeModelId': 'gemini-2.5-pro',
  'models': [
    {
      'id': 'gemini-2.5-flash',
      'name': 'My Flash',
      'reasoning': true,
      'input': ['text', 'image'],
      'supportedThinkingLevels': ['low', 'medium', 'high'],
      'contextWindow': 1000000,
      'maxTokens': 65536,
      'temperature': 0.22,
      'cacheConfig': {'mode': 'off', 'retention': 'short', 'affinity': 'off'},
    },
    {
      'id': 'gemini-2.5-pro',
      'name': 'My Pro',
      'reasoning': true,
      'input': ['text', 'image'],
      'supportedThinkingLevels': ['low', 'medium', 'high'],
      'contextWindow': 2000000,
      'maxTokens': 65536,
      'temperature': 0.44,
      'cacheConfig': {
        'mode': 'openai',
        'retention': 'long',
        'affinity': 'openai',
      },
    },
    {
      'id': 'gemini-private',
      'name': 'Keep Private',
      'contextWindow': 777777,
      'temperature': 0.66,
    },
  ],
};

Future<LlmModelConfig> _saveModelProfile(
  WidgetTester tester,
  LlmModelConfig model,
) async {
  ModelProfileResult? result;
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              result = await ModelProfileDialog.show(
                context,
                model: model,
                canDelete: false,
              );
            },
            child: const Text('Edit model'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Edit model'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Save'));
  await tester.pumpAndSettle();
  return result!.model!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OpenAI-compatible factory catalog', () {
    test('OpenAI defaults contain only current non-reasoning Chat models', () {
      expect(_provider('openai').models.map((m) => m.id), [
        'gpt-4o',
        'gpt-4o-mini',
      ]);
    });

    test('Anthropic uses its Chat compatibility route and current IDs', () {
      final provider = _provider('anthropic');

      expect(provider.protocol, LlmProtocol.openAiChat);
      expect(
        provider.fullEndpointUrl,
        'https://api.anthropic.com/v1/chat/completions',
      );
      expect(provider.activeModelId, 'claude-sonnet-5');
      expect(provider.models.map((m) => m.id), [
        'claude-sonnet-5',
        'claude-haiku-4-5-20251001',
      ]);
      expect(provider.models[0].contextWindow, 1000000);
      expect(provider.models[0].maxTokens, 128000);
      expect(provider.models[1].contextWindow, 200000);
      expect(provider.models[1].maxTokens, 64000);
      for (final model in provider.models) {
        expect(model.input, ['text', 'image']);
        expect(model.supportsThinking, isFalse);
        expect(model.supportedThinkingLevels, isEmpty);
      }
    });

    test('Gemini limits and explicit-off capability match each model', () {
      final provider = _provider('google');
      final flash = provider.models.singleWhere(
        (m) => m.id == 'gemini-2.5-flash',
      );
      final pro = provider.models.singleWhere((m) => m.id == 'gemini-2.5-pro');

      expect(flash.contextWindow, 1048576);
      expect(pro.contextWindow, 1048576);
      expect(flash.maxTokens, 65536);
      expect(pro.maxTokens, 65536);
      expect(flash.supportsThinkingOff, isTrue);
      expect(pro.supportsThinkingOff, isFalse);
      expect(flash.availableThinkingLevels, [
        ThinkingEffort.none,
        ThinkingEffort.low,
        ThinkingEffort.medium,
        ThinkingEffort.high,
      ]);
      expect(pro.availableThinkingLevels, [
        ThinkingEffort.low,
        ThinkingEffort.medium,
        ThinkingEffort.high,
      ]);
    });

    test('SiliconFlow removes only the retired new-default entry', () {
      final provider = _provider('siliconflow');

      expect(provider.activeModelId, 'deepseek-ai/DeepSeek-V3');
      expect(provider.models.map((m) => m.id), [
        'deepseek-ai/DeepSeek-V3',
        'deepseek-ai/DeepSeek-R1',
      ]);
    });

    test('Ollama model tags and configured contexts remain unchanged', () {
      final provider = _provider('ollama');

      expect(provider.models.map((m) => (m.id, m.contextWindow)), [
        ('llama3.3', 128000),
        ('deepseek-r1:14b', 64000),
        ('qwen2.5:7b', 32000),
      ]);
    });
  });

  group('Thinking-off metadata round trips', () {
    test('JSON and copyWith retain a model that cannot disable thinking', () {
      const model = LlmModelConfig(
        id: 'always-thinking',
        name: 'Always Thinking',
        reasoning: true,
        supportedThinkingLevels: [ThinkingEffort.low, ThinkingEffort.high],
        supportsThinkingOff: false,
      );

      final restored = LlmModelConfig.fromJson(model.toJson());
      expect(restored.supportsThinkingOff, isFalse);
      expect(restored.copyWith(name: 'Renamed').supportsThinkingOff, isFalse);
    });

    test('Old JSON defaults to allowing thinking off', () {
      final restored = LlmModelConfig.fromJson({
        'id': 'legacy-reasoner',
        'name': 'Legacy Reasoner',
        'reasoning': true,
        'supportedThinkingLevels': ['high'],
      });

      expect(restored.supportsThinkingOff, isTrue);
      expect(restored.availableThinkingLevels, [
        ThinkingEffort.none,
        ThinkingEffort.high,
      ]);
    });

    testWidgets('Model editor preserves the explicit-off capability', (
      tester,
    ) async {
      final saved = await _saveModelProfile(
        tester,
        const LlmModelConfig(
          id: 'gemini-2.5-pro',
          name: 'Gemini 2.5 Pro',
          reasoning: true,
          supportedThinkingLevels: [
            ThinkingEffort.low,
            ThinkingEffort.medium,
            ThinkingEffort.high,
          ],
          supportsThinkingOff: false,
        ),
      );

      expect(saved.supportsThinkingOff, isFalse);
    });
  });

  group('Canonical built-in migration', () {
    test('Anthropic legacy preset migrates while retaining user fields', () {
      final migrated = LlmProviderConfig.fromJson(_legacyAnthropicJson());

      expect(migrated.apiKey, 'synthetic-anthropic-key');
      expect(migrated.protocol, LlmProtocol.openAiChat);
      expect(migrated.activeModelId, 'claude-sonnet-5');
      expect(migrated.models.map((m) => m.id), [
        'claude-sonnet-5',
        'claude-haiku-4-5-20251001',
        'private-claude-snapshot',
      ]);
      final sonnet = migrated.models[0];
      expect(sonnet.temperature, 0.31);
      expect(sonnet.cacheConfig.mode, LlmCacheMode.off);
      final haiku = migrated.models[1];
      expect(haiku.temperature, 0.43);
      expect(haiku.cacheConfig.mode, LlmCacheMode.anthropic);
      expect(haiku.cacheConfig.retention, LlmCacheRetention.long);
      expect(migrated.models[2].temperature, 0.77);
    });

    test(
      'Anthropic-like relay configuration remains semantically untouched',
      () {
        final original = _legacyAnthropicJson(
          baseUrl: 'https://relay.example/v1',
        );
        final restored = LlmProviderConfig.fromJson(original);

        expect(restored.baseUrl, 'https://relay.example/v1');
        expect(restored.protocol, LlmProtocol.anthropicMessages);
        expect(restored.activeModelId, 'claude-3-7-sonnet-20250219');
        expect(restored.models.map((model) => model.id), [
          ..._legacyAnthropicIds,
          'private-claude-snapshot',
        ]);
        expect(restored.apiKey, 'synthetic-anthropic-key');
        expect(restored.models.first.temperature, 0.31);
      },
    );

    test('Gemini legacy metadata migrates without replacing user fields', () {
      final migrated = LlmProviderConfig.fromJson(_legacyGoogleJson());

      expect(migrated.activeModelId, 'gemini-2.5-pro');
      expect(migrated.models.map((m) => m.id), [
        'gemini-2.5-flash',
        'gemini-2.5-pro',
        'gemini-private',
      ]);
      final flash = migrated.models[0];
      expect(flash.name, 'My Flash');
      expect(flash.temperature, 0.22);
      expect(flash.cacheConfig.mode, LlmCacheMode.off);
      expect(flash.contextWindow, 1048576);
      expect(flash.supportsThinkingOff, isTrue);
      final pro = migrated.models[1];
      expect(pro.name, 'My Pro');
      expect(pro.temperature, 0.44);
      expect(pro.cacheConfig.mode, LlmCacheMode.openai);
      expect(pro.cacheConfig.retention, LlmCacheRetention.long);
      expect(pro.contextWindow, 1048576);
      expect(pro.supportsThinkingOff, isFalse);
      expect(migrated.models[2].contextWindow, 777777);
    });

    test('Gemini-like relay configuration remains semantically untouched', () {
      final original = _legacyGoogleJson(
        baseUrl: 'https://gemini-relay.example/v1',
      );
      final restored = LlmProviderConfig.fromJson(original);

      expect(restored.baseUrl, 'https://gemini-relay.example/v1');
      expect(restored.activeModelId, 'gemini-2.5-pro');
      expect(restored.models.map((model) => model.id), [
        'gemini-2.5-flash',
        'gemini-2.5-pro',
        'gemini-private',
      ]);
      expect(restored.models[0].contextWindow, 1000000);
      expect(restored.models[1].contextWindow, 2000000);
      expect(restored.models[2].contextWindow, 777777);
    });

    test('Saved deprecated OpenAI model is retained', () {
      final original = const LlmProviderConfig(
        id: 'openai',
        name: 'OpenAI',
        baseUrl: 'https://api.openai.com/v1',
        apiKey: 'synthetic-openai-key',
        activeModelId: 'o1',
        models: [
          LlmModelConfig(id: 'o1', name: 'Pinned o1', temperature: 0.45),
        ],
      ).toJson();

      expect(LlmProviderConfig.fromJson(original).toJson(), original);
    });

    test('Saved retired SiliconFlow model is retained', () {
      final original = const LlmProviderConfig(
        id: 'siliconflow',
        name: 'SiliconFlow',
        baseUrl: 'https://api.siliconflow.cn/v1',
        apiKey: 'synthetic-silicon-key',
        activeModelId: 'Qwen/Qwen2.5-Coder-32B-Instruct',
        models: [
          LlmModelConfig(
            id: 'Qwen/Qwen2.5-Coder-32B-Instruct',
            name: 'Pinned Qwen',
            temperature: 0.35,
          ),
        ],
      ).toJson();

      expect(LlmProviderConfig.fromJson(original).toJson(), original);
    });

    test(
      'Migrated canonical presets are stable after save and reload',
      () async {
        SharedPreferences.setMockInitialValues({
          'novelai_key': 'synthetic-novelai-key',
          'novelai_save_dir': '/tmp/harness-provider-migration-test',
          'llm_providers_json': jsonEncode([
            _legacyAnthropicJson(),
            _legacyGoogleJson(),
          ]),
          'active_llm_provider_id': 'anthropic',
          'image_edit_provider_id': 'anthropic',
          'image_edit_model_id': 'claude-3-5-haiku-20241022',
          'novelai_compaction_provider_id': 'anthropic',
          'novelai_compaction_model_id': 'claude-3-7-sonnet-20250219',
        });
        final service = ConfigService();

        final first = await service.loadConfig();
        await service.saveConfig(first);
        final second = await service.loadConfig();

        expect(
          second.llmProviders.map((provider) => provider.toJson()),
          first.llmProviders.map((provider) => provider.toJson()),
        );
        expect(second.activeLlmProviderId, 'anthropic');
        expect(second.imageEditModelId, 'claude-haiku-4-5-20251001');
        expect(second.compactionModelId, 'claude-sonnet-5');
      },
    );

    test('Relay secondary model references are not canonicalized', () async {
      SharedPreferences.setMockInitialValues({
        'novelai_key': 'synthetic-novelai-key',
        'novelai_save_dir': '/tmp/harness-provider-relay-test',
        'llm_providers_json': jsonEncode([
          _legacyAnthropicJson(baseUrl: 'https://relay.example/v1'),
        ]),
        'active_llm_provider_id': 'anthropic',
        'image_edit_provider_id': 'anthropic',
        'image_edit_model_id': 'claude-3-5-haiku-20241022',
        'novelai_compaction_provider_id': 'anthropic',
        'novelai_compaction_model_id': 'claude-3-7-sonnet-20250219',
      });

      final config = await ConfigService().loadConfig();

      expect(config.imageEditModelId, 'claude-3-5-haiku-20241022');
      expect(config.compactionModelId, 'claude-3-7-sonnet-20250219');
    });
  });

  group('Fetched Gemini metadata', () {
    test(
      'Refresh keeps model-specific thinking-off and exact context metadata',
      () async {
        final failingCatalog = ModelsDevCatalog(
          client: MockClient((request) async => http.Response('offline', 500)),
        );
        final fetcher = LlmModelFetcher(
          client: MockClient(
            (request) async => http.Response(
              jsonEncode({
                'data': [
                  {'id': 'gemini-2.5-flash'},
                  {'id': 'gemini-2.5-pro'},
                ],
              }),
              200,
            ),
          ),
          modelsDevCatalog: failingCatalog,
        );
        final existing = _provider('google').models;

        final result = await fetcher.fetchRemoteModels(
          baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
          protocol: LlmProtocol.openAiChat,
          apiKey: 'synthetic-google-key',
          existingModels: existing,
        );
        final flash = result.models.singleWhere(
          (m) => m.id == 'gemini-2.5-flash',
        );
        final pro = result.models.singleWhere((m) => m.id == 'gemini-2.5-pro');

        expect(flash.contextWindow, 1048576);
        expect(pro.contextWindow, 1048576);
        expect(
          flash.supportedThinkingLevels,
          existing[0].supportedThinkingLevels,
        );
        expect(
          pro.supportedThinkingLevels,
          existing[1].supportedThinkingLevels,
        );
        expect(flash.supportsThinkingOff, isTrue);
        expect(pro.supportsThinkingOff, isFalse);
      },
    );
  });

  group('Fetched Anthropic compatibility metadata', () {
    Future<LlmModelConfig> fetchClaude({
      required String baseUrl,
      required LlmProtocol protocol,
    }) async {
      final fetcher = LlmModelFetcher(
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'data': [
                {'id': 'claude-sonnet-5', 'reasoning': true},
              ],
            }),
            200,
          ),
        ),
        modelsDevCatalog: ModelsDevCatalog(
          client: MockClient((request) async => http.Response('offline', 500)),
        ),
      );

      final result = await fetcher.fetchRemoteModels(
        baseUrl: baseUrl,
        protocol: protocol,
        apiKey: 'synthetic-anthropic-key',
        existingModels: [_provider('anthropic').models.first],
      );
      return result.models.single;
    }

    test(
      'Official Anthropic Chat refresh suppresses ignored effort controls',
      () async {
        final model = await fetchClaude(
          baseUrl: 'https://api.anthropic.com/v1',
          protocol: LlmProtocol.openAiChat,
        );

        expect(model.reasoning, isFalse);
        expect(model.supportedThinkingLevels, isEmpty);
      },
    );

    test(
      'Anthropic-like relay refresh keeps upstream reasoning metadata',
      () async {
        final model = await fetchClaude(
          baseUrl: 'https://anthropic-relay.example/v1',
          protocol: LlmProtocol.openAiChat,
        );

        expect(model.reasoning, isTrue);
        expect(model.supportedThinkingLevels, [ThinkingEffort.high]);
      },
    );

    test(
      'Native Anthropic protocol refresh is not compatibility-suppressed',
      () async {
        final model = await fetchClaude(
          baseUrl: 'https://api.anthropic.com/v1',
          protocol: LlmProtocol.anthropicMessages,
        );

        expect(model.reasoning, isTrue);
        expect(model.supportedThinkingLevels, [ThinkingEffort.high]);
      },
    );
  });

  group('Studio provider assembly', () {
    late Directory sessionBase;
    late StudioViewModel viewModel;

    Future<void> initialize({
      required LlmProviderConfig active,
      LlmProviderConfig? compaction,
    }) async {
      sessionBase = Directory.systemTemp.createTempSync(
        'nai_openai_compatible_provider_test_',
      );
      final providers = [active, ?compaction];
      final summary = compaction ?? active;
      SharedPreferences.setMockInitialValues({
        'novelai_key': 'synthetic-novelai-key',
        'novelai_save_dir': sessionBase.path,
        'novelai_enable_tag_dictionary_auto_update': false,
        'novelai_enable_image_persistence': false,
        'llm_api_key': 'synthetic-unused-key',
        'llm_providers_json': jsonEncode(
          providers.map((provider) => provider.toJson()).toList(),
        ),
        'active_llm_provider_id': active.id,
        'novelai_compaction_provider_id': summary.id,
        'novelai_compaction_model_id': summary.activeModelId,
      });
      viewModel = StudioViewModel(sessionLogBaseDir: sessionBase.path);
      await viewModel.init();
    }

    tearDown(() async {
      await viewModel.flushPendingSaves();
      viewModel.dispose();
      try {
        sessionBase.deleteSync(recursive: true);
      } catch (_) {}
    });

    test(
      'Keyless loopback Ollama is assembled for chat and compaction',
      () async {
        await initialize(active: _provider('ollama'));

        expect(viewModel.providerForTesting, isA<OpenAiCompatibleProvider>());
        expect(
          viewModel.compactionProviderForTesting,
          isA<OpenAiCompatibleProvider>(),
        );
        expect(viewModel.providerForTesting!.apiKey, isEmpty);
      },
    );

    test(
      'Remote empty-key endpoint stays disabled for chat and compaction',
      () async {
        const remote = LlmProviderConfig(
          id: 'remote-ollama',
          name: 'Remote Ollama',
          baseUrl: 'http://ollama.example:11434/v1',
          apiKey: '',
          activeModelId: 'llama3.3',
          models: [LlmModelConfig(id: 'llama3.3', name: 'Llama 3.3')],
        );
        await initialize(active: remote);

        expect(viewModel.providerForTesting, isNull);
        expect(viewModel.compactionProviderForTesting, isNull);
      },
    );

    test('Gemini Flash can explicitly turn thinking off everywhere', () async {
      final google = _provider('google').copyWith(
        apiKey: 'synthetic-google-key',
        activeModelId: 'gemini-2.5-flash',
      );
      await initialize(active: google);

      viewModel.setThinkingEffort(ThinkingEffort.none);

      expect(viewModel.currentThinkingEffort, ThinkingEffort.none);
      final chat = viewModel.providerForTesting!;
      final compaction = viewModel.compactionProviderForTesting!;
      expect(chat.reasoning, isFalse);
      expect(chat.thinkingEffort, 'none');
      expect(compaction.reasoning, isFalse);
      expect(compaction.thinkingEffort, 'none');
    });

    test('Gemini Pro never enters an unsupported thinking-off state', () async {
      final google = _provider('google').copyWith(
        apiKey: 'synthetic-google-key',
        activeModelId: 'gemini-2.5-pro',
      );
      await initialize(active: google);

      viewModel.setThinkingEffort(ThinkingEffort.none);

      expect(viewModel.currentThinkingEffort, ThinkingEffort.medium);
      final chat = viewModel.providerForTesting!;
      final compaction = viewModel.compactionProviderForTesting!;
      expect(chat.reasoning, isTrue);
      expect(chat.thinkingEffort, 'medium');
      expect(compaction.reasoning, isTrue);
      expect(compaction.thinkingEffort, 'medium');
    });
  });
}
