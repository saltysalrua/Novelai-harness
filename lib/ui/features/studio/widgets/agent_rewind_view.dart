import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/context_l10n.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_action_button.dart';
import '../../../core/widgets/app_badge.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../../core/widgets/app_transitions.dart';
import '../../../core/widgets/smooth_scroll_controller.dart';
import '../../../core/widgets/stable_scrollbar.dart';
import '../view_models/chat_checkpoints.dart';
import '../view_models/studio_view_model.dart';

/// 全屏覆盖 Agent Card 的历史时刻回溯视图 (按两次 ESC 调出，参考 Pi 的对话时刻回溯)
///
/// Notion 极简时间线布局：柔和无框浅底卡片、默认定位到最新轮次、
/// 支持上下方向键选择 + Enter 确认回溯 + ESC 退出。
class AgentRewindView extends StatefulWidget {
  final StudioViewModel viewModel;
  final VoidCallback onBack;

  /// 窄屏/触屏紧凑形态：隐藏「Esc 退出」徽章 (移动端通常无物理键盘)
  final bool compact;

  const AgentRewindView({
    super.key,
    required this.viewModel,
    required this.onBack,
    this.compact = false,
  });

  @override
  State<AgentRewindView> createState() => _AgentRewindViewState();
}

class _AgentRewindViewState extends State<AgentRewindView> {
  int? _selectedCheckpointIndex;
  final FocusNode _focusNode = FocusNode();
  final SmoothWheelScrollController _scrollController =
      SmoothWheelScrollController();
  final Map<int, GlobalKey> _itemKeys = {};
  bool _initialRevealDone = false;
  Timer? _revealTimer;
  bool _confirming = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
      if (_scrollController.hasClients &&
          _scrollController.position.hasContentDimensions) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
    _revealTimer = Timer(const Duration(milliseconds: 450), () {
      if (mounted) setState(() => _initialRevealDone = true);
    });
  }

  @override
  void dispose() {
    _revealTimer?.cancel();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  List<ChatCheckpoint> _extractCheckpoints() =>
      extractChatCheckpoints(widget.viewModel.messages);

  String _formatTime(DateTime? dt) {
    if (dt == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }

  void _scrollToCheckpoint(int index) {
    final key = _itemKeys[index];
    final ctx = key?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: AppMotion.resolveDuration(context, AppMotionDurations.quick),
        curve: AppMotionCurves.smoothOut,
        alignment: 0.5,
      );
    }
  }

  Future<void> _confirmRewind(List<ChatCheckpoint> checkpoints) async {
    if (_confirming ||
        _selectedCheckpointIndex == null ||
        _selectedCheckpointIndex! < 0 ||
        _selectedCheckpointIndex! >= checkpoints.length) {
      return;
    }

    final target = checkpoints[_selectedCheckpointIndex!];
    setState(() => _confirming = true);
    try {
      // 截断到该条用户消息之前，内容放回输入框，不发送。
      await widget.viewModel.rewindToMessage(target.userMessage.id);
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
    if (!mounted) return;
    widget.onBack();
  }

  KeyEventResult _handleKeyEvent(
    FocusNode node,
    KeyEvent event,
    List<ChatCheckpoint> checkpoints,
  ) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (event is KeyDownEvent) widget.onBack();
      return KeyEventResult.handled;
    }
    if (checkpoints.isEmpty) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      final current = _selectedCheckpointIndex;
      final next = current == null
          ? checkpoints.length - 1
          : (current - 1).clamp(0, checkpoints.length - 1);
      setState(() => _selectedCheckpointIndex = next);
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _scrollToCheckpoint(next),
      );
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      final current = _selectedCheckpointIndex;
      final next = current == null
          ? 0
          : (current + 1).clamp(0, checkpoints.length - 1);
      setState(() => _selectedCheckpointIndex = next);
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _scrollToCheckpoint(next),
      );
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent &&
        (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter) &&
        _selectedCheckpointIndex != null) {
      _confirmRewind(checkpoints);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final checkpoints = _extractCheckpoints();
    final selected = _selectedCheckpointIndex;
    final hasSelection =
        selected != null && selected >= 0 && selected < checkpoints.length;

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: (node, event) => _handleKeyEvent(node, event, checkpoints),
      child: Card(
        margin: EdgeInsets.zero,
        color: colors.cardBackground,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 顶部导航栏
            Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: colors.cardBackground,
                border: Border(bottom: BorderSide(color: colors.borderSubtle)),
              ),
              child: Row(
                children: [
                  AppIconButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    tooltip: l10n.rewindBackTooltip,
                    size: 28,
                    iconSize: 14,
                    variant: AppIconButtonVariant.ghost,
                    onPressed: widget.onBack,
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.history_rounded, size: 15, color: colors.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            l10n.rewindTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                        if (checkpoints.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          AppBadge.pill(
                            label: '${checkpoints.length}',
                            variant: AppBadgeVariant.neutral,
                            fontSize: 10,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (!widget.compact)
                    AppBadge(
                      label: l10n.rewindEscExit,
                      variant: AppBadgeVariant.neutral,
                      shape: AppBadgeShape.pill,
                      fontSize: 10,
                    ),
                ],
              ),
            ),

            // 轻量说明提示条 (柔底无框，复用已有的 rewindDescription)
            if (checkpoints.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: colors.elevatedBackground,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 1.5),
                        child: Icon(
                          Icons.info_outline_rounded,
                          size: 13,
                          color: colors.textMuted,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          l10n.rewindDescription,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: colors.textSecondary,
                            height: 1.38,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // 轮次列表区域
            Expanded(
              child: checkpoints.isEmpty
                  ? AppEmptyState(
                      icon: Icons.history_toggle_off_rounded,
                      iconSize: 32,
                      title: l10n.rewindEmptyTitle,
                      actionLabel: l10n.rewindBackAction,
                      actionIcon: Icons.arrow_back,
                      onActionPressed: widget.onBack,
                      isCompact: true,
                    )
                  : _buildCheckpointList(context, checkpoints),
            ),

            // 底部操作坞
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: colors.cardBackground,
                border: Border(top: BorderSide(color: colors.borderSubtle)),
              ),
              child: SizedBox(
                width: double.infinity,
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    AppTextSwap(
                      text: hasSelection
                          ? l10n.rewindSelectedTurn(checkpoints[selected].index)
                          : (checkpoints.isNotEmpty
                                ? l10n.rewindSelectPrompt
                                : ''),
                      enableBlur: false,
                      duration: AppMotionDurations.quick,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: hasSelection
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: hasSelection
                            ? colors.primary
                            : colors.textMuted,
                      ),
                    ),
                    Wrap(
                      alignment: WrapAlignment.end,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        AppActionButton(
                          label: l10n.rewindCancelButton,
                          variant: AppActionButtonVariant.ghost,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          onPressed: widget.onBack,
                        ),
                        AppActionButton(
                          label: l10n.rewindConfirmButton,
                          variant: AppActionButtonVariant.primary,
                          isLoading: _confirming,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          onPressed: hasSelection && !_confirming
                              ? () => _confirmRewind(checkpoints)
                              : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckpointList(
    BuildContext context,
    List<ChatCheckpoint> checkpoints,
  ) {
    final colors = context.colors;
    final l10n = context.l10n;
    final theme = ScrollbarTheme.of(context);

    final list = ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      itemCount: checkpoints.length,
      separatorBuilder: (context, index) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final cp = checkpoints[index];
        final isSelected = _selectedCheckpointIndex == index;
        final isLastTurn = index == checkpoints.length - 1;
        final itemKey = _itemKeys.putIfAbsent(index, GlobalKey.new);

        final card = _CheckpointCard(
          key: itemKey,
          isSelected: isSelected,
          onTap: () {
            _focusNode.requestFocus();
            setState(() => _selectedCheckpointIndex = index);
          },
          onDoubleTap: () {
            setState(() => _selectedCheckpointIndex = index);
            _confirmRewind(checkpoints);
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AppBadge.pill(
                    label: '#${cp.index}',
                    variant: isSelected
                        ? AppBadgeVariant.primary
                        : AppBadgeVariant.neutral,
                    customBackgroundColor: isSelected
                        ? colors.primary
                        : colors.cardBackground,
                    customForegroundColor: isSelected ? colors.onPrimary : null,
                    fontSize: 10.5,
                  ),
                  if (isLastTurn) ...[
                    const SizedBox(width: 6),
                    Text(
                      l10n.rewindLatestBadge,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: colors.success,
                      ),
                    ),
                  ],
                  const Spacer(),
                  Text(
                    _formatTime(cp.userMessage.createdAt),
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: colors.textMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),

              // 用户 Prompt 预览
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1.5),
                    child: Icon(
                      Icons.keyboard_arrow_right_rounded,
                      size: 14,
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Expanded(
                    child: Text(
                      cp.userMessage.content,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),

              // 助手回复摘要 (Notion 引用左竖线)
              if (cp.assistantMessage != null &&
                  cp.assistantMessage!.content.isNotEmpty) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.only(left: 8),
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        color: isSelected
                            ? colors.primary.withValues(alpha: 0.4)
                            : colors.borderHover,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Text(
                    cp.assistantMessage!.content,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: colors.textSecondary,
                      height: 1.35,
                    ),
                  ),
                ),
              ],

              // 工具调用胶囊
              if (cp.toolMessages.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: cp.toolMessages.map((t) {
                    return AppBadge(
                      label: t.toolName ?? l10n.toolFallbackName,
                      variant: AppBadgeVariant.neutral,
                      customBackgroundColor: colors.cardBackground,
                      shape: AppBadgeShape.rounded,
                      fontSize: 10,
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        );

        if (index < 8) {
          return AppStaggerReveal(
            key: ValueKey('rewind_stagger_${cp.index}'),
            index: index,
            duration: _initialRevealDone
                ? Duration.zero
                : AppMotionDurations.fast,
            staggerDelay: _initialRevealDone
                ? Duration.zero
                : AppMotionDurations.stagger,
            distance: AppMotionDistances.base,
            maxStaggerIndex: 8,
            child: card,
          );
        }
        return card;
      },
    );

    return StableScrollbar(
      controller: _scrollController,
      thumbColor: theme.thumbColor?.resolve({}),
      thickness: theme.thickness?.resolve({}),
      radius: theme.radius,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: list,
      ),
    );
  }
}

/// 回溯时刻卡片：柔底无框低噪质感，悬停平滑高光与微抬升，选中态主色描边。
class _CheckpointCard extends StatefulWidget {
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final Widget child;

  const _CheckpointCard({
    super.key,
    required this.isSelected,
    required this.onTap,
    required this.onDoubleTap,
    required this.child,
  });

  @override
  State<_CheckpointCard> createState() => _CheckpointCardState();
}

class _CheckpointCardState extends State<_CheckpointCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final reduce = AppMotion.shouldReduceMotion(context);
    final duration = AppMotion.resolveDuration(
      context,
      AppMotionDurations.quick,
    );
    final bgColor = widget.isSelected
        ? colors.primaryTint.withValues(alpha: 0.55)
        : (_hovered
              ? colors.mutedBackground.withValues(alpha: 0.75)
              : colors.elevatedBackground);
    final borderColor = widget.isSelected
        ? colors.primary.withValues(alpha: 0.65)
        : (_hovered
              ? colors.borderHover
              : colors.borderHover.withValues(alpha: 0.0));

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: _hovered && !reduce ? -1.5 : 0.0),
        duration: duration,
        curve: AppMotionCurves.smoothOut,
        builder: (context, dy, child) =>
            Transform.translate(offset: Offset(0, dy), child: child),
        child: InkWell(
          onTap: widget.onTap,
          onDoubleTap: widget.onDoubleTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: AnimatedContainer(
            duration: duration,
            curve: AppMotionCurves.smoothOut,
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: borderColor,
                width: widget.isSelected ? 1.5 : 1,
              ),
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
