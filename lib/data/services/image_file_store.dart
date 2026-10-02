import 'dart:io';

import 'package:path/path.dart' as p;

/// 无覆盖写入：仅路径校验与独占占位同步，生产调用异步写入大图和 flush。
abstract final class ImageFileStore {
  static String write({
    required String root,
    required String relativePath,
    required List<int> bytes,
    List<int>? originalBytes,
  }) {
    final files = _reserve(root, relativePath, originalBytes != null);
    try {
      files.file.writeAsBytesSync(bytes, flush: true);
      files.raw?.writeAsBytesSync(originalBytes!, flush: true);
      return files.file.path;
    } catch (_) {
      for (final file in files.reserved) {
        file.deleteSync();
      }
      rethrow;
    }
  }

  static Future<String> writeAsync({
    required String root,
    required String relativePath,
    required List<int> bytes,
    List<int>? originalBytes,
  }) async {
    final files = _reserve(root, relativePath, originalBytes != null);
    try {
      await files.file.writeAsBytes(bytes, flush: true);
      if (files.raw case final raw?) {
        await raw.writeAsBytes(originalBytes!, flush: true);
      }
      return files.file.path;
    } catch (_) {
      for (final file in files.reserved) {
        try {
          await file.delete();
        } on FileSystemException {
          /* 保留原始错误 */
        }
      }
      rethrow;
    }
  }

  static ({File file, File? raw, List<File> reserved}) _reserve(
    String root,
    String relativePath,
    bool withOriginal,
  ) {
    final parts = relativePath.replaceAll('\\', '/').split('/');
    if (parts.any((part) => part.isEmpty || part == '.' || part == '..') ||
        p.windows.isAbsolute(relativePath) ||
        p.posix.isAbsolute(relativePath)) {
      throw FileSystemException('图片路径必须位于保存目录内', relativePath);
    }
    final directory = Directory(root)..createSync(recursive: true);
    // 用户选定的根目录允许是链接；其下模板生成的目录不允许链接/目录联接。
    final canonicalRoot = directory.resolveSymbolicLinksSync();
    var parent = directory.path;
    for (final part in parts.take(parts.length - 1)) {
      parent = p.join(parent, part);
      final type = FileSystemEntity.typeSync(parent, followLinks: false);
      if (type == FileSystemEntityType.notFound) Directory(parent).createSync();
      if (FileSystemEntity.typeSync(parent, followLinks: false) !=
          FileSystemEntityType.directory) {
        throw FileSystemException('图片子目录不是普通目录', parent);
      }
      final canonical = Directory(parent).resolveSymbolicLinksSync();
      if (!p.isWithin(canonicalRoot, canonical)) {
        throw FileSystemException('图片子目录指向保存目录外', parent);
      }
    }
    final name = parts.last;
    final stem = p.basenameWithoutExtension(name);
    final extension = p.extension(name);
    for (var index = 1; index <= 10000; index++) {
      final suffix = index == 1 ? '' : '_$index';
      final file = File(p.join(parent, '$stem$suffix$extension'));
      final raw = !withOriginal
          ? null
          : File(p.join(parent, '$stem${suffix}_raw$extension'));
      final targets = [file, ?raw];
      if (targets.any((target) => _occupied(target.path))) continue;
      final reserved = <File>[];
      try {
        for (final target in targets) {
          target.createSync(exclusive: true);
          reserved.add(target);
        }
      } on FileSystemException {
        final collided = targets
            .where((target) => !reserved.contains(target))
            .any((target) => _occupied(target.path));
        for (final target in reserved) {
          target.deleteSync();
        }
        if (collided) continue;
        rethrow;
      }
      return (file: file, raw: raw, reserved: reserved);
    }
    throw FileSystemException('同名图片过多，请调整命名模板', relativePath);
  }

  static bool _occupied(String path) =>
      FileSystemEntity.typeSync(path, followLinks: false) !=
      FileSystemEntityType.notFound;
}
