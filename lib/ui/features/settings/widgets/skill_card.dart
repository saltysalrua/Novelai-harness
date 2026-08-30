import 'package:flutter/material.dart';
import '../../../../core/harness/skills/skills.dart';
import '../../../core/theme/app_theme.dart';

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
    return InkWell(
      onTap: onToggle == null ? null : () => onToggle!(!isEnabled),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 270,
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        decoration: BoxDecoration(
          color: isEnabled
              ? AppTheme.notionBlue.withValues(alpha: 0.05)
              : AppTheme.pureWhite,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isEnabled
                ? AppTheme.notionBlue.withValues(alpha: 0.55)
                : AppTheme.border,
          ),
        ),
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
                      color: isEnabled ? AppTheme.notionBlue : AppTheme.border,
                      width: 1.5,
                    ),
                    color: isEnabled ? AppTheme.notionBlue : Colors.transparent,
                  ),
                  child: isEnabled
                      ? const Icon(Icons.check, size: 11, color: Colors.white)
                      : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    skill.name,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: isEnabled
                          ? AppTheme.notionBlue
                          : AppTheme.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // 内置 / 自定义 徽章
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1.5,
                  ),
                  decoration: BoxDecoration(
                    color: (skill.isBuiltin ? AppTheme.stone : AppTheme.accent)
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    skill.isBuiltin ? '内置' : '自定义',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                      color: skill.isBuiltin ? AppTheme.stone : AppTheme.accent,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // 导出按钮
                if (onExport != null)
                  SizedBox(
                    width: 26,
                    height: 26,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: const Icon(
                        Icons.download_rounded,
                        size: 14,
                        color: AppTheme.stone,
                      ),
                      tooltip: '导出为 SKILL.md',
                      onPressed: () => onExport!(skill),
                    ),
                  ),
                // 编辑按钮
                SizedBox(
                  width: 26,
                  height: 26,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(
                      Icons.edit_outlined,
                      size: 14,
                      color: AppTheme.stone,
                    ),
                    tooltip: '查看与编辑 Skill',
                    onPressed: () => onEdit(skill),
                  ),
                ),
                // 删除按钮 (仅自定义可删)
                if (onDelete != null && !skill.isBuiltin)
                  SizedBox(
                    width: 26,
                    height: 26,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: const Icon(
                        Icons.close_rounded,
                        size: 14,
                        color: AppTheme.stone,
                      ),
                      tooltip: '删除 Skill',
                      onPressed: onDelete,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              skill.id,
              style: const TextStyle(
                fontSize: 10.5,
                fontFamily: 'monospace',
                color: AppTheme.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Text(
              skill.description.isNotEmpty ? skill.description : '暂无描述',
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.textSecondary,
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
