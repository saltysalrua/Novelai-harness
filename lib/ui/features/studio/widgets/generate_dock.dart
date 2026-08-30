import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../view_models/studio_view_model.dart';

/// 左侧面板底部常驻操作坞：账号等级 / 点数 / Opus 免点标识 / V5 体力条 / 刷新 + 生成按钮
class GenerateDock extends StatelessWidget {
  final StudioViewModel viewModel;

  const GenerateDock({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final params = viewModel.params;
    final info = viewModel.accountInfo;
    final isOpusFree = params.isOpusFree;

    final percent = info != null
        ? (info.staminaPercent / 100.0).clamp(0.0, 1.0)
        : 0.0;
    final staminaColor = (info?.staminaPercent ?? 0) >= 80
        ? AppTheme.success
        : (info?.staminaPercent ?? 0) >= 30
        ? AppTheme.warning
        : AppTheme.error;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: const BoxDecoration(
        color: AppTheme.pureWhite,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (info == null)
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '未获取账号信息 (请检查 API Key)',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _OpusBadge(isOpusFree: isOpusFree),
                const SizedBox(width: 6),
                _RefreshButton(viewModel: viewModel),
              ],
            )
          else ...[
            // 等级、点数、免点胶囊与刷新
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.skyTint,
                    borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                    border: Border.all(
                      color: AppTheme.notionBlue.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    info.tierName,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.notionBlue,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${info.totalAnlas} Anlas',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(width: 8),
                _OpusBadge(isOpusFree: isOpusFree),
                const Spacer(),
                _RefreshButton(viewModel: viewModel),
              ],
            ),
            const SizedBox(height: 8),

            // V5 体力进度条
            Row(
              children: [
                const Text(
                  'V5 体力',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                    child: LinearProgressIndicator(
                      value: percent,
                      backgroundColor: const Color(0xFFEFEFEF),
                      valueColor: AlwaysStoppedAnimation<Color>(staminaColor),
                      minHeight: 5,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${info.staminaPercent.toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: staminaColor,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  info.timeUntilNextPercent > 0
                      ? '(${info.timeUntilNextPercent}s)'
                      : (info.staminaPercent >= 100 ? '(满)' : ''),
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 12),

          // 生成按钮 (Primary CTA)
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.notionBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusButton),
              ),
            ),
            onPressed: viewModel.isGenerating
                ? null
                : () => viewModel.generateImage(),
            icon: viewModel.isGenerating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.auto_awesome, size: 17),
            label: Text(
              viewModel.isGenerating ? '生成中...' : '生成图片',
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Opus 免点 / 需点数 标识胶囊
class _OpusBadge extends StatelessWidget {
  final bool isOpusFree;

  const _OpusBadge({required this.isOpusFree});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
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
          fontWeight: FontWeight.w700,
          color: isOpusFree ? AppTheme.success : AppTheme.warning,
        ),
      ),
    );
  }
}

/// 账号信息刷新按钮
class _RefreshButton extends StatelessWidget {
  final StudioViewModel viewModel;

  const _RefreshButton({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final isLoading = viewModel.isLoadingAccount;
    return IconButton(
      icon: isLoading
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.notionBlue),
              ),
            )
          : const Icon(Icons.refresh, size: 17, color: AppTheme.textSecondary),
      tooltip: '刷新体力与点数',
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(3),
      constraints: const BoxConstraints(),
      onPressed: isLoading ? null : () => viewModel.refreshAccountInfo(),
    );
  }
}
