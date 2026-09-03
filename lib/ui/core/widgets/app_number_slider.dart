import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import '../theme/theme_context_extensions.dart';

/// 统一双向绑定微调数值滑块组件
///
/// 左侧数字输入框 + 右侧连续/分段滑块，支持整型与浮点型，
/// 具备自动范围钳制、步长吸附、可选刻度线与单位后缀支持。
class AppNumberSlider extends StatefulWidget {
  final String title;
  final double value;
  final double min;
  final double max;
  final int fractionDigits;
  final double? step;
  final String? unit;
  final ValueChanged<double> onChanged;

  const AppNumberSlider({
    super.key,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    this.fractionDigits = 0,
    this.step,
    this.unit,
    required this.onChanged,
  });

  /// 整型滑块便捷工厂
  factory AppNumberSlider.integer({
    Key? key,
    required String title,
    required int value,
    required int min,
    required int max,
    int step = 1,
    String? unit,
    required ValueChanged<int> onChanged,
  }) {
    return AppNumberSlider(
      key: key,
      title: title,
      value: value.toDouble(),
      min: min.toDouble(),
      max: max.toDouble(),
      fractionDigits: 0,
      step: step.toDouble(),
      unit: unit,
      onChanged: (v) => onChanged(v.round()),
    );
  }

  @override
  State<AppNumberSlider> createState() => _AppNumberSliderState();
}

class _AppNumberSliderState extends State<AppNumberSlider> {
  late final TextEditingController _controller;

  String _format(double v) => v.toStringAsFixed(widget.fractionDigits);

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _format(widget.value));
  }

  @override
  void didUpdateWidget(AppNumberSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      final parsed = double.tryParse(_controller.text);
      if (parsed != widget.value) {
        _controller.text = _format(widget.value);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(String val) {
    final parsed = double.tryParse(val);
    if (parsed != null) {
      final clamped = double.parse(
        parsed
            .clamp(widget.min, widget.max)
            .toStringAsFixed(widget.fractionDigits),
      );
      _controller.text = _format(clamped);
      widget.onChanged(clamped);
    } else {
      _controller.text = _format(widget.value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final divisions = widget.step != null && widget.step! > 0
        ? ((widget.max - widget.min) / widget.step!).round()
        : (widget.fractionDigits == 0
            ? (widget.max - widget.min).round()
            : null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
            ),
            if (widget.unit != null)
              Text(
                widget.unit!,
                style: TextStyle(
                  fontSize: 11.5,
                  color: colors.textMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            // 左侧单层平整微调输入框
            Container(
              width: 64,
              height: 36,
              decoration: BoxDecoration(
                color: colors.cardBackground,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: colors.borderDefault),
              ),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: TextField(
                controller: _controller,
                keyboardType: TextInputType.numberWithOptions(
                  decimal: widget.fractionDigits > 0,
                  signed: widget.min < 0,
                ),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  isDense: true,
                  filled: false,
                ),
                onSubmitted: _submit,
              ),
            ),
            const SizedBox(width: AppSpacing.md),

            // 右侧连续滑块
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: colors.primary,
                  inactiveTrackColor: colors.mutedBackground,
                  thumbColor: colors.primary,
                  overlayColor: colors.primary.withValues(alpha: 0.12),
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                ),
                child: Slider(
                  value: widget.value.clamp(widget.min, widget.max),
                  min: widget.min,
                  max: widget.max,
                  divisions: (divisions != null && divisions > 0)
                      ? divisions
                      : null,
                  onChanged: (v) {
                    final rounded = double.parse(
                      v.toStringAsFixed(widget.fractionDigits),
                    );
                    _controller.text = _format(rounded);
                    widget.onChanged(rounded);
                  },
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
