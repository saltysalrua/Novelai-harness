import 'package:flutter/material.dart';

import '../../../../core/harness/context_memory.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../core/context_l10n.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../../core/widgets/app_section_header.dart';
import '../../../core/widgets/app_transitions.dart';
import '../../../core/widgets/overlay_anchor.dart';

/// 请求上下文用量环形胶囊；桌面悬停看摘要，桌面/手机点按均可弹出完整用量面板。
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
    showAnchoredPopover<void>(
      context: context,
      preferAbove: false,
      maxWidth: 320,
      maxHeight: 380,
      builder: (popoverContext) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppSectionHeader(
              title: popoverContext.l10n.chatContextTitle,
              trailing: AppIconButton(
                icon: Icons.close_rounded,
                size: 32,
                iconSize: 18,
                variant: AppIconButtonVariant.ghost,
                tooltip: popoverContext.l10n.close,
                onPressed: () => Navigator.of(popoverContext).pop(),
              ),
            ),
            SelectableText(modelName),
            const SizedBox(height: AppSpacing.md),
            Text(
              _label(popoverContext.l10n),
              style: const TextStyle(fontSize: 13, height: 1.5),
            ),
            if (usage.error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              SelectableText(
                usage.error!,
                style: TextStyle(color: popoverContext.colors.error),
              ),
            ],
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Divider(),
            ),
            SelectableText(
              sessionUsage,
              style: const TextStyle(fontSize: 13, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final progressColor = usage.error != null || usage.fraction >= 0.85
        ? colors.error
        : (usage.fraction >= 0.7 ? colors.warning : colors.primary);
    final percentText = '${(usage.fraction * 100).round()}%';

    return Tooltip(
      message: usage.error != null
          ? '${_label(l10n)}\n${usage.error}'
          : _label(l10n),
      child: Semantics(
        button: true,
        label: l10n.chatContextTitle,
        child: InkWell(
          key: const ValueKey('chat_context_details'),
          onTap: () => _showDetails(context),
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 28),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: AppIconSwap(
                      swapKey: usage.compacting,
                      enableBlur: false,
                      duration: AppMotionDurations.quick,
                      child: usage.compacting
                          ? Center(
                              key: const ValueKey(true),
                              child: AppMatrixDotLoader(
                                variant: AppMatrixDotVariant.orbit,
                                rounded: true,
                                dotSize: 1.8,
                                gap: 1.2,
                                baseColor: progressColor.withValues(
                                  alpha: 0.25,
                                ),
                                activeColor: progressColor,
                              ),
                            )
                          : CircularProgressIndicator(
                              key: const ValueKey(false),
                              value: usage.fraction.clamp(0.0, 1.0),
                              strokeWidth: 2.0,
                              backgroundColor: colors.borderDefault,
                              color: progressColor,
                            ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  AppNumberPopIn(
                    value: percentText,
                    enableBlur: false,
                    distance: AppMotionDistances.micro,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: usage.error != null
                          ? colors.error
                          : colors.textMuted,
                    ),
                  ),
                  if (usage.error != null) ...[
                    const SizedBox(width: 3),
                    Icon(
                      Icons.error_outline_rounded,
                      size: 12,
                      color: colors.error,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
