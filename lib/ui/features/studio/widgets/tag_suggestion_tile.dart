import 'package:flutter/material.dart';
import '../../../../data/models/tag_models.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';

/// 标签分类胶囊 (自动补全卡与标签灵感库共用)
class TagCategoryPill extends StatelessWidget {
  final DanbooruTagCategory category;
  final String? customLabel;
  final double fontSize;

  const TagCategoryPill({
    super.key,
    required this.category,
    this.customLabel,
    this.fontSize = 10,
  });

  @override
  Widget build(BuildContext context) {
    final label = customLabel ?? category.label;
    // 分类色统一事实源：context.tagCategoryColor (亮暗自适应)，
    // 不再直连数据模型里的固定色 (Model 字段待阶段 4C 解耦删除)
    final color = customLabel != null
        ? context
              .colors
              .primary // 词组合标识随主题主色
        : context.tagCategoryColor(category);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

/// 标签热度计数文本 (等宽字体淡显)
class TagCountText extends StatelessWidget {
  final String formattedCount;
  final double fontSize;

  const TagCountText({
    super.key,
    required this.formattedCount,
    this.fontSize = 11,
  });

  @override
  Widget build(BuildContext context) {
    if (formattedCount.isEmpty) return const SizedBox.shrink();
    return Text(
      formattedCount,
      style: TextStyle(
        fontSize: fontSize,
        fontFamily: 'monospace',
        fontWeight: FontWeight.w500,
        color: context.colors.textMuted,
      ),
    );
  }
}
