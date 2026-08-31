import 'package:flutter/material.dart';
import '../../../../data/models/novelai_models.dart';
import '../../../../data/models/prompt_library_models.dart';
import '../../../core/theme/app_theme.dart';
import '../view_models/studio_view_model.dart';
import 'character_position_canvas_view.dart';
import 'pill_widgets.dart';
import 'prompt_combo_edit_dialog.dart';
import 'prompt_resize_handle.dart';
import 'rich_prompt_text_controller.dart';

/// 单个角色编辑卡：一体化卡片容器 (无嵌套边框) + 名称/启停/位置 + 正负提示词独立垂直拖拽调节。
///
/// 位置胶囊点击直接打开中间画板进行拖拽定位；编辑模式下悬停卡片滚轮可
/// 循环切换选中角色 (140ms 节流)，键盘方向键切换由 StudioView 全局处理。
class CharacterCardItem extends StatefulWidget {
  final NaiCharacterPrompt character;
  final int index;
  final int enabledTotal;
  final StudioViewModel viewModel;

  const CharacterCardItem({
    super.key,
    required this.character,
    required this.index,
    required this.enabledTotal,
    required this.viewModel,
  });

  @override
  State<CharacterCardItem> createState() => _CharacterCardItemState();
}

class _CharacterCardItemState extends State<CharacterCardItem> {
  static const double _defaultPromptHeight = 76.0;
  static const double _defaultNegativeHeight = 54.0;

  late final TextEditingController _nameController;
  late final RichPromptTextController _promptController;
  late final RichPromptTextController _negativeController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.character.name);
    _promptController = RichPromptTextController(text: widget.character.prompt);
    _negativeController = RichPromptTextController(
      text: widget.character.negativePrompt,
    );
  }

  @override
  void didUpdateWidget(covariant CharacterCardItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    final character = widget.character;
    if (oldWidget.character.id != character.id) return;
    if (_nameController.text != character.name) {
      _nameController.text = character.name;
    }
    if (_promptController.text != character.prompt) {
      _promptController.text = character.prompt;
    }
    if (_negativeController.text != character.negativePrompt) {
      _negativeController.text = character.negativePrompt;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _promptController.dispose();
    _negativeController.dispose();
    super.dispose();
  }

  void _update(NaiCharacterPrompt updated) {
    widget.viewModel.updateCharacterPrompt(updated);
  }

  void _saveToLibrary() {
    final character = widget.character;
    final title = character.name.trim().isNotEmpty
        ? character.name.trim()
        : '角色 ${widget.index + 1}';
    PromptComboEditDialog.show(
      context,
      viewModel: widget.viewModel,
      initialEntry: PromptComboEntry(
        id: '',
        title: title,
        category: PromptComboCategories.character,
        prompt: character.prompt.trim(),
        negativePrompt: character.negativePrompt.trim(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
  }

  /// 位置标签：AI 自动布局时显示 AI；自定义定位在 V5 显示百分比 (如 50%, 50%)，在 V4/V4.5 显示网格参考 (如 B2)
  String get _positionLabel {
    final c = widget.character;
    final model = widget.viewModel.params.model;
    if (!widget.viewModel.params.characterAiPosition) {
      final x = c.useCustomPosition ? c.positionX : _autoX();
      final y = c.useCustomPosition ? c.positionY : _autoY();
      if (model.supportsFreeCharacterPositioning) {
        final pctX = (x * 100).round();
        final pctY = (y * 100).round();
        return '$pctX%, $pctY%';
      }
      return _gridLabel(x, y);
    }
    return 'AI';
  }

  double _autoX() {
    final list = widget.viewModel.params.characterPrompts
        .where((x) => x.enabled)
        .toList();
    final idx = list.indexWhere((x) => x.id == widget.character.id);
    return NaiCharacterPositionLayout.positionForIndex(
      idx < 0 ? widget.index : idx,
      widget.enabledTotal,
    ).x;
  }

  double _autoY() {
    final list = widget.viewModel.params.characterPrompts
        .where((x) => x.enabled)
        .toList();
    final idx = list.indexWhere((x) => x.id == widget.character.id);
    return NaiCharacterPositionLayout.positionForIndex(
      idx < 0 ? widget.index : idx,
      widget.enabledTotal,
    ).y;
  }

  String _gridLabel(double x, double y) {
    final col = (x * 4).round().clamp(0, 4);
    final row = (y * 4).round().clamp(0, 4);
    return '${String.fromCharCode('A'.codeUnitAt(0) + col)}${row + 1}';
  }

  @override
  Widget build(BuildContext context) {
    // 同步设置项：标签分类着色开关 (设置弹窗保存后 viewModel 通知重建)
    final showCategoryColors = widget.viewModel.config.showTagCategoryColors;
    _promptController.setHighlightOptions(categoryColors: showCategoryColors);
    _negativeController.setHighlightOptions(categoryColors: showCategoryColors);

    final character = widget.character;
    final viewModel = widget.viewModel;
    final customMode = !viewModel.params.characterAiPosition;
    final isSelectedInCanvas =
        viewModel.isEditingCharacterPositions &&
        viewModel.selectedCharacterId == character.id;

    final card = Container(
      decoration: BoxDecoration(
        color: AppTheme.pureWhite,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(
          color: isSelectedInCanvas
              ? AppTheme.notionBlue
              : (character.enabled
                    ? AppTheme.border
                    : AppTheme.border.withValues(alpha: 0.5)),
          width: isSelectedInCanvas ? 1.8 : 1.0,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Opacity(
        opacity: character.enabled ? 1.0 : 0.55,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 头部：序号 + 名称 (弹性自适应占满) + 删除，下层为启停 + 位置胶囊 (流式防溢出)
            Container(
              color: isSelectedInCanvas
                  ? AppTheme.skyTint.withValues(alpha: 0.45)
                  : AppTheme.surfaceElevated,
              padding: const EdgeInsets.fromLTRB(10, 7, 8, 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 第一行：角色序号 + 名称输入框 (自适应弹性填充) + 删除按钮
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isSelectedInCanvas
                              ? AppTheme.notionBlue
                              : AppTheme.borderSubtle,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${widget.index + 1}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isSelectedInCanvas
                                ? Colors.white
                                : AppTheme.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _nameController,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                          decoration: const InputDecoration(
                            isDense: true,
                            filled: false,
                            hoverColor: Colors.transparent,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            hintText: '角色名称 (可选)',
                            hintStyle: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.normal,
                              color: AppTheme.textMuted,
                            ),
                            contentPadding: EdgeInsets.zero,
                          ),
                          // 输入中不做 trim，避免末尾空格被吞导致无法输入带空格的名称
                          onChanged: (value) =>
                              _update(character.copyWith(name: value)),
                          onSubmitted: (value) =>
                              _update(character.copyWith(name: value.trim())),
                        ),
                      ),
                      const SizedBox(width: 4),
                      _SaveToLibraryIcon(onTap: _saveToLibrary),
                      const SizedBox(width: 2),
                      _DeleteIcon(
                        onTap: () =>
                            viewModel.removeCharacterPrompt(character.id),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // 第二行：启停状态胶囊 + 位置胶囊 (流式防溢出，自适应窄屏)
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ToggleChip(
                        isActive: character.enabled,
                        icon: character.enabled
                            ? Icons.visibility_rounded
                            : Icons.visibility_off_rounded,
                        label: character.enabled ? '启用' : '停用',
                        onTap: () => _update(
                          character.copyWith(enabled: !character.enabled),
                        ),
                      ),
                      _PositionPill(
                        label: _positionLabel,
                        isCustom: customMode,
                        isSelected: isSelectedInCanvas,
                        onTap: () {
                          if (viewModel.params.characterAiPosition) {
                            viewModel.setCharacterAiPosition(false);
                          }
                          viewModel.selectCharacterId(character.id);
                          viewModel.setEditingCharacterPositions(true);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(
              height: 1,
              thickness: 1,
              color: AppTheme.borderSubtle,
            ),

            // 正向提示词输入区 (支持上下拖拽调节高度，无内部嵌套边框)
            ResizableTextField(
              controller: _promptController,
              onChanged: (value) => _update(character.copyWith(prompt: value)),
              hintText: '角色正向提示词，如: 1girl, silver hair, twintails, smile...',
              defaultHeight: _defaultPromptHeight,
              minHeight: 44,
              maxHeight: 400,
              resizeTooltip: '拖动调整正向提示词高度 (双击重置)',
              enableAutocomplete: viewModel.config.enableTagAutocomplete,
              showTranslation: viewModel.config.showTagTranslations,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.48,
                color: AppTheme.textPrimary,
              ),
              hintStyle: const TextStyle(
                fontSize: 13,
                height: 1.48,
                color: AppTheme.textMuted,
              ),
            ),
            const Divider(
              height: 1,
              thickness: 1,
              color: AppTheme.borderSubtle,
            ),

            // 负面提示词输入区 (支持上下拖拽调节高度，无内部嵌套边框)
            ResizableTextField(
              controller: _negativeController,
              onChanged: (value) =>
                  _update(character.copyWith(negativePrompt: value)),
              hintText: '角色负面提示词 (可选)，如: bad hands, blurry...',
              defaultHeight: _defaultNegativeHeight,
              minHeight: 36,
              maxHeight: 300,
              resizeTooltip: '拖动调整负面提示词高度 (双击重置)',
              enableAutocomplete: viewModel.config.enableTagAutocomplete,
              showTranslation: viewModel.config.showTagTranslations,
              style: const TextStyle(
                fontSize: 13,
                height: 1.45,
                color: AppTheme.textSecondary,
              ),
              hintStyle: const TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: AppTheme.textMuted,
              ),
            ),
          ],
        ),
      ),
    );

    // 编辑模式下悬停卡片滚轮可切换选中角色 (带节流)
    return CharacterWheelCycleListener(
      viewModel: viewModel,
      throttle: const Duration(milliseconds: 140),
      child: card,
    );
  }
}

/// 位置胶囊 (点击直接打开中间画板进行位置拖拽定位)
class _PositionPill extends StatelessWidget {
  final String label;
  final bool isCustom;
  final bool isSelected;
  final VoidCallback onTap;

  const _PositionPill({
    required this.label,
    required this.isCustom,
    this.isSelected = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '在中间画板编辑角色位置',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.notionBlue
                : (isCustom ? AppTheme.skyTint : AppTheme.surfaceMuted),
            borderRadius: BorderRadius.circular(AppTheme.radiusPill),
            border: Border.all(
              color: isSelected
                  ? AppTheme.notionBlue
                  : (isCustom
                        ? AppTheme.notionBlue.withValues(alpha: 0.5)
                        : AppTheme.border),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.open_with_rounded,
                size: 11.5,
                color: isSelected
                    ? Colors.white
                    : (isCustom ? AppTheme.notionBlue : AppTheme.textMuted),
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isSelected
                      ? Colors.white
                      : (isCustom
                            ? AppTheme.notionBlue
                            : AppTheme.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 保存到词库图标按钮
class _SaveToLibraryIcon extends StatelessWidget {
  final VoidCallback onTap;

  const _SaveToLibraryIcon({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '保存角色到词库',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: const Padding(
          padding: EdgeInsets.all(5),
          child: Icon(
            Icons.bookmark_add_outlined,
            size: 15,
            color: AppTheme.textMuted,
          ),
        ),
      ),
    );
  }
}

/// 删除图标按钮
class _DeleteIcon extends StatelessWidget {
  final VoidCallback onTap;

  const _DeleteIcon({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '删除该角色',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: const Padding(
          padding: EdgeInsets.all(5),
          child: Icon(Icons.close_rounded, size: 15, color: AppTheme.textMuted),
        ),
      ),
    );
  }
}
