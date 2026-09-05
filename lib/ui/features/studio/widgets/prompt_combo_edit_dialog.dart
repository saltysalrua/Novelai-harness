import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../../data/models/prompt_library_models.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_badge.dart';
import '../../../core/widgets/app_dialog_scaffold.dart';
import '../view_models/studio_view_model.dart';

/// 词组合弹窗统一输入框装饰 (浅灰填写风格，可选强调色)
///
/// 弹窗内五个表单字段共用同一套 OutlineInputBorder 视觉，仅 hint、
/// 内边距与强调色 (负面词字段为珊瑚色) 不同，避免逐字段复制粘贴。
InputDecoration _comboFieldDecoration(
  BuildContext context,
  String hint, {
  double hintFontSize = 12,
  EdgeInsetsGeometry contentPadding = const EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 8,
  ),
  Color? fillColor,
  Color? accentColor,
  Color? borderColor,
}) {
  final colors = context.colors;
  OutlineInputBorder outline(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: color, width: width),
      );
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(fontSize: hintFontSize, color: colors.textMuted),
    contentPadding: contentPadding,
    filled: true,
    fillColor: fillColor ?? colors.mutedBackground,
    border: outline(borderColor ?? colors.borderDefault),
    enabledBorder: outline(borderColor ?? colors.borderDefault),
    focusedBorder: outline(accentColor ?? colors.primary, 1.5),
  );
}

/// 词组合预设新建/编辑弹窗 (占屏 60~80%，左侧贯通预览图，右侧选择器与表单)
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
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        if (file.bytes != null) {
          setState(() {
            _previewBytes = file.bytes;
            _previewImagePath = file.path;
          });
        } else if (file.path != null) {
          final bytes = await File(file.path!).readAsBytes();
          setState(() {
            _previewBytes = bytes;
            _previewImagePath = file.path;
          });
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('选择图片失败: $e'),
          duration: const Duration(seconds: 2),
        ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已采用当前画板图像作为预览图'),
          duration: Duration(milliseconds: 900),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('画板当前暂无生成的图像'),
          duration: Duration(milliseconds: 1200),
          behavior: SnackBarBehavior.floating,
        ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('工作台主提示词为空'),
          duration: Duration(milliseconds: 900),
          behavior: SnackBarBehavior.floating,
        ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('工作台负面提示词为空'),
          duration: Duration(milliseconds: 900),
          behavior: SnackBarBehavior.floating,
        ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请输入词组合名称'),
          duration: Duration(milliseconds: 1200),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (prompt.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请输入主提示词内容'),
          duration: Duration(milliseconds: 1200),
          behavior: SnackBarBehavior.floating,
        ),
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
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isEdit ? '已更新词组合: $title' : '已添加词组合: $title'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('保存失败: $e'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = (screenSize.width * 0.72).clamp(700.0, 1060.0);
    final dialogHeight = (screenSize.height * 0.78).clamp(520.0, 800.0);

    return AppDialogScaffold(
      title: _isEdit ? '编辑词组合' : '新建词组合',
      width: dialogWidth,
      height: dialogHeight,
      sidebarWidth: 270.0,
      sidebar: _buildLeftPosterPanel(context),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 组合名称
            _buildFieldLabel(context, '组合名称', isRequired: true),
            const SizedBox(height: 6),
            TextField(
              controller: _titleController,
              style: TextStyle(fontSize: 13, color: colors.textPrimary),
              decoration: _comboFieldDecoration(
                context,
                '例如：赛博朋克猫耳少女 / 日系水彩插画',
                hintFontSize: 13,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 分类选择器
            _buildFieldLabel(context, '分类', isRequired: true),
            const SizedBox(height: 6),
            _buildCategoryDropdown(context),
            if (_isCustomCategory) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _customCategoryController,
                style: TextStyle(fontSize: 12, color: colors.textPrimary),
                decoration: _comboFieldDecoration(
                  context,
                  '输入自定义分类名称 (如：光影、视角)',
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),

            // 主提示词 (Positive)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildFieldLabel(context, '主提示词', isRequired: true),
                TextButton.icon(
                  onPressed: _fillFromCurrentWorkspacePrompt,
                  icon: Icon(Icons.input, size: 13, color: colors.primary),
                  label: Text(
                    '填入工作台主词',
                    style: TextStyle(fontSize: 11, color: colors.primary),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _promptController,
              maxLines: 4,
              minLines: 3,
              style: TextStyle(
                fontSize: 13,
                color: colors.textPrimary,
                height: 1.4,
              ),
              decoration: _comboFieldDecoration(
                context,
                '输入正向提示词 (如: 1girl, hatsune miku, cybernetic...)',
                hintFontSize: 13,
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
            const SizedBox(height: 16),

            // 负面提示词 (Negative) — 【只在选择了角色时才出现】
            if (_isCharacterCategory) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      _buildFieldLabel(context, '负面提示词'),
                      const SizedBox(width: 6),
                      const AppBadge(
                        label: '仅角色分类可用',
                        variant: AppBadgeVariant.error,
                        fontSize: 10,
                      ),
                    ],
                  ),
                  TextButton.icon(
                    onPressed: _fillFromCurrentWorkspaceNegative,
                    icon: Icon(Icons.input, size: 13, color: colors.error),
                    label: Text(
                      '填入工作台负向词',
                      style: TextStyle(fontSize: 11, color: colors.error),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _negativePromptController,
                maxLines: 3,
                minLines: 2,
                style: TextStyle(
                  fontSize: 12,
                  color: colors.textPrimary,
                  height: 1.35,
                ),
                decoration: _comboFieldDecoration(
                  context,
                  '角色专有负面词 (如: worst quality, bad hands, mutated...)',
                  contentPadding: const EdgeInsets.all(10),
                  fillColor: colors.errorSurface,
                  accentColor: colors.error,
                  borderColor: colors.error.withValues(alpha: 0.3),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // 检索标签 (Tags)
            _buildFieldLabel(context, '检索标签 (Tags)'),
            const SizedBox(height: 6),
            TextField(
              controller: _tagsController,
              style: TextStyle(fontSize: 12, color: colors.textPrimary),
              decoration: _comboFieldDecoration(
                context,
                '用于快速筛选，用逗号分隔 (例如：miku, 水彩, 二次元, 赛博)',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            '取消',
            style: TextStyle(fontSize: 12, color: colors.textSecondary),
          ),
        ),
        const SizedBox(width: 10),
        ElevatedButton(
          onPressed: _isSaving ? null : _handleSave,
          style: ElevatedButton.styleFrom(
            backgroundColor: colors.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
          ),
          child: _isSaving
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  _isEdit ? '保存修改' : '创建词组合',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
      ],
    );
  }

  /// 左侧贯通面板的图片占位符与预览区
  Widget _buildLeftPosterPanel(BuildContext context) {
    final colors = context.colors;
    final hasImage =
        _previewBytes != null ||
        (_previewImagePath != null && File(_previewImagePath!).existsSync());

    return Container(
      color: colors.mutedBackground,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 底层图像渲染或纯灰占位
          if (hasImage)
            (_previewBytes != null
                ? Image.memory(
                    _previewBytes!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        _buildPlaceholderGraphic(context),
                  )
                : Image.file(
                    File(_previewImagePath!),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        _buildPlaceholderGraphic(context),
                  ))
          else
            _buildPlaceholderGraphic(context),

          // 中央上下显示两个主要按钮
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              decoration: BoxDecoration(
                color: hasImage
                    ? Colors.black.withValues(alpha: 0.6)
                    : colors.cardBackground.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: hasImage
                      ? Colors.white.withValues(alpha: 0.2)
                      : colors.borderDefault,
                ),
                boxShadow: context.shadowSubtle,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!hasImage) ...[
                    Icon(
                      Icons.image_outlined,
                      size: 36,
                      color: colors.textSecondary,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '设置预览图',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // 上按钮：选择本地图片
                  ElevatedButton.icon(
                    onPressed: _pickLocalImage,
                    icon: const Icon(Icons.file_upload_outlined, size: 15),
                    label: const Text(
                      '选择本地图片',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: hasImage
                          ? colors.cardBackground
                          : colors.primaryTint,
                      foregroundColor: hasImage
                          ? colors.textPrimary
                          : colors.primary,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        side: BorderSide(
                          color: hasImage
                              ? Colors.transparent
                              : colors.primary.withValues(alpha: 0.3),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // 下按钮：使用画板当前图
                  ElevatedButton.icon(
                    onPressed: _useCurrentCanvasImage,
                    icon: const Icon(Icons.image_outlined, size: 15),
                    label: const Text(
                      '使用画板当前图',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: hasImage
                          ? colors.cardBackground
                          : colors.mutedBackground,
                      foregroundColor: colors.textPrimary,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        side: BorderSide(
                          color: hasImage
                              ? Colors.transparent
                              : colors.borderDefault,
                        ),
                      ),
                    ),
                  ),

                  // 若已有图片，显示移除图片按钮
                  if (hasImage) ...[
                    const SizedBox(height: 10),
                    TextButton.icon(
                      onPressed: _clearPreviewImage,
                      icon: Icon(
                        Icons.delete_outline,
                        size: 14,
                        color: colors.error,
                      ),
                      label: Text(
                        '移除预览图',
                        style: TextStyle(fontSize: 12, color: colors.error),
                      ),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholderGraphic(BuildContext context) {
    return Container(color: context.colors.mutedBackground);
  }

  Widget _buildFieldLabel(
    BuildContext context,
    String label, {
    bool isRequired = false,
  }) {
    final colors = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        if (isRequired)
          Text(' *', style: TextStyle(fontSize: 12, color: colors.error)),
      ],
    );
  }

  /// 下拉分类选择器 (取代平铺 Chips)
  Widget _buildCategoryDropdown(BuildContext context) {
    final colors = context.colors;
    final categories = [...PromptComboCategories.defaults, '自定义...'];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colors.mutedBackground,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.borderDefault),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _isCustomCategory ? '自定义...' : _selectedCategory,
          isExpanded: true,
          icon: Icon(Icons.arrow_drop_down, color: colors.textSecondary),
          style: TextStyle(fontSize: 13, color: colors.textPrimary),
          dropdownColor: colors.cardBackground,
          borderRadius: BorderRadius.circular(AppRadius.md),
          items: categories.map((cat) {
            final isChar = cat == '角色';
            return DropdownMenuItem<String>(
              value: cat,
              child: Row(
                children: [
                  Icon(
                    isChar
                        ? Icons.person_outline
                        : (cat == '自定义...'
                              ? Icons.edit_outlined
                              : Icons.label_outline),
                    size: 15,
                    color: isChar ? colors.error : colors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    cat,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isChar ? FontWeight.w600 : FontWeight.normal,
                      color: isChar ? colors.error : colors.textPrimary,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: (val) {
            if (val == null) return;
            setState(() {
              if (val == '自定义...') {
                _isCustomCategory = true;
              } else {
                _isCustomCategory = false;
                _selectedCategory = val;
              }
            });
          },
        ),
      ),
    );
  }
}
