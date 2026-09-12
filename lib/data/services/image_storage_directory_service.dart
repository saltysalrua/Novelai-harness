import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 图片、历史索引与画布共同使用的普通文件目录。
///
/// Android 的 SAF 目录授权不等于 dart:io 文件权限，不能只看目录是否存在。
/// 保留仍可读写的旧目录；无效配置回退应用文档目录，不向系统临时目录落图。
class ImageStorageDirectoryService {
  ImageStorageDirectoryService({
    bool? isAndroid,
    Future<Directory> Function()? documentsDirectory,
  }) : _isAndroid = isAndroid ?? Platform.isAndroid,
       _documentsDirectory =
           documentsDirectory ?? getApplicationDocumentsDirectory;

  final bool _isAndroid;
  final Future<Directory> Function() _documentsDirectory;

  Future<String> resolve(String configuredDirectory) async {
    if (!_isAndroid && configuredDirectory.isNotEmpty) {
      return configuredDirectory;
    }
    if (_isAndroid && await _canPersist(configuredDirectory)) {
      return configuredDirectory;
    }

    try {
      final documents = await _documentsDirectory();
      final directory = Directory(p.join(documents.path, 'NovelAI_Output'));
      await directory.create(recursive: true);
      if (_isAndroid && !await _canPersist(directory.path)) {
        throw FileSystemException('无法读写应用图片存储目录', directory.path);
      }
      return directory.path;
    } catch (_) {
      // 安卓不能静默返回空目录：仓储会因此只留内存图片，重启即丢失。
      if (_isAndroid) rethrow;
      return '';
    }
  }

  Future<bool> _canPersist(String path) async {
    // content:// 是授权 URI，不是普通路径；相对路径和空串也不能持久化。
    if (path.trim().isEmpty || path.contains('://') || !p.isAbsolute(path)) {
      return false;
    }
    Directory? probe;
    try {
      final directory = await Directory(path).create(recursive: true);
      probe = await directory.createTemp('.nai_storage_check_');
      // 不只测试 PNG：作用域存储可能允许媒体文件，却拒绝 JSON 历史索引。
      final file = await File(
        p.join(probe.path, 'history.json'),
      ).create(exclusive: true);
      await file.writeAsString('[]', flush: true);
      return await file.readAsString() == '[]';
    } on FileSystemException {
      return false;
    } finally {
      if (probe != null) {
        try {
          await probe.delete(recursive: true);
        } on FileSystemException {
          // 只清理本次独占创建的探针，不触碰用户原有图片与目录。
        }
      }
    }
  }
}
