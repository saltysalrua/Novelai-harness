import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../theme/app_tokens.dart';
import '../theme/theme_context_extensions.dart';

/// 统一双向绑定微调数值滑块组件
///
/// 左侧数字输入框 + 右侧连续滑块，支持整型与浮点型，
/// 具备自动范围钳制、步长吸附与单位后缀支持。
///
/// 输入框同时支持回车提交与**失焦自动提交**（点击别处不丢输入）；
/// 滑块手柄规格 (radius 8 + 白色浮起)；
/// 滑块始终以连续模式运行（不传 Material `divisions`），由内部按 `step` 实时吸附，
/// 避免 Flutter 离散滑块自带的 100ms 追赶缓动动画导致拖动粘滞不跟手。
class AppNumberSlider extends StatefulWidget {
  /// 标题；传 null 时隐藏标题行 (嵌入 AppSettingTile.bottomChild 等容器内使用)
  final String? title;
  final double value;
  final double min;
  final double max;
  final int fractionDigits;
  final double? step;
  final String? unit;

  /// 输入提交或滑块手势结束时回调；拖动预览仅更新组件内部状态。
  final ValueChanged<double> onChanged;

  /// 为 false 时锁定输入和滑块，用于算力档位强制参数。
  final bool enabled;

  /// 是否允许在输入框中键入负数 (滑块仍限制在 [min, max] 视觉范围内)
  final bool allowNegativeInput;

  /// 是否允许在输入框中键入超出 [max] 的数值 (对齐官网 uncap 特性)
  final bool uncapInput;

  const AppNumberSlider({
    super.key,
    this.title,
    required this.value,
    required this.min,
    required this.max,
    this.fractionDigits = 0,
    this.step,
    this.unit,
    this.enabled = true,
    this.allowNegativeInput = false,
    this.uncapInput = false,
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
    bool enabled = true,
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
      enabled: enabled,
      onChanged: (v) => onChanged(v.round()),
    );
  }

  @override
  State<AppNumberSlider> createState() => _AppNumberSliderState();
}

class _AppNumberSliderState extends State<AppNumberSlider> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  double? _dragValue;

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
    if (oldWidget.value != widget.value ||
        oldWidget.min != widget.min ||
        oldWidget.max != widget.max) {
      // 外部更新优先，避免迟到的拖动提交覆盖模型切换或 Agent 修改。
      _dragValue = null;
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
    if (!widget.enabled) {
      _controller.text = _format(widget.value);
      return;
    }
    final parsed = double.tryParse(val.trim());
    if (parsed != null && parsed.isFinite) {
      double resolved;
      if (widget.allowNegativeInput || widget.uncapInput) {
        final lower = widget.allowNegativeInput ? -99.0 : widget.min;
        final upper = widget.uncapInput ? 99.0 : widget.max;
        resolved = parsed.clamp(lower, upper).toDouble();
      } else {
        resolved = _snapToStep(parsed).clamp(widget.min, widget.max).toDouble();
      }
      final clamped = double.parse(
        resolved.toStringAsFixed(widget.fractionDigits),
      );
      _controller.text = _format(clamped);
      if (clamped != widget.value) widget.onChanged(clamped);
    } else {
      _controller.text = _format(widget.value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final sliderValue = _snapToStep(
      _dragValue ?? widget.value,
    ).clamp(widget.min, widget.max).toDouble();

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
                readOnly: !widget.enabled,
                enabled: widget.enabled,
                keyboardType: TextInputType.numberWithOptions(
                  decimal: widget.fractionDigits > 0,
                  signed: widget.min < 0 || widget.allowNegativeInput,
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
                  value: sliderValue,
                  min: widget.min,
                  max: widget.max,
                  onChanged: widget.enabled
                      ? (v) {
                          final snapped = _snapToStep(v);
                          final rounded = double.parse(
                            snapped.toStringAsFixed(widget.fractionDigits),
                          );
                          if (_dragValue == rounded) return;
                          setState(() => _dragValue = rounded);
                          _controller.text = _format(rounded);
                        }
                      : null,
                  onChangeEnd: widget.enabled
                      ? (_) {
                          final committed = _dragValue;
                          if (committed == null) return;
                          if (committed != widget.value) {
                            widget.onChanged(committed);
                            // 延后至帧末清理：若父级同步回传新 value，didUpdateWidget 会无缝清掉 _dragValue；
                            // 若父级拒绝变更，则在帧末自动回正到真实 widget.value，避免松手瞬间闪回旧值。
                            SchedulerBinding.instance.addPostFrameCallback((_) {
                              if (!mounted || _dragValue != committed) return;
                              setState(() => _dragValue = null);
                              _controller.text = _format(widget.value);
                            });
                          } else {
                            setState(() => _dragValue = null);
                          }
                        }
                      : null,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
