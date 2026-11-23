import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../data/services/session_log_service.dart';
import '../../../../data/services/usage_ledger_service.dart';
import '../../../core/context_l10n.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_action_button.dart';
import '../../../core/widgets/app_badge.dart';
import '../../../core/widgets/app_confirm_dialog.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../../core/widgets/app_prompt_dialog.dart';
import '../../../core/widgets/app_search_field.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/app_toggle_controls.dart';
import '../../../core/widgets/app_transitions.dart';
import '../../../core/widgets/context_menu.dart';
import '../../../core/widgets/smooth_scroll_controller.dart';
import '../../../core/widgets/stable_scrollbar.dart';
import '../view_models/studio_view_model.dart';

/// Agent 会话管理列表全卡片视图
///
/// Notion 极简列表布局：柔底无框卡片、右键/菜单上下文操作、
/// 平滑滚轮与 ESC 退焦返回。
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
  final SmoothWheelScrollController _scrollController =
      SmoothWheelScrollController();
  String _searchQuery = '';
  bool _selecting = false;
  bool _busy = false;
  final Set<String> _selectedIds = {};
  bool _initialRevealDone = false;
  Timer? _revealTimer;

  void _toggleSelected(String id) => setState(() {
    if (!_selectedIds.add(id)) _selectedIds.remove(id);
  });

  Future<void> _runAction(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        showAppToast(
          context,
          message: '$error',
          tone: AppToastTone.error,
          enableBlur: false,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteSelected() async {
    final ids = _selectedIds.toList(growable: false);
    if (ids.isEmpty) return;
    final confirmed = await showAppConfirmDialog(
      context,
      title: context.l10n.sessionDeleteTitle,
      message: context.l10n.sessionDeleteBatchConfirm(ids.length),
      confirmLabel: context.l10n.sessionDeleteConfirmButton,
      cancelLabel: context.l10n.sessionCancel,
      isDestructive: true,
    );
    if (!mounted || confirmed != true) return;
    await _runAction(() async {
      await widget.viewModel.deleteSessions(ids);
      if (mounted) setState(() => _selectedIds.removeAll(ids));
    });
  }

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
    _revealTimer = Timer(const Duration(milliseconds: 550), () {
      if (mounted) setState(() => _initialRevealDone = true);
    });
  }

  @override
  void dispose() {
    _revealTimer?.cancel();
    _scrollController.dispose();
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
      title: context.l10n.sessionRenameTitle,
      initialValue: session.title,
      hintText: context.l10n.sessionRenameHint,
      icon: Icons.edit_outlined,
      confirmLabel: context.l10n.sessionSave,
      cancelLabel: context.l10n.sessionCancel,
    );
    if (mounted && newName != null && newName.trim().isNotEmpty) {
      await _runAction(
        () => widget.viewModel.renameSession(session.id, newName.trim()),
      );
    }
  }

  void _showDeleteConfirmDialog(SessionInfo session) async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: context.l10n.sessionDeleteTitle,
      message: context.l10n.sessionDeleteConfirm(session.title),
      confirmLabel: context.l10n.sessionDeleteConfirmButton,
      cancelLabel: context.l10n.sessionCancel,
      isDestructive: true,
    );
    if (mounted && confirmed == true) {
      await _runAction(() => widget.viewModel.deleteSession(session.id));
    }
  }

  void _showSessionContextMenu(
    BuildContext context,
    SessionInfo session,
    Offset position,
  ) {
    final l10n = context.l10n;
    showStudioContextMenu(
      context,
      position: position,
      actions: [
        ContextMenuItem(
          icon: Icons.edit_outlined,
          label: l10n.sessionRenameAction,
          onTap: _busy ? null : () => _showRenameDialog(session),
        ),
        ContextMenuItem(
          icon: Icons.delete_outline_rounded,
          label: l10n.sessionDeleteAction,
          isDestructive: true,
          onTap: _busy ? null : () => _showDeleteConfirmDialog(session),
        ),
      ],
    );
  }

  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final isToday =
        dt.year == now.year && dt.month == now.month && dt.day == now.day;
    String two(int n) => n.toString().padLeft(2, '0');
    if (isToday) {
      return '${two(dt.hour)}:${two(dt.minute)}';
    }
    return context.l10n.sessionDateFormat(
      dt.month,
      dt.day,
      '${two(dt.hour)}:${two(dt.minute)}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final sessions = widget.viewModel.sessions;
    final filtered = _getFilteredSessions(sessions);
    final currentId = widget.viewModel.currentSessionId;
    _selectedIds.retainAll(sessions.map((session) => session.id));
    final theme = ScrollbarTheme.of(context);

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent ||
            event.logicalKey != LogicalKeyboardKey.escape) {
          return KeyEventResult.ignored;
        }
        final primary = FocusManager.instance.primaryFocus;
        final editingText =
            primary?.context?.findAncestorStateOfType<EditableTextState>() !=
            null;
        if (editingText) {
          primary!.unfocus();
          return KeyEventResult.handled;
        }
        if (_selecting) {
          setState(() {
            _selecting = false;
            _selectedIds.clear();
          });
          return KeyEventResult.handled;
        }
        if (!_busy) widget.onBack();
        return KeyEventResult.handled;
      },
      child: Card(
        margin: EdgeInsets.zero,
        color: colors.cardBackground,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 顶部导航栏与新建按钮
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
                    tooltip: l10n.sessionBackTooltip,
                    size: 28,
                    iconSize: 14,
                    variant: AppIconButtonVariant.ghost,
                    onPressed: _busy ? null : widget.onBack,
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.forum_outlined, size: 15, color: colors.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            l10n.sessionTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                        if (sessions.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          AppBadge.pill(
                            label: '${sessions.length}',
                            variant: AppBadgeVariant.neutral,
                            fontSize: 10,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  AppActionButton(
                    icon: Icons.add_rounded,
                    label: l10n.sessionNew,
                    variant: AppActionButtonVariant.primary,
                    iconSize: 14,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    onPressed: _busy
                        ? null
                        : () => _runAction(() async {
                            await widget.viewModel.createNewSession();
                            if (mounted) widget.onBack();
                          }),
                  ),
                ],
              ),
            ),

            // 搜索栏
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: AppSearchField(
                controller: _searchController,
                hintText: l10n.sessionSearchHint,
                height: 34,
                fontSize: 12,
                debounceDuration: Duration.zero,
                onClear: () => _searchController.clear(),
              ),
            ),

            // 批量管理与计数条
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              child: SizedBox(
                height: 30,
                child: Row(
                  children: [
                    if (_selecting) ...[
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: AppCheckbox(
                          value:
                              filtered.isNotEmpty &&
                              filtered.every((s) => _selectedIds.contains(s.id)),
                          size: 16.0,
                          onChanged: _busy || filtered.isEmpty
                              ? null
                              : (value) => setState(() {
                                  final ids = filtered.map((s) => s.id);
                                  if (value) {
                                    _selectedIds.addAll(ids);
                                  } else {
                                    _selectedIds.removeAll(ids);
                                  }
                                }),
                          semanticLabel: l10n.sessionSelectAll,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          l10n.sessionSelectedCount(_selectedIds.length),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                      AppIconButton(
                        icon: Icons.delete_outline_rounded,
                        size: 28,
                        iconSize: 16,
                        tooltip: l10n.sessionDeleteAction,
                        iconColor: colors.error,
                        variant: AppIconButtonVariant.ghost,
                        onPressed: _busy || _selectedIds.isEmpty
                            ? null
                            : _deleteSelected,
                      ),
                    ] else ...[
                      if (_searchQuery.isNotEmpty)
                        Text(
                          '${filtered.length} / ${sessions.length}',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: colors.textMuted,
                          ),
                        ),
                      const Spacer(),
                    ],
                    InkWell(
                      onTap: _busy
                          ? null
                          : () => setState(() {
                              _selecting = !_selecting;
                              _selectedIds.clear();
                            }),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 4,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!_selecting) ...[
                              Icon(
                                Icons.checklist_rounded,
                                size: 13.5,
                                color: colors.textSecondary,
                              ),
                              const SizedBox(width: 4),
                            ],
                            Text(
                              _selecting
                                  ? l10n.sessionCancel
                                  : l10n.sessionManage,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                                color: _selecting
                                    ? colors.primary
                                    : colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_busy) const LinearProgressIndicator(minHeight: 2),

            // 会话列表
            Expanded(
              child: filtered.isEmpty
                  ? AppEmptyState(
                      icon: Icons.chat_bubble_outline_rounded,
                      iconSize: 32,
                      title: _searchQuery.isNotEmpty
                          ? l10n.sessionNoMatchingTitle
                          : l10n.sessionEmptyTitle,
                      isCompact: true,
                    )
                  : StableScrollbar(
                      controller: _scrollController,
                      thumbColor: theme.thumbColor?.resolve({}),
                      thickness: theme.thickness?.resolve({}),
                      radius: theme.radius,
                      child: ScrollConfiguration(
                        behavior: ScrollConfiguration.of(
                          context,
                        ).copyWith(scrollbars: false),
                        child: ListView.separated(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                          itemCount: filtered.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 6),
                          itemBuilder: (context, index) {
                            final item = filtered[index];
                            final isCurrent = item.id == currentId;
                            final card = _buildSessionCard(item, isCurrent);
                            final skipReveal = _initialRevealDone || index >= 8;
                            return AppStaggerReveal(
                              key: ValueKey('session_reveal_${item.id}'),
                              index: index,
                              maxStaggerIndex: 8,
                              distance: AppMotionDistances.base,
                              duration: skipReveal
                                  ? Duration.zero
                                  : AppMotionDurations.fast,
                              staggerDelay: skipReveal
                                  ? Duration.zero
                                  : AppMotionDurations.stagger,
                              enableBlur: false,
                              child: card,
                            );
                          },
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionCard(SessionInfo session, bool isCurrent) {
    final colors = context.colors;
    final l10n = context.l10n;
    final isSelectedInBatch = _selecting && _selectedIds.contains(session.id);
    final preview = session.preview.trim();
    final modelId = session.modelId?.trim() ?? '';

    return _SessionCardSurface(
      isCurrent: isCurrent,
      isBatchSelected: isSelectedInBatch,
      onContextMenu: _selecting || _busy
          ? null
          : (pos) => _showSessionContextMenu(context, session, pos),
      onTap: _busy
          ? null
          : () {
              if (_selecting) {
                _toggleSelected(session.id);
                return;
              }
              _runAction(() async {
                if (!isCurrent) {
                  await widget.viewModel.switchSession(session.id);
                }
                if (mounted) widget.onBack();
              });
            },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头部：标题 + 当前会话标签 + 更多菜单
          Row(
            children: [
              if (_selecting)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: AppCheckbox(
                    value: isSelectedInBatch,
                    size: 16.0,
                    onChanged: _busy
                        ? null
                        : (_) => _toggleSelected(session.id),
                    semanticLabel: session.title,
                  ),
                ),
              if (isCurrent) ...[
                AppBadge.pill(
                  label: l10n.sessionCurrentBadge,
                  variant: AppBadgeVariant.primary,
                  customBackgroundColor: colors.primary,
                  customForegroundColor: colors.onPrimary,
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
              if (!_selecting)
                Builder(
                  builder: (btnCtx) => AppIconButton(
                    icon: Icons.more_horiz_rounded,
                    size: 24,
                    iconSize: 15,
                    variant: AppIconButtonVariant.ghost,
                    onPressed: _busy
                        ? null
                        : () {
                            final box =
                                btnCtx.findRenderObject() as RenderBox?;
                            if (box == null) return;
                            final pos = box.localToGlobal(
                              Offset(box.size.width, box.size.height),
                            );
                            _showSessionContextMenu(btnCtx, session, pos);
                          },
                  ),
                ),
            ],
          ),
          if (preview.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              preview,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                color: colors.textSecondary,
                height: 1.38,
              ),
            ),
          ],
          const SizedBox(height: 7),

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
                l10n.sessionMessageCount(session.messageCount),
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
              if (modelId.isNotEmpty) ...[
                const SizedBox(width: 6),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: isCurrent
                          ? colors.cardBackground.withValues(alpha: 0.7)
                          : colors.cardBackground,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Text(
                      modelId,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        fontFamily: 'monospace',
                        color: colors.textMuted,
                      ),
                    ),
                  ),
                ),
              ],
              if (session.totalTokens > 0) ...[
                if (modelId.isEmpty) const Spacer() else const SizedBox(width: 6),
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
    );
  }
}

/// 会话卡片外框：Notion 柔底低噪表面 + 悬停微抬升 + 当前/选中态主色描边
class _SessionCardSurface extends StatefulWidget {
  final bool isCurrent;
  final bool isBatchSelected;
  final VoidCallback? onTap;
  final ValueChanged<Offset>? onContextMenu;
  final Widget child;

  const _SessionCardSurface({
    required this.isCurrent,
    this.isBatchSelected = false,
    required this.onTap,
    this.onContextMenu,
    required this.child,
  });

  @override
  State<_SessionCardSurface> createState() => _SessionCardSurfaceState();
}

class _SessionCardSurfaceState extends State<_SessionCardSurface> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final reduce = AppMotion.shouldReduceMotion(context);
    final duration = AppMotion.resolveDuration(
      context,
      AppMotionDurations.quick,
    );
    final highlighted = widget.isCurrent || widget.isBatchSelected;
    final bgColor = highlighted
        ? colors.primaryTint.withValues(alpha: 0.5)
        : (_hovered
              ? colors.mutedBackground.withValues(alpha: 0.75)
              : colors.elevatedBackground);
    final borderColor = highlighted
        ? colors.primary.withValues(alpha: _hovered ? 0.85 : 0.6)
        : (_hovered
              ? colors.borderHover
              : colors.borderHover.withValues(alpha: 0.0));

    return MouseRegion(
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: _hovered && !reduce ? -1.5 : 0.0),
        duration: duration,
        curve: AppMotionCurves.smoothOut,
        builder: (context, dy, child) =>
            Transform.translate(offset: Offset(0, dy), child: child),
        child: StudioContextMenuRegion(
          onShow: widget.onContextMenu,
          child: InkWell(
            onTap: widget.onTap,
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
                  width: highlighted ? 1.5 : 1,
                ),
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}
