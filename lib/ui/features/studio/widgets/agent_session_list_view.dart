import 'package:flutter/material.dart';
import '../../../../data/services/session_log_service.dart';
import '../../../../data/services/usage_ledger_service.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_badge.dart';
import '../../../core/widgets/app_confirm_dialog.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../../core/widgets/app_prompt_dialog.dart';
import '../../../core/widgets/app_search_field.dart';
import '../view_models/studio_view_model.dart';

/// Agent 会话管理列表全卡片视图
///
/// 替换 AgentCard 整体内容，提供会话浏览、切换、新建、重命名与删除管理。
class AgentSessionListView extends StatefulWidget {
  final StudioViewModel viewModel;
  final VoidCallback onBack;

  const AgentSessionListView({
    super.key,
    required this.viewModel,
    required this.onBack,
  });

  @override
  State<AgentSessionListView> createState() => _AgentSessionListViewState();
}

class _AgentSessionListViewState extends State<AgentSessionListView> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
    // 打开时刷新最新列表
    widget.viewModel.refreshSessions();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<SessionInfo> _getFilteredSessions(List<SessionInfo> allSessions) {
    if (_searchQuery.isEmpty) return allSessions;
    return allSessions.where((s) {
      return s.title.toLowerCase().contains(_searchQuery) ||
          s.preview.toLowerCase().contains(_searchQuery) ||
          (s.modelId?.toLowerCase().contains(_searchQuery) ?? false);
    }).toList();
  }

  void _showRenameDialog(SessionInfo session) async {
    final newName = await showAppPromptDialog(
      context,
      title: '重命名会话',
      initialValue: session.title,
      hintText: '请输入会话新名称...',
      icon: Icons.edit_outlined,
      confirmLabel: '保存',
      cancelLabel: '取消',
    );
    if (newName != null && newName.trim().isNotEmpty) {
      widget.viewModel.renameSession(session.id, newName.trim());
    }
  }

  void _showDeleteConfirmDialog(SessionInfo session) async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: '删除会话',
      message: '确定要永久删除会话 "${session.title}" 吗？此操作无法撤销。',
      confirmLabel: '删除',
      cancelLabel: '取消',
      isDestructive: true,
    );
    if (confirmed == true) {
      widget.viewModel.deleteSession(session.id);
    }
  }

  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final isToday =
        dt.year == now.year && dt.month == now.month && dt.day == now.day;
    String two(int n) => n.toString().padLeft(2, '0');
    if (isToday) {
      return '${two(dt.hour)}:${two(dt.minute)}';
    }
    return '${dt.month}月${dt.day}日 ${two(dt.hour)}:${two(dt.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final sessions = widget.viewModel.sessions;
    final filtered = _getFilteredSessions(sessions);
    final currentId = widget.viewModel.currentSessionId;

    return Card(
      margin: EdgeInsets.zero,
      color: colors.cardBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 顶部导航栏与新建按钮
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
                  icon: Icons.arrow_back_ios_new_rounded,
                  tooltip: '返回对话',
                  size: 28,
                  iconSize: 14,
                  variant: AppIconButtonVariant.ghost,
                  onPressed: widget.onBack,
                ),
                const SizedBox(width: 4),
                Icon(Icons.forum_outlined, size: 15, color: colors.primary),
                const SizedBox(width: 6),
                Text(
                  '会话管理',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                const Spacer(),
                FilledButton.icon(
                  icon: const Icon(Icons.add_rounded, size: 14),
                  label: const Text(
                    '新建会话',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    minimumSize: const Size(0, 30),
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                  ),
                  onPressed: () async {
                    await widget.viewModel.createNewSession();
                    widget.onBack();
                  },
                ),
              ],
            ),
          ),

          // 搜索与过滤栏
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: AppSearchField(
              controller: _searchController,
              hintText: '搜索历史会话...',
              height: 34,
              fontSize: 12,
              debounceDuration: Duration.zero,
              onClear: () => _searchController.clear(),
            ),
          ),

          // 会话列表
          Expanded(
            child: filtered.isEmpty
                ? AppEmptyState(
                    icon: Icons.chat_bubble_outline_rounded,
                    iconSize: 32,
                    title: _searchQuery.isNotEmpty ? '未找到匹配的会话' : '暂无历史会话记录',
                    isCompact: true,
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                    itemCount: filtered.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      final isCurrent = item.id == currentId;
                      return _buildSessionCard(item, isCurrent);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionCard(SessionInfo session, bool isCurrent) {
    final colors = context.colors;
    return InkWell(
      onTap: () async {
        if (!isCurrent) {
          await widget.viewModel.switchSession(session.id);
        }
        widget.onBack();
      },
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isCurrent
              ? colors.primaryTint.withValues(alpha: 0.5)
              : colors.cardBackground,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: isCurrent
                ? colors.primary.withValues(alpha: 0.7)
                : colors.borderDefault,
            width: isCurrent ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 头部：标题 + 当前会话标签 + 操作菜单
            Row(
              children: [
                if (isCurrent) ...[
                  AppBadge.pill(
                    label: '当前',
                    variant: AppBadgeVariant.primary,
                    customBackgroundColor: colors.primary,
                    customForegroundColor: Colors.white,
                    fontSize: 10,
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    session.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert_rounded,
                    size: 15,
                    color: colors.textMuted,
                  ),
                  padding: EdgeInsets.zero,
                  splashRadius: 16,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    side: BorderSide(color: colors.borderDefault),
                  ),
                  color: colors.cardBackground,
                  itemBuilder: (ctx) => [
                    PopupMenuItem(
                      value: 'rename',
                      height: 32,
                      child: Row(
                        children: [
                          Icon(
                            Icons.edit_outlined,
                            size: 14,
                            color: colors.textSecondary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '重命名',
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      height: 32,
                      child: Row(
                        children: [
                          Icon(
                            Icons.delete_outline,
                            size: 14,
                            color: colors.error,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '删除',
                            style: TextStyle(fontSize: 12, color: colors.error),
                          ),
                        ],
                      ),
                    ),
                  ],
                  onSelected: (action) {
                    if (action == 'rename') {
                      _showRenameDialog(session);
                    } else if (action == 'delete') {
                      _showDeleteConfirmDialog(session);
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 4),

            // 摘要预览
            Text(
              session.preview,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: colors.textSecondary,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 6),

            // 底部元数据: 消息数、最后修改时间、模型与 Token 用量
            Row(
              children: [
                Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: 11,
                  color: colors.textMuted,
                ),
                const SizedBox(width: 3),
                Text(
                  '${session.messageCount} 条',
                  style: TextStyle(fontSize: 11, color: colors.textMuted),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.access_time_rounded,
                  size: 11,
                  color: colors.textMuted,
                ),
                const SizedBox(width: 3),
                Text(
                  _formatDateTime(session.lastModified),
                  style: TextStyle(fontSize: 11, color: colors.textMuted),
                ),
                if (session.totalTokens > 0) ...[
                  const Spacer(),
                  Icon(Icons.token_outlined, size: 11, color: colors.primary),
                  const SizedBox(width: 3),
                  Text(
                    UsageLedgerService.formatTokens(session.totalTokens),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: colors.primary,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
