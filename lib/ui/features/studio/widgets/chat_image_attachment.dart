import 'dart:convert';
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
    return AgentMessageImage(base64: base64Encode(imageBytes));
  } catch (_) {
    return null;
  }
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
    Widget thumb = ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      child: Image.memory(
        bytes,
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      ),
    );
    final tap = onTap;
    if (tap != null) {
      thumb = GestureDetector(
        onTap: tap,
        child: MouseRegion(
          cursor: SystemMouseCursors.zoomIn,
          child: thumb,
        ),
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
