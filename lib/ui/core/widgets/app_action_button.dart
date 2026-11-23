import 'package:flutter/material.dart';

import '../theme/app_motion.dart';
import '../theme/app_tokens.dart';
import '../theme/theme_context_extensions.dart';
import 'app_transitions.dart';

/// [AppActionButton] 的视觉变体
enum AppActionButtonVariant {
  /// 白底/卡片底轻描边 (标准次级行动，如 选择 / 导入 / 立即更新)
  outlined,

  /// 品牌主色高亮 (强行动，如 新建 / 保存)
  primary,

  /// 无边框轻量行动 (如 取消 / 退出批注)
  ghost,
}

/// 统一紧凑型带图标标签操作按钮 (阶段 3 垂直切片沉淀)
///
/// 职责：收敛设置页/工具条散落的「图标 + 文案」小按钮重复实现。
/// 代码证据出处：
/// - settings_shared.dart:150-204 (SettingsActionButton 选择/立即更新/导入)
/// - models_settings_tab.dart / presets_settings_tab.dart 操作坞按钮群
///
/// 与 [AppIconButton] 的分工：本组件是**文字标签为主的宽按钮**；
/// AppIconButton 是**纯图标方形小按钮** (24~38px)。
///
/// 参数化驱动、无业务状态；取色一律 `context.colors` 语义色。
/// 支持图标/加载态切换动效 (`09-icon-swap`)、标签切换动效 (`04-text-states-swap`)
/// 以及前进箭头悬停微移 (`24-learn-more-hover`)。
class AppActionButton extends StatefulWidget {
  /// 按钮文案 (纯大白话，零营销词)
  final String label;

  /// 可选前缀图标
  final IconData? icon;

  final VoidCallback? onPressed;

  final AppActionButtonVariant variant;

  /// 图标字号 (默认 15，对齐旧 SettingsActionButton)
  final double iconSize;

  /// 圆角半径，默认 [AppRadius.md] (8.0)
  final double radius;

  /// 自定义内边距，未指定时使用紧凑默认内边距
  final EdgeInsetsGeometry? padding;

  /// 是否显示加载态旋转指示器 (同时禁用点击)
  final bool isLoading;

  const AppActionButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.variant = AppActionButtonVariant.outlined,
    this.iconSize = 15,
    this.radius = AppRadius.md,
    this.padding,
    this.isLoading = false,
  });

  @override
  State<AppActionButton> createState() => _AppActionButtonState();
}

class _AppActionButtonState extends State<AppActionButton> {
  bool _isHovered = false;

  bool _isDirectionalChevron(IconData? icon) {
    return icon == Icons.chevron_right ||
        icon == Icons.chevron_right_rounded ||
        icon == Icons.arrow_forward ||
        icon == Icons.arrow_forward_rounded ||
        icon == Icons.arrow_forward_ios ||
        icon == Icons.arrow_forward_ios_rounded ||
        icon == Icons.navigate_next ||
        icon == Icons.navigate_next_rounded ||
        icon == Icons.east ||
        icon == Icons.east_rounded;
  }

  bool _isDoneIcon(IconData? icon) {
    return icon == Icons.check ||
        icon == Icons.check_rounded ||
        icon == Icons.done ||
        icon == Icons.done_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final reduceMotion = AppMotion.shouldReduceMotion(context);
    final enabled = !widget.isLoading && widget.onPressed != null;
    final visuallyActive = enabled || widget.isLoading;

    final foreground = switch (widget.variant) {
      AppActionButtonVariant.outlined =>
        visuallyActive ? colors.textPrimary : colors.textMuted,
      AppActionButtonVariant.primary =>
        visuallyActive ? colors.onPrimary : colors.textMuted,
      AppActionButtonVariant.ghost =>
        visuallyActive ? colors.textSecondary : colors.textMuted,
    };
    final background = switch (widget.variant) {
      AppActionButtonVariant.outlined => colors.cardBackground,
      AppActionButtonVariant.primary =>
        visuallyActive ? colors.primary : colors.mutedBackground,
      AppActionButtonVariant.ghost => Colors.transparent,
    };
    final borderColor = switch (widget.variant) {
      AppActionButtonVariant.outlined => colors.borderDefault,
      AppActionButtonVariant.primary => colors.primary.withValues(
        alpha: visuallyActive ? 1.0 : 0.5,
      ),
      AppActionButtonVariant.ghost => Colors.transparent,
    };

    final text = AppTextSwap(
      text: widget.label,
      enableBlur: false,
      style: TextStyle(
        fontSize: 12,
        fontWeight: widget.variant == AppActionButtonVariant.primary
            ? FontWeight.w600
            : FontWeight.w500,
        color: foreground,
      ),
    );

    Widget? leading;
    if (widget.isLoading || widget.icon != null) {
      final Widget rawIcon;
      if (widget.isLoading) {
        rawIcon = SizedBox(
          key: const ValueKey('loading'),
          width: widget.iconSize,
          height: widget.iconSize,
          child: CircularProgressIndicator(
            strokeWidth: 1.8,
            color: foreground,
          ),
        );
      } else if (_isDoneIcon(widget.icon)) {
        rawIcon = AppSuccessCheck(
          key: ValueKey<IconData>(widget.icon!),
          size: widget.iconSize,
          strokeWidth: 2.0,
          color: foreground,
          bobDistance: 3.0,
        );
      } else {
        final iconWidget = Icon(
          widget.icon,
          key: ValueKey<IconData>(widget.icon!),
          size: widget.iconSize,
          color: foreground,
        );
        if (_isDirectionalChevron(widget.icon)) {
          final shiftDx = (_isHovered && enabled && !reduceMotion) ? 2.0 : 0.0;
          rawIcon = TweenAnimationBuilder<double>(
            key: ValueKey<IconData>(widget.icon!),
            tween: Tween<double>(end: shiftDx),
            duration: AppMotion.resolveDuration(
              context,
              AppMotionDurations.quick,
            ),
            curve: AppMotionCurves.smoothOut,
            builder: (context, dx, child) {
              return Transform.translate(offset: Offset(dx, 0), child: child);
            },
            child: iconWidget,
          );
        } else {
          rawIcon = iconWidget;
        }
      }

      leading = AppIconSwap(
        swapKey: widget.isLoading ? 'loading' : widget.icon,
        enableBlur: false,
        child: rawIcon,
      );
    }

    Widget button = OutlinedButton(
      onPressed: enabled ? widget.onPressed : null,
      style: OutlinedButton.styleFrom(
        backgroundColor: background,
        side: widget.variant == AppActionButtonVariant.ghost
            ? BorderSide.none
            : BorderSide(color: borderColor),
        padding:
            widget.padding ??
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(widget.radius),
        ),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: leading != null
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                leading,
                const SizedBox(width: AppSpacing.xs),
                text,
              ],
            )
          : text,
    );

    if (enabled && _isDirectionalChevron(widget.icon)) {
      button = MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: button,
      );
    }

    return button;
  }
}
