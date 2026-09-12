import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 公共图库导出钩子签名：(处理后的成品字节, 命名模板相对路径)。
///
/// 由 [MediaStoreService.saveImage] 消费，也可在测试中注入替身。
typedef MediaGalleryExportFn =
    Future<void> Function(Uint8List bytes, String relativePath);

/// 安卓系统媒体库 (MediaStore) 与剪贴板的原生通道封装。
///
/// 作用域存储下应用私有目录对其他应用不可见；经 MediaStore 写入公共
/// `Pictures/` 的图片会被媒体库原生登记，相册与文件管理器立即可见。
/// 安卓系统剪贴板不支持裸位图字节，复制图像走 FileProvider content URI。
///
/// 仅在 Android 平台真实可用 ([isSupported] 为 false 时调用抛
/// [UnsupportedError])；构造函数支持注入平台判定与通道，便于测试替身。
class MediaStoreService {
  MediaStoreService({bool? isAndroid, MethodChannel? channel})
    : _isAndroid = isAndroid ?? (!kIsWeb && Platform.isAndroid),
      _channel = channel ?? const MethodChannel(channelName);

  /// 原生方法通道名 (MainActivity.kt 注册同名处理器)。
  static const String channelName = 'novelai_harness/media_store';

  /// 生产环境共享实例：UI 层手动导出与剪贴板复制统一从这里走。
  static final MediaStoreService instance = MediaStoreService();

  final bool _isAndroid;
  final MethodChannel _channel;

  /// 是否运行在支持该通道的安卓环境。
  bool get isSupported => _isAndroid;

  /// 把 PNG 字节写入公共图片媒体库 `Pictures/<subDir>`，返回展示路径。
  ///
  /// [subDir] 为可选的相对子目录 (如 `NovelAI/2026-09`)，为空时直接落
  /// `Pictures/`。同名冲突由 MediaStore 自动追加序号 (Android 10+)。
  ///
  /// 失败时抛 [MediaStoreException]：
  /// - `PERMISSION_DENIED`：Android 9 及以下缺少存储权限，可回退 SAF 导出；
  /// - `SAVE_FAILED`：媒体库写入失败。
  Future<String> saveImage(
    Uint8List bytes,
    String fileName, {
    String subDir = '',
  }) async {
    _ensureSupported('saveImage');
    if (bytes.isEmpty) {
      throw const MediaStoreException('图片字节为空');
    }
    try {
      final location = await _channel.invokeMethod<String>('saveImage', {
        'bytes': bytes,
        'fileName': fileName,
        'subDir': subDir,
      });
      if (location == null || location.isEmpty) {
        throw const MediaStoreException('未返回保存路径');
      }
      return location;
    } on PlatformException catch (error) {
      throw MediaStoreException.fromPlatform(error);
    }
  }

  /// 把 PNG 字节复制到系统剪贴板 (content URI 形式)。
  ///
  /// 安卓剪贴板不支持裸位图；原生侧写入缓存文件并经 FileProvider 暴露
  /// URI，聊天/编辑类应用可直接粘贴。失败抛 [MediaStoreException]。
  Future<void> copyImageToClipboard(Uint8List bytes) async {
    _ensureSupported('copyImage');
    if (bytes.isEmpty) {
      throw const MediaStoreException('图片字节为空');
    }
    try {
      await _channel.invokeMethod<bool>('copyImage', {'bytes': bytes});
    } on PlatformException catch (error) {
      throw MediaStoreException.fromPlatform(error);
    }
  }

  /// 唤起系统目录选择器 (SAF `ACTION_OPEN_DOCUMENT_TREE`)。
  ///
  /// 返回自选导出目录信息；用户取消返回 null。选中后原生侧持久化
  /// 读写授权，重启后仍可写入。失败抛 [MediaStoreException]。
  Future<SafDirectoryInfo?> pickExportDirectory() async {
    _ensureSupported('pickExportDirectory');
    try {
      final info = await _channel.invokeMethod<Map<Object?, Object?>?>(
        'pickDirectory',
      );
      if (info == null) return null;
      return SafDirectoryInfo.fromChannelMap(info);
    } on PlatformException catch (error) {
      throw MediaStoreException.fromPlatform(error);
    }
  }

  /// 校验已保存的自选目录授权是否仍然有效 (用户可能在系统设置中撤销)。
  ///
  /// 授权失效或目录不存在时返回 null；有效时返回最新目录信息。
  Future<SafDirectoryInfo?> verifyExportDirectory(String treeUri) async {
    _ensureSupported('verifyExportDirectory');
    if (treeUri.isEmpty) return null;
    try {
      final info = await _channel.invokeMethod<Map<Object?, Object?>?>(
        'getTreeInfo',
        {'uri': treeUri},
      );
      if (info == null) return null;
      return SafDirectoryInfo.fromChannelMap(info);
    } on PlatformException catch (error) {
      throw MediaStoreException.fromPlatform(error);
    }
  }

  /// 把 PNG 字节写入自选 SAF 目录树。
  ///
  /// [relativePath] 形如 `2026-09/model/name.png`：目录段不存在时自动
  /// 创建，同名文件由 DocumentsProvider 自动改名，绝不覆盖。返回原生
  /// 侧拼好的展示路径。授权失效抛 [MediaStoreException]。
  Future<String> saveImageToDirectory(
    Uint8List bytes,
    String treeUri,
    String relativePath,
  ) async {
    _ensureSupported('saveImageToDirectory');
    if (bytes.isEmpty) {
      throw const MediaStoreException('图片字节为空');
    }
    if (treeUri.isEmpty) {
      throw const MediaStoreException('未选择导出目录', code: 'NO_DIRECTORY');
    }
    try {
      final location = await _channel.invokeMethod<String>('saveImageToTree', {
        'bytes': bytes,
        'treeUri': treeUri,
        'relativePath': relativePath,
      });
      if (location == null || location.isEmpty) {
        throw const MediaStoreException('未返回保存路径');
      }
      return location;
    } on PlatformException catch (error) {
      throw MediaStoreException.fromPlatform(error);
    }
  }

  void _ensureSupported(String operation) {
    if (!_isAndroid) {
      throw UnsupportedError('MediaStoreService.$operation 仅支持 Android');
    }
  }
}

/// 自选 SAF 导出目录信息 (原生目录选择器返回)。
class SafDirectoryInfo {
  const SafDirectoryInfo({required this.uri, required this.name});

  factory SafDirectoryInfo.fromChannelMap(Map<Object?, Object?> map) =>
      SafDirectoryInfo(
        uri: map['uri'] as String? ?? '',
        name: map['name'] as String? ?? '',
      );

  /// SAF 目录树 URI (`content://...`)，持久授权后跨重启可用。
  final String uri;

  /// 目录友好显示名 (设置页展示)。
  final String name;
}

/// 媒体库/剪贴板写入失败的统一异常，携带原生错误码与原因。
class MediaStoreException implements Exception {
  const MediaStoreException(this.message, {this.code});

  factory MediaStoreException.fromPlatform(PlatformException error) =>
      MediaStoreException(error.message ?? error.code, code: error.code);

  final String message;
  final String? code;

  /// Android 9 及以下缺少存储权限：调用方可回退 SAF 单文件导出。
  bool get isPermissionDenied => code == 'PERMISSION_DENIED';

  @override
  String toString() => code == null
      ? 'MediaStoreException: $message'
      : 'MediaStoreException($code): $message';
}
