import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../data/services/config_service.dart' show seedColorText;
import '../context_l10n.dart';
import '../theme/app_tokens.dart';
import '../theme/theme_context_extensions.dart';
import 'app_dialog_scaffold.dart';
import 'app_transitions.dart';

/// 通用 HSV 取色器弹窗 (原子组件，无业务状态)
///
/// - 色相/饱和度/明度三条渐变滑杆 (直接拖动条带或滑块)；
/// - 预设色板一键选取；
/// - 十六进制 #RRGGBB 输入 (回车提交，失焦不吞字符)；
/// - 点「保存」返回所选颜色，取消/ESC 返回 null。
///
/// 返回值：`Future<Color?>`，由调用方决定如何应用 (主题种子色等)。
class AppColorPickerDialog extends StatefulWidget {
  /// 初始颜色 (缺省 Notion 蓝)
  final Color initialColor;

  /// 自定义弹窗标题 (未指定时使用通用「选择颜色」)
  final String? title;

  /// 自定义预设色板 (未指定时使用默认强调色预设)
  final List<Color>? presets;

  const AppColorPickerDialog({
    super.key,
    required this.initialColor,
    this.title,
    this.presets,
  });

  static Future<Color?> show(
    BuildContext context, {
    Color? initialColor,
    String? title,
    List<Color>? presets,
  }) {
    return AppDialogScaffold.show<Color>(
      context: context,
      builder: (ctx) => AppColorPickerDialog(
        initialColor: initialColor ?? const Color(0xFF0075DE),
        title: title,
        presets: presets,
      ),
    );
  }

  @override
  State<AppColorPickerDialog> createState() => _AppColorPickerDialogState();
}

class _AppColorPickerDialogState extends State<AppColorPickerDialog> {
  late HSVColor _hsv;
  late final TextEditingController _hexController;
  late final FocusNode _hexFocus;
  final AppErrorShakeController _hexShakeController = AppErrorShakeController();
  String? _hexError;

  /// 预设种子色板 (Notion 语义色系 + 常用 MD3 种子色)
  static const List<Color> _kPresets = [
    Color(0xFF0075DE), // Notion 蓝
    Color(0xFF097FE8), // 信号蓝
    Color(0xFF3949AB), // 靛蓝
    Color(0xFF7B1FA2), // 紫
    Color(0xFFF06292), // 粉
    Color(0xFFF64932), // Coral
    Color(0xFFE32D14), // 朱红
    Color(0xFFE89D01), // 藏红花
    Color(0xFFFFB110), // 万寿菊
    Color(0xFF0F9960), // 成功绿
    Color(0xFF00897B), // 青
    Color(0xFFB18164), // 摩卡棕
    Color(0xFF607D8B), // 蓝灰
    Color(0xFF212121), // 墨
  ];

  Color get _currentColor => _hsv.toColor();

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initialColor);
    _hexController = TextEditingController(
      text: seedColorText(_currentColor.toARGB32()),
    );
    _hexFocus = FocusNode();
    // 失焦时提交输入框内容 (合法则采纳，非法则回显当前色)
    _hexFocus.addListener(_handleHexFocusChange);
  }

  @override
  void dispose() {
    _hexShakeController.dispose();
    _hexFocus.removeListener(_handleHexFocusChange);
    _hexFocus.dispose();
    _hexController.dispose();
    super.dispose();
  }

  void _handleHexFocusChange() {
    if (_hexFocus.hasFocus) return;
    _submitHex();
  }

  void _update(HSVColor next) {
    setState(() {
      _hsv = next;
      _hexError = null;
      // 输入框未持有时同步回显当前色；持有时不打断输入
      if (!_hexFocus.hasFocus) {
        _hexController.text = seedColorText(_currentColor.toARGB32()) ?? '';
      }
    });
  }

  void _submitHex() {
    final parsed = parseHexField(_hexController.text);
    if (parsed == null) {
      setState(() {
        _hexError = context.l10n.colorPickerHexInvalid;
      });
      _hexShakeController.shake();
      return;
    }
    _update(HSVColor.fromColor(parsed));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.colors;
    final current = _currentColor;

    final effectivePresets = widget.presets ?? _kPresets;

    return AppDialogScaffold(
      title: widget.title ?? l10n.colorPickerTitle,
      width: 420,
      onClose: () => Navigator.of(context).pop(),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          style: OutlinedButton.styleFrom(
            foregroundColor: colors.textSecondary,
            side: BorderSide(color: colors.borderDefault),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
          ),
          child: Text(l10n.cancel),
        ),
        const SizedBox(width: AppSpacing.sm),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(current),
          style: FilledButton.styleFrom(
            backgroundColor: colors.primary,
            foregroundColor: colors.onPrimary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
          ),
          child: Text(l10n.save),
        ),
      ],
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 当前颜色预览 + 十六进制文本
              Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: current,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(color: colors.borderDefault),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppErrorShake(
                          controller: _hexShakeController,
                          child: _HexField(
                            controller: _hexController,
                            focusNode: _hexFocus,
                            errorText: _hexError,
                            onSubmitted: (_) => _submitHex(),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'H ${_hsv.hue.round()}°  '
                          'S ${(_hsv.saturation * 100).round()}%  '
                          'V ${(_hsv.value * 100).round()}%',
                          style: context.typography.bodySmall?.copyWith(
                            color: colors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              // HSV 渐变滑杆
              _GradientSlider(
                label: l10n.colorPickerHue,
                value: _hsv.hue,
                min: 0,
                max: 360,
                unit: '°',
                gradient: const [
                  Color(0xFFFF0000),
                  Color(0xFFFFFF00),
                  Color(0xFF00FF00),
                  Color(0xFF00FFFF),
                  Color(0xFF0000FF),
                  Color(0xFFFF00FF),
                  Color(0xFFFF0000),
                ],
                onChanged: (v) =>
                    _update(_hsv.withHue(v.clamp(0.0, 360.0).toDouble())),
              ),
              const SizedBox(height: AppSpacing.md),
              _GradientSlider(
                label: l10n.colorPickerSaturation,
                value: _hsv.saturation,
                min: 0,
                max: 1,
                gradient: [
                  _hsv.withSaturation(0).toColor(),
                  _hsv.withSaturation(1).toColor(),
                ],
                onChanged: (v) =>
                    _update(_hsv.withSaturation(v.clamp(0.0, 1.0).toDouble())),
              ),
              const SizedBox(height: AppSpacing.md),
              _GradientSlider(
                label: l10n.colorPickerBrightness,
                value: _hsv.value,
                min: 0,
                max: 1,
                gradient: [
                  _hsv.withValue(0).toColor(),
                  _hsv.withValue(1).toColor(),
                ],
                onChanged: (v) =>
                    _update(_hsv.withValue(v.clamp(0.0, 1.0).toDouble())),
              ),
              const SizedBox(height: AppSpacing.lg),
              // 预设色板
              Text(
                l10n.colorPickerPresets,
                style: context.typography.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final preset in effectivePresets)
                    _PresetSwatch(
                      color: preset,
                      selected: preset.toARGB32() == current.toARGB32(),
                      onTap: () => _update(HSVColor.fromColor(preset)),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 十六进制输入框 (回车提交；错误态红边)
class _HexField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String? errorText;
  final ValueChanged<String> onSubmitted;

  const _HexField({
    required this.controller,
    required this.focusNode,
    required this.errorText,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: 140,
      height: 34,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        onSubmitted: onSubmitted,
        style: TextStyle(
          fontSize: 13,
          color: colors.textPrimary,
          fontFamily: 'MiSans',
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            borderSide: BorderSide(
              color: errorText != null ? colors.error : colors.borderDefault,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            borderSide: BorderSide(color: colors.primary, width: 1.5),
          ),
        ),
      ),
    );
  }
}

/// 预设色块
class _PresetSwatch extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _PresetSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(
            color: selected ? colors.textPrimary : colors.borderDefault,
            width: selected ? 2 : 1,
          ),
        ),
      ),
    );
  }
}

/// 渐变条滑杆 (条带即取值范围，拖动条带或圆形手柄调值)
class _GradientSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final String? unit;
  final List<Color> gradient;
  final ValueChanged<double> onChanged;

  const _GradientSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.gradient,
    required this.onChanged,
    this.unit,
  });

  double _fraction(double v) => ((v - min) / (max - min)).clamp(0.0, 1.0);

  double _fromFraction(double f) => min + f * (max - min);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fraction = _fraction(value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: context.typography.bodySmall?.copyWith(
                color: colors.textSecondary,
              ),
            ),
            Text(
              unit == null
                  ? '${(fraction * 100).round()}%'
                  : '${value.round()}$unit',
              style: context.typography.bodySmall?.copyWith(
                color: colors.textMuted,
                fontSize: 11,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return SizedBox(
              height: 22,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) =>
                    onChanged(_fromFraction(details.localPosition.dx / width)),
                onHorizontalDragUpdate: (details) => onChanged(
                  _fromFraction(
                    (_fraction(value) + details.delta.dx / width).clamp(
                      0.0,
                      1.0,
                    ),
                  ),
                ),
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    // 渐变条带
                    Positioned.fill(
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 7),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: gradient),
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          border: Border.all(color: colors.borderDefault),
                        ),
                      ),
                    ),
                    // 圆形手柄
                    Positioned(
                      left: (fraction * width - 9).clamp(
                        0.0,
                        math.max(width - 18, 0.0),
                      ),
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: colors.borderHover,
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// 解析十六进制输入 (#RRGGBB / RRGGBB，大小写不限)；非法返回 null
Color? parseHexField(String raw) {
  final text = raw.trim();
  final hex = text.startsWith('#') ? text.substring(1) : text;
  if (hex.length != 6) return null;
  final rgb = int.tryParse(hex, radix: 16);
  if (rgb == null) return null;
  return Color(0xFF000000 | rgb);
}
