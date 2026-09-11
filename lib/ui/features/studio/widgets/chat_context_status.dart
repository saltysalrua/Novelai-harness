import 'package:flutter/material.dart';

import '../../../../core/harness/context_memory.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../core/context_l10n.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../../core/widgets/app_progress_bar.dart';
import '../../../core/widgets/app_section_header.dart';

/// 请求上下文摘要；手机点按即可读取完整用量，不依赖鼠标悬停。
/// 接收展示快照，不持有 ViewModel 或操作会话记忆。
class ChatContextStatus extends StatelessWidget {
  final ContextUsage usage;
  final String modelName;
  final String sessionUsage;
  final bool compact;

  const ChatContextStatus({
    super.key,
    required this.usage,
    required this.modelName,
    required this.sessionUsage,
    this.compact = false,
  });

  String _status(AppLocalizations l10n) =>
      '${(usage.fraction * 100).toStringAsFixed(0)}% · ${l10n.chatContextNotes(usage.noteCount)}'
      '${usage.compacting
          ? ' · ${l10n.chatContextCompacting}'
          : usage.error != null
          ? ' · ${l10n.chatContextFailed}'
          : ''}';

  String _label(AppLocalizations l10n) =>
      '${l10n.chatContextEstimate(usage.tokens, usage.window)} · ${_status(l10n)}';

  void _showDetails(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: context.colors.cardBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (context) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppSectionHeader(
                title: context.l10n.chatContextTitle,
                trailing: AppIconButton(
                  icon: Icons.close_rounded,
                  size: 48,
                  iconSize: 20,
                  variant: AppIconButtonVariant.ghost,
                  tooltip: context.l10n.close,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              SelectableText(modelName),
              const SizedBox(height: AppSpacing.md),
              Text(
                _label(context.l10n),
                style: const TextStyle(fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                context.l10n.chatContextExplanation,
                style: TextStyle(
                  fontSize: 12,
                  color: context.colors.textSecondary,
                ),
              ),
              if (usage.error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                SelectableText(
                  usage.error!,
                  style: TextStyle(color: context.colors.error),
                ),
              ],
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: Divider(),
              ),
              SelectableText(
                sessionUsage,
                style: const TextStyle(fontSize: 13, height: 1.6),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = TextStyle(
      fontSize: 11,
      color: usage.error != null ? colors.error : colors.textSecondary,
    );
    final progress = AppProgressBar(
      value: usage.fraction,
      height: 2,
      color: usage.fraction >= 0.85 ? colors.error : colors.primary,
    );
    if (!compact) {
      return Tooltip(
        message:
            '${_label(context.l10n)}\n${usage.error ?? context.l10n.chatContextExplanation}',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_label(context.l10n), style: style),
            const SizedBox(height: AppSpacing.xs),
            progress,
          ],
        ),
      );
    }
    return Semantics(
      button: true,
      label: context.l10n.chatContextTitle,
      child: InkWell(
        key: const ValueKey('chat_context_details'),
        onTap: () => _showDetails(context),
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: AppSpacing.xs,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        context.l10n.chatContextEstimate(
                          usage.tokens,
                          usage.window,
                        ),
                        style: style,
                      ),
                      Text(_status(context.l10n), style: style),
                      const SizedBox(height: AppSpacing.xs),
                      progress,
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: colors.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
