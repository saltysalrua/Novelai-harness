import 'package:flutter/material.dart';
import '../../../../core/harness/tools/agent_tool.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_badge.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_icon_button.dart';

/// 预设配置中的单个 Tool 小卡片 (对齐 ModelCard 设计)
class ToolCard extends StatelessWidget {
  final AgentTool tool;
  final bool isEnabled;

  /// 为空 (内置预设只读) 时点击卡片不切换，仅保留查看入口
  final ValueChanged<bool>? onToggle;
  final ValueChanged<AgentTool> onInspectSchema;
  final ValueChanged<CustomAgentTool>? onEditCustomTool;
  final VoidCallback? onDelete;

  const ToolCard({
    super.key,
    required this.tool,
    required this.isEnabled,
    this.onToggle,
    required this.onInspectSchema,
    this.onEditCustomTool,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final properties = (tool.parameters['properties'] is Map)
        ? (tool.parameters['properties'] as Map).keys.toList()
        : <dynamic>[];

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
                    tool.label,
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
                  label: tool.isBuiltin ? '内置' : '自定义',
                  variant: tool.isBuiltin
                      ? AppBadgeVariant.neutral
                      : AppBadgeVariant.success,
                  fontSize: 10,
                ),
                const SizedBox(width: AppSpacing.xs),
                // 查看 Schema / 编辑 按钮
                AppIconButton(
                  icon: tool is CustomAgentTool
                      ? Icons.edit_outlined
                      : Icons.code_rounded,
                  size: 26,
                  iconSize: 14,
                  tooltip: tool is CustomAgentTool ? '编辑工具' : '查看 Schema',
                  onPressed: () {
                    if (tool is CustomAgentTool && onEditCustomTool != null) {
                      onEditCustomTool!(tool as CustomAgentTool);
                    } else {
                      onInspectSchema(tool);
                    }
                  },
                ),
                // 删除按钮 (仅自定义可删)
                if (onDelete != null && !tool.isBuiltin)
                  AppIconButton(
                    icon: Icons.close_rounded,
                    size: 26,
                    iconSize: 14,
                    tooltip: '删除自定义工具',
                    onPressed: onDelete,
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              tool.name,
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
              tool.description.isNotEmpty ? tool.description : '暂无工具描述',
              style: TextStyle(
                fontSize: 11,
                color: colors.textSecondary,
                height: 1.3,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (properties.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: properties.take(4).map((p) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1.5,
                    ),
                    decoration: BoxDecoration(
                      color: colors.mutedBackground,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      '$p',
                      style: TextStyle(
                        fontSize: 9,
                        fontFamily: 'monospace',
                        color: colors.textMuted,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
