import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../../data/models/novelai_models.dart';
import '../../../data/services/anlas_calculator.dart';
import '../types.dart';
import 'agent_tool.dart';
import 'canvas_view_tool.dart' show CanvasHistoryGetter, ModelVisionChecker;
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

/// 将批注覆盖层 (选区边框、锚点、编号徽章与标签) 离屏绘制到图像字节上
Future<AnnotationOverlayRenderResult> renderImageWithAnnotationOverlay(
  Uint8List imageBytes,
  List<ImageAnnotation> annotations, {
  int maxDimension = 1536,
}) async {
  final codec = await ui.instantiateImageCodec(imageBytes);
  final frame = await codec.getNextFrame();
  final source = frame.image;

  final longSide = math.max(source.width, source.height);
  final scale = longSide > maxDimension ? maxDimension / longSide : 1.0;
  final outW = math.max(1, (source.width * scale).round());
  final outH = math.max(1, (source.height * scale).round());

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(
    recorder,
    ui.Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble()),
  );

  // 1. 绘制底图
  canvas.drawImageRect(
    source,
    ui.Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
    ui.Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble()),
    ui.Paint()..filterQuality = ui.FilterQuality.medium,
  );

  final canvasSize = ui.Size(outW.toDouble(), outH.toDouble());

  // 2. 依次绘制各条批注
  for (var i = 0; i < annotations.length; i++) {
    final ann = annotations[i];
    final color = ann.color;
    final indexNum = i + 1;

    switch (ann.type) {
      case AnnotationType.rect:
        if (ann.rect != null) {
          final r = ann.rect!;
          final drawRect = ui.Rect.fromLTWH(
            r.left * canvasSize.width,
            r.top * canvasSize.height,
            r.width * canvasSize.width,
            r.height * canvasSize.height,
          );

          // 半透明高亮填充
          canvas.drawRect(
            drawRect,
            ui.Paint()
              ..color = color.withValues(alpha: 0.18)
              ..style = ui.PaintingStyle.fill,
          );

          // 矩形边框
          canvas.drawRect(
            drawRect,
            ui.Paint()
              ..color = color
              ..style = ui.PaintingStyle.stroke
              ..strokeWidth = math.max(2.0, canvasSize.shortestSide * 0.0035),
          );

          // 编号图钉锚点 (绘制在选区左上角)
          final badgeDiameter = (canvasSize.width * 0.035).clamp(24.0, 52.0);
          final badgeCenter = ui.Offset(
            (drawRect.left + badgeDiameter * 0.6).clamp(
              badgeDiameter / 2,
              canvasSize.width - badgeDiameter / 2,
            ),
            (drawRect.top + badgeDiameter * 0.6).clamp(
              badgeDiameter / 2,
              canvasSize.height - badgeDiameter / 2,
            ),
          );

          _drawPinBadge(canvas, badgeCenter, badgeDiameter, indexNum, color);

          // 批注简要文字标签 (若有)
          if (ann.note.trim().isNotEmpty) {
            _drawNoteLabelBadge(
              canvas,
              canvasSize,
              ann.note.trim(),
              badgeCenter.dx + badgeDiameter * 0.7,
              badgeCenter.dy - badgeDiameter * 0.5,
              color,
            );
          }
        }
        break;

      case AnnotationType.point:
        if (ann.point != null) {
          final p = ann.point!;
          final badgeDiameter = (canvasSize.width * 0.035).clamp(24.0, 52.0);
          final center = ui.Offset(
            p.dx * canvasSize.width,
            p.dy * canvasSize.height,
          );

          _drawPinBadge(canvas, center, badgeDiameter, indexNum, color);

          if (ann.note.trim().isNotEmpty) {
            _drawNoteLabelBadge(
              canvas,
              canvasSize,
              ann.note.trim(),
              center.dx + badgeDiameter * 0.7,
              center.dy - badgeDiameter * 0.5,
              color,
            );
          }
        }
        break;

      case AnnotationType.global:
        // 整图全局批注在右上角绘制醒目标签
        final noteText = ann.note.trim().isNotEmpty ? ann.note.trim() : '整图批注';
        _drawGlobalBanner(canvas, canvasSize, indexNum, noteText, color, i);
        break;
    }
  }

  final picture = recorder.endRecording();
  final outImage = await picture.toImage(outW, outH);
  final data = await outImage.toByteData(format: ui.ImageByteFormat.png);
  source.dispose();
  outImage.dispose();

  final bytes = data?.buffer.asUint8List();
  if (bytes == null || bytes.isEmpty) {
    throw StateError('批注覆盖层编码失败');
  }

  return AnnotationOverlayRenderResult(
    bytes: bytes,
    width: outW,
    height: outH,
    overlayApplied: true,
  );
}

void _drawPinBadge(
  ui.Canvas canvas,
  ui.Offset center,
  double diameter,
  int number,
  ui.Color color,
) {
  // 外阴影白描边
  canvas.drawCircle(
    center,
    diameter / 2 + 2.5,
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );
  // 实色底圆
  canvas.drawCircle(center, diameter / 2, ui.Paint()..color = color);
  // 编号数字
  final fontSize = diameter * 0.48;
  final painter = TextPainter(
    text: TextSpan(
      text: '$number',
      style: TextStyle(
        color: const ui.Color(0xFFFFFFFF),
        fontSize: fontSize,
        fontWeight: FontWeight.w800,
      ),
    ),
    textAlign: TextAlign.center,
    textDirection: TextDirection.ltr,
  )..layout();
  painter.paint(
    canvas,
    center - ui.Offset(painter.width / 2, painter.height / 2),
  );
}

void _drawNoteLabelBadge(
  ui.Canvas canvas,
  ui.Size canvasSize,
  String text,
  double left,
  double top,
  ui.Color color,
) {
  final singleLineText = text.replaceAll('\n', ' ');
  final truncated = singleLineText.length > 24
      ? '${singleLineText.substring(0, 24)}...'
      : singleLineText;

  final fontSize = (canvasSize.width * 0.015).clamp(11.0, 22.0);
  final painter = TextPainter(
    text: TextSpan(
      text: truncated,
      style: TextStyle(
        color: const ui.Color(0xFFFFFFFF),
        fontSize: fontSize,
        fontWeight: FontWeight.w600,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  const padH = 7.0;
  const padV = 3.5;
  final badgeW = painter.width + padH * 2;
  final badgeH = painter.height + padV * 2;

  final clampedL = left
      .clamp(0.0, math.max(0.0, canvasSize.width - badgeW))
      .toDouble();
  final clampedT = top
      .clamp(0.0, math.max(0.0, canvasSize.height - badgeH))
      .toDouble();

  final rrect = ui.RRect.fromRectAndRadius(
    ui.Rect.fromLTWH(clampedL, clampedT, badgeW, badgeH),
    const ui.Radius.circular(5),
  );
  canvas.drawRRect(rrect, ui.Paint()..color = const ui.Color(0xEB1E1E24));
  canvas.drawRRect(
    rrect,
    ui.Paint()
      ..color = color.withValues(alpha: 0.8)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 1.2,
  );
  painter.paint(canvas, ui.Offset(clampedL + padH, clampedT + padV));
}

void _drawGlobalBanner(
  ui.Canvas canvas,
  ui.Size canvasSize,
  int number,
  String noteText,
  ui.Color color,
  int index,
) {
  final text = '#$number 整图: $noteText';
  final singleLineText = text.replaceAll('\n', ' ');
  final truncated = singleLineText.length > 32
      ? '${singleLineText.substring(0, 32)}...'
      : singleLineText;

  final fontSize = (canvasSize.width * 0.015).clamp(11.0, 20.0);
  final painter = TextPainter(
    text: TextSpan(
      text: truncated,
      style: TextStyle(
        color: const ui.Color(0xFFFFFFFF),
        fontSize: fontSize,
        fontWeight: FontWeight.w600,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  const padH = 10.0;
  const padV = 5.0;
  final badgeW = painter.width + padH * 2;
  final badgeH = painter.height + padV * 2;
  final top = 12.0 + index * (badgeH + 6.0);
  final left = (canvasSize.width - badgeW - 12.0).clamp(0.0, canvasSize.width);

  final rrect = ui.RRect.fromRectAndRadius(
    ui.Rect.fromLTWH(left, top, badgeW, badgeH),
    const ui.Radius.circular(6),
  );
  canvas.drawRRect(rrect, ui.Paint()..color = const ui.Color(0xF018181B));
  canvas.drawRRect(
    rrect,
    ui.Paint()
      ..color = color
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 1.5,
  );
  painter.paint(canvas, ui.Offset(left + padH, top + padV));
}

/// 查看画板图片批注工具：获取历史图片及其全部圈选批注、锚点与整图备注
class ViewImageAnnotationsTool extends AgentTool {
  final CanvasHistoryGetter getHistory;
  final ModelVisionChecker isModelMultimodal;

  ViewImageAnnotationsTool({
    required this.getHistory,
    required this.isModelMultimodal,
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
    final rawBytes = targetImage.bytes;
    final imageBytes = rawBytes is Uint8List
        ? rawBytes
        : Uint8List.fromList(rawBytes);

    final withImage = args['with_image'] is bool
        ? args['with_image'] as bool
        : true;
    final withOverlay = args['with_overlay'] is bool
        ? args['with_overlay'] as bool
        : true;
    final fullResolution = args['full_resolution'] is bool
        ? args['full_resolution'] as bool
        : false;

    final dims = await AnlasCalculator.decodeImageDimensions(imageBytes);
    final width = dims?.width ?? params.width;
    final height = dims?.height ?? params.height;

    Uint8List? finalImageBytes;
    var overlayApplied = false;

    if (withImage) {
      if (!isModelMultimodal()) {
        // 模型不支持图片输入时仅返回结构化文本
      } else if (withOverlay && annotations.isNotEmpty) {
        try {
          final rendered = await renderImageWithAnnotationOverlay(
            imageBytes,
            annotations,
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

    // 视觉附件压缩：默认压到最长边 1024px 控制视觉 Token，
    // 模型看不清批注细节时可传 full_resolution=true 获取原图
    String resultMime = 'image/png';
    if (finalImageBytes != null && !fullResolution) {
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
            '• 相对坐标 (归一化，可直接作为 novelai_inpaint / get_inpaint_geometry 的 rect 参数): [${bbox?[0]}, ${bbox?[1]}, ${bbox?[2]}, ${bbox?[3]}] (ymin, xmin, ymax, xmax)',
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

/// 按编号 (1 起) 或批注 ID 定位批注
ImageAnnotation? _findAnnotation(
  List<ImageAnnotation> annotations,
  Map<String, dynamic> args,
) {
  final rawNumber = args['annotation'];
  final id = args['annotation_id'] as String?;

  if (id != null && id.isNotEmpty) {
    return annotations.where((a) => a.id == id).firstOrNull;
  }
  int number = -1;
  if (rawNumber is int) {
    number = rawNumber;
  } else if (rawNumber is num) {
    number = rawNumber.toInt();
  } else if (rawNumber is String) {
    number = int.tryParse(rawNumber) ?? -1;
  }
  if (number < 1 || number > annotations.length) return null;
  return annotations[number - 1];
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
           },
           'required': ['type'],
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
    final type = AnnotationType.fromId(args['type'] as String?);
    final note = (args['note'] as String?)?.trim() ?? '';
    final rawColor = args['color_index'];
    final colorIndex = rawColor is int
        ? rawColor
        : (rawColor is num ? rawColor.toInt() : target.annotations.length);

    final x = _resolvePercent(args, 'x');
    final y = _resolvePercent(args, 'y');
    final w = _resolvePercent(args, 'w');
    final h = _resolvePercent(args, 'h');

    ImageAnnotation newAnn;
    switch (type) {
      case AnnotationType.rect:
        if (x == null || y == null || w == null || h == null) {
          return ToolResult(
            toolCallId: toolCallId,
            content: '矩形选区批注需要提供 x/y/w/h 四个百分比坐标 (0~100)。',
            isError: true,
          );
        }
        newAnn = ImageAnnotation.rect(
          normalizedRect: Rect.fromLTWH(
            x / 100.0,
            y / 100.0,
            w / 100.0,
            h / 100.0,
          ),
          note: note,
          colorIndex: colorIndex,
        );
      case AnnotationType.point:
        if (x == null || y == null) {
          return ToolResult(
            toolCallId: toolCallId,
            content: '图钉锚点批注需要提供 x/y 两个百分比坐标 (0~100)。',
            isError: true,
          );
        }
        newAnn = ImageAnnotation.point(
          normalizedPoint: Offset(x / 100.0, y / 100.0),
          note: note,
          colorIndex: colorIndex,
        );
      case AnnotationType.global:
        newAnn = ImageAnnotation.global(note: note, colorIndex: colorIndex);
    }

    final updatedList = [...target.annotations, newAnn];
    final ok = await writeAnnotations(target.id, updatedList);
    if (!ok) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '批注写入失败，图片可能已被移除。',
        isError: true,
      );
    }

    final dims = await AnlasCalculator.decodeImageDimensions(
      target.bytes is Uint8List
          ? target.bytes as Uint8List
          : Uint8List.fromList(target.bytes),
    );
    final summary = _describeAnnotation(
      newAnn,
      updatedList.length,
      dims?.width ?? target.params.width,
      dims?.height ?? target.params.height,
    );

    return ToolResult(
      toolCallId: toolCallId,
      toolName: 'add_image_annotation',
      content:
          '已在图片 (索引 $index) 上添加批注，当前共 ${updatedList.length} 条：\n$summary\n'
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
             '修改画板历史图片上的一条既有批注。用 annotation (1 起编号) 或 annotation_id 定位；'
             '可更新 note 文字、x/y/w/h 百分比坐标 (0~100) 与颜色索引。未提供的字段保持不变。',
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
    final ann = _findAnnotation(target.annotations, args);
    if (ann == null) {
      return ToolResult(
        toolCallId: toolCallId,
        content:
            '未找到指定批注。该图片共 ${target.annotations.length} 条批注，编号有效范围 1 到 ${target.annotations.length}。',
        isError: true,
      );
    }

    final x = _resolvePercent(args, 'x');
    final y = _resolvePercent(args, 'y');
    final w = _resolvePercent(args, 'w');
    final h = _resolvePercent(args, 'h');
    final rawColor = args['color_index'];
    final colorIndex = rawColor is int
        ? rawColor
        : (rawColor is num ? rawColor.toInt() : null);
    final note = args['note'] is String ? args['note'] as String : null;

    ImageAnnotation updated = ann;
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

    final updatedList = target.annotations
        .map((a) => a.id == updated.id ? updated : a)
        .toList();
    final ok = await writeAnnotations(target.id, updatedList);
    if (!ok) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '批注写入失败，图片可能已被移除。',
        isError: true,
      );
    }

    final number = updatedList.indexOf(updated) + 1;
    final summary = _describeAnnotation(
      updated,
      number,
      target.params.width,
      target.params.height,
    );
    return ToolResult(
      toolCallId: toolCallId,
      toolName: 'update_image_annotation',
      content: '已更新图片 (索引 $index) 的批注 $number：\n$summary',
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
             '删除画板历史图片上的一条既有批注。用 annotation (1 起编号) 或 annotation_id 定位。',
         parameters: const {
           'type': 'object',
           'properties': {
             'index': {
               'type': 'integer',
               'description': '图片索引（从新到旧，0 表示最新/当前图片，默认 0）。',
             },
             'annotation': {
               'type': 'integer',
               'description': '要删除的批注编号（1 起顺序编号）。',
             },
             'annotation_id': {
               'type': 'string',
               'description': '要删除的批注 ID（与 annotation 二选一，优先使用）。',
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
    final ann = _findAnnotation(target.annotations, args);
    if (ann == null) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '未找到指定批注。该图片共 ${target.annotations.length} 条批注。',
        isError: true,
      );
    }

    final updatedList = target.annotations
        .where((a) => a.id != ann.id)
        .toList();
    final ok = await writeAnnotations(target.id, updatedList);
    if (!ok) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '批注写入失败，图片可能已被移除。',
        isError: true,
      );
    }

    return ToolResult(
      toolCallId: toolCallId,
      toolName: 'remove_image_annotation',
      content:
          '已删除图片 (索引 $index) 的批注「[${ann.type.label}] ${ann.note.trim().isEmpty ? '（无文字）' : ann.note.trim()}」。当前剩余 ${updatedList.length} 条批注。',
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
