import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/core/harness/presets/agent_preset.dart';
import 'package:novelai_harness/data/services/preset_transfer_service.dart';
import 'package:novelai_harness/data/services/config_service.dart';
import 'package:novelai_harness/ui/features/settings/widgets/presets_settings_tab.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const sample = AgentPreset(
    id: 'custom',
    name: 'My preset',
    description: 'Custom content',
    systemPrompt: '  Keep this exact text.  ',
    enabledSkillIds: ['custom-skill'],
    enabledToolNames: [],
    allowedModifiableParams: [],
  );
  List<AgentPreset> decode(
    Object json, [
    List<AgentPreset> existing = const [],
  ]) => PresetTransferService.decode(
    jsonEncode(json),
    existing: existing,
    availableToolNames: PresetToolKeys.all,
  );

  test('round trip preserves empty permissions and exact prompt text', () {
    final imported = PresetTransferService.decode(
      PresetTransferService.encode(sample),
      existing: [],
      availableToolNames: PresetToolKeys.all,
    ).single;
    expect(imported.toJson(), sample.toJson());
  });
  test(
    'duplicates append independently and imported builtin flags cannot replace existing presets',
    () {
      final old = sample.copyWith(isBuiltin: true);
      final imported = decode([old.toJson(), old.toJson()], [old]);
      expect(imported.map((p) => p.id), ['custom-2', 'custom-3']);
      expect(imported.every((p) => !p.isBuiltin), isTrue);
      expect(old.toJson(), sample.copyWith(isBuiltin: true).toJson());
    },
  );
  test('missing or malformed permissions never gain legacy full access', () {
    for (final key in [
      'enabledSkillIds',
      'enabledToolNames',
      'allowedModifiableParams',
    ]) {
      for (final value in [
        null,
        'all',
        [1],
      ]) {
        expect(
          () => decode({...sample.toJson(), key: value}),
          throwsA(isA<PresetImportException>()),
        );
      }
    }
  });
  test('unknown tools and parameters fail the whole import', () {
    for (final field in ['enabledToolNames', 'allowedModifiableParams']) {
      expect(
        () => decode([
          sample.toJson(),
          {
            ...sample.toJson(),
            field: ['unsupported'],
          },
        ]),
        throwsA(isA<PresetImportException>()),
      );
    }
    expect(() => decode([]), throwsA(isA<PresetImportException>()));
  });

  test(
    'import stays in the draft without activating or mutating saved presets',
    () {
      final builtin = sample.copyWith(id: 'builtin', isBuiltin: true);
      final config = AppConfig(presets: [builtin], activePresetId: builtin.id);
      final draft = PresetsSettingsDraft(config);
      addTearDown(draft.dispose);
      // The UI updates its dropdown from this listener as each field loads.
      draft.nameController.addListener(draft.syncFromForm);
      final imported = sample.copyWith(
        name: ' Imported ',
        description: ' New description ',
      );
      draft.appendImportedPresets([imported]);
      expect(draft.currentPreset.toJson(), imported.toJson());
      expect(draft.activePresetId, builtin.id);
      expect(config.presets.single.toJson(), builtin.toJson());
      expect(config.activePresetId, builtin.id);
      draft.switchPreset(builtin.id);
      expect(draft.presets.last.toJson(), imported.toJson());
      draft.nameController.text = 'Ignored built-in form edit';
      expect(draft.currentPreset.toJson(), builtin.toJson());
    },
  );
}
