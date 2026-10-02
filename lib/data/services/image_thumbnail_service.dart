import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// 可丢弃的 ≤240px 缩略图缓存，版本由原图路径、大小与修改时间决定。
/// 原图解码/降采样使用引擎 IO 线程；不再用 Dart 全尺寸 PNG 解码器重建历史。
abstract final class ImageThumbnailService {
  static const maxSide = 240;

  static Future<Uint8List?> fromBytes(Uint8List bytes) async {
    if (bytes.isEmpty) return null;
    ui.Codec? codec;
    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      codec = await ui.instantiateImageCodecWithSize(
        buffer,
        getTargetSize: (width, height) {
          final scale = maxSide / (width > height ? width : height);
          return ui.TargetImageSize(
            width: scale >= 1
                ? width
                : (width * scale).round().clamp(1, maxSide),
            height: scale >= 1
                ? height
                : (height * scale).round().clamp(1, maxSide),
          );
        },
      );
      final frame = await codec.getNextFrame();
      try {
        final data = await frame.image.toByteData(
          format: ui.ImageByteFormat.png,
        );
        return data?.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      } finally {
        frame.image.dispose();
      }
    } catch (_) {
      return null;
    } finally {
      codec?.dispose();
    }
  }

  static String _prefix(String sourcePath) => sha256
      .convert(utf8.encode(p.normalize(p.absolute(sourcePath))))
      .toString();

  static Future<Uint8List?> load({
    required String sourcePath,
    required String cacheDirectory,
    Uint8List? sourceBytes,
  }) async {
    try {
      final stat = await File(sourcePath).stat();
      if (stat.type != FileSystemEntityType.file) return null;
      final prefix = _prefix(sourcePath);
      final name =
          '${prefix}_${stat.size}_${stat.modified.microsecondsSinceEpoch}.png';
      final cache = File(p.join(cacheDirectory, name));
      if (await cache.exists()) {
        final bytes = await cache.readAsBytes();
        if (_validThumbnail(bytes)) return bytes;
      }
      final thumb = await fromBytes(
        sourceBytes ?? await File(sourcePath).readAsBytes(),
      );
      if (thumb == null) return null;
      try {
        await Directory(cacheDirectory).create(recursive: true);
        // 独占创建，不覆盖其他正在写的缓存；缓存失败不影响原图与历史。
        final temp = File(
          '${cache.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
        );
        try {
          await temp.writeAsBytes(thumb, flush: true);
          await temp.rename(cache.path);
        } finally {
          if (await temp.exists()) await temp.delete();
        }
        await for (final entry in Directory(cacheDirectory).list()) {
          if (entry is File &&
              p.basename(entry.path).startsWith('${prefix}_') &&
              entry.path != cache.path &&
              entry.path.endsWith('.png')) {
            await entry.delete();
          }
        }
      } on FileSystemException {
        /* 缓存是可丢弃的 */
      }
      return thumb;
    } on FileSystemException {
      return null;
    }
  }

  static bool _validThumbnail(Uint8List bytes) {
    if (bytes.length < 33 || bytes.length > 512 * 1024) return false;
    const header = [137, 80, 78, 71, 13, 10, 26, 10];
    for (var i = 0; i < header.length; i++) {
      if (bytes[i] != header[i]) return false;
    }
    const end = [0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130];
    for (var i = 0; i < end.length; i++) {
      if (bytes[bytes.length - end.length + i] != end[i]) return false;
    }
    final data = ByteData.sublistView(bytes);
    final width = data.getUint32(16), height = data.getUint32(20);
    return width > 0 && height > 0 && width <= maxSide && height <= maxSide;
  }

  static Future<void> remove(String sourcePath, String cacheDirectory) async {
    try {
      final dir = Directory(cacheDirectory);
      if (!await dir.exists()) return;
      final prefix = '${_prefix(sourcePath)}_';
      await for (final entry in dir.list()) {
        if (entry is File && p.basename(entry.path).startsWith(prefix)) {
          await entry.delete();
        }
      }
    } on FileSystemException {
      /* 不阻塞历史删除 */
    }
  }
}
