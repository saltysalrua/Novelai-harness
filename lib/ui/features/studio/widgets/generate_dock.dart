import 'package:flutter/material.dart';
import '../../../../data/models/novelai_models.dart';
import '../../../core/context_l10n.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_badge.dart';
import '../../../core/widgets/app_floating_dock.dart';
import '../view_models/studio_view_model.dart';

/// 左侧面板底部常驻操作坞：账号等级 / 点数 / Opus 免点标识 / V5 体力条 / 刷新 + 主操作按钮
///
/// 主操作按钮随侧栏页签切换：修复页签下为「开始修复」(执行局部修复)，
/// 其余页签为「生成图片」(结合预计点数 / 生成中可点击终止)。
class GenerateDock extends StatelessWidget {
  final StudioViewModel viewModel;

  const GenerateDock({super.key, required this.viewModel});

  String _buildButtonLabel(BuildContext context, int cost) {
    final l10n = context.l10n;
    if (viewModel.isGenerating) {
      if (viewModel.liveTotalSteps > 0 && viewModel.liveCurrentStep > 0) {
        return l10n.dockAbortWithSteps(
          viewModel.liveCurrentStep,
          viewModel.liveTotalSteps,
        );
      }
      return l10n.abortGeneration;
    }
    if (cost > 0) {
      return l10n.dockGenerateWithCost(cost);
    }
    if (cost < 0) {
      return l10n.dockGenerateNeedPoints;
    }
    return l10n.generateImage;
  }

  Color _buildButtonColor(BuildContext context, int cost) {
    final colors = context.colors;
    if (viewModel.isGenerating) {
      return colors.error;
    }
    if (cost != 0) {
      return colors.warning;
    }
    return colors.primary;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
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
        ? colors.success
        : (info?.staminaPercent ?? 0) >= 30
        ? colors.warning
        : colors.error;

    return AppFloatingDock(
      radius: 0,
      shadows: const [],
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      backgroundColor: colors.cardBackground,
      borderColor: colors.borderDefault,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (info == null)
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.l10n.dockNoAccountInfo,
                    style: TextStyle(fontSize: 12, color: colors.textSecondary),
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
                AppBadge(
                  label: info.tierName,
                  shape: AppBadgeShape.pill,
                  variant: AppBadgeVariant.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '${info.totalAnlas} Anlas',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
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
                  Text(
                    context.l10n.v5Stamina,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      child: LinearProgressIndicator(
                        value: percent,
                        backgroundColor: colors.mutedBackground,
                        valueColor: AlwaysStoppedAnimation<Color>(staminaColor),
                        minHeight: 5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${info.staminaPercent.toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 12,
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
                  ? colors.primary
                  : _buildButtonColor(context, estimatedCost),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
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
            label: isInpaintTab
                ? Text(
                    isAiEditMode
                        ? (isRepairing
                              ? context.l10n.dockAiEditing
                              : context.l10n.startAiEdit)
                        : (isRepairing
                              ? context.l10n.dockInpainting
                              : context.l10n.startInpaint),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                : ListenableBuilder(
                    // 生成中的步数文案仅随实时进度控制器局部刷新
                    listenable: viewModel.liveProgressController,
                    builder: (context, _) => Text(
                      _buildButtonLabel(context, estimatedCost),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
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
    final colors = context.colors;
    final isLoading = viewModel.isLoadingAccount;
    return IconButton(
      icon: isLoading
          ? SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
              ),
            )
          : Icon(Icons.refresh, size: 17, color: colors.textSecondary),
      tooltip: context.l10n.dockRefreshTooltip,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(3),
      constraints: const BoxConstraints(),
      onPressed: isLoading ? null : () => viewModel.refreshAccountInfo(),
    );
  }
}
