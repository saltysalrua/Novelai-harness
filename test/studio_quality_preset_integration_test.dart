import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/core/harness/presets/agent_preset.dart';
import 'package:novelai_harness/core/harness/tools/studio_params_tool.dart';
import 'package:novelai_harness/data/models/novelai_models.dart';

void main() {
  for (final off in ['Off', 'None']) {
    test('$off disables quality text and request metadata together', () async {
      var state = const NaiGenerationParams(
        prompt: '1girl, manga',
        model: NaiModel.v5Full,
        qualityToggle: true,
        qualityPreset: 'Standard',
      );
      final tool = NovelAiUpdateParamsTool(
        getCurrentParams: () => state,
        onUpdateParams: (value) => state = value,
      );

      await tool.execute('quality-off', {'quality_preset': off});

      expect(state.effectivePrompt, '1girl, manga');
      final payload = state.toApiPayload();
      final parameters = payload['parameters'] as Map<String, dynamic>;
      expect(payload['input'], '1girl, manga');
      expect(parameters['qualityPresetId'], 'none');
      expect(parameters['tag_hint_qt'], 0);
      final report =
          await NovelAiGetStudioParamsTool(
            getCurrentParams: () => state,
          ).execute('quality-state', {
            'keys': ['quality_preset'],
          });
      expect(report.content, contains('质量标签: Off'));
    });
  }

  test('selecting a quality preset re-enables its effective suffix', () async {
    var state = const NaiGenerationParams(
      prompt: '1girl, manga',
      model: NaiModel.v5Full,
      qualityToggle: false,
      qualityPreset: 'Standard',
    );
    final tool = NovelAiUpdateParamsTool(
      getCurrentParams: () => state,
      onUpdateParams: (value) => state = value,
    );
    await tool.execute('quality-light', {'quality_preset': 'Light'});

    expect(state.effectivePrompt, contains('amazing quality'));
    expect(state.effectivePrompt, isNot(contains('masterpiece')));
    final parameters =
        state.toApiPayload()['parameters'] as Map<String, dynamic>;
    expect(parameters['qualityPresetId'], 'light');
    expect(parameters['tag_hint_qt'], 3);
  });

  test(
    'a locked quality setting cannot disable the effective preset',
    () async {
      var state = const NaiGenerationParams(
        prompt: '1girl, manga',
        model: NaiModel.v5Full,
      );
      final before = state.effectivePrompt;
      final tool = NovelAiUpdateParamsTool(
        getCurrentParams: () => state,
        onUpdateParams: (value) => state = value,
        permissionChecker: (key) => key != PresetParamKeys.qualityPreset,
      );
      final result = await tool.execute('locked', {'quality_preset': 'Off'});
      expect(result.isError, isTrue);
      expect(state.effectivePrompt, before);
      expect(state.qualityToggle, isTrue);
    },
  );
}
