import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/data/models/novelai_models.dart';
import 'package:novelai_harness/data/repositories/novelai_repository.dart';
import 'package:novelai_harness/data/services/media_store_service.dart';
import 'package:novelai_harness/data/services/novelai_service.dart';
import 'package:path/path.dart' as p;

/// 1x1 测试 PNG 字节 (与 auto_save_cache_test 同构，避免跨文件依赖)
final _testPngBytes = Uint8List.fromList([
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

class _FakeNovelAiService extends NovelAiService {
  @override
  Future<List<Uint8List>> generateImage({
    required String apiKey,
    required NaiGenerationParams params,
  }) async {
    return [Uint8List.fromList(_testPngBytes)];
  }
}

NaiGenerationParams get _params =>
    const NaiGenerationParams(prompt: 'test', width: 64, height: 64);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel(MediaStoreService.channelName),
          null,
        );
  });

  MediaStoreService mobileService() => MediaStoreService(
    isAndroid: true,
    channel: const MethodChannel(MediaStoreService.channelName),
  );

  group('MediaStoreService 通道封装', () {
    test('saveImage 透传字节/文件名/子目录并返回原生路径', () async {
      Object? capturedBytes;
      String? capturedName;
      String? capturedSubDir;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(MediaStoreService.channelName),
            (call) async {
              capturedBytes = call.arguments['bytes'];
              capturedName = call.arguments['fileName'];
              capturedSubDir = call.arguments['subDir'];
              return 'Pictures/NovelAI/demo.png';
            },
          );

      final location = await mobileService().saveImage(
        _testPngBytes,
        'demo.png',
        subDir: 'NovelAI',
      );

      expect(location, equals('Pictures/NovelAI/demo.png'));
      expect(capturedBytes, equals(_testPngBytes));
      expect(capturedName, equals('demo.png'));
      expect(capturedSubDir, equals('NovelAI'));
    });

    test('saveImage 把原生异常映射为 MediaStoreException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(MediaStoreService.channelName),
            (call) async => throw PlatformException(
              code: 'PERMISSION_DENIED',
              message: '缺少存储权限',
            ),
          );

      await expectLater(
        mobileService().saveImage(_testPngBytes, 'demo.png'),
        throwsA(
          isA<MediaStoreException>().having(
            (e) => e.isPermissionDenied,
            'isPermissionDenied',
            isTrue,
          ),
        ),
      );
    });

    test('copyImageToClipboard 透传字节且失败抛 MediaStoreException', () async {
      var callCount = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(MediaStoreService.channelName),
            (call) async {
              callCount++;
              if (call.method == 'copyImage' && callCount == 1) {
                return true;
              }
              throw PlatformException(code: 'COPY_FAILED', message: 'boom');
            },
          );

      final service = mobileService();
      await service.copyImageToClipboard(_testPngBytes);
      expect(callCount, equals(1));

      await expectLater(
        service.copyImageToClipboard(_testPngBytes),
        throwsA(isA<MediaStoreException>()),
      );
    });

    test('空字节与非安卓平台被拒绝', () async {
      final mobile = mobileService();
      await expectLater(
        mobile.saveImage(Uint8List(0), 'demo.png'),
        throwsA(isA<MediaStoreException>()),
      );

      final desktop = MediaStoreService(isAndroid: false);
      expect(desktop.isSupported, isFalse);
      await expectLater(
        desktop.saveImage(_testPngBytes, 'demo.png'),
        throwsA(isA<UnsupportedError>()),
      );
      await expectLater(
        desktop.copyImageToClipboard(_testPngBytes),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });

  group('NovelAiRepository 公共图库导出钩子', () {
    late Directory saveDir;
    late NovelAiRepository repo;

    setUp(() {
      saveDir = Directory.systemTemp.createTempSync('nai_gallery_test_');
      repo = NovelAiRepository(service: _FakeNovelAiService());
    });

    tearDown(() {
      try {
        saveDir.deleteSync(recursive: true);
      } catch (_) {
        // 清理失败不影响断言
      }
    });

    test('自动保存时调用钩子并传入成品字节与模板相对路径', () async {
      final calls = <(Uint8List, String)>[];
      repo.galleryExportFn = (bytes, relativePath) async {
        calls.add((bytes, relativePath));
      };

      final results = await repo.generate(
        apiKey: 'test-key',
        params: _params,
        saveDir: saveDir.path,
        autoSave: true,
      );

      expect(results, hasLength(1));
      expect(calls, hasLength(1));
      // 钩子拿到的与写进正式存储目录的成品字节完全一致
      final persisted = File(results.first.localFilePath!).readAsBytesSync();
      expect(calls.first.$1, equals(persisted));
      expect(calls.first.$2, endsWith('.png'));
    });

    test('钩子抛错不阻塞落图主流程', () async {
      repo.galleryExportFn = (bytes, relativePath) async {
        throw const MediaStoreException('媒体库写入失败');
      };

      final results = await repo.generate(
        apiKey: 'test-key',
        params: _params,
        saveDir: saveDir.path,
        autoSave: true,
      );

      expect(results, hasLength(1));
      expect(File(results.first.localFilePath!).existsSync(), isTrue);
    });

    test('自动保存关闭时 (未保存缓存) 不触发钩子', () async {
      var callCount = 0;
      repo.galleryExportFn = (bytes, relativePath) async {
        callCount++;
      };

      final results = await repo.generate(
        apiKey: 'test-key',
        params: _params,
        saveDir: saveDir.path,
        autoSave: false,
      );

      expect(results, hasLength(1));
      expect(results.first.isUnsaved, isTrue);
      expect(callCount, equals(0));
      expect(
        p.dirname(results.first.localFilePath!),
        equals(p.join(saveDir.path, 'cache')),
      );
    });
  });
}
