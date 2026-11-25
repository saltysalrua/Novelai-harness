import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../models/novelai_models.dart';
import 'prompt_image_probe.dart';

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

  /// 每张精准参考图每张生成图片的附加费用 (V5 与 V4.5 均为 5 Anlas)
  static const int preciseReferenceCostPerImage = 5;

  /// Vibe Transfer 免费槽位上限 (前 4 张免生成附加费，第 5 张起每张每图 +2 Anlas)
  static const int vibeFreeSlotLimit = 4;

  /// 超出免费槽位后的 Vibe Transfer 每张每图附加费
  static const int vibeExtraSlotCostPerImage = 2;

  /// V4 / V4.5 原始图首次编码为 Vibe 的单次费用 (2 Anlas / 张)
  static const int vibeEncodeCostPerImage = 2;

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
    final activePreciseCount = params.effectivePreciseReferences().length;
    final activeVibes = params.effectiveVibeReferences();
    final pendingVibeEncodeCount = activeVibes
        .where((v) => v.needsServerEncodingFor(params.model))
        .length;
    return calculateFromValues(
      width: params.width,
      height: params.height,
      // 节约档实际只跑锁定的 14 步 (但启用精准参考时 V5 Full 自动强制高档)。
      steps: params.effectiveSteps,
      nSamples: params.nSamples,
      model: params.model,
      isOpus: isOpus,
      opusQuotaExhausted: opusQuotaExhausted,
      preciseReferenceCount: activePreciseCount,
      vibeReferenceCount: activeVibes.length,
      vibeEncodeCount: pendingVibeEncodeCount,
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
    int preciseReferenceCount = 0,
    int vibeReferenceCount = 0,
    int vibeEncodeCount = 0,
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

    // 单次请求多张时只有第一张基础图享受 Opus 折扣；
    // 精准参考附加费按 5 * 参考图数 * 生成张数 叠加 (Opus 免费不免除参考费，与官网 2026-11 计费一致)。
    final int baseTotal = perSample * math.max<int>(nSamples - opusDiscount, 0);
    final bool hasActivePrecise =
        preciseReferenceCount > 0 && model.supportsPreciseReference;
    final int refAdditional = hasActivePrecise
        ? preciseReferenceCostPerImage * preciseReferenceCount * nSamples
        : 0;

    // Vibe Transfer：与精准参考互斥；1~4 张免附加费，超过 4 张每张每图 +2 Anlas；
    // V4/V4.5 未缓存编码的原始图另加一次性编码费 2 Anlas / 张。
    final bool hasActiveVibes =
        !hasActivePrecise &&
        vibeReferenceCount > 0 &&
        model.supportsVibeTransfer;
    final int vibeSlotAdditional = hasActiveVibes
        ? math.max<int>(vibeReferenceCount - vibeFreeSlotLimit, 0) *
              vibeExtraSlotCostPerImage *
              nSamples
        : 0;
    final int vibeEncodeAdditional =
        (hasActiveVibes && model.usesEncodedVibeTransfer && vibeEncodeCount > 0)
        ? vibeEncodeCount * vibeEncodeCostPerImage
        : 0;

    return baseTotal +
        refAdditional +
        vibeSlotAdditional +
        vibeEncodeAdditional;
  }

  /// 计算官方云端超分的 Anlas 消耗
  ///
  /// 按输入面积分档计费 (V5 换代后的新超分模型固定倍率输出，无倍率参数)；
  /// Opus 用户输入不超过 640x640 时免费。
  static int estimateUpscaleCost({
    required int inputWidth,
    required int inputHeight,
    bool isOpus = false,
  }) {
    if (inputWidth <= 0 || inputHeight <= 0) return invalidCost;

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
    final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    // 优先只读 24-30B 文件头 (PNG/WebP/JPEG)，避免全图像素解码瞬间吃掉数十 MB
    final probed = PromptImageProbe.probeDimensions(data);
    if (probed != null) {
      return (width: probed.$1, height: probed.$2);
    }
    ui.Codec? codec;
    ui.Image? image;
    try {
      codec = await ui.instantiateImageCodec(data);
      final frame = await codec.getNextFrame();
      image = frame.image;
      return (width: image.width, height: image.height);
    } catch (_) {
      return null;
    } finally {
      image?.dispose();
      codec?.dispose();
    }
  }
}
