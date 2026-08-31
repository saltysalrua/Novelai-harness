import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/data/models/novelai_models.dart';
import 'package:novelai_harness/data/services/config_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NaiSeedMode & NaiSeedTiming Enums', () {
    test('NaiSeedMode fromId parses correctly', () {
      expect(NaiSeedMode.fromId('random'), equals(NaiSeedMode.random));
      expect(NaiSeedMode.fromId('increase'), equals(NaiSeedMode.increase));
      expect(NaiSeedMode.fromId('fixed'), equals(NaiSeedMode.fixed));
      expect(NaiSeedMode.fromId('unknown'), equals(NaiSeedMode.random));
      expect(NaiSeedMode.fromId(null), equals(NaiSeedMode.random));
    });

    test('NaiSeedTiming fromId parses correctly', () {
      expect(NaiSeedTiming.fromId('before'), equals(NaiSeedTiming.before));
      expect(NaiSeedTiming.fromId('after'), equals(NaiSeedTiming.after));
      expect(NaiSeedTiming.fromId('unknown'), equals(NaiSeedTiming.before));
      expect(NaiSeedTiming.fromId(null), equals(NaiSeedTiming.before));
    });
  });

  group('NaiGenerationParams Seed Serialization', () {
    test('default seedMode is random and seedTiming is before', () {
      const params = NaiGenerationParams(prompt: 'masterpiece');
      expect(params.seedMode, equals(NaiSeedMode.random));
      expect(params.seedTiming, equals(NaiSeedTiming.before));
    });

    test('copyWith updates seedMode and seedTiming', () {
      const params = NaiGenerationParams(prompt: 'masterpiece');
      final updated = params.copyWith(
        seed: 123456,
        seedMode: NaiSeedMode.increase,
        seedTiming: NaiSeedTiming.after,
      );
      expect(updated.seed, equals(123456));
      expect(updated.seedMode, equals(NaiSeedMode.increase));
      expect(updated.seedTiming, equals(NaiSeedTiming.after));
    });

    test('toJson and fromJson preserves seedMode and seedTiming', () {
      const params = NaiGenerationParams(
        prompt: '1girl',
        seed: 987654,
        seedMode: NaiSeedMode.fixed,
        seedTiming: NaiSeedTiming.after,
      );
      final json = params.toJson();
      expect(json['seedMode'], equals('fixed'));
      expect(json['seedTiming'], equals('after'));

      final restored = NaiGenerationParams.fromJson(json);
      expect(restored.seed, equals(987654));
      expect(restored.seedMode, equals(NaiSeedMode.fixed));
      expect(restored.seedTiming, equals(NaiSeedTiming.after));
    });
  });

  group('ConfigService Seed Persistence', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('save and load seed mode and timing', () async {
      final service = ConfigService();
      expect(await service.loadSeedMode(), equals(NaiSeedMode.random));
      expect(await service.loadSeedTiming(), equals(NaiSeedTiming.before));

      await service.saveSeedMode(NaiSeedMode.increase);
      await service.saveSeedTiming(NaiSeedTiming.after);

      expect(await service.loadSeedMode(), equals(NaiSeedMode.increase));
      expect(await service.loadSeedTiming(), equals(NaiSeedTiming.after));
    });
  });

  group('generateRandomSeed CSPRNG Tests', () {
    test(
      'generateRandomSeed produces distinct values within [0, 4294967295]',
      () {
        final seeds = List.generate(50, (_) => generateRandomSeed());
        for (final s in seeds) {
          expect(s, isNonNegative);
          expect(s, lessThanOrEqualTo(4294967295));
        }
        final uniqueCount = seeds.toSet().length;
        // 50 组独立随机数应该几乎全部唯一
        expect(uniqueCount, greaterThan(45));
      },
    );
  });
}
