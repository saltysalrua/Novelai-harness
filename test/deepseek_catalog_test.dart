import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/data/models/llm_models.dart';
import 'package:novelai_harness/data/services/config_service.dart';
import 'package:novelai_harness/l10n/app_localizations.dart';
import 'package:novelai_harness/ui/core/theme/app_theme.dart';
import 'package:novelai_harness/ui/features/settings/widgets/model_profile_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _currentDeepSeekIds = ['deepseek-flash', 'deepseek-v4-pro'];
const _retiredFlashAliases = [
  'deepseek-chat',
  'deepseek-reasoner',
  'deepseek-v4-flash',
  'deepseek-v4-flash-vision-exp',
];

Future<LlmModelConfig> _saveModelProfile(
  WidgetTester tester,
  LlmModelConfig model, {
  bool removeHigh = false,
}) async {
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
            key: const ValueKey('open-model-profile'),
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
  await tester.tap(find.byKey(const ValueKey('open-model-profile')));
  await tester.pumpAndSettle();
  if (removeHigh) {
    await tester.ensureVisible(find.text('High'));
    await tester.tap(find.text('High'));
    await tester.pump();
  }
  await tester.tap(find.text('Save'));
  await tester.pumpAndSettle();
  return result!.model!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('DeepSeek factory catalog matches the current official API models', () {
    final provider = LlmProviderConfig.defaultProviders.singleWhere(
      (provider) => provider.id == 'deepseek',
    );

    expect(provider.baseUrl, 'https://api.deepseek.com');
    expect(provider.activeModelId, 'deepseek-flash');
    expect(provider.models.map((model) => model.id), _currentDeepSeekIds);

    final flash = provider.models[0];
    expect(flash.name, 'DeepSeek V4.1 Flash');
    expect(flash.input, ['text', 'image']);
    expect(flash.isMultimodal, isTrue);

    final pro = provider.models[1];
    expect(pro.name, 'DeepSeek V4 Pro');
    expect(pro.input, ['text']);
    expect(pro.isMultimodal, isFalse);

    for (final model in provider.models) {
      expect(model.supportedThinkingLevels, [
        ThinkingEffort.low,
        ThinkingEffort.high,
        ThinkingEffort.max,
      ]);
      expect(model.defaultThinkingEffort, ThinkingEffort.high);
      expect(model.contextWindow, 1000000);
      expect(model.maxTokens, 393216);
    }
  });

  test('Missing model IDs use a provider-neutral fallback', () {
    expect(LlmModelConfig.fromJson({}).id, 'default');
  });

  test('Unrelated model catalogs retain their existing effort fallback', () {
    const model = LlmModelConfig(
      id: 'custom-reasoner',
      name: 'Custom reasoner',
      reasoning: true,
      supportedThinkingLevels: [
        ThinkingEffort.low,
        ThinkingEffort.high,
        ThinkingEffort.max,
      ],
    );

    expect(model.defaultThinkingEffort, ThinkingEffort.max);
  });

  testWidgets('Model editor preserves a supported preferred effort', (
    tester,
  ) async {
    final original = LlmProviderConfig.defaultDeepSeekProvider.activeModel;
    final saved = await _saveModelProfile(tester, original);

    expect(saved.supportedThinkingLevels, original.supportedThinkingLevels);
    expect(saved.preferredThinkingEffort, ThinkingEffort.high);
    expect(saved.defaultThinkingEffort, ThinkingEffort.high);
  });

  testWidgets('Model editor clears a preferred effort removed by the user', (
    tester,
  ) async {
    final original = LlmProviderConfig.defaultDeepSeekProvider.activeModel;
    final saved = await _saveModelProfile(tester, original, removeHigh: true);

    expect(saved.supportedThinkingLevels, [
      ThinkingEffort.low,
      ThinkingEffort.max,
    ]);
    expect(saved.preferredThinkingEffort, isNull);
    expect(saved.defaultThinkingEffort, ThinkingEffort.max);
  });

  for (final alias in _retiredFlashAliases) {
    test('Legacy scalar $alias migrates to the current official catalog', () {
      final provider = LlmProviderConfig.fromJson({
        'id': 'saved-deepseek',
        'name': 'Saved DeepSeek',
        'baseUrl': 'https://api.deepseek.com/v1',
        'apiKey': 'synthetic-deepseek-key',
        'model': alias,
        'temperature': 0.42,
        'thinkingParamFormat': 'deepseek',
      });

      expect(provider.id, 'saved-deepseek');
      expect(provider.name, 'Saved DeepSeek');
      expect(provider.baseUrl, 'https://api.deepseek.com/v1');
      expect(provider.apiKey, 'synthetic-deepseek-key');
      expect(provider.thinkingParamFormat, ThinkingParamFormat.deepseek);
      expect(provider.models.map((model) => model.id), _currentDeepSeekIds);
      expect(provider.activeModelId, 'deepseek-flash');
      expect(provider.activeModel.temperature, 0.42);
    });
  }

  test('Empty official legacy model uses the current catalog', () {
    final provider = LlmProviderConfig.fromJson({
      'baseUrl': 'https://api.deepseek.com',
      'model': '',
      'temperature': 0.25,
    });

    expect(provider.models.map((model) => model.id), _currentDeepSeekIds);
    expect(provider.activeModelId, 'deepseek-flash');
    expect(provider.activeModel.temperature, 0.25);
  });

  test(
    'Official migration keeps canonical and custom models without duplicates',
    () {
      final provider = LlmProviderConfig.fromJson({
        'id': 'customized-official',
        'name': 'Customized official account',
        'baseUrl': 'https://api.deepseek.com/v1',
        'apiKey': 'synthetic-account-key',
        'activeModelId': 'deepseek-reasoner',
        'models': [
          {
            'id': 'deepseek-flash',
            'name': 'My canonical Flash',
            'reasoning': true,
            'input': ['text', 'image'],
            'supportedThinkingLevels': ['low', 'high', 'max'],
            'contextWindow': 123456,
            'maxTokens': 6543,
            'temperature': 0.33,
          },
          {'id': 'deepseek-chat', 'name': 'Old chat', 'temperature': 0.11},
          {
            'id': 'deepseek-v4-flash-vision-exp',
            'name': 'Old vision',
            'temperature': 0.22,
          },
          {'id': 'custom-snapshot', 'name': 'Keep me', 'temperature': 0.77},
          {'id': 'deepseek-v4-pro', 'name': 'Pinned Pro', 'temperature': 0.55},
        ],
      });

      expect(provider.apiKey, 'synthetic-account-key');
      expect(provider.activeModelId, 'deepseek-flash');
      expect(provider.models.map((model) => model.id), [
        'deepseek-flash',
        'custom-snapshot',
        'deepseek-v4-pro',
      ]);

      final canonical = provider.models[0];
      expect(canonical.name, 'My canonical Flash');
      expect(canonical.contextWindow, 123456);
      expect(canonical.maxTokens, 6543);
      expect(canonical.temperature, 0.33);

      final custom = provider.models[1];
      expect(custom.name, 'Keep me');
      expect(custom.temperature, 0.77);

      final once = provider.toJson();
      final twice = LlmProviderConfig.fromJson(once).toJson();
      expect(twice, once);
    },
  );

  test('Official migration retains an already valid active selection', () {
    final original = const LlmProviderConfig(
      id: 'deepseek',
      name: 'DeepSeek',
      baseUrl: 'https://api.deepseek.com',
      apiKey: 'synthetic-key',
      activeModelId: 'deepseek-v4-pro',
      models: [
        LlmModelConfig(
          id: 'deepseek-v4-pro',
          name: 'Pro only',
          temperature: 0.18,
        ),
      ],
    ).toJson();

    expect(LlmProviderConfig.fromJson(original).toJson(), original);
  });

  for (final endpoint in [
    'https://relay.example/v1',
    'https://api.deepseek.com.relay.example/v1',
  ]) {
    test('Migration leaves third-party endpoint $endpoint untouched', () {
      final original = LlmProviderConfig(
        id: 'deepseek',
        name: 'Relay',
        baseUrl: endpoint,
        apiKey: 'synthetic-relay-key',
        activeModelId: 'deepseek-chat',
        models: const [
          LlmModelConfig(
            id: 'deepseek-chat',
            name: 'Relay chat alias',
            temperature: 0.37,
          ),
        ],
      ).toJson();

      expect(LlmProviderConfig.fromJson(original).toJson(), original);
    });
  }

  test(
    'SiliconFlow keeps its DeepSeek defaults while dropping retired Qwen',
    () {
      final provider = LlmProviderConfig.defaultProviders.singleWhere(
        (provider) => provider.id == 'siliconflow',
      );

      expect(provider.activeModelId, 'deepseek-ai/DeepSeek-V3');
      expect(provider.models.map((model) => model.id), [
        'deepseek-ai/DeepSeek-V3',
        'deepseek-ai/DeepSeek-R1',
      ]);
    },
  );

  group('ConfigService DeepSeek migration', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({
        'novelai_key': 'synthetic-novelai-key',
        'novelai_save_dir': '/tmp/harness-deepseek-catalog-test',
        'llm_api_key': 'synthetic-saved-llm-key',
      });
    });

    test('Fresh startup loads the current default DeepSeek catalog', () async {
      final config = await ConfigService().loadConfig();
      final provider = config.llmProviders.first;

      expect(provider.models.map((model) => model.id), _currentDeepSeekIds);
      expect(provider.activeModelId, 'deepseek-flash');
      expect(provider.apiKey, 'synthetic-saved-llm-key');
    });

    test('Legacy preferences preserve temperature while migrating', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('llm_model', 'deepseek-reasoner');
      await prefs.setDouble('llm_temperature', 0.35);

      final provider = (await ConfigService().loadConfig()).llmProviders.first;

      expect(provider.models.map((model) => model.id), _currentDeepSeekIds);
      expect(provider.activeModelId, 'deepseek-flash');
      expect(provider.activeModel.temperature, 0.35);
      expect(provider.apiKey, 'synthetic-saved-llm-key');
    });

    test(
      'Legacy relay without a model keeps the historical fallback',
      () async {
        SharedPreferences.setMockInitialValues({
          'novelai_key': 'synthetic-novelai-key',
          'novelai_save_dir': '/tmp/harness-deepseek-catalog-test',
          'llm_base_url': 'https://relay.example/v1',
          'llm_api_key': 'synthetic-relay-key',
          'llm_temperature': 0.27,
        });

        final provider =
            (await ConfigService().loadConfig()).llmProviders.first;

        expect(provider.baseUrl, 'https://relay.example/v1');
        expect(provider.apiKey, 'synthetic-relay-key');
        expect(provider.models.map((model) => model.id), ['deepseek-chat']);
        expect(provider.activeModelId, 'deepseek-chat');
        expect(provider.activeModel.temperature, 0.27);
      },
    );

    test(
      'Official secondary selections migrate and stay stable after reload',
      () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          'llm_providers_json',
          jsonEncode([
            const LlmProviderConfig(
              id: 'official-deepseek',
              name: 'Official DeepSeek',
              baseUrl: 'https://api.deepseek.com/v1',
              apiKey: 'synthetic-provider-key',
              activeModelId: 'deepseek-reasoner',
              models: [
                LlmModelConfig(
                  id: 'deepseek-reasoner',
                  name: 'Legacy reasoner',
                ),
                LlmModelConfig(
                  id: 'deepseek-v4-flash-vision-exp',
                  name: 'Legacy vision',
                ),
              ],
            ).toJson(),
          ]),
        );
        await prefs.setString('image_edit_provider_id', 'official-deepseek');
        await prefs.setString(
          'image_edit_model_id',
          'deepseek-v4-flash-vision-exp',
        );
        await prefs.setString(
          'novelai_compaction_provider_id',
          'official-deepseek',
        );
        await prefs.setString(
          'novelai_compaction_model_id',
          'deepseek-reasoner',
        );

        final service = ConfigService();
        final first = await service.loadConfig();
        expect(first.imageEditModelId, 'deepseek-flash');
        expect(first.imageEditModel?.id, 'deepseek-flash');
        expect(first.compactionModelId, 'deepseek-flash');

        await service.saveConfig(first);
        final second = await service.loadConfig();
        expect(second.imageEditModelId, 'deepseek-flash');
        expect(second.imageEditModel?.id, 'deepseek-flash');
        expect(second.compactionModelId, 'deepseek-flash');
      },
    );

    test('Relay secondary selections remain untouched', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'llm_providers_json',
        jsonEncode([
          const LlmProviderConfig(
            id: 'relay',
            name: 'Relay',
            baseUrl: 'https://relay.example/v1',
            apiKey: 'synthetic-relay-key',
            activeModelId: 'deepseek-chat',
            models: [
              LlmModelConfig(id: 'deepseek-chat', name: 'Relay chat'),
              LlmModelConfig(
                id: 'deepseek-v4-flash-vision-exp',
                name: 'Relay vision',
              ),
            ],
          ).toJson(),
        ]),
      );
      await prefs.setString('image_edit_provider_id', 'relay');
      await prefs.setString(
        'image_edit_model_id',
        'deepseek-v4-flash-vision-exp',
      );
      await prefs.setString('novelai_compaction_provider_id', 'relay');
      await prefs.setString('novelai_compaction_model_id', 'deepseek-chat');

      final config = await ConfigService().loadConfig();
      expect(config.imageEditModelId, 'deepseek-v4-flash-vision-exp');
      expect(config.compactionModelId, 'deepseek-chat');
    });

    test(
      'Saved provider migration remains stable after save and reload',
      () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          'llm_providers_json',
          jsonEncode([
            const LlmProviderConfig(
              id: 'deepseek',
              name: 'DeepSeek',
              baseUrl: 'https://api.deepseek.com/v1',
              apiKey: 'synthetic-provider-key',
              activeModelId: 'deepseek-v4-flash',
              models: [
                LlmModelConfig(
                  id: 'deepseek-v4-flash',
                  name: 'Legacy Flash',
                  temperature: 0.61,
                ),
                LlmModelConfig(id: 'private-model', name: 'Private model'),
              ],
            ).toJson(),
          ]),
        );

        final service = ConfigService();
        final first = await service.loadConfig();
        await service.saveConfig(first);
        final second = await service.loadConfig();

        expect(second.llmProviders.map((provider) => provider.toJson()), [
          first.llmProviders.first.toJson(),
        ]);
        expect(second.llmProviders.first.activeModelId, 'deepseek-flash');
        expect(second.llmProviders.first.activeModel.temperature, 0.61);
        expect(second.llmProviders.first.models.map((model) => model.id), [
          'deepseek-flash',
          'private-model',
        ]);
      },
    );
  });
}
