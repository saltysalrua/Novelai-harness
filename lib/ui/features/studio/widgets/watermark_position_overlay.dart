import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../view_models/studio_view_model.dart';

// ==================== 水印 2D 位置与自由缩放画板交互层 ====================

/// 水印位置与缩放画板交互层 (直接在画板图像上拖动位置、拖拽边框/角点自由缩放、滚轮微调与实时预览)
class WatermarkPositionOverlay extends StatefulWidget {
  final StudioViewModel viewModel;

  const WatermarkPositionOverlay({super.key, required this.viewModel});

  @override
  State<WatermarkPositionOverlay> createState() =>
      _WatermarkPositionOverlayState();
}

class _WatermarkPositionOverlayState extends State<WatermarkPositionOverlay> {
  bool _isDragging = false;
  bool _isResizing = false;
  double _dragX = 0.5;
  double _dragY = 0.5;
  double _dragScale = 12.0;
  double _imageAspectRatio = 1.0;
  Uint8List? _lastImageBytes;

  // 缩放开始时锚定的左上角物理坐标，确保向右下拖动时左上角固定
  double _resizePinLeft = 0.0;
  double _resizePinTop = 0.0;

  @override
  void initState() {
    super.initState();
    _resolveImageAspect();
  }

  @override
  void didUpdateWidget(WatermarkPositionOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.viewModel.watermarkConfig.imageBytes != _lastImageBytes) {
      _resolveImageAspect();
    }
  }

  void _resolveImageAspect() {
    final bytes = widget.viewModel.watermarkConfig.imageBytes;
    _lastImageBytes = bytes;
    if (bytes == null || bytes.isEmpty) {
      _imageAspectRatio = 1.0;
      return;
    }
    decodeImageFromList(bytes)
        .then((img) {
          if (mounted && img.width > 0 && img.height > 0) {
            setState(() {
              _imageAspectRatio = img.width / img.height;
            });
          }
        })
        .catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = widget.viewModel;
    final config = viewModel.watermarkConfig;

    return LayoutBuilder(
      builder: (context, constraints) {
        final canvasSize = constraints.biggest;
        if (canvasSize.width <= 0 || canvasSize.height <= 0) {
          return const SizedBox.shrink();
        }

        final shortSide = math.min(canvasSize.width, canvasSize.height);
        final marginPx = (shortSide * config.marginPercent) / 100.0;
        final currentScale = _isResizing ? _dragScale : config.scalePercent;

        // 目标水印尺寸与长宽比适配 (与实际合成算法完全一致)
        final targetWmW = (shortSide * (currentScale / 100.0)).clamp(
          24.0,
          canvasSize.width,
        );
        final targetWmH =
            (targetWmW / (_imageAspectRatio > 0 ? _imageAspectRatio : 1.0))
                .clamp(16.0, canvasSize.height);

        final availW = math.max(
          0.0,
          canvasSize.width - 2 * marginPx - targetWmW,
        );
        final availH = math.max(
          0.0,
          canvasSize.height - 2 * marginPx - targetWmH,
        );

        final posX = (_isDragging || _isResizing)
            ? _dragX
            : config.posX.clamp(0.0, 1.0);
        final posY = (_isDragging || _isResizing)
            ? _dragY
            : config.posY.clamp(0.0, 1.0);

        final left = marginPx + availW * posX;
        final top = marginPx + availH * posY;

        return Stack(
          fit: StackFit.expand,
          children: [
            // 1. 半透明暗化背景层
            const ColoredBox(color: Color(0x38000000)),

            // 2. 九宫格辅助参考线
            CustomPaint(painter: _WatermarkGridGuidePainter()),

            // 3. 画布空白处点击直接定位
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) {
                if (availW <= 0 && availH <= 0) return;
                final clickX =
                    details.localPosition.dx - marginPx - targetWmW / 2;
                final clickY =
                    details.localPosition.dy - marginPx - targetWmH / 2;
                final newX = availW > 0
                    ? (clickX / availW).clamp(0.0, 1.0)
                    : config.posX;
                final newY = availH > 0
                    ? (clickY / availH).clamp(0.0, 1.0)
                    : config.posY;
                viewModel.updateWatermarkConfig(
                  config.copyWith(posX: newX, posY: newY),
                );
              },
            ),

            // 4. 水印实体与拖拽/缩放控制器
            Positioned(
              left: left,
              top: top,
              width: targetWmW,
              height: targetWmH,
              child: Listener(
                // 滚轮悬停缩放
                onPointerSignal: (event) {
                  if (event is PointerScrollEvent) {
                    final delta = event.scrollDelta.dy > 0 ? -1.0 : 1.0;
                    final newScale = (config.scalePercent + delta).clamp(
                      1.0,
                      50.0,
                    );
                    final newTargetWmW = (shortSide * (newScale / 100.0)).clamp(
                      24.0,
                      canvasSize.width,
                    );
                    final newTargetWmH =
                        (newTargetWmW /
                                (_imageAspectRatio > 0
                                    ? _imageAspectRatio
                                    : 1.0))
                            .clamp(16.0, canvasSize.height);
                    final newAvailW = math.max(
                      0.0,
                      canvasSize.width - 2 * marginPx - newTargetWmW,
                    );
                    final newAvailH = math.max(
                      0.0,
                      canvasSize.height - 2 * marginPx - newTargetWmH,
                    );
                    final newX = newAvailW > 0
                        ? ((left - marginPx) / newAvailW).clamp(0.0, 1.0)
                        : config.posX;
                    final newY = newAvailH > 0
                        ? ((top - marginPx) / newAvailH).clamp(0.0, 1.0)
                        : config.posY;
                    viewModel.updateWatermarkConfig(
                      config.copyWith(
                        scalePercent: newScale,
                        posX: newX,
                        posY: newY,
                      ),
                    );
                  }
                },
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // 水印图像主体 (拖拽移动位置，拖拽中仅本地 setState，拖拽结束统一提交)
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (details) {
                          setState(() {
                            _isDragging = true;
                            _dragX = config.posX;
                            _dragY = config.posY;
                          });
                        },
                        onPanUpdate: (details) {
                          if (availW <= 0 && availH <= 0) return;
                          setState(() {
                            if (availW > 0) {
                              _dragX = (_dragX + details.delta.dx / availW)
                                  .clamp(0.0, 1.0);
                            }
                            if (availH > 0) {
                              _dragY = (_dragY + details.delta.dy / availH)
                                  .clamp(0.0, 1.0);
                            }
                          });
                        },
                        onPanEnd: (_) {
                          setState(() => _isDragging = false);
                          viewModel.updateWatermarkConfig(
                            config.copyWith(posX: _dragX, posY: _dragY),
                          );
                        },
                        onPanCancel: () {
                          setState(() => _isDragging = false);
                        },
                        child: MouseRegion(
                          cursor: SystemMouseCursors.move,
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: AppTheme.notionBlue,
                                width: 1.5,
                              ),
                              borderRadius: BorderRadius.circular(4),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.notionBlue.withValues(
                                    alpha: 0.2,
                                  ),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: Opacity(
                                opacity: config.opacity.clamp(0.1, 1.0),
                                child:
                                    config.imageBytes != null &&
                                        config.imageBytes!.isNotEmpty
                                    ? Image.memory(
                                        config.imageBytes!,
                                        fit: BoxFit.contain,
                                        gaplessPlayback: true,
                                      )
                                    : Container(
                                        color: AppTheme.pureWhite,
                                        child: const Center(
                                          child: Icon(
                                            Icons.branding_watermark,
                                            size: 28,
                                            color: AppTheme.notionBlue,
                                          ),
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // 右下角自由缩放控制手柄 (拖向右下时左上角锁定不动，本地流畅放大)
                    Positioned(
                      right: -9,
                      bottom: -9,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (details) {
                          setState(() {
                            _isResizing = true;
                            _dragScale = config.scalePercent;
                            _dragX = config.posX;
                            _dragY = config.posY;
                            _resizePinLeft = left;
                            _resizePinTop = top;
                          });
                        },
                        onPanUpdate: (details) {
                          setState(() {
                            final delta =
                                (details.delta.dx / shortSide) * 100.0;
                            _dragScale = (_dragScale + delta).clamp(1.0, 50.0);

                            final newW = (shortSide * (_dragScale / 100.0))
                                .clamp(24.0, canvasSize.width);
                            final newH =
                                (newW /
                                        (_imageAspectRatio > 0
                                            ? _imageAspectRatio
                                            : 1.0))
                                    .clamp(16.0, canvasSize.height);

                            final newAvailW = math.max(
                              0.0,
                              canvasSize.width - 2 * marginPx - newW,
                            );
                            final newAvailH = math.max(
                              0.0,
                              canvasSize.height - 2 * marginPx - newH,
                            );

                            _dragX = newAvailW > 0
                                ? ((_resizePinLeft - marginPx) / newAvailW)
                                      .clamp(0.0, 1.0)
                                : 0.0;
                            _dragY = newAvailH > 0
                                ? ((_resizePinTop - marginPx) / newAvailH)
                                      .clamp(0.0, 1.0)
                                : 0.0;
                          });
                        },
                        onPanEnd: (_) {
                          setState(() => _isResizing = false);
                          viewModel.updateWatermarkConfig(
                            config.copyWith(
                              scalePercent: _dragScale,
                              posX: _dragX,
                              posY: _dragY,
                            ),
                          );
                        },
                        onPanCancel: () {
                          setState(() => _isResizing = false);
                        },
                        child: MouseRegion(
                          cursor: SystemMouseCursors.resizeDownRight,
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color: AppTheme.pureWhite,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppTheme.notionBlue,
                                width: 2.0,
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x33000000),
                                  blurRadius: 4,
                                  offset: Offset(0, 1),
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.aspect_ratio_rounded,
                                size: 10,
                                color: AppTheme.notionBlue,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // 4 个角的定位装饰微锚点
                    _buildCornerGrip(-3, -3),
                    _buildCornerGrip(null, -3, right: -3),
                    _buildCornerGrip(-3, null, bottom: -3),
                  ],
                ),
              ),
            ),

            // 5. 拖动或缩放时的实时浮动信息标签
            if (_isDragging || _isResizing)
              Positioned(
                left: (left + targetWmW / 2 - 50).clamp(
                  8.0,
                  math.max(8.0, canvasSize.width - 108),
                ),
                top: (top - 36).clamp(
                  8.0,
                  math.max(8.0, canvasSize.height - 36),
                ),
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xEE1A1A1A),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white24),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 6,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      _isResizing
                          ? '缩放: ${currentScale.toStringAsFixed(1)}%'
                          : '位置: ${(posX * 100).toInt()}%, ${(posY * 100).toInt()}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildCornerGrip(
    double? top,
    double? left, {
    double? right,
    double? bottom,
  }) {
    return Positioned(
      top: top,
      left: left,
      right: right,
      bottom: bottom,
      child: IgnorePointer(
        child: Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: AppTheme.notionBlue,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 1.0),
          ),
        ),
      ),
    );
  }
}

class _WatermarkGridGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.25)
      ..strokeWidth = 1.0;

    // 垂直三等分线
    canvas.drawLine(
      Offset(size.width / 3, 0),
      Offset(size.width / 3, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * 2 / 3, 0),
      Offset(size.width * 2 / 3, size.height),
      paint,
    );

    // 水平三等分线
    canvas.drawLine(
      Offset(0, size.height / 3),
      Offset(size.width, size.height / 3),
      paint,
    );
    canvas.drawLine(
      Offset(0, size.height * 2 / 3),
      Offset(size.width, size.height * 2 / 3),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
