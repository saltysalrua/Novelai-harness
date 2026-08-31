import 'package:flutter/gestures.dart' show GestureBinding, PointerScrollEvent;
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../../data/models/novelai_models.dart';
import '../view_models/studio_view_model.dart';
import 'canvas_overlays.dart';

class CharacterWheelCycleListener extends StatefulWidget {
  final StudioViewModel viewModel;
  final Widget child;
  final Duration throttle;

  const CharacterWheelCycleListener({
    super.key,
    required this.viewModel,
    required this.child,
    this.throttle = Duration.zero,
  });

  @override
  State<CharacterWheelCycleListener> createState() =>
      _CharacterWheelCycleListenerState();
}

class _CharacterWheelCycleListenerState
    extends State<CharacterWheelCycleListener> {
  DateTime? _lastSwitch;

  @override
  Widget build(BuildContext context) {
    final viewModel = widget.viewModel;
    // 非编辑模式或仅单个角色时不拦截滚轮；依赖祖先随 viewModel 通知重建
    // 来切换挂载状态，避免常驻 Listener 抢走底层滚动容器的信号注册权
    if (!viewModel.isEditingCharacterPositions ||
        viewModel.params.characterPrompts.length <= 1) {
      return widget.child;
    }
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerSignal: (signal) {
        if (signal is! PointerScrollEvent) return;
        GestureBinding.instance.pointerSignalResolver.register(signal, (_) {
          final now = DateTime.now();
          if (widget.throttle != Duration.zero &&
              _lastSwitch != null &&
              now.difference(_lastSwitch!) < widget.throttle) {
            return;
          }
          _lastSwitch = now;
          if (signal.scrollDelta.dy > 0) {
            viewModel.cycleSelectedCharacter(1);
          } else if (signal.scrollDelta.dy < 0) {
            viewModel.cycleSelectedCharacter(-1);
          }
        });
      },
      child: widget.child,
    );
  }
}

/// 性别推导与显示信息
typedef CharacterChipDisplay = ({
  IconData? genderIcon,
  String label,
  Color color,
});

CharacterChipDisplay resolveCharacterChipDisplay(
  NaiCharacterPrompt character,
  int index,
) {
  final prompt = character.prompt.toLowerCase();
  final tags = prompt
      .split(',')
      .map((t) => t.trim())
      .where((t) => t.isNotEmpty)
      .toList();

  IconData? genderIcon;
  Color color = const Color(0xFF8B5CF6); // 默认紫色 (other)

  final isFemale = tags.any(
    (t) =>
        t == '1girl' ||
        t == 'girl' ||
        t == 'female' ||
        t == 'woman' ||
        t.contains('girl'),
  );
  final isMale = tags.any(
    (t) =>
        t == '1boy' ||
        t == 'boy' ||
        t == 'male' ||
        t == 'man' ||
        t.contains('boy'),
  );

  if (isFemale) {
    genderIcon = Icons.female_rounded;
    color = const Color(0xFFEC4899); // 粉色
  } else if (isMale) {
    genderIcon = Icons.male_rounded;
    color = const Color(0xFF3B82F6); // 蓝色
  }

  String label = character.name.trim();
  if (label.isEmpty || RegExp(r'^角色 \d+$').hasMatch(label)) {
    if (tags.isNotEmpty) {
      label = tags.first;
      if (genderIcon != null && tags.length > 1) {
        label = tags[1];
      }
    }
  }

  return (genderIcon: genderIcon, label: label, color: color);
}

/// 角色位置交互覆盖层 (直接叠加在图像或临时占位卡片之上)
///
/// 键盘交互 (方向键循环切换 / ESC 退出) 统一由 StudioView 的全局

// ==================== Notion 风格画板悬浮操作栏 ====================

/// 角色或水印位置编辑中悬浮的控制栏 (顶部快捷切换/锚点 + 右下角完成编辑微胶囊)
class CanvasPositionFloatingControls extends StatelessWidget {
  final StudioViewModel viewModel;

  const CanvasPositionFloatingControls({super.key, required this.viewModel});

  Widget _buildWatermarkFloatingControls(BuildContext context) {
    return Stack(
      children: [
        // 右下角：完成编辑微胶囊
        Positioned(
          bottom: 18,
          right: 18,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => viewModel.setEditingWatermarkPosition(false),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                height: 38,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.notionBlue,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.notionBlue.withValues(alpha: 0.25),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_rounded, size: 16, color: Colors.white),
                    SizedBox(width: 6),
                    Text(
                      '完成编辑',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (viewModel.isEditingWatermarkPosition) {
      return _buildWatermarkFloatingControls(context);
    }

    final params = viewModel.params;
    final characters = params.characterPrompts;
    final selectedId =
        viewModel.selectedCharacterId ??
        (characters.isNotEmpty ? characters.first.id : null);

    return Stack(
      children: [
        // 1. 顶部中央：多角色切换芯片条 (仅在有角色时展示，悬停滚轮可循环切换)
        if (characters.isNotEmpty)
          Positioned(
            top: 14,
            left: 0,
            right: 0,
            child: Center(
              child: CharacterWheelCycleListener(
                viewModel: viewModel,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 5,
                  ),
                  decoration: canvasBadgeDecoration(),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < characters.length; i++) ...[
                        if (i > 0) const SizedBox(width: 4),
                        _FloatingCharacterChip(
                          character: characters[i],
                          index: i,
                          isSelected: characters[i].id == selectedId,
                          onTap: () =>
                              viewModel.selectCharacterId(characters[i].id),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),

        // 2. 右下角：Notion 风格完成编辑胶囊
        Positioned(
          bottom: 18,
          right: 18,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => viewModel.setEditingCharacterPositions(false),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                height: 38,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.notionBlue,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.notionBlue.withValues(alpha: 0.25),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_rounded, size: 16, color: Colors.white),
                    SizedBox(width: 6),
                    Text(
                      '完成编辑',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FloatingCharacterChip extends StatelessWidget {
  final NaiCharacterPrompt character;
  final int index;
  final bool isSelected;
  final VoidCallback onTap;

  const _FloatingCharacterChip({
    required this.character,
    required this.index,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final display = resolveCharacterChipDisplay(character, index);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.notionBlue : AppTheme.surfaceMuted,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${index + 1}',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: isSelected ? Colors.white : AppTheme.textPrimary,
              ),
            ),
            if (display.genderIcon != null) ...[
              const SizedBox(width: 3),
              Icon(
                display.genderIcon,
                size: 13,
                color: isSelected ? Colors.white : display.color,
              ),
            ],
            if (display.label.isNotEmpty) ...[
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 90),
                child: Text(
                  display.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isSelected
                        ? FontWeight.w600
                        : FontWeight.normal,
                    color: isSelected ? Colors.white : AppTheme.textPrimary,
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
