import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../../data/models/novelai_models.dart';
import '../../../core/context_l10n.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_badge.dart';
import '../../../core/widgets/app_page_stack.dart';
import '../view_models/studio_view_model.dart';
import 'generate_dock.dart';
import 'inpaint_canvas_overlay.dart';
import 'inpaint_page.dart';
import 'parameters_page.dart';
import 'prompts_page.dart';

/// 左侧工作台面板：三页面 (参数设置 / 提示词管理 / 修复设置) + 底部生成操作坞。
/// 各页首次访问时挂载，隐藏页不随工作台通知重建；切页保留输入与滚动位置。
/// 窄屏 (`compact == true`) 下在局部修复页签同屏整合修复画板与可折叠参数抽屉。
class ParameterCard extends StatelessWidget {
  final StudioViewModel viewModel;
  final StudioSidebarTab activeTab;
  final bool compact;

  const ParameterCard({
    super.key,
    required this.viewModel,
    this.activeTab = StudioSidebarTab.parameters,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final pageIndex = switch (activeTab) {
      StudioSidebarTab.parameters => 0,
      StudioSidebarTab.prompts => 1,
      StudioSidebarTab.inpaint => 2,
      StudioSidebarTab.library => 0,
    };

    return ExcludeSemantics(
      // The root is not the only exclusion: expose the active workstation
      // page to macOS assistive technology as well.
      excluding: kIsWeb || defaultTargetPlatform != TargetPlatform.macOS,
      child: Card(
        margin: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 页面主体 (根据侧边栏 Tab 切换)
            Expanded(
              child: AppPageStack(
                index: pageIndex,
                itemCount: 3,
                itemBuilder: (context, index) => switch (index) {
                  0 => ParametersPage(viewModel: viewModel),
                  1 => PromptsPage(viewModel: viewModel),
                  _ => compact
                      ? _MobileUnifiedInpaintWorkspace(viewModel: viewModel)
                      : InpaintPage(viewModel: viewModel),
                },
              ),
            ),

            // 底部常驻操作面板 (账号/体力/免点/刷新 + 主操作按钮：生成图片/开始修复)
            GenerateDock(viewModel: viewModel, compact: compact),
          ],
        ),
      ),
    );
  }
}

/// 窄屏端局部修复同屏工作台：上方蒙版画板 + 中部可折叠参数抽屉 + 底部共用生成坞
class _MobileUnifiedInpaintWorkspace extends StatefulWidget {
  final StudioViewModel viewModel;

  const _MobileUnifiedInpaintWorkspace({required this.viewModel});

  @override
  State<_MobileUnifiedInpaintWorkspace> createState() =>
      _MobileUnifiedInpaintWorkspaceState();
}

class _MobileUnifiedInpaintWorkspaceState
    extends State<_MobileUnifiedInpaintWorkspace> {
  bool _paramsExpanded = true;
  bool _wasExecuting = false;

  @override
  void initState() {
    super.initState();
    _wasExecuting =
        widget.viewModel.isExecutingInpaint ||
        widget.viewModel.isExecutingAiEdit;
    widget.viewModel.addListener(_onViewModelChanged);
  }

  @override
  void didUpdateWidget(covariant _MobileUnifiedInpaintWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewModel != widget.viewModel) {
      oldWidget.viewModel.removeListener(_onViewModelChanged);
      _wasExecuting =
          widget.viewModel.isExecutingInpaint ||
          widget.viewModel.isExecutingAiEdit;
      widget.viewModel.addListener(_onViewModelChanged);
    }
  }

  @override
  void dispose() {
    widget.viewModel.removeListener(_onViewModelChanged);
    super.dispose();
  }

  void _onViewModelChanged() {
    final isExecuting =
        widget.viewModel.isExecutingInpaint ||
        widget.viewModel.isExecutingAiEdit;
    if (!_wasExecuting && isExecuting && _paramsExpanded && mounted) {
      setState(() => _paramsExpanded = false);
    }
    _wasExecuting = isExecuting;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final inpaint = widget.viewModel.inpaintParams;
    final modeLabel = switch (inpaint.mode) {
      InpaintMode.focus => l10n.inpaintModeFocus,
      InpaintMode.standard => l10n.inpaintModeStandard,
      InpaintMode.aiEdit => l10n.inpaintModeAiEdit,
    };
    final summaryLabel = inpaint.mode == InpaintMode.aiEdit
        ? modeLabel
        : '$modeLabel · ${(inpaint.strength * 100).round()}% / ${(inpaint.noise * 100).round()}%';

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxDrawerHeight = constraints.maxHeight > 120
            ? math.min(220.0, constraints.maxHeight * 0.45)
            : 120.0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. 顶部修复画板 (无滚动干扰，蒙版描边与源图严格对齐)
            Expanded(
              child: ColoredBox(
                color: colors.canvasBackground,
                child: InpaintRepairCanvas(viewModel: widget.viewModel),
              ),
            ),

            // 2. 可折叠参数抽屉开关头
            InkWell(
              key: const Key('mobile_inpaint_params_toggle'),
              onTap: () => setState(() => _paramsExpanded = !_paramsExpanded),
              child: Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: colors.cardBackground,
                  border: Border(
                    top: BorderSide(color: colors.borderDefault),
                    bottom: _paramsExpanded
                        ? BorderSide(color: colors.borderSubtle)
                        : BorderSide.none,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.tune_rounded, size: 15, color: colors.primary),
                    const SizedBox(width: 6),
                    Text(
                      l10n.tabInpaint,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: AppBadge.pill(
                          label: summaryLabel,
                          variant: AppBadgeVariant.neutral,
                          fontSize: 10,
                        ),
                      ),
                    ),
                    Icon(
                      _paramsExpanded
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.keyboard_arrow_up_rounded,
                      size: 18,
                      color: colors.textSecondary,
                    ),
                  ],
                ),
              ),
            ),

            // 3. 修复参数面板 (保持状态保活，收起时不占高度)
            Visibility(
              visible: _paramsExpanded,
              maintainState: true,
              child: SizedBox(
                height: maxDrawerHeight,
                child: InpaintPage(viewModel: widget.viewModel),
              ),
            ),
          ],
        );
      },
    );
  }
}
