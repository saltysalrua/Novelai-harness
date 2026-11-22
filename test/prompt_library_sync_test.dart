import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:novelai_harness/data/models/prompt_library_models.dart';
import 'package:novelai_harness/data/models/prompt_library_sync_models.dart';
import 'package:novelai_harness/data/services/config_service.dart';
import 'package:novelai_harness/data/services/prompt_library_service.dart';
import 'package:novelai_harness/data/services/prompt_library_sync_service.dart';
import 'package:novelai_harness/l10n/app_localizations.dart';
import 'package:novelai_harness/ui/features/studio/view_models/studio_view_model.dart';
import 'package:novelai_harness/ui/features/studio/widgets/prompt_library_sync_dialog.dart';
import 'package:novelai_harness/ui/features/studio/widgets/prompt_library_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 模拟 Cloudflare Worker + D1 内存服务端，用于多端同步端到端测试
class _FakeCloudflareSyncServer {
  _FakeCloudflareSyncServer({required this.expectedToken});

  final String expectedToken;
  int revision = 0;
  final Map<String, Map<String, Map<String, dynamic>>> entriesByNs = {};
  final Map<String, ({Uint8List bytes, String mime, String ext})> images = {};

  int imageUploadCount = 0;
  int imageDownloadCount = 0;

  late final MockClient client = MockClient(_handle);

  http.Response _jsonResponse(Object data, {int status = 200}) {
    return http.Response.bytes(
      utf8.encode(jsonEncode(data)),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );
  }

  Future<http.Response> _handle(http.Request req) async {
    final auth = req.headers['Authorization'] ?? '';
    if (auth != 'Bearer $expectedToken') {
      return _jsonResponse({'ok': false, 'error': '同步密钥验证失败'}, status: 401);
    }

    final path = req.url.path;
    final ns = req.url.queryParameters['namespace'] ?? 'default';

    if (req.method == 'GET' && path == '/api/health') {
      final nsMap = entriesByNs[ns] ?? const {};
      final active = nsMap.values.where((e) => e['deletedAt'] == null).length;
      final tombstones = nsMap.values
          .where((e) => e['deletedAt'] != null)
          .length;
      final imgBytes = images.values.fold<int>(
        0,
        (sum, item) => sum + item.bytes.length,
      );
      return _jsonResponse({
        'ok': true,
        'namespace': ns,
        'revision': revision,
        'activeEntries': active,
        'tombstoneEntries': tombstones,
        'imageCount': images.length,
        'imageBytes': imgBytes,
        'serverTime': DateTime.now().toUtc().toIso8601String(),
      });
    }

    if (req.method == 'GET' && path == '/api/sync') {
      final nsMap = entriesByNs[ns] ?? const {};
      return _jsonResponse({
        'ok': true,
        'namespace': ns,
        'revision': revision,
        'entries': nsMap.values.toList(),
        'serverTime': DateTime.now().toUtc().toIso8601String(),
      });
    }

    if (req.method == 'POST' && path == '/api/sync/push') {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      final bodyNs = body['namespace'] as String? ?? 'default';
      final mode = body['mode'] as String? ?? 'merge';
      final incoming = (body['entries'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final nsMap = entriesByNs.putIfAbsent(bodyNs, () => {});
      revision++;
      final nowIso = DateTime.now().toUtc().toIso8601String();

      if (mode == 'replace') {
        final incomingIds = incoming
            .where((e) => e['deletedAt'] == null)
            .map((e) => e['id'] as String)
            .toSet();
        for (final key in nsMap.keys.toList()) {
          if (!incomingIds.contains(key)) {
            nsMap[key] = {
              ...nsMap[key]!,
              'deletedAt': nowIso,
              'updatedAt': nowIso,
              'previewHash': null,
              'previewExt': null,
              'revision': revision,
            };
          }
        }
        for (final item in incoming) {
          nsMap[item['id'] as String] = {...item, 'revision': revision};
        }
      } else {
        for (final item in incoming) {
          final id = item['id'] as String;
          nsMap[id] = {...item, 'revision': revision};
        }
      }

      return _jsonResponse({
        'ok': true,
        'namespace': bodyNs,
        'mode': mode,
        'revision': revision,
        'appliedCount': incoming.length,
        'serverTime': nowIso,
      });
    }

    if (req.method == 'POST' && path == '/api/images/check') {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      final hashes = (body['hashes'] as List<dynamic>)
          .map((e) => e.toString())
          .toList();
      final existing = <String>[];
      final missing = <String>[];
      for (final h in hashes) {
        if (images.containsKey(h)) {
          existing.add(h);
        } else {
          missing.add(h);
        }
      }
      return _jsonResponse({'ok': true, 'existing': existing, 'missing': missing});
    }

    final imgMatch = RegExp(r'^/api/images/([a-f0-9]{64})$').firstMatch(path);
    if (imgMatch != null) {
      final hash = imgMatch.group(1)!;
      if (req.method == 'PUT') {
        final bytes = req.bodyBytes;
        final actual = sha256.convert(bytes).toString();
        if (actual != hash) {
          return _jsonResponse({'ok': false, 'error': 'SHA-256 mismatch'}, status: 400);
        }
        images[hash] = (
          bytes: bytes,
          mime: req.headers['Content-Type'] ?? 'image/png',
          ext: req.headers['X-Image-Ext'] ?? 'png',
        );
        imageUploadCount++;
        return _jsonResponse({'ok': true, 'hash': hash, 'deduplicated': false});
      }
      if (req.method == 'GET') {
        final img = images[hash];
        if (img == null) {
          return _jsonResponse({'ok': false, 'error': 'Not found'}, status: 404);
        }
        imageDownloadCount++;
        return http.Response.bytes(
          img.bytes,
          200,
          headers: {'Content-Type': img.mime},
        );
      }
    }

    return _jsonResponse({'ok': false, 'error': 'Not found'}, status: 404);
  }
}

Uint8List _samplePngBytes(int marker) {
  return Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, marker,
  ]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PromptLibrarySyncConfig & ConfigService Persistence', () {
    test('resolveApiUri normalizes scheme and trailing slashes', () {
      const cfg = PromptLibrarySyncConfig(
        endpoint: 'sync.example.workers.dev/',
        token: 'abc',
        namespace: ' ',
      );
      expect(cfg.normalizedNamespace, 'default');
      expect(
        cfg.resolveApiUri('/api/health', {'namespace': 'default'}).toString(),
        'https://sync.example.workers.dev/api/health?namespace=default',
      );
    });

    test('ConfigService persists prompt sync settings across reload', () async {
      SharedPreferences.setMockInitialValues({});
      final service = ConfigService();
      await service.saveConfig(
        const AppConfig(
          promptSyncEndpoint: 'https://my-worker.workers.dev',
          promptSyncToken: 'my-sync-secret',
          promptSyncNamespace: 'anime-v5',
        ),
      );

      final loaded = await service.loadConfig();
      expect(loaded.promptSyncEndpoint, 'https://my-worker.workers.dev');
      expect(loaded.promptSyncToken, 'my-sync-secret');
      expect(loaded.promptSyncNamespace, 'anime-v5');
    });
  });

  group('planPromptLibraryMerge conflict & tombstone rules', () {
    test('merges additions, newer updates, and tombstones accurately', () {
      final t1 = DateTime.utc(2026, 11, 18, 10, 0, 0);
      final t2 = DateTime.utc(2026, 11, 18, 10, 5, 0);
      final t3 = DateTime.utc(2026, 11, 18, 10, 10, 0);

      final localEntries = [
        // 1. Local only -> push
        PromptComboEntry(
          id: 'local_only',
          title: 'Local Only',
          category: '风格',
          prompt: '',
          prefixPrompt: 'artist:local',
          suffixPrompt: 'very aesthetic',
          negativePrompt: 'lowres style',
          createdAt: t1,
          updatedAt: t1,
        ),
        // 2. Local newer than remote -> push
        PromptComboEntry(
          id: 'both_local_newer',
          title: 'Local Newer',
          category: '风格',
          prompt: 'new local',
          createdAt: t1,
          updatedAt: t3,
        ),
        // 3. Remote newer than local -> pull
        PromptComboEntry(
          id: 'both_remote_newer',
          title: 'Local Older',
          category: '风格',
          prompt: 'old local',
          createdAt: t1,
          updatedAt: t1,
        ),
        // 4. Remote deleted newer than local active -> delete locally
        PromptComboEntry(
          id: 'deleted_on_remote',
          title: 'To Delete Locally',
          category: '风格',
          prompt: 'will die',
          createdAt: t1,
          updatedAt: t1,
        ),
      ];

      final localTombstones = <String, DateTime>{
        // 5. Local deleted newer than remote active -> push tombstone
        'deleted_locally': t3,
      };

      final remoteRecords = [
        RemotePromptEntryRecord(
          id: 'remote_only',
          title: 'Remote Only',
          category: '角色',
          prompt: '1girl',
          negativePrompt: 'lowres',
          createdAt: t1,
          updatedAt: t1,
        ),
        RemotePromptEntryRecord(
          id: 'both_local_newer',
          title: 'Remote Older',
          category: '风格',
          prompt: 'old remote',
          createdAt: t1,
          updatedAt: t2,
        ),
        RemotePromptEntryRecord(
          id: 'both_remote_newer',
          title: 'Remote Newer',
          category: '风格',
          prompt: 'new remote',
          createdAt: t1,
          updatedAt: t2,
        ),
        RemotePromptEntryRecord.tombstone(
          id: 'deleted_on_remote',
          deletedAt: t2,
        ),
        RemotePromptEntryRecord(
          id: 'deleted_locally',
          title: 'Still On Remote',
          category: '风格',
          prompt: 'old',
          createdAt: t1,
          updatedAt: t2,
        ),
      ];

      final plan = planPromptLibraryMerge(
        localEntries: localEntries,
        localImageHashes: const {},
        localTombstones: localTombstones,
        remoteRecords: remoteRecords,
      );

      expect(
        plan.toPush.map((e) => e.id).toSet(),
        equals({'local_only', 'both_local_newer', 'deleted_locally'}),
      );
      expect(
        plan.pulledActive.map((e) => e.id).toSet(),
        equals({'remote_only', 'both_remote_newer'}),
      );
      expect(plan.deletedLocalIds, equals({'deleted_on_remote'}));
      expect(plan.deletedRemoteCount, 1);
      expect(
        plan.nextTombstones.keys.toSet(),
        equals({'deleted_on_remote', 'deleted_locally'}),
      );

      // 校验风格条目的 prefixPrompt / suffixPrompt / negativePrompt 经远端协议往返无损
      final pushedStyle = plan.toPush.firstWhere((e) => e.id == 'local_only');
      final roundTripped = RemotePromptEntryRecord.fromJson(
        pushedStyle.toJson(),
      ).toLocalEntry();
      expect(roundTripped.prefixPrompt, 'artist:local');
      expect(roundTripped.suffixPrompt, 'very aesthetic');
      expect(roundTripped.negativePrompt, 'lowres style');
    });
  });

  group('PromptLibrarySyncService End-to-End Two-Device Sync', () {
    late Directory dirA;
    late Directory dirB;
    late PromptLibraryService libA;
    late PromptLibraryService libB;
    late _FakeCloudflareSyncServer server;
    late PromptLibrarySyncService syncA;
    late PromptLibrarySyncService syncB;
    const syncConfig = PromptLibrarySyncConfig(
      endpoint: 'https://sync.example.com',
      token: 'unit-test-sync-token-value',
      namespace: 'default',
    );

    setUp(() {
      dirA = Directory.systemTemp.createTempSync('sync_dev_a_');
      dirB = Directory.systemTemp.createTempSync('sync_dev_b_');
      libA = PromptLibraryService.instance;
      // Note: PromptLibraryService is a singleton in production; test sync
      // across two independent directories by swapping or using test helper.
      // Wait: PromptLibraryService() returns the singleton instance, so let's
      // test two devices cleanly by switching dirA / dirB or verifying each step!
      libA.setCustomStorageDirectory(dirA.path);
      libB = libA;
      server = _FakeCloudflareSyncServer(
        expectedToken: 'unit-test-sync-token-value',
      );
      syncA = PromptLibrarySyncService(
        libraryService: libA,
        httpClient: server.client,
      );
      syncB = PromptLibrarySyncService(
        libraryService: libB,
        httpClient: server.client,
      );
    });

    tearDown(() {
      try {
        dirA.deleteSync(recursive: true);
      } catch (_) {}
      try {
        dirB.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('testConnection rejects wrong token and returns stats on valid token',
        () async {
      await expectLater(
        () => syncA.testConnection(
          const PromptLibrarySyncConfig(
            endpoint: 'https://sync.example.com',
            token: 'wrong-token',
          ),
        ),
        throwsA(isA<PromptLibrarySyncException>()),
      );

      final health = await syncA.testConnection(syncConfig);
      expect(health.namespace, 'default');
      expect(health.activeEntries, 0);
    });

    test(
      'syncs entries + deduplicated preview images, propagates edits & tombstones, and prunes orphaned files',
      () async {
        // Device A creates entry with preview image
        final pngA = _samplePngBytes(42);
        final previewPathA = await libA.savePreviewImageBytes(pngA);
        final t1 = DateTime.now().toUtc().subtract(const Duration(minutes: 10));
        await libA.addEntry(
          PromptComboEntry(
            id: 'combo_1',
            title: '初音未来',
            category: '角色',
            prompt: '1girl, hatsune miku',
            negativePrompt: 'lowres',
            previewImagePath: previewPathA,
            createdAt: t1,
            updatedAt: t1,
            tags: const ['vocaloid'],
          ),
        );

        // Device A pushes to cloud
        final resA1 = await syncA.sync(syncConfig);
        expect(resA1.pushedEntries, 1);
        expect(resA1.uploadedImages, 1);
        expect(server.imageUploadCount, 1);

        // Second sync on Device A must NOT re-upload the image or entry
        final resA2 = await syncA.sync(syncConfig);
        expect(resA2.hasChanges, isFalse);
        expect(server.imageUploadCount, 1);

        // Switch to Device B storage directory
        libB.setCustomStorageDirectory(dirB.path);
        expect(await libB.loadEntries(), isEmpty);

        // Device B pulls from cloud
        final resB1 = await syncB.sync(syncConfig);
        expect(resB1.pulledEntries, 1);
        expect(resB1.downloadedImages, 1);
        expect(server.imageDownloadCount, 1);

        final entriesB = await libB.loadEntries();
        expect(entriesB.length, 1);
        expect(entriesB.first.title, '初音未来');
        expect(entriesB.first.negativePrompt, 'lowres');
        expect(entriesB.first.previewImagePath, isNotNull);
        final localImgB = File(entriesB.first.previewImagePath!);
        expect(localImgB.existsSync(), isTrue);
        expect(await localImgB.readAsBytes(), pngA);

        // Device B deletes combo_1 (creates tombstone) and adds combo_2
        await libB.deleteEntry('combo_1');
        expect(localImgB.existsSync(), isFalse);
        final t2 = DateTime.now().toUtc().subtract(const Duration(minutes: 5));
        await libB.addEntry(
          PromptComboEntry(
            id: 'combo_2',
            title: '赛博霓虹',
            category: '风格',
            prompt: 'cyberpunk, neon lights',
            createdAt: t2,
            updatedAt: t2,
          ),
        );

        // Device B syncs (Wait: tombstone timestamp is DateTime.now().toUtc(),
        // which is newer than t1)
        final resB2 = await syncB.sync(syncConfig);
        expect(resB2.pushedEntries, 1);
        expect(resB2.deletedRemote, 1);

        // Switch back to Device A and sync -> combo_1 should be deleted locally & combo_2 pulled!
        libA.setCustomStorageDirectory(dirA.path);
        final resA3 = await syncA.sync(syncConfig);
        expect(resA3.deletedLocal, 1);
        expect(resA3.pulledEntries, 1);

        final entriesA = await libA.loadEntries();
        expect(entriesA.length, 1);
        expect(entriesA.first.id, 'combo_2');
        // Orphaned preview image on Device A must be cleaned up!
        expect(File(previewPathA!).existsSync(), isFalse);
      },
    );

    test('forcePush and forcePull overwrite cleanly', () async {
      libA.setCustomStorageDirectory(dirA.path);
      final t1 = DateTime.utc(2026, 11, 18, 9, 0, 0);
      await libA.saveEntries([
        PromptComboEntry(
          id: 'keep_1',
          title: '保留项',
          category: '风格',
          prompt: 'keep me',
          createdAt: t1,
          updatedAt: t1,
        ),
        PromptComboEntry(
          id: 'drop_1',
          title: '将被覆盖删除',
          category: '风格',
          prompt: 'drop me',
          createdAt: t1,
          updatedAt: t1,
        ),
      ]);
      await syncA.sync(syncConfig, mode: PromptLibrarySyncMode.forcePush);

      // Now remove drop_1 directly via saveEntries and forcePush
      await libA.saveEntries([
        PromptComboEntry(
          id: 'keep_1',
          title: '保留项',
          category: '风格',
          prompt: 'keep me',
          createdAt: t1,
          updatedAt: t1,
        ),
      ]);
      final pushRes = await syncA.sync(
        syncConfig,
        mode: PromptLibrarySyncMode.forcePush,
      );
      expect(pushRes.pushedEntries, 1);

      // Device B has conflicting local-only item; forcePull replaces it completely
      libB.setCustomStorageDirectory(dirB.path);
      await libB.saveEntries([
        PromptComboEntry(
          id: 'unsynced_local',
          title: '将被本地覆盖掉',
          category: '风格',
          prompt: 'local garbage',
          createdAt: t1,
          updatedAt: t1,
        ),
      ]);
      final pullRes = await syncB.sync(
        syncConfig,
        mode: PromptLibrarySyncMode.forcePull,
      );
      expect(pullRes.pulledEntries, 1);
      final afterPull = await libB.loadEntries();
      expect(afterPull.length, 1);
      expect(afterPull.first.id, 'keep_1');
    });

    test(
      'surfaces Worker upgrade guidance when legacy server rejects affix-only style entry with 400',
      () async {
        libA.setCustomStorageDirectory(dirA.path);
        final t1 = DateTime.utc(2026, 11, 22, 10, 0, 0);
        await libA.saveEntries([
          PromptComboEntry(
            id: 'style_affix_only',
            title: '纯前后缀画风',
            category: '风格',
            prompt: '',
            prefixPrompt: 'artist:example',
            suffixPrompt: 'best quality',
            createdAt: t1,
            updatedAt: t1,
          ),
        ]);

        final legacyClient = MockClient((req) async {
          if (req.method == 'GET' && req.url.path == '/api/sync') {
            return http.Response.bytes(
              utf8.encode(
                jsonEncode({
                  'ok': true,
                  'namespace': 'default',
                  'revision': 1,
                  'entries': const [],
                  'serverTime': t1.toIso8601String(),
                }),
              ),
              200,
              headers: const {'content-type': 'application/json; charset=utf-8'},
            );
          }
          if (req.method == 'POST' && req.url.path == '/api/sync/push') {
            return http.Response.bytes(
              utf8.encode(
                jsonEncode({
                  'ok': false,
                  'error': '条目 style_affix_only 缺少 title 或 prompt',
                  'code': 'INVALID_ENTRY',
                }),
              ),
              400,
              headers: const {'content-type': 'application/json; charset=utf-8'},
            );
          }
          return http.Response('not found', 404);
        });

        final legacySync = PromptLibrarySyncService(
          libraryService: libA,
          httpClient: legacyClient,
        );

        await expectLater(
          () => legacySync.sync(syncConfig),
          throwsA(
            isA<PromptLibrarySyncException>()
                .having((e) => e.statusCode, 'statusCode', 400)
                .having((e) => e.message, 'message', contains('npm run deploy')),
          ),
        );
      },
    );
  });

  group('PromptLibraryView & PromptLibrarySyncDialog Widget Tests', () {
    late Directory tempDir;
    late _FakeCloudflareSyncServer server;
    late StudioViewModel vm;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tempDir = Directory.systemTemp.createTempSync('sync_ui_test_');
      PromptLibraryService.instance.setCustomStorageDirectory(tempDir.path);
      server = _FakeCloudflareSyncServer(expectedToken: 'ui-token');
      server.entriesByNs['default'] = {
        'remote_1': {
          'id': 'remote_1',
          'title': '云端同步测试词条',
          'category': '风格',
          'prompt': 'masterpiece, oil painting',
          'negativePrompt': '',
          'tags': ['cloud'],
          'isFavorite': false,
          'isBuiltin': false,
          'previewHash': null,
          'previewExt': null,
          'createdAt': '2026-11-18T10:00:00.000Z',
          'updatedAt': '2026-11-18T10:00:00.000Z',
          'deletedAt': null,
          'revision': 1,
        },
      };
      server.revision = 1;

      final syncService = PromptLibrarySyncService(
        libraryService: PromptLibraryService.instance,
        httpClient: server.client,
      );
      vm = StudioViewModel(
        configService: ConfigService(),
        promptLibraryService: PromptLibraryService.instance,
        promptLibrarySyncService: syncService,
        sessionLogBaseDir: tempDir.path,
      );
      await vm.init();
    });

    tearDown(() {
      vm.dispose();
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    testWidgets(
      'Clicking Cloud Sync button opens sync dialog when unconfigured and syncs after configuring',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: ThemeData.light(),
            home: Scaffold(body: PromptLibraryView(viewModel: vm)),
          ),
        );
        await tester.pumpAndSettle();

        // Tap Cloud Sync button while unconfigured -> opens PromptLibrarySyncDialog
        final syncBtn = find.byKey(const Key('library_cloud_sync_button'));
        expect(syncBtn, findsOneWidget);
        await tester.tap(syncBtn);
        await tester.pumpAndSettle();

        expect(find.byType(PromptLibrarySyncDialog), findsOneWidget);

        // Fill endpoint and token
        final fields = find.descendant(
          of: find.byType(PromptLibrarySyncDialog),
          matching: find.byType(TextField),
        );
        expect(fields, findsNWidgets(3));
        await tester.enterText(fields.at(0), 'https://sync.example.com');
        await tester.enterText(fields.at(1), 'ui-token');
        await tester.pump();

        // Trigger merge sync inside dialog (runAsync lets SharedPreferences + File I/O complete)
        await tester.runAsync(() async {
          await tester.tap(find.text('立即云同步 (双向合并)'));
          await Future<void>.delayed(const Duration(milliseconds: 250));
        });
        await tester.pump();
        await tester.pump(const Duration(seconds: 4));

        expect(vm.promptLibraryEntries.length, 1);
        expect(vm.promptLibraryEntries.first.title, '云端同步测试词条');

        // Close dialog and verify card is visible in gallery
        await tester.tap(find.text('关闭'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('云端同步测试词条'), findsOneWidget);
      },
    );

    testWidgets(
      'Manage menu opens Notion context menu and sync dialog supports inline overwrite confirmation',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.runAsync(
          () => vm.savePromptSyncConfig(
            const PromptLibrarySyncConfig(
              endpoint: 'https://sync.example.com',
              token: 'ui-token',
              namespace: 'default',
            ),
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: ThemeData.light(),
            home: Scaffold(body: PromptLibraryView(viewModel: vm)),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Tap Manage button -> opens Notion-style context menu
        final manageBtn = find.byKey(const Key('library_manage_menu_button'));
        expect(manageBtn, findsOneWidget);
        await tester.tap(manageBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('云同步设置...'), findsOneWidget);
        expect(find.text('导出词库 (JSON)'), findsOneWidget);
        expect(find.text('导入词库 (JSON)'), findsOneWidget);

        // Open sync dialog from Manage menu
        await tester.tap(find.text('云同步设置...'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(PromptLibrarySyncDialog), findsOneWidget);

        // Already configured -> connection settings collapsed, overwrite section collapsed
        expect(find.text('连接配置'), findsOneWidget);
        expect(find.text('强制覆盖与恢复'), findsOneWidget);
        expect(find.text('确认覆盖'), findsNothing);

        // Expand Force Overwrite & Recovery section
        await tester.tap(find.text('强制覆盖与恢复'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        // Tap Force Pull -> shows inline confirmation bar (no second stacked modal)
        final forcePullBtn = find.text('强制拉取覆盖本地').last;
        await tester.ensureVisible(forcePullBtn);
        await tester.tap(forcePullBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        final confirmBtn = find.text('确认覆盖');
        expect(confirmBtn, findsOneWidget);
        await tester.ensureVisible(confirmBtn);
        await tester.runAsync(() async {
          await tester.tap(confirmBtn);
          await Future<void>.delayed(const Duration(milliseconds: 250));
        });
        await tester.pump();
        await tester.pump(const Duration(seconds: 4));

        expect(vm.promptLibraryEntries.length, 1);
        expect(vm.promptLibraryEntries.first.title, '云端同步测试词条');

        await tester.tap(find.text('关闭'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
      },
    );
  });
}
