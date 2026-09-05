import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/core/harness/tools/character_prompt_tools.dart';
import 'package:novelai_harness/data/models/novelai_models.dart';

void main() {
  group('NaiCharacterPrompt Model Tests', () {
    test('JSON roundtrip preserves all fields', () {
      final character = NaiCharacterPrompt(
        id: 'deadbeef',
        name: '银发少女',
        prompt: 'girl, silver hair, blue eyes',
        negativePrompt: 'lowres, bad hands',
        enabled: false,
        useCustomPosition: true,
        positionX: 0.25,
        positionY: 0.75,
      );
      final restored = NaiCharacterPrompt.fromJson(character.toJson());
      expect(restored.id, 'deadbeef');
      expect(restored.name, '银发少女');
      expect(restored.prompt, 'girl, silver hair, blue eyes');
      expect(restored.negativePrompt, 'lowres, bad hands');
      expect(restored.enabled, isFalse);
      expect(restored.useCustomPosition, isTrue);
      expect(restored.positionX, 0.25);
      expect(restored.positionY, 0.75);
    });

    test('fromJson tolerates missing fields with defaults', () {
      final restored = NaiCharacterPrompt.fromJson({});
      expect(restored.enabled, isTrue);
      expect(restored.useCustomPosition, isFalse);
      expect(restored.positionX, 0.5);
      expect(restored.positionY, 0.5);
      expect(restored.prompt, isEmpty);
    });

    test('generateId returns unique 8-hex ids', () {
      final ids = {
        for (var i = 0; i < 50; i++) NaiCharacterPrompt.generateId(),
      };
      expect(ids.length, 50);
      for (final id in ids) {
        expect(id, hasLength(8));
        expect(id, matches(RegExp(r'^[0-9a-f]{8}$')));
      }
    });

    test('resolveCenter uses auto layout when not custom', () {
      const character = NaiCharacterPrompt(
        id: 'aaaaaaaa',
        name: 'A',
        prompt: 'girl',
      );
      // 两个角色时第一个自动位置是 (0.25, 0.5)
      final center = character.resolveCenter(0, 2);
      expect(center.x, closeTo(0.25, 0.001));
      expect(center.y, closeTo(0.5, 0.001));
    });

    test('resolveCenter clamps custom coordinates to 0.0-1.0', () {
      const character = NaiCharacterPrompt(
        id: 'aaaaaaaa',
        name: 'A',
        prompt: 'girl',
        useCustomPosition: true,
        positionX: 1.5,
        positionY: -0.3,
      );
      final center = character.resolveCenter(0, 1);
      expect(center.x, 1.0);
      expect(center.y, 0.0);
    });
  });

  group('Model Character Prompt Capability Tests', () {
    test('V5 allows 22 characters, V4/V4.5 allow 6, v3 none', () {
      expect(NaiModel.v5Full.maxCharacterPrompts, 22);
      expect(NaiModel.v5Curated.maxCharacterPrompts, 22);
      expect(NaiModel.v45Full.maxCharacterPrompts, 6);
      expect(NaiModel.v4Curated.maxCharacterPrompts, 6);
      expect(NaiModel.v3.maxCharacterPrompts, 0);
      expect(NaiModel.v3Furry.maxCharacterPrompts, 0);
    });

    test('V5 supports free positioning, V4 limited to grid', () {
      expect(NaiModel.v5Full.supportsFreeCharacterPositioning, isTrue);
      expect(NaiModel.v45Full.supportsFreeCharacterPositioning, isFalse);
    });

    test('gridQuantize snaps to quarter steps', () {
      expect(NaiCharacterPositionLayout.gridQuantize(0.1), closeTo(0.0, 1e-9));
      expect(NaiCharacterPositionLayout.gridQuantize(0.3), 0.25);
      expect(NaiCharacterPositionLayout.gridQuantize(0.6), 0.5);
      expect(NaiCharacterPositionLayout.gridQuantize(0.9), 1.0);
      expect(NaiCharacterPositionLayout.gridQuantize(2.0), 1.0);
    });
  });

  group('NaiCharacterPositionLayout Tests', () {
    test('positionsForCount returns stable defaults per count', () {
      expect(NaiCharacterPositionLayout.positionsForCount(0), isEmpty);
      final single = NaiCharacterPositionLayout.positionsForCount(1);
      expect(single.single, const (x: 0.5, y: 0.5));

      final two = NaiCharacterPositionLayout.positionsForCount(2);
      expect(two[0].x, closeTo(0.25, 0.001));
      expect(two[1].x, closeTo(0.75, 0.001));

      final four = NaiCharacterPositionLayout.positionsForCount(4);
      expect(four[0], const (x: 0.25, y: 0.25));
      expect(four[3], const (x: 0.75, y: 0.75));

      // 22 角色也能给出稳定的 3 列网格布局
      final twentyTwo = NaiCharacterPositionLayout.positionsForCount(22);
      expect(twentyTwo, hasLength(22));
    });

    test('positionForIndex falls back to center out of range', () {
      expect(NaiCharacterPositionLayout.positionForIndex(99, 2), const (
        x: 0.5,
        y: 0.5,
      ));
    });
  });

  group('Character Prompts Payload Tests', () {
    for (final model in NaiModel.values.where((model) => model.isV4OrAbove)) {
      test(
        '${model.name}: AI positioning keeps schema in generate/infill/metadata',
        () {
          final params = NaiGenerationParams(
            prompt: '2girls',
            model: model,
            characterPrompts: const [
              NaiCharacterPrompt(
                id: 'a',
                name: 'A',
                prompt: 'girl',
                negativePrompt: 'lowres',
                useCustomPosition: true,
                positionX: 0.1,
                positionY: 0.9,
              ),
              NaiCharacterPrompt(id: 'b', name: 'B', prompt: 'girl'),
            ],
          );
          final payloads = [
            params.toApiPayload(),
            params.toApiPayload(streaming: true),
            params.toInfillApiPayload(
              sourceBytes: Uint8List(0),
              maskBytes: Uint8List(0),
              requestWidth: 832,
              requestHeight: 1216,
            ),
            params.toInfillApiPayload(
              sourceBytes: Uint8List(0),
              maskBytes: Uint8List(0),
              requestWidth: 832,
              requestHeight: 1216,
              streaming: true,
            ),
          ];
          final structures = <Map<String, dynamic>>[
            for (final payload in payloads)
              payload['parameters'] as Map<String, dynamic>,
            params.toMetadataComment(seed: 42),
          ];
          for (final structure in structures) {
            final positive = structure['v4_prompt'] as Map<String, dynamic>;
            expect(positive['use_coords'], isFalse);
            for (final key in ['v4_prompt', 'v4_negative_prompt']) {
              final prompt = structure[key] as Map<String, dynamic>;
              final caption = prompt['caption'] as Map<String, dynamic>;
              final chars = caption['char_captions'] as List<dynamic>;
              expect(chars, hasLength(2));
              for (final entry in chars.cast<Map<String, dynamic>>()) {
                expect(entry['centers'], [
                  {'x': 0.5, 'y': 0.5},
                ]);
              }
            }
            if (structure.containsKey('characterPrompts')) {
              expect(structure['use_coords'], isFalse);
              final chars = structure['characterPrompts'] as List<dynamic>;
              for (final entry in chars.cast<Map<String, dynamic>>()) {
                expect(entry['center'], {'x': 0.5, 'y': 0.5});
                expect(entry['enabled'], isTrue);
              }
            }
          }
        },
      );
    }
    test(
      "AI's Choice disables constraints but keeps required center structures",
      () {
        const params = NaiGenerationParams(
          prompt: '2girls, classroom, sunlight',
          model: NaiModel.v5Full,
          characterPrompts: [
            NaiCharacterPrompt(
              id: 'aaaa0001',
              name: '左',
              prompt: 'girl, silver hair',
              negativePrompt: 'lowres',
            ),
            NaiCharacterPrompt(
              id: 'aaaa0002',
              name: '右',
              prompt: 'girl, black hair',
            ),
          ],
        );

        final payload = params.toApiPayload();
        final parameters = payload['parameters'] as Map<String, dynamic>;

        expect(params.useCoords, isFalse);
        expect(parameters['use_coords'], isFalse);
        expect(
          (parameters['v4_prompt'] as Map<String, dynamic>)['use_coords'],
          isFalse,
        );

        final characterPrompts =
            parameters['characterPrompts'] as List<dynamic>;
        expect(characterPrompts, hasLength(2));
        final first = characterPrompts[0] as Map<String, dynamic>;
        expect(first['center'], {'x': 0.5, 'y': 0.5});
        expect(first['prompt'], 'girl, silver hair');
        expect(first['uc'], 'lowres');
        expect(first['enabled'], isTrue);

        final v4Prompt = parameters['v4_prompt'] as Map<String, dynamic>;
        final caption = v4Prompt['caption'] as Map<String, dynamic>;
        expect(caption['base_caption'], params.effectivePrompt);
        final charCaptions = caption['char_captions'] as List<dynamic>;
        expect(charCaptions, hasLength(2));
        final secondCaption = charCaptions[1] as Map<String, dynamic>;
        expect(secondCaption['char_caption'], 'girl, black hair');
        expect(secondCaption['centers'], [
          {'x': 0.5, 'y': 0.5},
        ]);

        final v4Negative =
            parameters['v4_negative_prompt'] as Map<String, dynamic>;
        final negativeCaption = v4Negative['caption'] as Map<String, dynamic>;
        final negativeCharCaptions =
            negativeCaption['char_captions'] as List<dynamic>;
        expect(negativeCharCaptions, hasLength(2));
        expect(
          (negativeCharCaptions[1] as Map<String, dynamic>)['char_caption'],
          '',
        );
      },
    );

    test(
      'custom mode on V5 sends continuous decimal centers for every enabled character',
      () {
        const params = NaiGenerationParams(
          prompt: 'sunset',
          model: NaiModel.v5Full,
          characterAiPosition: false,
          characterPrompts: [
            NaiCharacterPrompt(
              id: 'bbbb0001',
              name: 'A',
              prompt: 'girl',
              useCustomPosition: true,
              positionX: 0.123,
              positionY: 0.456,
            ),
            NaiCharacterPrompt(
              id: 'bbbb0002',
              name: 'B',
              prompt: 'girl',
              // 未手动定位 → 按启用顺序自动布局
            ),
          ],
        );
        final parameters =
            params.toApiPayload()['parameters'] as Map<String, dynamic>;
        expect(parameters['use_coords'], isTrue);
        final entries = parameters['characterPrompts'] as List<dynamic>;
        expect(entries, hasLength(2));
        final firstCenter =
            (entries[0] as Map<String, dynamic>)['center']
                as Map<String, dynamic>;
        expect(firstCenter['x'], closeTo(0.123, 0.001));
        expect(firstCenter['y'], closeTo(0.456, 0.001));
        // 未手动定位的第二个角色落到两角色自动布局右侧
        final secondCenter =
            (entries[1] as Map<String, dynamic>)['center']
                as Map<String, dynamic>;
        expect(secondCenter['x'], closeTo(0.75, 0.001));
        expect(secondCenter['y'], closeTo(0.5, 0.001));
      },
    );

    test('custom mode on V4 quantizes coordinates to the 5x5 grid', () {
      const params = NaiGenerationParams(
        prompt: 'sunset',
        model: NaiModel.v45Full,
        characterAiPosition: false,
        characterPrompts: [
          NaiCharacterPrompt(
            id: 'cccc0001',
            name: 'A',
            prompt: 'girl',
            useCustomPosition: true,
            positionX: 0.3,
            positionY: 0.6,
          ),
        ],
      );
      final parameters =
          params.toApiPayload()['parameters'] as Map<String, dynamic>;
      expect(parameters['use_coords'], isTrue);
      final center =
          ((parameters['characterPrompts'] as List<dynamic>)[0]
                  as Map<String, dynamic>)['center']
              as Map<String, dynamic>;
      expect(center['x'], 0.25);
      expect(center['y'], 0.5);
    });

    test('custom mode with no characters still keeps use_coords false', () {
      const params = NaiGenerationParams(
        prompt: 'solo',
        model: NaiModel.v5Full,
        characterAiPosition: false,
      );
      expect(params.useCoords, isFalse);
    });

    test('disabled or empty-prompt characters are excluded from payload', () {
      const params = NaiGenerationParams(
        prompt: 'classroom',
        model: NaiModel.v5Curated,
        characterPrompts: [
          NaiCharacterPrompt(id: 'cccc0001', name: '启用', prompt: 'girl'),
          NaiCharacterPrompt(
            id: 'cccc0002',
            name: '停用',
            prompt: 'girl',
            enabled: false,
          ),
          NaiCharacterPrompt(id: 'cccc0003', name: '空提示词', prompt: '   '),
        ],
      );
      final parameters =
          params.toApiPayload()['parameters'] as Map<String, dynamic>;
      expect(parameters['characterPrompts'], hasLength(1));
      expect(params.enabledCharacterPrompts, hasLength(1));
      expect(params.useCoords, isFalse);
    });

    test('v3 model payload contains no character prompt fields', () {
      const params = NaiGenerationParams(
        prompt: 'classroom',
        model: NaiModel.v3,
        characterPrompts: [
          NaiCharacterPrompt(id: 'dddd0001', name: 'A', prompt: 'girl'),
        ],
      );
      final parameters =
          params.toApiPayload()['parameters'] as Map<String, dynamic>;
      expect(parameters.containsKey('characterPrompts'), isFalse);
      expect(parameters.containsKey('v4_prompt'), isFalse);
    });

    test('empty character list keeps legacy empty arrays', () {
      const params = NaiGenerationParams(
        prompt: 'solo',
        model: NaiModel.v5Full,
      );
      final parameters =
          params.toApiPayload()['parameters'] as Map<String, dynamic>;
      expect(parameters['characterPrompts'], isEmpty);
      expect(parameters['use_coords'], isFalse);
    });

    test('copyWith replaces characterPrompts list and ai position', () {
      const base = NaiGenerationParams(prompt: 'x');
      expect(base.characterPrompts, isEmpty);
      expect(base.characterAiPosition, isTrue);
      final updated = base.copyWith(
        characterPrompts: [
          NaiCharacterPrompt(id: 'eeee0001', name: 'A', prompt: 'girl'),
        ],
        characterAiPosition: false,
      );
      expect(updated.characterPrompts, hasLength(1));
      expect(updated.characterAiPosition, isFalse);
      expect(base.characterPrompts, isEmpty);
      expect(base.characterAiPosition, isTrue);
    });
  });

  group('Character Prompt Tools Tests', () {
    List<NaiCharacterPrompt> characters = [];

    setUp(() {
      characters = [
        NaiCharacterPrompt(
          id: 'aaaa0001',
          name: '银发少女',
          prompt: 'girl, silver hair',
        ),
      ];
    });

    void update(List<NaiCharacterPrompt> next) => characters = next;

    test('add tool appends character and syncs list', () async {
      final tool = NovelAiAddCharacterPromptTool(
        getCharacterPrompts: () => characters,
        updateCharacterPrompts: update,
      );
      final result = await tool.execute('t1', {
        'name': '黑发少年',
        'prompt': 'boy, black hair',
        'negative_prompt': 'lowres',
        'position_x': 0.2,
        'position_y': 0.4,
      });
      expect(result.isError, isFalse);
      expect(characters, hasLength(2));
      final added = characters[1];
      expect(added.name, '黑发少年');
      expect(added.negativePrompt, 'lowres');
      expect(added.useCustomPosition, isTrue);
      expect(added.positionX, closeTo(0.2, 0.001));
      expect(result.content, contains(added.id));
    });

    test('add tool rejects empty prompt', () async {
      final tool = NovelAiAddCharacterPromptTool(
        getCharacterPrompts: () => characters,
        updateCharacterPrompts: update,
      );
      final result = await tool.execute('t1', {'prompt': '  '});
      expect(result.isError, isTrue);
      expect(characters, hasLength(1));
    });

    test('add tool enforces the model character limit', () async {
      characters = [
        for (var i = 0; i < 6; i++)
          NaiCharacterPrompt(id: 'cap0000$i', name: 'C$i', prompt: 'girl'),
      ];
      final tool = NovelAiAddCharacterPromptTool(
        getCharacterPrompts: () => characters,
        updateCharacterPrompts: update,
        getCharacterLimit: () => 6,
      );
      final result = await tool.execute('t1', {'prompt': 'boy'});
      expect(result.isError, isTrue);
      expect(characters, hasLength(6));

      // V5 上限为 22
      final v5Characters = [
        for (var i = 0; i < 21; i++)
          NaiCharacterPrompt(id: 'big0000$i', name: 'C$i', prompt: 'girl'),
      ];
      characters = v5Characters;
      final v5Tool = NovelAiAddCharacterPromptTool(
        getCharacterPrompts: () => characters,
        updateCharacterPrompts: update,
        getCharacterLimit: () => 22,
      );
      final v5Result = await v5Tool.execute('t1', {'prompt': 'boy'});
      expect(v5Result.isError, isFalse);
      expect(characters, hasLength(22));
    });

    test('update tool modifies only provided fields', () async {
      final tool = NovelAiUpdateCharacterPromptTool(
        getCharacterPrompts: () => characters,
        updateCharacterPrompts: update,
      );
      final result = await tool.execute('t1', {
        'id': 'aaaa0001',
        'prompt': 'girl, blonde hair',
        'enabled': false,
      });
      expect(result.isError, isFalse);
      final updated = characters.single;
      expect(updated.prompt, 'girl, blonde hair');
      expect(updated.enabled, isFalse);
      expect(updated.name, '银发少女'); // 未传入字段保持不变
    });

    test('update tool can restore auto position and set coordinates', () async {
      final tool = NovelAiUpdateCharacterPromptTool(
        getCharacterPrompts: () => characters,
        updateCharacterPrompts: update,
      );
      var result = await tool.execute('t1', {
        'id': 'aaaa0001',
        'position_x': 0.8,
        'position_y': 0.1,
      });
      expect(result.isError, isFalse);
      expect(characters.single.useCustomPosition, isTrue);
      expect(characters.single.positionX, closeTo(0.8, 0.001));

      result = await tool.execute('t1', {
        'id': 'aaaa0001',
        'use_auto_position': true,
      });
      expect(result.isError, isFalse);
      expect(characters.single.useCustomPosition, isFalse);
    });

    test('update tool errors on unknown id', () async {
      final tool = NovelAiUpdateCharacterPromptTool(
        getCharacterPrompts: () => characters,
        updateCharacterPrompts: update,
      );
      final result = await tool.execute('t1', {'id': 'ffffffff'});
      expect(result.isError, isTrue);
    });

    test('remove tool deletes by id', () async {
      final tool = NovelAiRemoveCharacterPromptTool(
        getCharacterPrompts: () => characters,
        updateCharacterPrompts: update,
      );
      final result = await tool.execute('t1', {'id': 'aaaa0001'});
      expect(result.isError, isFalse);
      expect(characters, isEmpty);
    });

    test('remove tool errors on unknown id', () async {
      final tool = NovelAiRemoveCharacterPromptTool(
        getCharacterPrompts: () => characters,
        updateCharacterPrompts: update,
      );
      final result = await tool.execute('t1', {'id': 'nope'});
      expect(result.isError, isTrue);
      expect(characters, hasLength(1));
    });

    test('list tool reports characters and global position mode', () async {
      final tool = NovelAiListCharacterPromptsTool(
        getCharacterPrompts: () => characters,
        getAiPosition: () => false,
      );
      final result = await tool.execute('t1', {});
      expect(result.isError, isFalse);
      expect(result.content, contains('aaaa0001'));
      expect(result.content, contains('银发少女'));
      expect(result.content, contains('自定义定位'));
    });
  });

  group('Character Preset Tests', () {
    test('initialCharacterPrompt per model and gender', () {
      // V5 与 V4/V4.5 统一为标签开头
      expect(
        NaiModel.v5Full.initialCharacterPrompt(NaiCharacterGender.female),
        'girl, ',
      );
      expect(
        NaiModel.v5Curated.initialCharacterPrompt(NaiCharacterGender.male),
        'boy, ',
      );
      expect(
        NaiModel.v45Full.initialCharacterPrompt(NaiCharacterGender.female),
        'girl, ',
      );
      expect(
        NaiModel.v4Curated.initialCharacterPrompt(NaiCharacterGender.male),
        'boy, ',
      );
      expect(
        NaiModel.v5Full.initialCharacterPrompt(NaiCharacterGender.other),
        '',
      );

      // v3 不支持角色提示词
      for (final gender in NaiCharacterGender.values) {
        expect(NaiModel.v3.initialCharacterPrompt(gender), '');
        expect(NaiModel.v3Furry.initialCharacterPrompt(gender), '');
      }
    });

    test('NaiCharacterGender fromName parsing', () {
      expect(NaiCharacterGender.fromName('female'), NaiCharacterGender.female);
      expect(NaiCharacterGender.fromName('male'), NaiCharacterGender.male);
      expect(NaiCharacterGender.fromName('other'), NaiCharacterGender.other);
      expect(NaiCharacterGender.fromName('alien'), NaiCharacterGender.other);
      expect(NaiCharacterGender.fromName(null), NaiCharacterGender.other);
    });

    test('presetNegativePrompt matches Aaalice launcher default', () {
      expect(NaiCharacterPrompt.presetNegativePrompt, 'lowres, aliasing, ');
    });
  });
}
