import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/context_l10n.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_badge.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../view_models/chat_checkpoints.dart';
import '../view_models/studio_view_model.dart';

/// 全屏覆盖 Agent Card 的历史时刻回溯视图 (按两次 ESC 调出，参考 Pi 的对话时刻回溯)
class AgentRewindView extends StatefulWidget {
  final StudioViewModel viewModel;
  final VoidCallback onBack;

  const AgentRewindView({
    super.key,
    required this.viewModel,
    required this.onBack,
  });

  @override
  State<AgentRewindView> createState() => _AgentRewindViewState();
}

class _AgentRewindViewState extends State<AgentRewindView> {
  int? _selectedCheckpointIndex;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
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

  void _confirmRewind(List<ChatCheckpoint> checkpoints) {
    if (_selectedCheckpointIndex == null ||
        _selectedCheckpointIndex! < 0 ||
        _selectedCheckpointIndex! >= checkpoints.length) {
      return;
    }

    final target = checkpoints[_selectedCheckpointIndex!];
    // 回溯至目标用户消息处并撤销后续修改
    widget.viewModel.rewindToMessage(target.userMessage.id);
    widget.onBack();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final checkpoints = _extractCheckpoints();

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          widget.onBack();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Card(
        margin: EdgeInsets.zero,
        color: colors.cardBackground,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 顶部导航栏
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: colors.cardBackground,
                border: Border(bottom: BorderSide(color: colors.borderDefault)),
              ),
              child: Row(
                children: [
                  AppIconButton(
                    icon: Icons.arrow_back_rounded,
                    tooltip: context.l10n.rewindBackTooltip,
                    size: 28,
                    variant: AppIconButtonVariant.ghost,
                    onPressed: widget.onBack,
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.history_rounded, size: 15, color: colors.primary),
                  const SizedBox(width: 6),
                  Text(
                    context.l10n.rewindTitle,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  AppBadge(
                    label: context.l10n.rewindEscExit,
                    variant: AppBadgeVariant.neutral,
                    shape: AppBadgeShape.pill,
                    fontSize: 10,
                  ),
                ],
              ),
            ),

            // 说明提示栏
            Container(
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: colors.canvasBackground,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: colors.borderDefault),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 13,
                    color: colors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      context.l10n.rewindDescription,
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.textSecondary,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 轮次列表区域
            Expanded(
              child: checkpoints.isEmpty
                  ? AppEmptyState(
                      icon: Icons.history_toggle_off_rounded,
                      iconSize: 32,
                      title: context.l10n.rewindEmptyTitle,
                      actionLabel: context.l10n.rewindBackAction,
                      actionIcon: Icons.arrow_back,
                      onActionPressed: widget.onBack,
                      isCompact: true,
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                      itemCount: checkpoints.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final cp = checkpoints[index];
                        final isSelected = _selectedCheckpointIndex == index;
                        final isLastTurn = index == checkpoints.length - 1;

                        return InkWell(
                          onTap: () =>
                              setState(() => _selectedCheckpointIndex = index),
                          onDoubleTap: () {
                            setState(() => _selectedCheckpointIndex = index);
                            _confirmRewind(checkpoints);
                          },
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? colors.primaryTint.withValues(alpha: 0.5)
                                  : colors.cardBackground,
                              borderRadius: BorderRadius.circular(AppRadius.lg),
                              border: Border.all(
                                color: isSelected
                                    ? colors.primary
                                    : colors.borderDefault,
                                width: isSelected ? 1.5 : 1,
                              ),
                            ),
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
                                          : null,
                                      customForegroundColor: isSelected
                                          ? Colors.white
                                          : null,
                                      fontSize: 11,
                                    ),
                                    if (isLastTurn) ...[
                                      const SizedBox(width: 6),
                                      Text(
                                        context.l10n.rewindLatestBadge,
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
                                        color: colors.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),

                                // 用户 Prompt 预览
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(top: 1.5),
                                      child: Icon(
                                        Icons.keyboard_arrow_right,
                                        size: 13,
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
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: colors.textPrimary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),

                                // 助手回复摘要
                                if (cp.assistantMessage != null &&
                                    cp
                                        .assistantMessage!
                                        .content
                                        .isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    cp.assistantMessage!.content,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: colors.textSecondary,
                                    ),
                                  ),
                                ],

                                // 工具调用胶囊
                                if (cp.toolMessages.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Wrap(
                                    spacing: 4,
                                    children: cp.toolMessages.map((t) {
                                      return AppBadge(
                                        label: t.toolName ?? 'tool',
                                        variant: AppBadgeVariant.neutral,
                                        shape: AppBadgeShape.rounded,
                                        fontSize: 10,
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),

            // 底部操作坞
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: colors.canvasBackground,
                border: Border(top: BorderSide(color: colors.borderDefault)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _selectedCheckpointIndex != null
                          ? context.l10n.rewindSelectedTurn(
                              checkpoints[_selectedCheckpointIndex!].index,
                            )
                          : context.l10n.rewindSelectPrompt,
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      visualDensity: VisualDensity.compact,
                      side: BorderSide(color: colors.borderDefault),
                      foregroundColor: colors.textPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                    ),
                    onPressed: widget.onBack,
                    child: Text(
                      context.l10n.rewindCancelButton,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                    ),
                    onPressed: _selectedCheckpointIndex != null
                        ? () => _confirmRewind(checkpoints)
                        : null,
                    child: Text(
                      context.l10n.rewindConfirmButton,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
