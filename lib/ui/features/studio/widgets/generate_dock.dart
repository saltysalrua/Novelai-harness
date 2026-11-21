import 'package:flutter/material.dart';
import '../../../../data/models/comfyui_models.dart';
import '../../../../data/models/novelai_models.dart';
import '../../../core/context_l10n.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_async_icon_button.dart';
import '../../../core/widgets/app_badge.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../../core/widgets/app_progress_bar.dart';
import '../../../core/widgets/app_transitions.dart';
import '../view_models/studio_view_model.dart';
import 'studio_shared.dart';

/// 左侧面板底部常驻操作坞：统一状态条 (账号等级/点数/V5 体力 或 ComfyUI 状态) + 主操作按钮
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

  String _buildButtonLabel(BuildContext context, int cost) =>
      resolveGenerateActionLabel(
        context,
        isGenerating: viewModel.isGenerating,
        currentStep: viewModel.liveCurrentStep,
        totalSteps: viewModel.liveTotalSteps,
        estimatedCost: cost,
      );

  Color _buildButtonColor(BuildContext context, int cost) =>
      resolveGenerateActionColor(
        context,
        isGenerating: viewModel.isGenerating,
        estimatedCost: cost,
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        final colors = context.colors;
        final info = viewModel.accountInfo;
        final estimatedCost = viewModel.estimatedGenerationCost;
        // 修复页签下主按钮切换为「开始修复」(AI 整图编辑模式下为「开始 AI 编辑」)，
        // 其余页签为「生成图片」
        final isInpaintTab =
            viewModel.activeSidebarTab == StudioSidebarTab.inpaint;
        final isAiEditMode =
            isInpaintTab && viewModel.inpaintParams.mode == InpaintMode.aiEdit;
        final isRepairing =
            viewModel.isExecutingInpaint || viewModel.isExecutingAiEdit;

        final labelStyle = TextStyle(
          fontSize: compact ? 14 : 13.5,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
        );

        return Container(
          padding: EdgeInsets.fromLTRB(
            compact ? AppSpacing.md : 12,
            compact ? AppSpacing.sm : 8,
            compact ? AppSpacing.md : 12,
            compact ? AppSpacing.sm : 12,
          ),
          decoration: BoxDecoration(
            color: colors.cardBackground,
            border: Border(top: BorderSide(color: colors.borderSubtle)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 顶部状态条：ComfyUI Bridge 状态 / 未获取账号 / 账号点数与 V5 内联体力
              _StatusStripContainer(
                child: viewModel.isComfyUiMode
                    ? _ComfyStatusRow(viewModel: viewModel, compact: compact)
                    : (info == null
                          ? _EmptyAccountRow(
                              viewModel: viewModel,
                              compact: compact,
                            )
                          : _AccountStatusStrip(
                              viewModel: viewModel,
                              info: info,
                              compact: compact,
                            )),
              ),

              const SizedBox(height: AppSpacing.sm),

              // 主操作按钮 (修复页签 = 开始修复；其余 = 生成图片)
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isInpaintTab
                      ? colors.primary
                      : _buildButtonColor(context, estimatedCost),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: colors.mutedBackground,
                  disabledForegroundColor: colors.textMuted,
                  minimumSize: Size(double.infinity, compact ? 44 : 38),
                  padding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: compact ? 10 : 8,
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  elevation: 0,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
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
                icon: AppIconSwap(
                  swapKey: (isInpaintTab, isAiEditMode, viewModel.isGenerating),
                  enableBlur: false,
                  child: Icon(
                    isInpaintTab
                        ? (isAiEditMode
                              ? Icons.auto_awesome
                              : Icons.auto_fix_high_outlined)
                        : (viewModel.isGenerating
                              ? Icons.stop_circle_outlined
                              : Icons.auto_awesome),
                    size: 16,
                  ),
                ),
                label: isInpaintTab
                    ? (isRepairing
                          ? AppShimmerText(
                              text: isAiEditMode
                                  ? context.l10n.dockAiEditing
                                  : context.l10n.dockInpainting,
                              style: labelStyle,
                              baseColor: colors.textMuted,
                              highlightColor: colors.textPrimary,
                              textAlign: TextAlign.center,
                            )
                          : AppTextSwap(
                              text: isAiEditMode
                                  ? context.l10n.startAiEdit
                                  : context.l10n.startInpaint,
                              style: labelStyle,
                              textAlign: TextAlign.center,
                              alignment: Alignment.center,
                              enableBlur: false,
                            ))
                    : ListenableBuilder(
                        // 生成中的步数文案仅随实时进度控制器局部刷新
                        listenable: viewModel.liveProgressController,
                        builder: (context, _) {
                          final label = _buildButtonLabel(
                            context,
                            estimatedCost,
                          );
                          if (viewModel.isGenerating) {
                            return AppShimmerText(
                              text: label,
                              style: labelStyle,
                              baseColor: Colors.white.withValues(alpha: 0.78),
                              highlightColor: Colors.white,
                              textAlign: TextAlign.center,
                            );
                          }
                          return AppTextSwap(
                            text: label,
                            style: labelStyle,
                            textAlign: TextAlign.center,
                            alignment: Alignment.center,
                            enableBlur: false,
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 底部操作坞顶部统一状态条容器 (对齐工作台微边框胶囊容器语言)
class _StatusStripContainer extends StatelessWidget {
  final Widget child;

  const _StatusStripContainer({required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.mutedBackground.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: child,
    );
  }
}

/// 未获取账号信息时的紧凑状态行
class _EmptyAccountRow extends StatelessWidget {
  final StudioViewModel viewModel;
  final bool compact;

  const _EmptyAccountRow({required this.viewModel, required this.compact});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
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
    );
  }
}

/// 账号等级 / Anlas 点数 / V5 体力内联单行状态条 (极端窄宽自动折行)
class _AccountStatusStrip extends StatelessWidget {
  final StudioViewModel viewModel;
  final NaiAccountInfo info;
  final bool compact;

  const _AccountStatusStrip({
    required this.viewModel,
    required this.info,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final showStamina = viewModel.params.model.isV5;
    final percent = (info.staminaPercent / 100.0).clamp(0.0, 1.0);
    final staminaColor = info.staminaPercent >= 80
        ? colors.success
        : info.staminaPercent >= 30
        ? colors.warning
        : colors.error;

    return Row(
      children: [
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppBadge(
                    label: info.tierName,
                    shape: AppBadgeShape.rounded,
                    variant: AppBadgeVariant.primary,
                    fontSize: 10.5,
                  ),
                  const SizedBox(width: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppNumberPopIn(
                        value: '${info.totalAnlas}',
                        enableBlur: false,
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                      Text(
                        ' Anlas',
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (showStamina) ...[
                Container(
                  width: 1,
                  height: 12,
                  color: colors.borderDefault,
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      context.l10n.v5Stamina,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 38,
                      child: AppProgressBar(
                        value: percent,
                        color: staminaColor,
                        backgroundColor: colors.borderDefault.withValues(
                          alpha: 0.6,
                        ),
                        height: 4,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '${info.staminaPercent.toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                        color: staminaColor,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 6),
        _RefreshButton(viewModel: viewModel, compact: compact),
      ],
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
    return AppAsyncIconButton(
      isLoading: viewModel.isLoadingAccount,
      icon: Icons.refresh_rounded,
      size: compact ? 36 : 24,
      iconSize: compact ? 18 : 14,
      loadingIndicatorSize: compact ? 15 : 12,
      variant: AppIconButtonVariant.ghost,
      tooltip: context.l10n.dockRefreshTooltip,
      onPressed: () => viewModel.refreshAccountInfo(showError: true),
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
        AnimatedContainer(
          duration: AppMotion.resolveDuration(context, AppMotionDurations.quick),
          curve: AppMotionCurves.smoothOut,
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              AppTextSwap(
                text: statusText,
                enableBlur: false,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              Text(
                viewModel.config.comfyUiBaseUrl,
                style: TextStyle(
                  fontSize: 11.5,
                  fontFamily: 'monospace',
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        AppAsyncIconButton(
          isLoading: status == ComfyUiConnectionStatus.connecting,
          icon: Icons.refresh_rounded,
          size: compact ? 36 : 24,
          iconSize: compact ? 18 : 14,
          loadingIndicatorSize: compact ? 15 : 12,
          variant: AppIconButtonVariant.ghost,
          tooltip: l10n.dockRefreshTooltip,
          onPressed: viewModel.refreshComfyUiStatus,
        ),
      ],
    );
  }
}
