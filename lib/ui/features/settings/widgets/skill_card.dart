import 'package:flutter/material.dart';
import '../../../../core/harness/skills/skills.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_badge.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../../core/widgets/app_transitions.dart';
import '../../../core/context_l10n.dart';

/// 预设配置与技能管理中的单个 Skill 卡片 (对齐 ModelCard 设计)
class SkillCard extends StatelessWidget {
  final Skill skill;
  final bool isEnabled;

  /// 是否显示左侧勾选框（预设页用于启停，技能库页隐藏勾选框且点击卡片直接编辑）
  final bool showToggleCheckbox;

  /// 内置技能是否存在本地修改覆盖
  final bool isOverridden;

  /// 为空 (内置预设只读) 时点击卡片不切换，仅保留查看入口
  final ValueChanged<bool>? onToggle;
  final ValueChanged<Skill> onEdit;
  final ValueChanged<Skill>? onExport;
  final VoidCallback? onDelete;
  final VoidCallback? onResetDefault;
  final double? width;

  const SkillCard({
    super.key,
    required this.skill,
    required this.isEnabled,
    this.showToggleCheckbox = true,
    this.isOverridden = false,
    this.onToggle,
    required this.onEdit,
    this.onExport,
    this.onDelete,
    this.onResetDefault,
    this.width = 270,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;

    final VoidCallback? cardTap = showToggleCheckbox
        ? (onToggle == null ? null : () => onToggle!(!isEnabled))
        : () => onEdit(skill);

    final card = AppCard(
      isSelected: showToggleCheckbox && isEnabled,
      onTap: cardTap,
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
              if (showToggleCheckbox) ...[
                // 勾选启用状态
                AnimatedContainer(
                  duration: AppMotion.resolveDuration(
                    context,
                    AppMotionDurations.quick,
                  ),
                  curve: AppMotionCurves.smoothOut,
                  width: 15,
                  height: 15,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                      color: isEnabled ? colors.primary : colors.borderDefault,
                      width: 1.5,
                    ),
                    color: isEnabled ? colors.primary : null,
                  ),
                  child: AppIconSwap(
                    swapKey: isEnabled,
                    enableBlur: false,
                    child: isEnabled
                        ? Icon(
                            Icons.check,
                            key: const ValueKey<bool>(true),
                            size: 11,
                            color: colors.onPrimary,
                          )
                        : const SizedBox.shrink(key: ValueKey<bool>(false)),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs * 2),
              ],
              Expanded(
                child: Text(
                  skill.name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: (showToggleCheckbox && isEnabled)
                        ? colors.primary
                        : colors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // 内置 / 已修改 / 自定义 徽章
              AppBadge(
                label: skill.isBuiltin
                    ? (isOverridden
                          ? l10n.skillBadgeModified
                          : l10n.settingsBadgeBuiltin)
                    : l10n.settingsBadgeCustom,
                variant: skill.isBuiltin
                    ? (isOverridden
                          ? AppBadgeVariant.primary
                          : AppBadgeVariant.neutral)
                    : AppBadgeVariant.warning,
                fontSize: 10,
              ),
              const SizedBox(width: AppSpacing.xs),
              // 恢复默认按钮 (仅被覆盖修改过的内置技能显示)
              if (skill.isBuiltin && isOverridden && onResetDefault != null)
                AppIconButton(
                  icon: Icons.restart_alt_rounded,
                  size: 26,
                  iconSize: 14,
                  variant: AppIconButtonVariant.ghost,
                  tooltip: l10n.skillResetDefault,
                  onPressed: onResetDefault,
                ),
              // 导出按钮
              if (onExport != null)
                AppIconButton(
                  icon: Icons.download_rounded,
                  size: 26,
                  iconSize: 14,
                  variant: AppIconButtonVariant.ghost,
                  tooltip: l10n.skillTooltipExport,
                  onPressed: () => onExport!(skill),
                ),
              // 编辑按钮
              AppIconButton(
                icon: Icons.edit_outlined,
                size: 26,
                iconSize: 14,
                variant: AppIconButtonVariant.ghost,
                tooltip: l10n.skillTooltipEdit,
                onPressed: () => onEdit(skill),
              ),
              // 删除按钮 (仅自定义可删)
              if (onDelete != null && !skill.isBuiltin)
                AppIconButton(
                  icon: Icons.close_rounded,
                  size: 26,
                  iconSize: 14,
                  variant: AppIconButtonVariant.ghost,
                  tooltip: l10n.skillTooltipDelete,
                  onPressed: onDelete,
                ),
            ],
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              Expanded(
                child: Text(
                  skill.id,
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: colors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // 标准技能包的配套文件数量 (无包时不占用空间)
              if (skill.resourcePaths.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1.5,
                  ),
                  decoration: BoxDecoration(
                    color: colors.elevatedBackground,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.folder_zip_outlined,
                        size: 11,
                        color: colors.textSecondary,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        l10n.skillPackageFiles(skill.resourcePaths.length),
                        style: TextStyle(
                          fontSize: 10,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            skill.description.isNotEmpty
                ? skill.description
                : l10n.skillNoDescription,
            style: TextStyle(
              fontSize: 11,
              color: colors.textSecondary,
              height: 1.35,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
    return width != null ? SizedBox(width: width, child: card) : card;
  }
}
