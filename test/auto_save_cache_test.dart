import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/data/models/novelai_models.dart';
import 'package:novelai_harness/data/repositories/novelai_repository.dart';
import 'package:novelai_harness/data/services/config_service.dart';
import 'package:novelai_harness/data/services/novelai_service.dart';
import 'package:novelai_harness/ui/features/studio/view_models/studio_view_model.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

final kTestPngBytes = Uint8List.fromList([
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

/// 假图服务：跳过网络直接返回 1x1 测试 PNG
class _FakeNovelAiService extends NovelAiService {
  @override
  Future<List<Uint8List>> generateImage({
    required String apiKey,
    required NaiGenerationParams params,
  }) async {
    return [Uint8List.fromList(kTestPngBytes)];
  }
}

NaiGenerationParams get _params =>
    const NaiGenerationParams(prompt: 'test', width: 64, height: 64);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory saveDir;
  late NovelAiRepository repo;

  setUp(() {
    saveDir = Directory.systemTemp.createTempSync('nai_autosave_test_');
    repo = NovelAiRepository(service: _FakeNovelAiService());
  });

  tearDown(() {
    try {
      saveDir.deleteSync(recursive: true);
    } catch (_) {
      // 目录清理失败不影响断言
    }
  });

  group('generate 自动保存开关', () {
    test('自动保存关闭时写入缓存目录且标记未保存 (即使配置了水印)', () async {
      final watermarkPng = Uint8List.fromList(kTestPngBytes);
      final results = await repo.generate(
        apiKey: 'test-key',
        params: _params,
        saveDir: saveDir.path,
        enablePersistence: true,
        enableWatermark: true,
        watermarkBytes: watermarkPng,
        autoSave: false,
      );

      expect(results, hasLength(1));
      final image = results.first;
      expect(image.isUnsaved, isTrue);
      expect(image.provenance, equals(NaiImageProvenance.unsaved));
      // 文件必须落在 cache 子目录且为无处理原图字节
      final cacheDir = Directory(p.join(saveDir.path, 'cache'));
      expect(cacheDir.existsSync(), isTrue);
      expect(image.localFilePath, isNotNull);
      expect(p.dirname(image.localFilePath!), equals(cacheDir.path));
      expect(File(image.localFilePath!).existsSync(), isTrue);
      // 存储目录根不应出现正式保存文件
      final rootPngs = Directory(saveDir.path)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.png'))
          .toList();
      expect(rootPngs, isEmpty);
      // 索引在根目录并记录未保存状态
      final index = File(p.join(saveDir.path, 'image_history.json'));
      expect(index.existsSync(), isTrue);
      expect(index.readAsStringSync(), contains('"isUnsaved":true'));
    });

    test('自动保存开启时写入存储目录根且不标记未保存', () async {
      final results = await repo.generate(
        apiKey: 'test-key',
        params: _params,
        saveDir: saveDir.path,
        autoSave: true,
      );

      final image = results.first;
      expect(image.isUnsaved, isFalse);
      expect(p.dirname(image.localFilePath!), isNot(contains('cache')));
      expect(File(image.localFilePath!).existsSync(), isTrue);
    });
  });

  group('savePersistedHistory 缓存上限淘汰', () {
    test('超出上限的未保存缓存图片文件被删除，已保存文件保留', () async {
      final cacheDir = Directory(p.join(saveDir.path, 'cache'))
        ..createSync(recursive: true);
      final savedFile = File(p.join(saveDir.path, 'saved.png'))
        ..writeAsBytesSync(kTestPngBytes);

      // 依时间序构造三张图：1 张已保存 + 3 张未保存缓存
      NaiGeneratedImage img(String id, String path, {bool unsaved = true}) =>
          NaiGeneratedImage(
            id: id,
            bytes: kTestPngBytes,
            localFilePath: path,
            params: _params,
            seed: 1,
            isOpusFree: false,
            isUnsaved: unsaved,
            createdAt: DateTime.now(),
          );

      final cacheFiles = <File>[];
      for (var i = 0; i < 3; i++) {
        final f = File(p.join(cacheDir.path, 'cache_$i.png'))
          ..writeAsBytesSync(kTestPngBytes);
        cacheFiles.add(f);
      }

      // addImageForTesting 插入头部：先加旧的再加新的
      repo.addImageForTesting(img('old-saved', savedFile.path, unsaved: false));
      repo.addImageForTesting(img('c0', cacheFiles[0].path));
      repo.addImageForTesting(img('c1', cacheFiles[1].path));
      repo.addImageForTesting(img('c2', cacheFiles[2].path));

      await repo.savePersistedHistory(saveDir: saveDir.path, maxImages: 2);

      // 历史被裁剪到 2 张
      expect(repo.history, hasLength(2));
      // 最旧的已保存文件保留，最旧的缓存图片被删除，其余缓存保留
      expect(savedFile.existsSync(), isTrue);
      expect(cacheFiles[0].existsSync(), isFalse);
      expect(cacheFiles[1].existsSync(), isTrue);
      expect(cacheFiles[2].existsSync(), isTrue);
    });
  });

  group('saveUnsavedImageToDisk 手动保存', () {
    test('落盘到存储目录、删除缓存文件并更新历史条目', () async {
      final cacheDir = Directory(p.join(saveDir.path, 'cache'))
        ..createSync(recursive: true);
      final cacheFile = File(p.join(cacheDir.path, 'cache_0.png'))
        ..writeAsBytesSync(kTestPngBytes);

      final image = NaiGeneratedImage(
        id: 'u1',
        bytes: kTestPngBytes,
        localFilePath: cacheFile.path,
        params: _params,
        seed: 42,
        isOpusFree: false,
        isUnsaved: true,
        createdAt: DateTime.now(),
      );
      repo.addImageForTesting(image);

      final saved = await repo.saveUnsavedImageToDisk(
        imageId: 'u1',
        saveDir: saveDir.path,
      );

      expect(saved, isNotNull);
      expect(saved!.isUnsaved, isFalse);
      expect(saved.localFilePath, isNotNull);
      // 保存文件在存储目录根，缓存文件已删除
      expect(p.dirname(saved.localFilePath!), equals(saveDir.path));
      expect(File(saved.localFilePath!).existsSync(), isTrue);
      expect(cacheFile.existsSync(), isFalse);
      // 历史条目同步更新
      expect(repo.history.first.isUnsaved, isFalse);
      // 重复保存直接返回不再写文件
      final again = await repo.saveUnsavedImageToDisk(
        imageId: 'u1',
        saveDir: saveDir.path,
      );
      expect(again!.isUnsaved, isFalse);
      expect(again.localFilePath, equals(saved.localFilePath));
    });

    test('开启保持原图时同时保存 _raw.png 副本', () async {
      final cacheDir = Directory(p.join(saveDir.path, 'cache'))
        ..createSync(recursive: true);
      final cacheFile = File(p.join(cacheDir.path, 'cache_1.png'))
        ..writeAsBytesSync(kTestPngBytes);

      repo.addImageForTesting(
        NaiGeneratedImage(
          id: 'u2',
          bytes: kTestPngBytes,
          localFilePath: cacheFile.path,
          params: _params,
          seed: 43,
          isOpusFree: false,
          isUnsaved: true,
          createdAt: DateTime.now(),
        ),
      );

      final saved = await repo.saveUnsavedImageToDisk(
        imageId: 'u2',
        saveDir: saveDir.path,
        stripMetadata: true,
        keepOriginalImage: true,
      );

      expect(saved, isNotNull);
      final rawPath =
          '${saved!.localFilePath!.substring(0, saved.localFilePath!.lastIndexOf('.'))}_raw.png';
      expect(File(rawPath).existsSync(), isTrue);
    });
  });

  group('clearAllHistory 清理语义', () {
    test('自动保存关闭时删除缓存图片但保留已保存文件与 _raw 副本', () async {
      final cacheDir = Directory(p.join(saveDir.path, 'cache'))
        ..createSync(recursive: true);
      final cacheFile = File(p.join(cacheDir.path, 'cache_x.png'))
        ..writeAsBytesSync(kTestPngBytes);
      final savedFile = File(p.join(saveDir.path, 'nai_saved.png'))
        ..writeAsBytesSync(kTestPngBytes);
      final rawFile = File(p.join(saveDir.path, 'nai_saved_raw.png'))
        ..writeAsBytesSync(kTestPngBytes);
      File(
        p.join(saveDir.path, 'image_history.json'),
      ).writeAsStringSync('[{"id":"x"}]');

      repo.addImageForTesting(
        NaiGeneratedImage(
          id: 'saved',
          bytes: kTestPngBytes,
          localFilePath: savedFile.path,
          params: _params,
          seed: 1,
          isOpusFree: false,
          createdAt: DateTime.now(),
        ),
      );

      await repo.clearAllHistory(saveDir: saveDir.path, autoSave: false);

      expect(repo.history, isEmpty);
      expect(cacheDir.existsSync(), isFalse);
      expect(savedFile.existsSync(), isTrue);
      expect(rawFile.existsSync(), isTrue);
      expect(
        File(p.join(saveDir.path, 'image_history.json')).existsSync(),
        isFalse,
      );
      expect(cacheFile.existsSync(), isFalse);
    });

    test('自动保存开启时仅清理 UI 记录与索引，全部文件保留', () async {
      final cacheDir = Directory(p.join(saveDir.path, 'cache'))
        ..createSync(recursive: true);
      final cacheFile = File(p.join(cacheDir.path, 'cache_y.png'))
        ..writeAsBytesSync(kTestPngBytes);
      final savedFile = File(p.join(saveDir.path, 'nai_saved2.png'))
        ..writeAsBytesSync(kTestPngBytes);

      repo.addImageForTesting(
        NaiGeneratedImage(
          id: 'saved2',
          bytes: kTestPngBytes,
          localFilePath: savedFile.path,
          params: _params,
          seed: 2,
          isOpusFree: false,
          createdAt: DateTime.now(),
        ),
      );

      await repo.clearAllHistory(saveDir: saveDir.path, autoSave: true);

      expect(repo.history, isEmpty);
      expect(savedFile.existsSync(), isTrue);
      expect(cacheFile.existsSync(), isTrue);
      expect(
        File(p.join(saveDir.path, 'image_history.json')).existsSync(),
        isFalse,
      );
    });
  });

  group('isUnsaved 序列化往返', () {
    test('toJson / fromJson 保留未保存标记', () {
      final image = NaiGeneratedImage(
        id: 'u3',
        bytes: kTestPngBytes,
        params: _params,
        seed: 7,
        isOpusFree: false,
        isUnsaved: true,
        createdAt: DateTime.now(),
      );
      final restored = NaiGeneratedImage.fromJson(image.toJson());
      expect(restored.isUnsaved, isTrue);
      expect(restored.provenance, equals(NaiImageProvenance.unsaved));

      final saved = NaiGeneratedImage(
        id: 's3',
        bytes: kTestPngBytes,
        params: _params,
        seed: 8,
        isOpusFree: false,
        isUpscaled: true,
        createdAt: DateTime.now(),
      );
      expect(NaiGeneratedImage.fromJson(saved.toJson()).isUnsaved, isFalse);
    });
  });

  group('StudioViewModel.saveCurrentImageToDisk', () {
    test('保存当前选中未保存图片并更新选中状态', () async {
      SharedPreferences.setMockInitialValues({});
      final sessionBase = Directory.systemTemp.createTempSync(
        'nai_autosave_vm_test_',
      );
      final vmSaveDir = Directory.systemTemp.createTempSync(
        'nai_autosave_vm_save_',
      );
      final cacheDir = Directory(p.join(vmSaveDir.path, 'cache'))
        ..createSync(recursive: true);
      final cacheFile = File(p.join(cacheDir.path, 'cache_vm.png'))
        ..writeAsBytesSync(kTestPngBytes);

      final repo = NovelAiRepository();
      final vm = StudioViewModel(
        repository: repo,
        sessionLogBaseDir: sessionBase.path,
      );
      await vm.init();
      await vm.updateConfig(
        vm.config.copyWith(
          saveDirectory: vmSaveDir.path,
          autoSaveImages: false,
          localePreference: AppLocalePreference.zh,
        ),
      );

      final unsaved = NaiGeneratedImage(
        id: 'vm-u1',
        bytes: kTestPngBytes,
        localFilePath: cacheFile.path,
        params: _params,
        seed: 9,
        isOpusFree: false,
        isUnsaved: true,
        createdAt: DateTime.now(),
      );
      repo.addImageForTesting(unsaved);
      vm.selectImage(unsaved);
      expect(vm.autoSaveImages, isFalse);

      final ok = await vm.saveCurrentImageToDisk();
      expect(ok, isTrue);
      expect(vm.selectedImage!.isUnsaved, isFalse);
      expect(vm.selectedImage!.localFilePath, isNotNull);
      expect(File(vm.selectedImage!.localFilePath!).existsSync(), isTrue);
      expect(cacheFile.existsSync(), isFalse);
      expect(vm.statusMessage, contains('已保存到'));

      vm.dispose();
      try {
        sessionBase.deleteSync(recursive: true);
        vmSaveDir.deleteSync(recursive: true);
      } catch (_) {}
    });
  });
}
