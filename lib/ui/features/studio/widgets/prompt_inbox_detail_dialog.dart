import 'dart:io';
import 'package:flutter/material.dart';
import '../../../../data/models/prompt_library_models.dart';
import '../../../core/context_l10n.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_action_button.dart';
import '../../../core/widgets/app_dialog_scaffold.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/smooth_scroll_controller.dart';
import '../../settings/widgets/settings_shared.dart';
import '../view_models/studio_view_model.dart';

class _InboxCharacterDraft {
  final TextEditingController nameController;
  final TextEditingController promptController;
  final TextEditingController negativeController;

  _InboxCharacterDraft({
    String name = '',
    String prompt = '',
    String negativePrompt = '',
  }) : nameController = TextEditingController(text: name),
       promptController = TextEditingController(text: prompt),
       negativeController = TextEditingController(text: negativePrompt);

  void dispose() {
    nameController.dispose();
    promptController.dispose();
    negativeController.dispose();
  }
}

/// 待整理区条目详情与编辑弹窗：
/// 完整呈现图片、主提示词、主负面词及全部角色提示词（支持直接修改保存、手动建词条或交给后台助手整理）。
class PromptInboxDetailDialog extends StatefulWidget {
  final StudioViewModel viewModel;
  final PromptInboxItem item;
  final VoidCallback onOrganizeWithAgent;
  final ValueChanged<PromptInboxItem> onManualConvert;

  const PromptInboxDetailDialog({
    super.key,
    required this.viewModel,
    required this.item,
    required this.onOrganizeWithAgent,
    required this.onManualConvert,
  });

  static Future<void> show(
    BuildContext context, {
    required StudioViewModel viewModel,
    required PromptInboxItem item,
    required VoidCallback onOrganizeWithAgent,
    required ValueChanged<PromptInboxItem> onManualConvert,
  }) {
    return AppDialogScaffold.show<void>(
      context: context,
      builder: (ctx) => PromptInboxDetailDialog(
        viewModel: viewModel,
        item: item,
        onOrganizeWithAgent: onOrganizeWithAgent,
        onManualConvert: onManualConvert,
      ),
    );
  }

  @override
  State<PromptInboxDetailDialog> createState() =>
      _PromptInboxDetailDialogState();
}

class _PromptInboxDetailDialogState extends State<PromptInboxDetailDialog> {
  late final TextEditingController _promptController;
  late final TextEditingController _negativeController;
  late final SmoothWheelScrollController _scrollController;
  final List<_InboxCharacterDraft> _characters = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _promptController = TextEditingController(text: widget.item.prompt);
    _negativeController = TextEditingController(
      text: widget.item.negativePrompt,
    );
    _scrollController = SmoothWheelScrollController();
    for (final c in widget.item.characterPrompts) {
      _characters.add(
        _InboxCharacterDraft(
          name: c.name,
          prompt: c.prompt,
          negativePrompt: c.negativePrompt,
        ),
      );
    }
  }

  @override
  void dispose() {
    _promptController.dispose();
    _negativeController.dispose();
    _scrollController.dispose();
    for (final c in _characters) {
      c.dispose();
    }
    super.dispose();
  }

  PromptInboxItem _buildCurrentItem() {
    final chars = <PromptInboxCharacter>[];
    for (final draft in _characters) {
      final p = draft.promptController.text.trim();
      if (p.isEmpty) continue;
      chars.add(
        PromptInboxCharacter(
          name: draft.nameController.text.trim(),
          prompt: p,
          negativePrompt: draft.negativeController.text.trim(),
        ),
      );
    }
    return widget.item.copyWith(
      prompt: _promptController.text.trim(),
      negativePrompt: _negativeController.text.trim(),
      characterPrompts: chars,
      updatedAt: DateTime.now(),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.viewModel.updatePromptInboxItem(_buildCurrentItem());
      if (!mounted) return;
      Navigator.of(context).pop();
      showAppToast(
        context,
        message: context.l10n.libraryInboxSavedChanges,
        tone: AppToastTone.success,
        duration: const Duration(milliseconds: 1400),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final imgPath = widget.item.imagePath?.trim();
    final hasFile =
        imgPath != null && imgPath.isNotEmpty && File(imgPath).existsSync();

    return AppDialogScaffold(
      title: l10n.libraryInboxDetailTitle,
      width: 660,
      maxHeight: 680,
      minimalChrome: true,
      body: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hasFile) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: ColoredBox(
                    color: colors.elevatedBackground,
                    child: Image.file(
                      File(imgPath),
                      fit: BoxFit.contain,
                      width: double.infinity,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
            ],
            SettingsFieldLabel(label: l10n.libraryInboxMainPromptLabel),
            const SizedBox(height: 6),
            TextField(
              controller: _promptController,
              minLines: 3,
              maxLines: 7,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: colors.textPrimary,
              ),
              decoration: settingsSoftInputDecoration(
                context,
                hintText: l10n.libraryEditFieldPromptHint,
                contentPadding: const EdgeInsets.all(10),
              ),
            ),
            const SizedBox(height: 12),
            SettingsFieldLabel(label: l10n.libraryInboxMainNegativeLabel),
            const SizedBox(height: 6),
            TextField(
              controller: _negativeController,
              minLines: 2,
              maxLines: 4,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: colors.textPrimary,
              ),
              decoration: settingsSoftInputDecoration(
                context,
                hintText: l10n.libraryEditFieldNegativeHint,
                contentPadding: const EdgeInsets.all(10),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: SettingsFieldLabel(
                    label:
                        '${l10n.libraryInboxCharactersLabel} (${_characters.length})',
                  ),
                ),
                AppActionButton(
                  icon: Icons.person_add_alt_1_outlined,
                  label: l10n.libraryInboxAddCharacter,
                  variant: AppActionButtonVariant.outlined,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  onPressed: () {
                    setState(() => _characters.add(_InboxCharacterDraft()));
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < _characters.length; i++) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colors.elevatedBackground,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: colors.borderSubtle),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: colors.errorSurface,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Text(
                            '#${i + 1}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: colors.error,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _characters[i].nameController,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: colors.textPrimary,
                            ),
                            decoration: settingsSoftInputDecoration(
                              context,
                              hintText: l10n.libraryInboxCharacterNameHint,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        AppIconButton(
                          icon: Icons.delete_outline,
                          size: 28,
                          iconSize: 15,
                          iconColor: colors.error,
                          variant: AppIconButtonVariant.ghost,
                          tooltip: l10n.delete,
                          onPressed: () {
                            setState(() {
                              final removed = _characters.removeAt(i);
                              removed.dispose();
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _characters[i].promptController,
                      minLines: 2,
                      maxLines: 5,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: colors.textPrimary,
                      ),
                      decoration: settingsSoftInputDecoration(
                        context,
                        hintText: l10n.libraryInboxCharacterPromptHint,
                        contentPadding: const EdgeInsets.all(8),
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _characters[i].negativeController,
                      minLines: 1,
                      maxLines: 3,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: colors.textPrimary,
                      ),
                      decoration: settingsSoftInputDecoration(
                        context,
                        hintText: l10n.libraryInboxCharacterNegativeHint,
                        contentPadding: const EdgeInsets.all(8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        AppActionButton(
          label: l10n.cancel,
          variant: AppActionButtonVariant.ghost,
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: 6),
        AppActionButton(
          icon: Icons.library_add_outlined,
          label: l10n.libraryInboxManualConvert,
          variant: AppActionButtonVariant.outlined,
          onPressed: _saving
              ? null
              : () {
                  final snapshot = _buildCurrentItem();
                  Navigator.of(context).pop();
                  widget.onManualConvert(snapshot);
                },
        ),
        const SizedBox(width: 6),
        AppActionButton(
          icon: Icons.auto_awesome_outlined,
          label: l10n.libraryInboxAskAgentOne,
          variant: AppActionButtonVariant.outlined,
          onPressed: _saving
              ? null
              : () {
                  Navigator.of(context).pop();
                  widget.onOrganizeWithAgent();
                },
        ),
        const SizedBox(width: 6),
        AppActionButton(
          icon: Icons.check_rounded,
          label: l10n.save,
          variant: AppActionButtonVariant.primary,
          isLoading: _saving,
          onPressed: _saving ? null : _save,
        ),
      ],
    );
  }
}
