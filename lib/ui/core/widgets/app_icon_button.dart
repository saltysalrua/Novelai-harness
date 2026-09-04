import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import '../theme/theme_context_extensions.dart';

/// [AppIconButton] 的视觉变体
enum AppIconButtonVariant {
  /// 白底/卡片底轻描边 (标准操作按钮，如卡片右侧快捷操作)
  outlined,

  /// 浮层轻阴影 (悬浮于画布或半透明背景上的操作按钮)
  elevated,

  /// 品牌主色高亮 (主行动按钮，如发送或确定键)
  primary,

  /// 幽灵按钮/中性纯图标 (无外框无底色，仅 Hover 时显现背景)
  ghost,
}

/// 统一紧凑型方形操作按钮 (AppIconButton)
///
/// 代码证据出处：
/// - `prompt_combo_card.dart:90-111` (_ActionIconButton 28x28 / 32x32 白底描边)
/// - `model_card.dart:82-112` (28x28 模型操作键)
/// - `skill_card.dart:104-153` 与 `tool_card.dart:108-150` (26x26 技能/工具卡按钮)
/// - `canvas_overlays.dart:265-290` (HistoryToggleButton 38x38 浮层阴影按钮)
/// - `resolution_pad_picker.dart:178-237` (36x38 方向与宽高交换键)
/// - `agent_chat_card.dart:358-367` (28x28 对话卡操作按钮)
/// - `agent_chat_input_bar.dart:504-557` (36x36 附件与发送键)
/// - `settings_shared.dart:150-204` (SettingsActionButton 操作键)
///
/// 核心职责：
/// 统一全工程散落的 24/28/32/36/38px 紧凑方形图标按钮，
/// 提供白底描边、浮层阴影、主色高亮与幽灵无框四套视觉风格，内置 Tooltip 与禁用态。
class AppIconButton extends StatefulWidget {
  /// 按钮图标
  final IconData icon;

  /// 点击事件；为 null 时自动呈现禁用态
  final VoidCallback? onPressed;

  /// 悬停提示文字 (可选)
  final String? tooltip;

  /// 按钮外观尺寸 (方形边长)，默认 28.0
  final double size;

  /// 图标大小；若未指定则自动按 [size] 的 0.54 等比缩放
  final double? iconSize;

  /// 视觉变体，默认 [AppIconButtonVariant.outlined]
  final AppIconButtonVariant variant;

  /// 自定义图标颜色 (覆盖变体预设)
  final Color? iconColor;

  /// 自定义背景色 (覆盖变体预设)
  final Color? backgroundColor;

  /// 自定义边框颜色 (覆盖变体预设)
  final Color? borderColor;

  /// 圆角半径，默认 [AppRadius.md] (8.0)
  final double radius;

  /// 是否启用按钮交互，默认 true
  final bool enabled;

  const AppIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.size = 28.0,
    this.iconSize,
    this.variant = AppIconButtonVariant.outlined,
    this.iconColor,
    this.backgroundColor,
    this.borderColor,
    this.radius = AppRadius.md,
    this.enabled = true,
  });

  @override
  State<AppIconButton> createState() => _AppIconButtonState();
}

class _AppIconButtonState extends State<AppIconButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isInteractive = widget.enabled && widget.onPressed != null;

    final double effectiveIconSize =
        widget.iconSize ?? (widget.size * 0.54).clamp(12.0, 24.0);

    // 计算各变体下的默认背景、边框、前景色与阴影
    final (
      Color bg,
      Color border,
      Color fg,
      List<BoxShadow>? shadow,
    ) = switch (widget.variant) {
      AppIconButtonVariant.outlined => (
        widget.backgroundColor ?? colors.cardBackground,
        widget.borderColor ??
            (_isHovered && isInteractive
                ? colors.borderHover
                : colors.borderDefault),
        widget.iconColor ??
            (_isHovered && isInteractive
                ? colors.textPrimary
                : colors.textSecondary),
        isInteractive && _isHovered ? context.shadowSubtle : null,
      ),
      AppIconButtonVariant.elevated => (
        widget.backgroundColor ?? colors.cardBackground,
        widget.borderColor ?? colors.borderSubtle,
        widget.iconColor ??
            (_isHovered && isInteractive ? colors.primary : colors.textPrimary),
        isInteractive ? context.shadowSubtle : null,
      ),
      AppIconButtonVariant.primary => (
        widget.backgroundColor ??
            (_isHovered && isInteractive ? colors.primaryDark : colors.primary),
        widget.borderColor ?? Colors.transparent,
        widget.iconColor ?? Colors.white,
        isInteractive && _isHovered
            ? AppShadows.subtle(
                colors.primary,
                brightness: context.themeBrightness,
              )
            : null,
      ),
      AppIconButtonVariant.ghost => (
        widget.backgroundColor ??
            (_isHovered && isInteractive
                ? colors.mutedBackground
                : Colors.transparent),
        widget.borderColor ?? Colors.transparent,
        widget.iconColor ??
            (_isHovered && isInteractive
                ? colors.textPrimary
                : colors.textSecondary),
        null,
      ),
    };

    final effectiveBg = isInteractive
        ? bg
        : colors.mutedBackground.withValues(alpha: 0.5);
    final effectiveFg = isInteractive
        ? fg
        : colors.textMuted.withValues(alpha: 0.5);
    final effectiveBorder = isInteractive ? border : colors.borderSubtle;

    Widget button = InkWell(
      onTap: isInteractive ? widget.onPressed : null,
      borderRadius: BorderRadius.circular(widget.radius),
      hoverColor: Colors.transparent,
      splashColor: isInteractive
          ? colors.primaryTint.withValues(alpha: 0.3)
          : Colors.transparent,
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: effectiveBg,
          borderRadius: BorderRadius.circular(widget.radius),
          border: effectiveBorder != Colors.transparent
              ? Border.all(color: effectiveBorder)
              : null,
          boxShadow: shadow,
        ),
        alignment: Alignment.center,
        child: Icon(widget.icon, size: effectiveIconSize, color: effectiveFg),
      ),
    );

    if (isInteractive) {
      button = MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: button,
      );
    }

    if (widget.tooltip != null && widget.tooltip!.isNotEmpty) {
      button = Tooltip(message: widget.tooltip!, child: button);
    }

    return button;
  }
}
