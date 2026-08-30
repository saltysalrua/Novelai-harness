import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../../data/models/novelai_models.dart';
import '../view_models/studio_view_model.dart';
import 'character_card_item.dart';
import 'fixed_affixes_panel.dart';

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

  void _switchTab(int index) {
    if (_activeTabIndex == index) return;
    setState(() {
      _slideDirection = index > _activeTabIndex ? 1 : -1;
      _activeTabIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
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
              color: AppTheme.surfaceMuted,
              borderRadius: BorderRadius.circular(AppTheme.radiusButton),
              border: Border.all(color: AppTheme.borderSubtle),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _DeckSegmentTab(
                    label: 'Character Prompts',
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
                    label: 'Fixed Affixes',
                    badge: isAffixesEnabled ? '已启用' : null,
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
                  )
                : _buildFixedAffixesToolbar(
                    viewModel: viewModel,
                    isAffixesEnabled: isAffixesEnabled,
                    params: params,
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
                  ? _buildCharacterPromptsContent(viewModel)
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
  }) {
    return KeyedSubtree(
      key: const ValueKey('char_toolbar'),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (characters.isNotEmpty)
            _DualPositionToggle(
              isAiPosition: params.characterAiPosition,
              onChanged: (isAi) => viewModel.setCharacterAiPosition(isAi),
              isCanvasEditing: viewModel.isEditingCharacterPositions,
              onToggleCanvasEdit: () => viewModel.setEditingCharacterPositions(
                !viewModel.isEditingCharacterPositions,
              ),
            )
          else
            const Text(
              '独立角色物理隔离',
              style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
            ),
          _AddCharacterDeckButton(
            enabled: supported && !isFull,
            onTap: supported && !isFull
                ? () => viewModel.addCharacterPrompt()
                : null,
          ),
        ],
      ),
    );
  }

  /// 固定词缀二级操作工具栏 (左侧说明 + 右侧 Switch，流式排版永不溢出)
  Widget _buildFixedAffixesToolbar({
    required StudioViewModel viewModel,
    required bool isAffixesEnabled,
    required NaiGenerationParams params,
  }) {
    return KeyedSubtree(
      key: const ValueKey('affix_toolbar'),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text(
            '全局固定前置与后置词缀',
            style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
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
  Widget _buildCharacterPromptsContent(StudioViewModel viewModel) {
    final params = viewModel.params;
    final characters = params.characterPrompts;
    final limit = viewModel.characterPromptLimit;
    final supported = limit > 0;

    if (!supported) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.pureWhite,
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          border: Border.all(color: AppTheme.border),
        ),
        child: Text(
          '当前模型不支持角色提示词 (仅 V4 及以上模型生效)，下方配置将保留但不会参与生成。',
          style: TextStyle(
            fontSize: 12,
            color: AppTheme.warning.withValues(alpha: 0.9),
          ),
        ),
      );
    }

    if (characters.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        decoration: BoxDecoration(
          color: AppTheme.pureWhite,
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          children: [
            const Icon(
              Icons.people_outline_rounded,
              size: 28,
              color: AppTheme.textMuted,
            ),
            const SizedBox(height: 6),
            const Text(
              '暂无独立角色提示词',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '点击右上角「+ 添加角色」即可开启多角色防串色隔离生图',
              style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
              textAlign: TextAlign.center,
            ),
          ],
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusButton - 2),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5.5),
        decoration: BoxDecoration(
          color: isActive ? AppTheme.pureWhite : Colors.transparent,
          borderRadius: BorderRadius.circular(AppTheme.radiusButton - 2),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
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
                    color: isActive
                        ? AppTheme.textPrimary
                        : AppTheme.textSecondary,
                  ),
                ),
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 4.5,
                  vertical: 1,
                ),
                decoration: BoxDecoration(
                  color: badgeIsActive
                      ? AppTheme.skyTint
                      : AppTheme.surfaceMuted,
                  borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                  border: Border.all(
                    color: badgeIsActive
                        ? AppTheme.notionBlue.withValues(alpha: 0.3)
                        : AppTheme.borderSubtle,
                    width: 0.5,
                  ),
                ),
                child: Text(
                  badge!,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: badgeIsActive
                        ? AppTheme.notionBlue
                        : AppTheme.textMuted,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 一体化定位模式双选胶囊 (AI 自动 ↔ 自定义 + 画板编辑)
class _DualPositionToggle extends StatelessWidget {
  final bool isAiPosition;
  final ValueChanged<bool> onChanged;
  final bool isCanvasEditing;
  final VoidCallback onToggleCanvasEdit;

  const _DualPositionToggle({
    required this.isAiPosition,
    required this.onChanged,
    required this.isCanvasEditing,
    required this.onToggleCanvasEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PositionToggleOption(
            label: 'AI 自动',
            icon: Icons.auto_awesome_rounded,
            isActive: isAiPosition,
            onTap: () => onChanged(true),
          ),
          const SizedBox(width: 2),
          _PositionToggleOption(
            label: '自定义',
            icon: Icons.open_with_rounded,
            isActive: !isAiPosition,
            onTap: () => onChanged(false),
          ),
          const SizedBox(width: 2),
          Tooltip(
            message: isCanvasEditing ? '退出画板位置编辑' : '在中间画板编辑角色位置',
            child: InkWell(
              onTap: onToggleCanvasEdit,
              borderRadius: BorderRadius.circular(AppTheme.radiusPill),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(
                  horizontal: 7,
                  vertical: 3.5,
                ),
                decoration: BoxDecoration(
                  color: isCanvasEditing
                      ? AppTheme.notionBlue
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.control_camera_rounded,
                      size: 11.5,
                      color: isCanvasEditing
                          ? Colors.white
                          : AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 3.5),
                    Text(
                      isCanvasEditing ? '编辑中' : '画板编辑',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: isCanvasEditing
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: isCanvasEditing
                            ? Colors.white
                            : AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PositionToggleOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  const _PositionToggleOption({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
        decoration: BoxDecoration(
          color: isActive ? AppTheme.pureWhite : Colors.transparent,
          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 11.5,
              color: isActive ? AppTheme.notionBlue : AppTheme.textMuted,
            ),
            const SizedBox(width: 3.5),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive ? AppTheme.notionBlue : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 添加角色胶囊按钮
class _AddCharacterDeckButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback? onTap;

  const _AddCharacterDeckButton({required this.enabled, this.onTap});

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
                fontSize: 11,
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

/// 词缀总开关控件
class _AffixToggleSwitch extends StatelessWidget {
  final bool isEnabled;
  final ValueChanged<bool> onChanged;

  const _AffixToggleSwitch({required this.isEnabled, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          isEnabled ? '已启用' : '已停用',
          style: TextStyle(
            fontSize: 11.5,
            color: isEnabled ? AppTheme.notionBlue : AppTheme.textMuted,
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
              activeTrackColor: AppTheme.notionBlue,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}
