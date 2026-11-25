/// NovelAI Vibe Transfer (风格迁移 / 氛围参考) 数据模型。
///
/// 严格对齐 NovelAI 网页端与官方文件规范：
/// - V4 / V4.5：编码式 Vibe Transfer (走 `/ai/encode-vibe` 获取向量编码，
///   或直接导入 `.naiv4vibe` / `.naiv4vibebundle` / 带内嵌编码的 PNG 零编码费)；
///   支持 `normalize_reference_strength_multiple` 强度归一化；
///   1~4 张免生成附加费，第 5 张起每多 1 张每张成图 +2 Anlas。
/// - V3 / Furry V3：原图式 Vibe Transfer (448×448 黑底居中 PNG base64 +
///   `reference_information_extracted_multiple` + `reference_strength_multiple`)。
/// - V5：官网目前未开放 Vibe Transfer (`supportsVibeTransfer == false`)。
/// - 互斥规则：V4.5 下启用精准参考时自动屏蔽 Vibe Transfer；Inpainting 不支持 Vibe Transfer。
library;

import 'dart:typed_data';
import 'nai_catalog.dart';

/// Vibe 参考数据来源
enum NaiVibeSourceType {
  /// 普通原始图片 (V4/V4.5 需服务端编码 +2 Anlas；V3 直接缩放发送)
  rawImage,

  /// 官方 `.naiv4vibe` 单文件 (通常含预编码数据)
  naiv4vibe,

  /// 官方 `.naiv4vibebundle` 批量包解出的条目
  naiv4vibebundle,

  /// 携带官方 iTXt (`NovelAI_Vibe_Encoding_Base64` / `naidata`) 的 PNG
  pngEmbedded,
}

/// 单条 Vibe Transfer 参考配置
class NaiVibeReference {
  static const double defaultStrength = 0.6;
  static const double defaultInfoExtracted = 1.0;

  final String id;

  /// 显示名称 (文件名或 .naiv4vibe 内的 name)
  final String displayName;

  /// 数据来源类型
  final NaiVibeSourceType sourceType;

  /// 原始图片字节 (用于 V3 直传、V4/V4.5 编码或修改信息提取度后重新编码；
  /// 部分纯编码 `.naiv4vibe` 文件可能为 null)
  final Uint8List? rawImageBytes;

  /// 预览缩略图字节 (优先显示缩略图，回退原图)
  final Uint8List? thumbnailBytes;

  /// 按模型 ID (`NaiModel.id`) 缓存的 Base64 编码结果
  final Map<String, String> encodingsByModel;

  /// 各模型已编码时对应的 `information_extracted` 值；
  /// 若用户改动了 [informationExtracted] 且持有原图，则自动触发重新编码。
  final Map<String, double> encodedInfoExtractedByModel;

  /// 参考强度 (滑块 0.0~1.0，支持负值或超限输入)
  final double strength;

  /// 信息提取度 (0.01~1.0)
  final double informationExtracted;

  /// 是否参与本次生成
  final bool enabled;

  const NaiVibeReference({
    required this.id,
    required this.displayName,
    this.sourceType = NaiVibeSourceType.rawImage,
    this.rawImageBytes,
    this.thumbnailBytes,
    this.encodingsByModel = const {},
    this.encodedInfoExtractedByModel = const {},
    this.strength = defaultStrength,
    this.informationExtracted = defaultInfoExtracted,
    this.enabled = true,
  });

  /// 用于 UI 展示的缩略图字节
  Uint8List? get previewBytes =>
      (thumbnailBytes != null && thumbnailBytes!.isNotEmpty)
      ? thumbnailBytes
      : ((rawImageBytes != null && rawImageBytes!.isNotEmpty)
            ? rawImageBytes
            : null);

  /// 是否拥有原始图，可用于编码或调整信息提取度后重新编码
  bool get hasRawImage => rawImageBytes != null && rawImageBytes!.isNotEmpty;

  /// 获取目标模型下可直接复用的有效预编码；无可用编码或需重编时返回 null。
  String? resolveEncodingFor(NaiModel model) {
    if (!model.usesEncodedVibeTransfer) return null;
    final cached = encodingsByModel[model.id];
    if (cached == null || cached.isEmpty) return null;

    // 没有原图时无法重编码，始终直接使用已有编码
    if (!hasRawImage) return cached;

    final encodedInfo = encodedInfoExtractedByModel[model.id];
    if (encodedInfo == null) return cached;
    if ((encodedInfo - informationExtracted).abs() < 1e-4) {
      return cached;
    }
    return null;
  }

  /// 当前模型下是否已具备可直接使用的编码 (无需再花 2 Anlas 调 /ai/encode-vibe)
  bool hasValidEncodingFor(NaiModel model) => resolveEncodingFor(model) != null;

  /// 当前模型下是否需要先调 `/ai/encode-vibe` 进行服务端编码 (每次 2 Anlas)
  bool needsServerEncodingFor(NaiModel model) {
    if (!enabled || !model.usesEncodedVibeTransfer) return false;
    return !hasValidEncodingFor(model) && hasRawImage;
  }

  /// 当前条目是否在目标模型下有效可参与生成
  bool isEffectiveFor(NaiModel model) {
    if (!enabled || !model.supportsVibeTransfer) return false;
    if (model.usesEncodedVibeTransfer) {
      return hasValidEncodingFor(model) || hasRawImage;
    }
    return hasRawImage;
  }

  /// 写入某个模型的编码缓存
  NaiVibeReference withEncodingForModel({
    required NaiModel model,
    required String encoding,
    double? informationExtracted,
  }) {
    if (encoding.isEmpty) return this;
    final info = informationExtracted ?? this.informationExtracted;
    return copyWith(
      encodingsByModel: {...encodingsByModel, model.id: encoding},
      encodedInfoExtractedByModel: {
        ...encodedInfoExtractedByModel,
        model.id: info,
      },
    );
  }

  NaiVibeReference copyWith({
    String? id,
    String? displayName,
    NaiVibeSourceType? sourceType,
    Uint8List? rawImageBytes,
    Uint8List? thumbnailBytes,
    Map<String, String>? encodingsByModel,
    Map<String, double>? encodedInfoExtractedByModel,
    double? strength,
    double? informationExtracted,
    bool? enabled,
  }) {
    return NaiVibeReference(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      sourceType: sourceType ?? this.sourceType,
      rawImageBytes: rawImageBytes ?? this.rawImageBytes,
      thumbnailBytes: thumbnailBytes ?? this.thumbnailBytes,
      encodingsByModel: encodingsByModel ?? this.encodingsByModel,
      encodedInfoExtractedByModel:
          encodedInfoExtractedByModel ?? this.encodedInfoExtractedByModel,
      strength: strength ?? this.strength,
      informationExtracted: informationExtracted ?? this.informationExtracted,
      enabled: enabled ?? this.enabled,
    );
  }

  /// 对齐官网 `p.p` 的多 Vibe 强度归一化算法：
  /// 开启归一化且条数 > 1 且各强度绝对值之和 > 1 时，等比缩放到总和为 1。
  static List<double> normalizeStrengths(
    List<double> strengths, {
    required bool normalize,
  }) {
    if (!normalize || strengths.length <= 1) return List<double>.from(strengths);
    final total = strengths.fold<double>(0.0, (sum, v) => sum + v.abs());
    if (total == 0.0 || total <= 1.0) return List<double>.from(strengths);
    return strengths.map((v) => v / total).toList();
  }
}
