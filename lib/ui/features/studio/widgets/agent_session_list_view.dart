import 'package:flutter/material.dart';
import '../../../../data/services/session_log_service.dart';
import '../../../../data/services/usage_ledger_service.dart';
import '../../../core/theme/app_theme.dart';
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

  void _showRenameDialog(SessionInfo session) {
    final controller = TextEditingController(text: session.title);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        ),
        title: const Row(
          children: [
            Icon(Icons.edit_outlined, size: 18, color: AppTheme.notionBlue),
            SizedBox(width: 8),
            Text(
              '重命名会话',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary),
          decoration: InputDecoration(
            hintText: '请输入会话新名称...',
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusButton),
              borderSide: const BorderSide(color: AppTheme.border),
            ),
          ),
          onSubmitted: (val) {
            final text = val.trim();
            if (text.isNotEmpty) {
              widget.viewModel.renameSession(session.id, text);
              Navigator.of(ctx).pop();
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.notionBlue,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusButton),
              ),
            ),
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) {
                widget.viewModel.renameSession(session.id, text);
                Navigator.of(ctx).pop();
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmDialog(SessionInfo session) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        ),
        title: const Row(
          children: [
            Icon(Icons.delete_outline_rounded, size: 18, color: AppTheme.error),
            SizedBox(width: 8),
            Text(
              '删除会话',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        content: Text(
          '确定要永久删除会话 "${session.title}" 吗？此操作无法撤销。',
          style: const TextStyle(fontSize: 12.5, color: AppTheme.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.error,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusButton),
              ),
            ),
            onPressed: () {
              widget.viewModel.deleteSession(session.id);
              Navigator.of(ctx).pop();
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final isToday = dt.year == now.year && dt.month == now.month && dt.day == now.day;
    String two(int n) => n.toString().padLeft(2, '0');
    if (isToday) {
      return '${two(dt.hour)}:${two(dt.minute)}';
    }
    return '${dt.month}月${dt.day}日 ${two(dt.hour)}:${two(dt.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final sessions = widget.viewModel.sessions;
    final filtered = _getFilteredSessions(sessions);
    final currentId = widget.viewModel.currentSessionId;

    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 顶部导航栏与新建按钮
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppTheme.border)),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    size: 15,
                    color: AppTheme.textSecondary,
                  ),
                  tooltip: '返回对话',
                  onPressed: widget.onBack,
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.forum_outlined,
                  size: 16,
                  color: AppTheme.notionBlue,
                ),
                const SizedBox(width: 6),
                const Text(
                  '会话管理',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const Spacer(),
                FilledButton.icon(
                  icon: const Icon(Icons.add_rounded, size: 15),
                  label: const Text(
                    '新建会话',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.notionBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusButton),
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
            child: TextField(
              controller: _searchController,
              style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  size: 16,
                  color: AppTheme.textMuted,
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 14),
                        color: AppTheme.textMuted,
                        onPressed: () => _searchController.clear(),
                      )
                    : null,
                hintText: '搜索历史会话...',
                hintStyle: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                fillColor: AppTheme.paperWarmth,
                filled: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusButton),
                  borderSide: const BorderSide(color: AppTheme.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusButton),
                  borderSide: const BorderSide(color: AppTheme.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusButton),
                  borderSide: const BorderSide(
                    color: AppTheme.notionBlue,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),

          // 会话列表
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 32,
                          color: AppTheme.stone,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _searchQuery.isNotEmpty
                              ? '未找到匹配的会话'
                              : '暂无历史会话记录',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                    itemCount: filtered.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 6),
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
    return InkWell(
      onTap: () async {
        if (!isCurrent) {
          await widget.viewModel.switchSession(session.id);
        }
        widget.onBack();
      },
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isCurrent
              ? AppTheme.skyTint.withValues(alpha: 0.5)
              : AppTheme.pureWhite,
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          border: Border.all(
            color: isCurrent
                ? AppTheme.notionBlue.withValues(alpha: 0.7)
                : AppTheme.border,
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
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1.5,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.notionBlue,
                      borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                    ),
                    child: const Text(
                      '当前',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
                Expanded(
                  child: Text(
                    session.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(
                    Icons.more_vert_rounded,
                    size: 15,
                    color: AppTheme.textMuted,
                  ),
                  padding: EdgeInsets.zero,
                  splashRadius: 16,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                  ),
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'rename',
                      height: 32,
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined, size: 14, color: AppTheme.textSecondary),
                          SizedBox(width: 8),
                          Text('重命名', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      height: 32,
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline, size: 14, color: AppTheme.error),
                          SizedBox(width: 8),
                          Text('删除', style: TextStyle(fontSize: 12, color: AppTheme.error)),
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
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.textSecondary,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 6),

            // 底部元数据: 消息数、最后修改时间、模型与 Token 用量
            Row(
              children: [
                const Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: 11,
                  color: AppTheme.textMuted,
                ),
                const SizedBox(width: 3),
                Text(
                  '${session.messageCount} 条',
                  style: const TextStyle(fontSize: 10.5, color: AppTheme.textMuted),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.access_time_rounded,
                  size: 11,
                  color: AppTheme.textMuted,
                ),
                const SizedBox(width: 3),
                Text(
                  _formatDateTime(session.lastModified),
                  style: const TextStyle(fontSize: 10.5, color: AppTheme.textMuted),
                ),
                if (session.totalTokens > 0) ...[
                  const Spacer(),
                  const Icon(
                    Icons.token_outlined,
                    size: 11,
                    color: AppTheme.notionBlue,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    UsageLedgerService.formatTokens(session.totalTokens),
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.notionBlue,
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
