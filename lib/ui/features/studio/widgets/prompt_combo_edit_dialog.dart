import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../../data/models/prompt_library_models.dart';
import '../../../core/theme/app_theme.dart';
import '../view_models/studio_view_model.dart';

/// 词组合弹窗统一输入框装饰 (浅灰填写风格，可选强调色)
///
/// 弹窗内五个表单字段共用同一套 OutlineInputBorder 视觉，仅 hint、
/// 内边距与强调色 (负面词字段为珊瑚色) 不同，避免逐字段复制粘贴。
InputDecoration _comboFieldDecoration(
  String hint, {
  double hintFontSize = 12,
  EdgeInsetsGeometry contentPadding = const EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 8,
  ),
  Color? fillColor,
  Color accentColor = AppTheme.notionBlue,
  Color? borderColor,
}) {
  OutlineInputBorder outline(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusButton),
        borderSide: BorderSide(color: color, width: width),
      );
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(fontSize: hintFontSize, color: AppTheme.graphite),
    contentPadding: contentPadding,
    filled: true,
    fillColor: fillColor ?? AppTheme.surfaceMuted,
    border: outline(borderColor ?? AppTheme.border),
    enabledBorder: outline(borderColor ?? AppTheme.border),
    focusedBorder: outline(accentColor, 1.5),
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
    return showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
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
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = (screenSize.width * 0.72).clamp(700.0, 1060.0);
    final dialogHeight = (screenSize.height * 0.78).clamp(520.0, 800.0);

    return Dialog(
      backgroundColor: AppTheme.pureWhite,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        side: const BorderSide(color: AppTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. 左侧贯通图片占位符/海报区 (贯穿整个面板上下)
            _buildLeftPosterPanel(),

            const VerticalDivider(width: 1, color: AppTheme.border),

            // 2. 右侧区域 (包含顶部标题栏 + 滚动表单 + 底部操作栏)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // (1) 右侧顶部标题栏
                  _buildHeader(),
                  const Divider(height: 1, color: AppTheme.border),

                  // (2) 右侧表单滚动区
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 组合名称
                          _buildFieldLabel('组合名称', isRequired: true),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _titleController,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppTheme.charcoal,
                            ),
                            decoration: _comboFieldDecoration(
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
                          _buildFieldLabel('分类', isRequired: true),
                          const SizedBox(height: 6),
                          _buildCategoryDropdown(),
                          if (_isCustomCategory) ...[
                            const SizedBox(height: 8),
                            TextField(
                              controller: _customCategoryController,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.charcoal,
                              ),
                              decoration: _comboFieldDecoration(
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
                              _buildFieldLabel('主提示词', isRequired: true),
                              TextButton.icon(
                                onPressed: _fillFromCurrentWorkspacePrompt,
                                icon: const Icon(
                                  Icons.input,
                                  size: 13,
                                  color: AppTheme.notionBlue,
                                ),
                                label: const Text(
                                  '填入工作台主词',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.notionBlue,
                                  ),
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
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: AppTheme.charcoal,
                              height: 1.4,
                            ),
                            decoration: _comboFieldDecoration(
                              '输入正向提示词 (如: 1girl, hatsune miku, cybernetic...)',
                              hintFontSize: 12.5,
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
                                    _buildFieldLabel('负面提示词'),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 1.5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFDEEED),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: AppTheme.coral.withValues(
                                            alpha: 0.3,
                                          ),
                                        ),
                                      ),
                                      child: const Text(
                                        '仅角色分类可用',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: AppTheme.coral,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                TextButton.icon(
                                  onPressed: _fillFromCurrentWorkspaceNegative,
                                  icon: const Icon(
                                    Icons.input,
                                    size: 13,
                                    color: AppTheme.coral,
                                  ),
                                  label: const Text(
                                    '填入工作台负向词',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.coral,
                                    ),
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
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.charcoal,
                                height: 1.35,
                              ),
                              decoration: _comboFieldDecoration(
                                '角色专有负面词 (如: worst quality, bad hands, mutated...)',
                                contentPadding: const EdgeInsets.all(10),
                                fillColor: const Color(0xFFFCF9F9),
                                accentColor: AppTheme.coral,
                                borderColor: AppTheme.coral.withValues(
                                  alpha: 0.3,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],

                          // 检索标签 (Tags)
                          _buildFieldLabel('检索标签 (Tags)'),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _tagsController,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.charcoal,
                            ),
                            decoration: _comboFieldDecoration(
                              '用于快速筛选，用逗号分隔 (例如：miku, 水彩, 二次元, 赛博)',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const Divider(height: 1, color: AppTheme.border),

                  // (3) 右侧底部操作栏
                  _buildFooter(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppTheme.skyTint,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(
              Icons.collections_bookmark_outlined,
              size: 18,
              color: AppTheme.notionBlue,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _isEdit ? '编辑词组合' : '新建词组合',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppTheme.charcoal,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close, size: 18, color: AppTheme.graphite),
            onPressed: () => Navigator.of(context).pop(),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  /// 左侧贯通整个面板的图片占位符与预览区 (中性灰底色，中央上下排列两个操作按钮)
  Widget _buildLeftPosterPanel() {
    final hasImage =
        _previewBytes != null ||
        (_previewImagePath != null && File(_previewImagePath!).existsSync());

    return Container(
      width: 270,
      decoration: const BoxDecoration(
        color: Color(0xFFF2F1ED), // 统一纯净中性灰
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(AppTheme.radiusCard),
          bottomLeft: Radius.circular(AppTheme.radiusCard),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 底层图像渲染或纯灰占位
          if (hasImage)
            (_previewBytes != null
                ? Image.memory(
                    _previewBytes!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => _buildPlaceholderGraphic(),
                  )
                : Image.file(
                    File(_previewImagePath!),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => _buildPlaceholderGraphic(),
                  ))
          else
            _buildPlaceholderGraphic(),

          // 中央上下显示两个主要按钮
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              decoration: BoxDecoration(
                color: hasImage
                    ? Colors.black.withValues(alpha: 0.6)
                    : Colors.white.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                border: Border.all(
                  color: hasImage
                      ? Colors.white.withValues(alpha: 0.2)
                      : AppTheme.border,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!hasImage) ...[
                    const Icon(
                      Icons.image_outlined,
                      size: 36,
                      color: AppTheme.graphite,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '设置预览图',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.charcoal,
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
                          ? Colors.white
                          : AppTheme.skyTint,
                      foregroundColor: hasImage
                          ? AppTheme.charcoal
                          : AppTheme.notionBlue,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppTheme.radiusButton,
                        ),
                        side: BorderSide(
                          color: hasImage
                              ? Colors.transparent
                              : AppTheme.notionBlue.withValues(alpha: 0.3),
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
                          ? Colors.white
                          : AppTheme.surfaceMuted,
                      foregroundColor: hasImage
                          ? AppTheme.charcoal
                          : AppTheme.charcoal,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppTheme.radiusButton,
                        ),
                        side: BorderSide(
                          color: hasImage
                              ? Colors.transparent
                              : AppTheme.border,
                        ),
                      ),
                    ),
                  ),

                  // 若已有图片，显示移除图片按钮
                  if (hasImage) ...[
                    const SizedBox(height: 10),
                    TextButton.icon(
                      onPressed: _clearPreviewImage,
                      icon: const Icon(
                        Icons.delete_outline,
                        size: 14,
                        color: Color(0xFFFF8B80),
                      ),
                      label: const Text(
                        '移除预览图',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFFFF8B80),
                        ),
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

  Widget _buildPlaceholderGraphic() {
    return Container(color: const Color(0xFFF2F1ED));
  }

  Widget _buildFieldLabel(String label, {bool isRequired = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppTheme.charcoal,
          ),
        ),
        if (isRequired)
          const Text(
            ' *',
            style: TextStyle(fontSize: 12, color: AppTheme.coral),
          ),
      ],
    );
  }

  /// 下拉分类选择器 (取代平铺 Chips)
  Widget _buildCategoryDropdown() {
    final categories = [...PromptComboCategories.defaults, '自定义...'];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(AppTheme.radiusButton),
        border: Border.all(color: AppTheme.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _isCustomCategory ? '自定义...' : _selectedCategory,
          isExpanded: true,
          icon: const Icon(Icons.arrow_drop_down, color: AppTheme.graphite),
          style: const TextStyle(fontSize: 13, color: AppTheme.charcoal),
          dropdownColor: AppTheme.pureWhite,
          borderRadius: BorderRadius.circular(AppTheme.radiusButton),
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
                    color: isChar ? AppTheme.coral : AppTheme.graphite,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    cat,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: isChar ? FontWeight.w600 : FontWeight.normal,
                      color: isChar ? AppTheme.coral : AppTheme.charcoal,
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

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              '取消',
              style: TextStyle(fontSize: 12, color: AppTheme.graphite),
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            onPressed: _isSaving ? null : _handleSave,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.notionBlue,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusButton),
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
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
