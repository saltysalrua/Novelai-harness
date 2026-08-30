import 'package:flutter/material.dart';
import '../../../../core/harness/tools/agent_tool.dart';
import '../../../core/theme/app_theme.dart';

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
    final properties = (tool.parameters['properties'] is Map)
        ? (tool.parameters['properties'] as Map).keys.toList()
        : <dynamic>[];

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
                    tool.label,
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
                    color: (tool.isBuiltin ? AppTheme.stone : AppTheme.success)
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    tool.isBuiltin ? '内置' : '自定义',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                      color: tool.isBuiltin ? AppTheme.stone : AppTheme.success,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // 查看 Schema / 编辑 按钮
                SizedBox(
                  width: 26,
                  height: 26,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: Icon(
                      tool is CustomAgentTool
                          ? Icons.edit_outlined
                          : Icons.code_rounded,
                      size: 14,
                      color: AppTheme.stone,
                    ),
                    tooltip: tool is CustomAgentTool ? '编辑工具' : '查看 Schema',
                    onPressed: () {
                      if (tool is CustomAgentTool && onEditCustomTool != null) {
                        onEditCustomTool!(tool as CustomAgentTool);
                      } else {
                        onInspectSchema(tool);
                      }
                    },
                  ),
                ),
                // 删除按钮 (仅自定义可删)
                if (onDelete != null && !tool.isBuiltin)
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
                      tooltip: '删除自定义工具',
                      onPressed: onDelete,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              tool.name,
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
              tool.description.isNotEmpty ? tool.description : '暂无工具描述',
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.textSecondary,
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
                      color: AppTheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      '$p',
                      style: const TextStyle(
                        fontSize: 9,
                        fontFamily: 'monospace',
                        color: AppTheme.stone,
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
