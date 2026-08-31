import 'dart:typed_data';
import 'package:flutter/foundation.dart';

/// 统一解析后的图像元数据模型 (支持 NovelAI、WebUI、ComfyUI、InvokeAI 等)
class ImageMetadataResult {
  final String prompt;
  final String negativePrompt;
  final int? seed;
  final String? sampler;
  final int? steps;
  final double? scale;
  final double? cfgRescale;
  final int? width;
  final int? height;
  final String? model;
  final String? noiseSchedule;
  final bool? qualityToggle;
  final String? qualityPreset;
  final String? ucPreset;
  final bool? transparentBackground;
  final String software;
  final String? source;
  final List<String> characterPrompts;
  final List<String> characterNegativePrompts;
  final String rawJson;

  const ImageMetadataResult({
    this.prompt = '',
    this.negativePrompt = '',
    this.seed,
    this.sampler,
    this.steps,
    this.scale,
    this.cfgRescale,
    this.width,
    this.height,
    this.model,
    this.noiseSchedule,
    this.qualityToggle,
    this.qualityPreset,
    this.ucPreset,
    this.transparentBackground,
    this.software = 'NovelAI',
    this.source,
    this.characterPrompts = const [],
    this.characterNegativePrompts = const [],
    this.rawJson = '',
  });

  bool get hasData =>
      prompt.trim().isNotEmpty ||
      negativePrompt.trim().isNotEmpty ||
      seed != null ||
      (steps != null && steps! > 0) ||
      (model != null && model!.isNotEmpty && model != 'Unknown');

  Map<String, dynamic> toJson() => {
    'prompt': prompt,
    'negativePrompt': negativePrompt,
    'seed': seed,
    'sampler': sampler,
    'steps': steps,
    'scale': scale,
    'cfgRescale': cfgRescale,
    'width': width,
    'height': height,
    'model': model,
    'noiseSchedule': noiseSchedule,
    'qualityToggle': qualityToggle,
    'qualityPreset': qualityPreset,
    'ucPreset': ucPreset,
    'transparentBackground': transparentBackground,
    'software': software,
    'source': source,
    'characterPrompts': characterPrompts,
    'characterNegativePrompts': characterNegativePrompts,
    'rawJson': rawJson,
  };

  factory ImageMetadataResult.fromJson(Map<String, dynamic> json) {
    return ImageMetadataResult(
      prompt: json['prompt'] as String? ?? '',
      negativePrompt: json['negativePrompt'] as String? ?? '',
      seed: (json['seed'] as num?)?.toInt(),
      sampler: json['sampler'] as String?,
      steps: (json['steps'] as num?)?.toInt(),
      scale: (json['scale'] as num?)?.toDouble(),
      cfgRescale: (json['cfgRescale'] as num?)?.toDouble(),
      width: (json['width'] as num?)?.toInt(),
      height: (json['height'] as num?)?.toInt(),
      model: json['model'] as String?,
      noiseSchedule: json['noiseSchedule'] as String?,
      qualityToggle: json['qualityToggle'] as bool?,
      qualityPreset: json['qualityPreset'] as String?,
      ucPreset: json['ucPreset'] as String?,
      transparentBackground: json['transparentBackground'] as bool?,
      software: json['software'] as String? ?? 'NovelAI',
      source: json['source'] as String?,
      characterPrompts:
          (json['characterPrompts'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      characterNegativePrompts:
          (json['characterNegativePrompts'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      rawJson: json['rawJson'] as String? ?? '',
    );
  }
}

/// 水印设置配置模型
class WatermarkConfig {
  final bool enabled;
  final String? imagePath;
  final Uint8List? imageBytes;

  /// 水印相对位置 X (0.0 = 左, 1.0 = 右，默认 1.0 右下)
  final double posX;

  /// 水印相对位置 Y (0.0 = 顶, 1.0 = 底，默认 1.0 右下)
  final double posY;

  /// 缩放百分比 (1.0 ~ 100.0%, 默认 15.0%)
  final double scalePercent;

  /// 不透明度 (0.0 ~ 1.0, 默认 0.8)
  final double opacity;

  /// 边距百分比 (0.0 ~ 50.0%, 默认 2.0%)
  final double marginPercent;

  /// 自动对比度：按水印下方背景亮度自动加深/提亮水印，保证可见性
  final bool autoContrast;

  /// 智能选位：每次合成时基于图像内容自动选择信息量最低的位置 (覆盖 posX/posY)
  final bool autoPosition;

  /// 盲水印开关 (DCT 频域隐形水印，肉眼不可见)
  final bool blindEnabled;

  /// 盲水印载荷文本 (签名/版权信息)
  final String blindText;

  /// 盲水印强度 1~5 (强度越高越抗压缩，但对画质扰动略增)
  final int blindStrength;

  const WatermarkConfig({
    this.enabled = false,
    this.imagePath,
    this.imageBytes,
    this.posX = 1.0,
    this.posY = 1.0,
    this.scalePercent = 15.0,
    this.opacity = 0.8,
    this.marginPercent = 2.0,
    this.autoContrast = false,
    this.autoPosition = false,
    this.blindEnabled = false,
    this.blindText = '',
    this.blindStrength = 3,
  });

  WatermarkConfig copyWith({
    bool? enabled,
    String? imagePath,
    Uint8List? imageBytes,
    bool clearImage = false,
    double? posX,
    double? posY,
    double? scalePercent,
    double? opacity,
    double? marginPercent,
    bool? autoContrast,
    bool? autoPosition,
    bool? blindEnabled,
    String? blindText,
    int? blindStrength,
  }) {
    return WatermarkConfig(
      enabled: enabled ?? this.enabled,
      imagePath: clearImage ? null : (imagePath ?? this.imagePath),
      imageBytes: clearImage ? null : (imageBytes ?? this.imageBytes),
      posX: posX ?? this.posX,
      posY: posY ?? this.posY,
      scalePercent: scalePercent ?? this.scalePercent,
      opacity: opacity ?? this.opacity,
      marginPercent: marginPercent ?? this.marginPercent,
      autoContrast: autoContrast ?? this.autoContrast,
      autoPosition: autoPosition ?? this.autoPosition,
      blindEnabled: blindEnabled ?? this.blindEnabled,
      blindText: blindText ?? this.blindText,
      blindStrength: blindStrength ?? this.blindStrength,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'imagePath': imagePath,
    'posX': posX,
    'posY': posY,
    'scalePercent': scalePercent,
    'opacity': opacity,
    'marginPercent': marginPercent,
    'autoContrast': autoContrast,
    'autoPosition': autoPosition,
    'blindEnabled': blindEnabled,
    'blindText': blindText,
    'blindStrength': blindStrength,
  };

  factory WatermarkConfig.fromJson(Map<String, dynamic> json) {
    return WatermarkConfig(
      enabled: json['enabled'] as bool? ?? false,
      imagePath: json['imagePath'] as String?,
      posX: (json['posX'] as num?)?.toDouble() ?? 1.0,
      posY: (json['posY'] as num?)?.toDouble() ?? 1.0,
      scalePercent: (json['scalePercent'] as num?)?.toDouble() ?? 15.0,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 0.8,
      marginPercent: (json['marginPercent'] as num?)?.toDouble() ?? 2.0,
      autoContrast: json['autoContrast'] as bool? ?? false,
      autoPosition: json['autoPosition'] as bool? ?? false,
      blindEnabled: json['blindEnabled'] as bool? ?? false,
      blindText: json['blindText'] as String? ?? '',
      blindStrength: (json['blindStrength'] as num?)?.toInt() ?? 3,
    );
  }
}
