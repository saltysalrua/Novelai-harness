import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../../data/models/prompt_library_models.dart';
import '../../../core/context_l10n.dart';
import '../../../core/l10n/model_label_l10n.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_action_button.dart';
import '../../../core/widgets/app_dialog_scaffold.dart';
import '../../../core/widgets/app_dropdown.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/app_image_detail_layout.dart';
import '../../../core/widgets/app_section_header.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/app_transitions.dart';
import '../view_models/studio_view_model.dart';

/// 词组合预设新建/编辑弹窗：完整大图与独立表单分区，操作不覆盖图片。
class PromptComboEditDialog extends StatefulWidget {
  final StudioViewModel viewModel;
  final PromptComboEntry? initialEntry;

  const PromptComboEditDialog({
    super.key,
    required this.viewModel,
    this.initialEntry,
  });

  static Future<void> show(
    BuildContext context, {
    required StudioViewModel viewModel,
    PromptComboEntry? initialEntry,
  }) {
    return AppDialogScaffold.show(
      context: context,
      builder: (ctx) => PromptComboEditDialog(
        viewModel: viewModel,
        initialEntry: initialEntry,
      ),
    );
  }

  @override
  State<PromptComboEditDialog> createState() => _PromptComboEditDialogState();
}

class _PromptComboEditDialogState extends State<PromptComboEditDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _customCategoryController;
  late final TextEditingController _promptController;
  late final TextEditingController _negativePromptController;
  late final TextEditingController _tagsController;

  late String _selectedCategory;
  bool _isCustomCategory = false;
  String? _previewImagePath;
  Uint8List? _previewBytes;
  bool _isSaving = false;
  int _titleShakeTrigger = 0;
  int _promptShakeTrigger = 0;

  bool get _isEdit =>
      widget.initialEntry != null && widget.initialEntry!.id.trim().isNotEmpty;

  bool get _isCharacterCategory => PromptComboEntry.isCharacterCategory(
    _isCustomCategory ? _customCategoryController.text : _selectedCategory,
  );

  @override
  void initState() {
    super.initState();
    final entry = widget.initialEntry;
    _titleController = TextEditingController(text: entry?.title ?? '');
    _promptController = TextEditingController(text: entry?.prompt ?? '');
    _negativePromptController = TextEditingController(
      text: entry?.negativePrompt ?? '',
    );
    _tagsController = TextEditingController(text: entry?.tags.join(', ') ?? '');

    final cat = entry?.category ?? PromptComboCategories.character;
    if (PromptComboCategories.defaults.contains(cat)) {
      _selectedCategory = cat;
      _isCustomCategory = false;
      _customCategoryController = TextEditingController();
    } else {
      _selectedCategory = '自定义...';
      _isCustomCategory = true;
      _customCategoryController = TextEditingController(text: cat);
    }

    _previewImagePath = entry?.previewImagePath;
    _customCategoryController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _customCategoryController.dispose();
    _promptController.dispose();
    _negativePromptController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _pickLocalImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
        withData: true,
      );
      if (!mounted) return;
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        if (file.bytes != null) {
          setState(() {
            _previewBytes = file.bytes;
            _previewImagePath = file.path;
          });
        } else if (file.path != null) {
          final bytes = await File(file.path!).readAsBytes();
          if (!mounted) return;
          setState(() {
            _previewBytes = bytes;
            _previewImagePath = file.path;
          });
        }
      }
    } catch (e) {
      if (!mounted) return;
      showAppToast(
        context,
        message: context.l10n.libraryEditPickImageFailed(e.toString()),
        tone: AppToastTone.error,
        duration: const Duration(seconds: 2),
      );
    }
  }

  void _useCurrentCanvasImage() {
    final bytes = widget.viewModel.getCurrentCanvasImageBytes();
    if (bytes != null && bytes.isNotEmpty) {
      setState(() {
        _previewBytes = bytes;
        _previewImagePath = null; // 标记由内存字节保存
      });
      showAppToast(
        context,
        message: context.l10n.libraryEditAdoptedCanvasImage,
        tone: AppToastTone.success,
        duration: const Duration(milliseconds: 1200),
      );
    } else {
      showAppToast(
        context,
        message: context.l10n.libraryEditCanvasNoImage,
        tone: AppToastTone.warning,
        duration: const Duration(milliseconds: 1400),
      );
    }
  }

  void _clearPreviewImage() {
    setState(() {
      _previewBytes = null;
      _previewImagePath = null;
    });
  }

  void _fillFromCurrentWorkspacePrompt() {
    final current = widget.viewModel.params.prompt.trim();
    if (current.isEmpty) {
      showAppToast(
        context,
        message: context.l10n.libraryEditWorkspacePromptEmpty,
        tone: AppToastTone.info,
        duration: const Duration(milliseconds: 1200),
      );
      return;
    }
    setState(() {
      _promptController.text = current;
    });
  }

  void _fillFromCurrentWorkspaceNegative() {
    final current = widget.viewModel.params.negativePrompt.trim();
    if (current.isEmpty) {
      showAppToast(
        context,
        message: context.l10n.libraryEditWorkspaceNegativeEmpty,
        tone: AppToastTone.info,
        duration: const Duration(milliseconds: 1200),
      );
      return;
    }
    setState(() {
      _negativePromptController.text = current;
    });
  }

  Future<void> _handleSave() async {
    final title = _titleController.text.trim();
    final prompt = _promptController.text.trim();

    if (title.isEmpty) {
      setState(() => _titleShakeTrigger++);
      showAppToast(
        context,
        message: context.l10n.libraryEditTitleEmpty,
        tone: AppToastTone.warning,
        duration: const Duration(milliseconds: 1400),
      );
      return;
    }

    if (prompt.isEmpty) {
      setState(() => _promptShakeTrigger++);
      showAppToast(
        context,
        message: context.l10n.libraryEditPromptEmpty,
        tone: AppToastTone.warning,
        duration: const Duration(milliseconds: 1400),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final finalCategory = _isCustomCategory
          ? (_customCategoryController.text.trim().isNotEmpty
                ? _customCategoryController.text.trim()
                : PromptComboCategories.other)
          : _selectedCategory;

      final isChar = PromptComboEntry.isCharacterCategory(finalCategory);

      // 仅在角色分类时保存负面词
      final negativePrompt = isChar
          ? _negativePromptController.text.trim()
          : '';

      final rawTags = _tagsController.text
          .split(RegExp(r'[,，\n]'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      // 处理预览图保存
      String? savedImagePath = _previewImagePath;
      if (_previewBytes != null) {
        savedImagePath = await widget.viewModel.savePromptPreviewFromBytes(
          _previewBytes!,
        );
      } else if (_previewImagePath != null &&
          !_previewImagePath!.contains('prompt_previews')) {
        savedImagePath = await widget.viewModel.savePromptPreviewFromPath(
          _previewImagePath!,
        );
      }

      final now = DateTime.now();
      if (_isEdit) {
        final updated = widget.initialEntry!.copyWith(
          title: title,
          category: finalCategory,
          prompt: prompt,
          negativePrompt: negativePrompt,
          previewImagePath: savedImagePath,
          clearPreviewImage: savedImagePath == null,
          updatedAt: now,
          tags: rawTags,
        );
        await widget.viewModel.updatePromptCombo(updated);
      } else {
        final newEntry = PromptComboEntry(
          id: 'combo_${DateTime.now().millisecondsSinceEpoch}',
          title: title,
          category: finalCategory,
          prompt: prompt,
          negativePrompt: negativePrompt,
          previewImagePath: savedImagePath,
          createdAt: now,
          updatedAt: now,
          tags: rawTags,
        );
        await widget.viewModel.addPromptCombo(newEntry);
      }

      if (!mounted) return;
      final successMessage = _isEdit
          ? context.l10n.libraryEditUpdatedSuccess(title)
          : context.l10n.libraryEditCreatedSuccess(title);
      Navigator.of(context).pop();
      showAppToast(
        context,
        message: successMessage,
        tone: AppToastTone.success,
        duration: const Duration(seconds: 2),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      showAppToast(
        context,
        message: context.l10n.libraryEditSaveFailed(e.toString()),
        tone: AppToastTone.error,
        duration: const Duration(seconds: 2),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final screenSize = MediaQuery.sizeOf(context);
    final hasImage = _previewBytes != null || _previewImagePath != null;
    final ImageProvider<Object>? image = _previewBytes != null
        ? MemoryImage(_previewBytes!)
        : _previewImagePath != null
        ? FileImage(File(_previewImagePath!))
        : null;

    return AppDialogScaffold(
      title: _isEdit
          ? l10n.libraryEditDialogTitleEdit
          : l10n.libraryEditDialogTitleNew,
      width: 1440,
      height: (screenSize.height - 64).clamp(0.0, 1040.0),
      maxHeight: screenSize.height - 48,
      body: AppImageDetailLayout(
        image: image,
        placeholder: AppEmptyState(
          icon: Icons.image_outlined,
          title: l10n.libraryEditPosterTitle,
          isCompact: true,
        ),
        previewFooter: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            AppActionButton(
              label: l10n.libraryEditPickLocalImage,
              icon: Icons.file_upload_outlined,
              onPressed: _pickLocalImage,
            ),
            AppActionButton(
              label: l10n.libraryEditUseCanvasImage,
              icon: Icons.image_outlined,
              onPressed: _useCurrentCanvasImage,
            ),
            if (hasImage)
              AppActionButton(
                label: l10n.libraryEditRemovePreviewImage,
                icon: Icons.delete_outline,
                onPressed: _clearPreviewImage,
              ),
          ],
        ),
        details: _buildForm(context),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        const SizedBox(width: 8),
        if (_isSaving) ...[
          const AppMatrixDotLoader(
            variant: AppMatrixDotVariant.pulse,
            dotSize: 2.0,
            gap: 2.0,
          ),
          const SizedBox(width: 8),
        ],
        AppActionButton(
          label: _isEdit
              ? l10n.libraryEditSaveButton
              : l10n.libraryEditCreateButton,
          icon: Icons.check_rounded,
          variant: AppActionButtonVariant.primary,
          onPressed: _isSaving ? null : _handleSave,
        ),
      ],
    );
  }

  Widget _buildForm(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.colors;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSectionHeader(title: '${l10n.libraryEditFieldTitle} *'),
          AppErrorShake(
            trigger: _titleShakeTrigger,
            child: TextField(
              controller: _titleController,
              style: TextStyle(fontSize: 13, color: colors.textPrimary),
              decoration: InputDecoration(
                hintText: l10n.libraryEditFieldTitleHint,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppSectionHeader(title: '${l10n.libraryEditFieldCategory} *'),
          _buildCategoryDropdown(context),
          AppPanelReveal(
            visible: _isCustomCategory,
            openDuration: AppMotionDurations.fast,
            closeDuration: AppMotionDurations.quick,
            slideOffset: AppMotionDistances.base,
            enableBlur: false,
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: TextField(
                controller: _customCategoryController,
                decoration: InputDecoration(
                  hintText: l10n.libraryEditFieldCustomCategoryHint,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppSectionHeader(
            title: '${l10n.libraryEditFieldPrompt} *',
            trailing: AppActionButton(
              label: l10n.libraryEditFillFromPrompt,
              icon: Icons.input_rounded,
              onPressed: _fillFromCurrentWorkspacePrompt,
            ),
          ),
          AppErrorShake(
            trigger: _promptShakeTrigger,
            child: TextField(
              controller: _promptController,
              minLines: 6,
              maxLines: 12,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: colors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: l10n.libraryEditFieldPromptHint,
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
          ),
          AppPanelReveal(
            visible: _isCharacterCategory,
            openDuration: AppMotionDurations.fast,
            closeDuration: AppMotionDurations.quick,
            slideOffset: AppMotionDistances.base,
            enableBlur: false,
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppSectionHeader(
                    title: l10n.libraryEditFieldNegative,
                    subtitle: l10n.libraryEditCharacterOnlyBadge,
                    trailing: AppActionButton(
                      label: l10n.libraryEditFillFromNegative,
                      icon: Icons.input_rounded,
                      onPressed: _fillFromCurrentWorkspaceNegative,
                    ),
                  ),
                  TextField(
                    controller: _negativePromptController,
                    minLines: 3,
                    maxLines: 8,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: colors.textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: l10n.libraryEditFieldNegativeHint,
                      contentPadding: const EdgeInsets.all(12),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppSectionHeader(title: l10n.libraryEditFieldTags),
          TextField(
            controller: _tagsController,
            decoration: InputDecoration(
              hintText: l10n.libraryEditFieldTagsHint,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryDropdown(BuildContext context) {
    final l10n = context.l10n;
    return AppDropdown<String>.simple(
      value: _isCustomCategory ? '自定义...' : _selectedCategory,
      items: [...PromptComboCategories.defaults, '自定义...'],
      labelOf: (category) => category == '自定义...'
          ? l10n.libraryEditCustomCategoryOption
          : comboCategoryLabelOf(l10n, category),
      iconOf: (category) => category == PromptComboCategories.character
          ? Icons.person_outline
          : Icons.label_outline,
      onChanged: (category) {
        setState(() {
          _isCustomCategory = category == '自定义...';
          if (!_isCustomCategory) _selectedCategory = category;
        });
      },
    );
  }
}
