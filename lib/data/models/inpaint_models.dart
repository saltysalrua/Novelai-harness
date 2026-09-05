import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;
import 'nai_catalog.dart';

/// 修复画板交互工具。纯结构化枚举，UI 文案由 l10n 接管。
enum InpaintTool {
  /// 矩形选框 (拖拽新建/移动/四角缩放)
  rect('rect'),

  /// 画笔自由绘制蒙版
  brush('brush'),

  /// 橡皮擦除已有描边
  eraser('eraser');

  final String id;

  const InpaintTool(this.id);
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
  standard('standard', '常规重绘'),

  /// AI 整图编辑 (AI Image Edit)
  ///
  /// 把整张图片发给外部绘图模型 (如 nano banana / gpt-image)，
  /// 按自然语言指令重绘整图，不消耗 Anlas 点数。
  aiEdit('ai_edit', 'AI 整图编辑');

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

  /// 提交时栅格化的剩余白色蒙版归一化包围盒 (含橡皮抵消后的真实范围)。
  ///
  /// 由 [InpaintService.computeStrokeMaskBounds] 在描边提交时计算，
  /// 拖拽中不实时重算；[Rect.zero] 表示有正向描边但全被橡皮擦掉
  /// (回退矩形选区)；null 表示未计算 (旧数据回退几何并集)。
  final Rect? maskBounds;

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

  /// AI 整图编辑生图比例 (空 = 跟随原图；如 1:1 / 16:9 / 9:16 等)
  final String aiEditAspectRatio;

  /// AI 整图编辑生图分辨率 (空 = 默认；1K / 2K / 4K，仅部分模型如 Gemini 3 支持 2K 以上)
  final String aiEditResolution;

  /// 专属步数 (为 null 时继承主工作台步数)
  final int? customSteps;

  /// 专属 CFG Scale (为 null 时继承主工作台 CFG)
  final double? customScale;

  const InpaintParams({
    this.mode = InpaintMode.focus,
    this.selectionRect,
    this.brushStrokes = const [],
    this.maskBounds,
    this.brushRadius = 0.03,
    this.contextPadding = 64.0,
    this.strength = 0.70,
    this.noise = 0.00,
    this.customPrompt = '',
    this.customNegativePrompt = '',
    this.useMainPrompt = true,
    this.useMainNegative = true,
    this.customModel,
    this.aiEditAspectRatio = '',
    this.aiEditResolution = '',
    this.customSteps,
    this.customScale,
  });

  InpaintParams copyWith({
    InpaintMode? mode,
    Rect? selectionRect,
    bool clearSelectionRect = false,
    List<InpaintBrushStroke>? brushStrokes,
    bool clearBrushStrokes = false,
    Rect? maskBounds,
    bool clearMaskBounds = false,
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
    String? aiEditAspectRatio,
    String? aiEditResolution,
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
      maskBounds: clearMaskBounds ? null : (maskBounds ?? this.maskBounds),
      brushRadius: brushRadius ?? this.brushRadius,
      contextPadding: contextPadding ?? this.contextPadding,
      strength: strength ?? this.strength,
      noise: noise ?? this.noise,
      customPrompt: customPrompt ?? this.customPrompt,
      customNegativePrompt: customNegativePrompt ?? this.customNegativePrompt,
      useMainPrompt: useMainPrompt ?? this.useMainPrompt,
      useMainNegative: useMainNegative ?? this.useMainNegative,
      customModel: clearCustomModel ? null : (customModel ?? this.customModel),
      aiEditAspectRatio: aiEditAspectRatio ?? this.aiEditAspectRatio,
      aiEditResolution: aiEditResolution ?? this.aiEditResolution,
      customSteps: clearCustomSteps ? null : (customSteps ?? this.customSteps),
      customScale: clearCustomScale ? null : (customScale ?? this.customScale),
    );
  }

  /// 是否存在自由绘制蒙版 (仅正向画笔计入；橡皮描边只减不增修复区)
  bool get hasBrushMask =>
      brushStrokes.any((s) => !s.isEraser && s.points.isNotEmpty);

  /// 生效选区：栅格化蒙版包围盒优先，其次正向描边几何并集，
  /// 再次矩形选区，最后默认居中半幅
  ///
  /// 注意：仅为几何计算 (裁剪框/点数) 服务；UI 展示时 selectionRect == null
  /// 表示无选区，不要用本 getter 的默认兜底直接渲染选框。
  Rect get effectiveSelectionRect {
    if (hasBrushMask) {
      final mb = maskBounds;
      if (mb != null) {
        // 全被橡皮擦掉：回退矩形选区 (与 buildSourceMask 的蒙版回退同语义)
        if (mb.width <= 0 || mb.height <= 0) {
          return selectionRect ?? const Rect.fromLTWH(0.25, 0.25, 0.5, 0.5);
        }
        return mb;
      }
    }
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
    if (maskBounds != null)
      'maskBounds': {
        'left': maskBounds!.left,
        'top': maskBounds!.top,
        'width': maskBounds!.width,
        'height': maskBounds!.height,
      },
    if (customModel != null) 'customModel': customModel!.id,
    if (aiEditAspectRatio.isNotEmpty) 'aiEditAspectRatio': aiEditAspectRatio,
    if (aiEditResolution.isNotEmpty) 'aiEditResolution': aiEditResolution,
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

    Rect? bounds;
    if (json['maskBounds'] is Map) {
      final bm = json['maskBounds'] as Map<String, dynamic>;
      bounds = Rect.fromLTWH(
        (bm['left'] as num?)?.toDouble() ?? 0.0,
        (bm['top'] as num?)?.toDouble() ?? 0.0,
        (bm['width'] as num?)?.toDouble() ?? 0.0,
        (bm['height'] as num?)?.toDouble() ?? 0.0,
      );
    }

    return InpaintParams(
      mode: InpaintMode.fromId(json['mode'] as String?),
      selectionRect: rect,
      maskBounds: bounds,
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
      aiEditAspectRatio: json['aiEditAspectRatio'] as String? ?? '',
      aiEditResolution: json['aiEditResolution'] as String? ?? '',
      customSteps: (json['customSteps'] as num?)?.toInt(),
      customScale: (json['customScale'] as num?)?.toDouble(),
    );
  }
}
