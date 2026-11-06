import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/data/models/novelai_models.dart';

void main() {
  group('BannedWordSanitizer', () {
    test(
      'parses commas, newlines and Chinese separators without duplicates',
      () {
        expect(BannedWordSanitizer.parseList(' bad \nartist，Bad；child'), [
          'bad',
          'artist',
          'child',
        ]);
      },
    );

    test('latin terms match whole words and ignore case', () {
      expect(
        BannedWordSanitizer.strip(
          'masterpiece, Bad, artist, artist_name',
          'bad, art',
        ),
        'masterpiece, artist, artist_name',
      );
    });

    test('drops an emptied weight segment and keeps the rest', () {
      expect(
        BannedWordSanitizer.strip(
          'masterpiece, 0.8::banned artist::, 1girl',
          'banned artist',
        ),
        'masterpiece, 1girl',
      );
    });

    test('CJK terms match inside a longer tag', () {
      expect(BannedWordSanitizer.strip('可爱萝莉, 1girl', '萝莉'), '可爱, 1girl');
    });

    test('returns the original text when nothing matches', () {
      const original = '1girl,solo | 1boy';
      expect(BannedWordSanitizer.strip(original, 'landscape'), original);
      expect(BannedWordSanitizer.strip(original, '  \n '), original);
    });

    test('keeps prompt-mix separators after a removed chunk', () {
      expect(
        BannedWordSanitizer.strip('1girl | banned | 1boy', 'banned'),
        '1girl | 1boy',
      );
    });
  });

  group('NaiGenerationParams banned-word request filter', () {
    NaiGenerationParams sample({required bool enabled}) {
      return NaiGenerationParams(
        prompt: '1girl, banned',
        negativePrompt: 'blurry, banned',
        prefixPrompt: '0.7::banned::, masterpiece',
        suffixPrompt: 'banned, highres',
        qualityToggle: true,
        qualityPreset: 'Standard',
        ucPresetKey: 'None',
        model: NaiModel.v5Full,
        stripBannedWords: enabled,
        bannedWords: 'banned, masterpiece',
        characterPrompts: const [
          NaiCharacterPrompt(
            id: 'kept',
            name: 'kept',
            prompt: 'silver hair, banned',
            negativePrompt: 'hat, banned',
          ),
          NaiCharacterPrompt(id: 'dropped', name: 'dropped', prompt: 'banned'),
        ],
      );
    }

    test('off switch sends the stored prefix, suffix and other text', () {
      final params = sample(enabled: false);
      expect(params.prefixPrompt, contains('banned'));
      expect(params.finalPrompt, contains('0.7::banned::'));
      expect(params.finalPrompt, contains('banned, highres'));
      expect(params.effectivePrompt, contains('masterpiece'));
      expect(params.requestNegativePrompt, contains('banned'));
      final payload = params.toApiPayload();
      final characters = (payload['parameters']['characterPrompts'] as List)
          .cast<Map>();
      expect(characters, hasLength(2));
      expect(characters.first['prompt'], contains('banned'));
    });

    test(
      'on switch strips listed words from every text field in the request',
      () {
        final params = sample(enabled: true);
        expect(params.prefixPrompt, contains('banned'));
        expect(params.finalPrompt, isNot(contains('banned')));
        expect(params.finalPrompt, isNot(contains('masterpiece')));
        expect(params.finalPrompt, contains('1girl'));
        expect(params.finalPrompt, contains('highres'));
        expect(params.effectivePrompt, isNot(contains('banned')));
        expect(params.effectivePrompt, isNot(contains('masterpiece')));
        expect(params.requestNegativePrompt, isNot(contains('banned')));
        expect(params.requestNegativePrompt, contains('blurry'));

        final payload = params.toApiPayload();
        expect(payload['input'], isNot(contains('banned')));
        expect(
          payload['parameters']['negative_prompt'],
          isNot(contains('banned')),
        );
        final characters = (payload['parameters']['characterPrompts'] as List)
            .cast<Map>();
        expect(characters, hasLength(1));
        expect(characters.single['prompt'], 'silver hair');
        expect(characters.single['uc'], 'hat');
      },
    );

    test('empty word list does not change the outgoing prompt', () {
      const params = NaiGenerationParams(
        prompt: '1girl, solo',
        prefixPrompt: 'masterpiece',
        stripBannedWords: true,
      );
      expect(params.finalPrompt, 'masterpiece, 1girl, solo');
    });

    test('persists the switch and word list', () {
      final params = sample(enabled: true);
      final restored = NaiGenerationParams.fromJson(params.toJson());
      expect(restored.stripBannedWords, isTrue);
      expect(restored.bannedWords, 'banned, masterpiece');
      expect(restored.finalPrompt, params.finalPrompt);
    });
  });
}
