import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/harness/skills/skills.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_action_button.dart';
import '../../../core/widgets/app_dialog_scaffold.dart';
import '../../../core/widgets/app_collapsible_section.dart';
import '../../../core/widgets/app_segmented_controls.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/app_toggle_controls.dart';
import '../../../core/widgets/app_transitions.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../core/context_l10n.dart';
import '../../../core/l10n/skill_error_l10n.dart';

/// Skill 查看 / 编辑 / 导入对话框 (支持 Pi 标准 SKILL.md 导入导出)
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
      title: widget.isImportMode
          ? l10n.skillDialogImportTitle
          : (widget.skill == null
                ? l10n.skillDialogNewTitle
                : l10n.skillDialogEditTitle(widget.skill!.name)),
      width: 680,
      height: 640,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 视图切换模式
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
                Icon(
                  widget.isImportMode
                      ? Icons.file_upload_outlined
                      : Icons.psychology_outlined,
                  size: 20,
                  color: colors.primary,
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (widget.skill?.resourcePaths.isNotEmpty == true) ...[
              AppCollapsibleSection(
                title: l10n.skillPackageFiles(
                  widget.skill!.resourcePaths.length,
                ),
                subtitle: l10n.skillPackageResourceHelp,
                child: SizedBox(
                  height: 100,
                  child: ListView(
                    children: widget.skill!.resourcePaths
                        .map(
                          (path) => Text(
                            path,
                            style: const TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
              const SizedBox(height: 8),
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
      actions: [
        Expanded(
          child: Row(
            children: [
              AppActionButton(
                label: l10n.skillCopySkillMd,
                icon: _copiedSkillMd
                    ? Icons.check_rounded
                    : Icons.copy_rounded,
                onPressed: () => _copySkillMd(l10n),
              ),
              const Spacer(),
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
          ),
        ),
      ],
    );
  }

  Widget _buildStructuredEditor(bool isBuiltin, AppLocalizations l10n) {
    final colors = context.colors;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.skillFieldId,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _idController,
                      enabled: !isBuiltin,
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                      decoration: _fieldDecoration(
                        hint: l10n.skillFieldIdHint,
                        filled: isBuiltin,
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
                    Text(
                      l10n.skillFieldName,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _nameController,
                      style: const TextStyle(fontSize: 12),
                      decoration: _fieldDecoration(
                        hint: l10n.skillFieldNameHint,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            l10n.skillFieldDescription,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _descController,
            minLines: 2,
            maxLines: 4,
            style: const TextStyle(fontSize: 12, height: 1.4),
            decoration: _fieldDecoration(hint: l10n.skillFieldDescriptionHint),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l10n.skillFieldPrompt,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              InkWell(
                onTap: () =>
                    setState(() => _disableInvocation = !_disableInvocation),
                borderRadius: BorderRadius.circular(4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: Center(
                        child: AppCheckbox(
                          value: _disableInvocation,
                          size: 16,
                          onChanged: (v) =>
                              setState(() => _disableInvocation = v),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      l10n.skillFieldDisableInvocation,
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _promptController,
            maxLines: 12,
            style: const TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              height: 1.4,
            ),
            decoration: _fieldDecoration(
              hint: l10n.skillFieldPromptHint,
              subtleFill: true,
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
          style: TextStyle(fontSize: 12, color: colors.textSecondary),
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
              height: 1.4,
            ),
            decoration: _fieldDecoration(
              hint:
                  '---\nname: my-skill\ndescription: Skill description...\n---\n\nSkill prompt content...',
              subtleFill: true,
            ),
          ),
        ),
      ],
    );
  }

  InputDecoration _fieldDecoration({
    required String hint,
    bool filled = false,
    bool subtleFill = false,
  }) {
    final colors = context.colors;
    final fill = subtleFill
        ? colors.mutedBackground.withValues(alpha: 0.3)
        : (filled ? colors.mutedBackground : colors.cardBackground);
    return InputDecoration(
      hintText: hint,
      isDense: true,
      filled: true,
      fillColor: fill,
      hoverColor: fill,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: colors.borderDefault),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: colors.borderDefault),
      ),
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
