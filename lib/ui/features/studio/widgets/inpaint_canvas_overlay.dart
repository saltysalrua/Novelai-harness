import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../data/models/novelai_models.dart';
import '../../../../data/services/inpaint_service.dart';
import '../../../core/context_l10n.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_action_button.dart';
import '../../../core/widgets/app_badge.dart';
import '../../../core/widgets/app_floating_dock.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../../core/widgets/app_tool_chip.dart';
import '../../../core/widgets/app_transitions.dart';
import '../view_models/studio_view_model.dart';

/// 修复画板：以当前修复底图为中心的独立画布
///
/// 替代修复页签下的一般图像瀑布流——支持自由缩放与漫游平移、
/// 选区/画笔与源图像素严格对齐。支持四种交互：
/// - 漫游：滚轮/双指以焦点缩放；中键/右键/空格+左键/抓手模式/双指拖拽平移
/// - 框选：空白处拖出新选区 / 选区内拖动移动 / 四角手柄缩放
/// - 画笔：自由绘制蒙版描边 (提交为归一化轨迹，单击盖章一个圆点，支持实时笔刷圆环预览)
/// - 橡皮：反向画笔，在蒙版上打黑抵消先前笔迹；覆盖层渲染上用
///   saveLayer 隔离 + BlendMode.clear 让橡皮真正"打穿"粉笔迹
///
/// 性能要点：已提交描边一次性录制为 ui.Picture 缓存 (列表身份变化才
/// 重录)，缩放/平移由 TransformationController + RepaintBoundary 驱动，
/// 每帧零 notifyListeners、零整树重建。
class InpaintRepairCanvas extends StatefulWidget {
  final StudioViewModel viewModel;
  final bool compact;
  final VoidCallback? onExit;

  const InpaintRepairCanvas({
    super.key,
    required this.viewModel,
    this.compact = false,
    this.onExit,
  });

  @override
  State<InpaintRepairCanvas> createState() => _InpaintRepairCanvasState();
}

class _InpaintRepairCanvasState extends State<InpaintRepairCanvas> {
  static const double _minZoom = 0.5;
  static const double _maxZoom = 12.0;
  static const double _minBrushRadius = 0.003;
  static const double _maxBrushRadius = 0.25;

  // 顶部为浮动工具坞预留的高度 (工具坞 top:14 + 高度约 36 + 间隙)，
  // 保证初始 contain 居中的图片不会被工具坞遮挡
  static const double _dockTopReserve = 56.0;

  // 视口缩放/平移矩阵 (ValueNotifier 驱动 Transform，零整树 rebuild)
  final TransformationController _transformController =
      TransformationController();
  final ValueNotifier<double> _imageLodNotifier = ValueNotifier<double>(1.0);

  // 交互模式与光标/显隐局部状态 (全用 ValueNotifier，高频交互零 setState)
  final ValueNotifier<bool> _isSpacePressedNotifier = ValueNotifier<bool>(
    false,
  );
  final ValueNotifier<bool> _isPanModeNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _isActivelyPanningNotifier = ValueNotifier<bool>(
    false,
  );
  final ValueNotifier<bool> _maskVisibleNotifier = ValueNotifier<bool>(true);
  final ValueNotifier<Offset?> _hoverCanvasPosNotifier = ValueNotifier<Offset?>(
    null,
  );
  final ValueNotifier<double?> _brushSliderPreviewNotifier =
      ValueNotifier<double?>(null);

  // 原始多指/鼠标状态机 (同时处理单指绘制、单点盖章、中/右键平移、双指捏合缩放平移)
  final Map<int, Offset> _activePointers = {};
  bool _isPinchZooming = false;
  Offset _lastPinchFocal = Offset.zero;
  double _lastPinchSpan = 1.0;
  bool _isViewportPanning = false;
  int? _panPointerId;
  Offset _lastPanPos = Offset.zero;
  int? _drawPointerId;

  // 最新画布几何缓存 (供键盘快捷键与指针事件读取)
  Size _canvasSize = Size.zero;
  Rect _imageRect = Rect.zero;
  int _srcW = 1024;
  int _srcH = 1024;
  int? _lastTrackedSrcW;
  int? _lastTrackedSrcH;
  bool _tickerEnabled = true;

  // 框选交互状态 (起点 + 增量模式，避免手柄/选区随拖拽坐标漂移)
  _RectDragMode _rectDragMode = _RectDragMode.none;
  final ValueNotifier<int> _activeHandleNotifier = ValueNotifier<int>(-1);
  final ValueNotifier<Rect?> _liveSelectionNotifier = ValueNotifier<Rect?>(
    null,
  ); // 拖拽中的实时选区 (归一化)
  Rect? _dragBaseRect; // 拖拽开始时的选区
  Offset? _dragStartNorm; // 拖拽起点的归一化坐标
  Offset? _handleDragStartGlobal; // 手柄缩放起点的全局坐标 (State 级缓存)

  // 画笔交互状态 (使用局部 notifier 驱动重绘，拖拽期间零整树 setState)
  final List<Offset> _liveStrokePoints = [];
  final ValueNotifier<int> _livePaintRevision = ValueNotifier<int>(0);
  late final Listenable _viewportOverlayListenable = Listenable.merge([
    _livePaintRevision,
    _liveSelectionNotifier,
    _maskVisibleNotifier,
    _transformController,
  ]);
  late final Listenable _cursorVisualListenable = Listenable.merge([
    _hoverCanvasPosNotifier,
    _brushSliderPreviewNotifier,
    _transformController,
    _isSpacePressedNotifier,
    _isPanModeNotifier,
    _isActivelyPanningNotifier,
  ]);

  // 已提交描层的 Picture 缓存 (画得越多越不能每帧重画)
  ui.Picture? _committedPicture;
  int _committedPictureRevision = 0;
  bool _committedHasEraser = false;
  List<InpaintBrushStroke>? _committedCacheKey;
  Size _committedCacheSize = Size.zero;

  @override
  void initState() {
    super.initState();
    _syncTrackedImageDims(resetOnChange: false);
    _transformController.addListener(_onTransformChanged);
    widget.viewModel.addListener(_onViewModelChanged);
    HardwareKeyboard.instance.addHandler(_handleGlobalKey);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
  }

  @override
  void didUpdateWidget(covariant InpaintRepairCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewModel != widget.viewModel) {
      oldWidget.viewModel.removeListener(_onViewModelChanged);
      widget.viewModel.addListener(_onViewModelChanged);
      _syncTrackedImageDims(resetOnChange: true);
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleGlobalKey);
    widget.viewModel.removeListener(_onViewModelChanged);
    _transformController.removeListener(_onTransformChanged);
    _transformController.dispose();
    _imageLodNotifier.dispose();
    _isSpacePressedNotifier.dispose();
    _isPanModeNotifier.dispose();
    _isActivelyPanningNotifier.dispose();
    _maskVisibleNotifier.dispose();
    _hoverCanvasPosNotifier.dispose();
    _brushSliderPreviewNotifier.dispose();
    _activeHandleNotifier.dispose();
    _liveSelectionNotifier.dispose();
    _livePaintRevision.dispose();
    _committedPicture?.dispose();
    _committedPicture = null;
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // 视口矩阵与缩放/平移控制
  // ---------------------------------------------------------------------------

  double get _currentScale {
    final s = _transformController.value.entry(0, 0);
    return (s.isFinite && s > 0) ? s : 1.0;
  }

  void _onTransformChanged() {
    final scale = _currentScale;
    final lod = math
        .pow(2, (math.log(math.max(1.0, scale)) / math.ln2).ceil())
        .toDouble()
        .clamp(1.0, 8.0);
    if (_imageLodNotifier.value != lod) {
      _imageLodNotifier.value = lod;
    }
  }

  void _onViewModelChanged() {
    if (!mounted) return;
    _syncTrackedImageDims(resetOnChange: true);
  }

  void _syncTrackedImageDims({required bool resetOnChange}) {
    final image = widget.viewModel.inpaintSourceImage;
    if (image == null) {
      _lastTrackedSrcW = null;
      _lastTrackedSrcH = null;
      if (resetOnChange && _transformController.value != Matrix4.identity()) {
        _transformController.value = Matrix4.identity();
      }
      return;
    }
    final w = image.params.width > 0 ? image.params.width : 1024;
    final h = image.params.height > 0 ? image.params.height : 1024;
    final dimsChanged =
        _lastTrackedSrcW != null &&
        (_lastTrackedSrcW != w || _lastTrackedSrcH != h);
    _lastTrackedSrcW = w;
    _lastTrackedSrcH = h;
    if (resetOnChange &&
        dimsChanged &&
        _transformController.value != Matrix4.identity()) {
      _transformController.value = Matrix4.identity();
    }
  }

  Matrix4 _clampTransform(Matrix4 matrix, Size canvasSize, Rect imageRect) {
    if (canvasSize.isEmpty || imageRect.isEmpty) return matrix;
    final scaled = MatrixUtils.transformRect(matrix, imageRect);
    final marginX = math.min(80.0, scaled.width * 0.5);
    final marginY = math.min(80.0, scaled.height * 0.5);
    var tx = matrix.storage[12];
    var ty = matrix.storage[13];

    if (scaled.right < marginX) {
      tx += marginX - scaled.right;
    } else if (scaled.left > canvasSize.width - marginX) {
      tx -= scaled.left - (canvasSize.width - marginX);
    }

    final topBound = _dockTopReserve;
    if (scaled.bottom < topBound + marginY) {
      ty += (topBound + marginY) - scaled.bottom;
    } else if (scaled.top > canvasSize.height - marginY) {
      ty -= scaled.top - (canvasSize.height - marginY);
    }

    if (tx == matrix.storage[12] && ty == matrix.storage[13]) {
      return matrix;
    }
    return Matrix4.copy(matrix)
      ..storage[12] = tx
      ..storage[13] = ty;
  }

  Matrix4 _scaleAround(
    double targetScale,
    Offset anchor, {
    Offset? nextAnchor,
    required Size canvasSize,
    required Rect imageRect,
  }) {
    final scale = targetScale.clamp(_minZoom, _maxZoom);
    final scenePoint = _transformController.toScene(anchor);
    final destination = nextAnchor ?? anchor;
    final matrix = Matrix4.diagonal3Values(scale, scale, 1)
      ..setTranslationRaw(
        destination.dx - scenePoint.dx * scale,
        destination.dy - scenePoint.dy * scale,
        0,
      );
    return _clampTransform(matrix, canvasSize, imageRect);
  }

  void _zoomBy(double factor) {
    if (_canvasSize.isEmpty || _imageRect.isEmpty) return;
    final anchor = Offset(
      _canvasSize.width / 2,
      _dockTopReserve + (_canvasSize.height - _dockTopReserve) / 2,
    );
    _transformController.value = _scaleAround(
      _currentScale * factor,
      anchor,
      canvasSize: _canvasSize,
      imageRect: _imageRect,
    );
  }

  void _resetViewport() {
    _transformController.value = Matrix4.identity();
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (_canvasSize.isEmpty || _imageRect.isEmpty) return;
    if (event is PointerScrollEvent) {
      final dy = event.scrollDelta.dy;
      if (!dy.isFinite || dy == 0) return;
      GestureBinding.instance.pointerSignalResolver.register(event, (_) {
        final factor = math.exp(-dy / 460).clamp(0.65, 1.55);
        _transformController.value = _scaleAround(
          _currentScale * factor,
          event.localPosition,
          canvasSize: _canvasSize,
          imageRect: _imageRect,
        );
      });
    } else if (event is PointerScaleEvent) {
      if (!event.scale.isFinite || event.scale <= 0) return;
      GestureBinding.instance.pointerSignalResolver.register(event, (_) {
        _transformController.value = _scaleAround(
          _currentScale * event.scale,
          event.localPosition,
          canvasSize: _canvasSize,
          imageRect: _imageRect,
        );
      });
    }
  }

  // ---------------------------------------------------------------------------
  // 键盘快捷键 (非文本输入态且修复画板激活时生效)
  // ---------------------------------------------------------------------------

  bool _isTypingText() {
    final currentFocus = FocusManager.instance.primaryFocus;
    if (currentFocus == null || currentFocus.context == null) return false;
    final focusedWidget = currentFocus.context!.widget;
    if (focusedWidget is EditableText) return true;
    return currentFocus.context!
            .findAncestorWidgetOfExactType<EditableText>() !=
        null;
  }

  bool _isCanvasActiveForKeys() {
    if (!mounted || !_tickerEnabled) return false;
    final vm = widget.viewModel;
    if (vm.activeSidebarTab != StudioSidebarTab.inpaint) return false;
    if (vm.board.isAnnotatingImage ||
        vm.isEditingCharacterPositions ||
        vm.isEditingWatermarkPosition) {
      return false;
    }
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    return true;
  }

  bool _handleGlobalKey(KeyEvent event) {
    if (!_isCanvasActiveForKeys()) {
      if (_isSpacePressedNotifier.value) {
        _isSpacePressedNotifier.value = false;
      }
      return false;
    }

    if (event.logicalKey == LogicalKeyboardKey.space) {
      if (event is KeyUpEvent) {
        if (_isSpacePressedNotifier.value) {
          _isSpacePressedNotifier.value = false;
          return true;
        }
        return false;
      }
      if (_isTypingText()) return false;
      if (event is KeyDownEvent || event is KeyRepeatEvent) {
        if (!_isSpacePressedNotifier.value) {
          _isSpacePressedNotifier.value = true;
        }
        return true;
      }
      return false;
    }

    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    if (_isTypingText()) return false;

    final vm = widget.viewModel;
    final isAiEdit = vm.inpaintParams.mode == InpaintMode.aiEdit;
    final isExecuting = vm.isExecutingInpaint || vm.isExecutingAiEdit;
    final isCtrlOrCmd =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;
    final isAlt = HardwareKeyboard.instance.isAltPressed;
    final key = event.logicalKey;

    // Ctrl+Z / Ctrl+Shift+Z / Ctrl+Y 撤销重做蒙版
    if (isCtrlOrCmd && !isAlt && !isAiEdit && !isExecuting) {
      if (key == LogicalKeyboardKey.keyZ) {
        if (isShift) {
          vm.redoInpaintMask();
        } else {
          vm.undoInpaintMask();
        }
        return true;
      }
      if (key == LogicalKeyboardKey.keyY && !isShift) {
        vm.redoInpaintMask();
        return true;
      }
    }

    if (isCtrlOrCmd || isAlt) return false;

    // [ / ] 调整笔刷半径 (允许长按连续微调)
    if (!isAiEdit && !isExecuting) {
      if (key == LogicalKeyboardKey.bracketLeft) {
        final cur = vm.inpaintParams.brushRadius;
        vm.setInpaintBrushRadius(math.min(cur - 0.002, cur * 0.85));
        return true;
      }
      if (key == LogicalKeyboardKey.bracketRight) {
        final cur = vm.inpaintParams.brushRadius;
        vm.setInpaintBrushRadius(math.max(cur + 0.002, cur * 1.18));
        return true;
      }
    }

    if (event is! KeyDownEvent) return false;

    if (key == LogicalKeyboardKey.digit0 || key == LogicalKeyboardKey.numpad0) {
      _resetViewport();
      return true;
    }
    if (isAiEdit || isExecuting) return false;

    if (key == LogicalKeyboardKey.keyH) {
      _isPanModeNotifier.value = !_isPanModeNotifier.value;
      return true;
    }
    if (key == LogicalKeyboardKey.keyR) {
      _isPanModeNotifier.value = false;
      vm.setInpaintTool(InpaintTool.rect);
      return true;
    }
    if (key == LogicalKeyboardKey.keyB) {
      _isPanModeNotifier.value = false;
      vm.setInpaintTool(InpaintTool.brush);
      return true;
    }
    if (key == LogicalKeyboardKey.keyE) {
      _isPanModeNotifier.value = false;
      vm.setInpaintTool(InpaintTool.eraser);
      return true;
    }
    if (key == LogicalKeyboardKey.keyV) {
      _maskVisibleNotifier.value = !_maskVisibleNotifier.value;
      return true;
    }

    return false;
  }

  // ---------------------------------------------------------------------------
  // 几何换算
  // ---------------------------------------------------------------------------

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

  Offset _sceneToNormalized(Offset scenePoint, Rect imageRect) => Offset(
    ((scenePoint.dx - imageRect.left) / imageRect.width).clamp(0.0, 1.0),
    ((scenePoint.dy - imageRect.top) / imageRect.height).clamp(0.0, 1.0),
  );

  Rect _normRectInside(Rect r) => Rect.fromLTRB(
    r.left.clamp(0.0, 1.0),
    r.top.clamp(0.0, 1.0),
    r.right.clamp(0.0, 1.0),
    r.bottom.clamp(0.0, 1.0),
  );

  // ---------------------------------------------------------------------------
  // 生效选区与已提交描边 Picture 缓存
  // ---------------------------------------------------------------------------

  Rect? _currentDisplaySelNorm(InpaintParams inpaint, InpaintTool tool) {
    if (tool != InpaintTool.rect) return null;
    if (inpaint.hasEffectiveBrushMask && _liveSelectionNotifier.value == null) {
      return null;
    }
    return _liveSelectionNotifier.value ?? inpaint.selectionRect;
  }

  /// 生效选区的实时值：画笔拖拽中与已有有效画笔蒙版取并集，避免画第二笔时
  /// 外延裁剪框跳动；橡皮只做减法不改变修复区，拖拽中沿用已提交的生效选区。
  Rect? _liveEffectiveSelNorm(InpaintParams inpaint) {
    final tool = widget.viewModel.inpaintTool;
    final existing = inpaint.hasEffectiveBrushMask
        ? inpaint.effectiveSelectionRect
        : (_liveSelectionNotifier.value ?? inpaint.selectionRect);

    if (tool == InpaintTool.brush && _liveStrokePoints.isNotEmpty) {
      final liveBbox = _strokeBboxNorm(_liveStrokePoints, inpaint.brushRadius);
      if (existing != null && inpaint.hasEffectiveBrushMask) {
        return existing.expandToInclude(liveBbox);
      }
      return liveBbox;
    }
    return existing;
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

  /// 把已提交描边录制为 Picture (仅在描边列表身份或基础画布尺寸变化时重录)
  ui.Picture? _buildCommittedPicture(
    List<InpaintBrushStroke> strokes,
    Rect imageRect,
  ) {
    if (strokes.isEmpty) {
      if (_committedPicture != null) {
        _committedPicture?.dispose();
        _committedPicture = null;
        _committedPictureRevision++;
      }
      _committedHasEraser = false;
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
    final localRect = Offset.zero & imageRect.size;
    final canvas = ui.Canvas(recorder, localRect);

    final shortSide = math.min(imageRect.width, imageRect.height);
    var hasEraser = false;
    for (final stroke in strokes) {
      if (stroke.points.isEmpty) continue;
      if (stroke.isEraser) hasEraser = true;
      _paintStrokeOn(
        canvas,
        stroke.points,
        stroke.radius * shortSide,
        localRect,
        isEraser: stroke.isEraser,
      );
    }

    _committedPicture = recorder.endRecording();
    _committedPictureRevision++;
    _committedHasEraser = hasEraser;
    _committedCacheKey = strokes;
    _committedCacheSize = imageRect.size;
    return _committedPicture;
  }

  void _paintStrokeOn(
    ui.Canvas canvas,
    List<Offset> points,
    double radiusPx,
    Rect rect, {
    required bool isEraser,
  }) {
    if (points.isEmpty || radiusPx <= 0) return;
    final ui.Color color = isEraser
        ? const ui.Color(0xFF000000)
        : AppTheme.coral.withValues(alpha: 0.42);
    final ui.BlendMode blend = isEraser
        ? ui.BlendMode.clear
        : ui.BlendMode.srcOver;
    Offset toCanvas(Offset p) =>
        Offset(rect.left + p.dx * rect.width, rect.top + p.dy * rect.height);

    if (points.length == 1) {
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
  // 指针状态机 (单指绘制 / 单点盖章 / 空格与中右键漫游 / 双指捏合缩放与平移)
  // ---------------------------------------------------------------------------

  void _handleCanvasPointerDown(
    PointerDownEvent e, {
    required Size canvasSize,
    required Rect imageRect,
    required InpaintParams inpaint,
    required InpaintTool tool,
    required bool isAiEdit,
    required bool isExecuting,
  }) {
    _activePointers[e.pointer] = e.localPosition;

    // 第二指落下：取消可能误触的单指起笔，无缝切入双指缩放与平移
    if (_activePointers.length >= 2) {
      _cancelActiveDrawing();
      _isViewportPanning = false;
      _panPointerId = null;
      _isActivelyPanningNotifier.value = false;
      _isPinchZooming = true;
      final pts = _activePointers.values.take(2).toList(growable: false);
      _lastPinchFocal = (pts[0] + pts[1]) / 2;
      _lastPinchSpan = (pts[0] - pts[1]).distance;
      return;
    }

    final isMiddleOrRight =
        (e.buttons & kMiddleMouseButton) != 0 ||
        (e.buttons & kSecondaryMouseButton) != 0;
    final shouldPan =
        isMiddleOrRight ||
        _isSpacePressedNotifier.value ||
        _isPanModeNotifier.value ||
        isAiEdit ||
        isExecuting;

    if (shouldPan) {
      _isViewportPanning = true;
      _panPointerId = e.pointer;
      _lastPanPos = e.localPosition;
      _isActivelyPanningNotifier.value = true;
      return;
    }

    final scenePos = _transformController.toScene(e.localPosition);

    // 画笔与橡皮仅在底图区域内起笔，避免点击画布空白边距误盖章
    if ((tool == InpaintTool.brush || tool == InpaintTool.eraser) &&
        !imageRect.contains(scenePos)) {
      return;
    }

    // 隐藏蒙版状态下起笔自动恢复显示，避免盲涂
    if (!_maskVisibleNotifier.value) {
      _maskVisibleNotifier.value = true;
    }

    _drawPointerId = e.pointer;
    _onDrawStart(scenePos, imageRect, _currentDisplaySelNorm(inpaint, tool));
  }

  void _handleCanvasPointerMove(
    PointerMoveEvent e, {
    required Size canvasSize,
    required Rect imageRect,
  }) {
    _activePointers[e.pointer] = e.localPosition;
    if (e.kind == PointerDeviceKind.mouse) {
      _hoverCanvasPosNotifier.value = e.localPosition;
    }

    if (_isPinchZooming && _activePointers.length >= 2) {
      final pts = _activePointers.values.take(2).toList(growable: false);
      final newFocal = (pts[0] + pts[1]) / 2;
      final newSpan = (pts[0] - pts[1]).distance;
      final scaleDelta = (_lastPinchSpan > 4.0 && newSpan > 4.0)
          ? (newSpan / _lastPinchSpan)
          : 1.0;
      _transformController.value = _scaleAround(
        _currentScale * scaleDelta,
        _lastPinchFocal,
        nextAnchor: newFocal,
        canvasSize: canvasSize,
        imageRect: imageRect,
      );
      _lastPinchFocal = newFocal;
      _lastPinchSpan = newSpan;
      return;
    }

    if (_isViewportPanning && e.pointer == _panPointerId) {
      final delta = e.localPosition - _lastPanPos;
      _lastPanPos = e.localPosition;
      final next = Matrix4.copy(_transformController.value)
        ..storage[12] += delta.dx
        ..storage[13] += delta.dy;
      _transformController.value = _clampTransform(next, canvasSize, imageRect);
      return;
    }

    if (_drawPointerId == e.pointer) {
      final scenePos = _transformController.toScene(e.localPosition);
      _onDrawUpdate(scenePos, imageRect);
    }
  }

  void _handleCanvasPointerUpOrCancel(
    PointerEvent e, {
    required bool cancelled,
  }) {
    _activePointers.remove(e.pointer);

    if (_isPinchZooming) {
      if (_activePointers.length < 2) {
        _isPinchZooming = false;
      }
      return;
    }

    if (_isViewportPanning && e.pointer == _panPointerId) {
      _isViewportPanning = false;
      _panPointerId = null;
      _isActivelyPanningNotifier.value = false;
      return;
    }

    if (_drawPointerId == e.pointer) {
      _drawPointerId = null;
      if (cancelled) {
        _cancelActiveDrawing();
      } else {
        _onDrawEnd();
      }
    }
  }

  void _cancelActiveDrawing() {
    _drawPointerId = null;
    if (_liveStrokePoints.isNotEmpty) {
      _liveStrokePoints.clear();
      _livePaintRevision.value++;
    }
    if (_rectDragMode != _RectDragMode.none ||
        _liveSelectionNotifier.value != null) {
      _resetRectDrag();
    }
  }

  void _onDrawStart(Offset scenePoint, Rect imageRect, Rect? selNorm) {
    final vm = widget.viewModel;
    final norm = _sceneToNormalized(scenePoint, imageRect);
    switch (vm.inpaintTool) {
      case InpaintTool.rect:
        final inside =
            !vm.inpaintParams.hasEffectiveBrushMask &&
            selNorm != null &&
            Rect.fromLTWH(
              imageRect.left + selNorm.left * imageRect.width,
              imageRect.top + selNorm.top * imageRect.height,
              selNorm.width * imageRect.width,
              selNorm.height * imageRect.height,
            ).contains(scenePoint);
        _rectDragMode = inside ? _RectDragMode.move : _RectDragMode.marquee;
        _dragBaseRect = selNorm;
        _dragStartNorm = norm;
        if (_rectDragMode == _RectDragMode.marquee) {
          _liveSelectionNotifier.value = Rect.fromPoints(norm, norm);
        }
      case InpaintTool.brush:
      case InpaintTool.eraser:
        _liveStrokePoints.clear();
        _liveStrokePoints.add(norm);
        _livePaintRevision.value++;
    }
  }

  void _onDrawUpdate(Offset scenePoint, Rect imageRect) {
    final vm = widget.viewModel;
    final norm = _sceneToNormalized(scenePoint, imageRect);
    switch (vm.inpaintTool) {
      case InpaintTool.rect:
        final start = _dragStartNorm;
        if (start == null) return;
        if (_rectDragMode == _RectDragMode.marquee) {
          _liveSelectionNotifier.value = Rect.fromPoints(start, norm);
        } else if (_rectDragMode == _RectDragMode.move) {
          final base = _dragBaseRect;
          if (base == null) return;
          final dx = norm.dx - start.dx;
          final dy = norm.dy - start.dy;
          _liveSelectionNotifier.value = Rect.fromLTWH(
            (base.left + dx).clamp(0.0, 1.0 - base.width),
            (base.top + dy).clamp(0.0, 1.0 - base.height),
            base.width,
            base.height,
          );
        }
      case InpaintTool.brush:
      case InpaintTool.eraser:
        if (_liveStrokePoints.isNotEmpty) {
          // 轻微抽稀：放大慢画时不产生冗余重复点，同时保留足够密度
          final minDelta = 1.0 / math.max(_srcW, _srcH);
          if ((norm - _liveStrokePoints.last).distance < minDelta) return;
        }
        _liveStrokePoints.add(norm);
        _livePaintRevision.value++;
    }
  }

  void _onDrawEnd() {
    final vm = widget.viewModel;
    switch (vm.inpaintTool) {
      case InpaintTool.rect:
        final r = _liveSelectionNotifier.value;
        if (r != null && r.width > 0.008 && r.height > 0.008) {
          vm.setInpaintSelectionRect(_normRectInside(r));
        }
        _resetRectDrag();
      case InpaintTool.brush:
      case InpaintTool.eraser:
        if (_liveStrokePoints.isNotEmpty) {
          vm.commitInpaintStroke(
            List<Offset>.of(_liveStrokePoints),
            erase: vm.inpaintTool == InpaintTool.eraser,
          );
        }
        _liveStrokePoints.clear();
        _livePaintRevision.value++;
    }
  }

  void _resetRectDrag() {
    _rectDragMode = _RectDragMode.none;
    _activeHandleNotifier.value = -1;
    _liveSelectionNotifier.value = null;
    _dragBaseRect = null;
    _dragStartNorm = null;
    _handleDragStartGlobal = null;
  }

  MouseCursor _resolveCanvasCursor({
    required InpaintParams inpaint,
    required InpaintTool tool,
    required bool isAiEdit,
    required bool isExecuting,
    required Rect imageRect,
  }) {
    if (_isActivelyPanningNotifier.value) return SystemMouseCursors.grabbing;
    if (_isSpacePressedNotifier.value ||
        _isPanModeNotifier.value ||
        isAiEdit ||
        isExecuting) {
      return SystemMouseCursors.grab;
    }
    final hover = _hoverCanvasPosNotifier.value;
    if (tool == InpaintTool.brush || tool == InpaintTool.eraser) {
      if (hover != null &&
          imageRect.contains(_transformController.toScene(hover))) {
        return SystemMouseCursors.none;
      }
      return SystemMouseCursors.basic;
    }
    if (tool == InpaintTool.rect && hover != null) {
      final selNorm = _currentDisplaySelNorm(inpaint, tool);
      if (selNorm != null) {
        final scenePos = _transformController.toScene(hover);
        final selScene = Rect.fromLTWH(
          imageRect.left + selNorm.left * imageRect.width,
          imageRect.top + selNorm.top * imageRect.height,
          selNorm.width * imageRect.width,
          selNorm.height * imageRect.height,
        );
        if (selScene.contains(scenePos)) return SystemMouseCursors.move;
      }
      return SystemMouseCursors.precise;
    }
    return SystemMouseCursors.basic;
  }

  // ---------------------------------------------------------------------------
  // build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final vm = widget.viewModel;
        final inpaint = vm.inpaintParams;
        final image = vm.inpaintSourceImage;
        final isAiEdit = inpaint.mode == InpaintMode.aiEdit;
        final isExecuting = vm.isExecutingInpaint || vm.isExecutingAiEdit;

        if (image == null) {
          return Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    l10n.inpaintOverlayEmptyHint,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: context.colors.textSecondary,
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: widget.compact ? 10.0 : 18.0,
                right: widget.compact ? 10.0 : 18.0,
                child: _buildBottomActionCard(
                  context,
                  vm,
                  isAiEdit: isAiEdit,
                  isExecuting: isExecuting,
                  showStartAction: false,
                ),
              ),
            ],
          );
        }

        final srcW = image.params.width > 0 ? image.params.width : 1024;
        final srcH = image.params.height > 0 ? image.params.height : 1024;
        _srcW = srcW;
        _srcH = srcH;
        final isFocus = inpaint.mode == InpaintMode.focus;
        final tool = vm.inpaintTool;
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
            _canvasSize = canvasSize;
            _imageRect = imageRect;

            final committedPicture = _buildCommittedPicture(
              inpaint.brushStrokes,
              imageRect,
            );

            return Stack(
              children: [
                // 0. 可缩放画布主区域 (严格裁剪在画板内，滚轮全区生效)
                Positioned.fill(
                  child: ClipRect(
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerSignal: _handlePointerSignal,
                      child: ListenableBuilder(
                        listenable: _cursorVisualListenable,
                        builder: (context, child) {
                          final cursor = _resolveCanvasCursor(
                            inpaint: inpaint,
                            tool: tool,
                            isAiEdit: isAiEdit,
                            isExecuting: isExecuting,
                            imageRect: imageRect,
                          );
                          return MouseRegion(
                            cursor: cursor,
                            onHover: (e) =>
                                _hoverCanvasPosNotifier.value = e.localPosition,
                            onExit: (_) => _hoverCanvasPosNotifier.value = null,
                            child: child,
                          );
                        },
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // 1+2+4. 随视口矩阵整体缩放/平移的场景层 (零重建、GPU 变换)
                            ValueListenableBuilder<Matrix4>(
                              valueListenable: _transformController,
                              builder: (context, matrix, child) => Transform(
                                transform: matrix,
                                alignment: Alignment.topLeft,
                                child: child,
                              ),
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  // 1. 源图 (按缩放档位动态解码高分辨率，放大不糊)
                                  Positioned.fromRect(
                                    key: const ValueKey('inpaint-src'),
                                    rect: imageRect,
                                    child: RepaintBoundary(
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(6),
                                        child: ValueListenableBuilder<double>(
                                          valueListenable: _imageLodNotifier,
                                          builder: (context, lod, _) =>
                                              ValueListenableBuilder<
                                                Map<String, Uint8List>
                                              >(
                                                valueListenable:
                                                    vm.imageBytesNotifier,
                                                builder: (context, bytesMap, _) {
                                                  final fullBytes =
                                                      image.bytes.isNotEmpty
                                                      ? image.bytes
                                                      : bytesMap[image.id];
                                                  final desiredPx =
                                                      imageRect.width *
                                                      dpr *
                                                      lod;
                                                  final int? cacheW =
                                                      desiredPx >= srcW
                                                      ? null
                                                      : (((desiredPx / 128.0)
                                                                    .ceil() *
                                                                128)
                                                            .clamp(128, 4096));
                                                  if (fullBytes != null &&
                                                      fullBytes.isNotEmpty) {
                                                    return Image.memory(
                                                      fullBytes,
                                                      fit: BoxFit.fill,
                                                      gaplessPlayback: true,
                                                      filterQuality: lod > 1.0
                                                          ? FilterQuality.medium
                                                          : FilterQuality.low,
                                                      cacheWidth: cacheW,
                                                    );
                                                  }

                                                  vm.ensureImageLoaded(image);

                                                  final thumb =
                                                      image.thumbnailBytes;
                                                  if (thumb != null &&
                                                      thumb.isNotEmpty) {
                                                    return Image.memory(
                                                      thumb,
                                                      fit: BoxFit.fill,
                                                      gaplessPlayback: true,
                                                      cacheWidth: cacheW,
                                                    );
                                                  }

                                                  return Container(
                                                    color: context
                                                        .colors
                                                        .mutedBackground,
                                                    child: Center(
                                                      child: SizedBox(
                                                        width: 24,
                                                        height: 24,
                                                        child: CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                          valueColor:
                                                              AlwaysStoppedAnimation<
                                                                Color
                                                              >(
                                                                context
                                                                    .colors
                                                                    .primary,
                                                              ),
                                                        ),
                                                      ),
                                                    ),
                                                  );
                                                },
                                              ),
                                        ),
                                      ),
                                    ),
                                  ),

                                  // 2. 蒙版层：外延框外压暗 + 已提交描边 Picture + 实时描边 + 选区框
                                  if (!isAiEdit)
                                    Positioned.fromRect(
                                      key: const ValueKey('inpaint-mask'),
                                      rect: imageRect,
                                      child: IgnorePointer(
                                        child: RepaintBoundary(
                                          child: CustomPaint(
                                            painter: _InpaintMaskPainter(
                                              repaint:
                                                  _viewportOverlayListenable,
                                              committedPicture:
                                                  committedPicture,
                                              committedRevision:
                                                  _committedPictureRevision,
                                              committedHasEraser:
                                                  _committedHasEraser,
                                              liveStroke: _liveStrokePoints,
                                              liveStrokeIsEraser:
                                                  tool == InpaintTool.eraser,
                                              liveBrushRadius:
                                                  inpaint.brushRadius,
                                              tool: tool,
                                              baseSelectionRect:
                                                  inpaint.selectionRect,
                                              effectiveBrushSelectionRect:
                                                  inpaint.hasEffectiveBrushMask
                                                  ? inpaint
                                                        .effectiveSelectionRect
                                                  : null,
                                              liveSelection:
                                                  _liveSelectionNotifier,
                                              hasEffectiveBrushMask:
                                                  inpaint.hasEffectiveBrushMask,
                                              maskVisible: _maskVisibleNotifier,
                                              transformController:
                                                  _transformController,
                                              isFocus: isFocus,
                                              contextPadding:
                                                  inpaint.contextPadding,
                                              srcW: srcW,
                                              srcH: srcH,
                                              computeCropNorm: (selNorm) =>
                                                  _liveContextCropNorm(
                                                    selNorm,
                                                    srcW,
                                                    srcH,
                                                  ),
                                              selectionColor:
                                                  context.colors.primary,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),

                                  // 4. 执行中的中间帧预览 (贴在外延裁剪框位置，随视口缩放)
                                  if (isExecuting)
                                    ValueListenableBuilder<Uint8List?>(
                                      valueListenable:
                                          vm.inpaintPreviewNotifier,
                                      builder: (context, bytes, _) {
                                        if (bytes == null) {
                                          return const SizedBox.shrink();
                                        }
                                        final cropNormRect = isFocus
                                            ? _liveContextCropNorm(
                                                _liveEffectiveSelNorm(inpaint),
                                                srcW,
                                                srcH,
                                              )
                                            : null;
                                        final cropCanvasRect =
                                            cropNormRect == null
                                            ? null
                                            : Rect.fromLTWH(
                                                imageRect.left +
                                                    cropNormRect.left *
                                                        imageRect.width,
                                                imageRect.top +
                                                    cropNormRect.top *
                                                        imageRect.height,
                                                cropNormRect.width *
                                                    imageRect.width,
                                                cropNormRect.height *
                                                    imageRect.height,
                                              );
                                        return Positioned.fromRect(
                                          key: const ValueKey(
                                            'inpaint-preview',
                                          ),
                                          rect:
                                              (isFocus &&
                                                  cropCanvasRect != null)
                                              ? cropCanvasRect
                                              : imageRect,
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                            child: Image.memory(
                                              bytes,
                                              fit: BoxFit.contain,
                                              gaplessPlayback: true,
                                              cacheWidth: 256,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                ],
                              ),
                            ),

                            // 3. 焦点模式外延上下文框 (视口空间渲染，缩放后字号与边框始终清晰)
                            if (isFocus)
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: ListenableBuilder(
                                    listenable: _viewportOverlayListenable,
                                    builder: (context, _) {
                                      if (!_maskVisibleNotifier.value) {
                                        return const SizedBox.shrink();
                                      }
                                      final liveEffectiveSel =
                                          _liveEffectiveSelNorm(inpaint);
                                      final cropNormRect = _liveContextCropNorm(
                                        liveEffectiveSel,
                                        srcW,
                                        srcH,
                                      );
                                      if (cropNormRect == null) {
                                        return const SizedBox.shrink();
                                      }
                                      final cropSceneRect = Rect.fromLTWH(
                                        imageRect.left +
                                            cropNormRect.left * imageRect.width,
                                        imageRect.top +
                                            cropNormRect.top * imageRect.height,
                                        cropNormRect.width * imageRect.width,
                                        cropNormRect.height * imageRect.height,
                                      );
                                      final cropViewportRect =
                                          MatrixUtils.transformRect(
                                            _transformController.value,
                                            cropSceneRect,
                                          );
                                      return Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          Positioned.fromRect(
                                            key: const ValueKey(
                                              'inpaint-crop-frame',
                                            ),
                                            rect: cropViewportRect,
                                            child: Container(
                                              decoration: BoxDecoration(
                                                border: Border.all(
                                                  color: context.colors.primary
                                                      .withValues(alpha: 0.45),
                                                  width: 1.2,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Align(
                                                alignment: Alignment.topLeft,
                                                child: Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 5,
                                                        vertical: 2,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color:
                                                        context.colors.primary,
                                                    borderRadius:
                                                        const BorderRadius.only(
                                                          topLeft:
                                                              Radius.circular(
                                                                3,
                                                              ),
                                                          bottomRight:
                                                              Radius.circular(
                                                                3,
                                                              ),
                                                        ),
                                                  ),
                                                  child: Text(
                                                    l10n.inpaintOverlayContextCrop(
                                                      inpaint.contextPadding
                                                          .round(),
                                                    ),
                                                    style: const TextStyle(
                                                      fontSize: 9,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                              ),

                            // 5. 全画布原始指针交互层 (边缘起手框选 / 漫游平移 / 双指缩放 / 单击盖章)
                            Positioned.fill(
                              key: const ValueKey('inpaint-gesture'),
                              child: Listener(
                                behavior: HitTestBehavior.opaque,
                                onPointerDown: (e) => _handleCanvasPointerDown(
                                  e,
                                  canvasSize: canvasSize,
                                  imageRect: imageRect,
                                  inpaint: inpaint,
                                  tool: tool,
                                  isAiEdit: isAiEdit,
                                  isExecuting: isExecuting,
                                ),
                                onPointerMove: (e) => _handleCanvasPointerMove(
                                  e,
                                  canvasSize: canvasSize,
                                  imageRect: imageRect,
                                ),
                                onPointerUp: (e) =>
                                    _handleCanvasPointerUpOrCancel(
                                      e,
                                      cancelled: false,
                                    ),
                                onPointerCancel: (e) =>
                                    _handleCanvasPointerUpOrCancel(
                                      e,
                                      cancelled: true,
                                    ),
                                child: const SizedBox.expand(),
                              ),
                            ),

                            // 6. 四角缩放手柄 (视口空间定位，任何倍率下尺寸与命中区恒定)
                            if (!isExecuting &&
                                !isAiEdit &&
                                tool == InpaintTool.rect &&
                                !inpaint.hasEffectiveBrushMask)
                              Positioned.fill(
                                child: ListenableBuilder(
                                  listenable: Listenable.merge([
                                    _liveSelectionNotifier,
                                    _activeHandleNotifier,
                                    _transformController,
                                    _maskVisibleNotifier,
                                    _isPanModeNotifier,
                                    _isSpacePressedNotifier,
                                  ]),
                                  builder: (context, _) {
                                    if (!_maskVisibleNotifier.value ||
                                        _isPanModeNotifier.value ||
                                        _isSpacePressedNotifier.value) {
                                      return const SizedBox.shrink();
                                    }
                                    final displaySelNorm =
                                        _currentDisplaySelNorm(inpaint, tool);
                                    if (displaySelNorm == null) {
                                      return const SizedBox.shrink();
                                    }
                                    final displaySelScene = Rect.fromLTWH(
                                      imageRect.left +
                                          displaySelNorm.left * imageRect.width,
                                      imageRect.top +
                                          displaySelNorm.top * imageRect.height,
                                      displaySelNorm.width * imageRect.width,
                                      displaySelNorm.height * imageRect.height,
                                    );
                                    final displaySelViewport =
                                        MatrixUtils.transformRect(
                                          _transformController.value,
                                          displaySelScene,
                                        );
                                    return Stack(
                                      clipBehavior: Clip.none,
                                      children: _buildCornerHandles(
                                        imageRect,
                                        displaySelNorm,
                                        displaySelViewport,
                                        _activeHandleNotifier.value,
                                      ),
                                    );
                                  },
                                ),
                              ),

                            // 6b. 画笔 / 橡皮实时圆形光标与滑条大小预览层
                            if (!isExecuting && !isAiEdit)
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: CustomPaint(
                                    painter: _BrushCursorPainter(
                                      repaint: _cursorVisualListenable,
                                      hoverPos: _hoverCanvasPosNotifier,
                                      sliderPreviewRadius:
                                          _brushSliderPreviewNotifier,
                                      transformController: _transformController,
                                      isSpacePressed: _isSpacePressedNotifier,
                                      isPanMode: _isPanModeNotifier,
                                      isActivelyPanning:
                                          _isActivelyPanningNotifier,
                                      tool: tool,
                                      brushRadius: inpaint.brushRadius,
                                      imageRect: imageRect,
                                      srcW: srcW,
                                      srcH: srcH,
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

                // 7. 顶部浮动工具坞 (主工具栏精简不截断，笔刷滑条以二级迷你胶囊折在正下方)
                Positioned(
                  key: const ValueKey('inpaint-dock'),
                  top: 14,
                  left: (!widget.compact && vm.isLeftSidebarCollapsed)
                      ? 60
                      : 12,
                  right: 12,
                  child: Center(
                    child: _buildToolDock(
                      context,
                      vm,
                      inpaint,
                      srcW: srcW,
                      srcH: srcH,
                    ),
                  ),
                ),

                // 7b. 右上角点数标识 (宽画布独立停靠，不挤占顶部工具坞宽度)
                if (!isAiEdit && canvasSize.width >= 540)
                  Positioned(
                    key: const ValueKey('inpaint-cost-badge'),
                    top: 19,
                    right: 14,
                    child: _buildCostBadge(context, vm, inpaint),
                  ),

                // 8. 底部响应式控制区：宽画布左右分置，窄画布自动折为上下两层防碰撞
                _buildBottomControlsBar(
                  context,
                  vm,
                  canvasWidth: canvasSize.width,
                  isAiEdit: isAiEdit,
                  isExecuting: isExecuting,
                  showStartAction: !widget.compact && vm.isLeftSidebarCollapsed,
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 四角手柄
  // ---------------------------------------------------------------------------

  List<Widget> _buildCornerHandles(
    Rect imageRect,
    Rect selNorm,
    Rect selViewport,
    int activeHandleIndex,
  ) {
    const handleHit = 28.0;

    Rect applyDelta(Rect base, int corner, Offset deltaNorm) {
      var l = base.left;
      var t = base.top;
      var r = base.right;
      var b = base.bottom;
      switch (corner) {
        case 0: // TL
          l = (l + deltaNorm.dx).clamp(0.0, r - 0.01);
          t = (t + deltaNorm.dy).clamp(0.0, b - 0.01);
        case 1: // TR
          r = (r + deltaNorm.dx).clamp(l + 0.01, 1.0);
          t = (t + deltaNorm.dy).clamp(0.0, b - 0.01);
        case 2: // BR
          r = (r + deltaNorm.dx).clamp(l + 0.01, 1.0);
          b = (b + deltaNorm.dy).clamp(t + 0.01, 1.0);
        case 3: // BL
          l = (l + deltaNorm.dx).clamp(0.0, r - 0.01);
          b = (b + deltaNorm.dy).clamp(t + 0.01, 1.0);
      }
      return Rect.fromLTRB(l, t, r, b);
    }

    MouseCursor cursorForCorner(int corner) => switch (corner) {
      0 || 2 => SystemMouseCursors.resizeUpLeftDownRight,
      _ => SystemMouseCursors.resizeUpRightDownLeft,
    };

    Widget handle(int corner, Offset center) {
      return Positioned(
        key: ValueKey('inpaint-handle-$corner'),
        left: center.dx - handleHit / 2,
        top: center.dy - handleHit / 2,
        width: handleHit,
        height: handleHit,
        child: MouseRegion(
          cursor: cursorForCorner(corner),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (d) {
              _handleDragStartGlobal = d.globalPosition;
              _dragBaseRect = selNorm;
              _activeHandleNotifier.value = corner;
              _liveSelectionNotifier.value = selNorm;
            },
            onPanUpdate: (d) {
              final start = _handleDragStartGlobal;
              final base = _dragBaseRect;
              if (start == null || base == null) return;
              final scale = _currentScale;
              final deltaNorm = Offset(
                (d.globalPosition.dx - start.dx) / (imageRect.width * scale),
                (d.globalPosition.dy - start.dy) / (imageRect.height * scale),
              );
              _liveSelectionNotifier.value = _normRectInside(
                applyDelta(base, corner, deltaNorm),
              );
            },
            onPanEnd: (_) {
              final r = _liveSelectionNotifier.value;
              if (r != null && r.width > 0.008 && r.height > 0.008) {
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
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: activeHandleIndex == corner
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
        ),
      );
    }

    return [
      handle(0, selViewport.topLeft),
      handle(1, selViewport.topRight),
      handle(2, selViewport.bottomRight),
      handle(3, selViewport.bottomLeft),
    ];
  }

  // ---------------------------------------------------------------------------
  // 顶部工具坞 & 右上点数标识 & 左下角辅助胶囊 & 右下角操作坞
  // ---------------------------------------------------------------------------

  Widget _buildCostBadge(
    BuildContext context,
    StudioViewModel vm,
    InpaintParams inpaint,
  ) {
    final l10n = context.l10n;
    final geometry = vm.inpaintGeometry;
    final inpaintModel = inpaint.customModel ?? vm.params.model;
    final mediumEffort =
        inpaintModel == NaiModel.v5Full && vm.params.isMediumEffort;
    final steps = mediumEffort
        ? NaiEffort.mediumSteps
        : (inpaint.customSteps ?? vm.params.steps);
    final isFree = geometry.isOpusFree && steps <= 28;
    return AppBadge(
      label: isFree ? l10n.opusFree : l10n.inpaintRequiresPoints,
      variant: isFree ? AppBadgeVariant.success : AppBadgeVariant.warning,
    );
  }

  Widget _buildToolDock(
    BuildContext context,
    StudioViewModel vm,
    InpaintParams inpaint, {
    required int srcW,
    required int srcH,
  }) {
    final colors = context.colors;
    final l10n = context.l10n;

    if (inpaint.mode == InpaintMode.aiEdit) {
      return AppFloatingDock(
        radius: 20,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
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
        ),
      );
    }

    final showBrushSize =
        vm.inpaintTool == InpaintTool.brush ||
        vm.inpaintTool == InpaintTool.eraser;
    final minSide = math.min(srcW, srcH);

    Widget divider() => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Container(width: 1, height: 15, color: colors.borderDefault),
    );

    final iconBtnSize = widget.compact ? 30.0 : 28.0;
    final iconBtnRadius = iconBtnSize / 2;

    return ValueListenableBuilder<bool>(
      valueListenable: _isPanModeNotifier,
      builder: (context, isPanMode, _) {
        Widget toolChip(InpaintTool tool, IconData icon, String label) {
          final selected = !isPanMode && vm.inpaintTool == tool;
          return AppToolChip(
            icon: icon,
            label: label,
            isSelected: selected,
            variant: AppToolChipVariant.tinted,
            fontSize: 11.5,
            iconSize: 13.5,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            radius: 14,
            onTap: () {
              _isPanModeNotifier.value = false;
              vm.setInpaintTool(tool);
            },
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppFloatingDock(
              radius: 20,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppIconButton(
                      key: const Key('inpaint_pan_toggle_button'),
                      icon: Icons.pan_tool_outlined,
                      tooltip: l10n.inpaintToolPan,
                      size: iconBtnSize,
                      iconSize: 15,
                      radius: iconBtnRadius,
                      variant: isPanMode
                          ? AppIconButtonVariant.primary
                          : AppIconButtonVariant.ghost,
                      onPressed: () =>
                          _isPanModeNotifier.value = !_isPanModeNotifier.value,
                    ),
                    divider(),
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
                    divider(),
                    AppToolChip(
                      key: const Key('inpaint_clear_mask_button'),
                      icon: Icons.delete_sweep_outlined,
                      label: l10n.inpaintClearMask,
                      variant: AppToolChipVariant.tinted,
                      unselectedBackgroundColor: colors.errorSurface,
                      fontSize: 11.5,
                      iconSize: 13.5,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      radius: 14,
                      onTap: vm.clearInpaintMask,
                    ),
                  ],
                ),
              ),
            ),
            AppPanelReveal(
              visible: showBrushSize && !isPanMode,
              openDuration: AppMotionDurations.fast,
              closeDuration: AppMotionDurations.quick,
              slideOffset: AppMotionDistances.micro,
              enableBlur: false,
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: AppFloatingDock(
                  key: const ValueKey('inpaint-brush-size-dock'),
                  radius: 16,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 2,
                  ),
                  enableBlur: true,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        vm.inpaintTool == InpaintTool.eraser
                            ? Icons.layers_clear_rounded
                            : Icons.circle,
                        size: vm.inpaintTool == InpaintTool.eraser ? 12 : 9,
                        color: vm.inpaintTool == InpaintTool.eraser
                            ? colors.textSecondary
                            : AppTheme.coral,
                      ),
                      const SizedBox(width: 4),
                      _BrushSizeSlider(
                        value: inpaint.brushRadius,
                        min: _minBrushRadius,
                        max: _maxBrushRadius,
                        onPreviewChanged: (v) =>
                            _brushSliderPreviewNotifier.value = v,
                        onCommit: (v) {
                          _brushSliderPreviewNotifier.value = null;
                          vm.setInpaintBrushRadius(v);
                        },
                      ),
                      const SizedBox(width: 4),
                      ValueListenableBuilder<double?>(
                        valueListenable: _brushSliderPreviewNotifier,
                        builder: (context, preview, _) {
                          final r = preview ?? inpaint.brushRadius;
                          final px = (r * minSide * 2).round();
                          return SizedBox(
                            width: 34,
                            child: Text(
                              '${px}px',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                                color: colors.textSecondary,
                              ),
                            ),
                          );
                        },
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
  }

  Widget _buildBottomControlsBar(
    BuildContext context,
    StudioViewModel vm, {
    required double canvasWidth,
    required bool isAiEdit,
    required bool isExecuting,
    required bool showStartAction,
  }) {
    final l10n = context.l10n;
    final edge = widget.compact ? 10.0 : 18.0;
    final btnSize = widget.compact ? 30.0 : 28.0;
    final btnRadius = btnSize / 2;
    final isTightBottom = canvasWidth < (showStartAction ? 520.0 : 420.0);

    final statusPill = isExecuting
        ? AppFloatingDock(
            key: const ValueKey('inpaint-status'),
            radius: 18,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
          )
        : null;

    final leftControls = _buildBottomLeftCluster(
      context,
      vm,
      isAiEdit: isAiEdit,
      btnSize: btnSize,
      btnRadius: btnRadius,
    );
    final rightDock = _buildBottomActionCard(
      context,
      vm,
      isAiEdit: isAiEdit,
      isExecuting: isExecuting,
      showStartAction: showStartAction,
    );

    return Positioned(
      bottom: edge,
      left: edge,
      right: edge,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (statusPill != null) ...[
            Align(alignment: Alignment.centerLeft, child: statusPill),
            const SizedBox(height: 6),
          ],
          if (isTightBottom) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: leftControls,
              ),
            ),
            const SizedBox(height: 6),
            Align(alignment: Alignment.centerRight, child: rightDock),
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: leftControls,
                  ),
                ),
                const SizedBox(width: 8),
                rightDock,
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildBottomLeftCluster(
    BuildContext context,
    StudioViewModel vm, {
    required bool isAiEdit,
    required double btnSize,
    required double btnRadius,
  }) {
    final l10n = context.l10n;
    final colors = context.colors;

    return Row(
      key: const ValueKey('inpaint-zoom-dock'),
      mainAxisSize: MainAxisSize.min,
      children: [
        AppFloatingDock(
          radius: 18,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          enableBlur: true,
          child: ValueListenableBuilder<Matrix4>(
            valueListenable: _transformController,
            builder: (context, _, _) {
              final scale = _currentScale;
              final percentText = '${(scale * 100).round()}%';
              final isDefaultView =
                  (scale - 1.0).abs() < 0.01 &&
                  _transformController.value.storage[12].abs() < 0.5 &&
                  _transformController.value.storage[13].abs() < 0.5;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIconButton(
                    key: const Key('inpaint_zoom_out_button'),
                    icon: Icons.remove_rounded,
                    tooltip: l10n.inpaintZoomOut,
                    size: btnSize,
                    iconSize: 15,
                    radius: btnRadius,
                    variant: AppIconButtonVariant.ghost,
                    onPressed: scale > _minZoom + 0.01
                        ? () => _zoomBy(1 / 1.25)
                        : null,
                  ),
                  Tooltip(
                    message: l10n.inpaintZoomReset,
                    child: InkWell(
                      key: const Key('inpaint_zoom_reset_text'),
                      borderRadius: BorderRadius.circular(10),
                      onTap: isDefaultView ? null : _resetViewport,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 5,
                        ),
                        child: SizedBox(
                          width: 38,
                          child: Text(
                            percentText,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                              color: isDefaultView
                                  ? colors.textSecondary
                                  : colors.primary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  AppIconButton(
                    key: const Key('inpaint_zoom_in_button'),
                    icon: Icons.add_rounded,
                    tooltip: l10n.inpaintZoomIn,
                    size: btnSize,
                    iconSize: 15,
                    radius: btnRadius,
                    variant: AppIconButtonVariant.ghost,
                    onPressed: scale < _maxZoom - 0.01
                        ? () => _zoomBy(1.25)
                        : null,
                  ),
                  if (!isDefaultView)
                    AppIconButton(
                      key: const Key('inpaint_fit_view_button'),
                      icon: Icons.fit_screen_rounded,
                      tooltip: l10n.inpaintZoomReset,
                      size: btnSize,
                      iconSize: 14,
                      radius: btnRadius,
                      variant: AppIconButtonVariant.ghost,
                      onPressed: _resetViewport,
                    ),
                ],
              );
            },
          ),
        ),
        if (!isAiEdit) ...[
          const SizedBox(width: 6),
          AppFloatingDock(
            key: const ValueKey('inpaint-history-dock'),
            radius: 18,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            enableBlur: true,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIconButton(
                  key: const Key('inpaint_undo_button'),
                  icon: Icons.undo_rounded,
                  tooltip: l10n.inpaintUndoMask,
                  size: btnSize,
                  iconSize: 15,
                  radius: btnRadius,
                  variant: AppIconButtonVariant.ghost,
                  onPressed: vm.canUndoInpaintMask ? vm.undoInpaintMask : null,
                ),
                AppIconButton(
                  key: const Key('inpaint_redo_button'),
                  icon: Icons.redo_rounded,
                  tooltip: l10n.inpaintRedoMask,
                  size: btnSize,
                  iconSize: 15,
                  radius: btnRadius,
                  variant: AppIconButtonVariant.ghost,
                  onPressed: vm.canRedoInpaintMask ? vm.redoInpaintMask : null,
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: _maskVisibleNotifier,
                  builder: (context, visible, _) => AppIconButton(
                    key: const Key('inpaint_mask_visibility_button'),
                    icon: visible
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    tooltip: visible
                        ? l10n.inpaintToggleMaskVisibility
                        : l10n.inpaintShowMask,
                    size: btnSize,
                    iconSize: 15,
                    radius: btnRadius,
                    variant: visible
                        ? AppIconButtonVariant.ghost
                        : AppIconButtonVariant.primary,
                    onPressed: () => _maskVisibleNotifier.value = !visible,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildBottomActionCard(
    BuildContext context,
    StudioViewModel vm, {
    required bool isAiEdit,
    required bool isExecuting,
    required bool showStartAction,
  }) {
    final l10n = context.l10n;

    return AppFloatingDock(
      padding: const EdgeInsets.all(4),
      enableBlur: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppActionButton(
            key: const Key('inpaint_exit_button'),
            icon: Icons.close_rounded,
            label: l10n.inpaintExit,
            variant: AppActionButtonVariant.ghost,
            padding: widget.compact
                ? const EdgeInsets.symmetric(horizontal: 10, vertical: 7)
                : null,
            onPressed: isExecuting
                ? null
                : (widget.onExit ??
                      () => vm.exitInpaintMode(expandSidebar: false)),
          ),
          if (showStartAction) ...[
            const SizedBox(width: 6),
            AppActionButton(
              key: const Key('inpaint_canvas_start_button'),
              icon: isAiEdit
                  ? Icons.auto_awesome
                  : Icons.auto_fix_high_outlined,
              label: isExecuting
                  ? (isAiEdit ? l10n.dockAiEditing : l10n.dockInpainting)
                  : (isAiEdit ? l10n.startAiEdit : l10n.startInpaint),
              variant: AppActionButtonVariant.primary,
              isLoading: isExecuting,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              onPressed: (isExecuting || vm.isGenerating)
                  ? null
                  : () => vm.executeInpaint(),
            ),
          ],
        ],
      ),
    );
  }
}

enum _RectDragMode { none, marquee, move }

/// 本地拖动、松手提交的非线性笔刷大小滑条 (平方映射：小笔刷区间更细腻，
/// 拖动期间零 notifyListeners，同时通过回调驱动画布中心圆环实时预览)
class _BrushSizeSlider extends StatefulWidget {
  final double value;
  final double min;
  final double max;
  final ValueChanged<double?> onPreviewChanged;
  final ValueChanged<double> onCommit;

  const _BrushSizeSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.onPreviewChanged,
    required this.onCommit,
  });

  @override
  State<_BrushSizeSlider> createState() => _BrushSizeSliderState();
}

class _BrushSizeSliderState extends State<_BrushSizeSlider> {
  double? _dragNormalized;

  double _toSlider(double radius) {
    final norm = ((radius - widget.min) / (widget.max - widget.min)).clamp(
      0.0,
      1.0,
    );
    return math.sqrt(norm);
  }

  double _fromSlider(double t) {
    final clamped = t.clamp(0.0, 1.0);
    return widget.min + clamped * clamped * (widget.max - widget.min);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final sliderValue =
        _dragNormalized ??
        _toSlider(widget.value.clamp(widget.min, widget.max));
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
          value: sliderValue,
          min: 0.0,
          max: 1.0,
          onChanged: (t) {
            setState(() => _dragNormalized = t);
            widget.onPreviewChanged(_fromSlider(t));
          },
          onChangeEnd: (t) {
            final radius = _fromSlider(t);
            setState(() => _dragNormalized = null);
            widget.onCommit(radius);
          },
        ),
      ),
    );
  }
}

/// 画笔 / 橡皮光标实时预览绘制器 (视口坐标，零 rebuild)
class _BrushCursorPainter extends CustomPainter {
  final ValueNotifier<Offset?> hoverPos;
  final ValueNotifier<double?> sliderPreviewRadius;
  final TransformationController transformController;
  final ValueNotifier<bool> isSpacePressed;
  final ValueNotifier<bool> isPanMode;
  final ValueNotifier<bool> isActivelyPanning;
  final InpaintTool tool;
  final double brushRadius;
  final Rect imageRect;
  final int srcW;
  final int srcH;

  _BrushCursorPainter({
    required Listenable repaint,
    required this.hoverPos,
    required this.sliderPreviewRadius,
    required this.transformController,
    required this.isSpacePressed,
    required this.isPanMode,
    required this.isActivelyPanning,
    required this.tool,
    required this.brushRadius,
    required this.imageRect,
    required this.srcW,
    required this.srcH,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = transformController.value.entry(0, 0);
    final safeScale = (scale.isFinite && scale > 0) ? scale : 1.0;
    final shortSide = math.min(imageRect.width, imageRect.height);

    // 拖动笔刷滑条时在画布居中展示当前笔刷真实半径预览
    final previewNorm = sliderPreviewRadius.value;
    if (previewNorm != null) {
      final center = Offset(size.width / 2, size.height / 2);
      final rPx = previewNorm * shortSide * safeScale;
      _drawBrushRing(
        canvas,
        center,
        rPx,
        isEraser: tool == InpaintTool.eraser,
        pixelLabel: '${(previewNorm * math.min(srcW, srcH) * 2).round()} px',
      );
      return;
    }

    if (tool != InpaintTool.brush && tool != InpaintTool.eraser) return;
    if (isSpacePressed.value || isPanMode.value || isActivelyPanning.value) {
      return;
    }
    final pos = hoverPos.value;
    if (pos == null) return;
    if (!imageRect.contains(transformController.toScene(pos))) return;

    final rPx = brushRadius * shortSide * safeScale;
    _drawBrushRing(
      canvas,
      pos,
      rPx,
      isEraser: tool == InpaintTool.eraser,
    );
  }

  void _drawBrushRing(
    Canvas canvas,
    Offset center,
    double radiusPx, {
    required bool isEraser,
    String? pixelLabel,
  }) {
    final r = math.max(2.0, radiusPx);
    // 外阴影对比环，保证亮暗底图均清晰可见
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..color = Colors.black.withValues(alpha: 0.45)
        ..isAntiAlias = true,
    );
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = isEraser ? Colors.white : AppTheme.coral
        ..isAntiAlias = true,
    );
    // 中心精准准星小点
    canvas.drawCircle(
      center,
      1.6,
      Paint()..color = isEraser ? Colors.white : AppTheme.coral,
    );

    if (pixelLabel != null) {
      final tp = TextPainter(
        text: TextSpan(
          text: pixelLabel,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final pillRect = Rect.fromCenter(
        center: Offset(center.dx, center.dy + r + 16),
        width: tp.width + 12,
        height: tp.height + 6,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(pillRect, const Radius.circular(8)),
        Paint()..color = Colors.black.withValues(alpha: 0.72),
      );
      tp.paint(
        canvas,
        Offset(pillRect.left + 6, pillRect.top + 3),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BrushCursorPainter old) =>
      old.tool != tool ||
      old.brushRadius != brushRadius ||
      old.imageRect != imageRect ||
      old.srcW != srcW ||
      old.srcH != srcH;
}

/// 蒙版可视化绘制器：外延框外压暗环带 + 已提交描边 Picture + 实时描边 + 选区框
class _InpaintMaskPainter extends CustomPainter {
  final ui.Picture? committedPicture;
  final int committedRevision;
  final bool committedHasEraser;
  final List<Offset> liveStroke;
  final bool liveStrokeIsEraser;
  final double liveBrushRadius;
  final InpaintTool tool;
  final Rect? baseSelectionRect;
  final Rect? effectiveBrushSelectionRect;
  final ValueNotifier<Rect?> liveSelection;
  final bool hasEffectiveBrushMask;
  final ValueNotifier<bool> maskVisible;
  final TransformationController transformController;
  final bool isFocus;
  final double contextPadding;
  final int srcW;
  final int srcH;
  final Rect? Function(Rect? selNorm) computeCropNorm;

  /// 选区描框主题色 (由当前主题注入)
  final Color selectionColor;

  _InpaintMaskPainter({
    required Listenable repaint,
    required this.committedPicture,
    required this.committedRevision,
    required this.committedHasEraser,
    required this.liveStroke,
    required this.liveStrokeIsEraser,
    required this.liveBrushRadius,
    required this.tool,
    required this.baseSelectionRect,
    required this.effectiveBrushSelectionRect,
    required this.liveSelection,
    required this.hasEffectiveBrushMask,
    required this.maskVisible,
    required this.transformController,
    required this.isFocus,
    required this.contextPadding,
    required this.srcW,
    required this.srcH,
    required this.computeCropNorm,
    required this.selectionColor,
  }) : super(repaint: repaint);

  Rect? _resolveLiveEffectiveSelection() {
    final existing = hasEffectiveBrushMask
        ? effectiveBrushSelectionRect
        : (liveSelection.value ?? baseSelectionRect);

    if (tool == InpaintTool.brush && liveStroke.isNotEmpty) {
      var l = liveStroke.first.dx;
      var t = liveStroke.first.dy;
      var r = l;
      var b = t;
      for (final p in liveStroke.skip(1)) {
        l = math.min(l, p.dx);
        t = math.min(t, p.dy);
        r = math.max(r, p.dx);
        b = math.max(b, p.dy);
      }
      final liveBbox = Rect.fromLTRB(
        (l - liveBrushRadius).clamp(0.0, 1.0),
        (t - liveBrushRadius).clamp(0.0, 1.0),
        (r + liveBrushRadius).clamp(0.0, 1.0),
        (b + liveBrushRadius).clamp(0.0, 1.0),
      );
      if (existing != null && hasEffectiveBrushMask) {
        return existing.expandToInclude(liveBbox);
      }
      return liveBbox;
    }
    return existing;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (!maskVisible.value) return;

    final showRect =
        tool == InpaintTool.rect &&
        (!hasEffectiveBrushMask || liveSelection.value != null);
    final selectionRect = showRect
        ? (liveSelection.value ?? baseSelectionRect)
        : null;
    final dim = isFocus
        ? computeCropNorm(_resolveLiveEffectiveSelection())
        : null;

    // 1. 焦点模式：外延裁剪框外压暗 (外矩形+内矩形 even-odd 只填环带)
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

    // 2+3. 笔迹层：仅当存在橡皮擦笔迹 (BlendMode.clear) 时才分配 saveLayer 隔离图层
    if (committedPicture != null || liveStroke.isNotEmpty) {
      final needsIsolationLayer =
          committedHasEraser || (liveStroke.isNotEmpty && liveStrokeIsEraser);
      if (needsIsolationLayer) {
        canvas.saveLayer(Offset.zero & size, Paint());
      }
      if (committedPicture != null) {
        canvas.drawPicture(committedPicture!);
      }
      if (liveStroke.isNotEmpty) {
        final shortSide = math.min(size.width, size.height);
        final radius = liveBrushRadius.clamp(0.003, 0.25) * shortSide;
        final Color strokeColor = liveStrokeIsEraser
            ? const Color(0xFF000000)
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
      if (needsIsolationLayer) {
        canvas.restore();
      }
    }

    // 4. 矩形选区框 (边框线宽反缩放，任意倍率保持清晰 2px)
    final sel = selectionRect;
    if (sel != null && !sel.isEmpty && sel.width > 0 && sel.height > 0) {
      final rawScale = transformController.value.entry(0, 0);
      final viewScale = (rawScale.isFinite && rawScale > 0) ? rawScale : 1.0;
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
          ..strokeWidth = 2.0 / viewScale,
      );
      canvas.drawRect(
        r,
        Paint()..color = selectionColor.withValues(alpha: 0.10),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _InpaintMaskPainter old) =>
      old.committedRevision != committedRevision ||
      old.committedHasEraser != committedHasEraser ||
      old.liveStrokeIsEraser != liveStrokeIsEraser ||
      old.liveBrushRadius != liveBrushRadius ||
      old.tool != tool ||
      old.baseSelectionRect != baseSelectionRect ||
      old.effectiveBrushSelectionRect != effectiveBrushSelectionRect ||
      old.hasEffectiveBrushMask != hasEffectiveBrushMask ||
      old.isFocus != isFocus ||
      old.contextPadding != contextPadding ||
      old.srcW != srcW ||
      old.srcH != srcH ||
      old.selectionColor != selectionColor;
}
