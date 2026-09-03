import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../models/novelai_models.dart';
import 'image_metadata_service.dart';
import 'isolated_compute.dart';
import 'rgba_pixel_ops.dart';
import 'skia_image_codec.dart';

/// 水印合成与盲水印服务
///
/// 职责：
/// 1. 可见水印合成 (2D 位置/缩放/不透明度/边距，支持自动对比度与智能低信息区域选位)；
/// 2. 智能选位算法 (基于梯度能量积分图，挑选信息量最低的放置区域)；
/// 3. 盲水印 (Koch-Zhao DCT 频域隐形水印，肉眼不可见，可带载荷提取)；
/// 4. 统一导出处理管道 (水印 -> 元数据抹除 -> 盲水印嵌入)。
///
/// 架构：Skia 编解码只发生在根 isolate (`decodeToRawRgba`/`encodeRawRgbaToPng`)，
/// 纯像素运算 (缩放/选位/合成/DCT) 在 compute isolate 内以 flat RGBA 字节执行。
class WatermarkService {
  // ==================== 1. 可见水印合成 ====================

  /// 合成可见水印，返回合成后的 PNG 字节
  ///
  /// 根 isolate Skia 解码 → compute 纯像素合成 → 根 isolate Skia 编码；
  /// 任一图片解码失败时原样返回。
  static Future<Uint8List> applyWatermarkAsync({
    required Uint8List imageBytes,
    required Uint8List watermarkBytes,
    required WatermarkConfig config,
  }) async {
    final baseImage = await decodeToRawRgba(imageBytes);
    final watermarkImage = await decodeToRawRgba(watermarkBytes);

    if (baseImage == null || watermarkImage == null) {
      return imageBytes;
    }

    final outRgba = await runIsolated(
      _applyWatermarkIsolate,
      _WatermarkTaskArgs(
        base: IsolateBytes(baseImage.rgba),
        baseWidth: baseImage.width,
        baseHeight: baseImage.height,
        wm: IsolateBytes(watermarkImage.rgba),
        wmWidth: watermarkImage.width,
        wmHeight: watermarkImage.height,
        config: config,
      ),
    );
    return encodeRawRgbaToPng(
      outRgba.materialize(),
      baseImage.width,
      baseImage.height,
    );
  }

  /// 可见水印纯像素合成 (compute isolate 内执行)：
  /// 缩放水印 (预乘插值防光晕) → 选位 (固定/智能) → 自动对比度 → 不透明度 → alpha 混合
  static Uint8List _applyWatermarkPixels(_WatermarkTaskArgs args) {
    final baseRgba = args.base.materialize();
    final wmRgba = args.wm.materialize();
    final config = args.config;
    final imgW = args.baseWidth;
    final imgH = args.baseHeight;
    final shortSide = math.min(imgW, imgH);

    // 边距与水印目标尺寸计算 (与画板交互层算法一致)
    final marginPx = (shortSide * config.marginPercent) / 100.0;
    final targetWmW = math
        .max(1, ((shortSide * config.scalePercent) / 100.0).round())
        .clamp(1, imgW);
    final wmAspect = args.wmHeight / args.wmWidth;
    // 高度做 contain 钳制，避免超高水印溢出底图 (与画板预览一致)
    var targetWmH = math.max(1, (targetWmW * wmAspect).round());
    var fittedWmW = targetWmW;
    if (targetWmH > imgH) {
      targetWmH = imgH;
      fittedWmW = math.min(targetWmW, math.max(1, (imgH / wmAspect).round()));
    }

    // 缩放水印 (预乘 alpha 后插值，避免透明底 RGB 垃圾值渗入边缘形成光晕)
    final resizedWmRgba = resizeRgbaCubicAlphaAware(
      wmRgba,
      args.wmWidth,
      args.wmHeight,
      fittedWmW,
      targetWmH,
    );

    // 计算放置坐标 (posX/posY 为 0.0~1.0；智能选位时由算法决定)
    final availW = math.max(0.0, imgW - 2 * marginPx - fittedWmW);
    final availH = math.max(0.0, imgH - 2 * marginPx - targetWmH);
    double posX = config.posX.clamp(0.0, 1.0);
    double posY = config.posY.clamp(0.0, 1.0);
    if (config.autoPosition) {
      final smart = findLowInformationPosition(
        RawRgbaImage(rgba: baseRgba, width: imgW, height: imgH),
        wmW: fittedWmW,
        wmH: targetWmH,
        marginPx: marginPx,
      );
      posX = smart.$1;
      posY = smart.$2;
    }
    final dstX = (marginPx + availW * posX).round();
    final dstY = (marginPx + availH * posY).round();

    // 自动对比度：按水印下方背景亮度自动加深/提亮水印，保证可见性
    if (config.autoContrast) {
      _applyAutoContrast(
        baseRgba,
        imgW,
        imgH,
        resizedWmRgba,
        fittedWmW,
        targetWmH,
        dstX: dstX,
        dstY: dstY,
      );
    }

    // 支持不透明度调节
    if (config.opacity < 1.0) {
      final alphaFactor = config.opacity.clamp(0.0, 1.0);
      for (var i = 3; i < resizedWmRgba.length; i += 4) {
        resizedWmRgba[i] = (resizedWmRgba[i] * alphaFactor).round().clamp(
          0,
          255,
        );
      }
    }

    final out = Uint8List.fromList(baseRgba);
    // 合成水印 (BlendMode.alpha 语义，透明底与原图正常混合，不会盖掉背景)
    blendAlphaRect(
      out,
      imgW,
      imgH,
      resizedWmRgba,
      fittedWmW,
      targetWmH,
      dstX: dstX,
      dstY: dstY,
    );
    return out;
  }

  /// 自动对比度：统计水印覆盖区域的背景平均亮度，把水印向反色方向偏移
  static void _applyAutoContrast(
    Uint8List baseRgba,
    int baseWidth,
    int baseHeight,
    Uint8List wmRgba,
    int wmW,
    int wmH, {
    required int dstX,
    required int dstY,
  }) {
    // 1. 统计背景区域平均亮度
    var lumaSum = 0.0;
    var sampleCount = 0;
    for (var y = dstY; y < dstY + wmH; y += 2) {
      if (y < 0 || y >= baseHeight) continue;
      for (var x = dstX; x < dstX + wmW; x += 2) {
        if (x < 0 || x >= baseWidth) continue;
        final i = (y * baseWidth + x) * 4;
        lumaSum +=
            0.299 * baseRgba[i] +
            0.587 * baseRgba[i + 1] +
            0.114 * baseRgba[i + 2];
        sampleCount++;
      }
    }
    if (sampleCount == 0) return;
    final meanLuma = (lumaSum / sampleCount) / 255.0;

    // 2. 背景偏亮 -> 水印压暗；背景偏暗 -> 水印提亮
    const strength = 0.65;
    final target = meanLuma > 0.55 ? 0.0 : 1.0;
    final targetChannel = target * 255.0;
    for (var i = 0; i < wmRgba.length; i += 4) {
      if (wmRgba[i + 3] == 0) continue;
      for (var c = 0; c < 3; c++) {
        wmRgba[i +
            c] = (wmRgba[i + c] * (1 - strength) + targetChannel * strength)
            .round()
            .clamp(0, 255);
      }
    }
  }

  // ==================== 2. 智能低信息区域选位 ====================

  /// 在图像中寻找信息量最低的水印放置位置 (归一化 posX/posY，语义同 WatermarkConfig)
  ///
  /// 算法：把图像降采样后计算亮度梯度能量积分图，滑窗评估每个候选矩形
  /// (水印实际尺寸 + 边距约束) 的梯度总能量，取能量最低者——即细节/边缘
  /// 最少、对画面内容干扰最小的区域。
  ///
  /// 纯像素计算，可在 compute isolate 执行。
  static (double, double) findLowInformationPosition(
    RawRgbaImage image, {
    required int wmW,
    required int wmH,
    required double marginPx,
  }) {
    final imgW = image.width;
    final imgH = image.height;
    if (imgW < 8 || imgH < 8) return (1.0, 1.0);

    // 1. 降采样 (最长边不超过 480，选位不需要全分辨率精度；面积平均亮度)
    const maxSide = 480;
    final scale = math.min(1.0, maxSide / math.max(imgW, imgH));
    final w = math.max(8, (imgW * scale).round());
    final h = math.max(8, (imgH * scale).round());
    final luma = List<double>.filled(w * h, 0.0);
    for (var y = 0; y < h; y++) {
      final y0 = (y * imgH) ~/ h;
      final y1 = math.max(y0 + 1, ((y + 1) * imgH) ~/ h);
      for (var x = 0; x < w; x++) {
        final x0 = (x * imgW) ~/ w;
        final x1 = math.max(x0 + 1, ((x + 1) * imgW) ~/ w);
        var sum = 0.0;
        var cnt = 0;
        for (var sy = y0; sy < y1; sy++) {
          for (var sx = x0; sx < x1; sx++) {
            final i = (sy * imgW + sx) * 4;
            sum +=
                0.299 * image.rgba[i] +
                0.587 * image.rgba[i + 1] +
                0.114 * image.rgba[i + 2];
            cnt++;
          }
        }
        luma[y * w + x] = sum / cnt;
      }
    }

    // 2. 亮度梯度能量 + 积分图
    final integral = List<double>.filled((w + 1) * (h + 1), 0.0);
    for (var y = 0; y < h; y++) {
      var rowSum = 0.0;
      for (var x = 0; x < w; x++) {
        final gx = x + 1 < w
            ? (luma[y * w + x + 1] - luma[y * w + x]).abs()
            : 0.0;
        final gy = y + 1 < h
            ? (luma[(y + 1) * w + x] - luma[y * w + x]).abs()
            : 0.0;
        rowSum += gx + gy;
        integral[(y + 1) * (w + 1) + (x + 1)] =
            integral[y * (w + 1) + (x + 1)] + rowSum;
      }
    }

    double rectSum(int x0, int y0, int x1, int y1) {
      x0 = x0.clamp(0, w);
      x1 = x1.clamp(0, w);
      y0 = y0.clamp(0, h);
      y1 = y1.clamp(0, h);
      if (x1 <= x0 || y1 <= y0) return 0.0;
      return integral[y1 * (w + 1) + x1] -
          integral[y0 * (w + 1) + x1] -
          integral[y1 * (w + 1) + x0] +
          integral[y0 * (w + 1) + x0];
    }

    // 3. 候选窗口尺寸 (随降采样比例缩放)
    final sWmW = math.max(1, (wmW * scale).round());
    final sWmH = math.max(1, (wmH * scale).round());
    final sMargin = marginPx * scale;

    final availW = (w - 2 * sMargin - sWmW).floor();
    final availH = (h - 2 * sMargin - sWmH).floor();
    if (availW < 0 || availH < 0) return (1.0, 1.0);

    // 4. 网格滑窗搜索最低能量候选 (32x32 采样足够精细)
    const steps = 32;
    var bestScore = double.infinity;
    var bestLeft = sMargin;
    var bestTop = sMargin;
    for (var iy = 0; iy <= steps; iy++) {
      final top = sMargin + availH * iy / steps;
      for (var ix = 0; ix <= steps; ix++) {
        final left = sMargin + availW * ix / steps;
        final score = rectSum(
          left.round(),
          top.round(),
          (left + sWmW).round(),
          (top + sWmH).round(),
        );
        if (score < bestScore) {
          bestScore = score;
          bestLeft = left;
          bestTop = top;
        }
      }
    }

    // 5. 反解归一化坐标 (与合成公式 left = margin + avail * pos 互逆)
    final posBaseX = availW > 0 ? (bestLeft - sMargin) / availW : 0.0;
    final posBaseY = availH > 0 ? (bestTop - sMargin) / availH : 0.0;
    return (posBaseX.clamp(0.0, 1.0), posBaseY.clamp(0.0, 1.0));
  }

  /// 智能选位异步入口：基于图像字节计算低信息区域位置 (compute 后台执行)
  ///
  /// [watermarkBytes] 用于计算水印长宽比；为空时按 1:1 处理。
  static Future<(double, double)> findLowInformationPositionAsync(
    Uint8List imageBytes, {
    required double scalePercent,
    required double marginPercent,
    Uint8List? watermarkBytes,
  }) async {
    final image = await decodeToRawRgba(imageBytes);
    if (image == null) return (1.0, 1.0);
    var aspect = 1.0;
    if (watermarkBytes != null) {
      final wm = await decodeToRawRgba(watermarkBytes);
      if (wm != null && wm.width > 0) {
        aspect = wm.height / wm.width;
      }
    }
    final shortSide = math.min(image.width, image.height).toDouble();
    final marginPx = (shortSide * marginPercent) / 100.0;
    var wmW = math.max(1, ((shortSide * scalePercent) / 100.0).round());
    var wmH = math.max(1, (wmW * aspect).round());
    if (wmH > image.height) {
      wmH = image.height;
      wmW = math.max(1, (wmH / aspect).round());
    }
    return runIsolated(
      _findPositionIsolate,
      _SmartPositionArgs(
        base: IsolateBytes(image.rgba),
        baseWidth: image.width,
        baseHeight: image.height,
        wmW: wmW,
        wmH: wmH,
        marginPx: marginPx,
      ),
    );
  }

  // ==================== 3. 盲水印 (Koch-Zhao DCT) ====================

  /// 嵌入盲水印，返回嵌入后的 PNG 字节
  ///
  /// 载荷为 [text]；[strength] 1~5 控制频域扰动幅度 (越高越抗压缩)。
  /// 图像容量不足或解码失败时原样返回。
  /// 根 isolate Skia 解码 → compute 纯像素 DCT 嵌入 → 根 isolate Skia 编码。
  static Future<Uint8List> embedBlindWatermarkAsync(
    Uint8List imageBytes, {
    required String text,
    int strength = 3,
  }) async {
    if (text.isEmpty) return imageBytes;
    final image = await decodeToRawRgba(imageBytes);
    if (image == null) return imageBytes;

    final payload = _buildBlindPayload(text);
    if (payload == null) return imageBytes;

    final outRgba = await runIsolated(
      _embedBlindIsolate,
      _BlindEmbedTask(
        image: IsolateBytes(image.rgba),
        width: image.width,
        height: image.height,
        payload: payload,
        strength: strength.clamp(1, 5),
      ),
    );
    if (outRgba == null) return imageBytes;
    return encodeRawRgbaToPng(outRgba.materialize(), image.width, image.height);
  }

  /// 从图像字节提取盲水印文本，无水印或校验失败返回 null
  static Future<String?> extractBlindWatermarkAsync(
    Uint8List imageBytes,
  ) async {
    final image = await decodeToRawRgba(imageBytes);
    if (image == null) return null;
    return runIsolated(
      _extractBlindIsolate,
      _BlindExtractTask(
        image: IsolateBytes(image.rgba),
        width: image.width,
        height: image.height,
      ),
    );
  }

  /// 构造盲水印载荷: magic(4) + 长度(2 BE) + CRC16(2 BE) + UTF-8 数据
  static Uint8List? _buildBlindPayload(String text) {
    final data = utf8.encode(text);
    if (data.isEmpty || data.length > 0xFFFF) return null;
    final payload = Uint8List(8 + data.length);
    payload.setAll(0, _blindMagic);
    payload[4] = (data.length >> 8) & 0xFF;
    payload[5] = data.length & 0xFF;
    final crc = _crc16(data);
    payload[6] = (crc >> 8) & 0xFF;
    payload[7] = crc & 0xFF;
    payload.setAll(8, data);
    return payload;
  }

  static String? _decodeBlindPayload(Uint8List bits) {
    final byteLen = bits.length ~/ 8;
    if (byteLen < 8) return null;
    final bytes = Uint8List(byteLen);
    for (var i = 0; i < bits.length; i++) {
      if (bits[i] == 1) {
        bytes[i ~/ 8] |= 1 << (7 - (i % 8));
      }
    }
    // 校验 magic
    for (var i = 0; i < _blindMagic.length; i++) {
      if (bytes[i] != _blindMagic[i]) return null;
    }
    final dataLen = (bytes[4] << 8) | bytes[5];
    if (dataLen == 0 || 8 + dataLen > byteLen) return null;
    final data = bytes.sublist(8, 8 + dataLen);
    final crc = (bytes[6] << 8) | bytes[7];
    if (_crc16(data) != crc) return null;
    try {
      return utf8.decode(data);
    } catch (_) {
      return null;
    }
  }

  /// Koch-Zhao: 每个独立 PRNG 选出的中频系数对编码一个比特
  /// (纯像素计算，直接改写 [rgba]，compute isolate 内执行)
  static bool _embedBlindBits(
    Uint8List rgba,
    int width,
    int height,
    Uint8List payload,
    int strength,
  ) {
    final blocksX = width ~/ 8;
    final blocksY = height ~/ 8;
    final totalBlocks = blocksX * blocksY;
    final payloadBits = payload.length * 8;
    // 至少 2 倍冗余 (重复嵌入 + 多数投票提取)
    if (totalBlocks < payloadBits * 2) return false;

    // 基础 QIM 步长 (纹理区全强度)；平坦块在 _embedBlindBlock 内自适应降档
    final step = _blindMargin(strength);
    final rng = _BlindRng(_blindKeySeed);
    final block = List<double>.filled(64, 0.0);
    final dct = List<double>.filled(64, 0.0);

    var blockIndex = 0;
    for (var by = 0; by < blocksY; by++) {
      for (var bx = 0; bx < blocksX; bx++) {
        final bit =
            (payload[(blockIndex % payloadBits) ~/ 8] >>
                (7 - (blockIndex % payloadBits) % 8)) &
            1;
        final pairIndex = rng.nextInt(_blindPairs.length);
        _embedBlindBlock(
          rgba,
          width,
          bx * 8,
          by * 8,
          bit,
          _blindPairs[pairIndex],
          step,
          block,
          dct,
        );
        blockIndex++;
      }
    }
    return true;
  }

  static Uint8List? _extractBlindBits(Uint8List rgba, int width, int height) {
    final blocksX = width ~/ 8;
    final blocksY = height ~/ 8;
    final totalBlocks = blocksX * blocksY;
    if (totalBlocks < 16) return null;

    // 1. 按嵌入侧同一 PRNG 序列逐块提取原始比特
    final rawBits = Uint8List(totalBlocks);
    final rng = _BlindRng(_blindKeySeed);
    final block = List<double>.filled(64, 0.0);
    final dct = List<double>.filled(64, 0.0);
    var idx = 0;
    for (var by = 0; by < blocksY; by++) {
      for (var bx = 0; bx < blocksX; bx++) {
        final pairIndex = rng.nextInt(_blindPairs.length);
        rawBits[idx++] = _extractBlindBlockBit(
          rgba,
          width,
          bx * 8,
          by * 8,
          _blindPairs[pairIndex],
          block,
          dct,
        );
      }
    }

    // 2. 载荷头部 (magic+len=8 字节) 固定映射在前 64 个块，可直接读出
    if (totalBlocks < 64) return null;
    final headerBits = Uint8List(64);
    for (var i = 0; i < 64; i++) {
      headerBits[i] = rawBits[i];
    }
    final headerBytes = Uint8List(8);
    for (var i = 0; i < 64; i++) {
      if (headerBits[i] == 1) {
        headerBytes[i ~/ 8] |= 1 << (7 - (i % 8));
      }
    }
    for (var i = 0; i < _blindMagic.length; i++) {
      if (headerBytes[i] != _blindMagic[i]) return null;
    }
    final dataLen = (headerBytes[4] << 8) | headerBytes[5];
    if (dataLen == 0 || dataLen > 0xFFFF) return null;

    // 3. 按真实载荷长度做多数投票解码 (冗余重复嵌入)
    final payloadBits = (8 + dataLen) * 8;
    if (payloadBits > totalBlocks) return null;
    final bits = Uint8List(payloadBits);
    for (var i = 0; i < payloadBits; i++) {
      var ones = 0;
      var zeros = 0;
      for (var b = i; b < totalBlocks; b += payloadBits) {
        if (rawBits[b] == 1) {
          ones++;
        } else {
          zeros++;
        }
      }
      bits[i] = ones >= zeros ? 1 : 0;
    }
    return bits;
  }

  /// Koch-Zhao 单块嵌入 (QIM 奇偶格点量化 + 平坦区自适应步长 + 色相安全写回)
  ///
  /// 1. QIM: bit=1 把系数差 d 吸附到最近的 {+Δ/2, +3Δ/2, ...} 格点，
  ///    bit=0 吸附到 {-Δ/2, -3Δ/2, ...}。单系数对最大位移 Δ/2 (旧强制余量
  ///    方案为 Δ+2)，平均畸变约减半；提取端只判 d 符号，解码保证
  ///    |d| >= Δ/2 且符号正确，与旧已嵌入图的提取完全向后兼容。
  /// 2. 平坦块感知掩码：中高频能量低的块 (皮肤/天空/纯色背景) 步长降到
  ///    约 1/3，视觉接近无损；纹理区保持全强度鲁棒。提取端无需感知能量。
  /// 3. 写回时 RGB 三通道加同一增量并按像素公共区间钳制，色相严格保持。
  static void _embedBlindBlock(
    Uint8List rgba,
    int imgWidth,
    int px,
    int py,
    int bit,
    (int, int, int, int) pair,
    double baseStep,
    List<double> block,
    List<double> dct,
  ) {
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 8; x++) {
        final i = ((py + y) * imgWidth + (px + x)) * 4;
        block[y * 8 + x] =
            0.299 * rgba[i] + 0.587 * rgba[i + 1] + 0.114 * rgba[i + 2];
      }
    }

    // 2. 正向 DCT
    _dct8x8(block, dct);

    // 平坦块能量评估 (中高频 u+v>=2，排除 DC 与最低频)
    var energy = 0.0;
    for (var i = 0; i < 64; i++) {
      final u = i % 8;
      final v = i ~/ 8;
      if (u + v < 2) continue;
      energy += dct[i].abs();
    }
    final step =
        baseStep * (energy >= kTexturedBlockEnergy ? 1.0 : kFlatStepScale);

    // QIM 奇偶格点量化
    final (u1, v1, u2, v2) = pair;
    final i1 = v1 * 8 + u1;
    final i2 = v2 * 8 + u2;
    final d = dct[i1] - dct[i2];
    final half = step / 2;
    final newD = bit == 1
        ? half + step * math.max(0, ((d - half) / step).round())
        : -half - step * math.max(0, ((-d - half) / step).round());
    final adjust = (newD - d) / 2;
    dct[i1] += adjust;
    dct[i2] -= adjust;

    // 3. 逆向 DCT 并写回 (亮度差值等量叠加到 RGB，保持色相)
    _idct8x8(dct, block);
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 8; x++) {
        final i = ((py + y) * imgWidth + (px + x)) * 4;
        final oldLuma =
            0.299 * rgba[i] + 0.587 * rgba[i + 1] + 0.114 * rgba[i + 2];
        final delta = (block[y * 8 + x] - oldLuma).round();
        if (delta == 0) continue;
        // 像素级公共区间钳制：三通道加同一个值，色相严格保持，
        // 不再逐通道独立 clamp 造成极亮/极暗处偏色
        final lo = -math.min(math.min(rgba[i], rgba[i + 1]), rgba[i + 2]);
        final hi = 255 - math.max(math.max(rgba[i], rgba[i + 1]), rgba[i + 2]);
        final shift = delta.clamp(lo, hi).toInt();
        if (shift == 0) continue;
        rgba[i] += shift;
        rgba[i + 1] += shift;
        rgba[i + 2] += shift;
      }
    }
  }

  static int _extractBlindBlockBit(
    Uint8List rgba,
    int imgWidth,
    int px,
    int py,
    (int, int, int, int) pair,
    List<double> block,
    List<double> dct,
  ) {
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 8; x++) {
        final i = ((py + y) * imgWidth + (px + x)) * 4;
        block[y * 8 + x] =
            0.299 * rgba[i] + 0.587 * rgba[i + 1] + 0.114 * rgba[i + 2];
      }
    }
    _dct8x8(block, dct);
    final (u1, v1, u2, v2) = pair;
    final d = dct[v1 * 8 + u1] - dct[v2 * 8 + u2];
    return d > 0 ? 1 : 0;
  }

  static double _blindMargin(int strength) {
    // 强度 1~5 -> QIM 步长 16~80 (正交 DCT 中频系数量级，对应像素扰动约 T/8)。
    // strength 语义不变：越高越抗压缩；平坦块在 _embedBlindBlock 内自适应降档，
    // 低档强度下平坦区抗 JPEG 重压缩能力相应下降，这是可接受的取舍。
    return 10.0 + strength * 12.0;
  }

  /// 平坦块判定阈值：块内中高频 DCT 系数绝对值之和 (u+v>=2，排除 DC)。
  /// 依据 2026-09 用 3 张真实 NAI 生成图 (832x1216 两张、1024x1024 一张)
  /// 实测 E 分布校准：p25≈33~46 / p50≈96~151 / p75≈283~441，E<200 占
  /// 56%~67% (皮肤/天空/渐变等视觉平坦区)，E>=200 的块含真实纹理细节。
  static const double kTexturedBlockEnergy = 200.0;

  /// 平坦块嵌入步长缩放：扰动降到约 1/3，视觉接近无损；
  /// 纹理区保持全强度鲁棒。提取端只判符号，无需感知能量。
  static const double kFlatStepScale = 0.35;

  static const List<int> _blindMagic = [0x4E, 0x48, 0x57, 0x4D]; // 'NHWM'
  static const int _blindKeySeed = 0x4E48574D; // 固定内部密钥

  /// Koch-Zhao 中频系数对候选 (u1, v1, u2, v2)，均处于 8x8 DCT 中频区
  static const List<(int, int, int, int)> _blindPairs = [
    (1, 5, 5, 1),
    (3, 3, 4, 2),
    (2, 4, 4, 3),
    (1, 6, 6, 1),
    (2, 5, 5, 2),
    (2, 6, 6, 2),
    (3, 5, 5, 3),
    (1, 4, 4, 1),
    (2, 3, 3, 2),
    (3, 4, 4, 3),
    (1, 3, 3, 1),
    (2, 2, 3, 3),
    (1, 2, 2, 1),
    (1, 5, 2, 6),
    (4, 4, 5, 5),
  ];

  static int _crc16(List<int> data) {
    var crc = 0xFFFF;
    for (final b in data) {
      crc ^= b << 8;
      for (var i = 0; i < 8; i++) {
        if ((crc & 0x8000) != 0) {
          crc = ((crc << 1) ^ 0x1021) & 0xFFFF;
        } else {
          crc = (crc << 1) & 0xFFFF;
        }
      }
    }
    return crc;
  }

  /// 分离式正交 8 点 DCT-II / DCT-III (查表 + 行列两趟)
  static final List<double> _cosTable = _buildCosTable();

  static List<double> _buildCosTable() {
    final table = List<double>.filled(64, 0.0);
    for (var k = 0; k < 8; k++) {
      for (var n = 0; n < 8; n++) {
        table[k * 8 + n] = math.cos((2 * n + 1) * k * math.pi / 16);
      }
    }
    return table;
  }

  static double _dctScale(int k) => k == 0 ? _s0 : _s1;
  static final double _s0 = math.sqrt(1 / 8);
  static final double _s1 = math.sqrt(2 / 8);

  /// 正交 2D DCT-II: F(v,u) = c(v)c(u) ΣΣ f(y,x) cos... (先 行后 列)
  static void _dct8x8(List<double> src, List<double> dst) {
    final tmp = List<double>.filled(64, 0.0);
    // 行变换
    for (var y = 0; y < 8; y++) {
      for (var k = 0; k < 8; k++) {
        var sum = 0.0;
        for (var n = 0; n < 8; n++) {
          sum += src[y * 8 + n] * _cosTable[k * 8 + n];
        }
        tmp[y * 8 + k] = sum * _dctScale(k);
      }
    }
    // 列变换
    for (var x = 0; x < 8; x++) {
      for (var k = 0; k < 8; k++) {
        var sum = 0.0;
        for (var n = 0; n < 8; n++) {
          sum += tmp[n * 8 + x] * _cosTable[k * 8 + n];
        }
        dst[k * 8 + x] = sum * _dctScale(k);
      }
    }
  }

  /// 正交 2D DCT-III (逆变换): 先列后行
  static void _idct8x8(List<double> src, List<double> dst) {
    final tmp = List<double>.filled(64, 0.0);
    // 列逆变换
    for (var x = 0; x < 8; x++) {
      for (var n = 0; n < 8; n++) {
        var sum = 0.0;
        for (var k = 0; k < 8; k++) {
          sum += _dctScale(k) * src[k * 8 + x] * _cosTable[k * 8 + n];
        }
        tmp[n * 8 + x] = sum;
      }
    }
    // 行逆变换
    for (var y = 0; y < 8; y++) {
      for (var n = 0; n < 8; n++) {
        var sum = 0.0;
        for (var k = 0; k < 8; k++) {
          sum += _dctScale(k) * tmp[y * 8 + k] * _cosTable[k * 8 + n];
        }
        dst[y * 8 + n] = sum;
      }
    }
  }

  // ==================== 4. 统一导出处理管道 ====================

  /// 根据全局配置处理用于复制或下载的图片字节
  ///
  /// 顺序：可见水印合成 -> 元数据抹除 -> 盲水印嵌入 (盲水印始终最后，确保不被后续处理破坏)
  static Future<Uint8List> processExportImage({
    required Uint8List rawBytes,
    required bool stripMetadata,
    required bool enableWatermark,
    WatermarkConfig? watermarkConfig,
    Uint8List? watermarkBytes,
  }) async {
    var resultBytes = rawBytes;

    // 1. 添加可见水印 (若开启且提供了水印数据)
    if (enableWatermark &&
        watermarkBytes != null &&
        watermarkBytes.isNotEmpty &&
        watermarkConfig != null) {
      try {
        resultBytes = await applyWatermarkAsync(
          imageBytes: resultBytes,
          watermarkBytes: watermarkBytes,
          config: watermarkConfig,
        );
      } catch (_) {}
    }

    // 2. 剔除元数据 (若开启)
    if (stripMetadata) {
      try {
        resultBytes = await ImageMetadataService.stripPngMetadataAsync(
          resultBytes,
        );
      } catch (_) {}
    }

    // 3. 嵌入盲水印 (若开启且有载荷文本)
    final blindText = watermarkConfig?.blindText.trim() ?? '';
    if (watermarkConfig != null &&
        watermarkConfig.blindEnabled &&
        blindText.isNotEmpty) {
      try {
        resultBytes = await embedBlindWatermarkAsync(
          resultBytes,
          text: blindText,
          strength: watermarkConfig.blindStrength,
        );
      } catch (_) {}
    }

    return resultBytes;
  }
}

// ==================== Isolate 入口与参数对象 ====================

class _WatermarkTaskArgs {
  final IsolateBytes base;
  final int baseWidth;
  final int baseHeight;
  final IsolateBytes wm;
  final int wmWidth;
  final int wmHeight;
  final WatermarkConfig config;

  const _WatermarkTaskArgs({
    required this.base,
    required this.baseWidth,
    required this.baseHeight,
    required this.wm,
    required this.wmWidth,
    required this.wmHeight,
    required this.config,
  });
}

IsolateBytes _applyWatermarkIsolate(_WatermarkTaskArgs args) {
  return IsolateBytes(WatermarkService._applyWatermarkPixels(args));
}

class _SmartPositionArgs {
  final IsolateBytes base;
  final int baseWidth;
  final int baseHeight;
  final int wmW;
  final int wmH;
  final double marginPx;

  const _SmartPositionArgs({
    required this.base,
    required this.baseWidth,
    required this.baseHeight,
    required this.wmW,
    required this.wmH,
    required this.marginPx,
  });
}

(double, double) _findPositionIsolate(_SmartPositionArgs args) {
  return WatermarkService.findLowInformationPosition(
    RawRgbaImage(
      rgba: args.base.materialize(),
      width: args.baseWidth,
      height: args.baseHeight,
    ),
    wmW: args.wmW,
    wmH: args.wmH,
    marginPx: args.marginPx,
  );
}

class _BlindEmbedTask {
  final IsolateBytes image;
  final int width;
  final int height;
  final Uint8List payload;
  final int strength;

  const _BlindEmbedTask({
    required this.image,
    required this.width,
    required this.height,
    required this.payload,
    required this.strength,
  });
}

/// 容量不足时返回 null (调用方原样返回原图)
IsolateBytes? _embedBlindIsolate(_BlindEmbedTask args) {
  final rgba = args.image.materialize();
  final ok = WatermarkService._embedBlindBits(
    rgba,
    args.width,
    args.height,
    args.payload,
    args.strength,
  );
  return ok ? IsolateBytes(rgba) : null;
}

class _BlindExtractTask {
  final IsolateBytes image;
  final int width;
  final int height;

  const _BlindExtractTask({
    required this.image,
    required this.width,
    required this.height,
  });
}

String? _extractBlindIsolate(_BlindExtractTask args) {
  final bits = WatermarkService._extractBlindBits(
    args.image.materialize(),
    args.width,
    args.height,
  );
  if (bits == null) return null;
  return WatermarkService._decodeBlindPayload(bits);
}

/// 盲水印系数对选择用的确定性 PRNG (xorshift32)
class _BlindRng {
  int _state;

  _BlindRng(int seed) : _state = seed == 0 ? 0x9E3779B9 : seed;

  int nextInt(int max) {
    var x = _state;
    x ^= (x << 13) & 0xFFFFFFFF;
    x ^= x >>> 17;
    x ^= (x << 5) & 0xFFFFFFFF;
    _state = x;
    return (x & 0x7FFFFFFF) % max;
  }
}
