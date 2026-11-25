/// NovelAI 精准参考 (Precise Reference / Director Reference) 数据模型。
///
/// 协议与模型能力严格对齐 NovelAI 网页端生产实现 (2026-11 V5 Precise Reference)：
/// - V5 Full / Curated：支持角色/角色与风格/风格/服装 4 类参考、
///   `Prefer same outfit` 开关、Strength 0~5.0 (可输负值/超限)、移除 Fidelity
///   (固定 fidelity=1 -> secondary_strength=0)、97 档 1MP 桶裁切预处理；
///   V5 Inpainting 暂不支持；V5 Full 启用参考时强制 High effort。
/// - V4.5 Full / Curated：支持角色/角色与风格/风格 3 类、Strength 0~1.0、
///   Fidelity 0~1.0、三档大尺寸黑底居中预处理、支持 Inpainting。
library;

import 'dart:typed_data';
import 'nai_catalog.dart';

/// 精准参考类型 (UI 可选项)
enum NaiPreciseRefType {
  /// 角色参考 (Character)
  character('character'),

  /// 角色与风格参考 (Character & Style)
  characterAndStyle('character&style'),

  /// 风格参考 (Style)
  style('style'),

  /// 服装参考 (Outfit / API: `costume`，仅 V5 支持)
  outfit('costume');

  final String id;
  const NaiPreciseRefType(this.id);

  /// 该类型在支持服装参考的模型 (V5) 下是否提供「倾向相同服装」开关
  bool get supportsPreferSameOutfit =>
      this == NaiPreciseRefType.character ||
      this == NaiPreciseRefType.characterAndStyle;

  /// 是否仅限支持服装参考的模型 (V5)
  bool get requiresOutfitSupport => this == NaiPreciseRefType.outfit;

  static NaiPreciseRefType fromId(String? id) {
    return switch (id) {
      'character' || 'character_mainoutfit' => NaiPreciseRefType.character,
      'character&style' ||
      'character&style_anyoutfit' => NaiPreciseRefType.characterAndStyle,
      'style' => NaiPreciseRefType.style,
      'costume' || 'outfit' => NaiPreciseRefType.outfit,
      _ => NaiPreciseRefType.characterAndStyle,
    };
  }
}

/// 单张精准参考图条目
class NaiPreciseReference {
  final String id;

  /// 原始参考图字节 (PNG/JPG/WebP，供 UI 预览及按目标模型即时预处理)
  final Uint8List imageBytes;

  /// 原始文件名 (可选，仅用于界面展示)
  final String? fileName;

  /// 参考类型 (默认与官网导入一致: 角色与风格)
  final NaiPreciseRefType type;

  /// 倾向相同服装 (Prefer same outfit，仅 V5 下 character / character&style 生效)。
  ///
  /// 官网导入默认 `character&style` (即 true)；切到 `character` 时默认 false。
  final bool preferSameOutfit;

  /// 参考强度 (默认 1.0；V5 滑块 0~5.0，V4.5 滑块 0~1.0；允许负值或超限输入)
  final double strength;

  /// 保真度 (仅 V4.5 生效，0~1.0，默认 1.0；V5 强制按 1.0 处理，secondary=0.0)
  final double fidelity;

  /// 信息提取度 (官网默认 1.0)
  final double informationExtracted;

  /// 是否启用本参考图
  final bool enabled;

  const NaiPreciseReference({
    required this.id,
    required this.imageBytes,
    this.fileName,
    this.type = NaiPreciseRefType.characterAndStyle,
    this.preferSameOutfit = true,
    this.strength = 1.0,
    this.fidelity = 1.0,
    this.informationExtracted = 1.0,
    this.enabled = true,
  });

  /// 按当前模型能力解析是否应纳入本次请求
  bool isEffectiveFor(NaiModel model, {bool forInpaint = false}) {
    if (!enabled || imageBytes.isEmpty) return false;
    if (!model.supportsPreciseReference) return false;
    if (forInpaint && !model.supportsPreciseReferenceInpainting) return false;
    if (type.requiresOutfitSupport && !model.supportsOutfitReferences) {
      return false;
    }
    return true;
  }

  /// 按官网精确规则映射 `director_reference_descriptions[].caption.base_caption`：
  /// - V5 (`supportsOutfitReferences == true`):
  ///   - character + preferSameOutfit=true  -> `character_mainoutfit`
  ///   - character + preferSameOutfit=false -> `character`
  ///   - characterAndStyle + preferSameOutfit=true  -> `character&style`
  ///   - characterAndStyle + preferSameOutfit=false -> `character&style_anyoutfit`
  ///   - style -> `style`
  ///   - outfit -> `costume`
  /// - V4.5 (`supportsOutfitReferences == false`):
  ///   - character -> `character`
  ///   - characterAndStyle -> `character&style`
  ///   - style -> `style`
  String resolveApiDescription(NaiModel model) {
    final supportsOutfit = model.supportsOutfitReferences;
    return switch (type) {
      NaiPreciseRefType.character =>
        supportsOutfit && preferSameOutfit
            ? 'character_mainoutfit'
            : 'character',
      NaiPreciseRefType.characterAndStyle =>
        supportsOutfit && !preferSameOutfit
            ? 'character&style_anyoutfit'
            : 'character&style',
      NaiPreciseRefType.style => 'style',
      NaiPreciseRefType.outfit => 'costume',
    };
  }

  /// 实际发送给 API 的 secondary_strength 值 (`1.0 - effectiveFidelity`)。
  /// V5 模型移除了 Fidelity，按官网逻辑强制 `fidelity = 1.0`，故恒返回 `0.0`。
  double resolveApiSecondaryStrength(NaiModel model) {
    final effectiveFidelity = model.supportsPreciseReferenceFidelity
        ? fidelity
        : 1.0;
    final secondary = 1.0 - effectiveFidelity;
    // 规避浮点尾差 (如 1.0 - 1.0 或 1.0 - 0.7)
    return double.parse(secondary.toStringAsFixed(6));
  }

  NaiPreciseReference copyWith({
    String? id,
    Uint8List? imageBytes,
    String? fileName,
    NaiPreciseRefType? type,
    bool? preferSameOutfit,
    double? strength,
    double? fidelity,
    double? informationExtracted,
    bool? enabled,
  }) {
    return NaiPreciseReference(
      id: id ?? this.id,
      imageBytes: imageBytes ?? this.imageBytes,
      fileName: fileName ?? this.fileName,
      type: type ?? this.type,
      preferSameOutfit: preferSameOutfit ?? this.preferSameOutfit,
      strength: strength ?? this.strength,
      fidelity: fidelity ?? this.fidelity,
      informationExtracted: informationExtracted ?? this.informationExtracted,
      enabled: enabled ?? this.enabled,
    );
  }
}
