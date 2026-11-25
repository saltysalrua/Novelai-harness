/// NovelAI 精准参考图预处理服务。
///
/// 严格移植 NovelAI 网页端生产实现 (2026-11)：
/// - V5 (`bucketCharacterReferences`):
///   从官方 97 档 1MP 桶表中按对数宽高比匹配最接近的 `(bw, bh)`；
///   若原图尺寸已精确命中桶尺寸则直接保留 PNG；否则按 Cover 等比放大/缩小后
///   居中裁切至 `(bw, bh)`，输出纯 Base64 PNG。
/// - V4.5 (`resizeCharacterReferences`):
///   从官方三档大尺寸 `[[1024, 1536], [1536, 1024], [1472, 1472]]` 中按宽高比
///   匹配最接近的目标画布，Contain 等比缩放后在黑底画布上居中合成，输出纯 Base64 PNG。
///
/// 所有解码、缩放与 PNG 编码均通过 [runIsolated] 在后台 Isolate 执行，
/// 避免阻塞 UI 线程。
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import '../models/novelai_models.dart';
import 'isolated_compute.dart';

/// V5 桶裁切几何结果
class V5BucketCropPlan {
  final int width;
  final int height;
  final int resizeWidth;
  final int resizeHeight;
  final int left;
  final int top;
  final bool unchanged;

  const V5BucketCropPlan({
    required this.width,
    required this.height,
    required this.resizeWidth,
    required this.resizeHeight,
    required this.left,
    required this.top,
    required this.unchanged,
  });
}

/// V4.5 三档黑底居中填充几何结果
class V45LetterboxPlan {
  final int canvasWidth;
  final int canvasHeight;
  final int drawWidth;
  final int drawHeight;
  final int offsetX;
  final int offsetY;

  const V45LetterboxPlan({
    required this.canvasWidth,
    required this.canvasHeight,
    required this.drawWidth,
    required this.drawHeight,
    required this.offsetX,
    required this.offsetY,
  });
}

class PreciseReferenceImageService {
  PreciseReferenceImageService._();

  /// 官方 V5 精准参考 97 档 1MP 桶尺寸表 (与 novelai.net 生产前端完全一致)
  static const List<(int, int)> v5Buckets = [
    (256, 4096),
    (256, 4032),
    (256, 3968),
    (256, 3904),
    (256, 3840),
    (256, 3776),
    (256, 3712),
    (256, 3648),
    (256, 3584),
    (256, 3520),
    (256, 3456),
    (256, 3392),
    (256, 3328),
    (320, 3264),
    (320, 3200),
    (320, 3136),
    (320, 3072),
    (320, 3008),
    (320, 2944),
    (320, 2880),
    (320, 2816),
    (320, 2752),
    (384, 2688),
    (384, 2624),
    (384, 2560),
    (384, 2496),
    (384, 2432),
    (384, 2368),
    (448, 2304),
    (448, 2240),
    (448, 2176),
    (448, 2112),
    (512, 2048),
    (512, 1984),
    (512, 1920),
    (512, 1856),
    (576, 1792),
    (576, 1728),
    (576, 1664),
    (640, 1600),
    (640, 1536),
    (704, 1472),
    (704, 1408),
    (768, 1344),
    (768, 1280),
    (832, 1216),
    (896, 1152),
    (960, 1088),
    (1024, 1024),
    (1088, 960),
    (1152, 896),
    (1216, 832),
    (1280, 768),
    (1344, 768),
    (1408, 704),
    (1472, 704),
    (1536, 640),
    (1600, 640),
    (1664, 576),
    (1728, 576),
    (1792, 576),
    (1856, 512),
    (1920, 512),
    (1984, 512),
    (2048, 512),
    (2112, 448),
    (2176, 448),
    (2240, 448),
    (2304, 448),
    (2368, 384),
    (2432, 384),
    (2496, 384),
    (2560, 384),
    (2624, 384),
    (2688, 384),
    (2752, 320),
    (2816, 320),
    (2880, 320),
    (2944, 320),
    (3008, 320),
    (3072, 320),
    (3136, 320),
    (3200, 320),
    (3264, 320),
    (3328, 256),
    (3392, 256),
    (3456, 256),
    (3520, 256),
    (3584, 256),
    (3648, 256),
    (3712, 256),
    (3776, 256),
    (3840, 256),
    (3904, 256),
    (3968, 256),
    (4032, 256),
    (4096, 256),
  ];

  /// 官方 V4.5 精准参考三档大尺寸
  static const List<(int, int)> v45Canvases = [
    (1024, 1536),
    (1536, 1024),
    (1472, 1472),
  ];

  /// 计算 V5 桶裁切方案 (纯数学，供 Isolate 与单元测试共用)
  static V5BucketCropPlan computeV5BucketCrop(int width, int height) {
    final safeW = math.max(width, 1);
    final safeH = math.max(height, 1);
    final logRatio = math.log(safeW / safeH);

    var best = v5Buckets.first;
    var bestDiff = (logRatio - math.log(best.$1 / best.$2)).abs();
    for (final bucket in v5Buckets) {
      final diff = (logRatio - math.log(bucket.$1 / bucket.$2)).abs();
      if (diff < bestDiff) {
        best = bucket;
        bestDiff = diff;
      }
    }

    final (bw, bh) = best;
    final scale = math.max(bw / safeW, bh / safeH);
    final resizeW = math.max((safeW * scale + 0.5).floor(), bw);
    final resizeH = math.max((safeH * scale + 0.5).floor(), bh);

    return V5BucketCropPlan(
      width: bw,
      height: bh,
      resizeWidth: resizeW,
      resizeHeight: resizeH,
      left: (resizeW - bw) ~/ 2,
      top: (resizeH - bh) ~/ 2,
      unchanged: safeW == bw && safeH == bh,
    );
  }

  /// 计算 V4.5 三档黑底居中缩放方案 (纯数学，供 Isolate 与单元测试共用)
  static V45LetterboxPlan computeV45Letterbox(int width, int height) {
    final safeW = math.max(width, 1);
    final safeH = math.max(height, 1);
    final srcRatio = safeW / safeH;

    var best = v45Canvases.first;
    var bestDiff = ((best.$1 / best.$2) - srcRatio).abs();
    for (final canvas in v45Canvases) {
      final diff = ((canvas.$1 / canvas.$2) - srcRatio).abs();
      if (diff < bestDiff) {
        best = canvas;
        bestDiff = diff;
      }
    }

    final (cw, ch) = best;
    final canvasRatio = cw / ch;
    final int drawW;
    final int drawH;
    if (srcRatio > canvasRatio) {
      drawW = cw;
      drawH = (cw / srcRatio).round().clamp(1, ch);
    } else {
      drawH = ch;
      drawW = (ch * srcRatio).round().clamp(1, cw);
    }

    return V45LetterboxPlan(
      canvasWidth: cw,
      canvasHeight: ch,
      drawWidth: drawW,
      drawHeight: drawH,
      offsetX: ((cw - drawW) / 2).round(),
      offsetY: ((ch - drawH) / 2).round(),
    );
  }

  /// 在后台 Isolate 中将有效参考图批量规范化为对应模型所需的纯 Base64 PNG 字符串列表。
  static Future<List<String>> prepareImagesForModel({
    required List<NaiPreciseReference> references,
    required NaiModel model,
  }) async {
    if (references.isEmpty) return const [];
    final useV5Bucket = model.usesBucketPreciseReferenceResize;
    final results = <String>[];
    for (final ref in references) {
      final task = _PrepareTask(
        bytes: IsolateBytes(ref.imageBytes),
        useV5Bucket: useV5Bucket,
      );
      final encoded = await runIsolated(_prepareSingleImageIsolate, task);
      results.add(encoded);
    }
    return results;
  }

  /// 同步纯字节处理入口 (供单元测试直接验证像素结果)
  static Uint8List processSingleImageBytes(
    Uint8List inputBytes, {
    required bool useV5Bucket,
  }) {
    final decoded = img.decodeImage(inputBytes);
    if (decoded == null) return inputBytes;

    // 对齐官网：清理 stealth_pngcomp 带来的 254/1 alpha 噪点
    final normalized = _normalizeAlphaIfNeeded(decoded);

    if (useV5Bucket) {
      final plan = computeV5BucketCrop(normalized.width, normalized.height);
      if (plan.unchanged && _isPng(inputBytes)) {
        return inputBytes;
      }
      final resized =
          (normalized.width == plan.resizeWidth &&
              normalized.height == plan.resizeHeight)
          ? normalized
          : img.copyResize(
              normalized,
              width: plan.resizeWidth,
              height: plan.resizeHeight,
              interpolation: img.Interpolation.cubic,
            );
      final cropped =
          (resized.width == plan.width &&
              resized.height == plan.height &&
              plan.left == 0 &&
              plan.top == 0)
          ? resized
          : img.copyCrop(
              resized,
              x: plan.left,
              y: plan.top,
              width: plan.width,
              height: plan.height,
            );
      return Uint8List.fromList(img.encodePng(cropped));
    }

    // V4.5: Contain 缩放 + 黑底居中填充至三档大尺寸之一
    final plan = computeV45Letterbox(normalized.width, normalized.height);
    final resized =
        (normalized.width == plan.drawWidth &&
            normalized.height == plan.drawHeight)
        ? normalized
        : img.copyResize(
            normalized,
            width: plan.drawWidth,
            height: plan.drawHeight,
            interpolation: img.Interpolation.cubic,
          );

    final canvas = img.Image(
      width: plan.canvasWidth,
      height: plan.canvasHeight,
      numChannels: 4,
    );
    img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 255));
    img.compositeImage(
      canvas,
      resized,
      dstX: plan.offsetX,
      dstY: plan.offsetY,
    );
    return Uint8List.fromList(img.encodePng(canvas));
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

  static img.Image _normalizeAlphaIfNeeded(img.Image image) {
    if (image.numChannels < 4) return image;
    // 若存在 NovelAI 隐写残留 alpha=254，顺手归整避免边缘杂色；
    // 仅检测首像素快速短路，普通不透明 PNG 零开销。
    final first = image.getPixel(0, 0);
    if (first.a.toInt() != 254) return image;
    final copy = image.clone();
    for (final pixel in copy) {
      final a = pixel.a.toInt();
      if (a == 254) {
        pixel.a = 255;
      } else if (a == 1) {
        pixel.a = 0;
      }
    }
    return copy;
  }
}

class _PrepareTask {
  final IsolateBytes bytes;
  final bool useV5Bucket;

  const _PrepareTask({required this.bytes, required this.useV5Bucket});
}

String _prepareSingleImageIsolate(_PrepareTask task) {
  final raw = task.bytes.materialize();
  final processed = PreciseReferenceImageService.processSingleImageBytes(
    raw,
    useV5Bucket: task.useV5Bucket,
  );
  return base64Encode(processed);
}
