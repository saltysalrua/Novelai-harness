import 'package:flutter/material.dart';
import '../../../../data/models/novelai_models.dart';

/// 全屏大图查看器：自由平移缩放画板 + 顶部尺寸/种子信息栏
void showImageLightbox(BuildContext context, NaiGeneratedImage image) {
  showDialog(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.88),
    builder: (ctx) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            // 1. 全屏自由平移缩放画板
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 0.2,
                maxScale: 10.0,
                child: Center(
                  child: Image.memory(
                    image.uint8Bytes,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                  ),
                ),
              ),
            ),

            // 2. 顶部工具提示栏与关闭按键
            Positioned(
              top: 8,
              left: 8,
              right: 8,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Text(
                      '${image.params.width} × ${image.params.height} · 种子: ${image.seed} · 可使用滚轮自由缩放与拖拽平移',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                    tooltip: '关闭大图展示',
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}
