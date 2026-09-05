import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../../../data/models/novelai_models.dart';

/// 图片卡片顶栏高度 (与 BoardImageCard 顶栏保持一致)
const double kBoardCardHeaderHeight = 28.0;

/// 连线拖拽状态 (ComfyUI 风格端口拖拽连线，拖拽期间由 ValueNotifier 持有)
class BoardWireDragState {
  final String? noteId;
  final String? imageId;
  final Offset startBoardPos;
  final Offset currentBoardPos;

  BoardWireDragState({
    this.noteId,
    this.imageId,
    required this.startBoardPos,
    Offset? currentBoardPos,
  }) : currentBoardPos = currentBoardPos ?? startBoardPos;

  bool get isFromNote => noteId != null;

  BoardWireDragState withCurrent(Offset pos) => BoardWireDragState(
    noteId: noteId,
    imageId: imageId,
    startBoardPos: startBoardPos,
    currentBoardPos: pos,
  );
}

/// 本地拖拽实时覆盖层：
/// 卡片/选区拖拽期间只更新这里 (ValueNotifier 驱动连线层重绘)，
/// 拖拽结束才提交到 ViewModel，避免每个像素增量都触发全工作台重建。
class BoardLiveOverrides {
  final Map<String, Offset> nodeOffsets;
  final Map<String, Rect> annotationRects;
  final Map<String, Offset> annotationPoints;

  /// 卡片实时尺寸 (图片卡与便签卡共用，拖拽缩放期间驱动连线跟随)
  final Map<String, Size> nodeSizes;

  const BoardLiveOverrides({
    this.nodeOffsets = const {},
    this.annotationRects = const {},
    this.annotationPoints = const {},
    this.nodeSizes = const {},
  });

  static const BoardLiveOverrides empty = BoardLiveOverrides();

  Offset? nodeOffset(String nodeId) => nodeOffsets[nodeId];
  Rect? annotationRect(String annotationId) => annotationRects[annotationId];
  Offset? annotationPoint(String annotationId) =>
      annotationPoints[annotationId];
  Size? nodeSize(String nodeId) => nodeSizes[nodeId];
}

/// 卡片写入实时覆盖层的简易外观 (BoardImageCard / BoardNoteCard 共用)
class BoardLiveApi {
  BoardLiveApi(this.overlays);

  final ValueNotifier<BoardLiveOverrides> overlays;

  void setNodeOffset(String nodeId, Offset offset) {
    final cur = overlays.value;
    overlays.value = BoardLiveOverrides(
      nodeOffsets: {...cur.nodeOffsets, nodeId: offset},
      annotationRects: cur.annotationRects,
      annotationPoints: cur.annotationPoints,
      nodeSizes: cur.nodeSizes,
    );
  }

  void clearNodeOffset(String nodeId) {
    final cur = overlays.value;
    if (!cur.nodeOffsets.containsKey(nodeId)) return;
    overlays.value = BoardLiveOverrides(
      nodeOffsets: {...cur.nodeOffsets}..remove(nodeId),
      annotationRects: cur.annotationRects,
      annotationPoints: cur.annotationPoints,
      nodeSizes: cur.nodeSizes,
    );
  }

  void setNodeSize(String nodeId, Size size) {
    final cur = overlays.value;
    overlays.value = BoardLiveOverrides(
      nodeOffsets: cur.nodeOffsets,
      annotationRects: cur.annotationRects,
      annotationPoints: cur.annotationPoints,
      nodeSizes: {...cur.nodeSizes, nodeId: size},
    );
  }

  void clearNodeSize(String nodeId) {
    final cur = overlays.value;
    if (!cur.nodeSizes.containsKey(nodeId)) return;
    overlays.value = BoardLiveOverrides(
      nodeOffsets: cur.nodeOffsets,
      annotationRects: cur.annotationRects,
      annotationPoints: cur.annotationPoints,
      nodeSizes: {...cur.nodeSizes}..remove(nodeId),
    );
  }

  void setAnnotationRect(String annotationId, Rect rect) {
    final cur = overlays.value;
    overlays.value = BoardLiveOverrides(
      nodeOffsets: cur.nodeOffsets,
      annotationRects: {...cur.annotationRects, annotationId: rect},
      annotationPoints: cur.annotationPoints,
      nodeSizes: cur.nodeSizes,
    );
  }

  void setAnnotationPoint(String annotationId, Offset point) {
    final cur = overlays.value;
    overlays.value = BoardLiveOverrides(
      nodeOffsets: cur.nodeOffsets,
      annotationRects: cur.annotationRects,
      annotationPoints: {...cur.annotationPoints, annotationId: point},
      nodeSizes: cur.nodeSizes,
    );
  }

  void clearAnnotation(String annotationId) {
    final cur = overlays.value;
    if (!cur.annotationRects.containsKey(annotationId) &&
        !cur.annotationPoints.containsKey(annotationId)) {
      return;
    }
    overlays.value = BoardLiveOverrides(
      nodeOffsets: cur.nodeOffsets,
      annotationRects: {...cur.annotationRects}..remove(annotationId),
      annotationPoints: {...cur.annotationPoints}..remove(annotationId),
      nodeSizes: cur.nodeSizes,
    );
  }
}

/// 卡片右下角缩放手柄 (图片卡与便签卡共用，拖拽调节宽高)
class BoardCardResizeHandle extends StatelessWidget {
  final String tooltip;
  final Color color;
  final VoidCallback onPanStart;
  final ValueChanged<Offset> onPanUpdate;
  final VoidCallback onPanEnd;

  const BoardCardResizeHandle({
    super.key,
    required this.tooltip,
    required this.color,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onPanStart: (_) => onPanStart(),
        onPanUpdate: (details) => onPanUpdate(details.delta),
        onPanEnd: (_) => onPanEnd(),
        onPanCancel: onPanEnd,
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeDownRight,
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.only(
                bottomRight: Radius.circular(6),
              ),
              border: Border.all(color: color, width: 1.8),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 3),
              ],
            ),
            child: Icon(
              Icons.signal_cellular_alt_rounded,
              size: 10,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

/// 批注锚点在画布坐标系中的中心位置 (选框中心 / 图钉位置)
Offset boardAnnotationAnchor(
  CanvasImageNode imgNode,
  ImageAnnotation ann, {
  BoardLiveOverrides? live,
}) {
  final base = live?.nodeOffset(imgNode.id) ?? imgNode.offset;
  final size =
      live?.nodeSize(imgNode.id) ?? Size(imgNode.width, imgNode.height);
  if (ann.type == AnnotationType.rect) {
    final r = live?.annotationRect(ann.id) ?? ann.rect;
    if (r != null) {
      return Offset(
        base.dx + (r.left + r.width / 2) * size.width,
        base.dy + kBoardCardHeaderHeight + (r.top + r.height / 2) * size.height,
      );
    }
  } else if (ann.type == AnnotationType.point) {
    final p = live?.annotationPoint(ann.id) ?? ann.point;
    if (p != null) {
      return Offset(
        base.dx + p.dx * size.width,
        base.dy + kBoardCardHeaderHeight + p.dy * size.height,
      );
    }
  }
  return Offset(
    base.dx + size.width / 2,
    base.dy + kBoardCardHeaderHeight + size.height / 2,
  );
}

/// 批注选框在画布坐标系中的包围盒 (用于连线落点命中测试)
Rect? boardAnnotationRectBounds(
  CanvasImageNode imgNode,
  ImageAnnotation ann, {
  BoardLiveOverrides? live,
}) {
  if (ann.type != AnnotationType.rect) return null;
  final base = live?.nodeOffset(imgNode.id) ?? imgNode.offset;
  final size =
      live?.nodeSize(imgNode.id) ?? Size(imgNode.width, imgNode.height);
  final r = live?.annotationRect(ann.id) ?? ann.rect;
  if (r == null) return null;
  return Rect.fromLTWH(
    base.dx + r.left * size.width,
    base.dy + kBoardCardHeaderHeight + r.top * size.height,
    r.width * size.width,
    r.height * size.height,
  );
}

/// 参考图连线颜色 (Notion 绿，与便签连线区分)
const Color kImageLinkColor = Color(0xFF448361);

/// 图钉徽章半径 (连线端点回缩量，避免遮挡编号数字)
const double kPinBadgeRadius = 15.0;

/// 把连线端点从图钉中心回缩到徽章边缘，避免遮挡锚点编号数字
Offset retractFromPinBadge(Offset target, Offset from) {
  final delta = target - from;
  final dist = delta.distance;
  if (dist <= kPinBadgeRadius * 2) return target;
  return target - delta / dist * kPinBadgeRadius;
}

/// 背景网格点阵绘制器 (绘制在所有卡片之下)
class BoardGridPainter extends CustomPainter {
  /// 网格点颜色 (由当前主题注入，主题切换时参与重绘判定)
  final Color dotColor;

  const BoardGridPainter({required this.dotColor});

  @override
  void paint(Canvas canvas, Size size) {
    // 只画当前视口范围内的网格点，保证性能
    final clip = canvas.getLocalClipBounds();
    final left = clip.left.clamp(0.0, size.width);
    final right = clip.right.clamp(0.0, size.width);
    final top = clip.top.clamp(0.0, size.height);
    final bottom = clip.bottom.clamp(0.0, size.height);

    if (right <= left || bottom <= top) return;

    final dotPaint = Paint()
      ..color = dotColor
      ..strokeWidth = 1.8;

    const step = 36.0;
    final startX = (left / step).floor() * step;
    final endX = (right / step).ceil() * step;
    final startY = (top / step).floor() * step;
    final endY = (bottom / step).ceil() * step;

    final points = <Offset>[];
    for (double x = startX; x <= endX; x += step) {
      for (double y = startY; y <= endY; y += step) {
        points.add(Offset(x, y));
      }
    }
    if (points.isNotEmpty) {
      canvas.drawPoints(ui.PointMode.points, points, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant BoardGridPainter oldDelegate) =>
      oldDelegate.dotColor != dotColor;
}

/// 前景连线绘制器 (绘制在所有卡片之上，连线不会被图片遮挡)
///
/// 连线只允许两个来源：便利贴左侧端口、图片卡片顶栏端口；
/// 落点目标为图片上的选区与图钉锚点。
class BoardWirePainter extends CustomPainter {
  final CanvasBoardData boardData;
  final ValueNotifier<BoardLiveOverrides> liveOverlays;
  final ValueNotifier<BoardWireDragState?> wireDrag;

  /// 拖拽中即时连线的主题强调色 (由当前主题注入)
  final Color dragColor;

  BoardWirePainter({
    required this.boardData,
    required this.liveOverlays,
    required this.wireDrag,
    required this.dragColor,
  }) : super(repaint: Listenable.merge([liveOverlays, wireDrag]));

  @override
  void paint(Canvas canvas, Size size) {
    final live = liveOverlays.value;
    final drag = wireDrag.value;

    // 1. 参考图连线 (虚线，一个选区/锚点可挂多条)
    for (final link in boardData.imageLinks) {
      final srcNode = boardData.imageNodes
          .where((img) => img.id == link.sourceImageId)
          .firstOrNull;
      final tgtNode = boardData.imageNodes
          .where((img) => img.id == link.targetImageId)
          .firstOrNull;
      if (srcNode == null || tgtNode == null) continue;

      final ann = tgtNode.annotations
          .where((a) => a.id == link.targetAnnotationId)
          .firstOrNull;
      if (ann == null) continue;

      final srcPos = live.nodeOffset(srcNode.id) ?? srcNode.offset;
      final start = srcPos + const Offset(14, 14);
      final anchor = boardAnnotationAnchor(tgtNode, ann, live: live);
      final end = ann.type == AnnotationType.point
          ? retractFromPinBadge(anchor, start)
          : anchor;

      _drawDashedCable(canvas, start, end, kImageLinkColor);
    }

    // 2. 绘制既有便利贴与图片选区的贝塞尔连接线
    for (final note in boardData.noteNodes) {
      if (!note.isConnected) continue;

      // 便签正在被拖出重连时隐藏旧连线，提供"已拔出"视觉反馈
      if (drag?.noteId == note.id) continue;

      final imgNode = boardData.imageNodes
          .where((img) => img.id == note.targetImageId)
          .firstOrNull;
      if (imgNode == null) continue;

      final ann = imgNode.annotations
          .where((a) => a.id == note.targetAnnotationId)
          .firstOrNull;
      if (ann == null) continue;

      final targetAnchor = boardAnnotationAnchor(imgNode, ann, live: live);
      final notePos = live.nodeOffset(note.id) ?? note.offset;
      final noteSize = live.nodeSize(note.id) ?? Size(note.width, note.height);
      final isNoteOnRight = notePos.dx >= targetAnchor.dx;
      final noteAnchor = Offset(
        isNoteOnRight ? notePos.dx : notePos.dx + noteSize.width,
        notePos.dy + 14,
      );
      // 图钉锚点：端点回缩到徽章边缘，避免遮挡编号数字
      final targetOffset = ann.type == AnnotationType.point
          ? retractFromPinBadge(targetAnchor, noteAnchor)
          : targetAnchor;

      _drawBezierCable(canvas, noteAnchor, targetOffset, note.color);
    }

    // 3. 绘制正在拖拽拉出的即时动态连线 (ComfyUI 风格)
    if (drag != null) {
      _drawBezierCable(
        canvas,
        drag.startBoardPos,
        drag.currentBoardPos,
        dragColor,
        isDynamicDragging: true,
      );
    }
  }

  /// 虚线连线绘制 (参考图连线，直线 + 虚线 + 端点小圆点)
  void _drawDashedCable(Canvas canvas, Offset start, Offset end, Color color) {
    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..lineTo(end.dx, end.dy);

    final linePaint = Paint()
      ..color = color.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    // 逐段提取路径绘制虚线 (8px 实线 + 6px 间隔)
    for (final metric in path.computeMetrics()) {
      var dist = 0.0;
      var draw = true;
      while (dist < metric.length) {
        final next = (dist + (draw ? 8.0 : 6.0)).clamp(0.0, metric.length);
        if (draw) {
          final segment = metric.extractPath(dist, next);
          canvas.drawPath(segment, linePaint);
        }
        dist = next;
        draw = !draw;
      }
    }

    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(start, 3.5, dotPaint);
    canvas.drawCircle(end, 4.0, dotPaint);
  }

  void _drawBezierCable(
    Canvas canvas,
    Offset start,
    Offset end,
    Color color, {
    bool isDynamicDragging = false,
  }) {
    final path = Path();
    path.moveTo(start.dx, start.dy);

    final dx = (start.dx - end.dx).abs();
    final controlDist = dx * 0.5 + 40.0;

    final isStartOnRight = start.dx >= end.dx;
    final cp1 = Offset(
      isStartOnRight ? start.dx - controlDist : start.dx + controlDist,
      start.dy,
    );
    final cp2 = Offset(
      isStartOnRight ? end.dx + controlDist : end.dx - controlDist,
      end.dy,
    );

    path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, end.dx, end.dy);

    // 外发光层
    if (isDynamicDragging) {
      final glowPaint = Paint()
        ..color = color.withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6.0;
      canvas.drawPath(path, glowPaint);
    }

    // 主连线
    final linePaint = Paint()
      ..color = color.withValues(alpha: isDynamicDragging ? 0.95 : 0.80)
      ..style = PaintingStyle.stroke
      ..strokeWidth = isDynamicDragging ? 2.8 : 2.2;

    canvas.drawPath(path, linePaint);

    // 端点实心圆点
    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(start, isDynamicDragging ? 5.0 : 4.0, dotPaint);
    canvas.drawCircle(end, isDynamicDragging ? 6.0 : 4.5, dotPaint);
  }

  @override
  bool shouldRepaint(covariant BoardWirePainter oldDelegate) => true;
}
