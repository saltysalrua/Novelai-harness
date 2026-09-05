/// NovelAI 生成结果图片与流式生图进度数据模型。
library;

import 'dart:typed_data';

import 'image_annotation.dart';
import 'nai_generation_params.dart';

/// 历史图片来源结构化标记 (纯枚举，展示文案由 UI 层本地化映射)。
///
/// 用于历史缩略图角标与导出角标等 UI 标识位，取代旧 historyBadgeLabel
/// 直接携带中文字符串的做法 (阶段 4C 数据层文案解耦)。
enum NaiImageProvenance {
  /// 未保存的缓存图片
  unsaved,

  /// 官方超分放大产物
  upscaled,

  /// 局部修复 / 焦点特写产物
  inpainted,

  /// AI 整图编辑产物
  aiEdited,

  /// 外部导入的参考图
  imported,
}

/// 生成结果单张图片数据与元信息 (含批注与参考图标记)
class NaiGeneratedImage {
  final String id;
  final Uint8List bytes;
  final Uint8List? thumbnailBytes;

  /// 正式导出路径；未保存时为缓存路径，不用于选择 UI 原图。
  final String? localFilePath;

  /// 无水印、未脱敏的原图缓存。独立于导出文件，重启后仍用于显示与编辑。
  final String? originalFilePath;

  /// 旧版历史及外部参考图没有独立缓存时，兼容使用原有路径。
  String? get displayFilePath => originalFilePath ?? localFilePath;
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

  /// 是否为局部修复 / 焦点特写的产物 (历史缩略图角标用)
  final bool isInpainted;

  /// 是否为 AI 整图编辑 (外部绘图模型如 nano banana) 的产物 (历史缩略图角标用)
  final bool isAiEdited;

  /// 是否为未保存的缓存图片 (自动保存关闭时生图先落缓存目录，手动保存后置 false)
  final bool isUnsaved;

  const NaiGeneratedImage({
    required this.id,
    required this.bytes,
    this.thumbnailBytes,
    this.localFilePath,
    this.originalFilePath,
    required this.params,
    required this.createdAt,
    required this.seed,
    required this.isOpusFree,
    this.annotations = const [],
    this.isImportedReference = false,
    this.isUpscaled = false,
    this.isInpainted = false,
    this.isAiEdited = false,
    this.isUnsaved = false,
  });

  /// 历史缩略图角标来源：未保存 > 超分图 > 修复图 > AI 编辑图 > 导入图 优先级，普通生成图返回 null。
  /// 纯结构化标记，角标文案由 UI 层本地化 (model_label_l10n.dart)。
  NaiImageProvenance? get provenance {
    if (isUnsaved) return NaiImageProvenance.unsaved;
    if (isUpscaled) return NaiImageProvenance.upscaled;
    if (isInpainted) return NaiImageProvenance.inpainted;
    if (isAiEdited) return NaiImageProvenance.aiEdited;
    if (isImportedReference) return NaiImageProvenance.imported;
    return null;
  }

  /// 直接返回 Uint8List 引用 (杜绝复制与重复分配)
  Uint8List get uint8Bytes => bytes;

  NaiGeneratedImage copyWith({
    String? id,
    Uint8List? bytes,
    Uint8List? thumbnailBytes,
    String? localFilePath,
    String? originalFilePath,
    NaiGenerationParams? params,
    DateTime? createdAt,
    int? seed,
    bool? isOpusFree,
    List<ImageAnnotation>? annotations,
    bool? isImportedReference,
    bool? isUpscaled,
    bool? isInpainted,
    bool? isAiEdited,
    bool? isUnsaved,
  }) {
    return NaiGeneratedImage(
      id: id ?? this.id,
      bytes: bytes ?? this.bytes,
      thumbnailBytes: thumbnailBytes ?? this.thumbnailBytes,
      localFilePath: localFilePath ?? this.localFilePath,
      originalFilePath: originalFilePath ?? this.originalFilePath,
      params: params ?? this.params,
      createdAt: createdAt ?? this.createdAt,
      seed: seed ?? this.seed,
      isOpusFree: isOpusFree ?? this.isOpusFree,
      annotations: annotations ?? this.annotations,
      isImportedReference: isImportedReference ?? this.isImportedReference,
      isUpscaled: isUpscaled ?? this.isUpscaled,
      isInpainted: isInpainted ?? this.isInpainted,
      isAiEdited: isAiEdited ?? this.isAiEdited,
      isUnsaved: isUnsaved ?? this.isUnsaved,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'localFilePath': localFilePath,
    if (originalFilePath != null) 'originalFilePath': originalFilePath,
    'params': params.toJson(),
    'createdAt': createdAt.toIso8601String(),
    'seed': seed,
    'isOpusFree': isOpusFree,
    'annotations': annotations.map((a) => a.toJson()).toList(),
    if (isImportedReference) 'isImportedReference': true,
    if (isUpscaled) 'isUpscaled': true,
    if (isInpainted) 'isInpainted': true,
    if (isAiEdited) 'isAiEdited': true,
    if (isUnsaved) 'isUnsaved': true,
  };

  factory NaiGeneratedImage.fromJson(
    Map<String, dynamic> json, {
    Uint8List? bytes,
    Uint8List? thumbnailBytes,
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
      bytes: bytes ?? Uint8List(0),
      thumbnailBytes: thumbnailBytes,
      localFilePath: json['localFilePath'] as String?,
      originalFilePath: json['originalFilePath'] as String?,
      params: NaiGenerationParams.fromJson(paramsJson),
      createdAt: createdAt,
      seed: (json['seed'] as num?)?.toInt() ?? -1,
      isOpusFree: json['isOpusFree'] as bool? ?? false,
      annotations: annotations,
      isImportedReference: json['isImportedReference'] as bool? ?? false,
      isUpscaled: json['isUpscaled'] as bool? ?? false,
      isInpainted: json['isInpainted'] as bool? ?? false,
      isAiEdited: json['isAiEdited'] as bool? ?? false,
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
