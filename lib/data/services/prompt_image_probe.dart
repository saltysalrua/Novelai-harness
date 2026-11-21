import 'dart:async' show unawaited;
import 'dart:io';
import 'dart:typed_data';

/// 轻量级图片宽高比探测器：只读取文件头字节解析真实分辨率，
/// 不解码完整像素，供词库瀑布流以零留白、零裁切方式展示完整图片。
abstract final class PromptImageProbe {
  static final Map<String, double> _aspectCache = {};
  static final Set<String> _missingOrInvalid = {};
  static final Map<String, Future<double?>> _inFlight = {};

  /// 同步读取内存缓存的宽高比 (无磁盘 I/O；未命中返回 null)
  static double? getCachedAspectRatio(String? path) {
    final key = path?.trim();
    if (key == null || key.isEmpty) return null;
    return _aspectCache[key];
  }

  /// 是否已确认该路径不存在或无效 (仅作为异步探测后的快速提示)
  static bool isKnownMissing(String? path) {
    final key = path?.trim();
    if (key == null || key.isEmpty) return true;
    return _missingOrInvalid.contains(key);
  }

  /// 记录已知宽高比 (例如保存新预览图时直接写入，免去后续探测)
  static void recordBytes(String path, Uint8List bytes) {
    final key = path.trim();
    if (key.isEmpty) return;
    final ratio = probeBytes(bytes);
    if (ratio != null && ratio > 0) {
      _missingOrInvalid.remove(key);
      _aspectCache[key] = ratio;
    }
  }

  /// 清除指定路径缓存
  static void invalidate(String? path) {
    final key = path?.trim();
    if (key == null || key.isEmpty) return;
    _aspectCache.remove(key);
    _missingOrInvalid.remove(key);
  }

  /// 批量异步预热路径宽高比 (在后台加载词库列表时调用)
  static Future<void> warmUpPaths(Iterable<String?> paths) async {
    final pending = <Future<double?>>[];
    for (final path in paths) {
      final key = path?.trim();
      if (key == null ||
          key.isEmpty ||
          _aspectCache.containsKey(key) ||
          _missingOrInvalid.contains(key)) {
        continue;
      }
      pending.add(probeFile(key));
    }
    if (pending.isNotEmpty) {
      await Future.wait(pending);
    }
  }

  /// 异步读取文件头并缓存真实宽高比 (PNG / JPEG / WebP)
  static Future<double?> probeFile(String? path) {
    final key = path?.trim();
    if (key == null || key.isEmpty) return Future.value(null);
    final cached = _aspectCache[key];
    if (cached != null) return Future.value(cached);
    if (_missingOrInvalid.contains(key)) return Future.value(null);

    return _inFlight.putIfAbsent(key, () async {
      try {
        final file = File(key);
        if (!await file.exists()) {
          _missingOrInvalid.add(key);
          return null;
        }
        final raf = await file.open();
        try {
          // 绝大多数 PNG/WebP 仅需 32 字节；JPEG EXIF 后 SOF 通常在 64KB 内
          final head = await raf.read(32);
          var ratio = probeBytes(head);
          if (ratio == null && head.length >= 2 && head[0] == 0xFF && head[1] == 0xD8) {
            await raf.setPosition(0);
            final larger = await raf.read(65536);
            ratio = probeBytes(larger);
          }
          if (ratio != null && ratio > 0) {
            _aspectCache[key] = ratio;
            return ratio;
          }
          return null;
        } finally {
          await raf.close();
        }
      } catch (_) {
        return null;
      } finally {
        unawaited(_inFlight.remove(key));
      }
    });
  }

  /// 从字节头解析真实宽高 (PNG / WebP / JPEG)
  static (int, int)? probeDimensions(Uint8List bytes) {
    final size = _parseSize(bytes);
    if (size == null || size.$1 <= 0 || size.$2 <= 0) return null;
    return size;
  }

  /// 从字节头解析宽高比 (PNG / WebP / JPEG)
  static double? probeBytes(Uint8List bytes) {
    final size = probeDimensions(bytes);
    if (size == null) return null;
    return size.$1 / size.$2;
  }

  static (int, int)? _parseSize(Uint8List b) {
    // 1. PNG
    if (b.length >= 24 &&
        b[0] == 0x89 &&
        b[1] == 0x50 &&
        b[2] == 0x4E &&
        b[3] == 0x47 &&
        b[4] == 0x0D &&
        b[5] == 0x0A &&
        b[6] == 0x1A &&
        b[7] == 0x0A) {
      final w = (b[16] << 24) | (b[17] << 16) | (b[18] << 8) | b[19];
      final h = (b[20] << 24) | (b[21] << 16) | (b[22] << 8) | b[23];
      return (w, h);
    }

    // 2. WebP
    if (b.length >= 30 &&
        b[0] == 0x52 &&
        b[1] == 0x49 &&
        b[2] == 0x46 &&
        b[3] == 0x46 &&
        b[8] == 0x57 &&
        b[9] == 0x45 &&
        b[10] == 0x42 &&
        b[11] == 0x50) {
      // VP8
      if (b[12] == 0x56 && b[13] == 0x50 && b[14] == 0x38 && b[15] == 0x20) {
        final w = (b[26] | (b[27] << 8)) & 0x3FFF;
        final h = (b[28] | (b[29] << 8)) & 0x3FFF;
        return (w, h);
      }
      // VP8L
      if (b[12] == 0x56 && b[13] == 0x50 && b[14] == 0x38 && b[15] == 0x4C) {
        final bits = b[21] | (b[22] << 8) | (b[23] << 16) | (b[24] << 24);
        final w = (bits & 0x3FFF) + 1;
        final h = ((bits >> 14) & 0x3FFF) + 1;
        return (w, h);
      }
      // VP8X
      if (b[12] == 0x56 && b[13] == 0x50 && b[14] == 0x38 && b[15] == 0x58) {
        final w = (b[24] | (b[25] << 8) | (b[26] << 16)) + 1;
        final h = (b[27] | (b[28] << 8) | (b[29] << 16)) + 1;
        return (w, h);
      }
    }

    // 3. JPEG
    if (b.length >= 4 && b[0] == 0xFF && b[1] == 0xD8) {
      var offset = 2;
      while (offset + 1 < b.length) {
        while (offset < b.length && b[offset] == 0xFF) {
          offset++;
        }
        if (offset >= b.length) break;
        final marker = b[offset++];
        if (marker == 0xD9 || marker == 0xDA) break;
        if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) continue;
        if (offset + 1 >= b.length) break;
        final segLen = (b[offset] << 8) | b[offset + 1];
        if (segLen < 2) break;
        if ((marker >= 0xC0 && marker <= 0xCF) &&
            marker != 0xC4 &&
            marker != 0xC8 &&
            marker != 0xCC) {
          if (offset + 6 < b.length) {
            final h = (b[offset + 3] << 8) | b[offset + 4];
            final w = (b[offset + 5] << 8) | b[offset + 6];
            return (w, h);
          }
          break;
        }
        offset += segLen;
      }
    }

    return null;
  }
}
