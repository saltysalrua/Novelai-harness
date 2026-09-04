import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Uint8List;
import '../../../../data/models/novelai_models.dart';

/// 全屏大图查看器：自由平移缩放画板 (滚轮纯缩放、不随鼠标偏移) + 顶部关闭按钮
void showImageLightbox(
  BuildContext context,
  NaiGeneratedImage image, {
  Future<Uint8List?> Function()? loader,
}) {
  if (image.bytes.isNotEmpty) {
    showImageLightboxBytes(context, image.bytes);
  } else {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.9),
      barrierDismissible: true,
      builder: (ctx) => ImageLightboxDialog(
        bytes: null,
        placeholderBytes: image.thumbnailBytes,
        loader: loader,
      ),
    );
  }
}

/// 裸字节版全屏大图查看器 (对话卡图片附件/工具结果图等无参数模型场景共用)
void showImageLightboxBytes(BuildContext context, Uint8List bytes) {
  showDialog(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.9),
    barrierDismissible: true,
    builder: (ctx) => ImageLightboxDialog(bytes: bytes),
  );
}

class ImageLightboxDialog extends StatefulWidget {
  final Uint8List? bytes;
  final Uint8List? placeholderBytes;
  final Future<Uint8List?> Function()? loader;

  const ImageLightboxDialog({
    super.key,
    this.bytes,
    this.placeholderBytes,
    this.loader,
  });

  @override
  State<ImageLightboxDialog> createState() => _ImageLightboxDialogState();
}

class _ImageLightboxDialogState extends State<ImageLightboxDialog> {
  static const double _minScale = 0.2;
  static const double _maxScale = 10.0;

  late final TransformationController _transformationController;
  Uint8List? _activeBytes;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();
    _activeBytes = widget.bytes;
    if ((_activeBytes == null || _activeBytes!.isEmpty) &&
        widget.loader != null) {
      _isLoading = true;
      widget.loader!().then((loaded) {
        if (mounted && loaded != null && loaded.isNotEmpty) {
          setState(() {
            _activeBytes = loaded;
            _isLoading = false;
          });
        } else if (mounted) {
          setState(() => _isLoading = false);
        }
      });
    }
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  void _handlePointerSignal(PointerSignalEvent event, Size viewportSize) {
    if (event is! PointerScrollEvent) return;

    final double dy = event.scrollDelta.dy;
    if (dy == 0) return;

    // dy < 0 向上滚轮（放大），dy > 0 向下滚轮（缩小）
    // 指数因子支持离散滚轮与触控板平滑缩放
    final double zoomMultiplier = math.exp(-dy / 300.0).clamp(0.5, 2.0);

    final Matrix4 currentMatrix = _transformationController.value;
    final double currentScale = currentMatrix.getMaxScaleOnAxis();
    final double targetScale =
        (currentScale * zoomMultiplier).clamp(_minScale, _maxScale);

    if (currentScale == targetScale || currentScale <= 0) return;

    final double effectiveMultiplier = targetScale / currentScale;

    // 以视口中心为固定缩放原点（无论鼠标当前悬停在何处，均在中心纯缩放）
    final Offset center =
        Offset(viewportSize.width / 2, viewportSize.height / 2);

    final double tx = currentMatrix.storage[12];
    final double ty = currentMatrix.storage[13];

    final double newTx =
        effectiveMultiplier * tx + (1.0 - effectiveMultiplier) * center.dx;
    final double newTy =
        effectiveMultiplier * ty + (1.0 - effectiveMultiplier) * center.dy;

    _transformationController.value =
        Matrix4.diagonal3Values(targetScale, targetScale, 1.0)
          ..setTranslationRaw(newTx, newTy, 0.0);
  }

  void _handleDoubleTap() {
    final double currentScale =
        _transformationController.value.getMaxScaleOnAxis();
    if ((currentScale - 1.0).abs() > 0.01) {
      // 非 1:1 原图状态下双击重置
      _transformationController.value = Matrix4.identity();
    } else {
      // 1:1 状态下双击放大到 2x
      _transformationController.value =
          Matrix4.diagonal3Values(2.0, 2.0, 1.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewportSize =
              Size(constraints.maxWidth, constraints.maxHeight);

          return Stack(
            fit: StackFit.expand,
            children: [
              // 1. 全屏自由平移与滚轮纯缩放画板
              Positioned.fill(
                child: Listener(
                  onPointerSignal: (event) =>
                      _handlePointerSignal(event, viewportSize),
                  child: GestureDetector(
                    onDoubleTap: _handleDoubleTap,
                    child: InteractiveViewer(
                      transformationController: _transformationController,
                      minScale: _minScale,
                      maxScale: _maxScale,
                      scaleEnabled: false, // 禁用默认的以鼠标为原点缩放，交由 Listener 统一在中心纯缩放
                      panEnabled: true,
                      boundaryMargin: const EdgeInsets.all(double.infinity),
                      child: Center(
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            if (_activeBytes != null && _activeBytes!.isNotEmpty)
                              Image.memory(
                                _activeBytes!,
                                fit: BoxFit.contain,
                                gaplessPlayback: true,
                              )
                            else if (widget.placeholderBytes != null &&
                                widget.placeholderBytes!.isNotEmpty)
                              Image.memory(
                                widget.placeholderBytes!,
                                fit: BoxFit.contain,
                                gaplessPlayback: true,
                              )
                            else
                              const SizedBox(width: 100, height: 100),
                            if (_isLoading)
                              const Center(
                                child: SizedBox(
                                  width: 32,
                                  height: 32,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white70,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // 2. 右上角关闭按钮 (无多余信息提示条，纯净直接)
              Positioned(
                top: 16,
                right: 16,
                child: IconButton(
                  icon: const Icon(
                    Icons.close_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                  tooltip: '关闭大图展示',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.5),
                    hoverColor: Colors.black.withValues(alpha: 0.8),
                    padding: const EdgeInsets.all(8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: const BorderSide(color: Colors.white12),
                    ),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
