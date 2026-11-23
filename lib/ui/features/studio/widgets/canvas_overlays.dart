import 'dart:async';

import 'package:flutter/material.dart';
import '../../../../data/models/novelai_models.dart';
import '../../../core/context_l10n.dart';
import '../../../core/theme/app_colors_extension.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/app_floating_dock.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../../core/widgets/app_tool_chip.dart';
import '../../../core/widgets/app_transitions.dart';
import '../../settings/views/settings_dialog.dart';
import '../view_models/studio_view_model.dart';
import 'compact_prompt_popover.dart';
import 'image_canvas_actions.dart';
import 'notification_center_popover.dart';
import 'studio_shared.dart';

/// 画板浮层通用白底徽章装饰 (Notion 蓝白卡片，支持 context 语义色与无参回退)
BoxDecoration canvasBadgeDecoration([BuildContext? context]) {
  final bg = context != null
      ? context.colors.cardBackground
      : AppColorsExtension.light.cardBackground;
  final border = context != null
      ? context.colors.borderDefault
      : AppColorsExtension.light.borderDefault;
  final shadows = context != null
      ? context.shadowSubtle
      : [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ];

  return BoxDecoration(
    color: bg,
    borderRadius: BorderRadius.circular(AppRadius.md),
    border: Border.all(color: border),
    boxShadow: shadows,
  );
}

/// 左下角悬浮参数徽章：尺寸 + 种子 (种子点击复制) + 批注按钮
class CanvasParamBadges extends StatelessWidget {
  final NaiGeneratedImage image;
  final StudioViewModel? viewModel;

  const CanvasParamBadges({super.key, required this.image, this.viewModel});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    return AppCardResize(
      duration: AppMotionDurations.fast,
      curve: AppMotionCurves.smoothOut,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 尺寸徽章
          Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: canvasBadgeDecoration(context),
            alignment: Alignment.center,
            child: Text(
              '${image.params.width}  ×  ${image.params.height}',
              style: TextStyle(
                fontSize: 13,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 8),

          // 种子徽章 (点击可直接复制，非导入参考图时展示)
          if (!image.isImportedReference) ...[
            _SeedCopyBadge(seed: image.seed, compact: false),
            const SizedBox(width: 8),
          ],

          // 批注快捷按键
          if (viewModel != null)
            Tooltip(
              message: l10n.canvasEnterAnnotationTooltip,
              child: InkWell(
                onTap: () => viewModel!.board.setAnnotatingImage(
                  true,
                  targetImageId: image.id,
                ),
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: canvasBadgeDecoration(context),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.edit_note_rounded,
                        size: 17,
                        color: colors.primary,
                      ),
                      const SizedBox(width: 5),
                      AppTextSwap(
                        text: image.annotations.isEmpty
                            ? l10n.canvasAnnotate
                            : l10n.canvasAnnotateWithCount(
                                image.annotations.length,
                              ),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 可复用种子复制徽章：点击复制后图标平滑切换为绿色勾 (`09` + `10`)
class _SeedCopyBadge extends StatefulWidget {
  final int seed;
  final bool compact;

  const _SeedCopyBadge({required this.seed, required this.compact});

  @override
  State<_SeedCopyBadge> createState() => _SeedCopyBadgeState();
}

class _SeedCopyBadgeState extends State<_SeedCopyBadge> {
  bool _copied = false;
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  void _handleCopy() {
    copyTextWithSnackBar(
      context,
      '${widget.seed}',
      context.l10n.canvasCopiedSeed,
    );
    _resetTimer?.cancel();
    if (!_copied) {
      setState(() => _copied = true);
    }
    _resetTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() => _copied = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final iconSize = widget.compact ? 12.0 : 16.0;

    return Tooltip(
      message: l10n.canvasCopySeedTooltip,
      child: InkWell(
        onTap: _handleCopy,
        borderRadius: BorderRadius.circular(
          widget.compact ? AppRadius.sm : AppRadius.md,
        ),
        child: Container(
          height: widget.compact ? null : 38,
          padding: widget.compact
              ? const EdgeInsets.symmetric(horizontal: 6, vertical: 3)
              : const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: widget.compact
              ? BoxDecoration(
                  color: colors.mutedBackground,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                )
              : canvasBadgeDecoration(context),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIconSwap(
                swapKey: _copied,
                child: _copied
                    ? AppSuccessCheck(
                        key: const ValueKey<String>('seed-copied'),
                        size: iconSize,
                        color: colors.success,
                      )
                    : Icon(
                        Icons.eco_rounded,
                        key: const ValueKey<String>('seed-icon'),
                        size: iconSize,
                        color: colors.primary,
                      ),
              ),
              SizedBox(width: widget.compact ? 4 : 6),
              Text(
                '${widget.seed}',
                style: TextStyle(
                  fontSize: widget.compact ? 11 : 13,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                  color: widget.compact
                      ? colors.textSecondary
                      : colors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 右下角手动保存按钮 (自动保存关闭且当前图为未保存缓存图时展示)
class CanvasSaveButton extends StatelessWidget {
  final StudioViewModel viewModel;

  const CanvasSaveButton({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    return Tooltip(
      message: l10n.canvasSaveButtonTooltip,
      child: InkWell(
        onTap: () => saveOrExportSelectedCanvasImage(context, viewModel),
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: canvasBadgeDecoration(context),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.save_rounded, size: 17, color: colors.primary),
              const SizedBox(width: 6),
              Text(
                l10n.canvasSaveImage,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 顶部浮动提示：有新图片生成且用户正在浏览历史时显示，点击回到最新
class UnseenLatestBanner extends StatelessWidget {
  final VoidCallback onViewLatest;
  final VoidCallback onDismiss;

  const UnseenLatestBanner({
    super.key,
    required this.onViewLatest,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onViewLatest,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: colors.cardBackground,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
              color: colors.primary.withValues(alpha: 0.5),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: colors.primary.withValues(alpha: 0.12),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: colors.primaryTint,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.arrow_upward_rounded,
                  size: 13,
                  color: colors.primary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                context.l10n.canvasUnseenLatestBanner,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(width: 6),
              InkWell(
                onTap: onDismiss,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.all(2.0),
                  child: Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 右上角浮动 History 展开按键 (仅在侧边栏收回状态时显示)
class HistoryToggleButton extends StatelessWidget {
  final VoidCallback onTap;

  const HistoryToggleButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return AppIconButton(
      key: const Key('canvas_open_history_button'),
      icon: Icons.history_rounded,
      size: 38,
      iconSize: 20,
      variant: AppIconButtonVariant.elevated,
      tooltip: context.l10n.canvasOpenHistoryTooltip,
      onPressed: () {
        Tooltip.dismissAllToolTips();
        onTap();
      },
    );
  }
}

/// 窄屏/移动端画板底部统一操作栏：左侧分辨率/可复制种子 + 快捷操作 (修复 / 批注) + 固定右侧主要操作 (保存 / 更多)
/// 替代宽屏分散的左下参数徽章与右下保存按钮，彻底消除窄屏底栏碰撞重叠，并确保保存按钮在窄屏下始终前置可见无需滑动。
class MobileCanvasActionBar extends StatelessWidget {
  final NaiGeneratedImage image;
  final StudioViewModel viewModel;
  final VoidCallback? onInpaintPressed;

  const MobileCanvasActionBar({
    super.key,
    required this.image,
    required this.viewModel,
    this.onInpaintPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;

    return AppFloatingDock(
      key: const Key('mobile_canvas_action_bar'),
      radius: AppRadius.lg,
      enableBlur: true,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${image.params.width}×${image.params.height}',
                              style: TextStyle(
                                fontSize: 12,
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.w700,
                                color: colors.textPrimary,
                              ),
                            ),
                            if (!image.isImportedReference) ...[
                              const SizedBox(width: 8),
                              _SeedCopyBadge(seed: image.seed, compact: true),
                            ],
                          ],
                        ),
                        const SizedBox(width: 8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AppToolChip(
                              key: const Key('mobile_canvas_inpaint_button'),
                              icon: Icons.auto_fix_high_outlined,
                              label: l10n.sidebarTabInpaint,
                              variant: AppToolChipVariant.tinted,
                              fontSize: 11,
                              iconSize: 13,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 5,
                              ),
                              radius: AppRadius.sm + 2,
                              onTap: () {
                                viewModel.sendImageToInpaint(image);
                                onInpaintPressed?.call();
                              },
                            ),
                            const SizedBox(width: 4),
                            AppToolChip(
                              key: const Key('mobile_canvas_annotate_button'),
                              icon: Icons.edit_note_rounded,
                              label: image.annotations.isEmpty
                                  ? l10n.canvasAnnotate
                                  : l10n.canvasAnnotateWithCount(
                                      image.annotations.length,
                                    ),
                              variant: AppToolChipVariant.tinted,
                              fontSize: 11,
                              iconSize: 14,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 5,
                              ),
                              radius: AppRadius.sm + 2,
                              onTap: () => viewModel.board.setAnnotatingImage(
                                true,
                                targetImageId: image.id,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (image.isUnsaved) ...[
            const SizedBox(width: 6),
            AppToolChip(
              key: const Key('mobile_canvas_save_button'),
              icon: Icons.save_rounded,
              label: l10n.save,
              isSelected: true,
              variant: AppToolChipVariant.tinted,
              fontSize: 11,
              iconSize: 13,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              radius: AppRadius.sm + 2,
              onTap: () {
                if (viewModel.selectedImage?.id != image.id) {
                  viewModel.selectImage(image);
                }
                saveOrExportSelectedCanvasImage(context, viewModel);
              },
            ),
          ],
          const SizedBox(width: 6),
          AppIconButton(
            key: const Key('mobile_canvas_more_button'),
            icon: Icons.more_horiz_rounded,
            size: 28,
            iconSize: 16,
            variant: AppIconButtonVariant.outlined,
            tooltip: MaterialLocalizations.of(context).showMenuTooltip,
            onPressed: () => showMobileImageActionSheet(
              context,
              viewModel: viewModel,
              image: image,
            ),
          ),
        ],
      ),
    );
  }
}

/// 画板空状态占位 (无历史图且未在生成时展示)
class CanvasEmptyState extends StatelessWidget {
  final StudioViewModel? viewModel;

  const CanvasEmptyState({super.key, this.viewModel});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppEmptyState(
      icon: Icons.palette_outlined,
      title: l10n.canvasEmptyTitle,
      description: l10n.canvasEmptyDescription,
      iconSize: 54,
      actionLabel: viewModel != null ? l10n.canvasActionReadMetadata : null,
      actionIcon: viewModel != null ? Icons.image_search_outlined : null,
      onActionPressed: viewModel != null
          ? () => pickAndInspectImageMetadata(context, viewModel!)
          : null,
    );
  }
}

/// 画板快捷生成 / 终止按钮 (窄屏画板底栏与宽屏收起左卡片时复用，支持直接重复出图)
class CanvasQuickGenerateButton extends StatelessWidget {
  final StudioViewModel viewModel;
  final bool compact;
  final bool iconOnly;

  const CanvasQuickGenerateButton({
    super.key,
    required this.viewModel,
    this.compact = false,
    this.iconOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        viewModel,
        viewModel.liveProgressController,
      ]),
      builder: (context, _) {
        final isGenerating = viewModel.isGenerating;
        final estimatedCost = viewModel.estimatedGenerationCost;
        final bgColor = resolveGenerateActionColor(
          context,
          isGenerating: isGenerating,
          estimatedCost: estimatedCost,
        );
        final fullTooltip = resolveGenerateActionLabel(
          context,
          isGenerating: isGenerating,
          currentStep: viewModel.liveCurrentStep,
          totalSteps: viewModel.liveTotalSteps,
          estimatedCost: estimatedCost,
          compact: false,
        );
        final label = resolveGenerateActionLabel(
          context,
          isGenerating: isGenerating,
          currentStep: viewModel.liveCurrentStep,
          totalSteps: viewModel.liveTotalSteps,
          estimatedCost: estimatedCost,
          compact: compact,
        );
        final height = compact ? 40.0 : 38.0;
        final radius = compact ? AppRadius.lg : AppRadius.md;
        final fgColor = (!isGenerating && estimatedCost == 0)
            ? context.colors.onPrimary
            : Colors.white;

        return Tooltip(
          message: fullTooltip,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: const Key('canvas_quick_generate_button'),
              onTap: isGenerating
                  ? () => viewModel.abortGeneration()
                  : () => viewModel.generateImage(),
              borderRadius: BorderRadius.circular(radius),
              child: Container(
                width: iconOnly ? height : null,
                height: height,
                padding: iconOnly
                    ? EdgeInsets.zero
                    : EdgeInsets.symmetric(
                        horizontal: compact ? 12 : 14,
                        vertical: 8,
                      ),
                alignment: iconOnly ? Alignment.center : null,
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(radius),
                  border: Border.all(
                    color: fgColor.withValues(alpha: 0.14),
                  ),
                  boxShadow: context.shadowElevated,
                ),
                child: iconOnly
                    ? AppIconSwap(
                        swapKey: isGenerating,
                        enableBlur: false,
                        child: Icon(
                          isGenerating
                              ? Icons.stop_circle_outlined
                              : Icons.auto_awesome,
                          key: ValueKey<bool>(isGenerating),
                          size: 18,
                          color: fgColor,
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AppIconSwap(
                            swapKey: isGenerating,
                            enableBlur: false,
                            child: Icon(
                              isGenerating
                                  ? Icons.stop_circle_outlined
                                  : Icons.auto_awesome,
                              key: ValueKey<bool>(isGenerating),
                              size: 16,
                              color: fgColor,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: compact ? 12.5 : 13,
                              fontWeight: FontWeight.w600,
                              color: fgColor,
                              fontFeatures: isGenerating
                                  ? const [FontFeature.tabularFigures()]
                                  : null,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 宽屏收起左侧栏与左卡片时，画板左上角的轻量快捷悬浮条：
/// 展开左侧栏 + 弹出精简提示词浮窗 + 不拉出左卡片直达「词库」「设置」。
class CanvasCollapsedQuickDock extends StatefulWidget {
  final StudioViewModel viewModel;

  const CanvasCollapsedQuickDock({super.key, required this.viewModel});

  @override
  State<CanvasCollapsedQuickDock> createState() =>
      _CanvasCollapsedQuickDockState();
}

class _CanvasCollapsedQuickDockState extends State<CanvasCollapsedQuickDock> {
  bool _isPromptPopoverOpen = false;

  Future<void> _openCompactPromptPopover(BuildContext anchorContext) async {
    if (_isPromptPopoverOpen) return;
    setState(() => _isPromptPopoverOpen = true);
    try {
      await CompactPromptPopover.show(
        anchorContext,
        viewModel: widget.viewModel,
      );
    } finally {
      if (mounted) {
        setState(() => _isPromptPopoverOpen = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final viewModel = widget.viewModel;

    return AppFloatingDock(
      key: const Key('canvas_collapsed_quick_dock'),
      radius: AppRadius.lg,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      enableBlur: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIconButton(
            key: const Key('canvas_expand_sidebar_button'),
            icon: Icons.keyboard_double_arrow_right_rounded,
            size: 30,
            iconSize: 17,
            variant: AppIconButtonVariant.ghost,
            tooltip: l10n.sidebarExpandTooltip,
            onPressed: viewModel.toggleLeftSidebarCollapsed,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Container(width: 1, height: 18, color: colors.borderSubtle),
          ),
          AppToolChip(
            key: const Key('canvas_collapsed_library_button'),
            icon: Icons.collections_bookmark_outlined,
            label: l10n.tabLibrary,
            tooltip: l10n.tabLibrary,
            variant: AppToolChipVariant.tinted,
            fontSize: 12,
            iconSize: 14,
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            radius: AppRadius.md,
            onTap: () => viewModel.setActiveSidebarTab(
              StudioSidebarTab.library,
              expandSidebar: false,
            ),
          ),
          const SizedBox(width: 2),
          Builder(
            builder: (buttonContext) => AppIconButton(
              key: const Key('canvas_collapsed_prompts_button'),
              icon: Icons.edit_note_outlined,
              size: 30,
              iconSize: 17,
              variant: AppIconButtonVariant.ghost,
              backgroundColor: _isPromptPopoverOpen ? colors.primaryTint : null,
              iconColor: _isPromptPopoverOpen ? colors.primary : null,
              tooltip: l10n.canvasQuickPromptTooltip,
              onPressed: () => _openCompactPromptPopover(buttonContext),
            ),
          ),
          const SizedBox(width: 2),
          NotificationBellButton(
            key: const Key('canvas_collapsed_notifications_button'),
            viewModel: viewModel,
            size: 30,
            iconSize: 16,
          ),
          const SizedBox(width: 2),
          AppIconButton(
            key: const Key('canvas_collapsed_settings_button'),
            icon: Icons.settings_outlined,
            size: 30,
            iconSize: 16,
            variant: AppIconButtonVariant.ghost,
            tooltip: l10n.settings,
            onPressed: () => SettingsDialog.show(context, viewModel),
          ),
        ],
      ),
    );
  }
}
