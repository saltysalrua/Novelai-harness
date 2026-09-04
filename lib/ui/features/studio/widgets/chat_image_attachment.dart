import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../core/harness/types.dart';
import '../../../core/theme/app_theme.dart';

/// 对话图片附件上传上限 (一次最多随消息发送的图片数)
const int kMaxChatImageAttachments = 4;

/// 附件归一化后的最长边像素 (粘贴/上传的图统一缩到此上限内，控制请求体大小)
const int kChatImageMaxSide = 1024;

/// 把剪贴板/文件选择得到的原始图片字节 (PNG/JPEG/BMP 等) 归一化为
/// Chat 附件：最长边超过 [kChatImageMaxSide] 时等比缩小，统一重编码为 PNG，
/// 返回 base64 形态的 [AgentMessageImage]；解码失败返回 null。
Future<AgentMessageImage?> processImageAttachment(Uint8List rawBytes) async {
  if (rawBytes.isEmpty) return null;
  try {
    final codec = await ui.instantiateImageCodec(rawBytes);
    final frame = await codec.getNextFrame();
    final source = frame.image;

    ui.Image target = source;
    final srcW = source.width;
    final srcH = source.height;
    final longestSide = srcW > srcH ? srcW : srcH;
    if (longestSide > kChatImageMaxSide) {
      final scale = kChatImageMaxSide / longestSide;
      final newW = (srcW * scale).round().clamp(1, kChatImageMaxSide);
      final newH = (srcH * scale).round().clamp(1, kChatImageMaxSide);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImageRect(
        source,
        Rect.fromLTWH(0, 0, srcW.toDouble(), srcH.toDouble()),
        Rect.fromLTWH(0, 0, newW.toDouble(), newH.toDouble()),
        Paint()..filterQuality = ui.FilterQuality.medium,
      );
      final picture = recorder.endRecording();
      target = await picture.toImage(newW, newH);
      if (target != source) source.dispose();
    }

    final data = await target.toByteData(format: ui.ImageByteFormat.png);
    final imageBytes = data?.buffer.asUint8List();
    target.dispose();
    if (imageBytes == null || imageBytes.isEmpty) return null;
    return AgentMessageImage.fromBytes(bytes: imageBytes);
  } catch (_) {
    return null;
  }
}

/// 同步解析图片文件头里的画布尺寸 (PNG / JPEG / GIF / WebP)。
///
/// 图片 Widget 异步解码完成前没有内在尺寸，宽高未知时布局高度先按 0
/// 再突然撑开，滚动历史消息会一跳一跳；用本函数在 build 阶段同步读出
/// 宽高后以 AspectRatio 预留空间即可彻底消除跳动。解析失败 (格式不支持
/// 或数据损坏) 返回 null，调用方回退到不预留布局的旧行为。
({int width, int height})? probeImageHeaderSize(Uint8List bytes) {
  // PNG: 8 字节签名 + IHDR 块，width/height 为大端 32 位
  if (bytes.length >= 24 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    final w = bytes[16] << 24 | bytes[17] << 16 | bytes[18] << 8 | bytes[19];
    final h = bytes[20] << 24 | bytes[21] << 16 | bytes[22] << 8 | bytes[23];
    return (w > 0 && h > 0) ? (width: w, height: h) : null;
  }
  // GIF: 'GIF' + 版本 3 字节 + 小端 16 位 width/height
  if (bytes.length >= 10 &&
      bytes[0] == 0x47 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46) {
    final w = bytes[6] | bytes[7] << 8;
    final h = bytes[8] | bytes[9] << 8;
    return (w > 0 && h > 0) ? (width: w, height: h) : null;
  }
  // JPEG: FF D8 后逐段扫描，SOF0~SOF15 (DHT/JPG/DAC 除外) 段含尺寸
  if (bytes.length >= 4 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
    var i = 2;
    while (i + 9 < bytes.length) {
      if (bytes[i] != 0xFF) {
        i++;
        continue;
      }
      final marker = bytes[i + 1];
      // 0xFF 填充字节只跳 1 字节；无长度段的独立标记 (TEM/RST/EOI) 跳 2 字节
      if (marker == 0xFF) {
        i++;
        continue;
      }
      if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD9)) {
        i += 2;
        continue;
      }
      final segLen = (bytes[i + 2] << 8) | bytes[i + 3];
      final isSof =
          marker >= 0xC0 &&
          marker <= 0xCF &&
          marker != 0xC4 &&
          marker != 0xC8 &&
          marker != 0xCC;
      if (isSof) {
        final h = (bytes[i + 5] << 8) | bytes[i + 6];
        final w = (bytes[i + 7] << 8) | bytes[i + 8];
        return (w > 0 && h > 0) ? (width: w, height: h) : null;
      }
      if (segLen < 2) return null;
      i += 2 + segLen;
    }
    return null;
  }
  // WebP: 'RIFF' + 长度 + 'WEBP' + VP8X / VP8L / VP8 数据块
  if (bytes.length >= 30 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    final chunk = bytes[12] == 0x56 && bytes[13] == 0x50 && bytes[14] == 0x38;
    if (!chunk) return null;
    final kind = bytes[15]; // 'X' / 'L' / ' '(0x20)
    if (kind == 0x58) {
      // VP8X: 4 字节块头 + flags/reserved + 24 位小端 width-1 / height-1
      final w = (bytes[24] | bytes[25] << 8 | bytes[26] << 16) + 1;
      final h = (bytes[27] | bytes[28] << 8 | bytes[29] << 16) + 1;
      return (w > 0 && h > 0) ? (width: w, height: h) : null;
    }
    if (kind == 0x4C) {
      // VP8L: 签名 0x2F + 14 位 width-1 / 14 位 height-1 (LSB 优先)
      if (bytes.length >= 25 && bytes[20] == 0x2F) {
        final bits =
            bytes[21] | bytes[22] << 8 | bytes[23] << 16 | bytes[24] << 24;
        final w = (bits & 0x3FFF) + 1;
        final h = ((bits >> 14) & 0x3FFF) + 1;
        return (w > 0 && h > 0) ? (width: w, height: h) : null;
      }
      return null;
    }
    if (kind == 0x20) {
      // VP8 (有损关键帧): 3 字节帧标记 + 同步码 9D 01 2A + 14 位宽高
      if (bytes.length >= 30 &&
          bytes[23] == 0x9D &&
          bytes[24] == 0x01 &&
          bytes[25] == 0x2A) {
        final w = bytes[26] | (bytes[27] & 0x3F) << 8;
        final h = bytes[28] | (bytes[29] & 0x3F) << 8;
        return (w > 0 && h > 0) ? (width: w, height: h) : null;
      }
    }
  }
  return null;
}

/// 对话图片附件缩略图：输入栏待发送预览与用户消息历史渲染共用。
/// 传入 [onRemove] 时右上角叠加关闭按钮；传入 [onTap] 时可点击 (历史消息中放大查看)。
class ChatImageThumbnail extends StatelessWidget {
  final Uint8List bytes;

  /// 点击右上角关闭按钮移除附件 (仅输入栏待发送预览使用)
  final VoidCallback? onRemove;

  /// 点击缩略图本体 (历史消息中点开全屏大图)
  final VoidCallback? onTap;

  final double size;

  const ChatImageThumbnail({
    super.key,
    required this.bytes,
    this.onRemove,
    this.onTap,
    this.size = 64,
  });

  @override
  Widget build(BuildContext context) {
    // 按显示尺寸解码：缩略图 64~72px 却按附件原图 (最长边 1024px) 解码
    // 会白白占用成倍纹理内存，多图消息滚动时明显卡顿
    final thumbCacheWidth = (size * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(32, 512);
    Widget thumb = ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      child: Image.memory(
        bytes,
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        cacheWidth: thumbCacheWidth,
      ),
    );
    final tap = onTap;
    if (tap != null) {
      thumb = GestureDetector(
        onTap: tap,
        child: MouseRegion(cursor: SystemMouseCursors.zoomIn, child: thumb),
      );
    }
    final remove = onRemove;
    if (remove == null) return thumb;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        thumb,
        Positioned(
          top: -6,
          right: -6,
          child: GestureDetector(
            onTap: remove,
            child: Container(
              width: 18,
              height: 18,
              decoration: const BoxDecoration(
                color: Colors.black87,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close_rounded,
                size: 12,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
