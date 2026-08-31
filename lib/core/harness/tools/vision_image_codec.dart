import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// 发送给多模态模型的图片压缩上限：最长边 (像素)
const int kVisionImageMaxSide = 1024;

/// 压缩产物：字节 + 实际 MIME (编码失败回退原字节时保持原 MIME)
class VisionImagePayload {
  final Uint8List bytes;
  final String mimeType;

  const VisionImagePayload({required this.bytes, required this.mimeType});
}

/// 嗅探图片字节的真实 MIME 类型 (PNG / JPEG，其余按 PNG 处理)
String sniffImageMimeType(Uint8List bytes) {
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return 'image/png';
  }
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
    return 'image/jpeg';
  }
  return 'image/png';
}

/// 压缩发给多模态模型的图片附件：最长边超过 [maxSide] 时等比缩小并
/// 重编码为 PNG (透明底涂白)。解码或编码失败时回退原字节 (保持原 MIME)。
///
/// 多数视觉模型按分辨率计视觉 Token，1536px 级附件压到 1024px 后
/// Token 与请求体都会大幅下降；模型看不清细节时可用工具的
/// full_resolution 参数获取原图。
Future<VisionImagePayload> compressVisionImage(
  Uint8List bytes, {
  int maxSide = kVisionImageMaxSide,
}) async {
  if (bytes.isEmpty) {
    return VisionImagePayload(
      bytes: bytes,
      mimeType: sniffImageMimeType(bytes),
    );
  }
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final source = frame.image;

    final longSide = math.max(source.width, source.height);
    final scale = longSide > maxSide ? maxSide / longSide : 1.0;
    final outW = math.max(1, (source.width * scale).round());
    final outH = math.max(1, (source.height * scale).round());

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      ui.Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble()),
    );
    // 透明底涂白：透明区域对视觉模型不可见且多数模型不支持 alpha，
    // 统一压成白底避免误读成黑块
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble()),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
    canvas.drawImageRect(
      source,
      ui.Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
      ui.Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.medium,
    );

    final picture = recorder.endRecording();
    final outImage = await picture.toImage(outW, outH);
    final data = await outImage.toByteData(format: ui.ImageByteFormat.png);
    source.dispose();
    outImage.dispose();

    final outBytes = data?.buffer.asUint8List();
    if (outBytes == null || outBytes.isEmpty) {
      return VisionImagePayload(
        bytes: bytes,
        mimeType: sniffImageMimeType(bytes),
      );
    }
    return VisionImagePayload(bytes: outBytes, mimeType: 'image/png');
  } catch (_) {
    return VisionImagePayload(
      bytes: bytes,
      mimeType: sniffImageMimeType(bytes),
    );
  }
}
