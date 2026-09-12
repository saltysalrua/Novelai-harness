import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import '../theme/theme_context_extensions.dart';

/// 统一分组小节标题组件 (支持副标题与右侧快捷操作)
///
/// 窄屏 (< 480px) 时尾部操作自动折到标题下方，避免固定宽度的
/// trailing 控件组 (如双按钮坞) 撑爆标题行造成 RenderFlex 溢出。
class AppSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsets padding;

  const AppSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.only(
      bottom: AppSpacing.sm,
      top: AppSpacing.xs,
    ),
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    Widget buildTitle() => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
          ),
        ),
        if (subtitle != null && subtitle!.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            style: TextStyle(fontSize: 11, color: colors.textSecondary),
          ),
        ],
      ],
    );

    return Padding(
      padding: padding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 标题与尾部操作之间的安全间隔，防止长标题贴尾
          const gap = SizedBox(width: AppSpacing.md);

          // 窄屏：尾部操作折到标题下方 (trailing 控件组多为固定宽度，
          // 常见的双按钮坞约 330px，加上标题与间隔后 480px 内必爆行)
          if (trailing != null && constraints.maxWidth < 480) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                buildTitle(),
                const SizedBox(height: AppSpacing.xs),
                trailing!,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: buildTitle()),
              if (trailing != null) ...[gap, trailing!],
            ],
          );
        },
      ),
    );
  }
}
