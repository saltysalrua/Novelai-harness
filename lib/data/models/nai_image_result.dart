/// NovelAI 生成结果图片与流式生图进度数据模型。
library;

import 'dart:typed_data';

import 'nai_generation_params.dart';

/// 生成结果单张图片数据与元信息
class NaiGeneratedImage {
  final String id;
  final List<int> bytes;
  final String? localFilePath;
  final NaiGenerationParams params;
  final DateTime createdAt;
  final int seed;
  final bool isOpusFree;

  const NaiGeneratedImage({
    required this.id,
    required this.bytes,
    this.localFilePath,
    required this.params,
    required this.createdAt,
    required this.seed,
    required this.isOpusFree,
  });

  /// 缓存并获取 Uint8List 引用 (避免每次重绘创建新对象导致图片重复解码闪烁)
  Uint8List get uint8Bytes =>
      bytes is Uint8List ? (bytes as Uint8List) : Uint8List.fromList(bytes);

  Map<String, dynamic> toJson() => {
    'id': id,
    'localFilePath': localFilePath,
    'params': params.toJson(),
    'createdAt': createdAt.toIso8601String(),
    'seed': seed,
    'isOpusFree': isOpusFree,
  };

  factory NaiGeneratedImage.fromJson(
    Map<String, dynamic> json, {
    List<int>? bytes,
  }) {
    final paramsJson = (json['params'] as Map<String, dynamic>?) ?? {};
    final createdAtStr = json['createdAt'] as String?;
    final createdAt = createdAtStr != null
        ? (DateTime.tryParse(createdAtStr) ?? DateTime.now())
        : DateTime.now();

    return NaiGeneratedImage(
      id: json['id'] as String? ?? '${DateTime.now().millisecondsSinceEpoch}',
      bytes: bytes ?? const [],
      localFilePath: json['localFilePath'] as String?,
      params: NaiGenerationParams.fromJson(paramsJson),
      createdAt: createdAt,
      seed: (json['seed'] as num?)?.toInt() ?? -1,
      isOpusFree: json['isOpusFree'] as bool? ?? false,
    );
  }
}

/// 实时生图流式进度数据模型 (中间去噪步数帧与最终成图)
class NaiStreamProgress {
  final Uint8List? previewImage;
  final int currentStep;
  final int totalSteps;
  final double progress; // 0.0 ~ 1.0
  final bool isFinal;
  final Uint8List? finalImage;
  final NaiGeneratedImage? generatedImage;
  final String? errorMessage;

  const NaiStreamProgress({
    this.previewImage,
    this.currentStep = 0,
    this.totalSteps = 28,
    this.progress = 0.0,
    this.isFinal = false,
    this.finalImage,
    this.generatedImage,
    this.errorMessage,
  });

  factory NaiStreamProgress.intermediate({
    required Uint8List previewImage,
    required int currentStep,
    required int totalSteps,
  }) {
    final progress = totalSteps > 0
        ? (currentStep / totalSteps).clamp(0.0, 0.99)
        : 0.0;
    return NaiStreamProgress(
      previewImage: previewImage,
      currentStep: currentStep,
      totalSteps: totalSteps,
      progress: progress,
      isFinal: false,
    );
  }

  factory NaiStreamProgress.finalResult({
    required Uint8List finalImage,
    NaiGeneratedImage? generatedImage,
    int totalSteps = 28,
  }) {
    return NaiStreamProgress(
      previewImage: finalImage,
      currentStep: totalSteps,
      totalSteps: totalSteps,
      progress: 1.0,
      isFinal: true,
      finalImage: finalImage,
      generatedImage: generatedImage,
    );
  }

  factory NaiStreamProgress.error(String message) {
    return NaiStreamProgress(
      progress: 0.0,
      isFinal: false,
      errorMessage: message,
    );
  }
}
