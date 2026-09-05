import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import '../theme/theme_context_extensions.dart';

/// [AppActionButton] 的视觉变体
enum AppActionButtonVariant {
  /// 白底/卡片底轻描边 (标准次级行动，如 选择 / 导入 / 立即更新)
  outlined,

  /// 品牌主色高亮 (强行动，如 新建 / 保存)
  primary,
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
class AppActionButton extends StatelessWidget {
  /// 按钮文案 (纯大白话，零营销词)
  final String label;

  /// 可选前缀图标
  final IconData? icon;

  final VoidCallback? onPressed;

  final AppActionButtonVariant variant;

  /// 图标字号 (默认 15，对齐旧 SettingsActionButton)
  final double iconSize;

  const AppActionButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.variant = AppActionButtonVariant.outlined,
    this.iconSize = 15,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = onPressed != null;

    final foreground = switch (variant) {
      AppActionButtonVariant.outlined => colors.textPrimary,
      AppActionButtonVariant.primary =>
        enabled ? Colors.white : colors.textMuted,
    };
    final background = switch (variant) {
      AppActionButtonVariant.outlined => colors.cardBackground,
      AppActionButtonVariant.primary =>
        enabled ? colors.primary : colors.mutedBackground,
    };
    final borderColor = switch (variant) {
      AppActionButtonVariant.outlined => colors.borderDefault,
      AppActionButtonVariant.primary => colors.primary.withValues(
        alpha: enabled ? 1.0 : 0.5,
      ),
    };

    final text = Text(
      label,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: foreground,
      ),
    );

    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: background,
        side: BorderSide(color: borderColor),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: icon != null
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: iconSize, color: foreground),
                const SizedBox(width: AppSpacing.xs),
                text,
              ],
            )
          : text,
    );
  }
}
