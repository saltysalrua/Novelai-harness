import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../data/models/prompt_library_sync_models.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../core/context_l10n.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_action_button.dart';
import '../../../core/widgets/app_badge.dart';
import '../../../core/widgets/app_collapsible_section.dart';
import '../../../core/widgets/app_confirm_dialog.dart';
import '../../../core/widgets/app_dialog_scaffold.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/app_transitions.dart';
import '../../../core/widgets/smooth_scroll_controller.dart';
import '../../settings/widgets/settings_shared.dart';
import '../view_models/studio_view_model.dart';

/// 格式化一次词库云同步的结果摘要文案
String formatPromptLibrarySyncSummary(
  AppLocalizations l10n,
  PromptLibrarySyncResult result,
) {
  return switch (result.mode) {
    PromptLibrarySyncMode.forcePush => l10n.librarySyncForcePushDone(
      result.pushedEntries,
      result.uploadedImages,
    ),
    PromptLibrarySyncMode.forcePull => l10n.librarySyncForcePullDone(
      result.pulledEntries,
      result.downloadedImages,
    ),
    PromptLibrarySyncMode.merge =>
      result.hasChanges
          ? l10n.librarySyncDoneSummary(
              result.pushedEntries,
              result.pulledEntries,
              result.deletedLocal,
              result.deletedRemote,
              result.uploadedImages,
              result.downloadedImages,
            )
          : l10n.librarySyncDoneUpToDate(result.revision),
  };
}

/// 强制覆盖模式二次确认弹窗；双向合并无需确认直接放行
Future<bool> confirmPromptLibrarySyncMode(
  BuildContext context,
  PromptLibrarySyncMode mode,
) async {
  if (mode == PromptLibrarySyncMode.merge) return true;
  final l10n = context.l10n;
  final (title, message) = switch (mode) {
    PromptLibrarySyncMode.forcePush => (
      l10n.librarySyncForcePushConfirmTitle,
      l10n.librarySyncForcePushConfirmMessage,
    ),
    PromptLibrarySyncMode.forcePull => (
      l10n.librarySyncForcePullConfirmTitle,
      l10n.librarySyncForcePullConfirmMessage,
    ),
    PromptLibrarySyncMode.merge => ('', ''),
  };
  final ok = await showAppConfirmDialog(
    context,
    title: title,
    message: message,
    isDestructive: true,
  );
  return ok == true;
}

/// 词库云同步配置与操作弹窗 (Cloudflare Workers + D1)
class PromptLibrarySyncDialog extends StatefulWidget {
  final StudioViewModel viewModel;

  const PromptLibrarySyncDialog({super.key, required this.viewModel});

  static Future<void> show(
    BuildContext context, {
    required StudioViewModel viewModel,
  }) {
    return AppDialogScaffold.show<void>(
      context: context,
      barrierDismissible: !viewModel.isSyncingPromptLibrary,
      builder: (ctx) => PromptLibrarySyncDialog(viewModel: viewModel),
    );
  }

  @override
  State<PromptLibrarySyncDialog> createState() =>
      _PromptLibrarySyncDialogState();
}

enum _SyncHealthTone { idle, ok, error }

class _PromptLibrarySyncDialogState extends State<PromptLibrarySyncDialog> {
  late final TextEditingController _endpointController;
  late final TextEditingController _tokenController;
  late final TextEditingController _namespaceController;
  late final SmoothWheelScrollController _scrollController;

  bool _configExpanded = true;
  bool _overwriteExpanded = false;
  PromptLibrarySyncMode? _pendingOverwriteMode;
  bool _testing = false;
  _SyncHealthTone _healthTone = _SyncHealthTone.idle;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    final cfg = widget.viewModel.promptLibrarySyncConfig;
    _endpointController = TextEditingController(text: cfg.endpoint)
      ..addListener(_onDraftChanged);
    _tokenController = TextEditingController(text: cfg.token)
      ..addListener(_onDraftChanged);
    _namespaceController = TextEditingController(text: cfg.namespace)
      ..addListener(_onDraftChanged);
    _scrollController = SmoothWheelScrollController();
    _configExpanded = !cfg.isConfigured;
  }

  void _onDraftChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _endpointController.removeListener(_onDraftChanged);
    _tokenController.removeListener(_onDraftChanged);
    _namespaceController.removeListener(_onDraftChanged);
    _endpointController.dispose();
    _tokenController.dispose();
    _namespaceController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  PromptLibrarySyncConfig _draftConfig() {
    return PromptLibrarySyncConfig(
      endpoint: _endpointController.text.trim(),
      token: _tokenController.text.trim(),
      namespace: _namespaceController.text.trim().isEmpty
          ? 'default'
          : _namespaceController.text.trim(),
    );
  }

  bool get _hasUnsavedDraft {
    final saved = widget.viewModel.promptLibrarySyncConfig;
    final draft = _draftConfig();
    return draft.endpoint != saved.endpoint.trim() ||
        draft.token != saved.token.trim() ||
        draft.normalizedNamespace != saved.normalizedNamespace;
  }

  String? _displayHost(PromptLibrarySyncConfig cfg) {
    final uri = cfg.resolveApiUri('/api/health');
    if (uri == null) return null;
    return uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
  }

  Future<void> _saveConfig() async {
    await widget.viewModel.savePromptSyncConfig(_draftConfig());
    if (!mounted) return;
    setState(() {});
    showAppToast(
      context,
      message: context.l10n.librarySyncConfigSaved,
      tone: AppToastTone.success,
      duration: const Duration(seconds: 2),
    );
  }

  Future<void> _handleTestConnection() async {
    if (_testing || widget.viewModel.isSyncingPromptLibrary) return;
    final l10n = context.l10n;
    setState(() {
      _testing = true;
      _statusMessage = null;
    });
    try {
      final health = await widget.viewModel.testPromptLibrarySyncConnection(
        _draftConfig(),
      );
      if (!mounted) return;
      setState(() {
        _healthTone = _SyncHealthTone.ok;
        _statusMessage = l10n.librarySyncTestSuccess(
          health.activeEntries,
          health.imageCount,
          health.revision,
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _healthTone = _SyncHealthTone.error;
        _statusMessage = l10n.librarySyncTestFailed(e.toString());
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _runSync(PromptLibrarySyncMode mode) async {
    if (_testing || widget.viewModel.isSyncingPromptLibrary) return;
    final l10n = context.l10n;
    final cfg = _draftConfig();

    setState(() {
      _pendingOverwriteMode = null;
      _statusMessage = null;
    });

    await widget.viewModel.savePromptSyncConfig(cfg);
    if (!mounted) return;

    try {
      final result = await widget.viewModel.syncPromptLibrary(
        mode: mode,
        overrideConfig: cfg,
      );
      if (!mounted) return;
      final summary = formatPromptLibrarySyncSummary(l10n, result);
      setState(() {
        _healthTone = _SyncHealthTone.ok;
        _statusMessage = summary;
      });
      showAppToast(
        context,
        message: summary,
        tone: AppToastTone.success,
        duration: const Duration(seconds: 3),
      );
    } catch (e) {
      if (!mounted) return;
      final msg = l10n.librarySyncFailed(e.toString());
      setState(() {
        _healthTone = _SyncHealthTone.error;
        _statusMessage = msg;
      });
      showAppToast(
        context,
        message: msg,
        tone: AppToastTone.error,
        duration: const Duration(seconds: 3),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.colors;

    return ListenableBuilder(
      listenable: widget.viewModel.promptLibraryNotifier,
      builder: (context, _) {
        final syncing = widget.viewModel.isSyncingPromptLibrary;
        final stage = widget.viewModel.promptSyncStage;
        final draft = _draftConfig();
        final isReady = draft.isConfigured && draft.resolveApiUri('/api/health') != null;
        final lastSync = widget.viewModel.lastPromptSyncAt;
        final lastSyncText = lastSync != null
            ? l10n.librarySyncLastSynced(
                DateFormat('yyyy-MM-dd HH:mm').format(lastSync.toLocal()),
              )
            : l10n.librarySyncNeverSynced;

        return AppDialogScaffold(
          title: l10n.librarySyncDialogTitle,
          subtitle: l10n.librarySyncDialogSubtitle,
          width: 520,
          minimalChrome: true,
          barrierDismissible: !syncing,
          onClose: syncing ? null : () => Navigator.of(context).pop(),
          body: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildStatusCard(
                  context,
                  l10n: l10n,
                  draft: draft,
                  isReady: isReady,
                  syncing: syncing,
                  stage: stage,
                  lastSyncText: lastSyncText,
                ),
                const SizedBox(height: 12),

                // 连接配置折叠区：未配置时默认展开，已配置好后默认收起
                AppCollapsibleSection(
                  title: l10n.librarySyncConfigSection,
                  subtitle: _configExpanded
                      ? null
                      : (_displayHost(draft) ??
                            l10n.librarySyncConfigCollapsedHint),
                  isExpanded: _configExpanded,
                  onExpansionChanged: (v) => setState(() => _configExpanded = v),
                  trailing: _hasUnsavedDraft
                      ? AppBadge.pill(
                          label: l10n.librarySyncSaveConfig,
                          variant: AppBadgeVariant.warning,
                          fontSize: 10,
                        )
                      : null,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SettingsFieldLabel(
                        label: l10n.settingsLibrarySyncEndpointTitle,
                      ),
                      const SizedBox(height: 5),
                      TextField(
                        controller: _endpointController,
                        enabled: !syncing,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: colors.textPrimary,
                        ),
                        decoration: settingsSoftInputDecoration(
                          context,
                          hintText: l10n.settingsLibrarySyncEndpointHint,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SettingsFieldLabel(
                        label: l10n.settingsLibrarySyncTokenTitle,
                      ),
                      const SizedBox(height: 5),
                      SettingsKeyField(
                        controller: _tokenController,
                        hintText: l10n.settingsLibrarySyncTokenHint,
                        width: null,
                        soft: true,
                      ),
                      const SizedBox(height: 10),
                      SettingsFieldLabel(
                        label: l10n.settingsLibrarySyncNamespaceTitle,
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _namespaceController,
                              enabled: !syncing,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: colors.textPrimary,
                              ),
                              decoration: settingsSoftInputDecoration(
                                context,
                                hintText: l10n.settingsLibrarySyncNamespaceHint,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          AppActionButton(
                            icon: Icons.check_rounded,
                            label: l10n.librarySyncSaveConfig,
                            variant: AppActionButtonVariant.outlined,
                            onPressed: (!syncing && _hasUnsavedDraft)
                                ? _saveConfig
                                : null,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // 强制覆盖与恢复区：折叠收起 + 内联确认（避免弹窗叠弹窗双重黑屏）
                AppCollapsibleSection(
                  title: l10n.librarySyncOverwriteSection,
                  subtitle: l10n.librarySyncOverwriteSectionHint,
                  isExpanded: _overwriteExpanded,
                  onExpansionChanged: (v) => setState(() {
                    _overwriteExpanded = v;
                    if (!v) _pendingOverwriteMode = null;
                  }),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _OverwriteActionRow(
                        icon: Icons.cloud_upload_outlined,
                        title: l10n.librarySyncForcePushMenu,
                        subtitle: l10n.librarySyncForcePushHint,
                        buttonLabel: l10n.librarySyncForcePushMenu,
                        enabled: isReady && !syncing && !_testing,
                        isSelected:
                            _pendingOverwriteMode ==
                            PromptLibrarySyncMode.forcePush,
                        onPressed: () => setState(() {
                          _pendingOverwriteMode =
                              PromptLibrarySyncMode.forcePush;
                        }),
                      ),
                      const SizedBox(height: 8),
                      _OverwriteActionRow(
                        icon: Icons.cloud_download_outlined,
                        title: l10n.librarySyncForcePullMenu,
                        subtitle: l10n.librarySyncForcePullHint,
                        buttonLabel: l10n.librarySyncForcePullMenu,
                        enabled: isReady && !syncing && !_testing,
                        isSelected:
                            _pendingOverwriteMode ==
                            PromptLibrarySyncMode.forcePull,
                        onPressed: () => setState(() {
                          _pendingOverwriteMode =
                              PromptLibrarySyncMode.forcePull;
                        }),
                      ),
                      AppPanelReveal(
                        visible: _pendingOverwriteMode != null,
                        enableBlur: false,
                        child: _pendingOverwriteMode == null
                            ? const SizedBox.shrink()
                            : Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: _InlineOverwriteConfirmBar(
                                  message:
                                      _pendingOverwriteMode ==
                                          PromptLibrarySyncMode.forcePush
                                      ? l10n.librarySyncForcePushConfirmMessage
                                      : l10n.librarySyncForcePullConfirmMessage,
                                  cancelLabel: l10n.cancel,
                                  confirmLabel:
                                      l10n.librarySyncOverwriteConfirmButton,
                                  onCancel: () => setState(
                                    () => _pendingOverwriteMode = null,
                                  ),
                                  onConfirm: () =>
                                      _runSync(_pendingOverwriteMode!),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            AppActionButton(
              label: l10n.close,
              variant: AppActionButtonVariant.ghost,
              onPressed: syncing ? null : () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: 8),
            AppActionButton(
              icon: Icons.cloud_sync_outlined,
              label: syncing
                  ? l10n.librarySyncingLabel
                  : l10n.librarySyncMergeMenu,
              variant: AppActionButtonVariant.primary,
              isLoading: syncing,
              onPressed: (!isReady || syncing || _testing)
                  ? null
                  : () => _runSync(PromptLibrarySyncMode.merge),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatusCard(
    BuildContext context, {
    required AppLocalizations l10n,
    required PromptLibrarySyncConfig draft,
    required bool isReady,
    required bool syncing,
    required String? stage,
    required String lastSyncText,
  }) {
    final colors = context.colors;
    final (String badgeLabel, AppBadgeVariant badgeVariant) = syncing
        ? (stage ?? l10n.librarySyncingLabel, AppBadgeVariant.primary)
        : !isReady
        ? (l10n.librarySyncStatusUnconfigured, AppBadgeVariant.warning)
        : switch (_healthTone) {
            _SyncHealthTone.ok => (
              l10n.librarySyncStatusConnected,
              AppBadgeVariant.success,
            ),
            _SyncHealthTone.error => (
              l10n.librarySyncStatusError,
              AppBadgeVariant.error,
            ),
            _SyncHealthTone.idle => (
              l10n.librarySyncStatusConfigured,
              AppBadgeVariant.neutral,
            ),
          };

    final host = _displayHost(draft);

    return SettingsSoftContainer(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppBadge.pill(label: badgeLabel, variant: badgeVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  host != null
                      ? '$host · ${draft.normalizedNamespace}'
                      : lastSyncText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: colors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              AppActionButton(
                icon: Icons.network_check_rounded,
                label: _testing
                    ? l10n.librarySyncTesting
                    : l10n.librarySyncTestConnection,
                variant: AppActionButtonVariant.outlined,
                isLoading: _testing,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                onPressed: (!isReady || _testing || syncing)
                    ? null
                    : _handleTestConnection,
              ),
            ],
          ),
          if (host != null) ...[
            const SizedBox(height: 6),
            Text(
              lastSyncText,
              style: TextStyle(fontSize: 11.5, color: colors.textMuted),
            ),
          ],
          if (_statusMessage != null && _statusMessage!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              _statusMessage!,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: _healthTone == _SyncHealthTone.error
                    ? colors.error
                    : colors.success,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OverwriteActionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String buttonLabel;
  final bool enabled;
  final bool isSelected;
  final VoidCallback onPressed;

  const _OverwriteActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.enabled,
    required this.isSelected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: isSelected
            ? colors.errorSurface.withValues(alpha: 0.45)
            : colors.elevatedBackground,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: isSelected
              ? colors.error.withValues(alpha: 0.45)
              : colors.borderSubtle,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: isSelected ? colors.error : colors.textSecondary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 11, color: colors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          AppActionButton(
            label: buttonLabel,
            variant: AppActionButtonVariant.outlined,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            onPressed: enabled ? onPressed : null,
          ),
        ],
      ),
    );
  }
}

class _InlineOverwriteConfirmBar extends StatelessWidget {
  final String message;
  final String cancelLabel;
  final String confirmLabel;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  const _InlineOverwriteConfirmBar({
    required this.message,
    required this.cancelLabel,
    required this.confirmLabel,
    required this.onCancel,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.errorSurface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.error.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded, size: 16, color: colors.error),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.4,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              AppActionButton(
                label: cancelLabel,
                variant: AppActionButtonVariant.ghost,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                onPressed: onCancel,
              ),
              const SizedBox(width: 6),
              FilledButton(
                onPressed: onConfirm,
                style: FilledButton.styleFrom(
                  backgroundColor: colors.error,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                ),
                child: Text(
                  confirmLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
