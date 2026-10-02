import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:novelai_harness/data/models/novelai_models.dart';
import 'package:novelai_harness/data/repositories/novelai_repository.dart';
import 'package:novelai_harness/data/services/image_thumbnail_service.dart';
import 'package:novelai_harness/data/services/tag_dictionary_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('后台词库在首次加载和串行热替换后不保留主线程完整词条表', () async {
    final service = TagDictionaryService.instance;
    await service.ensureLoaded(rawTsvContent: 'old_tag\t100\t旧词\t\t0');
    expect(service.retainedMainEntryCount, 0);
    expect((await service.search('old tag')).first.tag, 'old tag');
    await Future.wait([
      service.replaceWithContent('intermediate_tag\t100\t中间词\t\t0'),
      service.replaceWithContent('new_tag\t100\t新词\t\t0'),
    ]);
    expect(service.retainedMainEntryCount, 0);
    expect(service.translationOf('new tag'), '新词');
    expect((await service.search('new tag')).first.tag, 'new tag');
    expect(await service.search('old tag'), isEmpty);
  });

  test('大图缓存同时按字节预算和张数淘汰，历史不旁路保留原图', () {
    final repo = NovelAiRepository();
    for (var i = 0; i < 3; i++) {
      repo.addImageForTesting(
        NaiGeneratedImage(
          id: '$i',
          bytes: Uint8List(32 * 1024 * 1024),
          localFilePath: 'image_$i.png',
          params: const NaiGenerationParams(prompt: ''),
          createdAt: DateTime.now(),
          seed: 0,
          isOpusFree: true,
        ),
      );
    }
    expect(repo.cachedImageByteCount, NovelAiRepository.maxLruCacheBytes);
    expect(repo.lruImageCache.keys, ['1', '2']);
    expect(repo.imageBytesNotifier.value.keys, ['1', '2']);
    expect(repo.history.every((image) => image.bytes.isEmpty), isTrue);
  });

  test('并行读取同一原图合并为一次加载，共用相同字节缓冲', () async {
    final dir = await Directory.systemTemp.createTemp('nai_image_load_');
    try {
      final file = File('${dir.path}/image.png');
      await file.writeAsBytes([1, 2, 3]);
      final image = NaiGeneratedImage(
        id: 'coalesce',
        bytes: Uint8List(0),
        localFilePath: file.path,
        params: const NaiGenerationParams(prompt: ''),
        createdAt: DateTime.now(),
        seed: 0,
        isOpusFree: true,
      );
      final repo = NovelAiRepository();
      final bytes = await Future.wait([
        repo.loadHistoryImageBytes(image),
        repo.loadHistoryImageBytes(image),
      ]);
      expect(identical(bytes[0], bytes[1]), isTrue);
      expect(repo.cachedImageByteCount, 3);
      await repo.flushPendingImageLoads();
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('缩略图缓存命中不重解码，损坏与原图变更时重建，删除时清理', () async {
    final dir = await Directory.systemTemp.createTemp('nai_thumbnail_');
    try {
      final image = img.Image(width: 1024, height: 768);
      img.fill(image, color: img.ColorRgb8(240, 100, 40));
      final source = File('${dir.path}/original.png');
      await source.writeAsBytes(img.encodePng(image));
      final cacheDir = '${dir.path}/thumbs';
      Future<Uint8List?> load({Uint8List? bytes}) => ImageThumbnailService.load(
        sourcePath: source.path,
        cacheDirectory: cacheDir,
        sourceBytes: bytes,
      );
      final first = (await load())!;
      final decoded = img.decodePng(first)!;
      expect(decoded.width, 240);
      expect(decoded.height, 180);
      // 传入无法解码的缓冲，已有缓存仍应直接命中。
      expect(await load(bytes: Uint8List(0)), first);
      var caches = await Directory(cacheDir).list().toList();
      expect(caches, hasLength(1));
      await File(caches.single.path).writeAsBytes([0]);
      expect(await load(), first);
      await source.setLastModified(
        DateTime.now().add(const Duration(seconds: 2)),
      );
      expect(await load(), first);
      caches = await Directory(cacheDir).list().toList();
      expect(caches, hasLength(1));
      await ImageThumbnailService.remove(source.path, cacheDir);
      expect(await Directory(cacheDir).list().toList(), isEmpty);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
