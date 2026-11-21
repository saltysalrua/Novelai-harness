import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderEditable;
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/app_segmented_controls.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/app_tool_chip.dart';
import '../../../core/widgets/app_transitions.dart';
import '../../../core/widgets/overlay_anchor.dart';
import '../../../../data/models/novelai_models.dart';
import '../../../../data/models/prompt_library_models.dart';
import '../../../../data/services/prompt_image_probe.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../core/context_l10n.dart';
import '../view_models/studio_view_model.dart';
import 'character_card_item.dart';
import 'fixed_affixes_panel.dart';
import 'prompt_combo_edit_dialog.dart';

String _genderLabel(AppLocalizations l10n, NaiCharacterGender gender) =>
    switch (gender) {
      NaiCharacterGender.female => l10n.charPromptGenderFemale,
      NaiCharacterGender.male => l10n.charPromptGenderMale,
      NaiCharacterGender.other => l10n.charPromptGenderOther,
    };

/// 判断指针落点是否命中可编辑文本 (多角色/固定词缀输入框等)
bool _pointerDownHitsEditableText(PointerDownEvent event) {
  final result = HitTestResult();
  WidgetsBinding.instance.hitTestInView(result, event.position, event.viewId);
  return result.path.any((entry) => entry.target is RenderEditable);
}

/// 甲板滑动切页专用横向拖拽识别器。
///
/// 覆写 [addPointer]：
/// 1. 指针落点命中可编辑文本 (RenderEditable) 时直接不加入手势竞技场，
///    鼠标在输入框内框选文本完全交给输入框自身处理，杜绝「拖选文字被抢成滑动切页」；
/// 2. 可选提供 [canAcceptPointer]（窄屏下限制仅顶部切换头响应，避免与外层 PageView 横滑冲突）。
class _DeckSwipeRecognizer extends HorizontalDragGestureRecognizer {
  bool Function(Offset globalPosition)? canAcceptPointer;

  @override
  void addPointer(PointerDownEvent event) {
    if (_pointerDownHitsEditableText(event)) return;
    if (canAcceptPointer != null && !canAcceptPointer!(event.position)) {
      return;
    }
    super.addPointer(event);
  }
}

/// 提示词扩展甲板：将多角色提示词 (Character Prompts) 与固定词缀 (Fixed Affixes)
/// 合并为同一个支持左右手势滑动与点击切换的一体化卡片容器。
/// 顶部为全宽自适应分段指示栏，下层为流式自适应工具栏，彻底消除窄屏下的像素溢出与文字截断。
class PromptExtensionDeck extends StatefulWidget {
  final StudioViewModel viewModel;
  final TextEditingController prefixController;
  final TextEditingController suffixController;

  const PromptExtensionDeck({
    super.key,
    required this.viewModel,
    required this.prefixController,
    required this.suffixController,
  });

  @override
  State<PromptExtensionDeck> createState() => _PromptExtensionDeckState();
}

class _PromptExtensionDeckState extends State<PromptExtensionDeck> {
  int _activeTabIndex = 0; // 0: Character Prompts, 1: Fixed Affixes
  double _horizontalDragAccumulated = 0;

  @override
  void initState() {
    super.initState();
    _activeTabIndex = widget.viewModel.deckActiveTab;
  }

  @override
  void didUpdateWidget(covariant PromptExtensionDeck oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_activeTabIndex != widget.viewModel.deckActiveTab) {
      _activeTabIndex = widget.viewModel.deckActiveTab;
    }
  }

  void _switchTab(int index) {
    if (_activeTabIndex == index) return;
    setState(() {
      _activeTabIndex = index;
    });
    widget.viewModel.setDeckActiveTab(index);
  }

  /// 横向滑动切页：速度优先，位移回退兼容慢速拖拽
  void _handleSwipeEnd(DragEndDetails details) {
    final vx = details.primaryVelocity ?? 0;
    if ((vx < -80 || _horizontalDragAccumulated < -30) &&
        _activeTabIndex == 0) {
      // 向左滑 -> 切换到 Fixed Affixes
      _switchTab(1);
    } else if ((vx > 80 || _horizontalDragAccumulated > 30) &&
        _activeTabIndex == 1) {
      // 向右滑 -> 切换到 Character Prompts
      _switchTab(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final viewModel = widget.viewModel;
    final params = viewModel.params;
    final characters = params.characterPrompts;
    final limit = viewModel.characterPromptLimit;
    final supported = limit > 0;
    final isFull = viewModel.isCharacterPromptFull;
    final isAffixesEnabled = params.applyFixedPrompts;
    final isNarrow = MediaQuery.sizeOf(context).width < 900;

    return RawGestureDetector(
      key: const ValueKey('deck_swipe_detector'),
      behavior: HitTestBehavior.translucent,
      gestures: <Type, GestureRecognizerFactory>{
        _DeckSwipeRecognizer:
            GestureRecognizerFactoryWithHandlers<_DeckSwipeRecognizer>(
              () => _DeckSwipeRecognizer(),
              (recognizer) {
                recognizer
                  ..canAcceptPointer = isNarrow
                      ? (globalPos) {
                          final box = context.findRenderObject() as RenderBox?;
                          if (box == null || !box.hasSize) return true;
                          return box.globalToLocal(globalPos).dy <= 44.0;
                        }
                      : null
                  ..onStart = (_) {
                    _horizontalDragAccumulated = 0;
                  }
                  ..onUpdate = (d) {
                    _horizontalDragAccumulated += d.delta.dx;
                  }
                  ..onEnd = _handleSwipeEnd;
              },
            ),
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. 顶部全宽分段指示栏 (复用 AppSegmentedCardBar，100% 宽度均分)
          AppSegmentedCardBar<int>(
            expand: true,
            selectedValue: _activeTabIndex,
            onValueChanged: _switchTab,
            items: [
              AppSegmentedItem<int>(
                value: 0,
                label: l10n.charPromptDeckTabCharacter,
                badgeLabel: characters.isNotEmpty
                    ? '${characters.length}/$limit'
                    : null,
              ),
              AppSegmentedItem<int>(
                value: 1,
                label: l10n.charPromptDeckTabAffixes,
                badgeLabel: isAffixesEnabled ? l10n.charPromptEnabled : null,
              ),
            ],
          ),

          const SizedBox(height: 8),

          // 2. 二级动态操作栏 (流式防溢出布局)
          AnimatedSwitcher(
            duration: AppMotion.resolveDuration(
              context,
              AppMotionDurations.quick,
            ),
            switchInCurve: AppMotionCurves.smoothOut,
            switchOutCurve: AppMotionCurves.smoothOut,
            child: _activeTabIndex == 0
                ? _buildCharacterPromptsToolbar(
                    viewModel: viewModel,
                    characters: characters,
                    supported: supported,
                    isFull: isFull,
                    params: params,
                    l10n: l10n,
                  )
                : _buildFixedAffixesToolbar(
                    viewModel: viewModel,
                    isAffixesEnabled: isAffixesEnabled,
                    params: params,
                  ),
          ),

          const SizedBox(height: 10),

          // 3. 左右滑动切换的内容区 (平滑过渡动效)
          AppPageSideBySide(
            index: _activeTabIndex,
            duration: AppMotionDurations.fast,
            curve: AppMotionCurves.smoothOut,
            slideDistance: AppMotionDistances.base,
            enableBlur: false,
            child: KeyedSubtree(
              key: ValueKey<int>(_activeTabIndex),
              child: _activeTabIndex == 0
                  ? _buildCharacterPromptsContent(viewModel, l10n)
                  : _buildFixedAffixesContent(viewModel),
            ),
          ),
        ],
      ),
    );
  }

  /// 角色提示词二级操作工具栏 (紧凑双选胶囊 + 添加角色按钮，流式排版永不溢出)
  Widget _buildCharacterPromptsToolbar({
    required StudioViewModel viewModel,
    required List<NaiCharacterPrompt> characters,
    required bool supported,
    required bool isFull,
    required NaiGenerationParams params,
    required AppLocalizations l10n,
  }) {
    final addButton = _buildAddCharacterButtons(viewModel, supported, isFull);
    if (characters.isEmpty) {
      return KeyedSubtree(
        key: const ValueKey('char_toolbar'),
        child: Align(alignment: Alignment.centerRight, child: addButton),
      );
    }

    return KeyedSubtree(
      key: const ValueKey('char_toolbar'),
      child: SizedBox(
        width: double.infinity,
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            AppSegmentedCardBar<bool>(
              items: [
                AppSegmentedItem(
                  value: true,
                  label: l10n.charPromptPositionAi,
                  icon: Icons.auto_awesome_rounded,
                ),
                AppSegmentedItem(
                  value: false,
                  label: l10n.charPromptPositionCustom,
                  icon: Icons.open_with_rounded,
                ),
              ],
              selectedValue: params.characterAiPosition,
              fontSize: 12,
              iconSize: 13,
              itemPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 4,
              ),
              onValueChanged: (isAi) => viewModel.setCharacterAiPosition(isAi),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _CanvasEditDeckButton(
                  isCanvasEditing: viewModel.isEditingCharacterPositions,
                  onTap: () => viewModel.setEditingCharacterPositions(
                    !viewModel.isEditingCharacterPositions,
                  ),
                ),
                const SizedBox(width: 6),
                addButton,
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 添加角色入口：合并官方三预设 (女/男/其他) 为单个下拉选项按钮，禁用时降级为上限芯片
  Widget _buildAddCharacterButtons(
    StudioViewModel viewModel,
    bool supported,
    bool isFull,
  ) {
    final enabled = supported && !isFull;
    if (!enabled) {
      return const _AddCharacterLimitChip();
    }
    return _AddCharacterMenuButton(
      onSelected: (gender) => viewModel.addCharacterPrompt(gender: gender),
    );
  }

  /// 固定词缀二级操作工具栏 (画风库一键填入 / 存为画风 / 启用开关)
  Widget _buildFixedAffixesToolbar({
    required StudioViewModel viewModel,
    required bool isAffixesEnabled,
    required NaiGenerationParams params,
  }) {
    final colors = context.colors;
    final l10n = context.l10n;
    return KeyedSubtree(
      key: const ValueKey('affix_toolbar'),
      child: SizedBox(
        width: double.infinity,
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _StyleLibraryPickerButton(viewModel: viewModel),
                const SizedBox(width: 6),
                AppToolChip(
                  icon: Icons.bookmark_add_outlined,
                  label: l10n.affixSaveStyleLabel,
                  tooltip: l10n.affixSaveStyleTooltip,
                  height: 28,
                  radius: 6,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  unselectedBackgroundColor: colors.cardBackground,
                  borderColor: colors.borderDefault,
                  onTap: () => _openSaveStyleDialog(viewModel),
                ),
              ],
            ),
            AppToolChip(
              icon: isAffixesEnabled ? Icons.check_rounded : Icons.close_rounded,
              label:
                  '${l10n.charPromptDeckTabAffixes}: ${isAffixesEnabled ? l10n.charPromptEnabled : l10n.charPromptDisabled}',
              isSelected: isAffixesEnabled,
              height: 28,
              radius: 6,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              unselectedBackgroundColor: colors.cardBackground,
              borderColor: colors.borderDefault,
              onTap: () => viewModel.updateParams(
                params.copyWith(applyFixedPrompts: !isAffixesEnabled),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openSaveStyleDialog(StudioViewModel viewModel) {
    final l10n = context.l10n;
    final params = viewModel.params;
    final prefix = (params.prefixPrompt ?? '').trim();
    final suffix = (params.suffixPrompt ?? '').trim();
    final negative = params.negativePrompt.trim();
    if (prefix.isEmpty && suffix.isEmpty && negative.isEmpty) {
      showAppToast(
        context,
        message: l10n.affixSaveStyleEmptyNotice,
        tone: AppToastTone.info,
        duration: const Duration(milliseconds: 1400),
      );
      return;
    }
    final now = DateTime.now();
    PromptComboEditDialog.show(
      context,
      viewModel: viewModel,
      initialEntry: PromptComboEntry(
        id: '',
        title: '',
        category: PromptComboCategories.style,
        prefixPrompt: prefix,
        suffixPrompt: suffix,
        negativePrompt: negative,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  /// 角色提示词内容视图
  Widget _buildCharacterPromptsContent(
    StudioViewModel viewModel,
    AppLocalizations l10n,
  ) {
    final colors = context.colors;
    final params = viewModel.params;
    final characters = params.characterPrompts;
    final limit = viewModel.characterPromptLimit;
    final supported = limit > 0;

    if (!supported) {
      return AppCard(
        padding: const EdgeInsets.all(12),
        child: Text(
          l10n.charPromptUnsupportedModel,
          style: TextStyle(
            fontSize: 12,
            color: colors.warning.withValues(alpha: 0.9),
          ),
        ),
      );
    }

    if (characters.isEmpty) {
      return AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        child: AppEmptyState(
          icon: Icons.people_outline_rounded,
          title: l10n.charPromptEmptyTitle,
          description: l10n.charPromptEmptyDescription,
          isCompact: true,
          iconSize: 28,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < characters.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          CharacterCardItem(
            key: ValueKey(characters[i].id),
            character: characters[i],
            index: i,
            enabledTotal: characters.where((c) => c.enabled).length,
            viewModel: viewModel,
          ),
        ],
      ],
    );
  }

  /// 固定词缀内容视图
  Widget _buildFixedAffixesContent(StudioViewModel viewModel) {
    return FixedAffixesCardContent(
      viewModel: viewModel,
      prefixController: widget.prefixController,
      suffixController: widget.suffixController,
    );
  }
}

/// 画板位置编辑统一芯片按钮 (与其它工具栏芯片等高同圆角)
class _CanvasEditDeckButton extends StatelessWidget {
  final bool isCanvasEditing;
  final VoidCallback onTap;

  const _CanvasEditDeckButton({
    required this.isCanvasEditing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    return AppToolChip(
      icon: Icons.control_camera_rounded,
      label: isCanvasEditing
          ? l10n.charPromptCanvasEditing
          : l10n.charPromptCanvasEdit,
      isSelected: isCanvasEditing,
      height: 28,
      radius: 6,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      unselectedBackgroundColor: colors.cardBackground,
      borderColor: colors.borderDefault,
      tooltip: isCanvasEditing
          ? l10n.charPromptExitCanvasEditTooltip
          : l10n.charPromptEnterCanvasEditTooltip,
      onTap: onTap,
    );
  }
}

/// 合并后的添加角色下拉选项按钮 (点击弹出 女 / 男 / 其他 预设菜单)
class _AddCharacterMenuButton extends StatefulWidget {
  final ValueChanged<NaiCharacterGender> onSelected;

  const _AddCharacterMenuButton({required this.onSelected});

  @override
  State<_AddCharacterMenuButton> createState() =>
      _AddCharacterMenuButtonState();
}

class _AddCharacterMenuButtonState extends State<_AddCharacterMenuButton> {
  bool _isOpen = false;

  static Color _genderColor(NaiCharacterGender gender) => switch (gender) {
    NaiCharacterGender.female => const Color(0xFFEC4899),
    NaiCharacterGender.male => const Color(0xFF3B82F6),
    NaiCharacterGender.other => const Color(0xFF8B5CF6),
  };

  static IconData _genderIcon(NaiCharacterGender gender) => switch (gender) {
    NaiCharacterGender.female => Icons.female_rounded,
    NaiCharacterGender.male => Icons.male_rounded,
    NaiCharacterGender.other => Icons.transgender_rounded,
  };

  static String _genderTooltip(
    AppLocalizations l10n,
    NaiCharacterGender gender,
  ) => switch (gender) {
    NaiCharacterGender.female => l10n.charPromptAddFemaleTooltip,
    NaiCharacterGender.male => l10n.charPromptAddMaleTooltip,
    NaiCharacterGender.other => l10n.charPromptAddOtherTooltip,
  };

  Future<void> _openMenu(BuildContext triggerContext) async {
    final l10n = context.l10n;
    final renderBox = triggerContext.findRenderObject() as RenderBox?;
    final triggerWidth = (renderBox != null && renderBox.hasSize)
        ? renderBox.size.width
        : 120.0;
    final menuMinWidth = math.max(triggerWidth, 120.0);
    final menuMaxWidth = math.max(triggerWidth, 180.0);

    setState(() => _isOpen = true);
    try {
      final selected = await showAnchoredPopover<NaiCharacterGender>(
        context: triggerContext,
        preferAbove: false,
        gap: 4,
        minWidth: menuMinWidth,
        maxWidth: menuMaxWidth,
        builder: (popoverContext) {
          final colors = popoverContext.colors;
          return Padding(
            padding: const EdgeInsets.all(6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final gender in NaiCharacterGender.values)
                  Tooltip(
                    message: _genderTooltip(l10n, gender),
                    waitDuration: AppMotionDurations.verySlow,
                    child: Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => Navigator.of(popoverContext).pop(gender),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _genderIcon(gender),
                                size: 15,
                                color: _genderColor(gender),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _genderLabel(l10n, gender),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: colors.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      );
      if (selected != null) {
        widget.onSelected(selected);
      }
    } finally {
      if (mounted) {
        setState(() => _isOpen = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final chevronDuration = AppMotion.resolveDuration(
      context,
      AppMotionDurations.dropdownOpen,
    );

    return Material(
      color: colors.cardBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: colors.borderDefault),
      ),
      clipBehavior: Clip.antiAlias,
      child: Builder(
        builder: (triggerContext) => InkWell(
          onTap: () => _openMenu(triggerContext),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.person_add_alt_1_rounded,
                  size: 14,
                  color: colors.textMuted,
                ),
                const SizedBox(width: 4),
                Text(
                  l10n.charPromptAddCharacter,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(width: 2),
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(end: _isOpen ? -1.0 : 1.0),
                  duration: chevronDuration,
                  curve: AppMotionCurves.smoothOut,
                  builder: (context, scaleY, child) {
                    return Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.diagonal3Values(1.0, scaleY, 1.0),
                      child: child,
                    );
                  },
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 16,
                    color: colors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 不支持或已达上限时的禁用芯片 (与添加角色按钮同尺寸同圆角)
class _AddCharacterLimitChip extends StatelessWidget {
  const _AddCharacterLimitChip();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: colors.mutedBackground,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.borderDefault),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.person_add_alt_rounded, size: 14, color: colors.textMuted),
          const SizedBox(width: 4),
          Text(
            l10n.charPromptLimitReached,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: colors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// 词库画风快速选择下拉按钮 (点击弹出「风格」条目浮层，一键填入前后缀与负面词)
class _StyleLibraryPickerButton extends StatelessWidget {
  final StudioViewModel viewModel;

  const _StyleLibraryPickerButton({required this.viewModel});

  Future<void> _openPopover(BuildContext triggerContext) async {
    final l10n = triggerContext.l10n;
    final styleEntries = viewModel.promptLibraryEntries
        .where((e) => e.isStyle)
        .toList(growable: false);

    final selected = await showAnchoredPopover<PromptComboEntry>(
      context: triggerContext,
      preferAbove: false,
      gap: 4,
      minWidth: 220,
      maxWidth: 320,
      maxHeight: 340,
      builder: (popoverContext) {
        final colors = popoverContext.colors;
        if (styleEntries.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            child: Text(
              l10n.affixStylePresetsEmpty,
              style: TextStyle(fontSize: 12, color: colors.textMuted),
            ),
          );
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final entry in styleEntries)
                _StylePresetPopoverItem(
                  entry: entry,
                  onTap: () => Navigator.of(popoverContext).pop(entry),
                ),
            ],
          ),
        );
      },
    );

    if (selected != null && triggerContext.mounted) {
      viewModel.applyPromptCombo(selected, asStyle: true, replace: true);
      showAppToast(
        triggerContext,
        message: l10n.affixAppliedStyleNotice(selected.title),
        tone: AppToastTone.success,
        duration: const Duration(milliseconds: 1400),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    return ListenableBuilder(
      listenable: viewModel.promptLibraryNotifier,
      builder: (context, _) {
        final styleCount = viewModel.promptLibraryEntries
            .where((e) => e.isStyle)
            .length;
        final label = styleCount > 0
            ? '${l10n.affixStylePresetsLabel} ($styleCount)'
            : l10n.affixStylePresetsLabel;
        return Builder(
          builder: (triggerContext) => AppToolChip(
            icon: Icons.palette_outlined,
            label: label,
            tooltip: l10n.affixStylePresetsTooltip,
            height: 28,
            radius: 6,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            unselectedBackgroundColor: colors.cardBackground,
            borderColor: colors.borderDefault,
            onTap: () => _openPopover(triggerContext),
          ),
        );
      },
    );
  }
}

class _StylePresetPopoverItem extends StatelessWidget {
  final PromptComboEntry entry;
  final VoidCallback onTap;

  const _StylePresetPopoverItem({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final rawPath = entry.previewImagePath?.trim();
    final hasThumb =
        rawPath != null &&
        rawPath.isNotEmpty &&
        !PromptImageProbe.isKnownMissing(rawPath);
    final summary = entry.displayPromptSummary.replaceAll('\n', ' · ');

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            children: [
              if (hasThumb) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: Image(
                      image: ResizeImage(
                        FileImage(File(rawPath)),
                        width: 64,
                        height: 64,
                        policy: ResizeImagePolicy.fit,
                      ),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          Icon(Icons.palette_outlined, size: 16, color: colors.textMuted),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ] else ...[
                Icon(Icons.palette_outlined, size: 15, color: colors.primary),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    if (summary.isNotEmpty)
                      Text(
                        summary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: colors.textMuted),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
