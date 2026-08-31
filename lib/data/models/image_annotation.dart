import 'dart:ui';

/// 批注区域类型
enum AnnotationType {
  /// 局部矩形选区 (Bounding Box)
  rect('rect', '选区'),

  /// 局部图钉锚点 (Point Pin)
  point('point', '锚点'),

  /// 整图全局批注 (Global Image Note)
  global('global', '整图');

  final String id;
  final String label;
  const AnnotationType(this.id, this.label);

  static AnnotationType fromId(String? id) {
    for (final type in AnnotationType.values) {
      if (type.id == id) return type;
    }
    return AnnotationType.rect;
  }
}

/// Notion 风格预设色彩调色板 (蓝、紫、粉、琥珀、翠绿、石板灰)
const List<Color> kAnnotationPalette = [
  Color(0xFF2383E2), // Notion Blue
  Color(0xFF9065B0), // Notion Purple
  Color(0xFFC14C8A), // Notion Pink
  Color(0xFFD9730D), // Notion Amber
  Color(0xFF0F7B6C), // Notion Green
  Color(0xFF787774), // Notion Gray
];

/// 单条图片批注模型
class ImageAnnotation {
  final String id;
  final AnnotationType type;

  /// 归一化矩形区域 (0.0 ~ 1.0)，仅当 type == AnnotationType.rect 时有效
  final Rect? rect;

  /// 归一化锚点坐标 (0.0 ~ 1.0)，仅当 type == AnnotationType.point 时有效
  final Offset? point;

  /// 批注文字内容
  final String note;

  /// 创建时间
  final DateTime createdAt;

  /// 调色板颜色索引 (0 ~ 5)
  final int colorIndex;

  const ImageAnnotation({
    required this.id,
    required this.type,
    this.rect,
    this.point,
    required this.note,
    required this.createdAt,
    this.colorIndex = 0,
  });

  /// 工厂构造：创建矩形选区批注
  factory ImageAnnotation.rect({
    String? id,
    required Rect normalizedRect,
    String note = '',
    int colorIndex = 0,
    DateTime? createdAt,
  }) {
    // 归一化并确保宽高非负
    final l = normalizedRect.left.clamp(0.0, 1.0);
    final t = normalizedRect.top.clamp(0.0, 1.0);
    final r = normalizedRect.right.clamp(0.0, 1.0);
    final b = normalizedRect.bottom.clamp(0.0, 1.0);
    final minX = l < r ? l : r;
    final maxX = l < r ? r : l;
    final minY = t < b ? t : b;
    final maxY = t < b ? b : t;

    return ImageAnnotation(
      id: id ?? 'ann_${DateTime.now().millisecondsSinceEpoch}',
      type: AnnotationType.rect,
      rect: Rect.fromLTRB(minX, minY, maxX, maxY),
      note: note,
      createdAt: createdAt ?? DateTime.now(),
      colorIndex: colorIndex % kAnnotationPalette.length,
    );
  }

  /// 工厂构造：创建图钉锚点批注
  factory ImageAnnotation.point({
    String? id,
    required Offset normalizedPoint,
    String note = '',
    int colorIndex = 0,
    DateTime? createdAt,
  }) {
    return ImageAnnotation(
      id: id ?? 'ann_${DateTime.now().millisecondsSinceEpoch}',
      type: AnnotationType.point,
      point: Offset(
        normalizedPoint.dx.clamp(0.0, 1.0),
        normalizedPoint.dy.clamp(0.0, 1.0),
      ),
      note: note,
      createdAt: createdAt ?? DateTime.now(),
      colorIndex: colorIndex % kAnnotationPalette.length,
    );
  }

  /// 工厂构造：创建整图全局批注
  factory ImageAnnotation.global({
    String? id,
    String note = '',
    int colorIndex = 0,
    DateTime? createdAt,
  }) {
    return ImageAnnotation(
      id: id ?? 'ann_${DateTime.now().millisecondsSinceEpoch}',
      type: AnnotationType.global,
      note: note,
      createdAt: createdAt ?? DateTime.now(),
      colorIndex: colorIndex % kAnnotationPalette.length,
    );
  }

  /// 获取该批注的主题色
  Color get color =>
      kAnnotationPalette[colorIndex.clamp(0, kAnnotationPalette.length - 1)];

  /// 归一化中心锚点位置 (用于绘制虚线弯曲引线)
  Offset get centerNormalized {
    switch (type) {
      case AnnotationType.rect:
        return rect?.center ?? const Offset(0.5, 0.5);
      case AnnotationType.point:
        return point ?? const Offset(0.5, 0.5);
      case AnnotationType.global:
        return const Offset(0.5, 0.5);
    }
  }

  /// 将归一化选区转换为对应图像真实像素的绝对 Rect
  Rect? toPixelRect(int imageWidth, int imageHeight) {
    if (type != AnnotationType.rect || rect == null) return null;
    final l = (rect!.left * imageWidth).roundToDouble();
    final t = (rect!.top * imageHeight).roundToDouble();
    final w = (rect!.width * imageWidth).roundToDouble();
    final h = (rect!.height * imageHeight).roundToDouble();
    return Rect.fromLTWH(l, t, w, h);
  }

  /// 将归一化锚点转换为对应图像真实像素的绝对 Offset
  Offset? toPixelPoint(int imageWidth, int imageHeight) {
    if (type != AnnotationType.point || point == null) return null;
    return Offset(
      (point!.dx * imageWidth).roundToDouble(),
      (point!.dy * imageHeight).roundToDouble(),
    );
  }

  /// 转换为空间视觉标准 [ymin, xmin, ymax, xmax] 格式
  List<double>? toBBox() {
    if (type != AnnotationType.rect || rect == null) return null;
    return [
      double.parse(rect!.top.toStringAsFixed(4)),
      double.parse(rect!.left.toStringAsFixed(4)),
      double.parse(rect!.bottom.toStringAsFixed(4)),
      double.parse(rect!.right.toStringAsFixed(4)),
    ];
  }

  /// 格式化坐标摘要字符串 (面向用户展示与 Agent 提示词)
  String formatCoordinateSummary(int imageWidth, int imageHeight) {
    switch (type) {
      case AnnotationType.rect:
        if (rect == null) return '选区';
        final l = (rect!.left * 100).toStringAsFixed(1);
        final t = (rect!.top * 100).toStringAsFixed(1);
        final w = (rect!.width * 100).toStringAsFixed(1);
        final h = (rect!.height * 100).toStringAsFixed(1);
        final pxL = (rect!.left * imageWidth).round();
        final pxT = (rect!.top * imageHeight).round();
        final pxR = (rect!.right * imageWidth).round();
        final pxB = (rect!.bottom * imageHeight).round();
        final pxW = pxR - pxL;
        final pxH = pxB - pxT;
        return '选区 [x: $l%, y: $t%, w: $w%, h: $h%] · 像素 [$pxL, $pxT, $pxR, $pxB] ($pxW×$pxH px)';
      case AnnotationType.point:
        if (point == null) return '锚点';
        final x = (point!.dx * 100).toStringAsFixed(1);
        final y = (point!.dy * 100).toStringAsFixed(1);
        final pxX = (point!.dx * imageWidth).round();
        final pxY = (point!.dy * imageHeight).round();
        return '锚点 [x: $x%, y: $y%] · 像素 ($pxX, $pxY px)';
      case AnnotationType.global:
        return '整图批注';
    }
  }

  ImageAnnotation copyWith({
    String? id,
    AnnotationType? type,
    Rect? rect,
    Offset? point,
    String? note,
    DateTime? createdAt,
    int? colorIndex,
  }) {
    return ImageAnnotation(
      id: id ?? this.id,
      type: type ?? this.type,
      rect: rect ?? this.rect,
      point: point ?? this.point,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
      colorIndex: colorIndex ?? this.colorIndex,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.id,
      if (rect != null)
        'rect': {
          'left': rect!.left,
          'top': rect!.top,
          'width': rect!.width,
          'height': rect!.height,
        },
      if (point != null) 'point': {'dx': point!.dx, 'dy': point!.dy},
      'note': note,
      'createdAt': createdAt.toIso8601String(),
      'colorIndex': colorIndex,
    };
  }

  factory ImageAnnotation.fromJson(Map<String, dynamic> json) {
    final type = AnnotationType.fromId(json['type'] as String?);
    Rect? rect;
    if (json['rect'] is Map) {
      final rm = json['rect'] as Map<String, dynamic>;
      final l = (rm['left'] as num?)?.toDouble() ?? 0.0;
      final t = (rm['top'] as num?)?.toDouble() ?? 0.0;
      final w = (rm['width'] as num?)?.toDouble() ?? 0.0;
      final h = (rm['height'] as num?)?.toDouble() ?? 0.0;
      rect = Rect.fromLTWH(l, t, w, h);
    }

    Offset? point;
    if (json['point'] is Map) {
      final pm = json['point'] as Map<String, dynamic>;
      final dx = (pm['dx'] as num?)?.toDouble() ?? 0.0;
      final dy = (pm['dy'] as num?)?.toDouble() ?? 0.0;
      point = Offset(dx, dy);
    }

    final createdAtStr = json['createdAt'] as String?;
    final createdAt = createdAtStr != null
        ? (DateTime.tryParse(createdAtStr) ?? DateTime.now())
        : DateTime.now();

    return ImageAnnotation(
      id: json['id'] as String? ?? 'ann_${DateTime.now().millisecondsSinceEpoch}',
      type: type,
      rect: rect,
      point: point,
      note: json['note'] as String? ?? '',
      createdAt: createdAt,
      colorIndex: (json['colorIndex'] as num?)?.toInt() ?? 0,
    );
  }
}
