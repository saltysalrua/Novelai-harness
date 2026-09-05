import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import '../theme/theme_context_extensions.dart';

/// 统一设置项/开关卡片组件 (用于设置弹窗与参数高级选项)
///
/// 统一设置项卡片，支持开关、按钮、自定义尾部控件
/// 以及下方可折叠/常驻扩展内容。
class AppSettingTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget control;
  final Widget? bottomChild;
  final EdgeInsets? padding;

  /// 外边距 (默认仅底部留 AppSpacing.sm 间距)
  final EdgeInsets? margin;

  /// 整行点击回调 (设置后整行可点击，光标变手型；开关行用于整行切换)
  final VoidCallback? onTap;

  const AppSettingTile({
    super.key,
    required this.title,
    this.subtitle,
    required this.control,
    this.bottomChild,
    this.padding,
    this.margin,
    this.onTap,
  });

  /// Switch 开关便捷工厂 (整行可点击切换)
  factory AppSettingTile.switchTile({
    Key? key,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    Widget? bottomChild,
    EdgeInsets? margin,
  }) {
    return AppSettingTile(
      key: key,
      title: title,
      subtitle: subtitle,
      bottomChild: bottomChild,
      margin: margin,
      onTap: () => onChanged(!value),
      control: Builder(
        builder: (context) {
          final colors = context.colors;
          return Switch(
            value: value,
            activeTrackColor: colors.primary,
            activeThumbColor: Colors.white,
            inactiveTrackColor: colors.mutedBackground,
            inactiveThumbColor: colors.textMuted,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: onChanged,
          );
        },
      ),
    );
  }

  /// 按钮操作项便捷工厂
  factory AppSettingTile.actionTile({
    Key? key,
    required String title,
    String? subtitle,
    required String buttonLabel,
    required VoidCallback onPressed,
    IconData? buttonIcon,
    Widget? bottomChild,
  }) {
    return AppSettingTile(
      key: key,
      title: title,
      subtitle: subtitle,
      bottomChild: bottomChild,
      control: Builder(
        builder: (context) {
          final colors = context.colors;
          final buttonStyle = OutlinedButton.styleFrom(
            foregroundColor: colors.textPrimary,
            side: BorderSide(color: colors.borderDefault),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
          );
          // 无图标时不拼 SizedBox.shrink() 占位，避免按钮内多出一段空隙
          return buttonIcon != null
              ? OutlinedButton.icon(
                  icon: Icon(buttonIcon, size: 14),
                  label: Text(buttonLabel),
                  style: buttonStyle,
                  onPressed: onPressed,
                )
              : OutlinedButton(
                  style: buttonStyle,
                  onPressed: onPressed,
                  child: Text(buttonLabel),
                );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final Widget card = Container(
      margin: margin ?? const EdgeInsets.only(bottom: AppSpacing.sm),
      padding:
          padding ??
          const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              control,
            ],
          ),
          if (bottomChild != null) ...[
            const SizedBox(height: AppSpacing.sm),
            bottomChild!,
          ],
        ],
      ),
    );

    // 整行可点击 (如开关行整行切换)；控件自身命中时由内部手势优先接管，
    // 不会与外层点击形成双触发
    if (onTap == null) return card;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: card,
      ),
    );
  }
}
