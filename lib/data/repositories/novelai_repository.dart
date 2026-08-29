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

  /// 执行生图并自动写入本地文件
  Future<List<NaiGeneratedImage>> generate({
    required String apiKey,
    required NaiGenerationParams params,
    required String saveDir,
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

    // 确保保存目录存在
    if (saveDir.isNotEmpty) {
      final dir = Directory(saveDir);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
    }

    for (int i = 0; i < imageBytesList.length; i++) {
      final bytes = imageBytesList[i];
      final id = '${now.millisecondsSinceEpoch}_$i';
      String? filePath;

      if (saveDir.isNotEmpty) {
        final fileName = imageBytesList.length == 1
            ? 'nai_${timeStr}_$effectiveSeed.png'
            : 'nai_${timeStr}_${effectiveSeed}_${i + 1}.png';
        filePath = p.join(saveDir, fileName);
        try {
          File(filePath).writeAsBytesSync(bytes);
        } catch (_) {}
      }

      final image = NaiGeneratedImage(
        id: id,
        bytes: bytes,
        localFilePath: filePath,
        params: requestParams,
        createdAt: now,
        seed: effectiveSeed,
        isOpusFree: requestParams.isOpusFree,
      );

      _history.insert(0, image);
      results.add(image);
    }

    return results;
  }

  /// 图像超分放大 (2x / 4x)
  Future<NaiGeneratedImage> upscale({
    required String apiKey,
    required NaiGeneratedImage sourceImage,
    int scale = 4,
    required String saveDir,
  }) async {
    final upscaledBytes = await _service.upscaleImage(
      apiKey: apiKey,
      imageBytes: Uint8List.fromList(sourceImage.bytes),
      scale: scale,
    );

    final now = DateTime.now();
    final timeStr = DateFormat('yyyyMMdd_HHmmss').format(now);
    final id = '${now.millisecondsSinceEpoch}_upscaled';
    String? filePath;

    if (saveDir.isNotEmpty) {
      final fileName = 'nai_${timeStr}_upscaled_${scale}x_${sourceImage.seed}.png';
      filePath = p.join(saveDir, fileName);
      try {
        File(filePath).writeAsBytesSync(upscaledBytes);
      } catch (_) {}
    }

    final upscaledImage = NaiGeneratedImage(
      id: id,
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

  /// 清理历史
  void clearHistory() {
    _history.clear();
  }
}
