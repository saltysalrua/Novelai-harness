import 'dart:math';
import 'package:flutter/material.dart';
import '../../../../data/models/novelai_models.dart';
import '../../../core/theme/app_theme.dart';

/// Notion 浅色风格与 2D 可视化交互手写板相结合的分辨率选择器
class ResolutionPadPicker extends StatefulWidget {
  final int width;
  final int height;
  final bool isOpusFree;
  final ValueChanged<({int width, int height})> onChanged;

  const ResolutionPadPicker({
    super.key,
    required this.width,
    required this.height,
    this.isOpusFree = false,
    required this.onChanged,
  });

  @override
  State<ResolutionPadPicker> createState() => _ResolutionPadPickerState();
}

class _ResolutionPadPickerState extends State<ResolutionPadPicker> {
  static const int _snap = 64;
  static const int _padMax = 2048;

  String? _dragMode; // 'corner', 'top', 'right', 'both'

  late TextEditingController _widthController;
  late TextEditingController _heightController;

  @override
  void initState() {
    super.initState();
    _widthController = TextEditingController(text: '${widget.width}');
    _heightController = TextEditingController(text: '${widget.height}');
  }

  @override
  void didUpdateWidget(ResolutionPadPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.width != widget.width) {
      _widthController.text = '${widget.width}';
    }
    if (oldWidget.height != widget.height) {
      _heightController.text = '${widget.height}';
    }
  }

  @override
  void dispose() {
    _widthController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  void _applyDimensions(int w, int h) {
    final clampedW = ((w / _snap).round() * _snap).clamp(_snap, _padMax);
    final clampedH = ((h / _snap).round() * _snap).clamp(_snap, _padMax);
    _widthController.text = '$clampedW';
    _heightController.text = '$clampedH';
    widget.onChanged((width: clampedW, height: clampedH));
  }

  void _swapDimensions() {
    _applyDimensions(widget.height, widget.width);
  }

  String _computeRatioAndMp() {
    final w = widget.width;
    final h = widget.height;
    final mp = (w * h) / 1000000.0;

    int gcd(int a, int b) => b == 0 ? a : gcd(b, a % b);
    final g = gcd(w, h);
    final ratioW = (w / g).round();
    final ratioH = (h / g).round();

    String ratioText = '$ratioW:$ratioH';
    if ((ratioW == 13 && ratioH == 19) || (w == 832 && h == 1216)) {
      ratioText = '13:19';
    } else if (ratioW == 19 && ratioH == 13 || (w == 1216 && h == 832)) {
      ratioText = '19:13';
    } else if (ratioW == 17 && ratioH == 30) {
      ratioText = '9:16';
    }

    return '$ratioText · ${mp.toStringAsFixed(2)}MP';
  }

  @override
  Widget build(BuildContext context) {
    final category = ResolutionCategory.fromDimensions(widget.width, widget.height);
    final orientation = ResolutionOrientation.fromDimensions(widget.width, widget.height);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题行与 Opus 免费徽章
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              '分辨率',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            if (widget.isOpusFree)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                ),
                child: const Text(
                  'Opus 免费',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),

        // 控制块 1：官方预设分类选择器 + 舒适大尺寸方向与交换按钮 (36x38)
        Row(
          children: [
            // 官方预设分类下拉框
            Expanded(
              child: Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: AppTheme.pureWhite,
                  borderRadius: BorderRadius.circular(AppTheme.radiusButton),
                  border: Border.all(color: AppTheme.border),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<ResolutionCategory>(
                    value: category,
                    isExpanded: true,
                    dropdownColor: AppTheme.pureWhite,
                    items: ResolutionCategory.values.map((cat) {
                      return DropdownMenuItem(
                        value: cat,
                        child: Text(
                          cat.label,
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
                        ),
                      );
                    }).toList(),
                    onChanged: (cat) {
                      if (cat != null && cat != ResolutionCategory.custom) {
                        var targetOrientation = orientation;
                        if (!ResolutionPresetHelper.supportsSquare(cat) && targetOrientation == ResolutionOrientation.square) {
                          targetOrientation = ResolutionOrientation.landscape;
                        }
                        final (w, h) = ResolutionPresetHelper.getDimensions(cat, targetOrientation);
                        _applyDimensions(w, h);
                      }
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),

            // 方向按键组：横屏 / 竖屏 / 正方形 (标准 36x38 舒适可点击尺寸)
            _buildOrientationButton(
              icon: Icons.crop_landscape_rounded,
              tooltip: 'Landscape',
              isSelected: orientation == ResolutionOrientation.landscape,
              onTap: () {
                final cat = category == ResolutionCategory.custom ? ResolutionCategory.normal : category;
                final (w, h) = ResolutionPresetHelper.getDimensions(cat, ResolutionOrientation.landscape);
                _applyDimensions(w, h);
              },
            ),
            const SizedBox(width: 4),
            _buildOrientationButton(
              icon: Icons.crop_portrait_rounded,
              tooltip: 'Portrait',
              isSelected: orientation == ResolutionOrientation.portrait,
              onTap: () {
                final cat = category == ResolutionCategory.custom ? ResolutionCategory.normal : category;
                final (w, h) = ResolutionPresetHelper.getDimensions(cat, ResolutionOrientation.portrait);
                _applyDimensions(w, h);
              },
            ),
            const SizedBox(width: 4),
            _buildOrientationButton(
              icon: Icons.crop_square_rounded,
              tooltip: ResolutionPresetHelper.supportsSquare(category)
                  ? 'Square'
                  : 'Square (Wallpaper 暂无 1:1 比例)',
              isSelected: orientation == ResolutionOrientation.square,
              onTap: ResolutionPresetHelper.supportsSquare(category)
                  ? () {
                      final cat = category == ResolutionCategory.custom ? ResolutionCategory.normal : category;
                      final (w, h) = ResolutionPresetHelper.getDimensions(cat, ResolutionOrientation.square);
                      _applyDimensions(w, h);
                    }
                  : null,
            ),
            const SizedBox(width: 4),

            // 宽高快速交换按钮 (36x38)
            Tooltip(
              message: 'Swap',
              child: InkWell(
                onTap: _swapDimensions,
                borderRadius: BorderRadius.circular(AppTheme.radiusButton),
                child: Container(
                  width: 36,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppTheme.pureWhite,
                    borderRadius: BorderRadius.circular(AppTheme.radiusButton),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: const Icon(
                    Icons.swap_horiz_rounded,
                    size: 18,
                    color: AppTheme.graphite,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // 控制块 2：与控制块 1 紧邻放置的直接数值输入行 (高度 36，填满整行)
        Row(
          children: [
            // 宽度输入框 (带前缀 'W')
            Expanded(
              child: Container(
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.pureWhite,
                  borderRadius: BorderRadius.circular(AppTheme.radiusButton),
                  border: Border.all(color: AppTheme.border),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  children: [
                    const Text(
                      'W',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: TextField(
                        controller: _widthController,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'monospace',
                          color: AppTheme.textPrimary,
                        ),
                        decoration: const InputDecoration(
                          contentPadding: EdgeInsets.zero,
                          isDense: true,
                          border: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          enabledBorder: InputBorder.none,
                        ),
                        onSubmitted: (val) {
                          final parsed = int.tryParse(val) ?? widget.width;
                          _applyDimensions(parsed, widget.height);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                '×',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
            // 高度输入框 (带前缀 'H')
            Expanded(
              child: Container(
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.pureWhite,
                  borderRadius: BorderRadius.circular(AppTheme.radiusButton),
                  border: Border.all(color: AppTheme.border),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  children: [
                    const Text(
                      'H',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: TextField(
                        controller: _heightController,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'monospace',
                          color: AppTheme.textPrimary,
                        ),
                        decoration: const InputDecoration(
                          contentPadding: EdgeInsets.zero,
                          isDense: true,
                          border: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          enabledBorder: InputBorder.none,
                        ),
                        onSubmitted: (val) {
                          final parsed = int.tryParse(val) ?? widget.height;
                          _applyDimensions(widget.width, parsed);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),

            // 比例与像素总量徽章
            Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.paperWarmth,
                borderRadius: BorderRadius.circular(AppTheme.radiusButton),
                border: Border.all(color: AppTheme.border),
              ),
              child: Text(
                _computeRatioAndMp(),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // 3. 位于两个控制行下方的完整 2D 交互画板 (1:1 正方形开阔画布)
        AspectRatio(
          aspectRatio: 1.0,
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.paperWarmth, // Notion 浅色底色
              borderRadius: BorderRadius.circular(AppTheme.radiusCard),
              border: Border.all(color: AppTheme.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = constraints.biggest;
                const margin = 6.0;
                final side = min(size.width - margin * 2, size.height - margin * 2);
                final origin = Offset(
                  (size.width - side) / 2,
                  size.height - (size.height - side) / 2,
                );

                return GestureDetector(
                  onPanDown: (details) {
                    final pos = details.localPosition;
                    final hd = _getHandles(origin, side);
                    if (_hit(pos, hd.corner, 18)) {
                      _dragMode = 'corner';
                    } else if (_hit(pos, hd.top, 16)) {
                      _dragMode = 'top';
                    } else if (_hit(pos, hd.right, 16)) {
                      _dragMode = 'right';
                    } else {
                      _dragMode = 'corner';
                      _handlePos(pos, origin, side, _dragMode!);
                    }
                  },
                  onPanUpdate: (details) {
                    if (_dragMode != null) {
                      _handlePos(details.localPosition, origin, side, _dragMode!);
                    }
                  },
                  onPanEnd: (_) => _dragMode = null,
                  onPanCancel: () => _dragMode = null,
                  child: CustomPaint(
                    size: size,
                    painter: _NotionResolutionPadPainter(
                      width: widget.width,
                      height: widget.height,
                      padMax: _padMax,
                      origin: origin,
                      side: side,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOrientationButton({
    required IconData icon,
    required String tooltip,
    required bool isSelected,
    required VoidCallback? onTap,
  }) {
    final isEnabled = onTap != null;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusButton),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 36,
          height: 38,
          decoration: BoxDecoration(
            color: !isEnabled
                ? AppTheme.paperWarmth.withValues(alpha: 0.6)
                : isSelected
                    ? AppTheme.skyTint
                    : AppTheme.pureWhite,
            borderRadius: BorderRadius.circular(AppTheme.radiusButton),
            border: Border.all(
              color: !isEnabled
                  ? AppTheme.border.withValues(alpha: 0.5)
                  : isSelected
                      ? AppTheme.notionBlue
                      : AppTheme.border,
              width: isSelected && isEnabled ? 1.2 : 1,
            ),
          ),
          child: Icon(
            icon,
            size: 18,
            color: !isEnabled
                ? AppTheme.textMuted.withValues(alpha: 0.35)
                : isSelected
                    ? AppTheme.notionBlue
                    : AppTheme.graphite,
          ),
        ),
      ),
    );
  }

  ({Offset corner, Offset top, Offset right}) _getHandles(Offset origin, double side) {
    final fx = (widget.width / _padMax).clamp(0.0, 1.0);
    final fy = (widget.height / _padMax).clamp(0.0, 1.0);

    final corner = Offset(origin.dx + fx * side, origin.dy - fy * side);
    final top = Offset(origin.dx + (fx * side) / 2, corner.dy);
    final right = Offset(corner.dx, origin.dy - (fy * side) / 2);
    return (corner: corner, top: top, right: right);
  }

  bool _hit(Offset pt, Offset target, double radius) {
    return (pt - target).distance <= radius;
  }

  void _handlePos(Offset pt, Offset origin, double side, String mode) {
    final fx = ((pt.dx - origin.dx) / side).clamp(0.0, 1.0);
    final fy = ((origin.dy - pt.dy) / side).clamp(0.0, 1.0);

    final targetW = ((fx * _padMax / _snap).round() * _snap).clamp(_snap, _padMax);
    final targetH = ((fy * _padMax / _snap).round() * _snap).clamp(_snap, _padMax);

    if (mode == 'top') {
      _applyDimensions(widget.width, targetH);
    } else if (mode == 'right') {
      _applyDimensions(targetW, widget.height);
    } else {
      _applyDimensions(targetW, targetH);
    }
  }
}

/// Notion 浅色风格 2D 画布绘制器
class _NotionResolutionPadPainter extends CustomPainter {
  final int width;
  final int height;
  final int padMax;
  final Offset origin;
  final double side;

  _NotionResolutionPadPainter({
    required this.width,
    required this.height,
    required this.padMax,
    required this.origin,
    required this.side,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. 绘制浅色点阵 (Notion 浅灰细点)
    final dotPaint = Paint()..color = const Color(0xFFCCCAC4);
    final gridStep = (64 / padMax) * side;

    final cols = (padMax / 64).round();
    for (int i = 0; i <= cols; i++) {
      for (int j = 0; j <= cols; j++) {
        final dx = origin.dx + i * gridStep;
        final dy = origin.dy - j * gridStep;
        canvas.drawCircle(Offset(dx, dy), 0.8, dotPaint);
      }
    }

    // 2. 绘制原点坐标基准线
    final axisPaint = Paint()
      ..color = const Color(0xFFDCDAD5)
      ..strokeWidth = 1.0;
    canvas.drawLine(origin, Offset(origin.dx + side, origin.dy), axisPaint);
    canvas.drawLine(origin, Offset(origin.dx, origin.dy - side), axisPaint);

    // 3. 计算当前尺寸矩形几何
    final fx = (width / padMax).clamp(0.0, 1.0);
    final fy = (height / padMax).clamp(0.0, 1.0);

    final rectW = fx * side;
    final rectH = fy * side;
    final rect = Rect.fromLTWH(origin.dx, origin.dy - rectH, rectW, rectH);

    // 4. 填充 Notion 浅蓝半透明选区
    final fillPaint = Paint()
      ..color = const Color(0x280070F3)
      ..style = PaintingStyle.fill;
    canvas.drawRect(rect, fillPaint);

    // 5. 绘制选区外边框 (Notion Blue)
    final borderPaint = Paint()
      ..color = const Color(0xFF0070F3)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawRect(rect, borderPaint);

    // 6. 绘制选区尺寸徽标标签 (微白胶囊底色 + Notion 蓝等宽文字)
    final textSpan = TextSpan(
      text: '$width × $height',
      style: const TextStyle(
        color: Color(0xFF0070F3),
        fontSize: 9.5,
        fontWeight: FontWeight.w700,
        fontFamily: 'monospace',
      ),
    );
    final tp = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    )..layout();

    final badgeRect = Rect.fromLTWH(
      (rect.right - tp.width - 8).clamp(origin.dx + 4, size.width - tp.width - 8),
      (rect.bottom - tp.height - 6).clamp(0.0, size.height - tp.height - 6),
      tp.width + 6,
      tp.height + 4,
    );
    final rBadge = RRect.fromRectAndRadius(badgeRect, const Radius.circular(3));
    canvas.drawRRect(rBadge, Paint()..color = Colors.white.withValues(alpha: 0.92));
    canvas.drawRRect(
      rBadge,
      Paint()
        ..color = const Color(0x330070F3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
    tp.paint(canvas, Offset(badgeRect.left + 3, badgeRect.top + 2));

    // 7. 绘制交互手柄 Handle
    // (1) 顶部高度手柄 (Pink/Coral)
    final topHandle = Offset(origin.dx + rectW / 2, rect.top);
    canvas.drawCircle(topHandle, 4.5, Paint()..color = const Color(0xFFE16259));
    canvas.drawCircle(
      topHandle,
      4.5,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // (2) 右侧宽度手柄 (Notion Blue)
    final rightHandle = Offset(rect.right, origin.dy - rectH / 2);
    canvas.drawCircle(rightHandle, 4.5, Paint()..color = const Color(0xFF0070F3));
    canvas.drawCircle(
      rightHandle,
      4.5,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // (3) 右上角双向手柄 (White with Notion Blue Ring)
    final cornerHandle = Offset(rect.right, rect.top);
    // 投影
    canvas.drawCircle(
      cornerHandle.translate(0, 0.8),
      6.0,
      Paint()..color = Colors.black.withValues(alpha: 0.15),
    );
    canvas.drawCircle(cornerHandle, 6.0, Paint()..color = Colors.white);
    canvas.drawCircle(
      cornerHandle,
      6.0,
      Paint()
        ..color = const Color(0xFF0070F3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );
  }

  @override
  bool shouldRepaint(covariant _NotionResolutionPadPainter oldDelegate) {
    return oldDelegate.width != width ||
        oldDelegate.height != height;
  }
}
