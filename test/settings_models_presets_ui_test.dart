import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/core/harness/presets/agent_preset.dart';
import 'package:novelai_harness/core/harness/skills/skills.dart';
import 'package:novelai_harness/core/harness/tools/agent_tool.dart';
import 'package:novelai_harness/data/models/novelai_models.dart';
import 'package:novelai_harness/data/services/config_service.dart';
import 'package:novelai_harness/data/services/llm_model_fetcher.dart';
import 'package:novelai_harness/l10n/app_localizations.dart';
import 'package:novelai_harness/ui/core/theme/app_theme.dart';
import 'package:novelai_harness/ui/core/widgets/app_dialog_scaffold.dart';
import 'package:novelai_harness/ui/core/widgets/app_search_field.dart';
import 'package:novelai_harness/ui/features/settings/views/settings_dialog.dart';
import 'package:novelai_harness/ui/features/settings/widgets/model_card.dart';
import 'package:novelai_harness/ui/features/settings/widgets/models_settings_tab.dart';
import 'package:novelai_harness/ui/features/settings/widgets/presets_settings_tab.dart';
import 'package:novelai_harness/ui/features/settings/widgets/tool_editor_dialog.dart';
import 'package:novelai_harness/ui/features/studio/view_models/studio_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeStudioViewModel implements StudioViewModel {
  @override
  AppConfig get config => const AppConfig(
    localePreference: AppLocalePreference.zh,
    enableTagDictionaryAutoUpdate: false,
  );

  @override
  List<Skill> get availableSkills => const [
    Skill(
      id: 'skill-alpha',
      name: 'Alpha Skill',
      description: 'First skill',
      systemPrompt: 'Alpha prompt',
      isBuiltin: true,
    ),
    Skill(
      id: 'skill-beta',
      name: 'Beta Skill',
      description: 'Second skill',
      systemPrompt: 'Beta prompt',
      isBuiltin: false,
    ),
  ];

  @override
  List<AgentTool> get availableTools => [
    CustomAgentTool(
      name: 'tool_one',
      label: 'Tool One',
      description: 'First tool',
      parameters: const {'type': 'object', 'properties': {}},
    ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _wrapApp(Widget home) {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: home),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'ModelsSettingsTab combines search query with image-only filter and resets on provider switch',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final draft = ModelsSettingsDraft(
        const AppConfig(
          activeLlmProviderId: 'p1',
          llmProviders: [
            LlmProviderConfig(
              id: 'p1',
              name: 'Provider One',
              baseUrl: 'https://api.example.com/v1',
              activeModelId: 'chat-a',
              models: [
                LlmModelConfig(id: 'chat-a', name: 'Chat A'),
                LlmModelConfig(
                  id: 'img-alpha',
                  name: 'Image Alpha',
                  imageOutput: true,
                ),
                LlmModelConfig(
                  id: 'img-beta',
                  name: 'Image Beta',
                  imageOutput: true,
                ),
              ],
            ),
            LlmProviderConfig(
              id: 'p2',
              name: 'Provider Two',
              baseUrl: 'https://api.second.com/v1',
              activeModelId: 'second-model',
              models: [
                LlmModelConfig(id: 'second-model', name: 'Second Model'),
              ],
            ),
          ],
        ),
      );

      await tester.pumpWidget(
        _wrapApp(
          ModelsSettingsTab(viewModel: _FakeStudioViewModel(), draft: draft),
        ),
      );
      await tester.pumpAndSettle();

      // 搜索 "alpha" 并叠加 "仅绘图模型" 过滤，只应命中 Image Alpha
      await tester.enterText(find.byType(AppSearchField), 'alpha');
      await tester.pumpAndSettle();
      await tester.tap(find.text('仅绘图模型'));
      await tester.pumpAndSettle();

      expect(find.text('Image Alpha'), findsOneWidget);
      expect(find.text('Image Beta'), findsNothing);
      expect(find.text('Chat A'), findsNothing);

      // 切换供应商后网格搜索状态应复位，展示新供应商的模型
      await tester.tap(find.text('Provider Two'));
      await tester.pumpAndSettle();

      expect(find.text('Second Model'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'ModelsSettingsTab defaults to alphabetical A-Z sort and switches sort modes',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final draft = ModelsSettingsDraft(
        const AppConfig(
          activeLlmProviderId: 'p1',
          llmProviders: [
            LlmProviderConfig(
              id: 'p1',
              name: 'Provider One',
              baseUrl: 'https://api.example.com/v1',
              activeModelId: 'zeta',
              models: [
                LlmModelConfig(
                  id: 'zeta',
                  name: 'Zeta Chat',
                  contextWindow: 32000,
                ),
                LlmModelConfig(
                  id: 'alpha',
                  name: 'Alpha Small',
                  contextWindow: 16000,
                ),
                LlmModelConfig(
                  id: 'beta',
                  name: 'Beta Long',
                  contextWindow: 1000000,
                  reasoning: true,
                ),
              ],
            ),
          ],
        ),
      );

      await tester.pumpWidget(
        _wrapApp(
          ModelsSettingsTab(viewModel: _FakeStudioViewModel(), draft: draft),
        ),
      );
      await tester.pumpAndSettle();

      List<String> renderedModelIds() => tester
          .widgetList<ModelCard>(find.byType(ModelCard))
          .map((card) => card.model.id)
          .toList();

      // 默认按名称首字母 A-Z 排序
      expect(renderedModelIds(), ['alpha', 'beta', 'zeta']);
      expect(find.text('名称 A-Z'), findsOneWidget);

      // 切换为「上下文从大到小」
      await tester.tap(find.text('名称 A-Z'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('上下文从大到小').last);
      await tester.pumpAndSettle();

      expect(renderedModelIds(), ['beta', 'zeta', 'alpha']);
      expect(tester.takeException(), isNull);
    },
  );

  test('sortLlmModels sorts by all supported modes with A-Z tie-breaker', () {
    const models = [
      LlmModelConfig(
        id: 'm-zeta',
        name: 'Zeta',
        contextWindow: 64000,
        maxTokens: 4096,
      ),
      LlmModelConfig(
        id: 'm-alpha',
        name: 'Alpha',
        contextWindow: 128000,
        maxTokens: 8192,
        reasoning: true,
      ),
      LlmModelConfig(
        id: 'm-beta',
        name: 'beta',
        contextWindow: 256000,
        maxTokens: 16384,
        input: ['text', 'image'],
        imageOutput: true,
      ),
    ];

    expect(
      sortLlmModels(models, ModelSortMode.defaultOrder).map((m) => m.id),
      ['m-zeta', 'm-alpha', 'm-beta'],
    );
    expect(
      sortLlmModels(models, ModelSortMode.nameAsc).map((m) => m.id),
      ['m-alpha', 'm-beta', 'm-zeta'],
    );
    expect(
      sortLlmModels(models, ModelSortMode.nameDesc).map((m) => m.id),
      ['m-zeta', 'm-beta', 'm-alpha'],
    );
    expect(
      sortLlmModels(models, ModelSortMode.contextDesc).map((m) => m.id),
      ['m-beta', 'm-alpha', 'm-zeta'],
    );
    expect(
      sortLlmModels(models, ModelSortMode.maxTokensDesc).map((m) => m.id),
      ['m-beta', 'm-alpha', 'm-zeta'],
    );
    expect(
      sortLlmModels(models, ModelSortMode.thinkingFirst).map((m) => m.id),
      ['m-alpha', 'm-beta', 'm-zeta'],
    );
    expect(
      sortLlmModels(models, ModelSortMode.multimodalFirst).map((m) => m.id),
      ['m-beta', 'm-alpha', 'm-zeta'],
    );
    expect(
      sortLlmModels(models, ModelSortMode.imageOutputFirst).map((m) => m.id),
      ['m-beta', 'm-alpha', 'm-zeta'],
    );
  });

  test(
    'ModelsSettingsDraft.applyFetchResult drops deleted models and revalidates selections',
    () {
      final draft = ModelsSettingsDraft(
        const AppConfig(
          activeLlmProviderId: 'p1',
          imageEditProviderId: 'p1',
          imageEditModelId: 'deleted-img',
          llmProviders: [
            LlmProviderConfig(
              id: 'p1',
              name: 'Relay',
              activeModelId: 'deleted-chat',
              models: [
                LlmModelConfig(id: 'deleted-chat', name: 'Deleted Chat'),
                LlmModelConfig(
                  id: 'deleted-img',
                  name: 'Deleted Image',
                  imageOutput: true,
                ),
                LlmModelConfig(id: 'kept-chat', name: 'Kept Chat'),
              ],
            ),
          ],
        ),
      );

      draft.applyFetchResult(
        const RemoteModelFetchResult(
          models: [
            LlmModelConfig(id: 'kept-chat', name: 'Kept Chat'),
            LlmModelConfig(
              id: 'new-img',
              name: 'New Image',
              imageOutput: true,
            ),
          ],
          enrichedCount: 0,
        ),
      );

      expect(draft.currentProvider.models.map((m) => m.id), [
        'kept-chat',
        'new-img',
      ]);
      expect(draft.currentProvider.activeModelId, 'kept-chat');
      expect(draft.imageEditModelId, 'new-img');
    },
  );

  testWidgets(
    'ModelsSettingsTab keeps normal cards compact while expanding multi-row badge cards without overflow',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(620, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final draft = ModelsSettingsDraft(
        const AppConfig(
          activeLlmProviderId: 'p1',
          llmProviders: [
            LlmProviderConfig(
              id: 'p1',
              name: 'Provider One',
              baseUrl: 'https://api.example.com/v1',
              activeModelId: 'alpha-1',
              models: [
                LlmModelConfig(
                  id: 'alpha-1',
                  name: 'Alpha Compact',
                  contextWindow: 128000,
                ),
                LlmModelConfig(
                  id: 'beta-2',
                  name: 'Beta Compact',
                  reasoning: true,
                  contextWindow: 128000,
                ),
                LlmModelConfig(
                  id: 'zeta-omni',
                  name: 'Zeta Omni Reasoning Image Model',
                  reasoning: true,
                  input: ['text', 'image'],
                  imageOutput: true,
                  contextWindow: 1048576,
                ),
              ],
            ),
          ],
        ),
      );

      await tester.pumpWidget(
        _wrapApp(
          ModelsSettingsTab(viewModel: _FakeStudioViewModel(), draft: draft),
        ),
      );
      await tester.pumpAndSettle();

      final cards = find.byType(ModelCard);
      expect(cards, findsNWidgets(3));
      // 第一行普通卡片保持紧凑高度，不留多余空白
      final firstRowHeight = tester.getSize(cards.at(0)).height;
      final omniCardHeight = tester.getSize(cards.at(2)).height;
      expect(firstRowHeight, lessThanOrEqualTo(108));
      expect(omniCardHeight, greaterThanOrEqualTo(firstRowHeight));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'PresetsSettingsTab switches presets via pills and duplicates builtin preset',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final draft = PresetsSettingsDraft(
        AppConfig(
          activePresetId: BuiltinPresets.all.first.id,
          presets: BuiltinPresets.all,
        ),
      );

      await tester.pumpWidget(
        _wrapApp(
          PresetsSettingsTab(viewModel: _FakeStudioViewModel(), draft: draft),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('复制并自定义'), findsOneWidget);
      await tester.tap(find.text('复制并自定义'));
      await tester.pumpAndSettle();

      expect(draft.currentPreset.isBuiltin, isFalse);
      expect(draft.presets.length, BuiltinPresets.all.length + 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'ToolEditorDialog renders read-only schema without TextFields and supports JSON formatting',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final tool = CustomAgentTool(
        name: 'my_tool',
        label: 'My Tool',
        description: 'Reads data',
        parameters: const {'type': 'object', 'properties': {}},
      );

      await tester.pumpWidget(
        _wrapApp(
          Builder(
            builder: (context) => Column(
              children: [
                TextButton(
                  onPressed: () => AppDialogScaffold.show<void>(
                    context: context,
                    builder: (_) => ToolEditorDialog(
                      tool: tool,
                      isReadOnlySchemaView: true,
                    ),
                  ),
                  child: const Text('inspect'),
                ),
                TextButton(
                  onPressed: () => AppDialogScaffold.show<CustomAgentTool>(
                    context: context,
                    builder: (_) => ToolEditorDialog(tool: tool),
                  ),
                  child: const Text('edit'),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.text('inspect'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Reads data'), findsOneWidget);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('edit'));
      await tester.pumpAndSettle();
      expect(find.text('格式化 JSON'), findsOneWidget);
      await tester.tap(find.text('格式化 JSON'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'SettingsDialog ESC unfocuses active text field before closing',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _wrapApp(
          Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  SettingsDialog.show(context, _FakeStudioViewModel()),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(SettingsDialog), findsOneWidget);
      final firstField = find.byType(TextField).first;
      await tester.ensureVisible(firstField);
      await tester.pumpAndSettle();
      await tester.tap(firstField);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorStateOfType<EditableTextState>(),
        isNotNull,
      );

      // 首次 ESC 仅退焦，不关闭弹窗
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(SettingsDialog), findsOneWidget);

      // 再次 ESC 关闭设置弹窗
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(SettingsDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
