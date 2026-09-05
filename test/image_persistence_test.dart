import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/data/models/novelai_models.dart';
import 'package:novelai_harness/data/repositories/novelai_repository.dart';
import 'package:novelai_harness/data/services/config_service.dart';
import 'package:novelai_harness/l10n/app_localizations.dart';
import 'package:novelai_harness/ui/features/settings/widgets/general_settings_tab.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NaiGenerationParams & NaiGeneratedImage Serialization', () {
    test('NaiGenerationParams toJson and fromJson round-trip', () {
      final original = NaiGenerationParams(
        prompt: '1girl, silver hair, glowing eyes',
        negativePrompt: 'low quality, worst quality',
        model: NaiModel.v5Full,
        width: 1024,
        height: 1024,
        steps: 28,
        scale: 7.0,
        cfgRescale: 0.2,
        sampler: NaiSampler.kDpmpp2m,
        noiseSchedule: NoiseSchedule.exponential,
        seed: 42,
        nSamples: 1,
        qualityToggle: true,
        qualityPreset: 'Standard',
        ucPresetKey: 'Heavy',
        transparentBg: false,
        prefixPrompt: 'masterpiece',
        suffixPrompt: 'highres',
        applyFixedPrompts: true,
        characterPrompts: [
          NaiCharacterPrompt(
            id: 'c1',
            name: 'Alice',
            prompt: 'blonde hair',
            negativePrompt: 'bad hands',
            enabled: true,
            useCustomPosition: true,
            positionX: 0.3,
            positionY: 0.4,
          ),
        ],
        characterAiPosition: false,
      );

      final json = original.toJson();
      final restored = NaiGenerationParams.fromJson(json);

      expect(restored.prompt, equals(original.prompt));
      expect(restored.negativePrompt, equals(original.negativePrompt));
      expect(restored.model, equals(original.model));
      expect(restored.width, equals(original.width));
      expect(restored.height, equals(original.height));
      expect(restored.steps, equals(original.steps));
      expect(restored.scale, equals(original.scale));
      expect(restored.cfgRescale, equals(original.cfgRescale));
      expect(restored.sampler, equals(original.sampler));
      expect(restored.noiseSchedule, equals(original.noiseSchedule));
      expect(restored.seed, equals(original.seed));
      expect(restored.nSamples, equals(original.nSamples));
      expect(restored.characterPrompts.length, equals(1));
      expect(restored.characterPrompts.first.name, equals('Alice'));
      expect(restored.characterPrompts.first.positionX, equals(0.3));
      expect(restored.characterAiPosition, isFalse);
    });

    test('NaiGeneratedImage toJson and fromJson round-trip', () {
      const params = NaiGenerationParams(prompt: 'test prompt');
      final now = DateTime(2026, 8, 30, 12, 0, 0);
      final original = NaiGeneratedImage(
        id: 'img_123',
        bytes: Uint8List.fromList([1, 2, 3, 4]),
        localFilePath: '/path/to/img.png',
        params: params,
        createdAt: now,
        seed: 999,
        isOpusFree: true,
      );

      final json = original.toJson();
      final restored = NaiGeneratedImage.fromJson(
        json,
        bytes: Uint8List.fromList([1, 2, 3, 4]),
      );

      expect(restored.id, equals('img_123'));
      expect(restored.localFilePath, equals('/path/to/img.png'));
      expect(restored.seed, equals(999));
      expect(restored.isOpusFree, isTrue);
      expect(restored.params.prompt, equals('test prompt'));
      expect(restored.bytes, equals([1, 2, 3, 4]));
      expect(restored.createdAt, equals(now));
    });
  });

  group('ConfigService Image Persistence Settings', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test(
      'Default config has image persistence enabled and max 50 images',
      () async {
        final configService = ConfigService();
        final config = await configService.loadConfig();

        expect(config.enableImagePersistence, isTrue);
        expect(config.maxPersistentImages, equals(50));
      },
    );

    test('saveConfig and loadConfig correctly persist new values', () async {
      final configService = ConfigService();
      var config = await configService.loadConfig();

      config = config.copyWith(
        enableImagePersistence: false,
        maxPersistentImages: 100,
      );
      await configService.saveConfig(config);

      final reloaded = await configService.loadConfig();
      expect(reloaded.enableImagePersistence, isFalse);
      expect(reloaded.maxPersistentImages, equals(100));
    });
  });

  group('NovelAiRepository Image Persistence Operations', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('nai_repo_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test(
      'savePersistedHistory and loadPersistedHistory round-trip with file reading',
      () async {
        final repo = NovelAiRepository();
        const params = NaiGenerationParams(prompt: 'persisted test');

        final imgPath1 = p.join(tempDir.path, 'img1.png');
        final imgPath2 = p.join(tempDir.path, 'img2.png');
        File(imgPath1).writeAsBytesSync([10, 20, 30]);
        File(imgPath2).writeAsBytesSync([40, 50, 60]);

        final img1 = NaiGeneratedImage(
          id: 'img1',
          bytes: Uint8List.fromList([10, 20, 30]),
          localFilePath: imgPath1,
          params: params,
          createdAt: DateTime.now(),
          seed: 100,
          isOpusFree: true,
        );
        final img2 = NaiGeneratedImage(
          id: 'img2',
          bytes: Uint8List.fromList([40, 50, 60]),
          localFilePath: imgPath2,
          params: params,
          createdAt: DateTime.now(),
          seed: 200,
          isOpusFree: true,
        );

        final repo2 = NovelAiRepository();
        await repo2.loadPersistedHistory(saveDir: tempDir.path);
        expect(repo2.history.isEmpty, isTrue);

        final historyFile = File(p.join(tempDir.path, 'image_history.json'));
        historyFile.writeAsStringSync(
          jsonEncode([img2.toJson(), img1.toJson()]),
        );

        final loaded = await repo.loadPersistedHistory(
          saveDir: tempDir.path,
          maxImages: 50,
        );

        expect(loaded.length, equals(2));
        expect(loaded[0].id, equals('img2'));
        expect(loaded[0].bytes.isEmpty, isTrue);
        final bytes2 = await repo.loadHistoryImageBytes(loaded[0]);
        expect(bytes2, equals([40, 50, 60]));

        expect(loaded[1].id, equals('img1'));
        expect(loaded[1].bytes.isEmpty, isTrue);
        final bytes1 = await repo.loadHistoryImageBytes(loaded[1]);
        expect(bytes1, equals([10, 20, 30]));
      },
    );

    test(
      'loadPersistedHistory skips missing local files without throwing',
      () async {
        final repo = NovelAiRepository();
        const params = NaiGenerationParams(prompt: 'persisted test');

        final imgPathExist = p.join(tempDir.path, 'exist.png');
        final imgPathMissing = p.join(tempDir.path, 'missing.png');
        File(imgPathExist).writeAsBytesSync([10, 20, 30]);

        final imgExist = NaiGeneratedImage(
          id: 'img_exist',
          bytes: Uint8List.fromList([10, 20, 30]),
          localFilePath: imgPathExist,
          params: params,
          createdAt: DateTime.now(),
          seed: 100,
          isOpusFree: true,
        );
        final imgMissing = NaiGeneratedImage(
          id: 'img_missing',
          bytes: Uint8List.fromList([0]),
          localFilePath: imgPathMissing,
          params: params,
          createdAt: DateTime.now(),
          seed: 200,
          isOpusFree: true,
        );

        final historyFile = File(p.join(tempDir.path, 'image_history.json'));
        historyFile.writeAsStringSync(
          jsonEncode([imgExist.toJson(), imgMissing.toJson()]),
        );

        final loaded = await repo.loadPersistedHistory(saveDir: tempDir.path);
        expect(loaded.length, equals(1));
        expect(loaded.first.id, equals('img_exist'));
      },
    );

    test('savePersistedHistory trims history to maxImages limit', () async {
      final repo = NovelAiRepository();
      const params = NaiGenerationParams(prompt: 'trim test');

      final historyFile = File(p.join(tempDir.path, 'image_history.json'));

      final imgPaths = List.generate(5, (i) {
        final path = p.join(tempDir.path, 'img_.png');
        File(path).writeAsBytesSync([i]);
        return path;
      });

      final images = List.generate(5, (i) {
        return NaiGeneratedImage(
          id: 'img_$i',
          bytes: Uint8List.fromList([i]),
          localFilePath: imgPaths[i],
          params: params,
          createdAt: DateTime.now(),
          seed: i,
          isOpusFree: true,
        );
      });

      historyFile.writeAsStringSync(
        jsonEncode(images.map((img) => img.toJson()).toList()),
      );
      await repo.loadPersistedHistory(saveDir: tempDir.path, maxImages: 3);

      expect(repo.history.length, equals(3));
      expect(repo.history[0].id, equals('img_0'));
      expect(repo.history[2].id, equals('img_2'));

      await repo.savePersistedHistory(saveDir: tempDir.path, maxImages: 2);
      expect(repo.history.length, equals(2));

      final savedJson = jsonDecode(historyFile.readAsStringSync()) as List;
      expect(savedJson.length, equals(2));
    });

    test(
      'deleteImage removes image from history, deletes file, and updates persistence',
      () async {
        final repo = NovelAiRepository();
        const params = NaiGenerationParams(prompt: 'delete test');

        final imgPath1 = p.join(tempDir.path, 'img1.png');
        final imgPath2 = p.join(tempDir.path, 'img2.png');
        final file1 = File(imgPath1)..writeAsBytesSync([10, 20, 30]);
        final file2 = File(imgPath2)..writeAsBytesSync([40, 50, 60]);

        final img1 = NaiGeneratedImage(
          id: 'img1',
          bytes: Uint8List.fromList([10, 20, 30]),
          localFilePath: imgPath1,
          params: params,
          createdAt: DateTime.now(),
          seed: 100,
          isOpusFree: true,
        );
        final img2 = NaiGeneratedImage(
          id: 'img2',
          bytes: Uint8List.fromList([40, 50, 60]),
          localFilePath: imgPath2,
          params: params,
          createdAt: DateTime.now(),
          seed: 200,
          isOpusFree: true,
        );

        repo.addImageForTesting(img1);
        repo.addImageForTesting(img2);
        expect(repo.history.length, equals(2));

        await repo.savePersistedHistory(saveDir: tempDir.path);
        final historyFile = File(p.join(tempDir.path, 'image_history.json'));
        expect(historyFile.existsSync(), isTrue);

        final deleted = await repo.deleteImage(
          imageId: 'img1',
          saveDir: tempDir.path,
        );
        expect(deleted, isTrue);
        expect(repo.history.length, equals(1));
        expect(repo.history.first.id, equals('img2'));
        expect(file1.existsSync(), isFalse);
        expect(file2.existsSync(), isTrue);

        final persistedList =
            jsonDecode(historyFile.readAsStringSync()) as List;
        expect(persistedList.length, equals(1));
        expect(persistedList.first['id'], equals('img2'));

        final deletedNonExistent = await repo.deleteImage(
          imageId: 'non_existent',
          saveDir: tempDir.path,
        );
        expect(deletedNonExistent, isFalse);
      },
    );

    test(
      'clearHistory removes image_history.json file when saveDir provided',
      () {
        final repo = NovelAiRepository();
        final historyFile = File(p.join(tempDir.path, 'image_history.json'));
        historyFile.writeAsStringSync('[]');
        expect(historyFile.existsSync(), isTrue);

        repo.clearHistory(saveDir: tempDir.path);
        expect(historyFile.existsSync(), isFalse);
      },
    );
  });

  group('GeneralSettingsTab & SettingsDialog UI Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('GeneralSettingsTab renders persistence switch and dropdown', (
      tester,
    ) async {
      // 设置页新增「主题模式」分组后页面更长，放大测试表面避免
      // DropdownButton 菜单超出 600px 默认视口 (menuLimits 断言崩溃)
      await tester.binding.setSurfaceSize(const Size(900, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final draft = GeneralSettingsDraft(
        const AppConfig(enableImagePersistence: true, maxPersistentImages: 50),
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: GeneralSettingsTab(draft: draft),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('图片历史持久化'), findsOneWidget);
      expect(find.text('可持久化图像上限'), findsOneWidget);
      expect(find.text('50 张'), findsOneWidget);

      await tester.tap(find.text('50 张'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('100 张').last);
      await tester.pumpAndSettle();

      expect(draft.maxPersistentImages, equals(100));

      draft.enableImagePersistence = false;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: GeneralSettingsTab(draft: draft),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('可持久化图像上限'), findsNothing);
    });

    testWidgets(
      'GeneralSettingsDraft and SettingsDialog save persistence settings',
      (tester) async {
        final config = const AppConfig(
          enableImagePersistence: true,
          maxPersistentImages: 50,
        );
        final draft = GeneralSettingsDraft(config);
        expect(draft.enableImagePersistence, isTrue);
        expect(draft.maxPersistentImages, equals(50));

        draft.enableImagePersistence = false;
        draft.maxPersistentImages = 200;

        final updated = config.copyWith(
          enableImagePersistence: draft.enableImagePersistence,
          maxPersistentImages: draft.maxPersistentImages,
        );

        expect(updated.enableImagePersistence, isFalse);
        expect(updated.maxPersistentImages, equals(200));
      },
    );
  });
}
