import 'dart:io';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../data/models/prompt_library_models.dart';
import '../../../../data/services/prompt_image_probe.dart';
import '../../../core/context_l10n.dart';
import '../../../core/l10n/model_label_l10n.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_action_button.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/app_tool_chip.dart';
import '../../../core/widgets/app_transitions.dart';
import '../../../core/widgets/smooth_scroll_controller.dart';
import '../view_models/studio_view_model.dart';

/// 词组合预设新建/编辑弹窗：
/// Notion 极简一体布局，零内部分割线、零图像空边框。
class PromptComboEditDialog extends StatefulWidget {
  final StudioViewModel viewModel;
  final PromptComboEntry? initialEntry;
  final String? initialCategory;

  const PromptComboEditDialog({
    super.key,
    required this.viewModel,
    this.initialEntry,
    this.initialCategory,
  });

  static Future<void> show(
    BuildContext context, {
    required StudioViewModel viewModel,
    PromptComboEntry? initialEntry,
    String? initialCategory,
  }) {
    return showAppModalDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (ctx) => PromptComboEditDialog(
        viewModel: viewModel,
        initialEntry: initialEntry,
        initialCategory: initialCategory,
      ),
    );
  }

  @override
  State<PromptComboEditDialog> createState() => _PromptComboEditDialogState();
}

class _PromptComboEditDialogState extends State<PromptComboEditDialog> {
  static const String _customCategorySentinel = '自定义...';

  late final TextEditingController _titleController;
  late final TextEditingController _customCategoryController;
  late final TextEditingController _promptController;
  late final TextEditingController _prefixPromptController;
  late final TextEditingController _suffixPromptController;
  late final TextEditingController _negativePromptController;
  late final TextEditingController _tagsController;
  late final SmoothWheelScrollController _formScrollController;

  late String _selectedCategory;
  bool _isCustomCategory = false;
  String? _previewImagePath;
  Uint8List? _previewBytes;
  double? _previewAspectRatio;
  bool _isSaving = false;
  bool _isDraggingOver = false;
  int _titleShakeTrigger = 0;
  int _promptShakeTrigger = 0;
  int _styleShakeTrigger = 0;

  bool get _isEdit =>
      widget.initialEntry != null && widget.initialEntry!.id.trim().isNotEmpty;

  String get _effectiveCategory =>
      _isCustomCategory ? _customCategoryController.text : _selectedCategory;

  bool get _isStyleCategory =>
      PromptComboEntry.isStyleCategory(_effectiveCategory);

  bool get _supportsNegativePrompt =>
      PromptComboEntry.supportsNegativePrompt(_effectiveCategory);

  @override
  void initState() {
    super.initState();
    final entry = widget.initialEntry;
    _titleController = TextEditingController(text: entry?.title ?? '');
    _promptController = TextEditingController(text: entry?.prompt ?? '');

    final initialPrefix = entry != null && entry.isStyle
        ? entry.effectiveStylePrefix
        : (entry?.prefixPrompt ?? '');
    _prefixPromptController = TextEditingController(text: initialPrefix);
    _suffixPromptController = TextEditingController(
      text: entry?.suffixPrompt ?? '',
    );
    _negativePromptController = TextEditingController(
      text: entry?.negativePrompt ?? '',
    );
    _tagsController = TextEditingController(text: entry?.tags.join(', ') ?? '');
    _formScrollController = SmoothWheelScrollController();

    final cat =
        entry?.category ??
        widget.initialCategory ??
        PromptComboCategories.character;
    if (PromptComboCategories.defaults.contains(cat)) {
      _selectedCategory = cat;
      _isCustomCategory = false;
      _customCategoryController = TextEditingController();
    } else {
      _selectedCategory = _customCategorySentinel;
      _isCustomCategory = true;
      _customCategoryController = TextEditingController(text: cat);
    }

    _previewImagePath = entry?.previewImagePath;
    _resolveInitialAspectRatio();
    _customCategoryController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  void _resolveInitialAspectRatio() {
    final path = _previewImagePath?.trim();
    if (path == null || path.isEmpty) return;
    final cached = PromptImageProbe.getCachedAspectRatio(path);
    if (cached != null) {
      _previewAspectRatio = cached;
      return;
    }
    PromptImageProbe.probeFile(path).then((ratio) {
      if (mounted && ratio != null) {
        setState(() => _previewAspectRatio = ratio);
      }
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _customCategoryController.dispose();
    _promptController.dispose();
    _prefixPromptController.dispose();
    _suffixPromptController.dispose();
    _negativePromptController.dispose();
    _tagsController.dispose();
    _formScrollController.dispose();
    super.dispose();
  }

  void _setPreviewBytes(Uint8List bytes, {String? path}) {
    setState(() {
      _previewBytes = bytes;
      _previewImagePath = path;
      _previewAspectRatio = PromptImageProbe.probeBytes(bytes);
    });
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
          _setPreviewBytes(file.bytes!, path: file.path);
        } else if (file.path != null) {
          final bytes = await File(file.path!).readAsBytes();
          if (!mounted) return;
          _setPreviewBytes(bytes, path: file.path);
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

  Future<void> _handleDroppedFiles(DropDoneDetails details) async {
    for (final file in details.files) {
      final lower = file.name.toLowerCase();
      if (!lower.endsWith('.png') &&
          !lower.endsWith('.jpg') &&
          !lower.endsWith('.jpeg') &&
          !lower.endsWith('.webp')) {
        continue;
      }
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      if (bytes.isNotEmpty) {
        _setPreviewBytes(
          bytes,
          path: file.path.isNotEmpty ? file.path : null,
        );
        break;
      }
    }
  }

  void _useCurrentCanvasImage() {
    final bytes = widget.viewModel.getCurrentCanvasImageBytes();
    if (bytes != null && bytes.isNotEmpty) {
      _setPreviewBytes(bytes);
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
      _previewAspectRatio = null;
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

  void _fillStyleFromCurrentWorkspace() {
    final params = widget.viewModel.params;
    final prefix = (params.prefixPrompt ?? '').trim();
    final suffix = (params.suffixPrompt ?? '').trim();
    final negative = params.negativePrompt.trim();
    if (prefix.isEmpty && suffix.isEmpty && negative.isEmpty) {
      showAppToast(
        context,
        message: context.l10n.libraryEditWorkspaceStyleEmpty,
        tone: AppToastTone.info,
        duration: const Duration(milliseconds: 1400),
      );
      return;
    }
    setState(() {
      _prefixPromptController.text = prefix;
      _suffixPromptController.text = suffix;
      _negativePromptController.text = negative;
    });
  }

  Future<void> _handleSave() async {
    final title = _titleController.text.trim();
    final isStyle = _isStyleCategory;
    final prompt = isStyle ? '' : _promptController.text.trim();
    final prefixPrompt = isStyle ? _prefixPromptController.text.trim() : '';
    final suffixPrompt = isStyle ? _suffixPromptController.text.trim() : '';
    final negativeRaw = _negativePromptController.text.trim();

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

    if (isStyle) {
      if (prefixPrompt.isEmpty &&
          suffixPrompt.isEmpty &&
          negativeRaw.isEmpty) {
        setState(() => _styleShakeTrigger++);
        showAppToast(
          context,
          message: context.l10n.libraryEditStyleContentEmpty,
          tone: AppToastTone.warning,
          duration: const Duration(milliseconds: 1400),
        );
        return;
      }
    } else if (prompt.isEmpty) {
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

      final allowNeg = PromptComboEntry.supportsNegativePrompt(finalCategory);
      final negativePrompt = allowNeg ? negativeRaw : '';

      final rawTags = _tagsController.text
          .split(RegExp(r'[,，\n]'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

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
          prefixPrompt: prefixPrompt,
          suffixPrompt: suffixPrompt,
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
          prefixPrompt: prefixPrompt,
          suffixPrompt: suffixPrompt,
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

  InputDecoration _softFieldDecoration(
    BuildContext context, {
    required String hintText,
    EdgeInsetsGeometry contentPadding = const EdgeInsets.symmetric(
      horizontal: 12,
      vertical: 10,
    ),
  }) {
    final colors = context.colors;
    return InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(fontSize: 13, color: colors.textMuted),
      filled: true,
      fillColor: colors.elevatedBackground,
      hoverColor: colors.mutedBackground.withValues(alpha: 0.7),
      contentPadding: contentPadding,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: colors.primary, width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final screenSize = MediaQuery.sizeOf(context);
    final dialogWidth = (screenSize.width * 0.74).clamp(620.0, 1020.0);
    final dialogHeight = (screenSize.height * 0.80).clamp(480.0, 720.0);

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event.logicalKey != LogicalKeyboardKey.escape) {
          return KeyEventResult.ignored;
        }
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
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
        Navigator.of(context).pop();
        return KeyEventResult.handled;
      },
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: dialogWidth,
            height: dialogHeight,
            constraints: BoxConstraints(
              maxWidth: screenSize.width - 48,
              maxHeight: screenSize.height - 48,
            ),
            decoration: BoxDecoration(
              color: colors.cardBackground,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: colors.borderDefault),
              boxShadow: context.shadowDialog,
            ),
            clipBehavior: Clip.antiAlias,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 720;
                if (isNarrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 10, 0),
                        child: _buildDialogTopRow(context, l10n),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          controller: _formScrollController,
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxHeight: (constraints.maxHeight * 0.34)
                                      .clamp(140.0, 240.0),
                                ),
                                child: _buildPreviewStage(context),
                              ),
                              const SizedBox(height: 8),
                              _buildPreviewActions(context),
                              const SizedBox(height: 14),
                              ..._buildFormFields(context),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
                        child: _buildFooterButtons(context),
                      ),
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 左侧纯净完整图片展示区 (无空底框、无垂直分隔线)
                    Expanded(
                      flex: 9,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(22, 22, 10, 18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: _buildPreviewStage(context)),
                            const SizedBox(height: 10),
                            _buildPreviewActions(context),
                          ],
                        ),
                      ),
                    ),
                    // 右侧一体化 Notion 表单
                    Expanded(
                      flex: 11,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 16, 20, 18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildDialogTopRow(context, l10n),
                            Expanded(
                              child: SingleChildScrollView(
                                controller: _formScrollController,
                                padding: const EdgeInsets.only(
                                  top: 4,
                                  bottom: 12,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: _buildFormFields(context),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            _buildFooterButtons(context),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDialogTopRow(BuildContext context, dynamic l10n) {
    final colors = context.colors;
    return Row(
      children: [
        Text(
          _isEdit
              ? context.l10n.libraryEditDialogTitleEdit
              : context.l10n.libraryEditDialogTitleNew,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textMuted,
          ),
        ),
        const Spacer(),
        IconButton(
          icon: Icon(
            Icons.close_rounded,
            size: 18,
            color: colors.textSecondary,
          ),
          splashRadius: 16,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 28, height: 28),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _buildPreviewStage(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final rawPath = _previewImagePath?.trim();
    final hasImage =
        _previewBytes != null || (rawPath != null && rawPath.isNotEmpty);

    final ImageProvider<Object>? image = _previewBytes != null
        ? MemoryImage(_previewBytes!)
        : (rawPath != null && rawPath.isNotEmpty)
        ? FileImage(File(rawPath))
        : null;

    Widget emptyStage = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 260, maxHeight: 200),
        child: Material(
          color: _isDraggingOver
              ? colors.primaryTint.withValues(alpha: 0.65)
              : colors.elevatedBackground,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: InkWell(
            onTap: _pickLocalImage,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.add_photo_alternate_outlined,
                      size: 32,
                      color: colors.textMuted.withValues(alpha: 0.7),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.libraryEditPosterTitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    Widget buildFittedImage() {
      final imgWidget = Image(
        image: image!,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => emptyStage,
      );
      final ratio = _previewAspectRatio;
      final framed = ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: ratio != null
            ? AspectRatio(aspectRatio: ratio, child: imgWidget)
            : imgWidget,
      );
      return InteractiveViewer(
        key: ValueKey(image),
        minScale: 1,
        maxScale: 5,
        child: Center(child: framed),
      );
    }

    final canAcceptDrop =
        (ModalRoute.of(context)?.isCurrent ?? true) &&
        TickerMode.valuesOf(context).enabled;
    return DropTarget(
      enable: canAcceptDrop,
      onDragEntered: (_) {
        if (!canAcceptDrop) return;
        setState(() => _isDraggingOver = true);
      },
      onDragExited: (_) => setState(() => _isDraggingOver = false),
      onDragDone: (details) async {
        setState(() => _isDraggingOver = false);
        if (!canAcceptDrop) return;
        await _handleDroppedFiles(details);
      },
      child: AnimatedContainer(
        duration: AppMotion.resolveDuration(context, AppMotionDurations.quick),
        curve: AppMotionCurves.smoothOut,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: _isDraggingOver
              ? Border.all(color: colors.primary, width: 1.5)
              : null,
        ),
        child: !hasImage || image == null ? emptyStage : buildFittedImage(),
      ),
    );
  }

  Widget _buildPreviewActions(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final rawPath = _previewImagePath?.trim();
    final hasImage =
        _previewBytes != null || (rawPath != null && rawPath.isNotEmpty);

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 6,
      runSpacing: 6,
      children: [
        AppToolChip(
          icon: Icons.file_upload_outlined,
          label: l10n.libraryEditPickLocalImage,
          variant: AppToolChipVariant.tinted,
          unselectedBackgroundColor: colors.elevatedBackground,
          onTap: _pickLocalImage,
        ),
        AppToolChip(
          icon: Icons.image_outlined,
          label: l10n.libraryEditUseCanvasImage,
          variant: AppToolChipVariant.tinted,
          unselectedBackgroundColor: colors.elevatedBackground,
          onTap: _useCurrentCanvasImage,
        ),
        if (hasImage)
          AppToolChip(
            icon: Icons.delete_outline,
            label: l10n.libraryEditRemovePreviewImage,
            variant: AppToolChipVariant.tinted,
            unselectedBackgroundColor: colors.errorSurface,
            onTap: _clearPreviewImage,
          ),
      ],
    );
  }

  List<Widget> _buildFormFields(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.colors;

    return [
      // 1. 标题 (Notion 页面大标题风格，无外框)
      _FieldLabel(text: '${l10n.libraryEditFieldTitle} *'),
      AppErrorShake(
        trigger: _titleShakeTrigger,
        child: TextField(
          controller: _titleController,
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: l10n.libraryEditFieldTitleHint,
            hintStyle: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: colors.textMuted.withValues(alpha: 0.75),
            ),
            filled: false,
            hoverColor: Colors.transparent,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 4),
          ),
        ),
      ),
      const SizedBox(height: 10),

      // 2. 分类 (无框一键胶囊)
      _FieldLabel(text: '${l10n.libraryEditFieldCategory} *'),
      const SizedBox(height: 6),
      _buildCategoryChips(context),
      AppPanelReveal(
        visible: _isCustomCategory,
        openDuration: AppMotionDurations.fast,
        closeDuration: AppMotionDurations.quick,
        slideOffset: AppMotionDistances.base,
        enableBlur: false,
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: TextField(
            controller: _customCategoryController,
            style: TextStyle(fontSize: 13, color: colors.textPrimary),
            decoration: _softFieldDecoration(
              context,
              hintText: l10n.libraryEditFieldCustomCategoryHint,
            ),
          ),
        ),
      ),
      const SizedBox(height: 14),

      // 3. 主提示词 (非风格分类) 或 前置词/后置词 (风格分类)
      if (_isStyleCategory) ...[
        SizedBox(
          width: double.infinity,
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              _FieldLabel(text: l10n.libraryEditFieldPrefix),
              AppToolChip(
                icon: Icons.input_rounded,
                label: l10n.libraryEditFillAllStyleFromWorkbench,
                variant: AppToolChipVariant.tinted,
                fontSize: 11.5,
                iconSize: 13,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                onTap: _fillStyleFromCurrentWorkspace,
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        AppErrorShake(
          trigger: _styleShakeTrigger,
          child: TextField(
            controller: _prefixPromptController,
            minLines: 3,
            maxLines: 6,
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: colors.textPrimary,
            ),
            decoration: _softFieldDecoration(
              context,
              hintText: l10n.libraryEditFieldPrefixHint,
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _FieldLabel(text: l10n.libraryEditFieldSuffix),
        const SizedBox(height: 6),
        TextField(
          controller: _suffixPromptController,
          minLines: 2,
          maxLines: 5,
          style: TextStyle(
            fontSize: 13,
            height: 1.5,
            color: colors.textPrimary,
          ),
          decoration: _softFieldDecoration(
            context,
            hintText: l10n.libraryEditFieldSuffixHint,
            contentPadding: const EdgeInsets.all(12),
          ),
        ),
      ] else ...[
        SizedBox(
          width: double.infinity,
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              _FieldLabel(text: '${l10n.libraryEditFieldPrompt} *'),
              AppToolChip(
                icon: Icons.input_rounded,
                label: l10n.libraryEditFillFromPrompt,
                variant: AppToolChipVariant.tinted,
                fontSize: 11.5,
                iconSize: 13,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                onTap: _fillFromCurrentWorkspacePrompt,
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        AppErrorShake(
          trigger: _promptShakeTrigger,
          child: TextField(
            controller: _promptController,
            minLines: 5,
            maxLines: 10,
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: colors.textPrimary,
            ),
            decoration: _softFieldDecoration(
              context,
              hintText: l10n.libraryEditFieldPromptHint,
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
        ),
      ],

      // 4. 负面提示词 (角色与风格分类时平滑展开)
      AppPanelReveal(
        visible: _supportsNegativePrompt,
        openDuration: AppMotionDurations.fast,
        closeDuration: AppMotionDurations.quick,
        slideOffset: AppMotionDistances.base,
        enableBlur: false,
        child: Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: double.infinity,
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _FieldLabel(text: l10n.libraryEditFieldNegative),
                        const SizedBox(width: 8),
                        Text(
                          l10n.libraryEditCharacterOnlyBadge,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: colors.error,
                          ),
                        ),
                      ],
                    ),
                    AppToolChip(
                      icon: Icons.input_rounded,
                      label: l10n.libraryEditFillFromNegative,
                      variant: AppToolChipVariant.tinted,
                      fontSize: 11.5,
                      iconSize: 13,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      onTap: _fillFromCurrentWorkspaceNegative,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _negativePromptController,
                minLines: 3,
                maxLines: 6,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: colors.textPrimary,
                ),
                decoration: _softFieldDecoration(
                  context,
                  hintText: l10n.libraryEditFieldNegativeHint,
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 14),

      // 5. 检索标签
      _FieldLabel(text: l10n.libraryEditFieldTags),
      const SizedBox(height: 6),
      TextField(
        controller: _tagsController,
        style: TextStyle(fontSize: 13, color: colors.textPrimary),
        decoration: _softFieldDecoration(
          context,
          hintText: l10n.libraryEditFieldTagsHint,
        ),
      ),
    ];
  }

  Widget _buildFooterButtons(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        AppActionButton(
          label: l10n.cancel,
          variant: AppActionButtonVariant.ghost,
          onPressed: () => Navigator.of(context).pop(),
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

  Widget _buildCategoryChips(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final options = [...PromptComboCategories.defaults, _customCategorySentinel];

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final category in options)
          AppToolChip(
            icon: _categoryIcon(category),
            label: category == _customCategorySentinel
                ? l10n.libraryEditCustomCategoryOption
                : comboCategoryLabelOf(l10n, category),
            isSelected: _isCustomCategory
                ? category == _customCategorySentinel
                : _selectedCategory == category,
            variant: AppToolChipVariant.tinted,
            unselectedBackgroundColor: colors.elevatedBackground,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            radius: AppRadius.md,
            onTap: () {
              setState(() {
                _isCustomCategory = category == _customCategorySentinel;
                if (!_isCustomCategory) {
                  _selectedCategory = category;
                }
              });
            },
          ),
      ],
    );
  }

  IconData _categoryIcon(String category) {
    return switch (category) {
      PromptComboCategories.character => Icons.person_outline,
      PromptComboCategories.style => Icons.palette_outlined,
      PromptComboCategories.attire => Icons.checkroom_outlined,
      PromptComboCategories.composition => Icons.crop_free_outlined,
      PromptComboCategories.environment => Icons.landscape_outlined,
      PromptComboCategories.effect => Icons.auto_awesome_outlined,
      _customCategorySentinel => Icons.edit_outlined,
      _ => Icons.label_outline,
    };
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;

  const _FieldLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        color: context.colors.textMuted,
      ),
    );
  }
}
