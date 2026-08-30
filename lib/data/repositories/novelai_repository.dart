import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import '../models/novelai_models.dart';
import '../services/novelai_service.dart';

class NovelAiRepository {
  final NovelAiService _service;
  final List<NaiGeneratedImage> _history = [];

  NovelAiRepository({NovelAiService? service})
    : _service = service ?? NovelAiService();

  List<NaiGeneratedImage> get history => List.unmodifiable(_history);

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

  /// 图像超分放大 (2x / 4x)
  Future<NaiGeneratedImage> upscale({
    required String apiKey,
    required NaiGeneratedImage sourceImage,
    int scale = 4,
    required String saveDir,
    bool enablePersistence = true,
    int maxImages = 50,
  }) async {
    final upscaledBytes = await _service.upscaleImage(
      apiKey: apiKey,
      imageBytes: Uint8List.fromList(sourceImage.bytes),
      scale: scale,
    );

    final now = DateTime.now();
    final timeStr = DateFormat('yyyyMMdd_HHmmss').format(now);
    final filePath = _writeImageFile(
      saveDir,
      'nai_${timeStr}_upscaled_${scale}x_${sourceImage.seed}.png',
      upscaledBytes,
    );

    final upscaledImage = NaiGeneratedImage(
      id: '${now.millisecondsSinceEpoch}_upscaled',
      bytes: upscaledBytes,
      localFilePath: filePath,
      params: sourceImage.params.copyWith(
        width: sourceImage.params.width * scale,
        height: sourceImage.params.height * scale,
      ),
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
}
