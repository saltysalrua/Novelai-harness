import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../../data/models/novelai_models.dart';
import '../view_models/studio_view_model.dart';
import 'pill_widgets.dart';

/// 角色提示词区块：多角色防串色隔离的增删改与定位管理。
///
/// 对齐官方 V5 交互：位置模式是区块级全局开关 (AI's Choice / 自定义)；
/// 自定义定位时 V5 在画布上自由拖动 (连续小数坐标)，V4/V4.5 限制 5x5 网格；
/// AI 自动布局下不发送任何位置参数，各角色的手动定位数据保留。
class CharacterPromptsSection extends StatelessWidget {
  final StudioViewModel viewModel;

  const CharacterPromptsSection({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final params = viewModel.params;
    final characters = params.characterPrompts;
    final limit = viewModel.characterPromptLimit;
    final supported = limit > 0;
    final isFull = viewModel.isCharacterPromptFull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      'Character Prompts',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  if (characters.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Text(
                      '${characters.length}/$limit',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            _AddCharacterButton(
              enabled: supported && !isFull,
              onTap: supported && !isFull
                  ? () => viewModel.addCharacterPrompt()
                  : null,
            ),
          ],
        ),
        if (!supported)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '当前模型不支持角色提示词 (仅 V4 及以上模型生效)，下方配置将保留但不会参与生成。',
              style: TextStyle(
                fontSize: 11,
                color: AppTheme.warning.withValues(alpha: 0.9),
              ),
            ),
          ),
        if (characters.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '添加多个角色即可进行防串色隔离生图，主提示词负责全局环境、构图与人数标签 (如 2girls)。',
              style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
            ),
          )
        else ...[
          // 全局位置模式行：AI 自动布局 (官方 AI's Choice) ↔ 自定义定位
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                ToggleChip(
                  isActive: params.characterAiPosition,
                  icon: Icons.auto_awesome_rounded,
                  label: 'AI 自动布局',
                  onTap: () => viewModel.setCharacterAiPosition(true),
                ),
                const SizedBox(width: 6),
                ToggleChip(
                  isActive: !params.characterAiPosition,
                  icon: Icons.open_with_rounded,
                  label: '自定义定位',
                  onTap: () => viewModel.setCharacterAiPosition(false),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < characters.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _CharacterCard(
              key: ValueKey(characters[i].id),
              character: characters[i],
              index: i,
              enabledTotal: characters.where((c) => c.enabled).length,
              viewModel: viewModel,
            ),
          ],
        ],
      ],
    );
  }
}

/// 添加角色胶囊按钮
class _AddCharacterButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback? onTap;

  const _AddCharacterButton({required this.enabled, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: enabled ? AppTheme.skyTint : AppTheme.surfaceMuted,
          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
          border: Border.all(
            color: enabled
                ? AppTheme.notionBlue.withValues(alpha: 0.5)
                : AppTheme.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.person_add_alt_rounded,
              size: 12.5,
              color: enabled ? AppTheme.notionBlue : AppTheme.textMuted,
            ),
            const SizedBox(width: 4),
            Text(
              enabled ? '添加角色' : '已达上限',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: enabled ? AppTheme.notionBlue : AppTheme.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 单个角色编辑卡：名称 + 启停 + 位置 + 正负提示词
class _CharacterCard extends StatefulWidget {
  final NaiCharacterPrompt character;
  final int index;
  final int enabledTotal;
  final StudioViewModel viewModel;

  const _CharacterCard({
    super.key,
    required this.character,
    required this.index,
    required this.enabledTotal,
    required this.viewModel,
  });

  @override
  State<_CharacterCard> createState() => _CharacterCardState();
}

class _CharacterCardState extends State<_CharacterCard> {
  late final TextEditingController _nameController;
  late final TextEditingController _promptController;
  late final TextEditingController _negativeController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.character.name);
    _promptController = TextEditingController(text: widget.character.prompt);
    _negativeController = TextEditingController(
      text: widget.character.negativePrompt,
    );
  }

  @override
  void didUpdateWidget(covariant _CharacterCard oldWidget) {
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

  /// 位置标签：AI 自动布局时显示 AI；自定义定位显示网格参考 (如 B2)
  String get _positionLabel {
    final c = widget.character;
    if (!widget.viewModel.params.characterAiPosition) {
      return _gridLabel(
        c.useCustomPosition ? c.positionX : _autoX(),
        c.useCustomPosition ? c.positionY : _autoY(),
      );
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
    final character = widget.character;
    final viewModel = widget.viewModel;
    final customMode = !viewModel.params.characterAiPosition;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.pureWhite,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(
          color: character.enabled
              ? AppTheme.border
              : AppTheme.border.withValues(alpha: 0.5),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Opacity(
        opacity: character.enabled ? 1.0 : 0.55,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 头部：序号 + 名称 + 启停 + 位置 + 删除
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 6, 0),
              child: Row(
                children: [
                  Text(
                    '${widget.index + 1}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textMuted,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _nameController,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: '角色名称',
                        hintStyle: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textMuted,
                        ),
                        contentPadding: EdgeInsets.symmetric(vertical: 4),
                      ),
                      onSubmitted: (value) =>
                          _update(character.copyWith(name: value.trim())),
                    ),
                  ),
                  const SizedBox(width: 6),
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
                  const SizedBox(width: 6),
                  _PositionPill(
                    label: _positionLabel,
                    isCustom: customMode,
                    onTap: customMode
                        ? () => _showPositionPicker(context)
                        : null,
                  ),
                  const SizedBox(width: 4),
                  _DeleteIcon(
                    onTap: () => viewModel.removeCharacterPrompt(character.id),
                  ),
                ],
              ),
            ),
            // 正向提示词
            _CardField(
              controller: _promptController,
              hintText: '角色正向提示词，如: girl, silver hair, ...',
              onChanged: (value) => _update(character.copyWith(prompt: value)),
            ),
            // 负面提示词
            _CardField(
              controller: _negativeController,
              hintText: '角色负面提示词 (可选)',
              isNegative: true,
              onChanged: (value) =>
                  _update(character.copyWith(negativePrompt: value)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showPositionPicker(BuildContext context) async {
    final character = widget.character;
    final model = widget.viewModel.params.model;
    final result = await showDialog<(double, double)>(
      context: context,
      builder: (ctx) => model.supportsFreeCharacterPositioning
          ? _FreePositionPickerDialog(character: character)
          : _GridPositionPickerDialog(character: character),
    );
    if (result == null || !mounted) return;
    final (x, y) = result;
    _update(
      character.copyWith(useCustomPosition: true, positionX: x, positionY: y),
    );
  }
}

/// 位置胶囊 (自定义定位模式下点击打开选择器；AI 模式置灰展示)
class _PositionPill extends StatelessWidget {
  final String label;
  final bool isCustom;
  final VoidCallback? onTap;

  const _PositionPill({
    required this.label,
    required this.isCustom,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
        decoration: BoxDecoration(
          color: isCustom ? AppTheme.skyTint : AppTheme.surfaceMuted,
          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
          border: Border.all(
            color: isCustom
                ? AppTheme.notionBlue.withValues(alpha: 0.5)
                : AppTheme.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.open_with_rounded,
              size: 11,
              color: isCustom ? AppTheme.notionBlue : AppTheme.textMuted,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: isCustom ? AppTheme.notionBlue : AppTheme.textSecondary,
              ),
            ),
          ],
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
          child: Icon(Icons.close_rounded, size: 14, color: AppTheme.textMuted),
        ),
      ),
    );
  }
}

/// 卡片内文本输入框 (正向 / 负面共用)
class _CardField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final bool isNegative;
  final ValueChanged<String> onChanged;

  const _CardField({
    required this.controller,
    required this.hintText,
    required this.onChanged,
    this.isNegative = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
      child: TextField(
        controller: controller,
        minLines: 1,
        maxLines: 4,
        style: TextStyle(
          fontSize: 12,
          height: 1.4,
          color: isNegative ? AppTheme.textSecondary : AppTheme.textPrimary,
        ),
        decoration: InputDecoration(
          isDense: true,
          hintText: hintText,
          hintStyle: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppTheme.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppTheme.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(
              color: AppTheme.notionBlue,
              width: 1.2,
            ),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 9,
            vertical: 7,
          ),
        ),
        onChanged: onChanged,
      ),
    );
  }
}

/// V5 自由定位弹窗：画布拖拽锚点 + 直接输入完整小数坐标。
///
/// 返回；取消返回 null。坐标为 0.0~1.0 连续小数，无网格量化。
class _FreePositionPickerDialog extends StatefulWidget {
  final NaiCharacterPrompt character;

  const _FreePositionPickerDialog({required this.character});

  @override
  State<_FreePositionPickerDialog> createState() =>
      _FreePositionPickerDialogState();
}

class _FreePositionPickerDialogState extends State<_FreePositionPickerDialog> {
  late double _x;
  late double _y;
  late final TextEditingController _xController;
  late final TextEditingController _yController;

  @override
  void initState() {
    super.initState();
    _x = widget.character.positionX.clamp(0.0, 1.0);
    _y = widget.character.positionY.clamp(0.0, 1.0);
    _xController = TextEditingController(text: _format(_x));
    _yController = TextEditingController(text: _format(_y));
  }

  @override
  void dispose() {
    _xController.dispose();
    _yController.dispose();
    super.dispose();
  }

  static String _format(double v) => v
      .toStringAsFixed(3)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');

  void _set(double x, double y) {
    setState(() {
      _x = x.clamp(0.0, 1.0);
      _y = y.clamp(0.0, 1.0);
      _xController.text = _format(_x);
      _yController.text = _format(_y);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.pureWhite,
      title: const Text(
        '角色位置 (自由坐标)',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '拖动锚点或直接输入坐标 (0.0~1.0 连续小数，X 左→右，Y 上→下)：',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 10),
            AspectRatio(
              aspectRatio: 1.4,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return GestureDetector(
                    onPanDown: (details) =>
                        _applyDrag(details.localPosition, constraints.biggest),
                    onPanUpdate: (details) =>
                        _applyDrag(details.localPosition, constraints.biggest),
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceMuted,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Stack(
                        children: [
                          // 三分参考线
                          Center(
                            child: Container(
                              width: 1,
                              color: AppTheme.border.withValues(alpha: 0.6),
                            ),
                          ),
                          Center(
                            child: Container(
                              height: 1,
                              color: AppTheme.border.withValues(alpha: 0.6),
                            ),
                          ),
                          Align(
                            alignment: Alignment(-1 + _x * 2, -1 + _y * 2),
                            child: Container(
                              margin: const EdgeInsets.all(14),
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: AppTheme.notionBlue,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppTheme.notionBlue.withValues(
                                      alpha: 0.35,
                                    ),
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _CoordField(
                    controller: _xController,
                    label: 'X',
                    onChanged: (v) => setState(() => _x = v),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _CoordField(
                    controller: _yController,
                    label: 'Y',
                    onChanged: (v) => setState(() => _y = v),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.notionBlue,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.of(context).pop((_x, _y)),
          child: const Text('确定'),
        ),
      ],
    );
  }

  void _applyDrag(Offset local, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    _set(local.dx / size.width, local.dy / size.height);
  }
}

/// 小数坐标输入框 (X / Y)
class _CoordField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final ValueChanged<double> onChanged;

  const _CoordField({
    required this.controller,
    required this.label,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(fontSize: 12.5, color: AppTheme.textPrimary),
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        labelStyle: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppTheme.border),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      ),
      onChanged: (value) {
        final parsed = double.tryParse(value.trim());
        if (parsed != null) onChanged(parsed.clamp(0.0, 1.0));
      },
    );
  }
}

/// V4/V4.5 网格定位弹窗：官方 5x5 网格 (列 A-E，行 1-5)。
class _GridPositionPickerDialog extends StatefulWidget {
  final NaiCharacterPrompt character;

  const _GridPositionPickerDialog({required this.character});

  @override
  State<_GridPositionPickerDialog> createState() =>
      _GridPositionPickerDialogState();
}

class _GridPositionPickerDialogState extends State<_GridPositionPickerDialog> {
  late int _selectedCol;
  late int _selectedRow;

  @override
  void initState() {
    super.initState();
    _selectedCol = (widget.character.positionX * 4).round().clamp(0, 4);
    _selectedRow = (widget.character.positionY * 4).round().clamp(0, 4);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.pureWhite,
      title: const Text(
        '角色位置 (5x5 网格)',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'V4/V4.5 官方限制 5x5 网格定位 (列 A-E，行 1-5)：',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 8),
            GridView.count(
              crossAxisCount: 5,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.25,
              children: [
                for (var row = 0; row < 5; row++)
                  for (var col = 0; col < 5; col++)
                    _GridCell(
                      label:
                          '${String.fromCharCode('A'.codeUnitAt(0) + col)}${row + 1}',
                      selected: _selectedCol == col && _selectedRow == row,
                      onTap: () => setState(() {
                        _selectedCol = col;
                        _selectedRow = row;
                      }),
                    ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.notionBlue,
            foregroundColor: Colors.white,
          ),
          onPressed: () =>
              Navigator.of(context).pop((_selectedCol / 4, _selectedRow / 4)),
          child: const Text('确定'),
        ),
      ],
    );
  }
}

/// 网格单元
class _GridCell extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _GridCell({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          decoration: BoxDecoration(
            color: selected ? AppTheme.notionBlue : AppTheme.surfaceMuted,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected
                  ? AppTheme.notionBlue
                  : AppTheme.border.withValues(alpha: 0.6),
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : AppTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
