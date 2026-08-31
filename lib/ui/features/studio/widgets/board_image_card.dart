import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HardwareKeyboard;
import '../../../../data/models/novelai_models.dart';
import '../../../core/theme/app_theme.dart';
import '../view_models/studio_view_model.dart';
import 'board_toolbar.dart';
import 'board_wire_painter.dart';

/// 自由大画布上的图片节点卡片：
/// 顶栏拖拽移动 + 连线端口 + 图片主体圈选批注 + 选区/图钉本地拖拽
///
/// 批注 (圈选/图钉) 仅主图支持；参考图是纯图片卡 (仅拖动/连线/删除)。
class BoardImageCard extends StatefulWidget {
  final StudioViewModel viewModel;
  final CanvasImageNode imageNode;
  final AnnotationToolMode toolMode;
  final bool isPanMode;
  final bool isWireDragging;
  final BoardLiveApi live;

  /// 从顶栏端口拉出连线 (参数为端口在画布坐标系中的锚点)
  final ValueChanged<Offset> onStartWireFromImage;

  /// 拖拽连线过程中指针的全局坐标 (由大画布统一转换为画布坐标)
  final ValueChanged<Offset> onUpdateWire;

  /// 松手结束连线 (由大画布统一做落点命中测试)
  final VoidCallback onEndWire;

  const BoardImageCard({
    super.key,
    required this.viewModel,
    required this.imageNode,
    required this.toolMode,
    required this.isPanMode,
    required this.isWireDragging,
    required this.live,
    required this.onStartWireFromImage,
    required this.onUpdateWire,
    required this.onEndWire,
  });

  @override
  State<BoardImageCard> createState() => _BoardImageCardState();
}

class _BoardImageCardState extends State<BoardImageCard> {
  // 圈选创建中的起止点 (归一化)
  Offset? _creatingStart;
  Offset? _creatingCurrent;

  // 卡片本地拖拽 (结束后才提交到 ViewModel，避免全工作台逐帧重建)
  Offset? _cardDragStart;
  Offset? _liveCardOffset;

  // 卡片本地缩放 (结束后才提交到 ViewModel，连线层经 live 覆盖跟随)
  Size? _liveCardSize;
  Size? _resizeStartSize;
  Offset? _resizeAccumDelta;

  // 选区/图钉本地拖拽
  String? _draggingAnnotationId;
  Rect? _liveRect;
  Offset? _livePoint;

  // 选区四角缩放中正在拖拽的角
  _RectCorner? _resizeCorner;

  // 图片主体 Stack 的全局键 (把指针全局坐标换算为归一化画布坐标)
  final GlobalKey _canvasStackKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final imgNode = widget.imageNode;
    final viewModel = widget.viewModel;
    final annotations = imgNode.annotations;
    final activeId = viewModel.activeAnnotationId;
    final cardPos = _liveCardOffset ?? imgNode.offset;
    final cardSize = _liveCardSize ?? Size(imgNode.width, imgNode.height);
    final isMain = imgNode.isMain;

    return Positioned(
      left: cardPos.dx,
      top: cardPos.dy,
      width: cardSize.width,
      height: cardSize.height + 32,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. 卡片顶部拖拽手柄条 + 连线端口 (仅参考图可拉线)
          GestureDetector(
            onPanStart: (details) {
              _cardDragStart = _liveCardOffset ?? widget.imageNode.offset;
            },
            onPanUpdate: (details) {
              if (_cardDragStart == null) return;
              final next = _cardDragStart! + details.delta;
              _cardDragStart = next;
              setState(() => _liveCardOffset = next);
              widget.live.setNodeOffset(widget.imageNode.id, next);
            },
            onPanEnd: (_) => _commitCardDrag(),
            onPanCancel: _commitCardDrag,
            child: Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: isMain ? AppTheme.notionBlue : const Color(0xFF37352F),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(8),
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 4,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // 连线端口：按住拖出连线到选区/图钉 (仅参考图)
                  if (!isMain) ...[
                    _WireSourcePort(
                      color: AppTheme.notionBlue,
                      onPanStart: () {
                        widget.onStartWireFromImage(
                          cardPos + const Offset(14, 14),
                        );
                      },
                      onPanUpdate: widget.onUpdateWire,
                      onPanEnd: widget.onEndWire,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Icon(
                    isMain ? Icons.star_rounded : Icons.image_outlined,
                    size: 13,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      isMain
                          ? '主图 (当前生成图)'
                          : '参考图 (${imgNode.image.params.width}x${imgNode.image.params.height})',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  if (!isMain)
                    Tooltip(
                      message: '移除参考图卡片',
                      child: GestureDetector(
                        onTap: () => viewModel.removeImageNode(imgNode.id),
                        child: const Icon(
                          Icons.close_rounded,
                          size: 14,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // 2. 图片主体与圈选交互层 (批注仅主图支持，参考图为纯图片)
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(8),
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final canvasSize = constraints.biggest;

                  return Stack(
                    key: _canvasStackKey,
                    fit: StackFit.expand,
                    clipBehavior: Clip.none,
                    children: [
                      Image.memory(
                        imgNode.image.uint8Bytes,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      ),

                      // 绘制选区/锚点手势 (漫游模式与连线拖拽时让位)
                      if (isMain && !widget.isPanMode && !widget.isWireDragging)
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onPanStart: (details) {
                              if (widget.toolMode != AnnotationToolMode.rect) {
                                return;
                              }
                              final norm = _normalize(
                                details.localPosition,
                                canvasSize,
                              );
                              setState(() {
                                _creatingStart = norm;
                                _creatingCurrent = norm;
                              });
                            },
                            onPanUpdate: (details) {
                              if (_creatingStart == null) return;
                              setState(() {
                                _creatingCurrent = _normalize(
                                  details.localPosition,
                                  canvasSize,
                                );
                              });
                            },
                            onPanEnd: (_) {
                              if (_creatingStart != null &&
                                  _creatingCurrent != null) {
                                final rect = Rect.fromPoints(
                                  _creatingStart!,
                                  _creatingCurrent!,
                                );
                                final pxW = rect.width * canvasSize.width;
                                final pxH = rect.height * canvasSize.height;

                                if (pxW >= 10.0 && pxH >= 10.0) {
                                  final nextIdx = annotations.length;
                                  final newAnn = ImageAnnotation.rect(
                                    normalizedRect: rect,
                                    colorIndex:
                                        nextIdx % kAnnotationPalette.length,
                                  );
                                  viewModel.addAnnotationToImageNode(
                                    imgNode.id,
                                    newAnn,
                                  );
                                }
                              }
                              setState(() {
                                _creatingStart = null;
                                _creatingCurrent = null;
                              });
                            },
                            onTapUp: (details) {
                              if (widget.toolMode != AnnotationToolMode.point) {
                                return;
                              }
                              final norm = _normalize(
                                details.localPosition,
                                canvasSize,
                              );
                              final nextIdx = annotations.length;
                              final newAnn = ImageAnnotation.point(
                                normalizedPoint: norm,
                                colorIndex: nextIdx % kAnnotationPalette.length,
                              );
                              viewModel.addAnnotationToImageNode(
                                imgNode.id,
                                newAnn,
                              );
                            },
                          ),
                        ),

                      if (isMain &&
                          _creatingStart != null &&
                          _creatingCurrent != null)
                        _buildCreatingRectPreview(canvasSize),

                      // 已有批注图钉与选区 (仅主图)
                      if (isMain)
                        for (var i = 0; i < annotations.length; i++)
                          _buildAnnotationElement(
                            annotations[i],
                            i,
                            canvasSize,
                            isActive: annotations[i].id == activeId,
                          ),

                      // 右下角卡片缩放手柄 (漫游/连线拖拽时让位)
                      if (!widget.isPanMode && !widget.isWireDragging)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: BoardCardResizeHandle(
                            tooltip: '拖拽调节图片卡片大小 (按住 Shift 锁定宽高比)',
                            color: isMain
                                ? AppTheme.notionBlue
                                : const Color(0xFF37352F),
                            onPanStart: () {
                              _resizeStartSize =
                                  _liveCardSize ??
                                  Size(imgNode.width, imgNode.height);
                              _resizeAccumDelta = Offset.zero;
                            },
                            onPanUpdate: (delta) {
                              _updateCardResize(delta);
                            },
                            onPanEnd: _commitCardResize,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 卡片拖拽结束：一次性提交到 ViewModel 并清空本地实时位置
  void _commitCardDrag() {
    _cardDragStart = null;
    final finalPos = _liveCardOffset;
    if (finalPos != null) {
      widget.viewModel.moveImageNode(widget.imageNode.id, finalPos);
    }
    setState(() => _liveCardOffset = null);
    widget.live.clearNodeOffset(widget.imageNode.id);
  }

  // ------------------------- 卡片缩放 -------------------------

  /// 卡片本地缩放：累积指针增量计算新尺寸 (Shift 锁定宽高比)
  void _updateCardResize(Offset delta) {
    final start =
        _resizeStartSize ??
        Size(widget.imageNode.width, widget.imageNode.height);
    final accum = (_resizeAccumDelta ?? Offset.zero) + delta;
    _resizeAccumDelta = accum;

    var newW = (start.width + accum.dx).clamp(
      kBoardImageCardMinWidth,
      kBoardCardMaxSize,
    );
    var newH = (start.height + accum.dy).clamp(
      kBoardImageCardMinHeight,
      kBoardCardMaxSize,
    );

    if (HardwareKeyboard.instance.isShiftPressed) {
      final aspect = start.width / start.height;
      newH = (newW / aspect).clamp(kBoardImageCardMinHeight, kBoardCardMaxSize);
    }

    final next = Size(newW, newH);
    setState(() => _liveCardSize = next);
    widget.live.setNodeSize(widget.imageNode.id, next);
  }

  /// 卡片缩放结束：一次性提交到 ViewModel 并清空本地实时尺寸
  void _commitCardResize() {
    _resizeStartSize = null;
    _resizeAccumDelta = null;
    final finalSize = _liveCardSize;
    if (finalSize != null) {
      widget.viewModel.resizeImageNode(
        widget.imageNode.id,
        finalSize.width,
        finalSize.height,
      );
    }
    setState(() => _liveCardSize = null);
    widget.live.clearNodeSize(widget.imageNode.id);
  }

  /// 画布内坐标归一化到 0.0 ~ 1.0
  Offset _normalize(Offset local, Size canvasSize) {
    return Offset(
      (local.dx / canvasSize.width).clamp(0.0, 1.0),
      (local.dy / canvasSize.height).clamp(0.0, 1.0),
    );
  }

  Widget _buildCreatingRectPreview(Size canvasSize) {
    final rect = Rect.fromPoints(_creatingStart!, _creatingCurrent!);
    return Positioned(
      left: rect.left * canvasSize.width,
      top: rect.top * canvasSize.height,
      width: rect.width * canvasSize.width,
      height: rect.height * canvasSize.height,
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.notionBlue.withValues(alpha: 0.22),
            border: Border.all(color: AppTheme.notionBlue, width: 2.0),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }

  Widget _buildAnnotationElement(
    ImageAnnotation ann,
    int index,
    Size canvasSize, {
    required bool isActive,
  }) {
    final color = ann.color;
    final isDragging = _draggingAnnotationId == ann.id;
    final imgNode = widget.imageNode;

    if (ann.type == AnnotationType.rect && ann.rect != null) {
      final r = (isDragging && _liveRect != null) ? _liveRect! : ann.rect!;
      final left = r.left * canvasSize.width;
      final top = r.top * canvasSize.height;
      final width = r.width * canvasSize.width;
      final height = r.height * canvasSize.height;

      return Positioned(
        left: left,
        top: top,
        width: width,
        height: height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // 选框本体：点击选中 + 拖拽移动选区
            GestureDetector(
              onTap: () => widget.viewModel.selectAnnotationId(ann.id),
              onPanStart: (details) {
                widget.viewModel.selectAnnotationId(ann.id);
                setState(() {
                  _draggingAnnotationId = ann.id;
                  _liveRect = ann.rect;
                });
              },
              onPanUpdate: (details) {
                final cur = _liveRect ?? ann.rect!;
                final deltaX = details.delta.dx / canvasSize.width;
                final deltaY = details.delta.dy / canvasSize.height;
                final newL = (cur.left + deltaX).clamp(0.0, 1.0 - cur.width);
                final newT = (cur.top + deltaY).clamp(0.0, 1.0 - cur.height);
                final next = Rect.fromLTWH(newL, newT, cur.width, cur.height);
                setState(() => _liveRect = next);
                widget.live.setAnnotationRect(ann.id, next);
              },
              onPanEnd: (_) => _finishAnnotationDrag(ann, rect: _liveRect),
              onPanCancel: () => _finishAnnotationDrag(ann, rect: _liveRect),
              child: Container(
                decoration: BoxDecoration(
                  color: color.withValues(alpha: isActive ? 0.25 : 0.12),
                  border: Border.all(color: color, width: isActive ? 2.5 : 1.8),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),

            // 左上角编号图钉 (仅点击选中，不提供拉线)
            Positioned(
              left: -11,
              top: -11,
              child: _PinPortBadge(
                number: index + 1,
                color: color,
                isActive: isActive,
                onTap: () => widget.viewModel.selectAnnotationId(ann.id),
              ),
            ),

            // 选中态选区右上角删除按钮 (在选区命中盒内，保证可点)
            if (isActive)
              Positioned(
                right: 4,
                top: 4,
                child: _AnnotationDeleteChip(
                  tooltip: '删除选区',
                  onDelete: () => widget.viewModel
                      .removeAnnotationFromImageNode(imgNode.id, ann.id),
                ),
              ),

            // 选中态四角缩放手柄 (拖拽调节选区大小，命中盒压在选区角上)
            if (isActive && !widget.isPanMode && !widget.isWireDragging)
              ..._RectCorner.values.map(
                (corner) => _buildRectResizeHandle(ann, corner),
              ),
          ],
        ),
      );
    }

    if (ann.type == AnnotationType.point && ann.point != null) {
      final p = (isDragging && _livePoint != null) ? _livePoint! : ann.point!;
      final cx = p.dx * canvasSize.width;
      final cy = p.dy * canvasSize.height;

      // 命中盒固定 60x26：图钉在左，选中时删除按钮在右侧 (悬出选区外
      // 的部分无法命中测试，必须包在同一 Positioned 盒内)
      return Positioned(
        left: cx - 12,
        top: cy - 13,
        width: 60,
        height: 26,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              top: 0,
              child: GestureDetector(
                onPanStart: (_) {
                  widget.viewModel.selectAnnotationId(ann.id);
                  setState(() {
                    _draggingAnnotationId = ann.id;
                    _livePoint = ann.point;
                  });
                },
                onPanUpdate: (details) {
                  final cur = _livePoint ?? ann.point!;
                  final newX = (cur.dx + details.delta.dx / canvasSize.width)
                      .clamp(0.0, 1.0);
                  final newY = (cur.dy + details.delta.dy / canvasSize.height)
                      .clamp(0.0, 1.0);
                  final next = Offset(newX, newY);
                  setState(() => _livePoint = next);
                  widget.live.setAnnotationPoint(ann.id, next);
                },
                onPanEnd: (_) => _finishAnnotationDrag(ann, point: _livePoint),
                onPanCancel: () =>
                    _finishAnnotationDrag(ann, point: _livePoint),
                child: _PinPortBadge(
                  number: index + 1,
                  color: color,
                  isActive: isActive,
                  onTap: () => widget.viewModel.selectAnnotationId(ann.id),
                ),
              ),
            ),

            // 选中态图钉右侧删除按钮
            if (isActive)
              Positioned(
                left: 30,
                top: 4,
                child: _AnnotationDeleteChip(
                  tooltip: '删除锚点',
                  onDelete: () =>
                      widget.viewModel.removeAnnotationFromImageNode(
                        widget.imageNode.id,
                        ann.id,
                      ),
                ),
              ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  /// 选区/图钉拖拽结束：先清本地实时状态再提交，同一帧内完成位置切换不闪回
  void _finishAnnotationDrag(ImageAnnotation ann, {Rect? rect, Offset? point}) {
    final changed =
        (rect != null && rect != ann.rect) ||
        (point != null && point != ann.point);

    setState(() {
      _draggingAnnotationId = null;
      _liveRect = null;
      _livePoint = null;
      _resizeCorner = null;
    });
    widget.live.clearAnnotation(ann.id);

    if (changed) {
      widget.viewModel.updateAnnotationInImageNode(
        widget.imageNode.id,
        ann.copyWith(rect: rect, point: point),
      );
    }
  }

  // ------------------------- 选区四角缩放 -------------------------

  /// 构建选区某个角的缩放手柄 (16x16 命中盒压在选区角上，外侧悬出部分不可点)
  Widget _buildRectResizeHandle(ImageAnnotation ann, _RectCorner corner) {
    final color = ann.color;
    const handleSize = 16.0;
    final positioned = switch (corner) {
      _RectCorner.topLeft => (Widget child) => Positioned(
        left: -handleSize / 2,
        top: -handleSize / 2,
        child: child,
      ),
      _RectCorner.topRight => (Widget child) => Positioned(
        right: -handleSize / 2,
        top: -handleSize / 2,
        child: child,
      ),
      _RectCorner.bottomLeft => (Widget child) => Positioned(
        left: -handleSize / 2,
        bottom: -handleSize / 2,
        child: child,
      ),
      _RectCorner.bottomRight => (Widget child) => Positioned(
        right: -handleSize / 2,
        bottom: -handleSize / 2,
        child: child,
      ),
    };

    return positioned(
      GestureDetector(
        onPanStart: (_) {
          widget.viewModel.selectAnnotationId(ann.id);
          setState(() {
            _draggingAnnotationId = ann.id;
            _liveRect = ann.rect;
            _resizeCorner = corner;
          });
        },
        onPanUpdate: (details) =>
            _updateRectResize(ann, details.globalPosition),
        onPanEnd: (_) => _finishAnnotationDrag(ann, rect: _liveRect),
        onPanCancel: () => _finishAnnotationDrag(ann, rect: _liveRect),
        child: Tooltip(
          message: '拖拽调节选区大小',
          child: MouseRegion(
            cursor:
                corner == _RectCorner.topLeft ||
                    corner == _RectCorner.bottomRight
                ? SystemMouseCursors.resizeUpLeftDownRight
                : SystemMouseCursors.resizeUpRightDownLeft,
            child: Container(
              width: handleSize,
              height: handleSize,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 2.2),
                boxShadow: const [
                  BoxShadow(color: Colors.black38, blurRadius: 3),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 选区缩放中：把指针全局坐标换算成归一化坐标后重算选区
  void _updateRectResize(ImageAnnotation ann, Offset globalPos) {
    final ro = _canvasStackKey.currentContext?.findRenderObject();
    if (ro is! RenderBox || !ro.attached || !ro.hasSize) return;
    final cur = _liveRect ?? ann.rect;
    final corner = _resizeCorner;
    if (cur == null || corner == null) return;

    final pointerNorm = _normalize(ro.globalToLocal(globalPos), ro.size);
    final next = _resizeRectFromCorner(cur, corner, pointerNorm, ro.size);
    setState(() => _liveRect = next);
    widget.live.setAnnotationRect(ann.id, next);
  }

  /// 按拖拽的角重算归一化选区 (对角固定，最小尺寸 12px，夹在 0~1)
  Rect _resizeRectFromCorner(
    Rect cur,
    _RectCorner corner,
    Offset pointer,
    Size canvasSize,
  ) {
    final minW = (12.0 / canvasSize.width).clamp(0.004, 1.0);
    final minH = (12.0 / canvasSize.height).clamp(0.004, 1.0);

    double l = cur.left, t = cur.top, r = cur.right, b = cur.bottom;
    final dx = pointer.dx.clamp(0.0, 1.0);
    final dy = pointer.dy.clamp(0.0, 1.0);

    switch (corner) {
      case _RectCorner.topLeft:
        l = dx;
        t = dy;
      case _RectCorner.topRight:
        r = dx;
        t = dy;
      case _RectCorner.bottomLeft:
        l = dx;
        b = dy;
      case _RectCorner.bottomRight:
        r = dx;
        b = dy;
    }

    // 最小尺寸：往被拖拽的角方向收缩固定对角，避免翻转成负宽高
    if (r - l < minW) {
      if (corner == _RectCorner.topLeft || corner == _RectCorner.bottomLeft) {
        l = r - minW;
      } else {
        r = l + minW;
      }
    }
    if (b - t < minH) {
      if (corner == _RectCorner.topLeft || corner == _RectCorner.topRight) {
        t = b - minH;
      } else {
        b = t + minH;
      }
    }

    l = l.clamp(0.0, 1.0);
    t = t.clamp(0.0, 1.0);
    r = r.clamp(l, 1.0);
    b = b.clamp(t, 1.0);
    return Rect.fromLTRB(l, t, r, b);
  }
}

/// 选区缩放手柄所在的角
enum _RectCorner { topLeft, topRight, bottomLeft, bottomRight }

/// 编号图钉 (仅点击选中；连线只能从便利贴与参考图端口拉出，落点为选区/图钉)
class _PinPortBadge extends StatelessWidget {
  final int number;
  final Color color;
  final bool isActive;
  final VoidCallback onTap;

  const _PinPortBadge({
    required this.number,
    required this.color,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '点击选中该批注',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: isActive ? 26 : 22,
          height: isActive ? 26 : 22,
          decoration: BoxDecoration(
            color: isActive ? Colors.white : color,
            shape: BoxShape.circle,
            border: Border.all(
              color: isActive ? color : Colors.white,
              width: isActive ? 2.5 : 1.8,
            ),
            boxShadow: const [
              BoxShadow(
                color: Colors.black38,
                blurRadius: 4,
                offset: Offset(0, 1),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            '$number',
            style: TextStyle(
              fontSize: isActive ? 12 : 10.5,
              fontWeight: FontWeight.w800,
              color: isActive ? color : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

/// 选中态批注的删除按钮 (选区右上角 / 锚点右侧，也可按 Delete 键)
class _AnnotationDeleteChip extends StatelessWidget {
  final String tooltip;
  final VoidCallback onDelete;

  const _AnnotationDeleteChip({required this.tooltip, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onDelete,
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: AppTheme.error, width: 1.5),
            boxShadow: const [
              BoxShadow(
                color: Colors.black38,
                blurRadius: 4,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: const Icon(
            Icons.close_rounded,
            size: 12,
            color: AppTheme.error,
          ),
        ),
      ),
    );
  }
}

/// ComfyUI 风格连线端口小圆点 (参考图卡片顶栏，按住拖出连线)
class _WireSourcePort extends StatelessWidget {
  final Color color;
  final VoidCallback onPanStart;
  final ValueChanged<Offset> onPanUpdate;
  final VoidCallback onPanEnd;

  const _WireSourcePort({
    required this.color,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '按住拖出连线到选区/图钉',
      child: GestureDetector(
        onPanStart: (_) => onPanStart(),
        onPanUpdate: (details) => onPanUpdate(details.globalPosition),
        onPanEnd: (_) => onPanEnd(),
        onPanCancel: onPanEnd,
        child: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2.5),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3)],
          ),
        ),
      ),
    );
  }
}
