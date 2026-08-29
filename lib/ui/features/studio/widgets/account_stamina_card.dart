import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../view_models/studio_view_model.dart';

class AccountStaminaCard extends StatelessWidget {
  final StudioViewModel viewModel;

  const AccountStaminaCard({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final info = viewModel.accountInfo;
    final isLoading = viewModel.isLoadingAccount;

    if (info == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.surfaceElevated,
          borderRadius: BorderRadius.circular(6),
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
            IconButton(
              icon: isLoading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 16),
              onPressed: isLoading ? null : () => viewModel.refreshAccountInfo(),
              tooltip: '刷新账号状态',
              visualDensity: VisualDensity.compact,
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
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部：等级与刷新按钮
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryDark.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppTheme.primaryLight.withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      info.tierName,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primaryLight,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${info.totalAnlas} Anlas',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: isLoading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 16),
                onPressed: isLoading ? null : () => viewModel.refreshAccountInfo(),
                tooltip: '刷新体力与点数',
                visualDensity: VisualDensity.compact,
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
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: percent,
              backgroundColor: AppTheme.background,
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
