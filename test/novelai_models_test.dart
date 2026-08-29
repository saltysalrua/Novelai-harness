import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/data/models/novelai_models.dart';

void main() {
  group('NovelAI Models & Payload Tests', () {
    test('isOpusFree returns true for standard portrait with <=28 steps', () {
      const params = NaiGenerationParams(
        prompt: '1girl, silver hair',
        width: 832,
        height: 1216,
        steps: 28,
        nSamples: 1,
      );
      expect(params.isOpusFree, isTrue);
    });

    test('isOpusFree returns false for >28 steps', () {
      const params = NaiGenerationParams(
        prompt: '1girl, silver hair',
        width: 832,
        height: 1216,
        steps: 35,
        nSamples: 1,
      );
      expect(params.isOpusFree, isFalse);
    });

    test('isOpusFree returns false for large wallpaper', () {
      const params = NaiGenerationParams(
        prompt: 'landscape',
        width: 1920,
        height: 1088, // 1920*1088 = 2088960 > 1048576
        steps: 28,
        nSamples: 1,
      );
      expect(params.isOpusFree, isFalse);
    });

    test('finalPrompt joins prefix, core prompt and suffix correctly', () {
      const params = NaiGenerationParams(
        prompt: '1girl, solo',
        prefixPrompt: 'masterpiece, anime',
        suffixPrompt: 'high resolution',
      );
      expect(params.finalPrompt, equals('masterpiece, anime, 1girl, solo, high resolution'));
    });

    test('toApiPayload structures V5 request correctly with v4_prompt', () {
      const params = NaiGenerationParams(
        prompt: '1girl in rain',
        negativePrompt: 'lowres, bad quality',
        model: NaiModel.v5Full,
        width: 832,
        height: 1216,
      );

      final payload = params.toApiPayload();
      expect(payload['model'], equals('nai-diffusion-5-full'));
      expect(payload['action'], equals('generate'));
      expect(payload['parameters']['v4_prompt'], isNotNull);
      expect(
        payload['parameters']['v4_prompt']['caption']['base_caption'],
        equals('1girl in rain'),
      );
    });

    test('NaiAccountInfo parses json properly', () {
      final json = {
        'subscription': {
          'tier': 3,
          'active': true,
          'expiresAt': 1780000000,
          'usage': {
            'percent': 95.5,
            'timeUntilNextPercent': 45,
          },
          'trainingStepsLeft': {
            'fixedTrainingStepsLeft': 10000,
            'purchasedTrainingSteps': 500,
          },
        },
        'priority': {
          'taskPriority': 10,
          'nextRefillAt': 1780000000,
        }
      };

      final info = NaiAccountInfo.fromJson(json);
      expect(info.tierName, equals('Opus'));
      expect(info.active, isTrue);
      expect(info.staminaPercent, equals(95.5));
      expect(info.timeUntilNextPercent, equals(45));
      expect(info.totalAnlas, equals(10500));
      expect(info.fixedAnlas, equals(10000));
    });
  });
}
