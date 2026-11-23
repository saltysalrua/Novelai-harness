import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect;

import '../../../data/models/novelai_models.dart';
import '../../../data/services/anlas_calculator.dart';
import '../types.dart';
import 'agent_tool.dart';
import 'canvas_view_tool.dart'
    show
        CanvasHistoryGetter,
        CanvasImageBytesLoader,
        ModelVisionChecker,
        resolveCanvasImageBytes,
        unavailableCanvasImageResult;
import 'vision_image_codec.dart';

/// 图像与批注覆盖层离屏渲染结果
class AnnotationOverlayRenderResult {
  final Uint8List bytes;
  final int width;
  final int height;
  final bool overlayApplied;

  const AnnotationOverlayRenderResult({
    required this.bytes,
    required this.width,
    required this.height,
    required this.overlayApplied,
  });
}

/// 离屏绘制批注覆盖层的回调签名（由数据/渲染层注入，保持 core 层无 Flutter painting 依赖）。
typedef AnnotationOverlayRenderFn =
    Future<AnnotationOverlayRenderResult> Function(
      Uint8List imageBytes,
      List<ImageAnnotation> annotations, {
      int maxDimension,
      bool whiteBackground,
    });

/// 查看画板图片批注工具：获取历史图片及其全部圈选批注、锚点与整图备注
class ViewImageAnnotationsTool extends AgentTool {
  final CanvasHistoryGetter getHistory;
  final ModelVisionChecker isModelMultimodal;
  final CanvasImageBytesLoader? loadImageBytes;
  final AnnotationOverlayRenderFn? renderOverlay;

  ViewImageAnnotationsTool({
    required this.getHistory,
    required this.isModelMultimodal,
    this.loadImageBytes,
    this.renderOverlay,
  }) : super(
         name: 'view_image_annotations',
         label: '查看图片批注',
         description:
             '获取画板历史图片及其关联的全部用户批注（包含圈选矩形选区、图钉锚点、整图修改意见，'
             '以及精确的相对百分比位置与绝对像素坐标）。'
             '通过 index 参数从新到旧指定图片（0 表示最新生成/当前图片，默认 0）。'
             '默认返回已离屏合成批注选框与编号的图像版本，便于具备视觉能力的多模态模型直接核对修改位置。'
             '返回的图片默认压缩到最长边 1024px；看不清批注细节时可传 full_resolution=true 获取原始尺寸图片。',
         parameters: const {
           'type': 'object',
           'properties': {
             'index': {
               'type': 'integer',
               'description': '要查看的图片索引（从新到旧排序，0 表示最新/当前图片，1 表示前一张，以此类推。默认 0）。',
             },
             'with_image': {
               'type': 'boolean',
               'description': '是否随结果附带图片数据（默认 true）。',
             },
             'with_overlay': {
               'type': 'boolean',
               'description': '是否在返回的图片上离屏绘制批注选框与编号图钉（默认 true）。false 时返回原图。',
             },
             'full_resolution': {
               'type': 'boolean',
               'description':
                   '是否返回未压缩的原始尺寸图片 (默认 false，压缩到最长边 1024px)。仅在压缩版看不清批注细节时使用。',
             },
           },
         },
       );

  @override
  Future<ToolResult> execute(
    String toolCallId,
    Map<String, dynamic> args,
  ) async {
    final history = getHistory();
    if (history.isEmpty) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '画板当前没有已生成的图片历史。请先生成或导入图片。',
        isError: true,
      );
    }

    final rawIndex = args['index'];
    final int index;
    if (rawIndex is int) {
      index = rawIndex;
    } else if (rawIndex is num) {
      index = rawIndex.toInt();
    } else if (rawIndex is String) {
      index = int.tryParse(rawIndex) ?? 0;
    } else {
      index = 0;
    }

    if (index < 0 || index >= history.length) {
      return ToolResult(
        toolCallId: toolCallId,
        content:
            '指定的图片索引 $index 超出范围。当前共有 ${history.length} 张历史图片，有效索引范围为 0 到 ${history.length - 1}。',
        isError: true,
      );
    }

    final targetImage = history[index];
    final annotations = targetImage.annotations;
    final params = targetImage.params;

    final withImage = args['with_image'] is bool
        ? args['with_image'] as bool
        : true;
    final withOverlay = args['with_overlay'] is bool
        ? args['with_overlay'] as bool
        : true;
    final fullResolution = args['full_resolution'] is bool
        ? args['full_resolution'] as bool
        : false;

    final attachImage = withImage && isModelMultimodal();
    final imageBytes = attachImage
        ? await resolveCanvasImageBytes(targetImage, loadImageBytes)
        : targetImage.bytes;
    if (imageBytes == null) {
      return unavailableCanvasImageResult(toolCallId, index);
    }
    final dims = imageBytes.isEmpty
        ? null
        : await AnlasCalculator.decodeImageDimensions(imageBytes);
    final width = dims?.width ?? params.width;
    final height = dims?.height ?? params.height;

    Uint8List? finalImageBytes;
    var overlayApplied = false;

    if (attachImage) {
      final renderer = renderOverlay;
      if (withOverlay && annotations.isNotEmpty && renderer != null) {
        try {
          final rendered = await renderer(
            imageBytes,
            annotations,
            maxDimension: fullResolution ? 1536 : kVisionImageMaxSide,
            whiteBackground: !fullResolution,
          );
          finalImageBytes = rendered.bytes;
          overlayApplied = true;
        } catch (_) {
          finalImageBytes = imageBytes;
        }
      } else {
        finalImageBytes = imageBytes;
      }
    }

    // 视觉附件压缩：默认压到最长边 1024px 控制视觉 Token；
    // 覆盖层已在非原图模式下一次性直出 ≤1024px 白底 PNG，无需二次编解码
    String resultMime = (finalImageBytes == null || overlayApplied)
        ? 'image/png'
        : sniffImageMimeType(finalImageBytes);
    if (finalImageBytes != null && !fullResolution && !overlayApplied) {
      final compressed = await compressVisionImage(finalImageBytes);
      finalImageBytes = compressed.bytes;
      resultMime = compressed.mimeType;
    }

    final isLatest = index == 0;
    final timeStr = targetImage.createdAt
        .toIso8601String()
        .replaceAll('T', ' ')
        .split('.')
        .first;

    final lines = <String>[
      '已获取画板图片批注 (索引: $index, ${isLatest ? '当前最新图片' : '从新到旧第 ${index + 1} 张'}，共 ${history.length} 张)：',
      '• 图片尺寸: ${width}x$height px',
      '• 来源类型: ${targetImage.isImportedReference ? '导入参考图' : 'NovelAI 生成图'}',
      if (!targetImage.isImportedReference) ...[
        '• 绘图模型: ${params.model.label}',
        if (targetImage.seed >= 0) '• 随机种子: ${targetImage.seed}',
      ],
      '• 生成时间: $timeStr',
      '• 批注数量: ${annotations.length} 条',
      '',
    ];

    if (annotations.isEmpty) {
      lines.add('（该图片当前暂无用户批注）');
    } else {
      for (var i = 0; i < annotations.length; i++) {
        final ann = annotations[i];
        final num = i + 1;
        final typeLabel = ann.type.label;
        final note = ann.note.trim().isEmpty ? '（未填写文字描述）' : ann.note.trim();

        lines.add('【批注 $num】[$typeLabel]');
        lines.add('• 批注 ID: ${ann.id}');
        lines.add('• 批注内容: "$note"');

        if (ann.type == AnnotationType.rect && ann.rect != null) {
          final r = ann.rect!;
          final bbox = ann.toBBox();
          final pxR = ann.toPixelRect(width, height);
          lines.add(
            '• 相对坐标 (归一化，可直接作为 novelai_inpaint 的 rect 参数): [${bbox?[0]}, ${bbox?[1]}, ${bbox?[2]}, ${bbox?[3]}] (ymin, xmin, ymax, xmax)',
          );
          lines.add(
            '• 百分比坐标: x: ${(r.left * 100).toStringAsFixed(1)}%, y: ${(r.top * 100).toStringAsFixed(1)}%, w: ${(r.width * 100).toStringAsFixed(1)}%, h: ${(r.height * 100).toStringAsFixed(1)}%',
          );
          if (pxR != null) {
            lines.add(
              '• 像素位置: [left: ${pxR.left.round()}px, top: ${pxR.top.round()}px, right: ${pxR.right.round()}px, bottom: ${pxR.bottom.round()}px] (宽: ${pxR.width.round()}px, 高: ${pxR.height.round()}px)',
            );
          }
        } else if (ann.type == AnnotationType.point && ann.point != null) {
          final p = ann.point!;
          final pxP = ann.toPixelPoint(width, height);
          lines.add(
            '• 相对坐标 (归一化): [x: ${p.dx.toStringAsFixed(4)}, y: ${p.dy.toStringAsFixed(4)}]',
          );
          lines.add(
            '• 百分比坐标: x: ${(p.dx * 100).toStringAsFixed(1)}%, y: ${(p.dy * 100).toStringAsFixed(1)}%',
          );
          if (pxP != null) {
            lines.add('• 像素位置: (${pxP.dx.round()}px, ${pxP.dy.round()}px)');
          }
        } else if (ann.type == AnnotationType.global) {
          lines.add('• 作用范围: 全局整图修改意见');
        }
        lines.add('');
      }
    }

    if (finalImageBytes != null) {
      lines.add(
        overlayApplied
            ? '已随结果附带叠加了选区框与编号图钉的批注图像，请结合视觉图像与上述坐标信息进行分析。'
            : '已随结果附带原始图像。',
      );
      lines.add(
        fullResolution
            ? '本次附件为原始尺寸图片 (未压缩)。'
            : '本次附件已压缩到最长边 1024px。若看不清批注细节，请再次调用本工具并传 full_resolution: true 获取原图。',
      );
    }

    // 批注 ↔ 修复联动提示：矩形/图钉批注可直接作为修复区域
    final hasPositionalAnnotation = annotations.any(
      (a) => a.type == AnnotationType.rect || a.type == AnnotationType.point,
    );
    if (hasPositionalAnnotation) {
      lines.add('');
      lines.add(
        '提示：矩形/图钉批注可通过 novelai_inpaint 的 annotation_id 参数直接作为修复区域 (图钉会自动转为以其为中心的小选区)；批注只提供修复区域，批注文字是用户修改意见、不会自动作为提示词——需按批注意见修复时请把意见翻译成绘制描述后显式传 prompt (prompt 留空则用工作台当前提示词)；也可直接复制上面的归一化相对坐标作为 rect 参数 (百分比与像素坐标同样会被自动识别换算)；可先用 get_inpaint_geometry 预演几何与点数消耗。',
      );
    }

    return ToolResult(
      toolCallId: toolCallId,
      toolName: 'view_image_annotations',
      content: lines.join('\n').trim(),
      imageBase64: finalImageBytes != null
          ? base64Encode(finalImageBytes)
          : null,
      imageMimeType: resultMime,
    );
  }
}

// ==================== Agent 批注增删改查工具四件套 ====================

/// 批注写入口：全量替换某张历史图片的批注 (由 ViewModel 提供仓库持久化与画布同步)
typedef ImageAnnotationWriter =
    Future<bool> Function(String imageId, List<ImageAnnotation> annotations);

/// 解析工具参数中的图片索引 (从新到旧，0 表示最新)
int _resolveImageIndexArg(Map<String, dynamic> args, int historyLength) {
  final raw = args['index'];
  int index = 0;
  if (raw is int) {
    index = raw;
  } else if (raw is num) {
    index = raw.toInt();
  } else if (raw is String) {
    index = int.tryParse(raw) ?? 0;
  }
  if (index < 0 || index >= historyLength) {
    return -1;
  }
  return index;
}

/// 解析百分比数值参数 (0~100，容错 0~1 归一化输入)
double? _resolvePercent(Map<String, dynamic> args, String key) {
  final raw = args[key];
  double? value;
  if (raw is num) {
    value = raw.toDouble();
  } else if (raw is String) {
    value = double.tryParse(raw);
  }
  if (value == null) return null;
  // 允许 0~1 归一化写法，自动放大为百分比
  if (value >= 0.0 && value <= 1.0) {
    return value * 100.0;
  }
  return value.clamp(0.0, 100.0);
}

/// 按编号 (1 起顺序编号) 或批注 ID 定位复数批注
///
/// 同时汇总 `annotation`/`annotation_id` 单数与数组形态，用于批量增删改。
List<ImageAnnotation> _findAnnotations(
  List<ImageAnnotation> annotations,
  Map<String, dynamic> args,
) {
  final numbers = <int>[];
  final ids = <String>[];

  void addNumber(Object? raw) {
    final value = switch (raw) {
      final int v => v,
      final num v => v.toInt(),
      final String v => int.tryParse(v.trim()) ?? -1,
      _ => -1,
    };
    if (value >= 1) numbers.add(value);
  }

  void addId(Object? raw) {
    if (raw is String && raw.isNotEmpty) ids.add(raw);
  }

  addId(args['annotation_id']);
  addNumber(args['annotation']);
  final rawNumbers = args['annotations'];
  if (rawNumbers is List) {
    for (final item in rawNumbers) {
      addNumber(item);
    }
  }
  final rawIds = args['annotation_ids'];
  if (rawIds is List) {
    for (final item in rawIds) {
      addId(item);
    }
  }

  final result = <ImageAnnotation>[];
  void collect(ImageAnnotation? match) {
    if (match != null && !result.any((a) => a.id == match.id)) {
      result.add(match);
    }
  }

  for (final id in ids) {
    collect(annotations.where((a) => a.id == id).firstOrNull);
  }
  for (final number in numbers) {
    if (number < 1 || number > annotations.length) continue;
    collect(annotations[number - 1]);
  }
  return result;
}

/// 解析批注工具的单条 / 批量规格参数
({List<Map<String, dynamic>> specs, String? error}) _resolveAnnotationSpecs(
  Map<String, dynamic> args, {
  String key = 'annotations',
}) {
  final raw = args[key];
  if (raw == null) return (specs: [args], error: null);
  if (raw is! List || raw.isEmpty) {
    return (specs: const [], error: '$key 必须是非空对象数组。');
  }
  final specs = <Map<String, dynamic>>[];
  for (final item in raw) {
    if (item is! Map) {
      return (specs: const [], error: '$key 必须是非空对象数组。');
    }
    specs.add(item.cast<String, dynamic>());
  }
  return (specs: specs, error: null);
}

/// 由规格构建单条批注；返回 error 时调用方应整体拒绝本次写入
({ImageAnnotation? annotation, String? error}) _buildAnnotationFromSpec(
  Map<String, dynamic> spec,
  int fallbackColorIndex,
) {
  final type = AnnotationType.fromId(spec['type'] as String?);
  final note = (spec['note'] as String?)?.trim() ?? '';
  final rawColor = spec['color_index'];
  final colorIndex = rawColor is int
      ? rawColor
      : (rawColor is num ? rawColor.toInt() : fallbackColorIndex);
  final x = _resolvePercent(spec, 'x');
  final y = _resolvePercent(spec, 'y');
  final w = _resolvePercent(spec, 'w');
  final h = _resolvePercent(spec, 'h');

  switch (type) {
    case AnnotationType.rect:
      if (x == null || y == null || w == null || h == null) {
        return (annotation: null, error: '矩形选区批注需要提供 x/y/w/h 四个百分比坐标 (0~100)。');
      }
      return (
        annotation: ImageAnnotation.rect(
          normalizedRect: Rect.fromLTWH(
            x / 100.0,
            y / 100.0,
            w / 100.0,
            h / 100.0,
          ),
          note: note,
          colorIndex: colorIndex,
        ),
        error: null,
      );
    case AnnotationType.point:
      if (x == null || y == null) {
        return (annotation: null, error: '图钉锚点批注需要提供 x/y 两个百分比坐标 (0~100)。');
      }
      return (
        annotation: ImageAnnotation.point(
          normalizedPoint: Offset(x / 100.0, y / 100.0),
          note: note,
          colorIndex: colorIndex,
        ),
        error: null,
      );
    case AnnotationType.global:
      return (
        annotation: ImageAnnotation.global(note: note, colorIndex: colorIndex),
        error: null,
      );
  }
}

/// 对单条批注应用规格中的字段修改 (未提供的字段保持不变)
ImageAnnotation _applyAnnotationUpdate(
  ImageAnnotation annotation,
  Map<String, dynamic> spec,
) {
  final x = _resolvePercent(spec, 'x');
  final y = _resolvePercent(spec, 'y');
  final w = _resolvePercent(spec, 'w');
  final h = _resolvePercent(spec, 'h');
  final rawColor = spec['color_index'];
  final colorIndex = rawColor is int
      ? rawColor
      : (rawColor is num ? rawColor.toInt() : null);
  final note = spec['note'] is String ? spec['note'] as String : null;

  var updated = annotation;
  if (note != null) updated = updated.copyWith(note: note);
  if (colorIndex != null) {
    updated = updated.copyWith(colorIndex: colorIndex);
  }

  if (updated.type == AnnotationType.rect && updated.rect != null) {
    final cur = updated.rect!;
    final newL = (x != null ? x / 100.0 : cur.left).clamp(0.0, 1.0);
    final newT = (y != null ? y / 100.0 : cur.top).clamp(0.0, 1.0);
    final newW = (w != null ? w / 100.0 : cur.width).clamp(0.0, 1.0);
    final newH = (h != null ? h / 100.0 : cur.height).clamp(0.0, 1.0);
    updated = updated.copyWith(rect: Rect.fromLTWH(newL, newT, newW, newH));
  } else if (updated.type == AnnotationType.point && updated.point != null) {
    final cur = updated.point!;
    final newX = (x != null ? x / 100.0 : cur.dx).clamp(0.0, 1.0);
    final newY = (y != null ? y / 100.0 : cur.dy).clamp(0.0, 1.0);
    updated = updated.copyWith(point: Offset(newX, newY));
  }
  return updated;
}

String _describeAnnotation(
  ImageAnnotation ann,
  int number,
  int imageWidth,
  int imageHeight,
) {
  final summary = ann.formatCoordinateSummary(imageWidth, imageHeight);
  final note = ann.note.trim().isEmpty ? '（未填写文字描述）' : ann.note.trim();
  return '【批注 $number】[${ann.type.label}] "$note" · $summary';
}

/// 在历史图片上添加批注工具：支持矩形选区 / 图钉锚点 / 整图意见三种类型
class AddImageAnnotationTool extends AgentTool {
  final CanvasHistoryGetter getHistory;
  final ImageAnnotationWriter writeAnnotations;

  AddImageAnnotationTool({
    required this.getHistory,
    required this.writeAnnotations,
  }) : super(
         name: 'add_image_annotation',
         label: '添加图片批注',
         description:
             '在画板历史图片上添加一条批注。type=rect 时需要 x/y/w/h 四个百分比坐标'
             '（左上角与宽高，0~100）；type=point 时需要 x/y 两个百分比坐标；'
             'type=global 表示整图修改意见，无需坐标。百分比也接受 0~1 小数写法。',
         parameters: const {
           'type': 'object',
           'properties': {
             'index': {
               'type': 'integer',
               'description': '图片索引（从新到旧，0 表示最新/当前图片，默认 0）。',
             },
             'type': {
               'type': 'string',
               'enum': ['rect', 'point', 'global'],
               'description': '批注类型：rect=矩形选区，point=图钉锚点，global=整图意见。',
             },
             'x': {'type': 'number', 'description': '选区左上角或锚点的横向百分比 (0~100)。'},
             'y': {'type': 'number', 'description': '选区左上角或锚点的纵向百分比 (0~100)。'},
             'w': {'type': 'number', 'description': '选区宽度百分比 (0~100)。'},
             'h': {'type': 'number', 'description': '选区高度百分比 (0~100)。'},
             'note': {'type': 'string', 'description': '批注文字内容（修改意见或描述）。'},
             'color_index': {
               'type': 'integer',
               'description': '颜色索引 0~5（默认自动按顺序取色）。',
             },
             'annotations': {
               'type': 'array',
               'description':
                   '批量添加多条批注：每项字段与顶层同名参数一致 (type 必填)，本次调用内一次全部写入，不要逐条多次调用',
               'items': {
                 'type': 'object',
                 'properties': {
                   'type': {
                     'type': 'string',
                     'enum': ['rect', 'point', 'global'],
                   },
                   'x': {'type': 'number'},
                   'y': {'type': 'number'},
                   'w': {'type': 'number'},
                   'h': {'type': 'number'},
                   'note': {'type': 'string'},
                   'color_index': {'type': 'integer'},
                 },
                 'required': ['type'],
               },
             },
           },
         },
       );

  @override
  Future<ToolResult> execute(
    String toolCallId,
    Map<String, dynamic> args,
  ) async {
    final history = getHistory();
    if (history.isEmpty) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '画板当前没有已生成的图片历史，无法添加批注。',
        isError: true,
      );
    }
    final index = _resolveImageIndexArg(args, history.length);
    if (index < 0) {
      return ToolResult(
        toolCallId: toolCallId,
        content:
            '图片索引超出范围。当前共 ${history.length} 张历史图片，有效索引为 0 到 ${history.length - 1}。',
        isError: true,
      );
    }

    final target = history[index];
    final resolved = _resolveAnnotationSpecs(args);
    if (resolved.error case final String error) {
      return ToolResult(toolCallId: toolCallId, content: error, isError: true);
    }

    // 单条与批量共用同一构建流程；批量时按既有条数顺序自动取色
    final built = <ImageAnnotation>[];
    for (var i = 0; i < resolved.specs.length; i++) {
      final result = _buildAnnotationFromSpec(
        resolved.specs[i],
        target.annotations.length + i,
      );
      if (result.annotation == null) {
        return ToolResult(
          toolCallId: toolCallId,
          content: result.error!,
          isError: true,
        );
      }
      built.add(result.annotation!);
    }

    final updatedList = [...target.annotations, ...built];
    final ok = await writeAnnotations(target.id, updatedList);
    if (!ok) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '批注写入失败，图片可能已被移除。',
        isError: true,
      );
    }

    final dims = await AnlasCalculator.decodeImageDimensions(target.bytes);
    final width = dims?.width ?? target.params.width;
    final height = dims?.height ?? target.params.height;
    final summaries = [
      for (var i = 0; i < built.length; i++)
        _describeAnnotation(
          built[i],
          target.annotations.length + i + 1,
          width,
          height,
        ),
    ];

    return ToolResult(
      toolCallId: toolCallId,
      toolName: 'add_image_annotation',
      content:
          '已在图片 (索引 $index) 上添加批注，当前共 ${updatedList.length} 条：\n'
          '${summaries.join('\n')}\n'
          '批注已持久化，并在批注画板打开时实时同步显示。',
    );
  }
}

/// 更新图片批注工具：修改既有批注的文字、坐标或颜色
class UpdateImageAnnotationTool extends AgentTool {
  final CanvasHistoryGetter getHistory;
  final ImageAnnotationWriter writeAnnotations;

  UpdateImageAnnotationTool({
    required this.getHistory,
    required this.writeAnnotations,
  }) : super(
         name: 'update_image_annotation',
         label: '修改图片批注',
         description:
             '修改画板历史图片上的既有批注。用 annotation (1 起编号) 或 annotation_id 定位；'
             '可更新 note 文字、x/y/w/h 百分比坐标 (0~100) 与颜色索引。未提供的字段保持不变。'
             '一次修改复数批注时用 updates 数组，避免逐条多次调用。',
         parameters: const {
           'type': 'object',
           'properties': {
             'index': {
               'type': 'integer',
               'description': '图片索引（从新到旧，0 表示最新/当前图片，默认 0）。',
             },
             'annotation': {
               'type': 'integer',
               'description': '要修改的批注编号（1 起顺序编号）。',
             },
             'annotation_id': {
               'type': 'string',
               'description': '要修改的批注 ID（与 annotation 二选一，优先使用）。',
             },
             'note': {'type': 'string', 'description': '新的批注文字内容。'},
             'x': {'type': 'number', 'description': '新的横向百分比 (0~100)。'},
             'y': {'type': 'number', 'description': '新的纵向百分比 (0~100)。'},
             'w': {'type': 'number', 'description': '矩形选区新的宽度百分比 (0~100)。'},
             'h': {'type': 'number', 'description': '矩形选区新的高度百分比 (0~100)。'},
             'color_index': {'type': 'integer', 'description': '新的颜色索引 0~5。'},
             'updates': {
               'type': 'array',
               'description':
                   '批量修改多条批注：每项用 annotation 或 annotation_id 定位，字段名与顶层同名参数一致，本次调用内一次全部应用',
               'items': {
                 'type': 'object',
                 'properties': {
                   'annotation': {'type': 'integer'},
                   'annotation_id': {'type': 'string'},
                   'note': {'type': 'string'},
                   'x': {'type': 'number'},
                   'y': {'type': 'number'},
                   'w': {'type': 'number'},
                   'h': {'type': 'number'},
                   'color_index': {'type': 'integer'},
                 },
               },
             },
           },
           'required': ['index'],
         },
       );

  @override
  Future<ToolResult> execute(
    String toolCallId,
    Map<String, dynamic> args,
  ) async {
    final history = getHistory();
    final index = _resolveImageIndexArg(args, history.length);
    if (history.isEmpty || index < 0) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '图片索引超出范围或画板没有历史图片。',
        isError: true,
      );
    }
    final target = history[index];
    final batch = args['updates'] != null;
    final resolved = _resolveAnnotationSpecs(args, key: 'updates');
    if (resolved.error case final String error) {
      return ToolResult(toolCallId: toolCallId, content: error, isError: true);
    }

    final updatedList = [...target.annotations];
    final applied = <({int number, String summary})>[];
    final failed = <String>[];
    for (final spec in resolved.specs) {
      final ann = _findAnnotations(updatedList, spec).firstOrNull;
      if (ann == null) {
        failed.add(
          '未找到批注 ${spec['annotation_id'] ?? spec['annotation'] ?? '(未指定编号)'}',
        );
        continue;
      }
      final updated = _applyAnnotationUpdate(ann, spec);
      final position = updatedList.indexWhere((a) => a.id == updated.id);
      updatedList[position] = updated;
      applied.add((
        number: position + 1,
        summary: _describeAnnotation(
          updated,
          position + 1,
          target.params.width,
          target.params.height,
        ),
      ));
    }

    if (applied.isEmpty) {
      if (batch) {
        return ToolResult(
          toolCallId: toolCallId,
          content:
              '未修改任何批注：${failed.join('；')}。该图片共 ${target.annotations.length} 条批注。',
          isError: true,
        );
      }
      return ToolResult(
        toolCallId: toolCallId,
        content:
            '未找到指定批注。该图片共 ${target.annotations.length} 条批注，编号有效范围 1 到 ${target.annotations.length}。',
        isError: true,
      );
    }

    final ok = await writeAnnotations(target.id, updatedList);
    if (!ok) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '批注写入失败，图片可能已被移除。',
        isError: true,
      );
    }

    final buffer = StringBuffer(
      applied.length == 1
          ? '已更新图片 (索引 $index) 的批注 ${applied.first.number}：\n${applied.first.summary}'
          : '已更新图片 (索引 $index) 的 ${applied.length} 条批注：\n'
                '${applied.map((e) => e.summary).join('\n')}',
    );
    if (failed.isNotEmpty) buffer.write('\n未修改：${failed.join('；')}。');
    return ToolResult(
      toolCallId: toolCallId,
      toolName: 'update_image_annotation',
      content: buffer.toString(),
    );
  }
}

/// 删除图片批注工具：按编号或 ID 移除一条批注
class RemoveImageAnnotationTool extends AgentTool {
  final CanvasHistoryGetter getHistory;
  final ImageAnnotationWriter writeAnnotations;

  RemoveImageAnnotationTool({
    required this.getHistory,
    required this.writeAnnotations,
  }) : super(
         name: 'remove_image_annotation',
         label: '删除图片批注',
         description:
             '删除画板历史图片上的既有批注。用 annotation (1 起编号) 或 annotation_id 定位；'
             '删除复数批注时用 annotations / annotation_ids 数组一次完成，不要逐条多次调用。',
         parameters: const {
           'type': 'object',
           'properties': {
             'index': {
               'type': 'integer',
               'description': '图片索引（从新到旧，0 表示最新/当前图片，默认 0）。',
             },
             'annotation': {
               'type': 'integer',
               'description': '要删除的单个批注编号（1 起顺序编号）。',
             },
             'annotation_id': {
               'type': 'string',
               'description': '要删除的单个批注 ID（与 annotation 二选一，优先使用）。',
             },
             'annotations': {
               'type': 'array',
               'items': {'type': 'integer'},
               'description': '批量删除的批注编号列表（1 起顺序编号，与单数参数可并用）',
             },
             'annotation_ids': {
               'type': 'array',
               'items': {'type': 'string'},
               'description': '批量删除的批注 ID 列表（与单数参数可并用）',
             },
           },
           'required': ['index'],
         },
       );

  @override
  Future<ToolResult> execute(
    String toolCallId,
    Map<String, dynamic> args,
  ) async {
    final history = getHistory();
    final index = _resolveImageIndexArg(args, history.length);
    if (history.isEmpty || index < 0) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '图片索引超出范围或画板没有历史图片。',
        isError: true,
      );
    }
    final target = history[index];
    final targets = _findAnnotations(target.annotations, args);
    if (targets.isEmpty) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '未找到指定批注。该图片共 ${target.annotations.length} 条批注。',
        isError: true,
      );
    }

    final removedIds = targets.map((a) => a.id).toSet();
    final updatedList = target.annotations
        .where((a) => !removedIds.contains(a.id))
        .toList();
    final ok = await writeAnnotations(target.id, updatedList);
    if (!ok) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '批注写入失败，图片可能已被移除。',
        isError: true,
      );
    }

    final described = targets
        .map(
          (ann) =>
              '「[${ann.type.label}] ${ann.note.trim().isEmpty ? '（无文字）' : ann.note.trim()}」',
        )
        .join('、');
    return ToolResult(
      toolCallId: toolCallId,
      toolName: 'remove_image_annotation',
      content:
          '已删除图片 (索引 $index) 的 ${targets.length} 条批注：$described。当前剩余 ${updatedList.length} 条批注。',
    );
  }
}

/// 清空图片批注工具：移除某张历史图片上的全部批注
class ClearImageAnnotationsTool extends AgentTool {
  final CanvasHistoryGetter getHistory;
  final ImageAnnotationWriter writeAnnotations;

  ClearImageAnnotationsTool({
    required this.getHistory,
    required this.writeAnnotations,
  }) : super(
         name: 'clear_image_annotations',
         label: '清空图片批注',
         description: '清空画板历史图片上的全部批注（选区、锚点与整图意见一并移除）。此操作不可撤销。',
         parameters: const {
           'type': 'object',
           'properties': {
             'index': {
               'type': 'integer',
               'description': '图片索引（从新到旧，0 表示最新/当前图片，默认 0）。',
             },
           },
           'required': ['index'],
         },
       );

  @override
  Future<ToolResult> execute(
    String toolCallId,
    Map<String, dynamic> args,
  ) async {
    final history = getHistory();
    final index = _resolveImageIndexArg(args, history.length);
    if (history.isEmpty || index < 0) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '图片索引超出范围或画板没有历史图片。',
        isError: true,
      );
    }
    final target = history[index];
    if (target.annotations.isEmpty) {
      return ToolResult(
        toolCallId: toolCallId,
        toolName: 'clear_image_annotations',
        content: '该图片当前没有批注，无需清空。',
      );
    }

    final count = target.annotations.length;
    final ok = await writeAnnotations(target.id, const []);
    if (!ok) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '批注写入失败，图片可能已被移除。',
        isError: true,
      );
    }

    return ToolResult(
      toolCallId: toolCallId,
      toolName: 'clear_image_annotations',
      content: '已清空图片 (索引 $index) 的 $count 条批注。',
    );
  }
}

/// 统一画板图片批注管理工具（合并 view / add / update / remove / clear 为单工具 action 调度）
class ImageAnnotationsTool extends AgentTool {
  final ViewImageAnnotationsTool _viewTool;
  final AddImageAnnotationTool _addTool;
  final UpdateImageAnnotationTool _updateTool;
  final RemoveImageAnnotationTool _removeTool;
  final ClearImageAnnotationsTool _clearTool;

  ImageAnnotationsTool({
    required List<NaiGeneratedImage> Function() getHistory,
    required Future<Uint8List?> Function(NaiGeneratedImage image) loadImageBytes,
    required bool Function() isModelMultimodal,
    AnnotationOverlayRenderFn? renderOverlay,
    required Future<bool> Function(
      String imageId,
      List<ImageAnnotation> nextAnnotations,
    )
    writeAnnotations,
  }) : _viewTool = ViewImageAnnotationsTool(
         getHistory: getHistory,
         loadImageBytes: loadImageBytes,
         isModelMultimodal: isModelMultimodal,
         renderOverlay: renderOverlay,
       ),
       _addTool = AddImageAnnotationTool(
         getHistory: getHistory,
         writeAnnotations: writeAnnotations,
       ),
       _updateTool = UpdateImageAnnotationTool(
         getHistory: getHistory,
         writeAnnotations: writeAnnotations,
       ),
       _removeTool = RemoveImageAnnotationTool(
         getHistory: getHistory,
         writeAnnotations: writeAnnotations,
       ),
       _clearTool = ClearImageAnnotationsTool(
         getHistory: getHistory,
         writeAnnotations: writeAnnotations,
       ),
       super(
         name: 'image_annotations',
         label: '图片批注管理',
         description:
             '统一查看与管理画板图片上的矩形选区/图钉/全局批注。通过 action 选择操作：\n'
             '- view: 查看批注清单（可选附带批注叠层图）；\n'
             '- add: 添加单条或批量批注（annotations 数组）；\n'
             '- update: 按 id 或 updates 数组批量修改批注；\n'
             '- remove: 按 id 或 ids 数组批量删除批注；\n'
             '- clear: 清空目标图片上的全部批注。',
         parameters: const {
           'type': 'object',
           'properties': {
             'action': {
               'type': 'string',
               'enum': ['view', 'add', 'update', 'remove', 'clear'],
               'description': '操作类型：view / add / update / remove / clear',
             },
             'image_index': {
               'type': 'integer',
               'description': '历史图片索引（0 表示最新图，默认 0）',
             },
             'include_image': {
               'type': 'boolean',
               'description': 'view 时是否附带标注叠层图，默认 true',
             },
             'id': {'type': 'string', 'description': '批注 ID (update / remove)'},
             'ids': {
               'type': 'array',
               'items': {'type': 'string'},
               'description': '批量删除的批注 ID 列表 (remove)',
             },
             'type': {
               'type': 'string',
               'enum': ['rect', 'point', 'global'],
               'description': '批注形状类型 (add / update)',
             },
             'text': {'type': 'string', 'description': '批注说明文本 (add / update)'},
             'rect': {
               'description': '矩形选区 [ymin, xmin, ymax, xmax] (0~1 归一化或 0~100 百分比)',
             },
             'point': {'description': '图钉锚点 [y, x]'},
             'color': {'type': 'string', 'description': '批注颜色十六进制'},
             'annotations': {
               'type': 'array',
               'items': {'type': 'object'},
               'description': '批量新增的批注数组 (add)',
             },
             'updates': {
               'type': 'array',
               'items': {'type': 'object'},
               'description': '批量修改的批注数组，每项需含 id (update)',
             },
           },
           'required': ['action'],
         },
       );

  @override
  Future<ToolResult> execute(
    String toolCallId,
    Map<String, dynamic> args,
  ) async {
    final action = (args['action'] as String?)?.trim().toLowerCase() ?? '';
    return switch (action) {
      'view' || 'list' => _viewTool.execute(toolCallId, args),
      'add' => _addTool.execute(toolCallId, args),
      'update' => _updateTool.execute(toolCallId, args),
      'remove' || 'delete' => _removeTool.execute(toolCallId, args),
      'clear' => _clearTool.execute(toolCallId, args),
      _ => ToolResult(
        toolCallId: toolCallId,
        content:
            '错误：image_annotations 的 action 必须是 view / add / update / remove / clear。',
        isError: true,
      ),
    };
  }
}
