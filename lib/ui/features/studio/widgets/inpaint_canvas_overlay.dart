import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../../../data/models/novelai_models.dart';
import '../../../../data/services/inpaint_service.dart';
import '../../../core/context_l10n.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_badge.dart';
import '../../../core/widgets/app_floating_dock.dart';
import '../../../core/widgets/app_tool_chip.dart';
import '../view_models/studio_view_model.dart';

/// 修复画板：以当前修复底图为中心的独立画布
///
/// 替代修复页签下的一般图像瀑布流——图片 contain 居中、无滚动干扰，
/// 选区/画笔与源图像素严格对齐。支持三种工具：
/// - 框选：空白处拖出新选区 / 选区内拖动移动 / 四角手柄缩放
/// - 画笔：自由绘制蒙版描边 (提交为归一化轨迹，单击盖章一个圆点)
/// - 橡皮：反向画笔，在蒙版上打黑抵消先前笔迹；覆盖层渲染上用
///   saveLayer 隔离 + BlendMode.clear 让橡皮真正"打穿"粉笔迹
///
/// 性能要点：已提交描边一次性录制为 ui.Picture 缓存 (列表身份变化才
/// 重录)，每帧只增量绘制进行中的描边；拖拽期间不触发 notifyListeners。
/// 布局要点：图片 contain 区域顶部预留工具坞高度，工具坞永不遮挡图片。
class InpaintRepairCanvas extends StatefulWidget {
  final StudioViewModel viewModel;

  const InpaintRepairCanvas({super.key, required this.viewModel});

  @override
  State<InpaintRepairCanvas> createState() => _InpaintRepairCanvasState();
}

class _InpaintRepairCanvasState extends State<InpaintRepairCanvas> {
  // 框选交互状态 (起点 + 增量模式，避免手柄/选区随拖拽坐标漂移)
  _RectDragMode _rectDragMode = _RectDragMode.none;
  int _activeHandleIndex = -1;
  Rect? _liveSelection; // 拖拽中的实时选区 (归一化)
  Rect? _dragBaseRect; // 拖拽开始时的选区
  Offset? _dragStartNorm; // 拖拽起点的归一化坐标
  Offset? _handleDragStartGlobal; // 手柄缩放起点的全局坐标 (State 级缓存)

  // 画笔交互状态
  final List<Offset> _liveStrokePoints = [];

  // 已提交描层的 Picture 缓存 (画得越多越不能每帧重画)
  ui.Picture? _committedPicture;
  List<InpaintBrushStroke>? _committedCacheKey;
  Size _committedCacheSize = Size.zero;

  @override
  void dispose() {
    _committedPicture?.dispose();
    _committedPicture = null;
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // 几何换算
  // ---------------------------------------------------------------------------

  // 顶部为浮动工具坞预留的高度 (工具坞 top:14 + 高度约 36 + 间隙)，
  // 保证 contain 居中的图片永远不会被工具坞遮挡
  static const double _dockTopReserve = 56.0;

  Rect _imageRectOf(Size canvas, int srcW, int srcH) {
    final availH = math.max(0.0, canvas.height - _dockTopReserve);
    final fitScale = math.min(canvas.width / srcW, availH / srcH);
    final w = srcW * fitScale;
    final h = srcH * fitScale;
    return Rect.fromLTWH(
      (canvas.width - w) / 2,
      _dockTopReserve + (availH - h) / 2,
      w,
      h,
    );
  }

  Offset _toNormalized(Offset localPoint, Rect imageRect) => Offset(
    ((localPoint.dx) / imageRect.width).clamp(0.0, 1.0),
    ((localPoint.dy) / imageRect.height).clamp(0.0, 1.0),
  );

  Rect _normRectInside(Rect r) => Rect.fromLTRB(
    r.left.clamp(0.0, 1.0),
    r.top.clamp(0.0, 1.0),
    r.right.clamp(0.0, 1.0),
    r.bottom.clamp(0.0, 1.0),
  );

  // ---------------------------------------------------------------------------
  // 已提交描边 Picture 缓存
  // ---------------------------------------------------------------------------

  /// 生效选区的实时值：画笔拖拽中用当前轨迹包围盒，否则用已提交描边
  /// 包围盒或矩形选区 (可为 null = 无选区，UI 不画默认框)。
  /// 橡皮只做减法不改变修复区，拖拽中沿用已提交的生效选区，
  /// 避免外延裁剪框跟着橡皮轨迹乱跳。
  Rect? _liveEffectiveSelNorm(InpaintParams inpaint) {
    final tool = widget.viewModel.inpaintTool;
    if (tool == InpaintTool.brush && _liveStrokePoints.isNotEmpty) {
      return _strokeBboxNorm(_liveStrokePoints, inpaint.brushRadius);
    }
    if (inpaint.hasBrushMask) return inpaint.effectiveSelectionRect;
    return _liveSelection ?? inpaint.selectionRect;
  }

  Rect _strokeBboxNorm(List<Offset> points, double radius) {
    var l = points.first.dx;
    var t = points.first.dy;
    var r = l;
    var b = t;
    for (final p in points.skip(1)) {
      l = math.min(l, p.dx);
      t = math.min(t, p.dy);
      r = math.max(r, p.dx);
      b = math.max(b, p.dy);
    }
    return Rect.fromLTRB(
      (l - radius).clamp(0.0, 1.0),
      (t - radius).clamp(0.0, 1.0),
      (r + radius).clamp(0.0, 1.0),
      (b + radius).clamp(0.0, 1.0),
    );
  }

  /// 焦点模式外延裁剪框的归一化矩形 (拖拽中实时跟随，常规模式返回 null)
  Rect? _liveContextCropNorm(Rect? selNormLive, int srcW, int srcH) {
    if (widget.viewModel.inpaintParams.mode != InpaintMode.focus) return null;
    if (selNormLive == null) return null;
    final geometry = InpaintService.resolveGeometry(
      sourceWidth: srcW,
      sourceHeight: srcH,
      selectionRect: Rect.fromLTWH(
        selNormLive.left * srcW,
        selNormLive.top * srcH,
        selNormLive.width * srcW,
        selNormLive.height * srcH,
      ),
      contextPadding: widget.viewModel.inpaintParams.contextPadding,
    );
    return Rect.fromLTWH(
      geometry.contextCrop.left / srcW,
      geometry.contextCrop.top / srcH,
      geometry.contextCrop.width / srcW,
      geometry.contextCrop.height / srcH,
    );
  }

  /// 把已提交描边录制为 Picture (仅在描边列表身份或画布尺寸变化时重录)
  ui.Picture? _buildCommittedPicture(
    List<InpaintBrushStroke> strokes,
    Rect imageRect,
  ) {
    if (strokes.isEmpty) {
      _committedPicture?.dispose();
      _committedPicture = null;
      _committedCacheKey = strokes;
      _committedCacheSize = imageRect.size;
      return null;
    }
    if (identical(strokes, _committedCacheKey) &&
        _committedCacheSize == imageRect.size &&
        _committedPicture != null) {
      return _committedPicture;
    }

    _committedPicture?.dispose();
    final recorder = ui.PictureRecorder();
    // Picture 用图层本地坐标录制 (原点=图片左上角)：回放发生在蒙版层
    // CustomPaint 里，其画布原点已经是 imageRect.topLeft，若录制时再
    // 加上 imageRect.left/top 会被平移两次，描边整体向右下漂移。
    final localRect = Offset.zero & imageRect.size;
    final canvas = ui.Canvas(recorder, localRect);

    final shortSide = math.min(imageRect.width, imageRect.height);
    for (final stroke in strokes) {
      if (stroke.points.isEmpty) continue;
      _paintStrokeOn(
        canvas,
        stroke.points,
        stroke.radius * shortSide,
        localRect,
        isEraser: stroke.isEraser,
      );
    }

    _committedPicture = recorder.endRecording();
    _committedCacheKey = strokes;
    _committedCacheSize = imageRect.size;
    return _committedPicture;
  }

  /// 在画布上绘制一条实心描边 (粗圆头折线，一次 stroke 操作，无空洞；
  /// 单点轨迹退化为圆点盖章)。橡皮描边用 BlendMode.clear——必须在
  /// 外层 saveLayer 隔离层内回放，才能真正打穿先前绘制的笔迹。
  void _paintStrokeOn(
    ui.Canvas canvas,
    List<Offset> points,
    double radiusPx,
    Rect rect, {
    required bool isEraser,
  }) {
    if (points.isEmpty || radiusPx <= 0) return;
    // 蒙版画笔 coral 是叠在用户图像上的身份色 (跨亮暗主题不变)，
    // 不属于主题化 UI 色；橡皮用 clear 混色仅作穿透语义。
    final ui.Color color = isEraser
        ? const ui.Color(0xFF000000)
        : AppTheme.coral.withValues(alpha: 0.42);
    final ui.BlendMode blend = isEraser
        ? ui.BlendMode.clear
        : ui.BlendMode.srcOver;
    Offset toCanvas(Offset p) =>
        Offset(rect.left + p.dx * rect.width, rect.top + p.dy * rect.height);

    if (points.length == 1) {
      // 单点：盖章一个实心圆 (画笔=补一笔，橡皮=抠一个洞)
      canvas.drawCircle(
        toCanvas(points.first),
        radiusPx,
        ui.Paint()
          ..style = ui.PaintingStyle.fill
          ..color = color
          ..blendMode = blend
          ..isAntiAlias = true,
      );
      return;
    }

    final path = ui.Path()
      ..moveTo(toCanvas(points.first).dx, toCanvas(points.first).dy);
    for (final p in points.skip(1)) {
      path.lineTo(toCanvas(p).dx, toCanvas(p).dy);
    }
    final paint = ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = radiusPx * 2
      ..strokeCap = ui.StrokeCap.round
      ..strokeJoin = ui.StrokeJoin.round
      ..color = color
      ..blendMode = blend
      ..isAntiAlias = true;
    canvas.drawPath(path, paint);
  }

  // ---------------------------------------------------------------------------
  // build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // 画板自带 VM 响应 (不依赖外层 ListenableBuilder 重建链路)。
    // 全部状态读取必须在 ListenableBuilder 的 builder 内进行——
    // 闭包若捕获外层局部变量，VM 通知后重建时拿到的仍是旧值。
    final l10n = context.l10n;
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final vm = widget.viewModel;
        final inpaint = vm.inpaintParams;
        final image = vm.inpaintSourceImage;

        if (image == null) {
          return Center(
            child: Text(
              l10n.inpaintOverlayEmptyHint,
              style: TextStyle(
                fontSize: 13,
                color: context.colors.textSecondary,
              ),
            ),
          );
        }

        final srcW = image.params.width > 0 ? image.params.width : 1024;
        final srcH = image.params.height > 0 ? image.params.height : 1024;
        final isFocus = inpaint.mode == InpaintMode.focus;
        final isAiEdit = inpaint.mode == InpaintMode.aiEdit;
        final tool = vm.inpaintTool;
        final isExecuting = vm.isExecutingInpaint || vm.isExecutingAiEdit;
        final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;

        return LayoutBuilder(
          builder: (context, constraints) {
            final canvasSize = Size(
              constraints.maxWidth,
              constraints.maxHeight,
            );
            if (canvasSize.width <= 0 || canvasSize.height <= 0) {
              return const SizedBox.shrink();
            }
            final imageRect = _imageRectOf(canvasSize, srcW, srcH);

            // 显示中的选区 (框选工具)：无选区时为 null，不画默认框
            final Rect? displaySelNorm = (tool == InpaintTool.rect)
                ? (_liveSelection ?? inpaint.selectionRect)
                : null;
            final Rect? displaySelCanvas = displaySelNorm == null
                ? null
                : Rect.fromLTWH(
                    imageRect.left + displaySelNorm.left * imageRect.width,
                    imageRect.top + displaySelNorm.top * imageRect.height,
                    displaySelNorm.width * imageRect.width,
                    displaySelNorm.height * imageRect.height,
                  );

            // 生效选区 (画笔描边优先) 与实时外延裁剪框
            final liveEffectiveSel = _liveEffectiveSelNorm(inpaint);
            final cropNormRect = isFocus
                ? _liveContextCropNorm(liveEffectiveSel, srcW, srcH)
                : null;
            final Rect? cropCanvasRect = cropNormRect == null
                ? null
                : Rect.fromLTWH(
                    imageRect.left + cropNormRect.left * imageRect.width,
                    imageRect.top + cropNormRect.top * imageRect.height,
                    cropNormRect.width * imageRect.width,
                    cropNormRect.height * imageRect.height,
                  );

            final committedPicture = _buildCommittedPicture(
              inpaint.brushStrokes,
              imageRect,
            );

            return Stack(
              children: [
                // 1. 源图 (contain 居中，与交互层严格同矩形；按显示尺寸解码)
                Positioned.fromRect(
                  key: const ValueKey('inpaint-src'),
                  rect: imageRect,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: ValueListenableBuilder<Map<String, Uint8List>>(
                      valueListenable: vm.imageBytesNotifier,
                      builder: (context, bytesMap, _) {
                        final fullBytes = image.bytes.isNotEmpty
                            ? image.bytes
                            : bytesMap[image.id];
                        final cacheW = (imageRect.width * dpr).round().clamp(
                          64,
                          4096,
                        );
                        if (fullBytes != null && fullBytes.isNotEmpty) {
                          return Image.memory(
                            fullBytes,
                            fit: BoxFit.fill,
                            gaplessPlayback: true,
                            cacheWidth: cacheW,
                          );
                        }

                        vm.ensureImageLoaded(image);

                        final thumb = image.thumbnailBytes;
                        if (thumb != null && thumb.isNotEmpty) {
                          return Image.memory(
                            thumb,
                            fit: BoxFit.fill,
                            gaplessPlayback: true,
                            cacheWidth: cacheW,
                          );
                        }

                        return Container(
                          color: context.colors.mutedBackground,
                          child: Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  context.colors.primary,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),

                // 2. 蒙版层：外延框外压暗 (even-odd 只填环带) + 已提交描边
                //    Picture 缓存 + 实时描边 + 选区框 (AI 整图编辑不渲染蒙版)
                if (!isAiEdit)
                  Positioned.fromRect(
                    key: const ValueKey('inpaint-mask'),
                    rect: imageRect,
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _InpaintMaskPainter(
                          committedPicture: committedPicture,
                          liveStroke: _liveStrokePoints,
                          liveStrokeIsEraser: tool == InpaintTool.eraser,
                          liveBrushRadius: inpaint.brushRadius,
                          dimOutsideRect: isFocus ? cropNormRect : null,
                          selectionRect: displaySelNorm,
                          selectionColor: context.colors.primary,
                        ),
                      ),
                    ),
                  ),

                // 3. 焦点模式外延上下文虚线框 (实时跟随)
                if (isFocus && cropCanvasRect != null)
                  Positioned.fromRect(
                    key: const ValueKey('inpaint-crop-frame'),
                    rect: cropCanvasRect,
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: context.colors.primary.withValues(
                              alpha: 0.45,
                            ),
                            width: 1.2,
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: context.colors.primary,
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(3),
                                bottomRight: Radius.circular(3),
                              ),
                            ),
                            child: Text(
                              l10n.inpaintOverlayContextCrop(
                                inpaint.contextPadding.round(),
                              ),
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                // 4. 执行中的中间帧预览 (贴在外延裁剪框位置)
                if (isExecuting && vm.inpaintPreviewBytes != null)
                  Positioned.fromRect(
                    key: const ValueKey('inpaint-preview'),
                    rect: (isFocus && cropCanvasRect != null)
                        ? cropCanvasRect
                        : imageRect,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.memory(
                        vm.inpaintPreviewBytes!,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      ),
                    ),
                  ),

                // 5. 手势交互层 (整个源图区域；执行中与 AI 整图编辑模式禁用)
                if (!isExecuting && !isAiEdit)
                  Positioned.fromRect(
                    key: const ValueKey('inpaint-gesture'),
                    rect: imageRect,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (d) => _onPanStart(
                        d.localPosition,
                        imageRect,
                        displaySelNorm,
                      ),
                      onPanUpdate: (d) => _onPanUpdate(
                        d.localPosition,
                        imageRect,
                        displaySelNorm,
                      ),
                      onPanEnd: (_) => _onPanEnd(),
                      onPanCancel: () => _onPanEnd(),
                      child: const SizedBox.expand(),
                    ),
                  ),

                // 6. 四角缩放手柄 (框选工具且无画笔蒙版且有选区时显示)
                if (!isExecuting &&
                    !isAiEdit &&
                    tool == InpaintTool.rect &&
                    !inpaint.hasBrushMask &&
                    displaySelCanvas != null)
                  ..._buildCornerHandles(
                    imageRect,
                    displaySelNorm!,
                    displaySelCanvas,
                  ),

                // 7. 顶部浮动工具坞
                Positioned(
                  key: const ValueKey('inpaint-dock'),
                  top: 14,
                  left: 0,
                  right: 0,
                  child: Center(child: _buildToolDock(context, vm, inpaint)),
                ),

                // 8. 执行中状态胶囊
                if (isExecuting)
                  Positioned(
                    key: const ValueKey('inpaint-status'),
                    bottom: 18,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: AppFloatingDock(
                        radius: 18,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 13,
                              height: 13,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  context.colors.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              l10n.inpaintOverlayInProgress,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: context.colors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 手势处理
  // ---------------------------------------------------------------------------

  void _onPanStart(Offset localPoint, Rect imageRect, Rect? selNorm) {
    final vm = widget.viewModel;
    final norm = _toNormalized(localPoint, imageRect);
    switch (vm.inpaintTool) {
      case InpaintTool.rect:
        final inside =
            !vm.inpaintParams.hasBrushMask &&
            selNorm != null &&
            Rect.fromLTWH(
              imageRect.left + selNorm.left * imageRect.width,
              imageRect.top + selNorm.top * imageRect.height,
              selNorm.width * imageRect.width,
              selNorm.height * imageRect.height,
            ).contains(localPoint + imageRect.topLeft);
        _rectDragMode = inside ? _RectDragMode.move : _RectDragMode.marquee;
        _dragBaseRect = selNorm;
        _dragStartNorm = norm;
        if (_rectDragMode == _RectDragMode.marquee) {
          _liveSelection = Rect.fromPoints(norm, norm);
        }
        setState(() {});
      case InpaintTool.brush:
      case InpaintTool.eraser:
        // 画笔与橡皮统一为拖绘制流 (橡皮 = 反向画笔)，仅本地 state 驱动
        _liveStrokePoints.clear();
        _liveStrokePoints.add(norm);
        setState(() {});
    }
  }

  void _onPanUpdate(Offset localPoint, Rect imageRect, Rect? selNorm) {
    final vm = widget.viewModel;
    final norm = _toNormalized(localPoint, imageRect);
    switch (vm.inpaintTool) {
      case InpaintTool.rect:
        final start = _dragStartNorm;
        if (start == null) return;
        if (_rectDragMode == _RectDragMode.marquee) {
          // 新建选区不依赖旧选区 (空白处拖拽时 _dragBaseRect 为 null)
          setState(() => _liveSelection = Rect.fromPoints(start, norm));
        } else if (_rectDragMode == _RectDragMode.move) {
          final base = _dragBaseRect;
          if (base == null) return;
          final dx = norm.dx - start.dx;
          final dy = norm.dy - start.dy;
          setState(() {
            _liveSelection = Rect.fromLTWH(
              (base.left + dx).clamp(0.0, 1.0 - base.width),
              (base.top + dy).clamp(0.0, 1.0 - base.height),
              base.width,
              base.height,
            );
          });
        }
      case InpaintTool.brush:
      case InpaintTool.eraser:
        setState(() => _liveStrokePoints.add(norm));
    }
  }

  void _onPanEnd() {
    final vm = widget.viewModel;
    switch (vm.inpaintTool) {
      case InpaintTool.rect:
        final r = _liveSelection;
        if (r != null && r.width > 0.015 && r.height > 0.015) {
          vm.setInpaintSelectionRect(_normRectInside(r));
        }
        _resetRectDrag();
      case InpaintTool.brush:
      case InpaintTool.eraser:
        // 单点也算一次提交 (单击盖章/抠洞)
        if (_liveStrokePoints.isNotEmpty) {
          vm.commitInpaintStroke(
            List<Offset>.of(_liveStrokePoints),
            erase: vm.inpaintTool == InpaintTool.eraser,
          );
        }
        _liveStrokePoints.clear();
        setState(() {});
    }
  }

  void _resetRectDrag() {
    _rectDragMode = _RectDragMode.none;
    _activeHandleIndex = -1;
    _liveSelection = null;
    _dragBaseRect = null;
    _dragStartNorm = null;
    _handleDragStartGlobal = null;
    setState(() {});
  }

  // ---------------------------------------------------------------------------
  // 四角手柄
  // ---------------------------------------------------------------------------

  List<Widget> _buildCornerHandles(
    Rect imageRect,
    Rect selNorm,
    Rect selCanvas,
  ) {
    const handleHit = 28.0;

    Rect applyDelta(Rect base, int corner, Offset deltaNorm) {
      var l = base.left;
      var t = base.top;
      var r = base.right;
      var b = base.bottom;
      switch (corner) {
        case 0: // TL
          l = (l + deltaNorm.dx).clamp(0.0, r - 0.02);
          t = (t + deltaNorm.dy).clamp(0.0, b - 0.02);
        case 1: // TR
          r = (r + deltaNorm.dx).clamp(l + 0.02, 1.0);
          t = (t + deltaNorm.dy).clamp(0.0, b - 0.02);
        case 2: // BR
          r = (r + deltaNorm.dx).clamp(l + 0.02, 1.0);
          b = (b + deltaNorm.dy).clamp(t + 0.02, 1.0);
        case 3: // BL
          l = (l + deltaNorm.dx).clamp(0.0, r - 0.02);
          b = (b + deltaNorm.dy).clamp(t + 0.02, 1.0);
      }
      return Rect.fromLTRB(l, t, r, b);
    }

    Widget handle(int corner, Offset center) {
      return Positioned(
        key: ValueKey('inpaint-handle-$corner'),
        left: center.dx - handleHit / 2,
        top: center.dy - handleHit / 2,
        width: handleHit,
        height: handleHit,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) {
            // 起点存 State 字段：拖拽中 rebuild 不会丢失基准
            _handleDragStartGlobal = d.globalPosition;
            _dragBaseRect = selNorm;
            setState(() {
              _activeHandleIndex = corner;
              _liveSelection = selNorm;
            });
          },
          onPanUpdate: (d) {
            final start = _handleDragStartGlobal;
            final base = _dragBaseRect;
            if (start == null || base == null) return;
            final deltaNorm = Offset(
              (d.globalPosition.dx - start.dx) / imageRect.width,
              (d.globalPosition.dy - start.dy) / imageRect.height,
            );
            setState(() {
              _liveSelection = _normRectInside(
                applyDelta(base, corner, deltaNorm),
              );
            });
          },
          onPanEnd: (_) {
            final r = _liveSelection;
            if (r != null && r.width > 0.015 && r.height > 0.015) {
              widget.viewModel.setInpaintSelectionRect(_normRectInside(r));
            }
            _resetRectDrag();
          },
          onPanCancel: _resetRectDrag,
          child: Center(
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                // 手柄悬浮在用户图像之上：白底与暗色投影是跨主题身份色
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(
                  color: _activeHandleIndex == corner
                      ? context.colors.error
                      : context.colors.primary,
                  width: 2.2,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 3,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return [
      handle(0, selCanvas.topLeft),
      handle(1, selCanvas.topRight),
      handle(2, selCanvas.bottomRight),
      handle(3, selCanvas.bottomLeft),
    ];
  }

  // ---------------------------------------------------------------------------
  // 工具坞
  // ---------------------------------------------------------------------------

  Widget _buildToolDock(
    BuildContext context,
    StudioViewModel vm,
    InpaintParams inpaint,
  ) {
    final colors = context.colors;
    final l10n = context.l10n;

    // AI 整图编辑：整图交给外部绘图模型重绘，蒙版与选区工具无意义，
    // 工具坞降级为模式提示胶囊
    if (inpaint.mode == InpaintMode.aiEdit) {
      return AppFloatingDock(
        radius: 20,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome, size: 13, color: colors.primary),
            const SizedBox(width: 5),
            Text(
              l10n.inpaintOverlayAiEditHint,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    final geometry = vm.inpaintGeometry;
    final steps = inpaint.customSteps ?? vm.params.steps;
    final isFree = geometry.isOpusFree && steps <= 28;

    Widget toolChip(InpaintTool tool, IconData icon, String label) {
      final selected = vm.inpaintTool == tool;
      return AppToolChip(
        icon: icon,
        label: label,
        isSelected: selected,
        variant: AppToolChipVariant.tinted,
        fontSize: 11,
        iconSize: 13,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        radius: 14,
        onTap: () => vm.setInpaintTool(tool),
      );
    }

    final showBrushSize =
        vm.inpaintTool == InpaintTool.brush ||
        vm.inpaintTool == InpaintTool.eraser;

    return AppFloatingDock(
      radius: 20,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          toolChip(
            InpaintTool.rect,
            Icons.crop_free_rounded,
            l10n.inpaintToolRect,
          ),
          toolChip(
            InpaintTool.brush,
            Icons.brush_rounded,
            l10n.inpaintToolBrush,
          ),
          toolChip(
            InpaintTool.eraser,
            Icons.layers_clear_rounded,
            l10n.inpaintToolEraser,
          ),
          const SizedBox(width: 4),
          if (showBrushSize) ...[
            _BrushSizeSlider(
              value: inpaint.brushRadius,
              onCommit: vm.setInpaintBrushRadius,
            ),
            const SizedBox(width: 2),
          ],
          AppToolChip(
            icon: Icons.delete_sweep_outlined,
            label: l10n.inpaintClearMask,
            variant: AppToolChipVariant.tinted,
            fontSize: 11,
            iconSize: 13,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            radius: 14,
            onTap: vm.clearInpaintMask,
          ),
          const SizedBox(width: 4),
          AppBadge(
            label: isFree ? l10n.opusFree : l10n.inpaintRequiresPoints,
            variant: isFree ? AppBadgeVariant.success : AppBadgeVariant.warning,
          ),
          // 执行修复统一由左侧生成坞的「开始修复」按钮触发，工具坞不再重复入口
        ],
      ),
    );
  }
}

enum _RectDragMode { none, marquee, move }

/// 本地拖动、松手提交的笔刷大小滑条 (拖动期间零 notifyListeners，不卡)
class _BrushSizeSlider extends StatefulWidget {
  final double value;
  final ValueChanged<double> onCommit;

  const _BrushSizeSlider({required this.value, required this.onCommit});

  @override
  State<_BrushSizeSlider> createState() => _BrushSizeSliderState();
}

class _BrushSizeSliderState extends State<_BrushSizeSlider> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final v = _dragValue ?? widget.value.clamp(0.005, 0.25);
    // 限高 28：Material Slider 默认 48px 会把工具坞撑到 ~70px 高，
    // 加剧工具坞遮挡图片的问题
    return SizedBox(
      width: 92,
      height: 28,
      child: SliderTheme(
        data: SliderThemeData(
          trackHeight: 3,
          activeTrackColor: colors.primary,
          inactiveTrackColor: colors.mutedBackground,
          thumbColor: colors.primary,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
        ),
        child: Slider(
          value: v,
          min: 0.005,
          max: 0.25,
          onChanged: (value) => setState(() => _dragValue = value),
          onChangeEnd: (value) {
            _dragValue = null;
            widget.onCommit(value);
          },
        ),
      ),
    );
  }
}

/// 蒙版可视化绘制器：外延框外压暗环带 + 已提交描边 Picture + 实时描边 + 选区框
class _InpaintMaskPainter extends CustomPainter {
  final ui.Picture? committedPicture;
  final List<Offset> liveStroke;
  final bool liveStrokeIsEraser;
  final double liveBrushRadius;
  final Rect? dimOutsideRect;
  final Rect? selectionRect;

  /// 选区描框主题色 (由当前主题注入)
  final Color selectionColor;

  _InpaintMaskPainter({
    required this.committedPicture,
    required this.liveStroke,
    required this.liveStrokeIsEraser,
    required this.liveBrushRadius,
    required this.dimOutsideRect,
    required this.selectionRect,
    required this.selectionColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. 焦点模式：外延裁剪框外压暗 (外矩形+内矩形 even-odd 只填环带)
    final dim = dimOutsideRect;
    if (dim != null) {
      final dimPath = ui.Path()
        ..addRect(Offset.zero & size)
        ..addRect(
          Rect.fromLTWH(
            dim.left * size.width,
            dim.top * size.height,
            dim.width * size.width,
            dim.height * size.height,
          ),
        )
        ..fillType = ui.PathFillType.evenOdd;
      canvas.drawPath(
        dimPath,
        Paint()..color = Colors.black.withValues(alpha: 0.28),
      );
    }

    // 2+3. 笔迹层：已提交描边 Picture + 进行中的描边，整体包在一个
    //    隔离图层 (saveLayer) 里——橡皮描边用 BlendMode.clear 打穿，
    //    视觉上真正擦掉先前笔迹而不是叠加一层白色 (clear 只作用于
    //    图层内部，不会打穿图层之下的压暗环带与源图)
    if (committedPicture != null || liveStroke.isNotEmpty) {
      canvas.saveLayer(Offset.zero & size, Paint());
      if (committedPicture != null) {
        canvas.drawPicture(committedPicture!);
      }
      if (liveStroke.isNotEmpty) {
        final shortSide = math.min(size.width, size.height);
        final radius = liveBrushRadius.clamp(0.005, 0.25) * shortSide;
        final Color strokeColor = liveStrokeIsEraser
            ? const Color(0xFF000000)
            // 同 _paintStrokeOn：画笔 coral 为图像上身份色，不随主题切换
            : AppTheme.coral.withValues(alpha: 0.42);
        final BlendMode strokeBlend = liveStrokeIsEraser
            ? BlendMode.clear
            : BlendMode.srcOver;
        if (liveStroke.length == 1) {
          canvas.drawCircle(
            Offset(
              liveStroke.first.dx * size.width,
              liveStroke.first.dy * size.height,
            ),
            radius,
            Paint()
              ..style = PaintingStyle.fill
              ..color = strokeColor
              ..blendMode = strokeBlend
              ..isAntiAlias = true,
          );
        } else {
          final path = ui.Path()
            ..moveTo(
              liveStroke.first.dx * size.width,
              liveStroke.first.dy * size.height,
            );
          for (final p in liveStroke.skip(1)) {
            path.lineTo(p.dx * size.width, p.dy * size.height);
          }
          canvas.drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = radius * 2
              ..strokeCap = StrokeCap.round
              ..strokeJoin = StrokeJoin.round
              ..color = strokeColor
              ..blendMode = strokeBlend
              ..isAntiAlias = true,
          );
        }
      }
      canvas.restore();
    }

    // 4. 矩形选区框 (无选区时不画)
    final sel = selectionRect;
    if (sel != null && !sel.isEmpty && sel.width > 0 && sel.height > 0) {
      final r = Rect.fromLTWH(
        sel.left * size.width,
        sel.top * size.height,
        sel.width * size.width,
        sel.height * size.height,
      );
      canvas.drawRect(
        r,
        Paint()
          ..color = selectionColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      canvas.drawRect(
        r,
        Paint()..color = selectionColor.withValues(alpha: 0.10),
      );
      final tp = TextPainter(
        text: const TextSpan(
          text: '修复选区',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: r.center,
            width: tp.width + 12,
            height: tp.height + 6,
          ),
          const Radius.circular(4),
        ),
        Paint()..color = Colors.black.withValues(alpha: 0.6),
      );
      tp.paint(canvas, r.center - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _InpaintMaskPainter old) => true;
}
