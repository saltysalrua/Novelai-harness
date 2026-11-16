import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/harness/skills/skills.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../core/context_l10n.dart';
import '../../../core/l10n/skill_error_l10n.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_action_button.dart';
import '../../../core/widgets/app_badge.dart';
import '../../../core/widgets/app_collapsible_section.dart';
import '../../../core/widgets/app_dialog_scaffold.dart';
import '../../../core/widgets/app_segmented_controls.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/app_toggle_controls.dart';
import '../../../core/widgets/app_transitions.dart';
import '../../../core/widgets/smooth_scroll_controller.dart';
import 'settings_shared.dart';

/// Skill 查看 / 编辑 / 导入对话框 (支持 Pi 标准 SKILL.md 导入导出)
///
/// 采用 Notion 极简一体无分割线布局，柔底输入框与平滑滚轮。
class SkillEditorDialog extends StatefulWidget {
  final Skill? skill;
  final bool isImportMode;
  final Future<void> Function(Skill skill)? onSave;

  const SkillEditorDialog({
    super.key,
    this.skill,
    this.isImportMode = false,
    this.onSave,
  });

  @override
  State<SkillEditorDialog> createState() => _SkillEditorDialogState();
}

enum _SkillEditorViewMode { structured, raw }

class _SkillEditorDialogState extends State<SkillEditorDialog> {
  late final TextEditingController _idController;
  late final TextEditingController _nameController;
  late final TextEditingController _descController;
  late final TextEditingController _promptController;
  late final TextEditingController _rawMdController;
  late final SmoothWheelScrollController _structuredScrollController;

  bool _disableInvocation = false;
  bool _saving = false;
  bool _copiedSkillMd = false;
  int _errorShakeTrigger = 0;
  Timer? _copyResetTimer;
  Map<String, Object?> _extraFrontmatter = const {};
  _SkillEditorViewMode _viewMode = _SkillEditorViewMode.structured;

  @override
  void initState() {
    super.initState();
    final s = widget.skill;
    _idController = TextEditingController(text: s?.id ?? '');
    _nameController = TextEditingController(text: s?.name ?? '');
    _descController = TextEditingController(text: s?.description ?? '');
    _promptController = TextEditingController(text: s?.systemPrompt ?? '');
    _disableInvocation = s?.disableModelInvocation ?? false;
    _extraFrontmatter = s?.extraFrontmatter ?? const {};
    _structuredScrollController = SmoothWheelScrollController();

    _rawMdController = TextEditingController(
      text: s != null ? s.toSkillMd() : '',
    );
    _viewMode = widget.isImportMode
        ? _SkillEditorViewMode.raw
        : _SkillEditorViewMode.structured;
  }

  @override
  void dispose() {
    _copyResetTimer?.cancel();
    _structuredScrollController.dispose();
    _idController.dispose();
    _nameController.dispose();
    _descController.dispose();
    _promptController.dispose();
    _rawMdController.dispose();
    super.dispose();
  }

  bool _syncFromRaw() {
    try {
      final parsed = Skill.fromSkillMd(
        _rawMdController.text,
        defaultId: _idController.text.trim().isNotEmpty
            ? _idController.text.trim()
            : 'imported-skill',
      );
      setState(() {
        _idController.text = parsed.id;
        _nameController.text = parsed.name;
        _descController.text = parsed.description;
        _promptController.text = parsed.systemPrompt;
        _disableInvocation = parsed.disableModelInvocation;
        _extraFrontmatter = parsed.extraFrontmatter;
      });
      return true;
    } catch (error) {
      _showError(error);
      return false;
    }
  }

  void _showError(Object error) {
    setState(() => _errorShakeTrigger++);
    showAppToast(
      context,
      message: skillErrorText(context.l10n, error),
      tone: AppToastTone.error,
    );
  }

  void _copySkillMd(AppLocalizations l10n) {
    if (_viewMode == _SkillEditorViewMode.structured) {
      _syncToRaw();
    }
    Clipboard.setData(ClipboardData(text: _rawMdController.text));
    _copyResetTimer?.cancel();
    setState(() => _copiedSkillMd = true);
    _copyResetTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _copiedSkillMd = false);
    });
    showAppToast(
      context,
      message: l10n.skillCopySuccess,
      tone: AppToastTone.success,
    );
  }

  void _syncToRaw() {
    final skill = Skill(
      id: _idController.text.trim(),
      name: _nameController.text.trim(),
      description: _descController.text.trim(),
      systemPrompt: _promptController.text.trim(),
      disableModelInvocation: _disableInvocation,
      extraFrontmatter: _extraFrontmatter,
    );
    _rawMdController.text = skill.toSkillMd();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final isBuiltin = widget.skill?.isBuiltin ?? false;

    return AppDialogScaffold(
      minimalChrome: true,
      title: widget.isImportMode
          ? l10n.skillDialogImportTitle
          : (widget.skill == null
                ? l10n.skillDialogNewTitle
                : l10n.skillDialogEditTitle(widget.skill!.name)),
      subtitle: widget.skill?.id,
      width: 700,
      height: 650,
      body: Padding(
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 视图切换模式 + 状态徽标
            Row(
              children: [
                AppSegmentedCardBar<_SkillEditorViewMode>(
                  items: [
                    AppSegmentedItem(
                      value: _SkillEditorViewMode.structured,
                      label: l10n.skillEditorTabStructured,
                    ),
                    AppSegmentedItem(
                      value: _SkillEditorViewMode.raw,
                      label: l10n.skillEditorTabRaw,
                    ),
                  ],
                  selectedValue: _viewMode,
                  onValueChanged: (mode) {
                    if (mode == _SkillEditorViewMode.structured &&
                        _viewMode == _SkillEditorViewMode.raw) {
                      if (!_syncFromRaw()) return;
                    } else if (mode == _SkillEditorViewMode.raw &&
                        _viewMode == _SkillEditorViewMode.structured) {
                      _syncToRaw();
                    }
                    setState(() => _viewMode = mode);
                  },
                ),
                const Spacer(),
                if (widget.skill != null)
                  AppBadge(
                    label: isBuiltin
                        ? l10n.settingsBadgeBuiltin
                        : l10n.settingsBadgeCustom,
                    variant: isBuiltin
                        ? AppBadgeVariant.neutral
                        : AppBadgeVariant.warning,
                    fontSize: 10.5,
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (widget.skill?.resourcePaths.isNotEmpty == true) ...[
              Container(
                decoration: BoxDecoration(
                  color: colors.elevatedBackground,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: AppCollapsibleSection(
                  isCard: false,
                  headerPadding: const EdgeInsets.symmetric(vertical: 8),
                  contentPadding: const EdgeInsets.only(bottom: 10),
                  title: l10n.skillPackageFiles(
                    widget.skill!.resourcePaths.length,
                  ),
                  subtitle: l10n.skillPackageResourceHelp,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 96),
                    child: ListView(
                      shrinkWrap: true,
                      children: widget.skill!.resourcePaths
                          .map(
                            (path) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 1),
                              child: Text(
                                path,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                  color: colors.textSecondary,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // 正文区
            Expanded(
              child: AppErrorShake(
                trigger: _errorShakeTrigger,
                child: AnimatedSwitcher(
                  duration: AppMotion.resolveDuration(
                    context,
                    AppMotionDurations.quick,
                  ),
                  switchInCurve: AppMotionCurves.smoothOut,
                  switchOutCurve: AppMotionCurves.smoothOut,
                  child: _viewMode == _SkillEditorViewMode.raw
                      ? KeyedSubtree(
                          key: const ValueKey<_SkillEditorViewMode>(
                            _SkillEditorViewMode.raw,
                          ),
                          child: _buildRawEditor(l10n),
                        )
                      : KeyedSubtree(
                          key: const ValueKey<_SkillEditorViewMode>(
                            _SkillEditorViewMode.structured,
                          ),
                          child: _buildStructuredEditor(isBuiltin, l10n),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
      footerLeading: AppActionButton(
        label: l10n.skillCopySkillMd,
        icon: _copiedSkillMd ? Icons.check_rounded : Icons.copy_rounded,
        onPressed: () => _copySkillMd(l10n),
      ),
      actions: [
        AppActionButton(
          label: l10n.cancel,
          variant: AppActionButtonVariant.ghost,
          onPressed: () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: 8),
        AppActionButton(
          label: l10n.skillSave,
          variant: AppActionButtonVariant.primary,
          isLoading: _saving,
          onPressed: _saving ? null : _save,
        ),
      ],
    );
  }

  Widget _buildStructuredEditor(bool isBuiltin, AppLocalizations l10n) {
    final colors = context.colors;

    return SingleChildScrollView(
      controller: _structuredScrollController,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SettingsFieldLabel(label: l10n.skillFieldId),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _idController,
                      enabled: !isBuiltin,
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: isBuiltin ? colors.textMuted : colors.textPrimary,
                      ),
                      decoration: settingsSoftInputDecoration(
                        context,
                        hintText: l10n.skillFieldIdHint,
                        readOnly: isBuiltin,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SettingsFieldLabel(label: l10n.skillFieldName),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _nameController,
                      style: const TextStyle(fontSize: 12),
                      decoration: settingsSoftInputDecoration(
                        context,
                        hintText: l10n.skillFieldNameHint,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SettingsFieldLabel(label: l10n.skillFieldDescription),
          const SizedBox(height: 6),
          TextField(
            controller: _descController,
            minLines: 2,
            maxLines: 4,
            style: const TextStyle(fontSize: 12, height: 1.4),
            decoration: settingsSoftInputDecoration(
              context,
              hintText: l10n.skillFieldDescriptionHint,
            ),
          ),
          const SizedBox(height: 12),
          SettingsFieldLabel(
            label: l10n.skillFieldPrompt,
            trailing: InkWell(
              onTap: () =>
                  setState(() => _disableInvocation = !_disableInvocation),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppCheckbox(
                      value: _disableInvocation,
                      size: 15,
                      onChanged: (v) =>
                          setState(() => _disableInvocation = v),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      l10n.skillFieldDisableInvocation,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _promptController,
            maxLines: 12,
            style: const TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              height: 1.48,
            ),
            decoration: settingsSoftInputDecoration(
              context,
              hintText: l10n.skillFieldPromptHint,
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRawEditor(AppLocalizations l10n) {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.skillRawEditorHelp,
          style: TextStyle(fontSize: 11.5, color: colors.textMuted),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: TextField(
            controller: _rawMdController,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            style: const TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              height: 1.48,
            ),
            decoration: settingsSoftInputDecoration(
              context,
              hintText:
                  '---\nname: my-skill\ndescription: Skill description...\n---\n\nSkill prompt content...',
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_viewMode == _SkillEditorViewMode.raw && !_syncFromRaw()) return;
    final id = _idController.text.trim();
    final name = _nameController.text.trim();
    if (id.isEmpty) {
      setState(() => _errorShakeTrigger++);
      showAppToast(
        context,
        message: context.l10n.skillIdEmptyError,
        tone: AppToastTone.error,
      );
      return;
    }

    final skill = Skill(
      id: widget.skill?.isBuiltin == true ? widget.skill!.id : id,
      name: name.isNotEmpty ? name : id,
      description: _descController.text.trim(),
      systemPrompt: _promptController.text.trim(),
      disableModelInvocation: _disableInvocation,
      isBuiltin: widget.skill?.isBuiltin ?? false,
      packageId: widget.skill?.packageId,
      resourcePaths: widget.skill?.resourcePaths ?? const [],
      extraFrontmatter: _extraFrontmatter,
    );

    setState(() => _saving = true);
    try {
      await widget.onSave?.call(skill);
      if (mounted) Navigator.of(context).pop(skill);
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
