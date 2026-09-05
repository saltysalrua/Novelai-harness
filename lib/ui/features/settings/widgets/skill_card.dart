import 'package:flutter/material.dart';
import '../../../../core/harness/skills/skills.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_badge.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_icon_button.dart';

/// 预设配置中的单个 Skill 小卡片 (对齐 ModelCard 设计)
class SkillCard extends StatelessWidget {
  final Skill skill;
  final bool isEnabled;

  /// 为空 (内置预设只读) 时点击卡片不切换，仅保留查看入口
  final ValueChanged<bool>? onToggle;
  final ValueChanged<Skill> onEdit;
  final ValueChanged<Skill>? onExport;
  final VoidCallback? onDelete;

  const SkillCard({
    super.key,
    required this.skill,
    required this.isEnabled,
    this.onToggle,
    required this.onEdit,
    this.onExport,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return SizedBox(
      width: 270,
      child: AppCard(
        isSelected: isEnabled,
        onTap: onToggle == null ? null : () => onToggle!(!isEnabled),
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        radius: AppRadius.md,
        selectedBackgroundColor: colors.primary.withValues(alpha: 0.05),
        selectedBorderColor: colors.primary.withValues(alpha: 0.55),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                // 勾选启用状态
                Container(
                  width: 15,
                  height: 15,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                      color: isEnabled ? colors.primary : colors.borderDefault,
                      width: 1.5,
                    ),
                    color: isEnabled ? colors.primary : Colors.transparent,
                  ),
                  child: isEnabled
                      ? const Icon(Icons.check, size: 11, color: Colors.white)
                      : null,
                ),
                const SizedBox(width: AppSpacing.xs * 2),
                Expanded(
                  child: Text(
                    skill.name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isEnabled ? colors.primary : colors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // 内置 / 自定义 徽章
                AppBadge(
                  label: skill.isBuiltin ? '内置' : '自定义',
                  variant: skill.isBuiltin
                      ? AppBadgeVariant.neutral
                      : AppBadgeVariant.warning,
                  fontSize: 10,
                ),
                const SizedBox(width: AppSpacing.xs),
                // 导出按钮
                if (onExport != null)
                  AppIconButton(
                    icon: Icons.download_rounded,
                    size: 26,
                    iconSize: 14,
                    tooltip: '导出为 SKILL.md',
                    onPressed: () => onExport!(skill),
                  ),
                // 编辑按钮
                AppIconButton(
                  icon: Icons.edit_outlined,
                  size: 26,
                  iconSize: 14,
                  tooltip: '查看与编辑 Skill',
                  onPressed: () => onEdit(skill),
                ),
                // 删除按钮 (仅自定义可删)
                if (onDelete != null && !skill.isBuiltin)
                  AppIconButton(
                    icon: Icons.close_rounded,
                    size: 26,
                    iconSize: 14,
                    tooltip: '删除 Skill',
                    onPressed: onDelete,
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              skill.id,
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: colors.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Text(
              skill.description.isNotEmpty ? skill.description : '暂无描述',
              style: TextStyle(
                fontSize: 11,
                color: colors.textSecondary,
                height: 1.3,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
