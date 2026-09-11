import 'package:flutter/material.dart';
import '../../../../data/models/comfyui_models.dart';
import '../../../../data/models/novelai_models.dart';
import '../../../core/context_l10n.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_async_icon_button.dart';
import '../../../core/widgets/app_badge.dart';
import '../../../core/widgets/app_floating_dock.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../../core/widgets/app_progress_bar.dart';
import '../view_models/studio_view_model.dart';

/// 左侧面板底部常驻操作坞：账号等级 / 点数 / Opus 免点标识 / V5 体力条 / 刷新 + 主操作按钮
///
/// 主操作按钮随侧栏页签切换：修复页签下为「开始修复」(执行局部修复)，
/// 其余页签为「生成图片」(结合预计点数 / 生成中可点击终止)。
class GenerateDock extends StatelessWidget {
  final StudioViewModel viewModel;
  final bool compact;

  const GenerateDock({
    super.key,
    required this.viewModel,
    this.compact = false,
  });

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
      padding: EdgeInsets.symmetric(
        horizontal: compact ? AppSpacing.md : AppSpacing.lg,
        vertical: compact ? AppSpacing.sm : 14,
      ),
      backgroundColor: colors.cardBackground,
      borderColor: colors.borderDefault,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ComfyUI 模式：账号栏换成 Bridge 连接状态 (无点数概念)
          if (viewModel.isComfyUiMode)
            _ComfyStatusRow(viewModel: viewModel, compact: compact)
          else if (info == null)
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.l10n.dockNoAccountInfo,
                    style: TextStyle(fontSize: 12, color: colors.textSecondary),
                    overflow: compact ? null : TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                _RefreshButton(viewModel: viewModel, compact: compact),
              ],
            )
          else ...[
            // 等级、点数与刷新
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      AppBadge(
                        label: info.tierName,
                        shape: AppBadgeShape.pill,
                        variant: AppBadgeVariant.primary,
                      ),
                      Text(
                        '${info.totalAnlas} Anlas',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                _RefreshButton(viewModel: viewModel, compact: compact),
              ],
            ),

            // 仅在当前选择 V5 系列模型时展示体力进度条
            if (viewModel.params.model.isV5) ...[
              SizedBox(height: compact ? 0 : AppSpacing.sm),
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
                    child: AppProgressBar(
                      value: percent,
                      color: staminaColor,
                      backgroundColor: colors.mutedBackground,
                      height: 5,
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

          const SizedBox(height: AppSpacing.md),

          // 主操作按钮 (修复页签 = 开始修复；其余 = 生成图片)
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: isInpaintTab
                  ? colors.primary
                  : _buildButtonColor(context, estimatedCost),
              foregroundColor: Colors.white,
              minimumSize: compact ? const Size(0, 48) : null,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
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
                    style: TextStyle(
                      fontSize: compact ? 14 : 15,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                : ListenableBuilder(
                    // 生成中的步数文案仅随实时进度控制器局部刷新
                    listenable: viewModel.liveProgressController,
                    builder: (context, _) => Text(
                      _buildButtonLabel(context, estimatedCost),
                      style: TextStyle(
                        fontSize: compact ? 14 : 15,
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

  final bool compact;

  const _RefreshButton({required this.viewModel, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isLoading = viewModel.isLoadingAccount;
    if (compact) {
      return AppAsyncIconButton(
        isLoading: isLoading,
        icon: Icons.refresh_rounded,
        size: 48,
        iconSize: 20,
        variant: AppIconButtonVariant.ghost,
        tooltip: context.l10n.dockRefreshTooltip,
        onPressed: viewModel.refreshAccountInfo,
      );
    }
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

/// ComfyUI 模式状态行：连接状态点 + 文案 + 服务地址 + 刷新按钮
class _ComfyStatusRow extends StatelessWidget {
  final StudioViewModel viewModel;

  final bool compact;

  const _ComfyStatusRow({required this.viewModel, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final status = viewModel.comfyConnectionStatus;

    final statusColor = switch (status) {
      ComfyUiConnectionStatus.connected => colors.success,
      ComfyUiConnectionStatus.connecting => colors.warning,
      ComfyUiConnectionStatus.disconnected => colors.error,
    };
    final statusText = switch (status) {
      ComfyUiConnectionStatus.connected => l10n.comfyStatusConnected,
      ComfyUiConnectionStatus.connecting => l10n.comfyStatusConnecting,
      ComfyUiConnectionStatus.disconnected => l10n.comfyStatusDisconnected,
    };

    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                statusText,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              Text(
                viewModel.config.comfyUiBaseUrl,
                style: TextStyle(fontSize: 12, color: colors.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        if (compact)
          AppAsyncIconButton(
            isLoading: status == ComfyUiConnectionStatus.connecting,
            icon: Icons.refresh_rounded,
            size: 48,
            iconSize: 20,
            variant: AppIconButtonVariant.ghost,
            tooltip: l10n.dockRefreshTooltip,
            onPressed: viewModel.refreshComfyUiStatus,
          )
        else if (status == ComfyUiConnectionStatus.connecting)
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(statusColor),
            ),
          )
        else
          IconButton(
            icon: Icon(Icons.refresh, size: 17, color: colors.textSecondary),
            tooltip: l10n.dockRefreshTooltip,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(3),
            constraints: const BoxConstraints(),
            onPressed: () => viewModel.refreshComfyUiStatus(),
          ),
      ],
    );
  }
}
