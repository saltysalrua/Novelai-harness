import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/data/models/novelai_models.dart';
import 'package:novelai_harness/data/repositories/novelai_repository.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('nai_lru_test_');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('NovelAiRepository LRU 大图缓存与缩略图机制', () {
    test('LRU 缓存上限为 5 张，超出时 FIFO 淘汰最久未访问者', () async {
      final repo = NovelAiRepository();
      const params = NaiGenerationParams(prompt: 'lru test');

      // 创建 6 张虚拟图片并写入磁盘
      final images = <NaiGeneratedImage>[];
      for (var i = 0; i < 6; i++) {
        final filePath = p.join(tempDir.path, 'img_$i.png');
        final bytes = Uint8List.fromList([i, i + 1, i + 2]);
        File(filePath).writeAsBytesSync(bytes);

        final img = NaiGeneratedImage(
          id: 'img_$i',
          bytes: bytes,
          localFilePath: filePath,
          params: params,
          createdAt: DateTime.now(),
          seed: i,
          isOpusFree: true,
        );
        images.add(img);
        repo.addImageForTesting(img);
      }

      // addImageForTesting 会自动将 bytes 缓存进 _lruImageCache
      // 添加了 6 张后，第 0 张应该被逐出，剩余 1..5
      final cacheKeys = repo.lruImageCache.keys.toList();
      expect(cacheKeys.length, equals(5));
      expect(cacheKeys.contains('img_0'), isFalse);
      expect(cacheKeys, equals(['img_1', 'img_2', 'img_3', 'img_4', 'img_5']));

      // 访问 img_1，使其重新成为最新使用的项 (MRU)
      final bytes1 = await repo.loadHistoryImageBytes(images[1]);
      expect(bytes1, equals([1, 2, 3]));

      // 此时 LRU 顺序应变为：img_2, img_3, img_4, img_5, img_1
      final cacheKeysAfterAccess = repo.lruImageCache.keys.toList();
      expect(
        cacheKeysAfterAccess,
        equals(['img_2', 'img_3', 'img_4', 'img_5', 'img_1']),
      );

      // 重新加载已被淘汰的 img_0，此时最老的 img_2 应该被淘汰
      final bytes0 = await repo.loadHistoryImageBytes(images[0]);
      expect(bytes0, equals([0, 1, 2]));

      final cacheKeysAfterReload0 = repo.lruImageCache.keys.toList();
      expect(cacheKeysAfterReload0.contains('img_2'), isFalse);
      expect(
        cacheKeysAfterReload0,
        equals(['img_3', 'img_4', 'img_5', 'img_1', 'img_0']),
      );
    });

    test('loadPersistedHistory 仅读元信息，大图 bytes 初始化为空，调用 loadHistoryImageBytes 懒加载', () async {
      final repo = NovelAiRepository();
      const params = NaiGenerationParams(prompt: 'persisted lazy');

      final filePath = p.join(tempDir.path, 'persist_lazy.png');
      final originalBytes = Uint8List.fromList([11, 22, 33, 44]);
      File(filePath).writeAsBytesSync(originalBytes);

      final img = NaiGeneratedImage(
        id: 'img_lazy_1',
        bytes: originalBytes,
        localFilePath: filePath,
        params: params,
        createdAt: DateTime.now(),
        seed: 777,
        isOpusFree: true,
      );

      final historyFile = File(p.join(tempDir.path, 'image_history.json'));
      historyFile.writeAsStringSync(jsonEncode([img.toJson()]));

      // 执行 loadPersistedHistory
      final loaded = await repo.loadPersistedHistory(saveDir: tempDir.path);
      expect(loaded.length, equals(1));

      final loadedImg = loaded.first;
      // 内存治理要点：大图常驻 bytes 必须为空
      expect(loadedImg.bytes.isEmpty, isTrue);
      // 此时 LRU 缓存中尚未加载该图
      expect(repo.lruImageCache.containsKey(loadedImg.id), isFalse);

      // 按需懒加载大图
      final loadedBytes = await repo.loadHistoryImageBytes(loadedImg);
      expect(loadedBytes, equals(originalBytes));
      // 此时已载入 LRU 缓存
      expect(repo.lruImageCache.containsKey(loadedImg.id), isTrue);
      expect(repo.lruImageCache[loadedImg.id], equals(originalBytes));
    });

    test('deleteImage 与 clearHistory 会同步清理 LRU 缓存条目', () async {
      final repo = NovelAiRepository();
      const params = NaiGenerationParams(prompt: 'cleanup test');

      final filePath1 = p.join(tempDir.path, 'cleanup_1.png');
      final bytes1 = Uint8List.fromList([1, 2, 3]);
      File(filePath1).writeAsBytesSync(bytes1);

      final img1 = NaiGeneratedImage(
        id: 'img_c1',
        bytes: bytes1,
        localFilePath: filePath1,
        params: params,
        createdAt: DateTime.now(),
        seed: 1,
        isOpusFree: true,
      );
      repo.addImageForTesting(img1);
      expect(repo.lruImageCache.containsKey('img_c1'), isTrue);

      // 删除图片
      await repo.deleteImage(imageId: 'img_c1', saveDir: tempDir.path);
      expect(repo.lruImageCache.containsKey('img_c1'), isFalse);

      // 再次添加并测试 clearHistory
      repo.addImageForTesting(img1);
      expect(repo.lruImageCache.containsKey('img_c1'), isTrue);

      repo.clearHistory(saveDir: tempDir.path);
      expect(repo.lruImageCache.isEmpty, isTrue);
    });
  });
}
