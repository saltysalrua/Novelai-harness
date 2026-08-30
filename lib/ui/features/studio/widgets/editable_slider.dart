import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

/// 官方风格数值微调滑块：左侧数字输入框 + 右侧大尺寸滑块，双向实时联动。
/// 整型与浮点型共用同一实现 (fractionDigits = 0 时为整数模式，滑块带刻度)。
class _EditableSliderCore extends StatefulWidget {
  final String title;
  final double value;
  final double min;
  final double max;
  final int fractionDigits;
  final ValueChanged<double> onChanged;

  const _EditableSliderCore({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.fractionDigits,
    required this.onChanged,
  });

  @override
  State<_EditableSliderCore> createState() => _EditableSliderCoreState();
}

class _EditableSliderCoreState extends State<_EditableSliderCore> {
  late final TextEditingController _controller;

  String _format(double v) => v.toStringAsFixed(widget.fractionDigits);

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _format(widget.value));
  }

  @override
  void didUpdateWidget(_EditableSliderCore oldWidget) {
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            // 左侧单层平整输入框
            Container(
              width: 60,
              height: 36,
              decoration: BoxDecoration(
                color: AppTheme.pureWhite,
                borderRadius: BorderRadius.circular(AppTheme.radiusButton),
                border: Border.all(color: AppTheme.border),
              ),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: TextField(
                controller: _controller,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                  color: AppTheme.textPrimary,
                ),
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                ),
                onSubmitted: _submit,
              ),
            ),
            const SizedBox(width: 12),
            // 右侧大尺寸滑块
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 5.0,
                  activeTrackColor: AppTheme.notionBlue,
                  inactiveTrackColor: AppTheme.border,
                  thumbColor: AppTheme.pureWhite,
                  overlayColor: AppTheme.notionBlue.withValues(alpha: 0.12),
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 8.0,
                    elevation: 2.0,
                  ),
                ),
                child: Slider(
                  value: widget.value.clamp(widget.min, widget.max),
                  min: widget.min,
                  max: widget.max,
                  divisions: widget.fractionDigits == 0
                      ? (widget.max - widget.min).round()
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

/// 整型数值微调滑块 (如 Steps)
class EditableSliderInt extends StatelessWidget {
  final String title;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  const EditableSliderInt({
    super.key,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _EditableSliderCore(
      title: title,
      value: value.toDouble(),
      min: min.toDouble(),
      max: max.toDouble(),
      fractionDigits: 0,
      onChanged: (v) => onChanged(v.round()),
    );
  }
}

/// 浮点型数值微调滑块 (如 Prompt Guidance / Rescale)
class EditableSliderDouble extends StatelessWidget {
  final String title;
  final double value;
  final double min;
  final double max;
  final int fractionDigits;
  final ValueChanged<double> onChanged;

  const EditableSliderDouble({
    super.key,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.fractionDigits,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _EditableSliderCore(
      title: title,
      value: value,
      min: min,
      max: max,
      fractionDigits: fractionDigits,
      onChanged: onChanged,
    );
  }
}
