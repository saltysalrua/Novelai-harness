import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../models/novelai_models.dart';

/// Anlas 预计消耗计算器 (移植自 Aaalice_NAI_Launcher 的 AnlasCalculator)
///
/// 基础计费公式与 NovelAI 网页端一致：
/// - 现代公式: ceil(面积系数 * 像素数 + 步数面积系数 * 像素数 * 步数)，
///   随后连乘模型倍率 (V5 为 1.5)，单张下限 2 Anlas、上限 140 Anlas。
/// - Opus 免费条件: 步数 <= 28 且像素数 <= 1,048,576；V5 的免费额度受
///   体力配额池限制，透支后不再抵扣，按正常价扣 Anlas。
/// - 单次请求多张 (n_samples > 1) 时只有第一张享受 Opus 免费折扣。
/// - 官方云端超分按输入面积分档计费，放大倍数不参与价格计算；
///   Opus 用户输入不超过 640x640 时免费。
///
/// 服务端计费仍是最终依据，此处仅作预估。
class AnlasCalculator {
  AnlasCalculator._();

  /// 超出计费上限或参数无效时的返回值
  static const int invalidCost = -3;

  /// 单张图片计费上限
  static const int maximumPerSampleCost = 140;

  /// Opus 免费步数上限
  static const int opusFreeMaxSteps = 28;

  /// Opus 免费像素数上限 (1024x1024)
  static const int opusFreeMaxPixels = 1024 * 1024;

  /// Opus 用户官方超分免费的最大输入面积 (640x640)
  static const int opusFreeUpscaleMaxInputPixels = 640 * 640;

  /// 官方云端超分按输入面积计费的分档表
  static const List<(int, int)> _upscaleCostTiers = [
    (1048576, 1),
    (1747627, 2),
    (2446678, 3),
    (3145728, 4),
  ];

  static const double _areaCoefficient = 2.951823174884865e-6;
  static const double _stepAreaCoefficient = 5.753298233447344e-7;

  /// 预估一次生图请求的 Anlas 消耗
  ///
  /// [isOpus] 账号是否拥有有效的 Opus 订阅权益；
  /// [opusQuotaExhausted] V5 体力配额池是否已透支。
  /// 返回 0 表示免费，[invalidCost] 表示参数超出计费上限。
  static int estimateGenerationCost({
    required NaiGenerationParams params,
    required bool isOpus,
    bool opusQuotaExhausted = false,
  }) {
    return calculateFromValues(
      width: params.width,
      height: params.height,
      steps: params.steps,
      nSamples: params.nSamples,
      model: params.model,
      isOpus: isOpus,
      opusQuotaExhausted: opusQuotaExhausted,
    );
  }

  /// 根据具体参数值计算单次请求的 Anlas 消耗
  static int calculateFromValues({
    required int width,
    required int height,
    required int steps,
    required int nSamples,
    required NaiModel model,
    bool isOpus = false,
    bool opusQuotaExhausted = false,
  }) {
    if (nSamples <= 0 || width <= 0 || height <= 0 || steps <= 0) return 0;

    final pixels = width * height;

    // 单张基础价: 现代公式 (本客户端支持的全部为 V3+ 现代计费模型)
    final baseCost =
        (_areaCoefficient * pixels + _stepAreaCoefficient * pixels * steps)
            .ceil();
    final perSample = math.max((baseCost * model.anlasMultiplier).ceil(), 2);

    if (perSample > maximumPerSampleCost) return invalidCost;

    // Opus 免费折扣: V5 受体力配额池限制，透支后不再抵扣
    final quotaBlocked = model.hasOpusUsageLimit && opusQuotaExhausted;
    final opusDiscount =
        !quotaBlocked &&
            _isOpusFree(isOpus: isOpus, steps: steps, resolution: pixels)
        ? 1
        : 0;

    // 单次请求多张时只有第一张享受折扣
    return perSample * math.max(nSamples - opusDiscount, 0);
  }

  /// 计算官方云端超分的 Anlas 消耗
  ///
  /// 按输入面积分档计费，放大倍数不参与价格计算；
  /// Opus 用户输入不超过 640x640 时免费。
  static int estimateUpscaleCost({
    required int inputWidth,
    required int inputHeight,
    int scale = 4,
    bool isOpus = false,
  }) {
    if (inputWidth <= 0 || inputHeight <= 0 || scale <= 0) return invalidCost;

    final inputPixels = inputWidth * inputHeight;
    if (isOpus && inputPixels <= opusFreeUpscaleMaxInputPixels) return 0;

    for (final (maxInputPixels, cost) in _upscaleCostTiers) {
      if (inputPixels <= maxInputPixels) return cost;
    }
    return invalidCost;
  }

  /// 检查是否满足 Opus 免费条件
  static bool _isOpusFree({
    required bool isOpus,
    required int steps,
    required int resolution,
  }) {
    return isOpus &&
        steps <= opusFreeMaxSteps &&
        resolution <= opusFreeMaxPixels;
  }

  /// 把预估消耗格式化为给用户看的状态文本
  ///
  /// 0 → `0 Anlas (Opus 免费)`；正值 → `预计 X Anlas`；无效 → `无法估算`。
  static String describeCost(int cost) {
    if (cost == 0) return '0 Anlas (Opus 免费)';
    if (cost < 0) return '无法估算';
    return '预计 $cost Anlas';
  }

  /// 从图片字节解码出实际宽高 (用于超分等按输入面积计费的场景)
  ///
  /// 解码失败 (非图片或损坏数据) 时返回 null。
  static Future<({int width, int height})?> decodeImageDimensions(
    List<int> bytes,
  ) async {
    try {
      final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
      final codec = await ui.instantiateImageCodec(data);
      final frame = await codec.getNextFrame();
      final size = (width: frame.image.width, height: frame.image.height);
      frame.image.dispose();
      codec.dispose();
      return size;
    } catch (_) {
      return null;
    }
  }
}
