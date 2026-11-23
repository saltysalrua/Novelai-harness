import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../data/services/notification_history_service.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../core/context_l10n.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_badge.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/overlay_anchor.dart';
import '../view_models/studio_view_model.dart';

/// 通知中心触发按钮：复用 [AppIconButton] 并在存在未读记录时叠加右上角红点。
class NotificationBellButton extends StatelessWidget {
  final StudioViewModel viewModel;
  final double size;
  final double iconSize;

  const NotificationBellButton({
    super.key,
    required this.viewModel,
    this.size = 30.0,
    this.iconSize = 17.0,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        final hasUnread = viewModel.unreadNotificationCount > 0;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Builder(
              builder: (buttonContext) => AppIconButton(
                icon: Icons.notifications_none_rounded,
                size: size,
                iconSize: iconSize,
                variant: AppIconButtonVariant.ghost,
                tooltip: l10n.notificationsTooltip,
                onPressed: () => NotificationCenterPopover.show(
                  buttonContext,
                  viewModel: viewModel,
                ),
              ),
            ),
            if (hasUnread)
              Positioned(
                top: 4,
                right: 4,
                child: IgnorePointer(
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: colors.error,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: colors.cardBackground,
                        width: 1,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 全局通知与错误历史浮窗：展示本地持久化的最近 100 条通知，支持单条/批量复制与清理。
class NotificationCenterPopover extends StatefulWidget {
  final StudioViewModel viewModel;

  const NotificationCenterPopover({super.key, required this.viewModel});

  /// 锚定在触发按钮附近弹出通知历史浮窗，并在挂载首帧后自动标记为已读。
  static Future<void> show(
    BuildContext anchorContext, {
    required StudioViewModel viewModel,
  }) {
    return showAnchoredPopover<void>(
      context: anchorContext,
      preferAbove: false,
      gap: 6,
      minWidth: 340,
      maxWidth: 400,
      maxHeight: 460,
      builder: (_) => NotificationCenterPopover(viewModel: viewModel),
    );
  }

  @override
  State<NotificationCenterPopover> createState() =>
      _NotificationCenterPopoverState();
}

class _NotificationCenterPopoverState extends State<NotificationCenterPopover> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.viewModel.markAllNotificationsRead();
    });
  }

  String _sourceLabel(AppLocalizations l10n, AppNoticeSource source) =>
      switch (source) {
        AppNoticeSource.generation => l10n.notificationSourceGeneration,
        AppNoticeSource.inpaint => l10n.notificationSourceInpaint,
        AppNoticeSource.agent => l10n.notificationSourceAgent,
        AppNoticeSource.account => l10n.notificationSourceAccount,
        AppNoticeSource.comfyUi => l10n.notificationSourceComfyUi,
        AppNoticeSource.storage => l10n.notificationSourceStorage,
        AppNoticeSource.system => l10n.notificationSourceSystem,
      };

  String _formatTimestamp(DateTime ts) {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final isToday =
        ts.year == now.year && ts.month == now.month && ts.day == now.day;
    if (isToday) {
      return '${two(ts.hour)}:${two(ts.minute)}:${two(ts.second)}';
    }
    return '${two(ts.month)}-${two(ts.day)} ${two(ts.hour)}:${two(ts.minute)}';
  }

  String _formatRecordLine(AppLocalizations l10n, AppNoticeRecord record) {
    final time = _formatTimestamp(record.timestamp);
    final source = _sourceLabel(l10n, record.source);
    return '[$time][$source] ${record.message}';
  }

  void _copyText(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    showAppToast(
      context,
      message: context.l10n.notificationCenterCopied,
      tone: AppToastTone.success,
      duration: const Duration(seconds: 2),
      enableBlur: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = widget.viewModel;
    return KeyedSubtree(
      key: const Key('notification_center_popover'),
      child: ListenableBuilder(
        listenable: viewModel,
        builder: (context, _) {
          final colors = context.colors;
          final l10n = context.l10n;
          final records = viewModel.notificationHistory;

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 顶部标题栏 + 数量徽标 + 批量复制/清空
              Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: colors.borderSubtle),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.notifications_none_rounded,
                      size: 16,
                      color: colors.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      l10n.notificationCenterTitle,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    AppBadge(
                      label: '${records.length}',
                      variant: records.isNotEmpty
                          ? AppBadgeVariant.primary
                          : AppBadgeVariant.neutral,
                      fontSize: 10.5,
                    ),
                    const Spacer(),
                    if (records.isNotEmpty) ...[
                      AppIconButton(
                        key: const Key('notification_center_copy_all'),
                        icon: Icons.copy_all_rounded,
                        size: 26,
                        iconSize: 15,
                        radius: 6,
                        variant: AppIconButtonVariant.ghost,
                        tooltip: l10n.notificationCenterCopyAll,
                        onPressed: () {
                          final joined = records
                              .map((r) => _formatRecordLine(l10n, r))
                              .join('\n');
                          _copyText(context, joined);
                        },
                      ),
                      const SizedBox(width: 2),
                      AppIconButton(
                        key: const Key('notification_center_clear_all'),
                        icon: Icons.delete_sweep_outlined,
                        size: 26,
                        iconSize: 15,
                        radius: 6,
                        variant: AppIconButtonVariant.ghost,
                        tooltip: l10n.notificationCenterClearAll,
                        onPressed: viewModel.clearNotificationHistory,
                      ),
                    ],
                  ],
                ),
              ),

              // 列表区或空态
              if (records.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 28,
                  ),
                  child: AppEmptyState(
                    icon: Icons.notifications_none_rounded,
                    title: l10n.notificationCenterEmpty,
                    isCompact: true,
                    iconSize: 28,
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(10),
                    itemCount: records.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final record = records[index];
                      return _NotificationRecordCard(
                        record: record,
                        sourceLabel: _sourceLabel(l10n, record.source),
                        timestampLabel: _formatTimestamp(record.timestamp),
                        onCopy: () => _copyText(
                          context,
                          _formatRecordLine(l10n, record),
                        ),
                        onDelete: () => viewModel.removeNotification(record.id),
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _NotificationRecordCard extends StatelessWidget {
  final AppNoticeRecord record;
  final String sourceLabel;
  final String timestampLabel;
  final VoidCallback onCopy;
  final VoidCallback onDelete;

  const _NotificationRecordCard({
    required this.record,
    required this.sourceLabel,
    required this.timestampLabel,
    required this.onCopy,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final (Color accentColor, IconData levelIcon) = switch (record.level) {
      AppNoticeLevel.error => (colors.error, Icons.error_outline_rounded),
      AppNoticeLevel.warning => (colors.warning, Icons.warning_amber_rounded),
      AppNoticeLevel.info => (colors.info, Icons.info_outline_rounded),
    };

    return Container(
      decoration: BoxDecoration(
        color: colors.elevatedBackground,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.borderSubtle),
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(levelIcon, size: 14, color: accentColor),
              const SizedBox(width: 6),
              Text(
                sourceLabel,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: colors.textSecondary,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: Text(
                  '·',
                  style: TextStyle(fontSize: 11, color: colors.textMuted),
                ),
              ),
              Text(
                timestampLabel,
                style: TextStyle(
                  fontSize: 11,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: colors.textMuted,
                ),
              ),
              const Spacer(),
              AppIconButton(
                icon: Icons.copy_rounded,
                size: 22,
                iconSize: 13,
                radius: 5,
                variant: AppIconButtonVariant.ghost,
                tooltip: l10n.copy,
                onPressed: onCopy,
              ),
              const SizedBox(width: 2),
              AppIconButton(
                icon: Icons.close_rounded,
                size: 22,
                iconSize: 13,
                radius: 5,
                variant: AppIconButtonVariant.ghost,
                tooltip: l10n.delete,
                onPressed: onDelete,
              ),
            ],
          ),
          const SizedBox(height: 5),
          SelectableText(
            record.message,
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
