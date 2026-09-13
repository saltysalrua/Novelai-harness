import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Uint8List;
import '../../../../data/models/novelai_models.dart';
import '../../../core/context_l10n.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../../core/widgets/app_scale_gesture_region.dart';

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

class _ImageLightboxDialogState extends State<ImageLightboxDialog>
    with SingleTickerProviderStateMixin {
  static const double _minScale = 0.2;
  static const double _maxScale = 10.0;

  late final TransformationController _transformationController;
  late final AnimationController _zoomController;
  Matrix4Tween? _zoomTween;
  double? _wheelTargetScale;
  double _wheelDirection = 0;
  Offset _lastFocalPoint = Offset.zero;
  double _lastGestureScale = 1;
  int _gesturePointerCount = 0;
  Uint8List? _activeBytes;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();
    _zoomController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    )..addListener(_handleZoomFrame);
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
    _zoomController.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  // 此处只有二维等比缩放，Z 始终为 1。不能用 getMaxScaleOnAxis：
  // 缩至 1 以下时它仍返回 Z 轴的 1，下一次滚轮便会算错比例并跳位。
  double get _currentScale => _transformationController.value.entry(0, 0);

  Matrix4 _scaleAround(
    double targetScale,
    Offset anchor, {
    Offset? nextAnchor,
  }) {
    final scenePoint = _transformationController.toScene(anchor);
    final destination = nextAnchor ?? anchor;
    final scale = targetScale.clamp(_minScale, _maxScale);
    return Matrix4.diagonal3Values(scale, scale, 1)..setTranslationRaw(
      destination.dx - scenePoint.dx * scale,
      destination.dy - scenePoint.dy * scale,
      0,
    );
  }

  void _handleZoomFrame() {
    if (_zoomTween case final tween?) {
      _transformationController.value = tween.transform(
        Curves.easeOutCubic.transform(_zoomController.value),
      );
    }
  }

  void _animateTo(Matrix4 target) {
    _zoomTween = Matrix4Tween(
      begin: _transformationController.value.clone(),
      end: target,
    );
    _zoomController.forward(from: 0);
  }

  void _stopZoom() {
    // 新手势从实际显示的位置接管，绝不让旧动画在下一帧写回旧平移量。
    _zoomController.stop();
    _zoomTween = null;
    _wheelTargetScale = null;
    _wheelDirection = 0;
  }

  void _handlePointerSignal(PointerSignalEvent event, Size viewportSize) {
    if (event is PointerScrollEvent) {
      final dy = event.scrollDelta.dy;
      if (!dy.isFinite || dy == 0) return;
      GestureBinding.instance.pointerSignalResolver.register(event, (_) {
        final multiplier = math.exp(-dy / 300).clamp(0.5, 2.0);
        // 连续同向滚轮累加目标，不丢步；反向立即以当前画面为起点，
        // 避免用户已经缩小，画面却仍在追赶上一次放大的目标。
        final baseScale =
            _zoomController.isAnimating && _wheelDirection == dy.sign
            ? _wheelTargetScale ?? _currentScale
            : _currentScale;
        final targetScale = (baseScale * multiplier).clamp(
          _minScale,
          _maxScale,
        );
        _wheelTargetScale = targetScale;
        _wheelDirection = dy.sign;
        _animateTo(_scaleAround(targetScale, viewportSize.center(Offset.zero)));
      });
    } else if (event is PointerScaleEvent) {
      if (!event.scale.isFinite || event.scale <= 0) return;
      GestureBinding.instance.pointerSignalResolver.register(event, (_) {
        _stopZoom();
        _transformationController.value = _scaleAround(
          _currentScale * event.scale,
          event.localPosition,
        );
      });
    }
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _stopZoom();
    _lastFocalPoint = details.localFocalPoint;
    _lastGestureScale = 1;
    _gesturePointerCount = details.pointerCount;
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    if (!details.scale.isFinite || details.scale <= 0) return;
    _stopZoom();
    // 手指数变化会改变质心，只重建基准，不把质心跳变误算成平移。
    if (_gesturePointerCount == details.pointerCount) {
      _transformationController.value = _scaleAround(
        _currentScale * details.scale / _lastGestureScale,
        _lastFocalPoint,
        nextAnchor: details.localFocalPoint,
      );
    }
    _lastFocalPoint = details.localFocalPoint;
    _lastGestureScale = details.scale;
    _gesturePointerCount = details.pointerCount;
  }

  void _handleDoubleTap(Size viewportSize) {
    _stopZoom();
    // 1 倍表示适应视口，并非原图像素 1:1；双击与滚轮共用中心锚点。
    _animateTo(
      (_currentScale - 1).abs() > 0.01
          ? Matrix4.identity()
          : _scaleAround(2, viewportSize.center(Offset.zero)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewportSize = Size(
            constraints.maxWidth,
            constraints.maxHeight,
          );

          return Stack(
            fit: StackFit.expand,
            children: [
              // 1. 全屏自由平移与滚轮纯缩放画板
              Positioned.fill(
                child: Listener(
                  onPointerDown: (_) => _stopZoom(),
                  onPointerPanZoomStart: (_) => _stopZoom(),
                  onPointerSignal: (event) =>
                      _handlePointerSignal(event, viewportSize),
                  child: AppScaleGestureRegion(
                    onDoubleTap: () => _handleDoubleTap(viewportSize),
                    onScaleStart: _handleScaleStart,
                    onScaleUpdate: _handleScaleUpdate,
                    // 手势与矩阵只有一个写入方；不叠加 InteractiveViewer 的
                    // 触控板平移和拖拽惯性。松手即停，图片解码层不逐帧重建。
                    child: ClipRect(
                      child: ValueListenableBuilder<Matrix4>(
                        valueListenable: _transformationController,
                        builder: (context, matrix, child) =>
                            Transform(transform: matrix, child: child),
                        child: RepaintBoundary(
                          child: Center(
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                if (_activeBytes != null &&
                                    _activeBytes!.isNotEmpty)
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
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
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
                ),
              ),

              // 2. 右上角关闭按钮 (无多余信息提示条，纯净直接)
              Positioned(
                top: 16,
                right: 16,
                child: AppIconButton(
                  icon: Icons.close_rounded,
                  tooltip: context.maybeL10n?.lightboxCloseTooltip ?? '关闭大图展示',
                  size: 42,
                  iconSize: 26,
                  variant: AppIconButtonVariant.elevated,
                  backgroundColor: Colors.black.withValues(alpha: 0.5),
                  borderColor: Colors.white.withValues(alpha: 0.12),
                  iconColor: Colors.white,
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
