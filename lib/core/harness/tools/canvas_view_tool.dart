import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../../data/models/novelai_models.dart';
import '../../../data/services/anlas_calculator.dart';
import '../types.dart';
import 'agent_tool.dart';
import 'vision_image_codec.dart';

/// 历史图片列表获取器 (从新到旧排序，索引 0 为最新生成的一张)
typedef CanvasHistoryGetter = List<NaiGeneratedImage> Function();

/// 视觉能力检查器 (当前对话模型是否支持图像输入)
typedef ModelVisionChecker = bool Function();

/// 覆盖层渲染结果
class OverlayRenderResult {
  final Uint8List bytes;
  final int width;
  final int height;
  final bool overlayApplied;

  const OverlayRenderResult({
    required this.bytes,
    required this.width,
    required this.height,
    required this.overlayApplied,
  });
}

/// 角色性别推导：粉色=女性 / 蓝色=男性 / 紫色=其他
/// (与画板 UI 的 CharacterPositionOverlay 锚点配色语义一致)
({ui.Color color, String label}) resolveCharacterAnchorDisplay(
  NaiCharacterPrompt character,
) {
  final tags = character.prompt
      .split(',')
      .map((t) => t.trim().toLowerCase())
      .where((t) => t.isNotEmpty)
      .toList();

  final isFemale = tags.any(
    (t) =>
        t == '1girl' ||
        t == 'girl' ||
        t == 'female' ||
        t == 'woman' ||
        t.contains('girl'),
  );
  final isMale = tags.any(
    (t) =>
        t == '1boy' ||
        t == 'boy' ||
        t == 'male' ||
        t == 'man' ||
        t.contains('boy'),
  );

  final color = isFemale
      ? const ui.Color(0xFFEC4899)
      : isMale
      ? const ui.Color(0xFF3B82F6)
      : const ui.Color(0xFF8B5CF6);

  var label = character.name.trim();
  if (label.isEmpty || RegExp(r'^角色 \d+$').hasMatch(label)) {
    if (tags.isNotEmpty) label = tags.first;
  }
  return (color: color, label: label);
}

/// 将角色位置覆盖层 (锚点编号 + 名称标签 + 参考网格) 渲染到画板图片上。
///
/// 渲染语义与画板 UI 的 CharacterPositionOverlay 一致：
/// - 仅渲染启用角色的锚点，位置取 resolveCenter (自定义坐标优先，否则自动布局)；
/// - V5 自由定位：锚点落在连续坐标处，叠加中心十字参考线；
/// - V4/V4.5：锚点吸附 5x5 网格格心，叠加网格线；
/// - 超过 [maxDimension] 的长边会被等比压缩，控制视觉 Token 消耗。
Future<OverlayRenderResult> renderImageWithCharacterOverlay(
  Uint8List imageBytes,
  NaiGenerationParams params, {
  int maxDimension = 1536,
}) async {
  final codec = await ui.instantiateImageCodec(imageBytes);
  final frame = await codec.getNextFrame();
  final source = frame.image;

  final longSide = math.max(source.width, source.height);
  final scale = longSide > maxDimension ? maxDimension / longSide : 1.0;
  final outW = math.max(1, (source.width * scale).round());
  final outH = math.max(1, (source.height * scale).round());

  final enabledCharacters = params.characterPrompts
      .where((c) => c.enabled)
      .toList();
  final useGrid = !params.model.supportsFreeCharacterPositioning;

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(
    recorder,
    ui.Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble()),
  );

  // 1. 底图
  canvas.drawImageRect(
    source,
    ui.Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
    ui.Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble()),
    ui.Paint()..filterQuality = ui.FilterQuality.medium,
  );

  final size = ui.Size(outW.toDouble(), outH.toDouble());

  // 2. 参考层 (V5 十字线 / V4 网格)
  final guidePaint = ui.Paint()
    ..color = const ui.Color(0x55FFFFFF)
    ..strokeWidth = math.max(1.0, size.shortestSide * 0.002);
  if (useGrid) {
    for (var i = 1; i < 5; i++) {
      canvas.drawLine(
        ui.Offset(size.width * i / 5, 0),
        ui.Offset(size.width * i / 5, size.height),
        guidePaint,
      );
      canvas.drawLine(
        ui.Offset(0, size.height * i / 5),
        ui.Offset(size.width, size.height * i / 5),
        guidePaint,
      );
    }
  } else {
    canvas.drawLine(
      ui.Offset(size.width / 2, 0),
      ui.Offset(size.width / 2, size.height),
      guidePaint,
    );
    canvas.drawLine(
      ui.Offset(0, size.height / 2),
      ui.Offset(size.width, size.height / 2),
      guidePaint,
    );
  }

  // 3. 角色锚点
  if (enabledCharacters.isNotEmpty) {
    final anchorDiameter = (size.width * 0.032).clamp(22.0, 56.0);
    final borderWidth = math.max(2.0, anchorDiameter * 0.085);
    final fontSize = anchorDiameter * 0.42;

    for (var i = 0; i < enabledCharacters.length; i++) {
      final character = enabledCharacters[i];
      final center = character.resolveCenter(i, enabledCharacters.length);

      double cx;
      double cy;
      if (useGrid) {
        final col = (center.x * 4).round().clamp(0, 4);
        final row = (center.y * 4).round().clamp(0, 4);
        cx = (col + 0.5) / 5 * size.width;
        cy = (row + 0.5) / 5 * size.height;
      } else {
        cx = center.x * size.width;
        cy = center.y * size.height;
      }

      final display = resolveCharacterAnchorDisplay(character);

      // 描边圆 + 填充圆
      canvas.drawCircle(
        ui.Offset(cx, cy),
        anchorDiameter / 2 + borderWidth,
        ui.Paint()..color = ui.Color(0xFFFFFFFF),
      );
      canvas.drawCircle(
        ui.Offset(cx, cy),
        anchorDiameter / 2,
        ui.Paint()..color = display.color,
      );

      // 序号
      _paintText(
        canvas,
        '${i + 1}',
        ui.Offset(cx, cy),
        fontSize: fontSize,
        color: ui.Color(0xFFFFFFFF),
        bold: true,
      );

      // 名称标签 (锚点下方黑底白字，超边界自动内收)
      if (display.label.isNotEmpty) {
        _paintLabelBadge(canvas, size, display.label, cx, cy + anchorDiameter);
      }
    }
  }

  final picture = recorder.endRecording();
  final outImage = await picture.toImage(outW, outH);
  final data = await outImage.toByteData(format: ui.ImageByteFormat.png);
  source.dispose();
  outImage.dispose();

  final bytes = data?.buffer.asUint8List();
  if (bytes == null || bytes.isEmpty) {
    throw StateError('图片编码失败');
  }

  return OverlayRenderResult(
    bytes: bytes,
    width: outW,
    height: outH,
    overlayApplied: true,
  );
}

void _paintText(
  ui.Canvas canvas,
  String text,
  ui.Offset center, {
  required double fontSize,
  required ui.Color color,
  bool bold = false,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
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

void _paintLabelBadge(
  ui.Canvas canvas,
  ui.Size canvasSize,
  String label,
  double cx,
  double topY,
) {
  final fontSize = (canvasSize.width * 0.014).clamp(10.0, 20.0);
  final painter = TextPainter(
    text: TextSpan(
      text: label,
      style: TextStyle(
        color: const ui.Color(0xFFFFFFFF),
        fontSize: fontSize,
        fontWeight: FontWeight.w600,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  const padH = 6.0;
  const padV = 3.0;
  final gap = 4.0;
  final badgeW = painter.width + padH * 2;
  final badgeH = painter.height + padV * 2;
  final top = (topY + gap)
      .clamp(0.0, math.max(0.0, canvasSize.height - badgeH))
      .toDouble();
  final left = (cx - badgeW / 2)
      .clamp(0.0, math.max(0.0, canvasSize.width - badgeW))
      .toDouble();

  final rrect = ui.RRect.fromRectAndRadius(
    ui.Rect.fromLTWH(left, top, badgeW, badgeH),
    ui.Radius.circular(4),
  );
  canvas.drawRRect(rrect, ui.Paint()..color = const ui.Color(0xD9000000));
  canvas.drawRRect(
    rrect,
    ui.Paint()
      ..color = const ui.Color(0x40FFFFFF)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 1,
  );
  painter.paint(canvas, ui.Offset(left + padH, top + padV));
}

/// 画板历史图片查看工具：按索引 (0 为最新，从新到旧) 获取已生成的图片 (可叠加角色位置覆盖层) 供 Agent 视觉检查。
class ViewCanvasImageTool extends AgentTool {
  final CanvasHistoryGetter getHistory;
  final ModelVisionChecker isModelMultimodal;

  ViewCanvasImageTool({required this.getHistory, required this.isModelMultimodal})
    : super(
        name: 'view_canvas_image',
        label: '查看画板图片',
        description:
            '获取已生成的历史图片供视觉检查。通过 index 参数从新到旧指定图片（0 表示最新生成的一张，1 表示倒数第二张，以此类推。默认 0）。'
            '默认返回叠加了角色位置覆盖层的版本 (各启用角色的编号锚点与名称标签，'
            'V5 附带中心十字参考线，V4/V4.5 附带 5x5 网格)，便于核对多角色构图与布局；'
            '传入 with_overlay=false 可获取未处理的原图。'
            '返回的图片默认压缩到最长边 1024px 以控制视觉 Token；'
            '若因分辨率不足看不清细节（小字、纹理、面部瑕疵等），可传 full_resolution=true 获取未压缩的原始尺寸图片。'
            '注意：当前对话模型需要具备图像理解能力。',
        parameters: const {
          'type': 'object',
          'properties': {
            'index': {
              'type': 'integer',
              'description':
                  '要查看的图片索引（从新到旧排序，0 表示最新生成的一张，1 表示倒数第二张，以此类推。默认 0）。',
            },
            'with_overlay': {
              'type': 'boolean',
              'description': '是否叠加角色位置覆盖层 (默认 true)。false 时返回原图。',
            },
            'full_resolution': {
              'type': 'boolean',
              'description':
                  '是否返回未压缩的原始尺寸图片 (默认 false，压缩到最长边 1024px)。仅在压缩版看不清细节时使用，原图会消耗更多视觉 Token。',
            },
          },
        },
      );

  @override
  Future<ToolResult> execute(
    String toolCallId,
    Map<String, dynamic> args,
  ) async {
    if (!isModelMultimodal()) {
      return ToolResult(
        toolCallId: toolCallId,
        content:
            '当前对话模型不支持图像输入，无法查看图片。请提示用户在设置中切换到具备视觉能力的多模态模型 (如 GPT-4o、Gemini、Claude)。',
        isError: true,
      );
    }

    final history = getHistory();
    if (history.isEmpty) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '画板当前没有已生成的图片历史。请先生成图片后再查看。',
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
            '指定的图片索引 $index 超出范围。当前共有 ${history.length} 张历史图片，有效索引范围为 0 到 ${history.length - 1}（0 表示最新生成的一张，${history.length - 1} 表示最早的一张）。',
        isError: true,
      );
    }

    final targetImage = history[index];
    final imageBytes = targetImage.bytes;

    final params = targetImage.params;
    final withOverlay = args['with_overlay'] is bool
        ? args['with_overlay'] as bool
        : true;
    final fullResolution = args['full_resolution'] is bool
        ? args['full_resolution'] as bool
        : false;

    final enabledCharacters = params.characterPrompts
        .where((c) => c.enabled)
        .toList();

    Uint8List finalBytes = imageBytes;
    var overlayApplied = false;
    String? overlayNote;

    if (withOverlay && enabledCharacters.isNotEmpty) {
      if (params.model.maxCharacterPrompts <= 0) {
        overlayNote = '当前模型 (${params.model.label}) 不支持多角色提示词，已返回原图。';
      } else {
        try {
          final rendered = await renderImageWithCharacterOverlay(
            imageBytes,
            params,
          );
          finalBytes = rendered.bytes;
          overlayApplied = true;
        } catch (_) {
          overlayNote = '覆盖层渲染失败，已回退返回原图。';
        }
      }
    } else if (withOverlay) {
      overlayNote = '该图片生成时没有启用的角色提示词，已返回原图。';
    }

    // 视觉附件压缩：默认压到最长边 1024px 控制视觉 Token，
    // 模型看不清细节时可传 full_resolution=true 获取原图
    String mime = sniffImageMimeType(finalBytes);
    if (!fullResolution) {
      final compressed = await compressVisionImage(finalBytes);
      finalBytes = compressed.bytes;
      mime = compressed.mimeType;
    }

    final dims = await AnlasCalculator.decodeImageDimensions(imageBytes);

    final isLatest = index == 0;
    final timeStr = targetImage.createdAt
        .toIso8601String()
        .replaceAll('T', ' ')
        .split('.')
        .first;

    final lines = <String>[
      '已获取历史图片 (索引: $index, ${isLatest ? '最新生成' : '从新到旧第 ${index + 1} 张'}，共 ${history.length} 张)${overlayApplied ? ' (已叠加角色位置覆盖层)' : ''}：',
      '• 索引编号: $index (${isLatest ? '最新图片' : '从新到旧第 ${index + 1} 张'})',
      '• 生成时间: $timeStr',
      if (targetImage.seed >= 0) '• 随机种子: ${targetImage.seed}',
      '• 图片尺寸: ${dims?.width ?? params.width}x${dims?.height ?? params.height}',
      '• 绘图模型: ${params.model.label}',
      '• 位置模式: ${params.characterAiPosition ? 'AI 自动布局 (AI\'s Choice)' : '自定义定位 (use_coords)'}',
      if (overlayApplied) ...[
        '• 启用角色: ${enabledCharacters.length} 个，锚点编号对应启用顺序',
        '• 锚点配色: 粉色=女性角色, 蓝色=男性角色, 紫色=其他；标签为角色名',
        if (!params.model.supportsFreeCharacterPositioning)
          '• V4/V4.5 网格模式: 锚点吸附到 5x5 网格格心',
      ],
      if (overlayNote != null) '• $overlayNote',
      fullResolution
          ? '• 本次为原始尺寸图片 (未压缩)。'
          : '• 本次附件已压缩到最长边 1024px。若看不清细节（小字、纹理等），请再次调用本工具并传 full_resolution: true 获取原图。',
      '图片已作为附件随本条结果返回，请直接查看图片内容进行检查。',
    ];

    return ToolResult(
      toolCallId: toolCallId,
      content: lines.join('\n'),
      imageBase64: base64Encode(finalBytes),
      imageMimeType: mime,
    );
  }
}
