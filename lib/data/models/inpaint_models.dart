import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;
import 'nai_catalog.dart';

/// 修复画板交互工具
enum InpaintTool {
  /// 矩形选框 (拖拽新建/移动/四角缩放)
  rect('rect', '框选'),

  /// 画笔自由绘制蒙版
  brush('brush', '画笔'),

  /// 橡皮擦除已有描边
  eraser('eraser', '橡皮');

  final String id;
  final String label;

  const InpaintTool(this.id, this.label);
}

/// 画笔描边 (自由绘制修复蒙版)
///
/// [points] 为归一化坐标 (0.0~1.0) 的连续轨迹点，[radius] 为笔刷半径
/// (相对原图短边的归一化值，如 0.03 ≈ 短边的 3%)。
class InpaintBrushStroke {
  final List<Offset> points;
  final double radius;

  /// 是否为反向画笔 (橡皮)：在蒙版上打黑，抵消先前绘制的白色区域。
  /// 描边按提交顺序依次栅格化，后画的橡皮可以擦掉先画的笔迹。
  final bool isEraser;

  const InpaintBrushStroke({
    required this.points,
    required this.radius,
    this.isEraser = false,
  });

  /// 描边归一化包围盒 (未含笔刷半径外扩)
  Rect get bounds {
    if (points.isEmpty) return Rect.zero;
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
    return Rect.fromLTRB(l, t, r, b);
  }

  Map<String, dynamic> toJson() => {
    'radius': radius,
    if (isEraser) 'isEraser': true,
    'points': points.map((p) => <double>[p.dx, p.dy]).toList(growable: false),
  };

  factory InpaintBrushStroke.fromJson(Map<String, dynamic> json) {
    final rawPoints = json['points'];
    final points = <Offset>[];
    if (rawPoints is List) {
      for (final p in rawPoints) {
        if (p is List && p.length >= 2) {
          points.add(
            Offset(
              (p[0] as num?)?.toDouble() ?? 0.0,
              (p[1] as num?)?.toDouble() ?? 0.0,
            ),
          );
        }
      }
    }
    return InpaintBrushStroke(
      points: points,
      radius: (json['radius'] as num?)?.toDouble() ?? 0.03,
      isEraser: json['isEraser'] as bool? ?? false,
    );
  }
}

/// 局部重绘模式
enum InpaintMode {
  /// 焦点特写修复 (Focus Inpaint / 局部特写修复)
  ///
  /// 自动计算上下文外延并将目标裁剪区域等比上采样至 1MP (1024x1024) 潜空间，
  /// 经 NovelAI infill 渲染后等比缩放并无损贴回原图，极大提升细节质量且 100% Opus 免费。
  focus('focus', '焦点特写'),

  /// 常规局部重绘 (Standard Inpaint)
  ///
  /// 针对整图尺度或指定遮罩区域进行重绘。
  standard('standard', '常规重绘');

  final String id;
  final String label;

  const InpaintMode(this.id, this.label);

  static InpaintMode fromId(String? id) {
    for (final mode in InpaintMode.values) {
      if (mode.id == id || mode.name == id) return mode;
    }
    return InpaintMode.focus;
  }
}

/// 焦点重绘几何信息 (对齐 Aaalice / NovelAI 空间布局标准)
class InpaintGeometry {
  /// 待修复目标在原图中的绝对像素矩形边界
  final Rect focusBounds;

  /// 包含外延上下文 (Context Padding) 的实际裁剪矩形区域 (限制在原图内)
  final Rect contextCrop;

  /// 发送给 NovelAI API 的目标请求宽度 (对齐 64 步长网格)
  final int requestWidth;

  /// 发送给 NovelAI API 的目标请求高度 (对齐 64 步长网格)
  final int requestHeight;

  /// 目标区域相较原裁剪区域的放大倍率 (潜空间 1MP 超采样倍数)
  final double scale;

  /// 是否受到最大像素上限动态收敛
  final bool wasDynamicallyConstrained;

  const InpaintGeometry({
    required this.focusBounds,
    required this.contextCrop,
    required this.requestWidth,
    required this.requestHeight,
    required this.scale,
    this.wasDynamicallyConstrained = false,
  });

  int get requestArea => requestWidth * requestHeight;

  /// 是否符合 Opus 免点数区间 (1MP 潜空间以内，即 requestArea <= 1048576)
  bool get isOpusFree => requestArea <= 1048576;
}

/// 局部修复工作台参数配置
class InpaintParams {
  final InpaintMode mode;

  /// 归一化选区 (0.0 ~ 1.0)，为 null 时默认使用全图或当前批注选区
  final Rect? selectionRect;

  /// 自由绘制画笔描边列表 (非空时优先于 [selectionRect] 作为修复蒙版)
  final List<InpaintBrushStroke> brushStrokes;

  /// 当前笔刷半径 (相对原图短边归一化，0.005 ~ 0.25)
  final double brushRadius;

  /// 焦点外延上下文内边距 (像素，默认 64 px，范围 16 ~ 192 px)
  final double contextPadding;

  /// 重绘去噪强度 (0.0 ~ 1.0，默认 0.70)
  final double strength;

  /// 附加噪声 (0.0 ~ 1.0，默认 0.00)
  final double noise;

  /// 自定义正向提示词 (当 useMainPrompt 为 false 时使用)
  final String customPrompt;

  /// 自定义负向提示词 (当 useMainNegative 为 false 时使用)
  final String customNegativePrompt;

  /// 是否复用主工作台正向提示词 (默认 true)
  final bool useMainPrompt;

  /// 是否复用主工作台负向提示词 (默认 true)
  final bool useMainNegative;

  /// 专属重绘模型 (为 null 时继承主工作台模型)
  final NaiModel? customModel;

  /// 专属步数 (为 null 时继承主工作台步数)
  final int? customSteps;

  /// 专属 CFG Scale (为 null 时继承主工作台 CFG)
  final double? customScale;

  const InpaintParams({
    this.mode = InpaintMode.focus,
    this.selectionRect,
    this.brushStrokes = const [],
    this.brushRadius = 0.03,
    this.contextPadding = 64.0,
    this.strength = 0.70,
    this.noise = 0.00,
    this.customPrompt = '',
    this.customNegativePrompt = '',
    this.useMainPrompt = true,
    this.useMainNegative = true,
    this.customModel,
    this.customSteps,
    this.customScale,
  });

  InpaintParams copyWith({
    InpaintMode? mode,
    Rect? selectionRect,
    bool clearSelectionRect = false,
    List<InpaintBrushStroke>? brushStrokes,
    bool clearBrushStrokes = false,
    double? brushRadius,
    double? contextPadding,
    double? strength,
    double? noise,
    String? customPrompt,
    String? customNegativePrompt,
    bool? useMainPrompt,
    bool? useMainNegative,
    NaiModel? customModel,
    bool clearCustomModel = false,
    int? customSteps,
    bool clearCustomSteps = false,
    double? customScale,
    bool clearCustomScale = false,
  }) {
    return InpaintParams(
      mode: mode ?? this.mode,
      selectionRect: clearSelectionRect
          ? null
          : (selectionRect ?? this.selectionRect),
      brushStrokes: clearBrushStrokes
          ? const []
          : (brushStrokes ?? this.brushStrokes),
      brushRadius: brushRadius ?? this.brushRadius,
      contextPadding: contextPadding ?? this.contextPadding,
      strength: strength ?? this.strength,
      noise: noise ?? this.noise,
      customPrompt: customPrompt ?? this.customPrompt,
      customNegativePrompt: customNegativePrompt ?? this.customNegativePrompt,
      useMainPrompt: useMainPrompt ?? this.useMainPrompt,
      useMainNegative: useMainNegative ?? this.useMainNegative,
      customModel: clearCustomModel ? null : (customModel ?? this.customModel),
      customSteps: clearCustomSteps ? null : (customSteps ?? this.customSteps),
      customScale: clearCustomScale ? null : (customScale ?? this.customScale),
    );
  }

  /// 是否存在自由绘制蒙版 (仅正向画笔计入；橡皮描边只减不增修复区)
  bool get hasBrushMask =>
      brushStrokes.any((s) => !s.isEraser && s.points.isNotEmpty);

  /// 生效选区：正向画笔描边包围盒优先，其次矩形选区，最后默认居中半幅
  ///
  /// 注意：仅为几何计算 (裁剪框/点数) 服务；UI 展示时 selectionRect == null
  /// 表示无选区，不要用本 getter 的默认兜底直接渲染选框。
  Rect get effectiveSelectionRect {
    Rect? merged;
    var maxRadius = 0.0;
    for (final stroke in brushStrokes) {
      if (stroke.isEraser || stroke.points.isEmpty) continue;
      final b = stroke.bounds;
      merged = (merged == null)
          ? b
          : Rect.fromLTRB(
              math.min(merged.left, b.left),
              math.min(merged.top, b.top),
              math.max(merged.right, b.right),
              math.max(merged.bottom, b.bottom),
            );
      if (stroke.radius > maxRadius) maxRadius = stroke.radius;
    }
    // 水平/垂直直线的包围盒宽高为 0，不能用 isEmpty 判空，用 null 累加器
    if (merged != null) {
      return Rect.fromLTRB(
        (merged.left - maxRadius).clamp(0.0, 1.0),
        (merged.top - maxRadius).clamp(0.0, 1.0),
        (merged.right + maxRadius).clamp(0.0, 1.0),
        (merged.bottom + maxRadius).clamp(0.0, 1.0),
      );
    }
    return selectionRect ?? const Rect.fromLTWH(0.25, 0.25, 0.5, 0.5);
  }

  Map<String, dynamic> toJson() => {
    'mode': mode.id,
    if (selectionRect != null)
      'selectionRect': {
        'left': selectionRect!.left,
        'top': selectionRect!.top,
        'width': selectionRect!.width,
        'height': selectionRect!.height,
      },
    'contextPadding': contextPadding,
    'strength': strength,
    'noise': noise,
    'customPrompt': customPrompt,
    'customNegativePrompt': customNegativePrompt,
    'useMainPrompt': useMainPrompt,
    'useMainNegative': useMainNegative,
    if (brushStrokes.isNotEmpty)
      'brushStrokes': brushStrokes
          .map((s) => s.toJson())
          .toList(growable: false),
    'brushRadius': brushRadius,
    if (customModel != null) 'customModel': customModel!.id,
    if (customSteps != null) 'customSteps': customSteps,
    if (customScale != null) 'customScale': customScale,
  };

  factory InpaintParams.fromJson(Map<String, dynamic> json) {
    Rect? rect;
    if (json['selectionRect'] is Map) {
      final rm = json['selectionRect'] as Map<String, dynamic>;
      rect = Rect.fromLTWH(
        (rm['left'] as num?)?.toDouble() ?? 0.0,
        (rm['top'] as num?)?.toDouble() ?? 0.0,
        (rm['width'] as num?)?.toDouble() ?? 0.0,
        (rm['height'] as num?)?.toDouble() ?? 0.0,
      );
    }

    return InpaintParams(
      mode: InpaintMode.fromId(json['mode'] as String?),
      selectionRect: rect,
      brushStrokes: (json['brushStrokes'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (m) => InpaintBrushStroke.fromJson(
              m.map((k, v) => MapEntry(k.toString(), v)),
            ),
          )
          .toList(growable: false),
      brushRadius: (json['brushRadius'] as num?)?.toDouble() ?? 0.03,
      contextPadding: (json['contextPadding'] as num?)?.toDouble() ?? 64.0,
      strength: (json['strength'] as num?)?.toDouble() ?? 0.70,
      noise: (json['noise'] as num?)?.toDouble() ?? 0.00,
      customPrompt: json['customPrompt'] as String? ?? '',
      customNegativePrompt: json['customNegativePrompt'] as String? ?? '',
      useMainPrompt: json['useMainPrompt'] as bool? ?? true,
      useMainNegative: json['useMainNegative'] as bool? ?? true,
      customModel: json['customModel'] is String
          ? NaiModel.fromId(json['customModel'] as String)
          : null,
      customSteps: (json['customSteps'] as num?)?.toInt(),
      customScale: (json['customScale'] as num?)?.toDouble(),
    );
  }
}
