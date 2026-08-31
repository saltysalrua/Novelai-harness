import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import '../models/novelai_models.dart';
import '../services/anlas_calculator.dart';
import '../services/novelai_service.dart';

class NovelAiRepository {
  final NovelAiService _service;
  final List<NaiGeneratedImage> _history = [];

  NovelAiRepository({NovelAiService? service})
    : _service = service ?? NovelAiService();

  List<NaiGeneratedImage> get history => List.unmodifiable(_history);

  /// 大画布布局持久化文件名 (与图片历史同目录)
  static const String kBoardLayoutFileName = 'canvas_board.json';

  /// 大画布参考图存子目录 (仅画布使用，不进入生图历史)
  static const String kBoardRefsDirName = 'board_refs';

  /// 从本地存储目录加载持久化的图像历史记录
  Future<List<NaiGeneratedImage>> loadPersistedHistory({
    required String saveDir,
    int maxImages = 50,
  }) async {
    _history.clear();
    if (saveDir.isEmpty) return List.unmodifiable(_history);

    final historyFile = File(p.join(saveDir, 'image_history.json'));
    if (!historyFile.existsSync()) return List.unmodifiable(_history);

    try {
      final content = await historyFile.readAsString();
      final decoded = jsonDecode(content);
      if (decoded is List) {
        for (final item in decoded) {
          if (_history.length >= maxImages) break;
          if (item is Map<String, dynamic>) {
            final filePath = item['localFilePath'] as String?;
            if (filePath != null && filePath.isNotEmpty) {
              final imgFile = File(filePath);
              if (imgFile.existsSync()) {
                try {
                  final bytes = await imgFile.readAsBytes();
                  _history.add(NaiGeneratedImage.fromJson(item, bytes: bytes));
                } catch (_) {}
              }
            }
          }
        }
      }
    } catch (_) {}
    return List.unmodifiable(_history);
  }

  /// 将当前历史记录保存至本地存储目录 (自动裁剪至 maxImages)。
  /// [enabled] 为 false 时删除持久化文件 (设置页关闭持久化时调用)。
  Future<void> savePersistedHistory({
    required String saveDir,
    int maxImages = 50,
    bool enabled = true,
  }) async {
    if (saveDir.isEmpty) return;
    final historyFile = File(p.join(saveDir, 'image_history.json'));
    if (!enabled) {
      if (historyFile.existsSync()) {
        try {
          historyFile.deleteSync();
        } catch (_) {}
      }
      return;
    }

    if (_history.length > maxImages) {
      _history.removeRange(maxImages, _history.length);
    }

    try {
      final dir = Directory(saveDir);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      final jsonList = _history.map((img) => img.toJson()).toList();
      await historyFile.writeAsString(jsonEncode(jsonList), flush: true);
    } catch (_) {}
  }

  /// 确保保存目录存在并写入图片文件，返回落盘路径 (目录为空或写入失败返回 null)
  String? _writeImageFile(String saveDir, String fileName, List<int> bytes) {
    if (saveDir.isEmpty) return null;
    final dir = Directory(saveDir);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final filePath = p.join(saveDir, fileName);
    try {
      File(filePath).writeAsBytesSync(bytes);
      return filePath;
    } catch (_) {
      return null;
    }
  }

  /// 构造生成结果并插入历史头部
  NaiGeneratedImage _recordGenerated({
    required String id,
    required List<int> bytes,
    String? filePath,
    required NaiGenerationParams params,
    required int seed,
  }) {
    final image = NaiGeneratedImage(
      id: id,
      bytes: bytes,
      localFilePath: filePath,
      params: params,
      createdAt: DateTime.now(),
      seed: seed,
      isOpusFree: params.isOpusFree,
    );
    _history.insert(0, image);
    return image;
  }

  /// 执行流式生图 (实时输出中间去噪步数帧并在最终完成时落盘存入历史)
  Stream<NaiStreamProgress> generateStream({
    required String apiKey,
    required NaiGenerationParams params,
    required String saveDir,
    bool enablePersistence = true,
    int maxImages = 50,
  }) async* {
    final effectiveSeed = params.seed < 0
        ? (DateTime.now().millisecondsSinceEpoch % 4294967295)
        : params.seed;

    final requestParams = params.copyWith(seed: effectiveSeed);

    final stream = _service.generateImageStream(
      apiKey: apiKey,
      params: requestParams,
    );

    await for (final progress in stream) {
      if (progress.isFinal && progress.finalImage != null) {
        final now = DateTime.now();
        final timeStr = DateFormat('yyyyMMdd_HHmmss').format(now);
        final filePath = _writeImageFile(
          saveDir,
          'nai_${timeStr}_$effectiveSeed.png',
          progress.finalImage!,
        );

        final generatedImage = _recordGenerated(
          id: '${now.millisecondsSinceEpoch}_0',
          bytes: progress.finalImage!,
          filePath: filePath,
          params: requestParams,
          seed: effectiveSeed,
        );

        if (enablePersistence && saveDir.isNotEmpty) {
          await savePersistedHistory(saveDir: saveDir, maxImages: maxImages);
        }

        yield NaiStreamProgress.finalResult(
          finalImage: progress.finalImage!,
          generatedImage: generatedImage,
          totalSteps: requestParams.steps,
        );
      } else {
        yield progress;
      }
    }
  }

  /// 执行生图并自动写入本地文件
  Future<List<NaiGeneratedImage>> generate({
    required String apiKey,
    required NaiGenerationParams params,
    required String saveDir,
    bool enablePersistence = true,
    int maxImages = 50,
  }) async {
    final effectiveSeed = params.seed < 0
        ? (DateTime.now().millisecondsSinceEpoch % 4294967295)
        : params.seed;

    final requestParams = params.copyWith(seed: effectiveSeed);
    final imageBytesList = await _service.generateImage(
      apiKey: apiKey,
      params: requestParams,
    );

    final now = DateTime.now();
    final timeStr = DateFormat('yyyyMMdd_HHmmss').format(now);
    final results = <NaiGeneratedImage>[];

    for (var i = 0; i < imageBytesList.length; i++) {
      final bytes = imageBytesList[i];
      final fileName = imageBytesList.length == 1
          ? 'nai_${timeStr}_$effectiveSeed.png'
          : 'nai_${timeStr}_${effectiveSeed}_${i + 1}.png';
      final filePath = _writeImageFile(saveDir, fileName, bytes);

      results.add(
        _recordGenerated(
          id: '${now.millisecondsSinceEpoch}_$i',
          bytes: bytes,
          filePath: filePath,
          params: requestParams,
          seed: effectiveSeed,
        ),
      );
    }

    if (enablePersistence && saveDir.isNotEmpty) {
      await savePersistedHistory(saveDir: saveDir, maxImages: maxImages);
    }

    return results;
  }

  /// 图像超分放大 (官方新超分模型，固定倍率输出)
  Future<NaiGeneratedImage> upscale({
    required String apiKey,
    required NaiGeneratedImage sourceImage,
    required String saveDir,
    bool enablePersistence = true,
    int maxImages = 50,
  }) async {
    final upscaledBytes = await _service.upscaleImage(
      apiKey: apiKey,
      imageBytes: Uint8List.fromList(sourceImage.bytes),
    );

    // 新超分不再接受 scale 参数：以解码出的真实输出尺寸为准
    final resultDims = await AnlasCalculator.decodeImageDimensions(
      upscaledBytes,
    );
    final outWidth = resultDims?.width ?? sourceImage.params.width;
    final outHeight = resultDims?.height ?? sourceImage.params.height;

    final now = DateTime.now();
    final timeStr = DateFormat('yyyyMMdd_HHmmss').format(now);
    final filePath = _writeImageFile(
      saveDir,
      'nai_${timeStr}_upscaled_${sourceImage.seed}.png',
      upscaledBytes,
    );

    final upscaledImage = NaiGeneratedImage(
      id: '${now.millisecondsSinceEpoch}_upscaled',
      bytes: upscaledBytes,
      localFilePath: filePath,
      params: sourceImage.params.copyWith(width: outWidth, height: outHeight),
      createdAt: now,
      seed: sourceImage.seed,
      isOpusFree: false,
    );

    _history.insert(0, upscaledImage);

    if (enablePersistence && saveDir.isNotEmpty) {
      await savePersistedHistory(saveDir: saveDir, maxImages: maxImages);
    }

    return upscaledImage;
  }

  /// 查询 Danbooru Tag 建议
  Future<List<NaiTagSuggestion>> suggestTags({
    required String apiKey,
    required String query,
    NaiModel model = NaiModel.v5Full,
  }) async {
    return await _service.suggestTags(
      apiKey: apiKey,
      query: query,
      model: model,
    );
  }

  /// 查询账号体力池
  Future<NaiAccountInfo> fetchAccountInfo({required String apiKey}) async {
    return await _service.fetchAccountInfo(apiKey: apiKey);
  }

  /// 更新指定图片的批注列表并自动落盘
  Future<NaiGeneratedImage?> updateImageAnnotations({
    required String imageId,
    required List<ImageAnnotation> annotations,
    required String saveDir,
    bool enablePersistence = true,
    int maxImages = 50,
  }) async {
    final index = _history.indexWhere((img) => img.id == imageId);
    if (index < 0) return null;

    final updated = _history[index].copyWith(annotations: annotations);
    _history[index] = updated;

    if (enablePersistence && saveDir.isNotEmpty) {
      await savePersistedHistory(saveDir: saveDir, maxImages: maxImages);
    }
    return updated;
  }

  /// 导入外部参考图片 (从外部拖入、粘贴或文件选择) 并写入历史记录
  Future<NaiGeneratedImage> importReferenceImage({
    required List<int> bytes,
    required int width,
    required int height,
    required String saveDir,
    String? originalFileName,
    bool enablePersistence = true,
    int maxImages = 50,
  }) async {
    final now = DateTime.now();
    final timeStr = DateFormat('yyyyMMdd_HHmmss').format(now);
    final ext = originalFileName != null && originalFileName.contains('.')
        ? p.extension(originalFileName)
        : '.png';
    final fileName =
        'nai_ref_${timeStr}_${now.millisecondsSinceEpoch % 10000}$ext';

    final filePath = _writeImageFile(saveDir, fileName, bytes);

    final image = NaiGeneratedImage(
      id: 'ref_${now.millisecondsSinceEpoch}',
      bytes: bytes,
      localFilePath: filePath,
      params: NaiGenerationParams(
        prompt: '导入参考图',
        width: width > 0 ? width : 1024,
        height: height > 0 ? height : 1024,
      ),
      createdAt: now,
      seed: -1,
      isOpusFree: false,
      isImportedReference: true,
    );

    _history.insert(0, image);

    if (enablePersistence && saveDir.isNotEmpty) {
      await savePersistedHistory(saveDir: saveDir, maxImages: maxImages);
    }

    return image;
  }

  /// 从历史记录中删除单张图片，同步更新持久化 JSON，并可选择是否删除本地文件
  Future<bool> deleteImage({
    required String imageId,
    required String saveDir,
    bool enablePersistence = true,
    int maxImages = 50,
    bool deleteLocalFile = true,
  }) async {
    final index = _history.indexWhere((img) => img.id == imageId);
    if (index < 0) return false;

    final removedImage = _history.removeAt(index);

    if (deleteLocalFile &&
        removedImage.localFilePath != null &&
        removedImage.localFilePath!.isNotEmpty) {
      final file = File(removedImage.localFilePath!);
      if (file.existsSync()) {
        try {
          file.deleteSync();
        } catch (_) {}
      }
    }

    if (enablePersistence && saveDir.isNotEmpty) {
      await savePersistedHistory(saveDir: saveDir, maxImages: maxImages);
    }
    return true;
  }

  /// 清理历史 (传 saveDir 时一并删除持久化索引文件)
  void clearHistory({String? saveDir}) {
    _history.clear();
    if (saveDir != null && saveDir.isNotEmpty) {
      final historyFile = File(p.join(saveDir, 'image_history.json'));
      if (historyFile.existsSync()) {
        try {
          historyFile.deleteSync();
        } catch (_) {}
      }
    }
  }

  // ==================== 自由大画布布局持久化 ====================

  /// 将大画布布局 (节点位置尺寸/便利贴/连线/视口) 写入 canvas_board.json
  ///
  /// [enabled] 为 false 时删除布局文件与 board_refs 目录 (关闭持久化时调用)。
  /// 同时清理 board_refs 下不再被任何节点引用的孤立参考图文件。
  Future<void> saveBoardLayout(
    CanvasBoardData data, {
    required String saveDir,
    bool enabled = true,
  }) async {
    if (saveDir.isEmpty) return;
    final layoutFile = File(p.join(saveDir, kBoardLayoutFileName));
    if (!enabled) {
      await _deleteIfExists(layoutFile);
      await _deleteIfExists(Directory(p.join(saveDir, kBoardRefsDirName)));
      return;
    }

    try {
      final dir = Directory(saveDir);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      await layoutFile.writeAsString(jsonEncode(data.toJson()), flush: true);
      await _pruneBoardRefs(data, saveDir);
    } catch (_) {}
  }

  /// 从 canvas_board.json 恢复大画布布局。
  ///
  /// 图片节点优先按 imageId 从历史记录解析 (主图与历史生图)；
  /// 不在历史里的参考图按 imageFilePath + imageMeta 从磁盘重建。
  Future<CanvasBoardData?> loadBoardLayout({required String saveDir}) async {
    if (saveDir.isEmpty) return null;
    final layoutFile = File(p.join(saveDir, kBoardLayoutFileName));
    if (!layoutFile.existsSync()) return null;

    try {
      final decoded = jsonDecode(await layoutFile.readAsString());
      if (decoded is! Map<String, dynamic>) return null;

      final rawImages = decoded['imageNodes'];
      if (rawImages is! List) return null;
      final imageMap = {for (final img in _history) img.id: img};

      final imageNodes = <CanvasImageNode>[];
      for (final raw in rawImages) {
        if (raw is! Map<String, dynamic>) continue;
        final imgId = raw['imageId'] as String? ?? raw['id'] as String?;
        final image = imageMap[imgId] ?? await _rebuildBoardImageFromFile(raw);
        if (image == null) continue;
        try {
          imageNodes.add(CanvasImageNode.fromJson(raw, image: image));
        } catch (_) {}
      }

      final rawNotes = decoded['noteNodes'];
      final noteNodes = rawNotes is List
          ? rawNotes
                .whereType<Map<String, dynamic>>()
                .map(CanvasNoteNode.fromJson)
                .toList()
          : <CanvasNoteNode>[];

      final rawLinks = decoded['imageLinks'];
      final imageLinks = rawLinks is List
          ? rawLinks
                .whereType<Map<String, dynamic>>()
                .map(CanvasImageLink.fromJson)
                .where(
                  (l) =>
                      l.sourceImageId.isNotEmpty &&
                      l.targetImageId.isNotEmpty &&
                      l.targetAnnotationId.isNotEmpty,
                )
                .toList()
          : <CanvasImageLink>[];

      return CanvasBoardData(
        imageNodes: imageNodes,
        noteNodes: noteNodes,
        imageLinks: imageLinks,
        viewScale: (decoded['viewScale'] as num?)?.toDouble() ?? 1.0,
        viewTx: (decoded['viewTx'] as num?)?.toDouble() ?? 0.0,
        viewTy: (decoded['viewTy'] as num?)?.toDouble() ?? 0.0,
      );
    } catch (_) {
      return null;
    }
  }

  /// 按节点 JSON 中的文件路径与元信息重建参考图 (不在历史记录里的画布参考图)
  Future<NaiGeneratedImage?> _rebuildBoardImageFromFile(
    Map<String, dynamic> raw,
  ) async {
    final filePath = raw['imageFilePath'] as String?;
    if (filePath == null || filePath.isEmpty) return null;
    final file = File(filePath);
    if (!file.existsSync()) return null;

    try {
      final bytes = await file.readAsBytes();
      final meta = (raw['imageMeta'] as Map?)?.cast<String, dynamic>() ?? {};
      final createdAtStr = meta['createdAt'] as String?;
      final imgId = raw['imageId'] as String? ?? raw['id'] as String? ?? '';
      return NaiGeneratedImage(
        id: imgId.isNotEmpty
            ? imgId
            : 'ref-${DateTime.now().millisecondsSinceEpoch}',
        bytes: bytes,
        localFilePath: filePath,
        params: NaiGenerationParams(
          prompt: meta['prompt'] as String? ?? '参考图',
          width: (meta['width'] as num?)?.toInt() ?? 1024,
          height: (meta['height'] as num?)?.toInt() ?? 1024,
        ),
        createdAt: createdAtStr != null
            ? (DateTime.tryParse(createdAtStr) ?? DateTime.now())
            : DateTime.now(),
        seed: (meta['seed'] as num?)?.toInt() ?? -1,
        isOpusFree: false,
        isImportedReference: meta['isImportedReference'] as bool? ?? true,
      );
    } catch (_) {
      return null;
    }
  }

  /// 把参考图字节写入 board_refs 子目录 (纯画布卡片，不进生图历史)
  String? writeBoardReferenceImage(
    List<int> bytes, {
    required String saveDir,
    required String imageId,
    String ext = '.png',
  }) {
    if (saveDir.isEmpty || bytes.isEmpty) return null;
    final refsDir = Directory(p.join(saveDir, kBoardRefsDirName));
    if (!refsDir.existsSync()) {
      refsDir.createSync(recursive: true);
    }
    final safeId = imageId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final normalizedExt = ext.startsWith('.') ? ext : '.$ext';
    final filePath = p.join(refsDir.path, '$safeId$normalizedExt');
    try {
      File(filePath).writeAsBytesSync(bytes);
      return filePath;
    } catch (_) {
      return null;
    }
  }

  /// 清理 board_refs 下不再被任何画布节点引用的孤立参考图文件
  Future<void> _pruneBoardRefs(CanvasBoardData data, String saveDir) async {
    final refsDir = Directory(p.join(saveDir, kBoardRefsDirName));
    if (!refsDir.existsSync()) return;
    final referenced = <String>{};
    for (final node in data.imageNodes) {
      final path = node.image.localFilePath;
      if (path != null &&
          path.isNotEmpty &&
          p.equals(p.dirname(path), refsDir.path)) {
        referenced.add(p.normalize(path));
      }
    }
    try {
      await for (final entity in refsDir.list()) {
        if (entity is! File) continue;
        if (!referenced.contains(p.normalize(entity.path))) {
          await _deleteIfExists(entity);
        }
      }
    } catch (_) {}
  }

  Future<void> _deleteIfExists(FileSystemEntity entity) async {
    try {
      if (entity.existsSync()) {
        await entity.delete(recursive: true);
      }
    } catch (_) {}
  }

  /// 测试专用：直接向历史中注入图片
  @visibleForTesting
  void addImageForTesting(NaiGeneratedImage image) {
    _history.insert(0, image);
  }
}
