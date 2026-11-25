/// NovelAI Vibe Transfer 文件解析与 V3 图像预处理服务。
///
/// 支持解析以下官方格式：
/// - `.naiv4vibe` 单条预编码 JSON (支持多模型 `encodings` 映射、`image`、`thumbnail`、`importInfo`)
/// - `.naiv4vibebundle` 批量包 JSON (`vibes[]`)
/// - 带官方 PNG `iTXt`/`tEXt` 块的预编码图片 (`NovelAI_Vibe_Encoding_Base64` / `naidata`)
/// - 普通图片文件 (PNG / JPG / WebP / BMP，作为 rawImage 导入)
///
/// 同时提供 V3 Vibe Transfer 所需的 448×448 黑底居中 PNG 预处理 (后台 Isolate 执行)。
library;

import 'dart:convert';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import '../models/novelai_models.dart';
import 'isolated_compute.dart';

/// 解析结果快照 (纯数据，可跨 Isolate 传输)
class ParsedVibeData {
  final String displayName;
  final NaiVibeSourceType sourceType;
  final Uint8List? rawImageBytes;
  final Uint8List? thumbnailBytes;
  final Map<String, String> encodingsByModel;
  final Map<String, double> encodedInfoExtractedByModel;
  final double strength;
  final double informationExtracted;

  const ParsedVibeData({
    required this.displayName,
    required this.sourceType,
    this.rawImageBytes,
    this.thumbnailBytes,
    this.encodingsByModel = const {},
    this.encodedInfoExtractedByModel = const {},
    this.strength = NaiVibeReference.defaultStrength,
    this.informationExtracted = NaiVibeReference.defaultInfoExtracted,
  });

  NaiVibeReference toReference(String id) {
    return NaiVibeReference(
      id: id,
      displayName: displayName,
      sourceType: sourceType,
      rawImageBytes: rawImageBytes,
      thumbnailBytes: thumbnailBytes,
      encodingsByModel: encodingsByModel,
      encodedInfoExtractedByModel: encodedInfoExtractedByModel,
      strength: strength,
      informationExtracted: informationExtracted,
      enabled: true,
    );
  }
}

class VibeTransferService {
  VibeTransferService._();

  static const String _itxtVibeKey = 'NovelAI_Vibe_Encoding_Base64';
  static const String _itxtNaiDataKey = 'naidata';
  static const int v3TargetSize = 448;

  /// 解析单个用户导入的文件 (后台 Isolate 执行，不阻塞 UI)
  static Future<List<ParsedVibeData>> parseImportedFile({
    required String fileName,
    required Uint8List bytes,
    NaiModel? activeModel,
  }) async {
    if (bytes.isEmpty) return const [];
    final task = _ParseFileTask(
      fileName: fileName,
      bytes: IsolateBytes(bytes),
      fallbackModelId: activeModel?.id,
    );
    return runIsolated(_parseFileIsolate, task);
  }

  /// 同步解析入口 (供单元测试直接验证)
  static List<ParsedVibeData> parseFileBytesSync({
    required String fileName,
    required Uint8List bytes,
    NaiModel? activeModel,
  }) {
    if (bytes.isEmpty) return const [];
    final lower = fileName.toLowerCase();
    final ext = lower.contains('.') ? lower.split('.').last : '';

    if (ext == 'naiv4vibebundle' || lower.contains('.naiv4vibebundle')) {
      final parsed = _tryParseJsonPayload(bytes, fileName);
      if (parsed.isNotEmpty) return parsed;
    }

    if (ext == 'naiv4vibe' || ext == 'json') {
      final parsed = _tryParseJsonPayload(bytes, fileName);
      if (parsed.isNotEmpty) return parsed;
    }

    if (ext == 'png' || _isPng(bytes)) {
      final embedded = _tryParsePngEmbedded(
        bytes,
        fileName,
        fallbackModelId: activeModel?.id,
      );
      if (embedded.isNotEmpty) return embedded;
    }

    // 兜底：作为普通原始图片导入
    final defaultInfo = activeModel == NaiModel.v45Full ? 0.7 : 1.0;
    return [
      ParsedVibeData(
        displayName: fileName,
        sourceType: NaiVibeSourceType.rawImage,
        rawImageBytes: bytes,
        thumbnailBytes: bytes,
        strength: NaiVibeReference.defaultStrength,
        informationExtracted: defaultInfo,
      ),
    ];
  }

  /// 为 V3 Vibe Transfer 批量准备 448×448 黑底居中 PNG Base64 (后台 Isolate 执行)
  static Future<List<String>> prepareV3Images(
    List<NaiVibeReference> vibes,
  ) async {
    if (vibes.isEmpty) return const [];
    final results = <String>[];
    for (final vibe in vibes) {
      final raw = vibe.rawImageBytes;
      if (raw == null || raw.isEmpty) {
        throw StateError('V3 Vibe Transfer 需要原始图片数据: ${vibe.displayName}');
      }
      final encoded = await runIsolated(
        _prepareV3SingleIsolate,
        IsolateBytes(raw),
      );
      results.add(encoded);
    }
    return results;
  }

  /// 同步将单张图片缩放为 V3 官方 448×448 黑底居中 PNG 字节 (供测试验证)
  static Uint8List processV3ImageBytes(Uint8List inputBytes) {
    final decoded = img.decodeImage(inputBytes);
    if (decoded == null) return inputBytes;
    if (decoded.width == v3TargetSize &&
        decoded.height == v3TargetSize &&
        _isPng(inputBytes)) {
      return inputBytes;
    }

    final srcRatio = decoded.width / decoded.height;
    final int drawW;
    final int drawH;
    if (srcRatio > 1.0) {
      drawW = v3TargetSize;
      drawH = (v3TargetSize / srcRatio).round().clamp(1, v3TargetSize);
    } else {
      drawH = v3TargetSize;
      drawW = (v3TargetSize * srcRatio).round().clamp(1, v3TargetSize);
    }

    final resized =
        (decoded.width == drawW && decoded.height == drawH)
        ? decoded
        : img.copyResize(
            decoded,
            width: drawW,
            height: drawH,
            interpolation: img.Interpolation.cubic,
          );

    final canvas = img.Image(
      width: v3TargetSize,
      height: v3TargetSize,
      numChannels: 4,
    );
    img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 255));
    img.compositeImage(
      canvas,
      resized,
      dstX: ((v3TargetSize - drawW) / 2).round(),
      dstY: ((v3TargetSize - drawH) / 2).round(),
    );
    return Uint8List.fromList(img.encodePng(canvas));
  }

  static List<ParsedVibeData> _tryParseJsonPayload(
    Uint8List bytes,
    String fileName,
  ) {
    try {
      final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: true));
      if (decoded is! Map<String, dynamic>) return const [];
      return _parseVibeJsonMap(decoded, fallbackName: fileName);
    } catch (_) {
      return const [];
    }
  }

  static List<ParsedVibeData> _tryParsePngEmbedded(
    Uint8List bytes,
    String fileName, {
    String? fallbackModelId,
  }) {
    try {
      final decoder = img.PngDecoder();
      final info = decoder.startDecode(bytes);
      if (info is! img.PngInfo) return const [];
      final textData = info.textData;
      if (textData.isEmpty) return const [];

      // 1. 优先查官方嵌入 JSON 块 `naidata` (Base64 JSON)
      final naiDataRaw = textData[_itxtNaiDataKey];
      if (naiDataRaw != null && naiDataRaw.trim().isNotEmpty) {
        try {
          final jsonBytes = base64Decode(naiDataRaw.trim());
          final decoded = jsonDecode(
            utf8.decode(jsonBytes, allowMalformed: true),
          );
          if (decoded is Map<String, dynamic>) {
            final parsed = _parseVibeJsonMap(
              decoded,
              fallbackName: fileName,
              fallbackThumbnail: bytes,
              sourceOverride: NaiVibeSourceType.pngEmbedded,
            );
            if (parsed.isNotEmpty) return parsed;
          }
        } catch (_) {}
      }

      // 2. 查单条预编码块 `NovelAI_Vibe_Encoding_Base64`
      final directEncoding = textData[_itxtVibeKey]?.trim();
      if (directEncoding != null && directEncoding.isNotEmpty) {
        final targetModel =
            (fallbackModelId != null
                ? NaiModel.fromVibeEncodingKey(fallbackModelId)
                : null) ??
            NaiModel.v45Full;
        return [
          ParsedVibeData(
            displayName: fileName,
            sourceType: NaiVibeSourceType.pngEmbedded,
            rawImageBytes: bytes,
            thumbnailBytes: bytes,
            encodingsByModel: {targetModel.id: directEncoding},
            encodedInfoExtractedByModel: {targetModel.id: 1.0},
            strength: NaiVibeReference.defaultStrength,
            informationExtracted: 1.0,
          ),
        ];
      }
    } catch (_) {}
    return const [];
  }

  static List<ParsedVibeData> _parseVibeJsonMap(
    Map<String, dynamic> map, {
    required String fallbackName,
    Uint8List? fallbackThumbnail,
    NaiVibeSourceType? sourceOverride,
  }) {
    final identifier = map['identifier']?.toString();
    if (identifier == 'novelai-vibe-transfer-bundle' ||
        map['vibes'] is List) {
      final vibes = map['vibes'];
      if (vibes is! List) return const [];
      final results = <ParsedVibeData>[];
      for (var i = 0; i < vibes.length; i++) {
        final item = vibes[i];
        if (item is Map) {
          final parsed = _parseSingleVibeMap(
            Map<String, dynamic>.from(item),
            fallbackName: '${fallbackName}_#${i + 1}',
            fallbackThumbnail: fallbackThumbnail,
            sourceType: sourceOverride ?? NaiVibeSourceType.naiv4vibebundle,
          );
          if (parsed != null) results.add(parsed);
        }
      }
      return results;
    }

    final single = _parseSingleVibeMap(
      map,
      fallbackName: fallbackName,
      fallbackThumbnail: fallbackThumbnail,
      sourceType: sourceOverride ?? NaiVibeSourceType.naiv4vibe,
    );
    return single != null ? [single] : const [];
  }

  static ParsedVibeData? _parseSingleVibeMap(
    Map<String, dynamic> map, {
    required String fallbackName,
    Uint8List? fallbackThumbnail,
    required NaiVibeSourceType sourceType,
  }) {
    final name = (map['name'] is String && (map['name'] as String).isNotEmpty)
        ? (map['name'] as String).trim()
        : fallbackName;

    final importInfo = map['importInfo'] is Map
        ? Map<String, dynamic>.from(map['importInfo'] as Map)
        : const <String, dynamic>{};

    final strength = (importInfo['strength'] is num)
        ? (importInfo['strength'] as num).toDouble()
        : NaiVibeReference.defaultStrength;
    var infoExtracted = (importInfo['information_extracted'] is num)
        ? (importInfo['information_extracted'] as num)
              .toDouble()
              .clamp(0.01, 1.0)
              .toDouble()
        : NaiVibeReference.defaultInfoExtracted;

    Uint8List? rawImage = _decodeOptionalBase64Image(map['image']);
    Uint8List? thumbnail =
        _decodeOptionalBase64Image(map['thumbnail']) ??
        rawImage ??
        fallbackThumbnail;

    final encodingsByModel = <String, String>{};
    final encodedInfoByModel = <String, double>{};

    final encodings = map['encodings'];
    if (encodings is Map) {
      for (final modelEntry in encodings.entries) {
        final modelKey = modelEntry.key.toString();
        final model = NaiModel.fromVibeEncodingKey(modelKey);
        if (model == null) continue;
        final variants = modelEntry.value;
        if (variants is! Map) continue;

        String? bestEncoding;
        double? bestInfo;
        double bestDiff = double.infinity;

        for (final variant in variants.values) {
          if (variant is! Map) continue;
          final enc = variant['encoding'];
          if (enc is! String || enc.isEmpty) continue;
          final params = variant['params'];
          final variantInfo =
              (params is Map && params['information_extracted'] is num)
              ? (params['information_extracted'] as num).toDouble()
              : infoExtracted;
          final diff = (variantInfo - infoExtracted).abs();
          if (bestEncoding == null || diff < bestDiff) {
            bestEncoding = enc;
            bestInfo = variantInfo;
            bestDiff = diff;
          }
        }

        if (bestEncoding != null) {
          encodingsByModel[model.id] = bestEncoding;
          if (bestInfo != null) {
            encodedInfoByModel[model.id] = bestInfo;
            infoExtracted = bestInfo;
          }
        }
      }
    }

    if (rawImage == null && encodingsByModel.isEmpty) return null;

    return ParsedVibeData(
      displayName: name,
      sourceType: sourceType,
      rawImageBytes: rawImage,
      thumbnailBytes: thumbnail,
      encodingsByModel: encodingsByModel,
      encodedInfoExtractedByModel: encodedInfoByModel,
      strength: strength,
      informationExtracted: infoExtracted,
    );
  }

  static Uint8List? _decodeOptionalBase64Image(Object? raw) {
    if (raw is! String || raw.trim().isEmpty) return null;
    var s = raw.trim();
    final commaIdx = s.indexOf(',');
    if (s.startsWith('data:') && commaIdx != -1) {
      s = s.substring(commaIdx + 1);
    }
    try {
      final decoded = base64Decode(s);
      return decoded.isEmpty ? null : decoded;
    } catch (_) {
      return null;
    }
  }

  static bool _isPng(Uint8List bytes) {
    if (bytes.length < 8) return false;
    return bytes[0] == 137 &&
        bytes[1] == 80 &&
        bytes[2] == 78 &&
        bytes[3] == 71 &&
        bytes[4] == 13 &&
        bytes[5] == 10 &&
        bytes[6] == 26 &&
        bytes[7] == 10;
  }
}

class _ParseFileTask {
  final String fileName;
  final IsolateBytes bytes;
  final String? fallbackModelId;

  const _ParseFileTask({
    required this.fileName,
    required this.bytes,
    this.fallbackModelId,
  });
}

List<ParsedVibeData> _parseFileIsolate(_ParseFileTask task) {
  final model = task.fallbackModelId != null
      ? NaiModel.fromId(task.fallbackModelId!)
      : null;
  return VibeTransferService.parseFileBytesSync(
    fileName: task.fileName,
    bytes: task.bytes.materialize(),
    activeModel: model,
  );
}

String _prepareV3SingleIsolate(IsolateBytes bytes) {
  final processed = VibeTransferService.processV3ImageBytes(
    bytes.materialize(),
  );
  return base64Encode(processed);
}
