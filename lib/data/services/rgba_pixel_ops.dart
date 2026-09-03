import 'dart:math' as math;
import 'dart:typed_data';

/// Flat RGBA 纯像素运算共享库 (无 Flutter / dart:ui 依赖，可进 compute isolate)
///
/// 所有函数操作裸 RGBA 字节缓冲，像素下标 `(y * width + x) * 4`，
/// 无隐式 alpha 语义。

/// 裁剪 RGBA 缓冲的矩形区域 (行级 memcpy)
Uint8List cropRgba(Uint8List src, int srcWidth, int x, int y, int w, int h) {
  final out = Uint8List(w * h * 4);
  for (var row = 0; row < h; row++) {
    final s = ((y + row) * srcWidth + x) * 4;
    out.setRange(row * w * 4, (row + 1) * w * 4, src, s);
  }
  return out;
}

/// 分离式 Catmull-Rom 双三次缩放 (RGBA 四通道同核处理，边缘钳制)
Uint8List resizeRgbaCubic(Uint8List src, int sw, int sh, int dw, int dh) {
  if (sw == dw && sh == dh) return src;
  // 水平通：(sw, sh) -> (dw, sh)
  final mid = _resampleAxis(src, sw, sh, dw, sh, true);
  // 垂直通：(dw, sh) -> (dw, dh)
  return _resampleAxis(mid, dw, sh, dw, dh, false);
}

/// 带 alpha 通道图像的缩放：预乘 -> Catmull-Rom 插值 -> 反预乘。
///
/// 直接对非预乘 RGBA 插值会让透明区域携带的 RGB 垃圾值
/// 渗入半透明边缘，形成黑边/白边光晕；预乘后透明像素 RGB 归零，
/// 插值出的边缘干净无晕。
Uint8List resizeRgbaCubicAlphaAware(
  Uint8List src,
  int sw,
  int sh,
  int dw,
  int dh,
) {
  if (sw == dw && sh == dh) return src;
  final premul = Uint8List.fromList(src);
  premultiplyRgbaInPlace(premul);
  final resized = resizeRgbaCubic(premul, sw, sh, dw, dh);
  unpremultiplyRgbaInPlace(resized);
  return resized;
}

/// 原地预乘 alpha (仅 a<255 像素变动)：RGB = RGB × A / 255
void premultiplyRgbaInPlace(Uint8List rgba) {
  for (var i = 0; i < rgba.length; i += 4) {
    final a = rgba[i + 3];
    if (a == 255) continue;
    if (a == 0) {
      rgba[i] = 0;
      rgba[i + 1] = 0;
      rgba[i + 2] = 0;
      continue;
    }
    rgba[i] = (rgba[i] * a + 127) ~/ 255;
    rgba[i + 1] = (rgba[i + 1] * a + 127) ~/ 255;
    rgba[i + 2] = (rgba[i + 2] * a + 127) ~/ 255;
  }
}

/// 原地反预乘 alpha (仅 0<A<255 像素变动)：RGB = RGB × 255 / A
void unpremultiplyRgbaInPlace(Uint8List rgba) {
  for (var i = 0; i < rgba.length; i += 4) {
    final a = rgba[i + 3];
    if (a == 0 || a == 255) continue;
    rgba[i] = (rgba[i] * 255 + a ~/ 2) ~/ a;
    rgba[i + 1] = (rgba[i + 1] * 255 + a ~/ 2) ~/ a;
    rgba[i + 2] = (rgba[i + 2] * 255 + a ~/ 2) ~/ a;
  }
}

/// 最近邻缩放 (蒙版专用：保持二值边界严格锐利)
Uint8List resizeRgbaNearest(Uint8List src, int sw, int sh, int dw, int dh) {
  if (sw == dw && sh == dh) return src;
  final out = Uint8List(dw * dh * 4);
  for (var y = 0; y < dh; y++) {
    final sy = (((y + 0.5) * sh) / dh).floor().clamp(0, sh - 1);
    for (var x = 0; x < dw; x++) {
      final sx = (((x + 0.5) * sw) / dw).floor().clamp(0, sw - 1);
      final s = (sy * sw + sx) * 4;
      final d = (y * dw + x) * 4;
      out[d] = src[s];
      out[d + 1] = src[s + 1];
      out[d + 2] = src[s + 2];
      out[d + 3] = src[s + 3];
    }
  }
  return out;
}

Uint8List _resampleAxis(
  Uint8List src,
  int sw,
  int sh,
  int dw,
  int dh,
  bool horizontal,
) {
  final out = Uint8List(dw * dh * 4);
  final srcLen = horizontal ? sw : sh;
  final dstLen = horizontal ? dw : dh;
  for (var d0 = 0; d0 < dstLen; d0++) {
    // 目标像素中心映射回源坐标
    final center = (d0 + 0.5) * srcLen / dstLen - 0.5;
    final base = center.floor();
    final taps = <int>[base - 1, base, base + 1, base + 2];
    final weights = List<double>.generate(4, (k) {
      return _catmullRom(center - taps[k]);
    });
    var wsum = 0.0;
    for (var k = 0; k < 4; k++) {
      taps[k] = taps[k].clamp(0, srcLen - 1);
      wsum += weights[k];
    }
    final rowLen = horizontal ? sh : dw;
    for (var d1 = 0; d1 < rowLen; d1++) {
      var r = 0.0, g = 0.0, b = 0.0, a = 0.0;
      for (var k = 0; k < 4; k++) {
        final w = weights[k] / wsum;
        if (w == 0) continue;
        final i = horizontal
            ? (d1 * sw + taps[k]) * 4
            : (taps[k] * sw + d1) * 4;
        r += src[i] * w;
        g += src[i + 1] * w;
        b += src[i + 2] * w;
        a += src[i + 3] * w;
      }
      final o = horizontal ? (d1 * dw + d0) * 4 : (d0 * dw + d1) * 4;
      out[o] = r.round().clamp(0, 255);
      out[o + 1] = g.round().clamp(0, 255);
      out[o + 2] = b.round().clamp(0, 255);
      out[o + 3] = a.round().clamp(0, 255);
    }
  }
  return out;
}

/// Catmull-Rom 插值核 (|d| <= 2)
double _catmullRom(double d) {
  final a = d.abs();
  if (a <= 1.0) return 1.5 * a * a * a - 2.5 * a * a + 1.0;
  if (a < 2.0) return -0.5 * a * a * a + 2.5 * a * a - 4.0 * a + 2.0;
  return 0.0;
}

/// 把 src 矩形以非预乘 alpha 混合盖进 dst (BlendMode.alpha 语义)：
/// out = dst * (1 - a) + src * a，四通道同式
void blendAlphaRect(
  Uint8List dst,
  int dstWidth,
  int dstHeight,
  Uint8List src,
  int srcWidth,
  int srcHeight, {
  required int dstX,
  required int dstY,
}) {
  for (var y = 0; y < srcHeight; y++) {
    final dy = dstY + y;
    if (dy < 0 || dy >= dstHeight) continue;
    for (var x = 0; x < srcWidth; x++) {
      final dx = dstX + x;
      if (dx < 0 || dx >= dstWidth) continue;
      final s = (y * srcWidth + x) * 4;
      final d = (dy * dstWidth + dx) * 4;
      final a = src[s + 3] / 255.0;
      if (a <= 0) continue;
      if (a >= 1.0) {
        dst[d] = src[s];
        dst[d + 1] = src[s + 1];
        dst[d + 2] = src[s + 2];
        dst[d + 3] = src[s + 3];
        continue;
      }
      for (var c = 0; c < 4; c++) {
        dst[d + c] = (dst[d + c] * (1 - a) + src[s + c] * a).round().clamp(
          0,
          255,
        );
      }
    }
  }
}

/// 把 src 矩形整像素替换进 dst (BlendMode.direct 语义，含 alpha，越界裁剪)
void copyRect(
  Uint8List dst,
  int dstWidth,
  int dstHeight,
  Uint8List src,
  int srcWidth,
  int srcHeight, {
  required int dstX,
  required int dstY,
}) {
  for (var y = 0; y < srcHeight; y++) {
    final dy = dstY + y;
    if (dy < 0 || dy >= dstHeight) continue;
    final copyW = math
        .min(srcWidth, math.max(0, dstWidth - math.max(0, dstX)))
        .toInt();
    if (copyW <= 0) break;
    final s = y * srcWidth * 4;
    final d = (dy * dstWidth + dstX) * 4;
    dst.setRange(d, d + copyW * 4, src, s);
  }
}
