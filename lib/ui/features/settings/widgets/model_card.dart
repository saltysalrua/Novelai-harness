import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../../data/models/novelai_models.dart';

/// 模型列表中的单个模型小卡片
///
/// 点击卡片切换为当前模型；右上角设置按钮进入模型参数编辑；
/// 能力胶囊 (思考 / 多模态 / 上下文) 直观展示模型档案。
class ModelCard extends StatelessWidget {
  final LlmModelConfig model;
  final bool isSelected;
  final ValueChanged<LlmModelConfig> onSelect;
  final ValueChanged<LlmModelConfig> onEdit;
  final VoidCallback? onDelete;

  const ModelCard({
    super.key,
    required this.model,
    required this.isSelected,
    required this.onSelect,
    required this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onSelect(model),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.notionBlue.withValues(alpha: 0.05)
              : AppTheme.pureWhite,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
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
                // 选中态指示点
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? AppTheme.notionBlue : AppTheme.border,
                      width: 1.5,
                    ),
                    color: isSelected
                        ? AppTheme.notionBlue
                        : Colors.transparent,
                  ),
                  child: isSelected
                      ? const Icon(Icons.check, size: 10, color: Colors.white)
                      : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    model.name,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? AppTheme.notionBlue
                          : AppTheme.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(
                  width: 28,
                  height: 28,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(
                      Icons.settings_outlined,
                      size: 15,
                      color: AppTheme.stone,
                    ),
                    tooltip: '模型设置',
                    onPressed: () => onEdit(model),
                  ),
                ),
                if (onDelete != null)
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: const Icon(
                        Icons.close_rounded,
                        size: 15,
                        color: AppTheme.stone,
                      ),
                      tooltip: '删除模型',
                      onPressed: onDelete,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                model.id,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontFamily: 'monospace',
                  color: AppTheme.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 7),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  if (model.supportsThinking)
                    _CapabilityChip(
                      icon: Icons.psychology_outlined,
                      label: '思考',
                      foreground: AppTheme.notionBlue,
                    ),
                  if (model.isMultimodal)
                    _CapabilityChip(
                      icon: Icons.visibility_outlined,
                      label: '多模态',
                      foreground: AppTheme.success,
                    ),
                  if (model.imageOutput)
                    _CapabilityChip(
                      icon: Icons.auto_awesome,
                      label: '绘图',
                      foreground: AppTheme.marigold,
                    ),
                  _CapabilityChip(
                    icon: Icons.straighten_outlined,
                    label: '${_formatTokens(model.contextWindow)} 上下文',
                    foreground: AppTheme.textSecondary,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatTokens(int tokens) {
    if (tokens >= 1000000) {
      final m = (tokens / 1000000).toStringAsFixed(
        tokens % 1000000 == 0 ? 0 : 1,
      );
      return '${m}M';
    }
    if (tokens >= 1000) return '${(tokens / 1000).round()}K';
    return '$tokens';
  }
}

/// 能力胶囊
class _CapabilityChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color foreground;

  const _CapabilityChip({
    required this.icon,
    required this.label,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: foreground.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: foreground),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }
}
