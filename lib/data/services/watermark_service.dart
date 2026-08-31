import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import '../models/novelai_models.dart';
import 'image_metadata_service.dart';

/// 水印合成与盲水印服务
///
/// 职责：
/// 1. 可见水印合成 (2D 位置/缩放/不透明度/边距，支持自动对比度与智能低信息区域选位)；
/// 2. 智能选位算法 (基于梯度能量积分图，挑选信息量最低的放置区域)；
/// 3. 盲水印 (Koch-Zhao DCT 频域隐形水印，肉眼不可见，可带载荷提取)；
/// 4. 统一导出处理管道 (水印 -> 元数据抹除 -> 盲水印嵌入)。
class WatermarkService {
  // ==================== 1. 可见水印合成 ====================

  /// 将水印合成到目标图像上 (Isolate 后台执行)
  static Future<Uint8List> applyWatermarkAsync({
    required Uint8List imageBytes,
    required Uint8List watermarkBytes,
    required WatermarkConfig config,
  }) {
    return compute(
      _applyWatermarkIsolate,
      _WatermarkTaskArgs(
        imageBytes: imageBytes,
        watermarkBytes: watermarkBytes,
        config: config,
      ),
    );
  }

  /// 同步合成可见水印
  static Uint8List applyWatermark({
    required Uint8List imageBytes,
    required Uint8List watermarkBytes,
    required WatermarkConfig config,
  }) {
    final baseImage = img.decodeImage(imageBytes);
    final watermarkImage = img.decodeImage(watermarkBytes);

    if (baseImage == null || watermarkImage == null) {
      return imageBytes;
    }

    final imgW = baseImage.width;
    final imgH = baseImage.height;
    final shortSide = math.min(imgW, imgH);

    // 边距与水印目标尺寸计算 (与画板交互层算法一致)
    final marginPx = (shortSide * config.marginPercent) / 100.0;
    final targetWmW = math
        .max(1, (shortSide * config.scalePercent) / 100.0)
        .round()
        .clamp(1, imgW);
    final wmAspect = watermarkImage.height / watermarkImage.width;
    // 高度做 contain 钳制，避免超高水印溢出底图 (与画板预览一致)
    var targetWmH = math.max(1, targetWmW * wmAspect).round();
    var fittedWmW = targetWmW;
    if (targetWmH > imgH) {
      targetWmH = imgH;
      fittedWmW = math.min(targetWmW, math.max(1, (imgH / wmAspect).round()));
    }

    // 缩放水印
    final resizedWatermark = img.copyResize(
      watermarkImage,
      width: fittedWmW,
      height: targetWmH,
      interpolation: img.Interpolation.cubic,
    );

    // 计算放置坐标 (posX/posY 为 0.0~1.0；智能选位时由算法决定)
    final availW = math.max(0.0, imgW - 2 * marginPx - fittedWmW);
    final availH = math.max(0.0, imgH - 2 * marginPx - targetWmH);
    double posX = config.posX.clamp(0.0, 1.0);
    double posY = config.posY.clamp(0.0, 1.0);
    if (config.autoPosition) {
      final smart = findLowInformationPosition(
        baseImage,
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
      _applyAutoContrast(baseImage, resizedWatermark, dstX: dstX, dstY: dstY);
    }

    // 支持不透明度调节
    if (config.opacity < 1.0) {
      final alphaFactor = config.opacity.clamp(0.0, 1.0);
      for (final p in resizedWatermark) {
        p.a = (p.a * alphaFactor).round();
      }
    }

    // 合成水印
    img.compositeImage(baseImage, resizedWatermark, dstX: dstX, dstY: dstY);

    return Uint8List.fromList(img.encodePng(baseImage));
  }

  /// 自动对比度：统计水印覆盖区域的背景平均亮度，把水印向反色方向偏移
  static void _applyAutoContrast(
    img.Image baseImage,
    img.Image watermark, {
    required int dstX,
    required int dstY,
  }) {
    // 1. 统计背景区域平均亮度
    var lumaSum = 0.0;
    var sampleCount = 0;
    for (var y = dstY; y < dstY + watermark.height; y += 2) {
      if (y < 0 || y >= baseImage.height) continue;
      for (var x = dstX; x < dstX + watermark.width; x += 2) {
        if (x < 0 || x >= baseImage.width) continue;
        final p = baseImage.getPixel(x, y);
        lumaSum += 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
        sampleCount++;
      }
    }
    if (sampleCount == 0) return;
    final meanLuma = (lumaSum / sampleCount) / 255.0;

    // 2. 背景偏亮 -> 水印压暗；背景偏暗 -> 水印提亮
    const strength = 0.65;
    final target = meanLuma > 0.55 ? 0.0 : 1.0;
    final targetChannel = target * 255.0;
    for (final p in watermark) {
      if (p.a == 0) continue;
      p.r = (p.r * (1 - strength) + targetChannel * strength).round().clamp(
        0,
        255,
      );
      p.g = (p.g * (1 - strength) + targetChannel * strength).round().clamp(
        0,
        255,
      );
      p.b = (p.b * (1 - strength) + targetChannel * strength).round().clamp(
        0,
        255,
      );
    }
  }

  // ==================== 2. 智能低信息区域选位 ====================

  /// 在图像中寻找信息量最低的水印放置位置 (归一化 posX/posY，语义同 WatermarkConfig)
  ///
  /// 算法：把图像降采样后计算亮度梯度能量积分图，滑窗评估每个候选矩形
  /// (水印实际尺寸 + 边距约束) 的梯度总能量，取能量最低者——即细节/边缘
  /// 最少、对画面内容干扰最小的区域。
  static (double, double) findLowInformationPosition(
    img.Image image, {
    required int wmW,
    required int wmH,
    required double marginPx,
  }) {
    final imgW = image.width;
    final imgH = image.height;
    if (imgW < 8 || imgH < 8) return (1.0, 1.0);

    // 1. 降采样 (最长边不超过 480，选位不需要全分辨率精度)
    const maxSide = 480;
    final scale = math.min(1.0, maxSide / math.max(imgW, imgH));
    final smallW = math.max(8, (imgW * scale).round());
    final smallH = math.max(8, (imgH * scale).round());
    final small = scale < 1.0
        ? img.copyResize(image, width: smallW, height: smallH)
        : image;

    // 2. 亮度梯度能量 + 积分图
    final w = small.width;
    final h = small.height;
    final integral = List<double>.filled((w + 1) * (h + 1), 0.0);
    final luma = List<double>.filled(w * h, 0.0);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = small.getPixel(x, y);
        luma[y * w + x] = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
      }
    }
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

  /// 智能选位异步入口：基于图像字节计算低信息区域位置 (Isolate 后台执行)
  ///
  /// [watermarkBytes] 用于计算水印长宽比；为空时按 1:1 处理。
  static Future<(double, double)> findLowInformationPositionAsync(
    Uint8List imageBytes, {
    required double scalePercent,
    required double marginPercent,
    Uint8List? watermarkBytes,
  }) {
    return compute(
      _findPositionIsolate,
      _SmartPositionArgs(
        imageBytes: imageBytes,
        scalePercent: scalePercent,
        marginPercent: marginPercent,
        watermarkBytes: watermarkBytes,
      ),
    );
  }

  // ==================== 3. 盲水印 (Koch-Zhao DCT) ====================

  /// 嵌入盲水印 (Isolate 后台执行)，返回嵌入后的 PNG 字节
  ///
  /// 载荷为 [text]；[strength] 1~5 控制频域扰动幅度 (越高越抗压缩)。
  /// 图像容量不足或解码失败时原样返回。
  static Future<Uint8List> embedBlindWatermarkAsync(
    Uint8List imageBytes, {
    required String text,
    int strength = 3,
  }) {
    return compute(
      _embedBlindIsolate,
      _BlindWatermarkArgs(
        imageBytes: imageBytes,
        text: text,
        strength: strength,
      ),
    );
  }

  /// 从图像字节提取盲水印文本 (Isolate 后台执行)，无水印或校验失败返回 null
  static Future<String?> extractBlindWatermarkAsync(Uint8List imageBytes) {
    return compute(_extractBlindIsolate, imageBytes);
  }

  static Uint8List embedBlindWatermark(
    Uint8List imageBytes, {
    required String text,
    int strength = 3,
  }) {
    if (text.isEmpty) return imageBytes;
    final image = img.decodeImage(imageBytes);
    if (image == null) return imageBytes;

    final payload = _buildBlindPayload(text);
    if (payload == null) return imageBytes;

    final ok = _embedBlindBits(image, payload, strength.clamp(1, 5));
    if (!ok) return imageBytes;
    return Uint8List.fromList(img.encodePng(image));
  }

  static String? extractBlindWatermark(Uint8List imageBytes) {
    final image = img.decodeImage(imageBytes);
    if (image == null) return null;
    final bits = _extractBlindBits(image);
    if (bits == null) return null;
    return _decodeBlindPayload(bits);
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
  static bool _embedBlindBits(
    img.Image image,
    Uint8List payload,
    int strength,
  ) {
    final blocksX = image.width ~/ 8;
    final blocksY = image.height ~/ 8;
    final totalBlocks = blocksX * blocksY;
    final payloadBits = payload.length * 8;
    // 至少 2 倍冗余 (重复嵌入 + 多数投票提取)
    if (totalBlocks < payloadBits * 2) return false;

    final margin = _blindMargin(strength);
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
          image,
          bx * 8,
          by * 8,
          bit,
          _blindPairs[pairIndex],
          margin,
          block,
          dct,
        );
        blockIndex++;
      }
    }
    return true;
  }

  static Uint8List? _extractBlindBits(img.Image image) {
    final blocksX = image.width ~/ 8;
    final blocksY = image.height ~/ 8;
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
          image,
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

    // 3. 按真实载荷长度做多数投票解码 (元余重复嵌入)
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

  static void _embedBlindBlock(
    img.Image image,
    int px,
    int py,
    int bit,
    (int, int, int, int) pair,
    double margin,
    List<double> block,
    List<double> dct,
  ) {
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 8; x++) {
        final p = image.getPixel(px + x, py + y);
        block[y * 8 + x] = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
      }
    }

    // 2. 正向 DCT
    _dct8x8(block, dct);

    final (u1, v1, u2, v2) = pair;
    final i1 = v1 * 8 + u1;
    final i2 = v2 * 8 + u2;
    final d = dct[i1] - dct[i2];
    if (bit == 1 && d < margin) {
      final delta = (margin - d) / 2 + 1;
      dct[i1] += delta;
      dct[i2] -= delta;
    } else if (bit == 0 && d > -margin) {
      final delta = (d + margin) / 2 + 1;
      dct[i1] -= delta;
      dct[i2] += delta;
    }

    // 3. 逆向 DCT 并写回 (亮度差值等量叠加到 RGB，保持色相)
    _idct8x8(dct, block);
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 8; x++) {
        final p = image.getPixel(px + x, py + y);
        final oldLuma = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
        final delta = (block[y * 8 + x] - oldLuma).round();
        if (delta == 0) continue;
        p.r = (p.r + delta).clamp(0, 255);
        p.g = (p.g + delta).clamp(0, 255);
        p.b = (p.b + delta).clamp(0, 255);
      }
    }
  }

  static int _extractBlindBlockBit(
    img.Image image,
    int px,
    int py,
    (int, int, int, int) pair,
    List<double> block,
    List<double> dct,
  ) {
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 8; x++) {
        final p = image.getPixel(px + x, py + y);
        block[y * 8 + x] = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
      }
    }
    _dct8x8(block, dct);
    final (u1, v1, u2, v2) = pair;
    final d = dct[v1 * 8 + u1] - dct[v2 * 8 + u2];
    return d > 0 ? 1 : 0;
  }

  static double _blindMargin(int strength) {
    // 强度 1~5 -> 频域扰动余量 16~80 (正交 DCT 中频系数量级，对应像素扰动约 T/8)
    return 10.0 + strength * 12.0;
  }

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
  final Uint8List imageBytes;
  final Uint8List watermarkBytes;
  final WatermarkConfig config;

  const _WatermarkTaskArgs({
    required this.imageBytes,
    required this.watermarkBytes,
    required this.config,
  });
}

Uint8List _applyWatermarkIsolate(_WatermarkTaskArgs args) {
  return WatermarkService.applyWatermark(
    imageBytes: args.imageBytes,
    watermarkBytes: args.watermarkBytes,
    config: args.config,
  );
}

class _SmartPositionArgs {
  final Uint8List imageBytes;
  final Uint8List? watermarkBytes;
  final double scalePercent;
  final double marginPercent;

  const _SmartPositionArgs({
    required this.imageBytes,
    required this.scalePercent,
    required this.marginPercent,
    this.watermarkBytes,
  });
}

(double, double) _findPositionIsolate(_SmartPositionArgs args) {
  final image = img.decodeImage(args.imageBytes);
  if (image == null) return (1.0, 1.0);
  var aspect = 1.0;
  if (args.watermarkBytes != null) {
    final wm = img.decodeImage(args.watermarkBytes!);
    if (wm != null && wm.width > 0) {
      aspect = wm.height / wm.width;
    }
  }
  final shortSide = math.min(image.width, image.height);
  final marginPx = (shortSide * args.marginPercent) / 100.0;
  var wmW = math.max(1, (shortSide * args.scalePercent) / 100.0).round();
  var wmH = math.max(1, (wmW * aspect).round());
  if (wmH > image.height) {
    wmH = image.height;
    wmW = math.max(1, (wmH / aspect).round());
  }
  return WatermarkService.findLowInformationPosition(
    image,
    wmW: wmW,
    wmH: wmH,
    marginPx: marginPx,
  );
}

class _BlindWatermarkArgs {
  final Uint8List imageBytes;
  final String text;
  final int strength;

  const _BlindWatermarkArgs({
    required this.imageBytes,
    required this.text,
    required this.strength,
  });
}

Uint8List _embedBlindIsolate(_BlindWatermarkArgs args) {
  return WatermarkService.embedBlindWatermark(
    args.imageBytes,
    text: args.text,
    strength: args.strength,
  );
}

String? _extractBlindIsolate(Uint8List imageBytes) {
  return WatermarkService.extractBlindWatermark(imageBytes);
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
