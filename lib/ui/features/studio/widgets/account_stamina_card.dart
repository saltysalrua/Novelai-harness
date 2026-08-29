import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../settings/views/settings_dialog.dart';
import '../view_models/studio_view_model.dart';

class AccountStaminaCard extends StatelessWidget {
  final StudioViewModel viewModel;

  const AccountStaminaCard({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final info = viewModel.accountInfo;
    final isLoading = viewModel.isLoadingAccount;
    final isOpusFree = viewModel.params.isOpusFree;

    if (info == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.pureWhite,
          borderRadius: BorderRadius.circular(AppTheme.radiusButton),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(
              child: Text(
                '未获取账号信息 (请检查 API Key)',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
            ),
            Row(
              children: [
                IconButton(
                  icon: isLoading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(AppTheme.notionBlue),
                          ),
                        )
                      : const Icon(Icons.refresh, size: 16, color: AppTheme.textSecondary),
                  onPressed: isLoading ? null : () => viewModel.refreshAccountInfo(),
                  tooltip: '刷新账号状态',
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.settings_outlined, size: 16, color: AppTheme.textSecondary),
                  tooltip: '全局配置',
                  onPressed: () => SettingsDialog.show(context, viewModel),
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ],
        ),
      );
    }

    final percent = (info.staminaPercent / 100.0).clamp(0.0, 1.0);
    final staminaColor = info.staminaPercent >= 80
        ? AppTheme.success
        : info.staminaPercent >= 30
            ? AppTheme.warning
            : AppTheme.error;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.pureWhite,
        borderRadius: BorderRadius.circular(AppTheme.radiusButton),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部：等级、点数、免点状态与操作按钮
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.skyTint,
                        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                        border: Border.all(color: AppTheme.notionBlue.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        info.tierName,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.notionBlue,
                        ),
                      ),
                    ),
                    Text(
                      '${info.totalAnlas} Anlas',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isOpusFree
                            ? AppTheme.success.withValues(alpha: 0.12)
                            : AppTheme.warning.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                        border: Border.all(
                          color: isOpusFree
                              ? AppTheme.success.withValues(alpha: 0.4)
                              : AppTheme.warning.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Text(
                        isOpusFree ? 'Opus 免费' : '需点数',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isOpusFree ? AppTheme.success : AppTheme.warning,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: isLoading
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.notionBlue),
                            ),
                          )
                        : const Icon(Icons.refresh, size: 16, color: AppTheme.textSecondary),
                    onPressed: isLoading ? null : () => viewModel.refreshAccountInfo(),
                    tooltip: '刷新体力与点数',
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.settings_outlined, size: 16, color: AppTheme.textSecondary),
                    tooltip: '全局配置',
                    onPressed: () => SettingsDialog.show(context, viewModel),
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),

          // V5 专属体力池
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'V5 体力',
                style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
              ),
              Text(
                '${info.staminaPercent.toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: staminaColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            child: LinearProgressIndicator(
              value: percent,
              backgroundColor: const Color(0xFFEFEFEF),
              valueColor: AlwaysStoppedAnimation<Color>(staminaColor),
              minHeight: 5,
            ),
          ),
          const SizedBox(height: 6),

          Text(
            info.timeUntilNextPercent > 0
                ? '${info.timeUntilNextPercent} 秒后 +1%'
                : info.staminaPercent >= 100
                    ? '已满'
                    : '恢复中',
            style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
          ),
        ],
      ),
    );
  }
}
