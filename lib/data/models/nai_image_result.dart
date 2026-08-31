/// NovelAI 生成结果图片与流式生图进度数据模型。
library;

import 'dart:typed_data';

import 'image_annotation.dart';
import 'nai_generation_params.dart';

/// 生成结果单张图片数据与元信息 (含批注与参考图标记)
class NaiGeneratedImage {
  final String id;
  final List<int> bytes;
  final String? localFilePath;
  final NaiGenerationParams params;
  final DateTime createdAt;
  final int seed;
  final bool isOpusFree;

  /// 该图片上的批注列表 (持久化保存)
  final List<ImageAnnotation> annotations;

  /// 是否为用户外部拖入/粘贴导入的参考图
  final bool isImportedReference;

  /// 是否为官方超分放大的产物 (历史缩略图角标用)
  final bool isUpscaled;

  /// 是否为未保存的缓存图片 (自动保存关闭时生图先落缓存目录，手动保存后置 false)
  final bool isUnsaved;

  const NaiGeneratedImage({
    required this.id,
    required this.bytes,
    this.localFilePath,
    required this.params,
    required this.createdAt,
    required this.seed,
    required this.isOpusFree,
    this.annotations = const [],
    this.isImportedReference = false,
    this.isUpscaled = false,
    this.isUnsaved = false,
  });

  /// 历史缩略图角标文案：未保存 > 超分图 > 导入图 优先级，普通生成图返回 null
  String? get historyBadgeLabel {
    if (isUnsaved) return '未保存';
    if (isUpscaled) return '放大';
    if (isImportedReference) return '导入';
    return null;
  }

  /// 缓存并获取 Uint8List 引用 (避免每次重绘创建新对象导致图片重复解码闪烁)
  Uint8List get uint8Bytes =>
      bytes is Uint8List ? (bytes as Uint8List) : Uint8List.fromList(bytes);

  NaiGeneratedImage copyWith({
    String? id,
    List<int>? bytes,
    String? localFilePath,
    NaiGenerationParams? params,
    DateTime? createdAt,
    int? seed,
    bool? isOpusFree,
    List<ImageAnnotation>? annotations,
    bool? isImportedReference,
    bool? isUpscaled,
    bool? isUnsaved,
  }) {
    return NaiGeneratedImage(
      id: id ?? this.id,
      bytes: bytes ?? this.bytes,
      localFilePath: localFilePath ?? this.localFilePath,
      params: params ?? this.params,
      createdAt: createdAt ?? this.createdAt,
      seed: seed ?? this.seed,
      isOpusFree: isOpusFree ?? this.isOpusFree,
      annotations: annotations ?? this.annotations,
      isImportedReference: isImportedReference ?? this.isImportedReference,
      isUpscaled: isUpscaled ?? this.isUpscaled,
      isUnsaved: isUnsaved ?? this.isUnsaved,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'localFilePath': localFilePath,
    'params': params.toJson(),
    'createdAt': createdAt.toIso8601String(),
    'seed': seed,
    'isOpusFree': isOpusFree,
    'annotations': annotations.map((a) => a.toJson()).toList(),
    if (isImportedReference) 'isImportedReference': true,
    if (isUpscaled) 'isUpscaled': true,
    if (isUnsaved) 'isUnsaved': true,
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

    final rawAnnotations = json['annotations'];
    final annotations = <ImageAnnotation>[];
    if (rawAnnotations is List) {
      for (final item in rawAnnotations) {
        if (item is Map<String, dynamic>) {
          try {
            annotations.add(ImageAnnotation.fromJson(item));
          } catch (_) {}
        }
      }
    }

    return NaiGeneratedImage(
      id: json['id'] as String? ?? '${DateTime.now().millisecondsSinceEpoch}',
      bytes: bytes ?? const [],
      localFilePath: json['localFilePath'] as String?,
      params: NaiGenerationParams.fromJson(paramsJson),
      createdAt: createdAt,
      seed: (json['seed'] as num?)?.toInt() ?? -1,
      isOpusFree: json['isOpusFree'] as bool? ?? false,
      annotations: annotations,
      isImportedReference: json['isImportedReference'] as bool? ?? false,
      isUpscaled: json['isUpscaled'] as bool? ?? false,
      isUnsaved: json['isUnsaved'] as bool? ?? false,
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
