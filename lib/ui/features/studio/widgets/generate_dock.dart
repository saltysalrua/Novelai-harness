import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../../data/models/novelai_models.dart';
import '../view_models/studio_view_model.dart';

/// 左侧面板底部常驻操作坞：账号等级 / 点数 / Opus 免点标识 / V5 体力条 / 刷新 + 主操作按钮
///
/// 主操作按钮随侧栏页签切换：修复页签下为「开始修复」(执行局部修复)，
/// 其余页签为「生成图片」(结合预计点数 / 生成中可点击终止)。
class GenerateDock extends StatelessWidget {
  final StudioViewModel viewModel;

  const GenerateDock({super.key, required this.viewModel});

  String _buildButtonLabel(int cost) {
    if (viewModel.isGenerating) {
      if (viewModel.liveTotalSteps > 0 && viewModel.liveCurrentStep > 0) {
        return '终止生成 (${viewModel.liveCurrentStep}/${viewModel.liveTotalSteps})';
      }
      return '终止生成';
    }
    if (cost > 0) {
      return '生成图片 ($cost Anlas)';
    }
    if (cost < 0) {
      return '生成图片 (需点数)';
    }
    return '生成图片';
  }

  Color _buildButtonColor(int cost) {
    if (viewModel.isGenerating) {
      return AppTheme.error;
    }
    if (cost != 0) {
      return AppTheme.warning;
    }
    return AppTheme.notionBlue;
  }

  @override
  Widget build(BuildContext context) {
    final info = viewModel.accountInfo;
    final estimatedCost = viewModel.estimatedGenerationCost;
    // 修复页签下主按钮切换为「开始修复」(AI 整图编辑模式下为「开始 AI 编辑」)，
    // 其余页签为「生成图片」
    final isInpaintTab = viewModel.activeSidebarTab == StudioSidebarTab.inpaint;
    final isAiEditMode =
        isInpaintTab && viewModel.inpaintParams.mode == InpaintMode.aiEdit;
    final isRepairing =
        viewModel.isExecutingInpaint || viewModel.isExecutingAiEdit;

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
                const SizedBox(width: 6),
                _RefreshButton(viewModel: viewModel),
              ],
            )
          else ...[
            // 等级、点数与刷新
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
                const Spacer(),
                _RefreshButton(viewModel: viewModel),
              ],
            ),

            // 仅在当前选择 V5 系列模型时展示体力进度条
            if (viewModel.params.model.isV5) ...[
              const SizedBox(height: 8),
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
                ],
              ),
            ],
          ],

          const SizedBox(height: 12),

          // 主操作按钮 (修复页签 = 开始修复；其余 = 生成图片)
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: isInpaintTab
                  ? AppTheme.notionBlue
                  : _buildButtonColor(estimatedCost),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusButton),
              ),
            ),
            onPressed: isInpaintTab
                ? (isRepairing || viewModel.isGenerating
                      ? null
                      : () => viewModel.executeInpaint())
                : (viewModel.isGenerating
                      ? () => viewModel.abortGeneration()
                      : () => viewModel.generateImage()),
            icon: isInpaintTab
                ? (isAiEditMode
                      ? const Icon(Icons.auto_awesome, size: 17)
                      : const Icon(Icons.auto_fix_high_outlined, size: 17))
                : (viewModel.isGenerating
                      ? const Icon(Icons.stop_circle_outlined, size: 17)
                      : const Icon(Icons.auto_awesome, size: 17)),
            label: Text(
              isInpaintTab
                  ? (isAiEditMode
                        ? (isRepairing ? 'AI 编辑中...' : '开始 AI 编辑')
                        : (isRepairing ? '修复中...' : '开始修复'))
                  : _buildButtonLabel(estimatedCost),
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
