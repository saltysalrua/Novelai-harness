import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_badge.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/app_segmented_controls.dart';
import '../../../../data/models/novelai_models.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../core/context_l10n.dart';
import '../view_models/studio_view_model.dart';
import 'character_card_item.dart';
import 'fixed_affixes_panel.dart';

String _genderLabel(AppLocalizations l10n, NaiCharacterGender gender) =>
    switch (gender) {
      NaiCharacterGender.female => l10n.charPromptGenderFemale,
      NaiCharacterGender.male => l10n.charPromptGenderMale,
      NaiCharacterGender.other => l10n.charPromptGenderOther,
    };

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
  int _slideDirection = 1; // 1: 从右向左滑动 (切换至右侧页), -1: 从左向右滑动
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
      _slideDirection = index > _activeTabIndex ? 1 : -1;
      _activeTabIndex = index;
    });
    widget.viewModel.setDeckActiveTab(index);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final viewModel = widget.viewModel;
    final params = viewModel.params;
    final characters = params.characterPrompts;
    final limit = viewModel.characterPromptLimit;
    final supported = limit > 0;
    final isFull = viewModel.isCharacterPromptFull;
    final isAffixesEnabled = params.applyFixedPrompts;

    return GestureDetector(
      key: const ValueKey('deck_swipe_detector'),
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) => _horizontalDragAccumulated = 0,
      onHorizontalDragUpdate: (d) => _horizontalDragAccumulated += d.delta.dx,
      onHorizontalDragEnd: (details) {
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
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. 顶部全宽分段指示栏 (100% 宽度均分，自适应缩放无截断)
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: colors.mutedBackground,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: colors.borderSubtle),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _DeckSegmentTab(
                    label: l10n.charPromptDeckTabCharacter,
                    badge: characters.isNotEmpty
                        ? '${characters.length}/$limit'
                        : null,
                    isActive: _activeTabIndex == 0,
                    onTap: () => _switchTab(0),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _DeckSegmentTab(
                    label: l10n.charPromptDeckTabAffixes,
                    badge: isAffixesEnabled ? l10n.charPromptEnabled : null,
                    badgeIsActive: isAffixesEnabled,
                    isActive: _activeTabIndex == 1,
                    onTap: () => _switchTab(1),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // 2. 二级动态操作栏 (流式防溢出布局)
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
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
                    l10n: l10n,
                  ),
          ),

          const SizedBox(height: 10),

          // 3. 左右滑动切换的内容区 (平滑过渡动效)
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              final isTarget = child.key == ValueKey<int>(_activeTabIndex);
              final startOffset = isTarget
                  ? Offset(_slideDirection * 0.25, 0.0)
                  : Offset(-_slideDirection * 0.25, 0.0);
              return SlideTransition(
                position: Tween<Offset>(
                  begin: startOffset,
                  end: Offset.zero,
                ).animate(animation),
                child: FadeTransition(opacity: animation, child: child),
              );
            },
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
    return KeyedSubtree(
      key: const ValueKey('char_toolbar'),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (characters.isNotEmpty) ...[
            AppSegmentedPillBar<bool>(
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
              variant: AppPillVariant.soft,
              itemPadding: const EdgeInsets.symmetric(
                horizontal: 7,
                vertical: 3.5,
              ),
              onValueChanged: (isAi) => viewModel.setCharacterAiPosition(isAi),
            ),
            _CanvasEditDeckButton(
              isCanvasEditing: viewModel.isEditingCharacterPositions,
              onTap: () => viewModel.setEditingCharacterPositions(
                !viewModel.isEditingCharacterPositions,
              ),
            ),
          ] else
            Text(
              l10n.charPromptIsolationHint,
              style: TextStyle(fontSize: 12, color: context.colors.textMuted),
            ),
          _buildAddCharacterButtons(viewModel, supported, isFull),
        ],
      ),
    );
  }

  /// 添加角色按钮组：官方三预设 (女/男/其他)，禁用时降级为单个上限胶囊
  Widget _buildAddCharacterButtons(
    StudioViewModel viewModel,
    bool supported,
    bool isFull,
  ) {
    final enabled = supported && !isFull;
    if (!enabled) {
      return const _AddCharacterLimitChip();
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final gender in NaiCharacterGender.values) ...[
          _AddGenderDeckButton(
            gender: gender,
            onTap: () => viewModel.addCharacterPrompt(gender: gender),
          ),
          if (gender != NaiCharacterGender.values.last)
            const SizedBox(width: 4),
        ],
      ],
    );
  }

  /// 固定词缀二级操作工具栏 (左侧说明 + 右侧 Switch，流式排版永不溢出)
  Widget _buildFixedAffixesToolbar({
    required StudioViewModel viewModel,
    required bool isAffixesEnabled,
    required NaiGenerationParams params,
    required AppLocalizations l10n,
  }) {
    return KeyedSubtree(
      key: const ValueKey('affix_toolbar'),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            l10n.promptsAffixesHint,
            style: TextStyle(fontSize: 12, color: context.colors.textMuted),
          ),
          _AffixToggleSwitch(
            isEnabled: isAffixesEnabled,
            onChanged: (val) =>
                viewModel.updateParams(params.copyWith(applyFixedPrompts: val)),
          ),
        ],
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

/// 甲板顶部全宽分段标签 (带自适应缩小，杜绝省略号截断)
class _DeckSegmentTab extends StatelessWidget {
  final String label;
  final String? badge;
  final bool badgeIsActive;
  final bool isActive;
  final VoidCallback onTap;

  const _DeckSegmentTab({
    required this.label,
    this.badge,
    this.badgeIsActive = false,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md - 2),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5.5),
        decoration: BoxDecoration(
          color: isActive ? colors.cardBackground : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.md - 2),
          boxShadow: isActive ? context.shadowSubtle : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    color: isActive ? colors.textPrimary : colors.textSecondary,
                  ),
                ),
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 4),
              AppBadge.pill(
                label: badge!,
                fontSize: 10,
                variant: badgeIsActive
                    ? AppBadgeVariant.primary
                    : AppBadgeVariant.neutral,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 画板位置编辑独立胶囊按钮 (流式排版自适应)
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
    return Tooltip(
      message: isCanvasEditing
          ? l10n.charPromptExitCanvasEditTooltip
          : l10n.charPromptEnterCanvasEditTooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isCanvasEditing ? colors.primary : colors.mutedBackground,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
              color: isCanvasEditing ? colors.primary : colors.borderSubtle,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.control_camera_rounded,
                size: 12,
                color: isCanvasEditing ? Colors.white : colors.textSecondary,
              ),
              const SizedBox(width: 3.5),
              Text(
                isCanvasEditing
                    ? l10n.charPromptCanvasEditing
                    : l10n.charPromptCanvasEdit,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isCanvasEditing
                      ? FontWeight.w700
                      : FontWeight.w500,
                  color: isCanvasEditing ? Colors.white : colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 添加角色胶囊按钮 (官方三预设：女/男/其他，各带性别色)
///
/// 性别专属粉/蓝/紫三色为业务身份色 (跨主题恒定)，非主题语义色，故保留字面值。
class _AddGenderDeckButton extends StatelessWidget {
  final NaiCharacterGender gender;
  final VoidCallback onTap;

  const _AddGenderDeckButton({required this.gender, required this.onTap});

  Color get _color => switch (gender) {
    NaiCharacterGender.female => const Color(0xFFEC4899),
    NaiCharacterGender.male => const Color(0xFF3B82F6),
    NaiCharacterGender.other => const Color(0xFF8B5CF6),
  };

  IconData get _icon => switch (gender) {
    NaiCharacterGender.female => Icons.female_rounded,
    NaiCharacterGender.male => Icons.male_rounded,
    NaiCharacterGender.other => Icons.transgender_rounded,
  };

  String _tooltip(AppLocalizations l10n) => switch (gender) {
    NaiCharacterGender.female => l10n.charPromptAddFemaleTooltip,
    NaiCharacterGender.male => l10n.charPromptAddMaleTooltip,
    NaiCharacterGender.other => l10n.charPromptAddOtherTooltip,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Tooltip(
      message: _tooltip(l10n),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: _color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: _color.withValues(alpha: 0.45)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_icon, size: 13, color: _color),
              const SizedBox(width: 4),
              Text(
                _genderLabel(l10n, gender),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 不支持或已达上限时的禁用胶囊

class _AddCharacterLimitChip extends StatelessWidget {
  const _AddCharacterLimitChip();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: colors.mutedBackground,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: colors.borderDefault),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.person_add_alt_rounded, size: 13, color: colors.textMuted),
          const SizedBox(width: 4),
          Text(
            l10n.charPromptLimitReached,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// 词缀总开关控件
class _AffixToggleSwitch extends StatelessWidget {
  final bool isEnabled;
  final ValueChanged<bool> onChanged;

  const _AffixToggleSwitch({required this.isEnabled, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          isEnabled ? l10n.charPromptEnabled : l10n.charPromptDisabled,
          style: TextStyle(
            fontSize: 12,
            color: isEnabled ? colors.primary : colors.textMuted,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          height: 22,
          width: 38,
          child: FittedBox(
            fit: BoxFit.fill,
            child: Switch(
              value: isEnabled,
              activeTrackColor: colors.primary,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}
