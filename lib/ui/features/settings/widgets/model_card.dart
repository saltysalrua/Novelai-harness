import 'package:flutter/material.dart';
import '../../../../data/models/novelai_models.dart';
import '../../../core/context_l10n.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_badge.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_icon_button.dart';

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
    final colors = context.colors;
    final l10n = context.l10n;

    return AppCard(
      isSelected: isSelected,
      onTap: () => onSelect(model),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      radius: AppRadius.md,
      selectedBackgroundColor: colors.primary.withValues(alpha: 0.05),
      selectedBorderColor: colors.primary.withValues(alpha: 0.55),
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
                    color: isSelected ? colors.primary : colors.borderDefault,
                    width: 1.5,
                  ),
                  color: isSelected ? colors.primary : Colors.transparent,
                ),
                child: isSelected
                    ? const Icon(Icons.check, size: 10, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: AppSpacing.xs * 2),
              Expanded(
                child: Text(
                  model.name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? colors.primary : colors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              AppIconButton(
                icon: Icons.settings_outlined,
                size: 28,
                iconSize: 15,
                tooltip: l10n.settingsModelSettings,
                onPressed: () => onEdit(model),
              ),
              if (onDelete != null)
                AppIconButton(
                  icon: Icons.close_rounded,
                  size: 28,
                  iconSize: 15,
                  tooltip: l10n.settingsDeleteModel,
                  onPressed: onDelete,
                ),
            ],
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              model.id,
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: colors.textSecondary,
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
                  AppBadge(
                    icon: Icons.psychology_outlined,
                    label: l10n.settingsModelBadgeThinking,
                    variant: AppBadgeVariant.primary,
                    fontSize: 10,
                  ),
                if (model.isMultimodal)
                  AppBadge(
                    icon: Icons.visibility_outlined,
                    label: l10n.settingsModelBadgeMultimodal,
                    variant: AppBadgeVariant.success,
                    fontSize: 10,
                  ),
                if (model.imageOutput)
                  AppBadge(
                    icon: Icons.auto_awesome,
                    label: l10n.settingsModelBadgeImageOutput,
                    variant: AppBadgeVariant.warning,
                    fontSize: 10,
                  ),
                AppBadge(
                  icon: Icons.straighten_outlined,
                  label: l10n.settingsModelBadgeContext(
                    _formatTokens(model.contextWindow),
                  ),
                  variant: AppBadgeVariant.neutral,
                  fontSize: 10,
                ),
              ],
            ),
          ),
        ],
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
