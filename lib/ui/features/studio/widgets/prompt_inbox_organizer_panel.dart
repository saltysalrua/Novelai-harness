import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/harness/presets/agent_preset.dart';
import '../../../../data/models/llm_models.dart';
import '../../../../data/models/prompt_library_models.dart';
import '../../../core/context_l10n.dart';
import '../../../core/l10n/model_label_l10n.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_action_button.dart';
import '../../../core/widgets/app_badge.dart';
import '../../../core/widgets/app_dialog_scaffold.dart';
import '../../../core/widgets/app_dropdown.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/app_toggle_controls.dart';
import '../../../core/widgets/smooth_scroll_controller.dart';
import '../../settings/widgets/settings_shared.dart';
import '../view_models/studio_view_model.dart';

/// 待整理区后台整理实时日志面板（监听独立 inboxOrganizerNotifier，不引发全局重建）
class PromptInboxOrganizerLogPanel extends StatefulWidget {
  final StudioViewModel viewModel;
  final VoidCallback onClose;

  const PromptInboxOrganizerLogPanel({
    super.key,
    required this.viewModel,
    required this.onClose,
  });

  @override
  State<PromptInboxOrganizerLogPanel> createState() =>
      _PromptInboxOrganizerLogPanelState();
}

class _PromptInboxOrganizerLogPanelState
    extends State<PromptInboxOrganizerLogPanel> {
  final SmoothWheelScrollController _scrollController =
      SmoothWheelScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottomIfNeeded() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final maxExtent = _scrollController.position.maxScrollExtent;
      if (maxExtent > 0) {
        _scrollController.jumpTo(maxExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;

    return ListenableBuilder(
      listenable: widget.viewModel.inboxOrganizerNotifier,
      builder: (context, _) {
        final vm = widget.viewModel;
        final running = vm.isOrganizingInbox;
        final logs = vm.inboxOrganizerLogs;
        final liveThoughts = vm.inboxOrganizerLiveThoughts;
        final liveContent = vm.inboxOrganizerLiveContent;
        final status = vm.inboxOrganizerStatus ?? l10n.libraryInboxLogsTitle;
        final modelLabel = vm.inboxOrganizerModelLabel;

        if (running) {
          _scrollToBottomIfNeeded();
        }

        final panelRadius = BorderRadius.circular(AppRadius.md);
        return Container(
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          decoration: BoxDecoration(
            color: colors.cardBackground,
            borderRadius: panelRadius,
          ),
          foregroundDecoration: BoxDecoration(
            borderRadius: panelRadius,
            border: Border.all(
              color: running
                  ? colors.primary.withValues(alpha: 0.45)
                  : colors.borderDefault,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 顶部状态条
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: colors.elevatedBackground,
                  border: Border(
                    bottom: BorderSide(color: colors.borderSubtle),
                  ),
                ),
                child: Row(
                  children: [
                    if (running)
                      SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.primary,
                        ),
                      )
                    else
                      Icon(
                        Icons.terminal_rounded,
                        size: 15,
                        color: colors.textSecondary,
                      ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              status,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: colors.textPrimary,
                              ),
                            ),
                          ),
                          if (modelLabel != null && modelLabel.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            AppBadge.pill(
                              label: modelLabel,
                              variant: AppBadgeVariant.neutral,
                              fontSize: 10,
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (running) ...[
                      const SizedBox(width: 8),
                      AppActionButton(
                        icon: Icons.stop_rounded,
                        label: l10n.libraryInboxStopOrganizing,
                        variant: AppActionButtonVariant.danger,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        onPressed: () => vm.abortInboxOrganizer(),
                      ),
                    ] else if (logs.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      AppActionButton(
                        label: l10n.libraryInboxClearLogs,
                        variant: AppActionButtonVariant.ghost,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        onPressed: vm.clearInboxOrganizerLogs,
                      ),
                    ],
                    const SizedBox(width: 4),
                    AppActionButton(
                      key: const Key('inbox_organizer_panel_collapse_button'),
                      icon: Icons.expand_less_rounded,
                      iconSize: 15,
                      label: l10n.libraryInboxHideLogs,
                      variant: AppActionButtonVariant.ghost,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      onPressed: widget.onClose,
                    ),
                  ],
                ),
              ),

              // 日志正文区
              ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: 88,
                  maxHeight: 240,
                ),
                child: logs.isEmpty &&
                        liveThoughts.isEmpty &&
                        liveContent.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            l10n.libraryInboxLogsEmpty,
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.textMuted,
                            ),
                          ),
                        ),
                      )
                    : SingleChildScrollView(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(10),
                        child: SelectionArea(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final entry in logs)
                                _LogRow(entry: entry),
                              if (liveThoughts.isNotEmpty)
                                _LogRow(
                                  entry: InboxOrganizerLogEntry(
                                    timestamp: DateTime.now(),
                                    kind: InboxOrganizerLogKind.thought,
                                    text: liveThoughts,
                                  ),
                                ),
                              if (liveContent.isNotEmpty)
                                _LogRow(
                                  entry: InboxOrganizerLogEntry(
                                    timestamp: DateTime.now(),
                                    kind: InboxOrganizerLogKind.content,
                                    text: liveContent,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LogRow extends StatelessWidget {
  final InboxOrganizerLogEntry entry;

  const _LogRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final timeStr = DateFormat('HH:mm:ss').format(entry.timestamp.toLocal());

    final (IconData icon, Color accent, bool isMono) = switch (entry.kind) {
      InboxOrganizerLogKind.system => (
        Icons.info_outline_rounded,
        colors.textMuted,
        false,
      ),
      InboxOrganizerLogKind.thought => (
        Icons.psychology_alt_outlined,
        colors.textMuted,
        false,
      ),
      InboxOrganizerLogKind.content => (
        Icons.auto_awesome_outlined,
        colors.primary,
        false,
      ),
      InboxOrganizerLogKind.toolCall => (
        Icons.build_outlined,
        colors.warning,
        true,
      ),
      InboxOrganizerLogKind.toolResult => (
        entry.isError
            ? Icons.error_outline_rounded
            : Icons.check_circle_outline_rounded,
        entry.isError ? colors.error : colors.success,
        false,
      ),
      InboxOrganizerLogKind.error => (
        Icons.error_outline_rounded,
        colors.error,
        false,
      ),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            timeStr,
            style: TextStyle(
              fontSize: 10.5,
              fontFamily: 'monospace',
              color: colors.textMuted,
            ),
          ),
          const SizedBox(width: 6),
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 13, color: accent),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (entry.title != null && entry.title!.isNotEmpty)
                  Text(
                    entry.title!,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: accent,
                    ),
                  ),
                Text(
                  entry.text,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.4,
                    fontFamily: isMono ? 'monospace' : null,
                    fontStyle: entry.kind == InboxOrganizerLogKind.thought
                        ? FontStyle.italic
                        : null,
                    color: entry.kind == InboxOrganizerLogKind.thought
                        ? colors.textMuted
                        : (entry.isError ? colors.error : colors.textPrimary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 待整理区后台整理配置弹窗（模型选择 + 分离后自动重跑预览图开关）
class PromptInboxOrganizerSettingsDialog extends StatefulWidget {
  final StudioViewModel viewModel;

  const PromptInboxOrganizerSettingsDialog({
    super.key,
    required this.viewModel,
  });

  static Future<void> show(
    BuildContext context, {
    required StudioViewModel viewModel,
  }) {
    return AppDialogScaffold.show<void>(
      context: context,
      builder: (ctx) => PromptInboxOrganizerSettingsDialog(
        viewModel: viewModel,
      ),
    );
  }

  @override
  State<PromptInboxOrganizerSettingsDialog> createState() =>
      _PromptInboxOrganizerSettingsDialogState();
}

class _PromptInboxOrganizerSettingsDialogState
    extends State<PromptInboxOrganizerSettingsDialog> {
  late String _providerId;
  late String _modelId;
  late bool _autoRerunPreview;
  late Set<String> _excludedCategories;
  late String _presetId;
  late final TextEditingController _customInstructionsController;
  Timer? _instructionsSaveTimer;

  @override
  void initState() {
    super.initState();
    _providerId = widget.viewModel.inboxOrganizerProviderId;
    _modelId = widget.viewModel.inboxOrganizerModelId;
    _autoRerunPreview = widget.viewModel.inboxAutoRerunPreview;
    _excludedCategories = widget.viewModel.inboxOrganizerExcludedCategories
        .toSet();
    _presetId = widget.viewModel.inboxOrganizerPresetId;
    _customInstructionsController = TextEditingController(
      text: widget.viewModel.inboxOrganizerCustomInstructions,
    );
  }

  @override
  void dispose() {
    if (_instructionsSaveTimer != null) {
      _instructionsSaveTimer!.cancel();
      _instructionsSaveTimer = null;
      unawaited(_persist());
    }
    _customInstructionsController.dispose();
    super.dispose();
  }

  Future<void> _persist() async {
    await widget.viewModel.updateInboxOrganizerSettings(
      providerId: _providerId,
      modelId: _modelId,
      autoRerunPreview: _autoRerunPreview,
      excludedCategories: _excludedCategories.toList(growable: false),
      presetId: _presetId,
      customInstructions: _customInstructionsController.text.trim(),
    );
  }

  void _scheduleInstructionsPersist() {
    _instructionsSaveTimer?.cancel();
    _instructionsSaveTimer = Timer(const Duration(milliseconds: 300), () {
      _instructionsSaveTimer = null;
      if (mounted) unawaited(_persist());
    });
  }

  void _toggleCategory(String category) {
    final next = Set<String>.from(_excludedCategories);
    if (next.contains(category)) {
      next.remove(category);
    } else {
      final remaining = PromptComboCategories.defaults
          .where((c) => !next.contains(c) && c != category)
          .length;
      if (remaining == 0) {
        showAppToast(
          context,
          message: context.l10n.libraryInboxOrganizerAtLeastOneCategory,
          tone: AppToastTone.warning,
        );
        return;
      }
      next.add(category);
    }
    setState(() => _excludedCategories = next);
    _persist();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final providers = widget.viewModel.config.llmProviders;
    final presets = widget.viewModel.config.presets;
    final selectedProvider = providers
        .where((p) => p.id == _providerId)
        .firstOrNull;
    final models = selectedProvider?.models ?? const <LlmModelConfig>[];
    final validPresetId = presets.any((p) => p.id == _presetId)
        ? _presetId
        : '';

    return AppDialogScaffold(
      title: l10n.libraryInboxOrganizerSettings,
      width: 480,
      minimalChrome: true,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsSoftContainer(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.libraryInboxOrganizerProviderTitle,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      AppDropdown<String>.simple(
                        value: selectedProvider?.id ?? '',
                        items: ['', ...providers.map((p) => p.id)],
                        labelOf: (id) => id.isEmpty
                            ? l10n.settingsFollowMainModel
                            : providers.firstWhere((p) => p.id == id).name,
                        variant: AppDropdownVariant.compact,
                        width: 190,
                        isExpanded: false,
                        onChanged: (id) {
                          setState(() {
                            _providerId = id;
                            _modelId = '';
                          });
                          _persist();
                        },
                      ),
                    ],
                  ),
                  if (selectedProvider != null) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.libraryInboxOrganizerModelTitle,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                              color: colors.textSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        AppDropdown<String>.simple(
                          value: models.any((m) => m.id == _modelId)
                              ? _modelId
                              : '',
                          items: ['', ...models.map((m) => m.id)],
                          labelOf: (id) => id.isEmpty
                              ? l10n.settingsFollowMainModel
                              : models.firstWhere((m) => m.id == id).name,
                          variant: AppDropdownVariant.compact,
                          width: 190,
                          isExpanded: false,
                          onChanged: (id) {
                            setState(() => _modelId = id);
                            _persist();
                          },
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            SettingsSoftContainer(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.libraryInboxOrganizerAutoRerunTitle,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          l10n.libraryInboxOrganizerAutoRerunSubtitle,
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.35,
                            color: colors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  AppSwitch(
                    key: const Key('inbox_auto_rerun_preview_switch'),
                    value: _autoRerunPreview,
                    onChanged: (v) {
                      setState(() => _autoRerunPreview = v);
                      _persist();
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SettingsSoftContainer(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.libraryInboxOrganizerCategoriesTitle,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    l10n.libraryInboxOrganizerCategoriesHint,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.35,
                      color: colors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 10),
                  PromptOrganizerCategorySelector(
                    excludedCategories: _excludedCategories,
                    onToggleCategory: _toggleCategory,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SettingsSoftContainer(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.libraryInboxOrganizerPresetTitle,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      AppDropdown<String>.simple(
                        value: validPresetId,
                        items: ['', ...presets.map((p) => p.id)],
                        labelOf: (id) => id.isEmpty
                            ? l10n.libraryInboxOrganizerPresetDefault
                            : presets
                                  .firstWhere(
                                    (p) => p.id == id,
                                    orElse: () => AgentPreset(
                                      id: id,
                                      name: id,
                                      description: '',
                                      systemPrompt: '',
                                    ),
                                  )
                                  .name,
                        variant: AppDropdownVariant.compact,
                        width: 190,
                        isExpanded: false,
                        onChanged: (id) {
                          setState(() => _presetId = id);
                          _persist();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    l10n.libraryInboxOrganizerCustomInstructionsTitle,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    key: const Key('inbox_organizer_custom_instructions_field'),
                    controller: _customInstructionsController,
                    minLines: 2,
                    maxLines: 5,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: colors.textPrimary,
                    ),
                    decoration: settingsSoftInputDecoration(
                      context,
                      hintText:
                          l10n.libraryInboxOrganizerCustomInstructionsHint,
                      contentPadding: const EdgeInsets.all(10),
                    ),
                    onChanged: (_) => _scheduleInstructionsPersist(),
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
          variant: AppActionButtonVariant.primary,
          onPressed: () {
            _instructionsSaveTimer?.cancel();
            _instructionsSaveTimer = null;
            unawaited(_persist());
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}

/// 允许后台整理助手拆分的分类多选胶囊（纯参数驱动，供词库弹窗与默认设置页共用）
class PromptOrganizerCategorySelector extends StatelessWidget {
  final Set<String> excludedCategories;
  final ValueChanged<String> onToggleCategory;

  const PromptOrganizerCategorySelector({
    super.key,
    required this.excludedCategories,
    required this.onToggleCategory,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final category in PromptComboCategories.defaults)
          Builder(
            builder: (context) {
              final allowed = !excludedCategories.contains(category);
              final label = comboCategoryLabelOf(l10n, category);
              return InkWell(
                key: Key('inbox_organizer_cat_$category'),
                onTap: () => onToggleCategory(category),
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: allowed
                        ? colors.primaryTint.withValues(alpha: 0.7)
                        : colors.elevatedBackground,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(
                      color: allowed
                          ? colors.primary.withValues(alpha: 0.55)
                          : colors.borderSubtle,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        allowed ? Icons.check_rounded : Icons.block_rounded,
                        size: 13,
                        color: allowed ? colors.primary : colors.textMuted,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              allowed ? FontWeight.w600 : FontWeight.w400,
                          color: allowed ? colors.primary : colors.textMuted,
                          decoration:
                              allowed ? null : TextDecoration.lineThrough,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}
