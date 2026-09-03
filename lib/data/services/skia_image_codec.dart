import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// 裸 RGBA 像素图：编解码与像素运算之间的统一数据容器。
///
/// - 像素下标恒为 `(y * width + x) * 4`，无任何隐式 alpha 或通道序语义；
/// - 所有通道为 8bit 非预乘 RGBA (与 `ui.PixelFormat.rgba8888` 一致)；
/// - 只承载数据，不含解码器状态，可安全传入 compute isolate。
class RawRgbaImage {
  final Uint8List rgba;
  final int width;
  final int height;

  const RawRgbaImage({
    required this.rgba,
    required this.width,
    required this.height,
  });

  /// 像素 (x, y) 的首字节下标
  int offsetOf(int x, int y) => (y * width + x) * 4;

  bool get isValid =>
      width > 0 && height > 0 && rgba.length == width * height * 4;
}

/// 用 Skia 解码图片字节 → 裸 RGBA (Skia 内部走 IO 线程，不卡 UI)。
///
/// 仅限根 isolate 调用：`ui.Image` 不能跨 isolate 传递，需要进 compute 的
/// 像素运算请传 [RawRgbaImage.rgba] 字节。解码失败返回 null。
Future<RawRgbaImage?> decodeToRawRgba(Uint8List bytes) async {
  if (bytes.isEmpty) return null;
  ui.Codec? codec;
  try {
    codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    try {
      final data = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (data == null || data.lengthInBytes == 0) return null;
      return RawRgbaImage(
        rgba: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        width: frame.image.width,
        height: frame.image.height,
      );
    } finally {
      frame.image.dispose();
    }
  } catch (_) {
    return null;
  } finally {
    codec?.dispose();
  }
}

/// 把裸 RGBA 编码为 PNG 字节 (Skia 无损编码)。
///
/// 仅限根 isolate 调用。内部输入恒为有效像素缓冲 (调用方保证长度匹配)，
/// 编码失败抛 [StateError]。
Future<Uint8List> encodeRawRgbaToPng(
  Uint8List rgba,
  int width,
  int height,
) async {
  final image = await _imageFromRgba(rgba, width, height);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null || data.lengthInBytes == 0) {
      throw StateError('PNG 编码失败：toByteData 返回空数据。');
    }
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
  }
}

Future<ui.Image> _imageFromRgba(Uint8List rgba, int width, int height) {
  if (width <= 0 || height <= 0 || rgba.length != width * height * 4) {
    throw StateError('非法 RGBA 缓冲: ${rgba.length} bytes / ${width}x$height');
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    rgba,
    width,
    height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}
