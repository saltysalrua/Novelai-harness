import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:novelai_harness/data/models/novelai_models.dart';
import 'package:novelai_harness/data/repositories/novelai_repository.dart';
import 'package:novelai_harness/data/services/config_service.dart';
import 'package:novelai_harness/data/services/image_storage_directory_service.dart';
import 'package:novelai_harness/data/services/novelai_service.dart';
import 'package:novelai_harness/data/services/prompt_library_service.dart';
import 'package:novelai_harness/l10n/app_localizations.dart';
import 'package:novelai_harness/ui/features/settings/widgets/general_settings_tab.dart';
import 'package:novelai_harness/ui/features/studio/view_models/studio_view_model.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

class _FakeNovelAiService extends NovelAiService {
  @override
  Future<List<Uint8List>> generateImage({
    required String apiKey,
    required NaiGenerationParams params,
  }) async => [
    Uint8List.fromList(img.encodePng(img.Image(width: 2, height: 2))),
  ];
}

/// 配置与文件仍走真实链路，仅禁用账号网络查询和词库在线更新。
class _OfflineConfigService extends ConfigService {
  _OfflineConfigService(ImageStorageDirectoryService directories)
    : super(imageStorageDirectoryService: directories);

  @override
  Future<AppConfig> loadConfig() async => (await super.loadConfig()).copyWith(
    novelAiKey: '',
    enableTagDictionaryAutoUpdate: false,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late ImageStorageDirectoryService directories;
  late String defaultPath;

  setUp(() {
    SharedPreferences.setMockInitialValues({
      // 阻止 ConfigService 从开发机私有配置中导入凭证；所有生图均使用 Mock。
      'novelai_key': 'unused-test-key',
      'novelai_enable_tag_dictionary_auto_update': false,
    });
    temp = Directory.systemTemp.createTempSync('android_image_persistence_');
    directories = ImageStorageDirectoryService(
      isAndroid: true,
      documentsDirectory: () async => Directory(p.join(temp.path, 'documents')),
    );
    defaultPath = p.join(temp.path, 'documents', 'NovelAI_Output');
    PromptLibraryService.instance.setCustomStorageDirectory(
      p.join(temp.path, 'library'),
    );
  });

  tearDown(() {
    PromptLibraryService.instance.setCustomStorageDirectory(null);
    temp.deleteSync(recursive: true);
  });

  group('Android 存储目录修复', () {
    test('首次启动使用应用文档目录，而非系统临时缓存', () async {
      expect(await directories.resolve(''), defaultPath);
      expect(Directory(defaultPath).existsSync(), isTrue);
      expect(Directory(defaultPath).listSync(), isEmpty);
    });

    test('拒绝 SAF URI、空白与相对路径，自动回退应用目录', () async {
      for (final invalid in [
        'content://com.android.externalstorage.documents/tree/primary%3APictures',
        '   ',
        'Pictures/NovelAI',
      ]) {
        expect(await directories.resolve(invalid), defaultPath);
      }
    });

    test('存在但不可写成目录的旧配置自动修复，不改动原文件', () async {
      final blocked = File(p.join(temp.path, 'blocked'))
        ..writeAsStringSync('keep');
      expect(await directories.resolve(blocked.path), defaultPath);
      expect(blocked.readAsStringSync(), 'keep');
    });

    test('保留可读写的旧目录和历史，不残留读写探针', () async {
      final existing = Directory(p.join(temp.path, 'existing'))..createSync();
      final history = File(p.join(existing.path, 'image_history.json'))
        ..writeAsStringSync('[]');
      expect(await directories.resolve(existing.path), existing.path);
      expect(existing.listSync().map((entry) => entry.path), [history.path]);
      expect(history.readAsStringSync(), '[]');
      expect(Directory(defaultPath).existsSync(), isFalse);
    });

    test('应用目录也无法使用时显式失败，不能退成空串只存内存', () async {
      final blocked = File(p.join(temp.path, 'blocked'))
        ..writeAsStringSync('keep');
      final unavailable = ImageStorageDirectoryService(
        isAndroid: true,
        documentsDirectory: () async => Directory(blocked.path),
      );
      await expectLater(
        unavailable.resolve(''),
        throwsA(isA<FileSystemException>()),
      );
      final missingProvider = ImageStorageDirectoryService(
        isAndroid: true,
        documentsDirectory: () async => throw StateError('unavailable'),
      );
      await expectLater(missingProvider.resolve(''), throwsStateError);
    });

    test('桌面自定义目录保持原语义，不被安卓策略覆盖', () async {
      final desktop = ImageStorageDirectoryService(
        isAndroid: false,
        documentsDirectory: () async => throw StateError('must not run'),
      );
      expect(await desktop.resolve('custom/path'), 'custom/path');
      expect(await desktop.resolve(''), '');
    });

    test('ConfigService 修正旧配置并持久化，新实例读到同一个目录', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('novelai_save_dir', 'content://storage/tree/old');
      final config = await ConfigService(
        imageStorageDirectoryService: directories,
      ).loadConfig();
      expect(config.saveDirectory, defaultPath);
      expect(prefs.getString('novelai_save_dir'), defaultPath);
      final reloaded = await ConfigService(
        imageStorageDirectoryService: directories,
      ).loadConfig();
      expect(reloaded.saveDirectory, defaultPath);
    });

    test('运行时修改目录也先修正，再同步内存配置和磁盘配置', () async {
      final vm = StudioViewModel(
        configService: _OfflineConfigService(directories),
        sessionLogBaseDir: p.join(temp.path, 'sessions'),
      );
      try {
        await vm.updateConfig(const AppConfig(saveDirectory: 'content://bad'));
        expect(vm.config.saveDirectory, defaultPath);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('novelai_save_dir'), defaultPath);
        await vm.flushPendingSaves();
      } finally {
        vm.dispose();
      }
    });
  });

  for (final autoSave in [false, true]) {
    test('修正安卓旧路径后生成、重启恢复、懒加载原图（自动保存=$autoSave）', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('novelai_save_dir', 'content://storage/tree/old');
      final config = await _OfflineConfigService(directories).loadConfig();
      final repo = NovelAiRepository(service: _FakeNovelAiService());
      final generated = (await repo.generate(
        apiKey: 'mock-only',
        params: const NaiGenerationParams(prompt: 'test', seed: 42),
        saveDir: config.saveDirectory,
        autoSave: autoSave,
        imageSaveTemplate: '{date}/{seed}',
      )).single;
      expect(generated.originalFilePath, isNotNull);
      expect(File(generated.originalFilePath!).existsSync(), isTrue);
      expect(generated.isUnsaved, !autoSave);
      expect(
        File(p.join(defaultPath, 'image_history.json')).existsSync(),
        isTrue,
      );

      // 丢掉旧仓储/内存缓存：新 ViewModel 启动必须读配置和磁盘索引自行恢复。
      final vm = StudioViewModel(
        configService: _OfflineConfigService(directories),
        repository: NovelAiRepository(service: _FakeNovelAiService()),
        sessionLogBaseDir: p.join(temp.path, 'sessions'),
      );
      try {
        await vm.init();
        expect(vm.gallery, hasLength(1));
        final restored = vm.selectedImage!;
        expect(restored.id, generated.id);
        expect(restored.originalFilePath, generated.originalFilePath);
        expect(restored.isUnsaved, !autoSave);
        expect(await vm.ensureImageLoaded(restored), generated.bytes);
        if (!autoSave) {
          expect(await vm.saveCurrentImageToDisk(), isTrue);
          expect(vm.selectedImage!.isUnsaved, isFalse);
          expect(File(vm.selectedImage!.localFilePath!).existsSync(), isTrue);
        }
        await vm.flushPendingSaves();
      } finally {
        vm.dispose();
      }
    });
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets('设置页目录入口遵循平台存储能力（$platform）', (tester) async {
      final draft = GeneralSettingsDraft(AppConfig(saveDirectory: defaultPath));
      addTearDown(draft.dispose);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: GeneralSettingsTab(draft: draft)),
        ),
      );
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.controller == draft.saveDirController,
        ),
      );
      final isAndroid = platform == TargetPlatform.android;
      expect(field.readOnly, isAndroid);
      // 桌面「本地存储目录」与安卓「导出文件夹」各有一个选择按钮，互不叠加
      expect(find.text('选择'), findsOneWidget);
      if (isAndroid) {
        expect(find.textContaining('重启后保留'), findsOneWidget);
        expect(find.textContaining('卸载应用'), findsOneWidget);
        // 安卓自选 SAF 导出目录入口：未选择时展示默认图库提示，不出现清除按钮
        expect(find.text('导出文件夹'), findsOneWidget);
        expect(find.textContaining('未选择，默认写入系统图库'), findsOneWidget);
        expect(find.text('清除'), findsNothing);
      }
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant({platform}));
  }
}
