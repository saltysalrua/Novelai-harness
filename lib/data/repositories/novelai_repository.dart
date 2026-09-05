import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Rect;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import '../models/novelai_models.dart';
import '../services/anlas_calculator.dart';
import '../services/image_metadata_service.dart';
import '../services/inpaint_service.dart';
import '../services/isolated_compute.dart';
import '../services/skia_image_codec.dart';
import '../services/watermark_service.dart';
import '../services/novelai_service.dart';
import '../services/image_edit_service.dart';

/// 在独立 isolate 中为持久化历史图片后台生成 ≤240px 缩略图
Map<String, Uint8List> _generateThumbnailsIsolate(
  List<Map<String, String>> tasks,
) {
  final result = <String, Uint8List>{};
  for (final task in tasks) {
    final id = task['id'];
    final path = task['path'];
    if (id == null || path == null) continue;
    try {
      final file = File(path);
      if (!file.existsSync()) continue;
      final bytes = file.readAsBytesSync();
      if (bytes.isEmpty) continue;

      // 小于 50KB 的小型图直接复用为缩略图
      if (bytes.lengthInBytes <= 50 * 1024) {
        result[id] = bytes;
        continue;
      }

      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        result[id] = bytes;
        continue;
      }

      if (decoded.width <= 240 && decoded.height <= 240) {
        result[id] = bytes;
        continue;
      }

      final int targetWidth;
      final int targetHeight;
      if (decoded.width >= decoded.height) {
        targetWidth = 240;
        targetHeight = (240 * decoded.height / decoded.width).round().clamp(
          1,
          240,
        );
      } else {
        targetHeight = 240;
        targetWidth = (240 * decoded.width / decoded.height).round().clamp(
          1,
          240,
        );
      }

      final resized = img.copyResize(
        decoded,
        width: targetWidth,
        height: targetHeight,
        interpolation: img.Interpolation.linear,
      );
      result[id] = Uint8List.fromList(img.encodePng(resized));
    } catch (_) {}
  }
  return result;
}

class NovelAiRepository {
  final NovelAiService _service;
  final ImageEditService _imageEditService;
  final List<NaiGeneratedImage> _history = [];
  static const int maxLruCacheSize = 5;
  final LinkedHashMap<String, Uint8List> _lruImageCache =
      LinkedHashMap<String, Uint8List>();

  NovelAiRepository({
    NovelAiService? service,
    ImageEditService? imageEditService,
  }) : _service = service ?? NovelAiService(),
       _imageEditService = imageEditService ?? ImageEditService();

  List<NaiGeneratedImage> get history => List.unmodifiable(_history);

  /// 当前 LRU 大图缓存快照 (供测试与诊断观察)
  Map<String, Uint8List> get lruImageCache =>
      UnmodifiableMapView(_lruImageCache);

  /// 将大图字节存入 LRU 缓存头部 (MRU)
  void _cacheImageBytes(String id, Uint8List bytes) {
    if (bytes.isEmpty) return;
    _lruImageCache.remove(id);
    _lruImageCache[id] = bytes;
    if (_lruImageCache.length > maxLruCacheSize) {
      _lruImageCache.remove(_lruImageCache.keys.first);
    }
  }

  /// 按需异步加载历史大图完整字节 (优先内存 LRU 缓存，未命中时按磁盘路径加载)
  Future<Uint8List?> loadHistoryImageBytes(NaiGeneratedImage image) async {
    if (image.bytes.isNotEmpty) {
      _cacheImageBytes(image.id, image.bytes);
      return image.bytes;
    }
    final cached = _lruImageCache.remove(image.id);
    if (cached != null) {
      _lruImageCache[image.id] = cached;
      return cached;
    }
    final filePath = image.localFilePath;
    if (filePath == null || filePath.isEmpty) return null;
    final file = File(filePath);
    if (!file.existsSync()) return null;
    try {
      final bytes = await file.readAsBytes();
      _cacheImageBytes(image.id, bytes);
      return bytes;
    } catch (_) {
      return null;
    }
  }

  /// 大画布布局持久化文件名 (与图片历史同目录)
  static const String kBoardLayoutFileName = 'canvas_board.json';

  /// 大画布参考图存子目录 (仅画布使用，不进入生图历史)
  static const String kBoardRefsDirName = 'board_refs';

  /// 未保存图片缓存子目录 (自动保存关闭时生图先落这里，无水印无导出处理)
  static const String kCacheDirName = 'cache';

  /// 解析存储目录对应的缓存目录 (存储目录为空时返回空串，表示不落盘)
  static String cacheDirOf(String saveDir) =>
      saveDir.isEmpty ? '' : p.join(saveDir, kCacheDirName);

  /// 判断文件路径是否位于缓存目录内
  static bool isCacheFilePath(String saveDir, String filePath) {
    final cacheDir = cacheDirOf(saveDir);
    return cacheDir.isNotEmpty &&
        p.equals(p.dirname(filePath), p.normalize(cacheDir));
  }

  /// 从本地存储目录加载持久化的图像历史记录 (仅读 JSON 元信息 + 后台生成缩略图，大图按需懒加载)
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
        final validEntries = <Map<String, dynamic>>[];
        final tasks = <Map<String, String>>[];

        for (final item in decoded) {
          if (validEntries.length >= maxImages) break;
          if (item is Map<String, dynamic>) {
            final filePath = item['localFilePath'] as String?;
            if (filePath != null && filePath.isNotEmpty) {
              final imgFile = File(filePath);
              if (imgFile.existsSync()) {
                validEntries.add(item);
                final id = item['id'] as String? ?? '';
                tasks.add({'id': id, 'path': filePath});
              }
            }
          }
        }

        final thumbnails = tasks.isNotEmpty
            ? await runIsolated(_generateThumbnailsIsolate, tasks)
            : <String, Uint8List>{};

        for (final item in validEntries) {
          final id = item['id'] as String? ?? '';
          final thumb = thumbnails[id];
          _history.add(
            NaiGeneratedImage.fromJson(
              item,
              bytes: Uint8List(0),
              thumbnailBytes: thumb,
            ),
          );
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
      final removed = _history.sublist(maxImages);
      _history.removeRange(maxImages, _history.length);
      // 超出上限的未保存缓存图片直接删除 (已保存文件保留由用户自行管理)
      for (final img in removed) {
        if (!img.isUnsaved) continue;
        final path = img.localFilePath;
        if (path == null || path.isEmpty) continue;
        final file = File(path);
        if (file.existsSync()) {
          try {
            file.deleteSync();
          } catch (_) {}
        }
      }
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
    bool isUnsaved = false,
    bool isUpscaled = false,
    bool isInpainted = false,
    bool isAiEdited = false,
  }) {
    final uBytes = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    _cacheImageBytes(id, uBytes);
    final image = NaiGeneratedImage(
      id: id,
      bytes: uBytes,
      localFilePath: filePath,
      params: params,
      createdAt: DateTime.now(),
      seed: seed,
      isOpusFree: params.isOpusFree,
      isUnsaved: isUnsaved,
      isUpscaled: isUpscaled,
      isInpainted: isInpainted,
      isAiEdited: isAiEdited,
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
    bool stripMetadata = false,
    bool enableWatermark = false,
    bool keepOriginalImage = false,
    WatermarkConfig? watermarkConfig,
    Uint8List? watermarkBytes,
    bool autoSave = true,
  }) async* {
    final effectiveSeed = params.seed < 0 ? generateRandomSeed() : params.seed;

    final requestParams = params.copyWith(seed: effectiveSeed);

    final stream = _service.generateImageStream(
      apiKey: apiKey,
      params: requestParams,
    );

    await for (final progress in stream) {
      if (progress.isFinal && progress.finalImage != null) {
        final now = DateTime.now();
        final timeStr = DateFormat('yyyyMMdd_HHmmss').format(now);
        final rawFinal = ImageMetadataService.embedNovelAiMetadata(
          pngBytes: Uint8List.fromList(progress.finalImage!),
          params: requestParams,
          seed: effectiveSeed,
        );

        // 自动保存关闭时：未保存图片写入缓存目录 (无水印、无导出处理)，
        // 重启后从缓存恢复到 UI 的始终是无水印原图
        if (!autoSave) {
          final cachePath = _writeImageFile(
            cacheDirOf(saveDir),
            'nai_${timeStr}_$effectiveSeed.png',
            rawFinal,
          );

          final generatedImage = _recordGenerated(
            id: '${now.millisecondsSinceEpoch}_0',
            bytes: rawFinal,
            filePath: cachePath,
            params: requestParams,
            seed: effectiveSeed,
            isUnsaved: true,
          );

          if (enablePersistence && saveDir.isNotEmpty) {
            await savePersistedHistory(saveDir: saveDir, maxImages: maxImages);
          }

          yield NaiStreamProgress.finalResult(
            finalImage: rawFinal,
            generatedImage: generatedImage,
            totalSteps: requestParams.steps,
          );
        } else {
          // 若需要处理落盘图片 (去元数据/加水印)
          final needsProcessing =
              stripMetadata ||
              (enableWatermark &&
                  watermarkBytes != null &&
                  watermarkBytes.isNotEmpty);

          if (needsProcessing && keepOriginalImage) {
            // 保存一份原图 (_raw.png)
            _writeImageFile(
              saveDir,
              'nai_${timeStr}_${effectiveSeed}_raw.png',
              rawFinal,
            );
          }

          List<int> fileBytes = rawFinal;
          if (needsProcessing) {
            fileBytes = await WatermarkService.processExportImage(
              rawBytes: Uint8List.fromList(rawFinal),
              stripMetadata: stripMetadata,
              enableWatermark: enableWatermark,
              watermarkConfig: watermarkConfig,
              watermarkBytes: watermarkBytes,
            );
          }

          final filePath = _writeImageFile(
            saveDir,
            'nai_${timeStr}_$effectiveSeed.png',
            fileBytes,
          );

          final generatedImage = _recordGenerated(
            id: '${now.millisecondsSinceEpoch}_0',
            bytes: rawFinal,
            filePath: filePath,
            params: requestParams,
            seed: effectiveSeed,
          );

          if (enablePersistence && saveDir.isNotEmpty) {
            await savePersistedHistory(saveDir: saveDir, maxImages: maxImages);
          }

          yield NaiStreamProgress.finalResult(
            finalImage: rawFinal,
            generatedImage: generatedImage,
            totalSteps: requestParams.steps,
          );
        }
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
    bool stripMetadata = false,
    bool enableWatermark = false,
    bool keepOriginalImage = false,
    WatermarkConfig? watermarkConfig,
    Uint8List? watermarkBytes,
    bool autoSave = true,
  }) async {
    final effectiveSeed = params.seed < 0 ? generateRandomSeed() : params.seed;

    final requestParams = params.copyWith(seed: effectiveSeed);
    final imageBytesList = await _service.generateImage(
      apiKey: apiKey,
      params: requestParams,
    );

    final now = DateTime.now();
    final timeStr = DateFormat('yyyyMMdd_HHmmss').format(now);
    final results = <NaiGeneratedImage>[];
    final needsProcessing =
        stripMetadata ||
        (enableWatermark &&
            watermarkBytes != null &&
            watermarkBytes.isNotEmpty);

    for (var i = 0; i < imageBytesList.length; i++) {
      final rawWithMeta = ImageMetadataService.embedNovelAiMetadata(
        pngBytes: Uint8List.fromList(imageBytesList[i]),
        params: requestParams,
        seed: effectiveSeed,
      );
      final baseName = imageBytesList.length == 1
          ? 'nai_${timeStr}_$effectiveSeed'
          : 'nai_${timeStr}_${effectiveSeed}_${i + 1}';

      // 自动保存关闭时：未保存图片写入缓存目录 (无水印、无导出处理)
      if (!autoSave) {
        final cachePath = _writeImageFile(
          cacheDirOf(saveDir),
          '$baseName.png',
          rawWithMeta,
        );
        results.add(
          _recordGenerated(
            id: '${now.millisecondsSinceEpoch}_$i',
            bytes: rawWithMeta,
            filePath: cachePath,
            params: requestParams,
            seed: effectiveSeed,
            isUnsaved: true,
          ),
        );
        continue;
      }

      if (needsProcessing && keepOriginalImage) {
        _writeImageFile(saveDir, '${baseName}_raw.png', rawWithMeta);
      }

      List<int> fileBytes = rawWithMeta;
      if (needsProcessing) {
        fileBytes = await WatermarkService.processExportImage(
          rawBytes: Uint8List.fromList(rawWithMeta),
          stripMetadata: stripMetadata,
          enableWatermark: enableWatermark,
          watermarkConfig: watermarkConfig,
          watermarkBytes: watermarkBytes,
        );
      }

      final filePath = _writeImageFile(saveDir, '$baseName.png', fileBytes);

      results.add(
        _recordGenerated(
          id: '${now.millisecondsSinceEpoch}_$i',
          bytes: rawWithMeta,
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

  // --------------------------------------------------------------------------
  // 局部修复 / 焦点特写 (共享管线)
  // --------------------------------------------------------------------------

  /// 修复管线共享准备结果：几何、请求源图/蒙版、源图尺寸蒙版与生效参数
  ///
  /// generateInpaintStream 与 generateInpaint 共用这一份单一事实源：
  /// 提示词/模型/步数/CFG 覆盖链 → 源图尺寸蒙版 (画笔描边优先) →
  /// 焦点几何 (1MP 超采样) 或常规请求尺寸 (源图分辨率 64 网格对齐)。
  Future<
    ({
      NaiGenerationParams requestParams,
      int seed,
      bool isFocus,
      InpaintGeometry geometry,
      Uint8List requestSourceBytes,
      Uint8List requestMaskBytes,
      Uint8List sourceMaskBytes,
      int srcW,
      int srcH,
    })
  >
  _prepareInpaintRequest({
    required Uint8List sourceImageBytes,
    required InpaintParams inpaintParams,
    required NaiGenerationParams generationParams,
  }) async {
    final effectiveSeed = generationParams.seed < 0
        ? generateRandomSeed()
        : generationParams.seed;

    final effectivePrompt = inpaintParams.useMainPrompt
        ? generationParams.prompt
        : inpaintParams.customPrompt;
    final effectiveNegative = inpaintParams.useMainNegative
        ? generationParams.negativePrompt
        : inpaintParams.customNegativePrompt;
    final effectiveModel = inpaintParams.customModel ?? generationParams.model;
    final effectiveSteps = inpaintParams.customSteps ?? generationParams.steps;
    final effectiveScale = inpaintParams.customScale ?? generationParams.scale;

    final resolvedDims = await AnlasCalculator.decodeImageDimensions(
      sourceImageBytes,
    );
    final srcW = resolvedDims?.width ?? generationParams.width;
    final srcH = resolvedDims?.height ?? generationParams.height;

    final isFocus = inpaintParams.mode == InpaintMode.focus;

    // 1. 源图尺寸蒙版：画笔描边优先；无描边时焦点模式用生效选区、
    //    常规模式无选区则整图重绘
    final sourceMask = InpaintService.buildSourceMask(
      sourceWidth: srcW,
      sourceHeight: srcH,
      brushStrokes: inpaintParams.brushStrokes,
      selectionRect: isFocus
          ? inpaintParams.effectiveSelectionRect
          : inpaintParams.selectionRect,
    );
    final sourceMaskBytes = await encodeRawRgbaToPng(
      sourceMask.rgba,
      sourceMask.width,
      sourceMask.height,
    );

    // 2. 几何与请求数据
    final InpaintGeometry geometry;
    final int reqW;
    final int reqH;
    final Uint8List requestSourceBytes;
    final Uint8List requestMaskBytes;

    if (isFocus) {
      final pixelRect = Rect.fromLTWH(
        inpaintParams.effectiveSelectionRect.left * srcW,
        inpaintParams.effectiveSelectionRect.top * srcH,
        inpaintParams.effectiveSelectionRect.width * srcW,
        inpaintParams.effectiveSelectionRect.height * srcH,
      );
      geometry = InpaintService.resolveGeometry(
        sourceWidth: srcW,
        sourceHeight: srcH,
        selectionRect: pixelRect,
        contextPadding: inpaintParams.contextPadding,
      );
      final reqData = await InpaintService.prepareFocusedRequestData(
        sourceImageBytes: sourceImageBytes,
        geometry: geometry,
        sourceMask: sourceMask,
      );
      requestSourceBytes = reqData.sourceBytes;
      requestMaskBytes = reqData.maskBytes;
      reqW = geometry.requestWidth;
      reqH = geometry.requestHeight;
    } else {
      final reqSize = InpaintService.resolveStandardRequestSize(srcW, srcH);
      geometry = InpaintGeometry(
        focusBounds: Rect.fromLTWH(0, 0, srcW.toDouble(), srcH.toDouble()),
        contextCrop: Rect.fromLTWH(0, 0, srcW.toDouble(), srcH.toDouble()),
        requestWidth: reqSize.width,
        requestHeight: reqSize.height,
        scale: 1.0,
      );
      final reqData = await InpaintService.prepareStandardRequestData(
        sourceImageBytes: sourceImageBytes,
        requestWidth: reqSize.width,
        requestHeight: reqSize.height,
        sourceMask: sourceMask,
      );
      requestSourceBytes = reqData.sourceBytes;
      requestMaskBytes = reqData.maskBytes;
      reqW = reqSize.width;
      reqH = reqSize.height;
    }

    final requestParams = generationParams.copyWith(
      prompt: effectivePrompt,
      negativePrompt: effectiveNegative,
      model: effectiveModel,
      steps: effectiveSteps,
      scale: effectiveScale,
      width: reqW,
      height: reqH,
      seed: effectiveSeed,
    );

    return (
      requestParams: requestParams,
      seed: effectiveSeed,
      isFocus: isFocus,
      geometry: geometry,
      requestSourceBytes: requestSourceBytes,
      requestMaskBytes: requestMaskBytes,
      sourceMaskBytes: sourceMaskBytes,
      srcW: srcW,
      srcH: srcH,
    );
  }

  /// 将生成补丁按蒙版回贴合成并嵌入元数据
  Future<Uint8List> _compositeInpaintResult({
    required Uint8List sourceImageBytes,
    required ({
      NaiGenerationParams requestParams,
      int seed,
      bool isFocus,
      InpaintGeometry geometry,
      Uint8List requestSourceBytes,
      Uint8List requestMaskBytes,
      Uint8List sourceMaskBytes,
      int srcW,
      int srcH,
    })
    prepared,
    required Uint8List generatedBytes,
  }) async {
    final compositedBytes = prepared.isFocus
        ? await InpaintService.compositeFocusedResult(
            originalSourceBytes: sourceImageBytes,
            generatedPatchBytes: generatedBytes,
            geometry: prepared.geometry,
            sourceMask: await InpaintService.decodeMaskOrNull(
              prepared.sourceMaskBytes,
            ),
          )
        : await InpaintService.compositeStandardResult(
            originalSourceBytes: sourceImageBytes,
            generatedImageBytes: generatedBytes,
            maskBytes: prepared.requestMaskBytes,
          );

    return ImageMetadataService.embedNovelAiMetadata(
      pngBytes: compositedBytes,
      params: prepared.requestParams.copyWith(
        width: prepared.srcW,
        height: prepared.srcH,
      ),
      seed: prepared.seed,
    );
  }

  /// 修复 / AI 编辑结果统一落盘入史 (自动保存分支写缓存目录并带未保存标记)
  ///
  /// [filePrefix] 与 [isAiEdited] 区分 NovelAI 修复与外部绘图模型整图编辑。
  Future<NaiGeneratedImage> _persistInpaintResult({
    required List<int> rawFinal,
    required NaiGenerationParams requestParams,
    required int seed,
    required int srcW,
    required int srcH,
    required String saveDir,
    required bool enablePersistence,
    required int maxImages,
    required bool stripMetadata,
    required bool enableWatermark,
    required bool keepOriginalImage,
    WatermarkConfig? watermarkConfig,
    Uint8List? watermarkBytes,
    required bool autoSave,
    String filePrefix = 'nai_inpaint',
    bool isAiEdited = false,
  }) async {
    final now = DateTime.now();
    final timeStr = DateFormat('yyyyMMdd_HHmmss').format(now);
    final displayParams = requestParams.copyWith(width: srcW, height: srcH);

    // 自动保存关闭时：未保存图片写入缓存目录 (无水印、无导出处理)，
    // 重启后从缓存恢复到 UI 的始终是无水印原图
    if (!autoSave) {
      final cachePath = _writeImageFile(
        cacheDirOf(saveDir),
        '${filePrefix}_${timeStr}_$seed.png',
        rawFinal,
      );
      final generatedImage = _recordGenerated(
        id: '${now.millisecondsSinceEpoch}_inpaint',
        bytes: rawFinal,
        filePath: cachePath,
        params: displayParams,
        seed: seed,
        isUnsaved: true,
        isInpainted: !isAiEdited,
        isAiEdited: isAiEdited,
      );
      if (enablePersistence && saveDir.isNotEmpty) {
        await savePersistedHistory(saveDir: saveDir, maxImages: maxImages);
      }
      return generatedImage;
    }

    final needsProcessing =
        stripMetadata ||
        (enableWatermark &&
            watermarkBytes != null &&
            watermarkBytes.isNotEmpty);

    if (needsProcessing && keepOriginalImage) {
      _writeImageFile(
        saveDir,
        '${filePrefix}_${timeStr}_${seed}_raw.png',
        rawFinal,
      );
    }

    List<int> fileBytes = rawFinal;
    if (needsProcessing) {
      fileBytes = await WatermarkService.processExportImage(
        rawBytes: Uint8List.fromList(rawFinal),
        stripMetadata: stripMetadata,
        enableWatermark: enableWatermark,
        watermarkConfig: watermarkConfig,
        watermarkBytes: watermarkBytes,
      );
    }

    final filePath = _writeImageFile(
      saveDir,
      '${filePrefix}_${timeStr}_$seed.png',
      fileBytes,
    );
    final generatedImage = _recordGenerated(
      id: '${now.millisecondsSinceEpoch}_inpaint',
      bytes: rawFinal,
      filePath: filePath,
      params: displayParams,
      seed: seed,
      isInpainted: !isAiEdited,
      isAiEdited: isAiEdited,
    );

    if (enablePersistence && saveDir.isNotEmpty) {
      await savePersistedHistory(saveDir: saveDir, maxImages: maxImages);
    }
    return generatedImage;
  }

  /// 执行局部修复 / 焦点特写流式生成
  Stream<NaiStreamProgress> generateInpaintStream({
    required String apiKey,
    required Uint8List sourceImageBytes,
    required InpaintParams inpaintParams,
    required NaiGenerationParams generationParams,
    required String saveDir,
    bool enablePersistence = true,
    int maxImages = 50,
    bool stripMetadata = false,
    bool enableWatermark = false,
    bool keepOriginalImage = false,
    WatermarkConfig? watermarkConfig,
    Uint8List? watermarkBytes,
    bool autoSave = true,
  }) async* {
    final prepared = await _prepareInpaintRequest(
      sourceImageBytes: sourceImageBytes,
      inpaintParams: inpaintParams,
      generationParams: generationParams,
    );

    final stream = _service.generateInfillStream(
      apiKey: apiKey,
      params: prepared.requestParams,
      sourceBytes: prepared.requestSourceBytes,
      maskBytes: prepared.requestMaskBytes,
      requestWidth: prepared.requestParams.width,
      requestHeight: prepared.requestParams.height,
      strength: inpaintParams.strength,
      noise: inpaintParams.noise,
    );

    await for (final progress in stream) {
      if (progress.isFinal && progress.finalImage != null) {
        final rawFinal = await _compositeInpaintResult(
          sourceImageBytes: sourceImageBytes,
          prepared: prepared,
          generatedBytes: Uint8List.fromList(progress.finalImage!),
        );
        final generatedImage = await _persistInpaintResult(
          rawFinal: rawFinal,
          requestParams: prepared.requestParams,
          seed: prepared.seed,
          srcW: prepared.srcW,
          srcH: prepared.srcH,
          saveDir: saveDir,
          enablePersistence: enablePersistence,
          maxImages: maxImages,
          stripMetadata: stripMetadata,
          enableWatermark: enableWatermark,
          keepOriginalImage: keepOriginalImage,
          watermarkConfig: watermarkConfig,
          watermarkBytes: watermarkBytes,
          autoSave: autoSave,
        );
        yield NaiStreamProgress.finalResult(
          finalImage: rawFinal,
          generatedImage: generatedImage,
          totalSteps: prepared.requestParams.steps,
        );
      } else {
        yield progress;
      }
    }
  }

  /// 执行局部修复 / 焦点特写生成 (标准归档模式)
  Future<NaiGeneratedImage> generateInpaint({
    required String apiKey,
    required Uint8List sourceImageBytes,
    required InpaintParams inpaintParams,
    required NaiGenerationParams generationParams,
    required String saveDir,
    bool enablePersistence = true,
    int maxImages = 50,
    bool stripMetadata = false,
    bool enableWatermark = false,
    bool keepOriginalImage = false,
    WatermarkConfig? watermarkConfig,
    Uint8List? watermarkBytes,
    bool autoSave = true,
  }) async {
    final prepared = await _prepareInpaintRequest(
      sourceImageBytes: sourceImageBytes,
      inpaintParams: inpaintParams,
      generationParams: generationParams,
    );

    final imageBytesList = await _service.generateInfill(
      apiKey: apiKey,
      params: prepared.requestParams,
      sourceBytes: prepared.requestSourceBytes,
      maskBytes: prepared.requestMaskBytes,
      requestWidth: prepared.requestParams.width,
      requestHeight: prepared.requestParams.height,
      strength: inpaintParams.strength,
      noise: inpaintParams.noise,
    );

    if (imageBytesList.isEmpty) {
      throw StateError('局部重绘未返回有效图像。');
    }

    final rawFinal = await _compositeInpaintResult(
      sourceImageBytes: sourceImageBytes,
      prepared: prepared,
      generatedBytes: imageBytesList.first,
    );

    return _persistInpaintResult(
      rawFinal: rawFinal,
      requestParams: prepared.requestParams,
      seed: prepared.seed,
      srcW: prepared.srcW,
      srcH: prepared.srcH,
      saveDir: saveDir,
      enablePersistence: enablePersistence,
      maxImages: maxImages,
      stripMetadata: stripMetadata,
      enableWatermark: enableWatermark,
      keepOriginalImage: keepOriginalImage,
      watermarkConfig: watermarkConfig,
      watermarkBytes: watermarkBytes,
      autoSave: autoSave,
    );
  }

  /// AI 整图编辑：把整张图片发给外部绘图模型 (如 nano banana) 按指令重绘
  ///
  /// 不消耗 Anlas 点数 (计费走绘图模型供应商)，结果带 isAiEdited 标记入史。
  Future<NaiGeneratedImage> editImageAi({
    required LlmProviderConfig provider,
    required String modelId,
    required String prompt,
    required Uint8List sourceImageBytes,
    required NaiGenerationParams generationParams,
    String aspectRatio = '',
    String imageResolution = '',
    required String saveDir,
    bool enablePersistence = true,
    int maxImages = 50,
    bool stripMetadata = false,
    bool enableWatermark = false,
    bool keepOriginalImage = false,
    WatermarkConfig? watermarkConfig,
    Uint8List? watermarkBytes,
    bool autoSave = true,
  }) async {
    if (prompt.trim().isEmpty) {
      throw StateError('请输入 AI 整图编辑的修改指令。');
    }

    final result = await _imageEditService.editImage(
      baseUrl: provider.baseUrl,
      apiKey: provider.apiKey,
      modelId: modelId,
      prompt: prompt.trim(),
      imageBytes: sourceImageBytes,
      aspectRatio: aspectRatio,
      imageResolution: imageResolution,
    );

    // 以真实字节解码分辨率为准 (导入图 / 修复图 params 可能是假宽高)
    final dims = await AnlasCalculator.decodeImageDimensions(result.imageBytes);
    final srcW = dims?.width ?? generationParams.width;
    final srcH = dims?.height ?? generationParams.height;

    final displayParams = generationParams.copyWith(
      prompt: prompt.trim(),
      width: srcW,
      height: srcH,
    );
    final seed = generateRandomSeed();

    return _persistInpaintResult(
      rawFinal: result.imageBytes,
      requestParams: displayParams,
      seed: seed,
      srcW: srcW,
      srcH: srcH,
      saveDir: saveDir,
      enablePersistence: enablePersistence,
      maxImages: maxImages,
      stripMetadata: stripMetadata,
      enableWatermark: enableWatermark,
      keepOriginalImage: keepOriginalImage,
      watermarkConfig: watermarkConfig,
      watermarkBytes: watermarkBytes,
      autoSave: autoSave,
      filePrefix: 'nai_ai_edit',
      isAiEdited: true,
    );
  }

  /// 图像超分放大 (官方新超分模型，固定倍率输出)
  Future<NaiGeneratedImage> upscale({
    required String apiKey,
    required NaiGeneratedImage sourceImage,
    required String saveDir,
    bool enablePersistence = true,
    int maxImages = 50,
    bool stripMetadata = false,
    bool enableWatermark = false,
    bool keepOriginalImage = false,
    WatermarkConfig? watermarkConfig,
    Uint8List? watermarkBytes,
    bool autoSave = true,
  }) async {
    final srcBytes = sourceImage.bytes.isNotEmpty
        ? sourceImage.bytes
        : (await loadHistoryImageBytes(sourceImage) ?? sourceImage.bytes);
    final upscaledBytes = await _service.upscaleImage(
      apiKey: apiKey,
      imageBytes: srcBytes,
    );

    // 新超分不再接受 scale 参数：以解码出的真实输出尺寸为准
    final resultDims = await AnlasCalculator.decodeImageDimensions(
      upscaledBytes,
    );
    final outWidth = resultDims?.width ?? sourceImage.params.width;
    final outHeight = resultDims?.height ?? sourceImage.params.height;

    final now = DateTime.now();
    final timeStr = DateFormat('yyyyMMdd_HHmmss').format(now);
    final baseName = 'nai_${timeStr}_upscaled_${sourceImage.seed}';

    String? filePath;
    final bool isUnsaved;
    if (!autoSave) {
      // 自动保存关闭时：超分结果同样先落缓存目录 (无水印、无导出处理)
      filePath = _writeImageFile(
        cacheDirOf(saveDir),
        '$baseName.png',
        upscaledBytes,
      );
      isUnsaved = true;
    } else {
      final needsProcessing =
          stripMetadata ||
          (enableWatermark &&
              watermarkBytes != null &&
              watermarkBytes.isNotEmpty);

      if (needsProcessing && keepOriginalImage) {
        _writeImageFile(saveDir, '${baseName}_raw.png', upscaledBytes);
      }

      List<int> fileBytes = upscaledBytes;
      if (needsProcessing) {
        fileBytes = await WatermarkService.processExportImage(
          rawBytes: upscaledBytes,
          stripMetadata: stripMetadata,
          enableWatermark: enableWatermark,
          watermarkConfig: watermarkConfig,
          watermarkBytes: watermarkBytes,
        );
      }

      filePath = _writeImageFile(saveDir, '$baseName.png', fileBytes);
      isUnsaved = false;
    }

    final upscaledImage = NaiGeneratedImage(
      id: '${now.millisecondsSinceEpoch}_upscaled',
      bytes: upscaledBytes,
      localFilePath: filePath,
      params: sourceImage.params.copyWith(width: outWidth, height: outHeight),
      createdAt: now,
      seed: sourceImage.seed,
      isOpusFree: false,
      isImportedReference: sourceImage.isImportedReference,
      isUpscaled: true,
      isUnsaved: isUnsaved,
    );

    _history.insert(0, upscaledImage);
    _cacheImageBytes(upscaledImage.id, upscaledBytes);

    if (enablePersistence && saveDir.isNotEmpty) {
      await savePersistedHistory(saveDir: saveDir, maxImages: maxImages);
    }

    return upscaledImage;
  }

  /// 手动保存未保存 (缓存) 图片到本地存储目录 (自动保存关闭时画板保存按钮专用)。
  ///
  /// 按全局导出设置处理元数据与水印后写入存储目录，删除旧缓存文件，
  /// 并把历史条目标记为已保存；返回更新后的图片 (未找到或无存储目录时返回 null)。
  Future<NaiGeneratedImage?> saveUnsavedImageToDisk({
    required String imageId,
    required String saveDir,
    bool enablePersistence = true,
    int maxImages = 50,
    bool stripMetadata = false,
    bool enableWatermark = false,
    bool keepOriginalImage = false,
    WatermarkConfig? watermarkConfig,
    Uint8List? watermarkBytes,
  }) async {
    final index = _history.indexWhere((img) => img.id == imageId);
    if (index < 0) return null;

    final image = _history[index];
    if (!image.isUnsaved) return image;
    if (saveDir.isEmpty) return null;

    final now = DateTime.now();
    final timeStr = DateFormat('yyyyMMdd_HHmmss').format(now);
    final baseName = 'nai_${timeStr}_${image.seed}';
    final rawBytes = image.bytes.isNotEmpty
        ? image.bytes
        : (await loadHistoryImageBytes(image) ?? image.bytes);

    final needsProcessing =
        stripMetadata ||
        (enableWatermark &&
            watermarkBytes != null &&
            watermarkBytes.isNotEmpty);

    if (needsProcessing && keepOriginalImage) {
      // 保存一份无处理原图 (_raw.png)
      _writeImageFile(saveDir, '${baseName}_raw.png', rawBytes);
    }

    List<int> fileBytes = rawBytes;
    if (needsProcessing) {
      fileBytes = await WatermarkService.processExportImage(
        rawBytes: rawBytes,
        stripMetadata: stripMetadata,
        enableWatermark: enableWatermark,
        watermarkConfig: watermarkConfig,
        watermarkBytes: watermarkBytes,
      );
    }

    final filePath = _writeImageFile(saveDir, '$baseName.png', fileBytes);
    if (filePath == null) return null;

    // 删除旧缓存文件 (图片已正式落盘保存)
    final oldPath = image.localFilePath;
    if (oldPath != null && oldPath.isNotEmpty) {
      final oldFile = File(oldPath);
      if (oldFile.existsSync()) {
        try {
          oldFile.deleteSync();
        } catch (_) {}
      }
    }

    final updated = image.copyWith(
      bytes: rawBytes,
      localFilePath: filePath,
      isUnsaved: false,
    );
    _history[index] = updated;
    _cacheImageBytes(updated.id, rawBytes);

    if (enablePersistence) {
      await savePersistedHistory(saveDir: saveDir, maxImages: maxImages);
    }
    return updated;
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
    final uBytes = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);

    final image = NaiGeneratedImage(
      id: 'ref_${now.millisecondsSinceEpoch}',
      bytes: uBytes,
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
    _cacheImageBytes(image.id, uBytes);

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

    _lruImageCache.remove(imageId);
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
    _lruImageCache.clear();
    if (saveDir != null && saveDir.isNotEmpty) {
      final historyFile = File(p.join(saveDir, 'image_history.json'));
      if (historyFile.existsSync()) {
        try {
          historyFile.deleteSync();
        } catch (_) {}
      }
    }
  }

  /// 一键清空全部历史图片：清空内存历史并移除持久化索引。
  ///
  /// [autoSave] 为 true (自动保存开启) 时仅清空界面记录，本地已保存的
  /// 图片文件全部保留；为 false (手动保存模式) 时一并删除缓存目录中的
  /// 未保存图片 (右键菜单「清空历史记录」专用)。
  Future<void> clearAllHistory({
    String? saveDir,
    bool enablePersistence = true,
    bool autoSave = false,
  }) async {
    if (saveDir != null && saveDir.isNotEmpty && !autoSave) {
      await _deleteIfExists(Directory(cacheDirOf(saveDir)));
    }
    clearHistory(saveDir: (enablePersistence ? saveDir : null));
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
    if (image.bytes.isNotEmpty) {
      _cacheImageBytes(image.id, image.bytes);
    }
  }
}
