import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import '../theme/theme_context_extensions.dart';

/// 统一双向绑定微调数值滑块组件
///
/// 左侧数字输入框 + 右侧连续/分段滑块，支持整型与浮点型，
/// 具备自动范围钳制、步长吸附、可选刻度线与单位后缀支持。
///
/// 输入框同时支持回车提交与**失焦自动提交**（点击别处不丢输入）；
/// 滑块手柄规格 (radius 8 + 白色浮起)；
/// 当步长不能整除范围时自动退化为连续滑块（无刻度），避免刻度不均。
class AppNumberSlider extends StatefulWidget {
  /// 标题；传 null 时隐藏标题行 (嵌入 AppSettingTile.bottomChild 等容器内使用)
  final String? title;
  final double value;
  final double min;
  final double max;
  final int fractionDigits;
  final double? step;
  final String? unit;
  final ValueChanged<double> onChanged;

  const AppNumberSlider({
    super.key,
    this.title,
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
    String? title,
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
  late final FocusNode _focusNode;

  String _format(double v) => v.toStringAsFixed(widget.fractionDigits);

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _format(widget.value));
    _focusNode = FocusNode();
    // 失焦自动提交：鼠标点击别处不再丢失输入框内容
    _focusNode.addListener(_handleFocusChange);
  }

  void _handleFocusChange() {
    if (!_focusNode.hasFocus && mounted) {
      _submit(_controller.text);
    }
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
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// 将原始值吸附到步长网格 (步长未整除范围时仍保证吸附正确)
  double _snapToStep(double v) {
    final step = widget.step;
    if (step == null || step <= 0) return v;
    final span = widget.max - widget.min;
    final maxIndex = (span / step).floor();
    final index = ((v - widget.min) / step).round().clamp(0, maxIndex);
    return (widget.min + index * step).clamp(widget.min, widget.max);
  }

  void _submit(String val) {
    final parsed = double.tryParse(val);
    if (parsed != null) {
      final snapped = _snapToStep(parsed);
      final clamped = double.parse(
        snapped
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
    final step = widget.step;
    // 仅当步长能整除范围时才显示均匀刻度；否则退化为连续滑块，
    // 由 onChanged 手动吸附步长，杜绝「刻度不均/尾格缺失」。
    int? divisions;
    if (step != null && step > 0) {
      final count = (widget.max - widget.min) / step;
      divisions = (count - count.round()).abs() < 1e-6 ? count.round() : null;
    } else if (widget.fractionDigits == 0) {
      final span = widget.max - widget.min;
      divisions = (span - span.round()).abs() < 1e-6 && span.round() > 0
          ? span.round()
          : null;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.title != null) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.title!,
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
                    fontSize: 12,
                    color: colors.textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
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
                focusNode: _focusNode,
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
                onSubmitted: (v) {
                  _submit(v);
                  // 提交后释放焦点，让全局快捷键恢复生效
                  _focusNode.unfocus();
                },
              ),
            ),
            const SizedBox(width: AppSpacing.md),

            // 右侧连续滑块 (手柄 radius 8 + 白色浮起)
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: colors.primary,
                  inactiveTrackColor: colors.mutedBackground,
                  thumbColor: Colors.white,
                  overlayColor: colors.primary.withValues(alpha: 0.12),
                  trackHeight: 4,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 8,
                    elevation: 2,
                  ),
                ),
                child: Slider(
                  value: _snapToStep(
                    widget.value,
                  ).clamp(widget.min, widget.max),
                  min: widget.min,
                  max: widget.max,
                  divisions: (divisions != null && divisions > 0)
                      ? divisions
                      : null,
                  onChanged: (v) {
                    final snapped = _snapToStep(v);
                    final rounded = double.parse(
                      snapped.toStringAsFixed(widget.fractionDigits),
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
