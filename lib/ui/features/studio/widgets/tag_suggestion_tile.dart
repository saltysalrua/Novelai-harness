import 'package:flutter/material.dart';
import '../../../../data/models/tag_models.dart';
import '../../../core/theme/app_theme.dart';

/// 标签分类胶囊 (自动补全卡与标签灵感库共用)
class TagCategoryPill extends StatelessWidget {
  final DanbooruTagCategory category;
  final double fontSize;

  const TagCategoryPill({
    super.key,
    required this.category,
    this.fontSize = 10,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: category.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      ),
      child: Text(
        category.label,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          color: category.color,
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
    this.fontSize = 10.5,
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
        color: AppTheme.textMuted,
      ),
    );
  }
}
