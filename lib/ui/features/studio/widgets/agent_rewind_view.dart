import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_theme.dart';
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 顶部导航栏
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppTheme.border)),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded, size: 18),
                    tooltip: '返回对话 (ESC)',
                    color: AppTheme.textPrimary,
                    visualDensity: VisualDensity.compact,
                    onPressed: widget.onBack,
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.history_rounded,
                    size: 16,
                    color: AppTheme.notionBlue,
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    '回溯历史时刻',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.stone.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                    ),
                    child: const Text(
                      'ESC 退出',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 说明提示栏
            Container(
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: AppTheme.paperWarmth,
                borderRadius: BorderRadius.circular(AppTheme.radiusButton),
                border: Border.all(color: AppTheme.border),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 13,
                    color: AppTheme.textSecondary,
                  ),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '选择要回退到的对话时刻。确认后将撤销此时刻之后的所有修改与对话记录。',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
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
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.history_toggle_off_rounded,
                            size: 32,
                            color: AppTheme.stone,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '当前会话暂无历史对话轮次可回溯',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textMuted,
                            ),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.arrow_back, size: 14),
                            label: const Text(
                              '返回对话',
                              style: TextStyle(fontSize: 12),
                            ),
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  AppTheme.radiusButton,
                                ),
                              ),
                            ),
                            onPressed: widget.onBack,
                          ),
                        ],
                      ),
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
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusCard,
                          ),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppTheme.skyTint.withValues(alpha: 0.5)
                                  : AppTheme.pureWhite,
                              borderRadius: BorderRadius.circular(
                                AppTheme.radiusCard,
                              ),
                              border: Border.all(
                                color: isSelected
                                    ? AppTheme.notionBlue
                                    : AppTheme.border,
                                width: isSelected ? 1.5 : 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 1.5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? AppTheme.notionBlue
                                            : AppTheme.stone.withValues(
                                                alpha: 0.15,
                                              ),
                                        borderRadius: BorderRadius.circular(
                                          AppTheme.radiusPill,
                                        ),
                                      ),
                                      child: Text(
                                        '#${cp.index}',
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w700,
                                          color: isSelected
                                              ? Colors.white
                                              : AppTheme.textSecondary,
                                        ),
                                      ),
                                    ),
                                    if (isLastTurn) ...[
                                      const SizedBox(width: 6),
                                      const Text(
                                        '(最新时刻)',
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.success,
                                        ),
                                      ),
                                    ],
                                    const Spacer(),
                                    Text(
                                      _formatTime(cp.userMessage.createdAt),
                                      style: const TextStyle(
                                        fontSize: 10.5,
                                        color: AppTheme.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),

                                // 用户 Prompt 预览
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Padding(
                                      padding: EdgeInsets.only(top: 1.5),
                                      child: Icon(
                                        Icons.keyboard_arrow_right,
                                        size: 13,
                                        color: AppTheme.notionBlue,
                                      ),
                                    ),
                                    const SizedBox(width: 3),
                                    Expanded(
                                      child: Text(
                                        cp.userMessage.content,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.textPrimary,
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
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                ],

                                // 工具调用胶囊
                                if (cp.toolMessages.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Wrap(
                                    spacing: 4,
                                    children: cp.toolMessages.map((t) {
                                      return Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 5,
                                          vertical: 1,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppTheme.paperWarmth,
                                          borderRadius: BorderRadius.circular(
                                            3,
                                          ),
                                          border: Border.all(
                                            color: AppTheme.border,
                                          ),
                                        ),
                                        child: Text(
                                          t.toolName ?? 'tool',
                                          style: const TextStyle(
                                            fontSize: 9.5,
                                            fontFamily: 'monospace',
                                            color: AppTheme.textMuted,
                                          ),
                                        ),
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
              decoration: const BoxDecoration(
                color: AppTheme.paperWarmth,
                border: Border(top: BorderSide(color: AppTheme.border)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _selectedCheckpointIndex != null
                          ? '已选择第 #${checkpoints[_selectedCheckpointIndex!].index} 轮对话'
                          : '请在上方列表中选择要回退的轮次',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppTheme.textSecondary,
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
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppTheme.radiusButton,
                        ),
                      ),
                    ),
                    onPressed: widget.onBack,
                    child: const Text('取消', style: TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.notionBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppTheme.radiusButton,
                        ),
                      ),
                    ),
                    onPressed: _selectedCheckpointIndex != null
                        ? () => _confirmRewind(checkpoints)
                        : null,
                    child: const Text('回到此时刻', style: TextStyle(fontSize: 12)),
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
