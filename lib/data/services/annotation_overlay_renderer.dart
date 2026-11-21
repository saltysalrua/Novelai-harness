import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../core/harness/tools/annotation_tools.dart'
    show AnnotationOverlayRenderResult;
import '../../core/harness/tools/canvas_view_tool.dart'
    show OverlayRenderResult;
import '../models/novelai_models.dart';

/// 将批注覆盖层 (选区边框、锚点、编号徽章与标签) 离屏绘制到图像字节上。
Future<AnnotationOverlayRenderResult> renderImageWithAnnotationOverlay(
  Uint8List imageBytes,
  List<ImageAnnotation> annotations, {
  int maxDimension = 1536,
  bool whiteBackground = false,
}) async {
  ui.Codec? codec;
  ui.Image? source;
  ui.Picture? picture;
  ui.Image? outImage;
  try {
    codec = await ui.instantiateImageCodec(imageBytes);
    final frame = await codec.getNextFrame();
    source = frame.image;

    final longSide = math.max(source.width, source.height);
    final scale = longSide > maxDimension ? maxDimension / longSide : 1.0;
    final outW = math.max(1, (source.width * scale).round());
    final outH = math.max(1, (source.height * scale).round());

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      ui.Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble()),
    );

    if (whiteBackground) {
      canvas.drawRect(
        ui.Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble()),
        ui.Paint()..color = const ui.Color(0xFFFFFFFF),
      );
    }

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
          final noteText =
              ann.note.trim().isNotEmpty ? ann.note.trim() : '整图批注';
          _drawGlobalBanner(canvas, canvasSize, indexNum, noteText, color, i);
          break;
      }
    }

    picture = recorder.endRecording();
    outImage = await picture.toImage(outW, outH);
    final data = await outImage.toByteData(format: ui.ImageByteFormat.png);

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
  } finally {
    outImage?.dispose();
    picture?.dispose();
    source?.dispose();
    codec?.dispose();
  }
}

void _drawPinBadge(
  ui.Canvas canvas,
  ui.Offset center,
  double diameter,
  int number,
  ui.Color color,
) {
  canvas.drawCircle(
    center,
    diameter / 2 + 2.5,
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );
  canvas.drawCircle(center, diameter / 2, ui.Paint()..color = color);
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
  );
  try {
    painter.layout();
    painter.paint(
      canvas,
      center - ui.Offset(painter.width / 2, painter.height / 2),
    );
  } finally {
    painter.dispose();
  }
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
  );
  try {
    painter.layout();

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
  } finally {
    painter.dispose();
  }
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
  );
  try {
    painter.layout();

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
  } finally {
    painter.dispose();
  }
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
Future<OverlayRenderResult> renderImageWithCharacterOverlay(
  Uint8List imageBytes,
  NaiGenerationParams params, {
  int maxDimension = 1536,
  bool whiteBackground = false,
}) async {
  ui.Codec? codec;
  ui.Image? source;
  ui.Picture? picture;
  ui.Image? outImage;
  try {
    codec = await ui.instantiateImageCodec(imageBytes);
    final frame = await codec.getNextFrame();
    source = frame.image;

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

    if (whiteBackground) {
      canvas.drawRect(
        ui.Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble()),
        ui.Paint()..color = const ui.Color(0xFFFFFFFF),
      );
    }

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

        final display = resolveCharacterAnchorDisplay(
          character.copyWith(prompt: params.textForAgent(character.prompt)),
        );

        canvas.drawCircle(
          ui.Offset(cx, cy),
          anchorDiameter / 2 + borderWidth,
          ui.Paint()..color = const ui.Color(0xFFFFFFFF),
        );
        canvas.drawCircle(
          ui.Offset(cx, cy),
          anchorDiameter / 2,
          ui.Paint()..color = display.color,
        );

        _paintText(
          canvas,
          '${i + 1}',
          ui.Offset(cx, cy),
          fontSize: fontSize,
          color: const ui.Color(0xFFFFFFFF),
          bold: true,
        );

        if (display.label.isNotEmpty) {
          _paintLabelBadge(
            canvas,
            size,
            display.label,
            cx,
            cy + anchorDiameter,
          );
        }
      }
    }

    picture = recorder.endRecording();
    outImage = await picture.toImage(outW, outH);
    final data = await outImage.toByteData(format: ui.ImageByteFormat.png);

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
  } finally {
    outImage?.dispose();
    picture?.dispose();
    source?.dispose();
    codec?.dispose();
  }
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
  );
  try {
    painter.layout();
    painter.paint(
      canvas,
      center - ui.Offset(painter.width / 2, painter.height / 2),
    );
  } finally {
    painter.dispose();
  }
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
  );
  try {
    painter.layout();

    const padH = 6.0;
    const padV = 3.0;
    const gap = 4.0;
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
      const ui.Radius.circular(4),
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
  } finally {
    painter.dispose();
  }
}
