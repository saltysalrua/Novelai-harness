import 'dart:math' as math;
import 'package:flutter/gestures.dart' show GestureBinding, PointerScrollEvent;
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../../data/models/novelai_models.dart';
import '../view_models/studio_view_model.dart';
import 'canvas_overlays.dart';

/// 滚轮循环切换选中角色的监听包装 (仅在角色位置编辑模式下生效)。
///
/// 悬停滚轮即可切换当前选中角色；[throttle] 为节流间隔，避免高频滚轮
/// 一次滚动跨多个角色。芯片条不节流，角色卡片用 140ms 节流。
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
typedef _CharacterChipDisplay = ({
  IconData? genderIcon,
  String label,
  Color color,
});

_CharacterChipDisplay _resolveChipDisplay(
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
/// HardwareKeyboard 处理器负责，本组件只负责指针交互。
class CharacterPositionOverlay extends StatefulWidget {
  final StudioViewModel viewModel;

  const CharacterPositionOverlay({super.key, required this.viewModel});

  @override
  State<CharacterPositionOverlay> createState() =>
      _CharacterPositionOverlayState();
}

class _CharacterPositionOverlayState extends State<CharacterPositionOverlay> {
  String? _draggingId;
  double _dragX = 0.5;
  double _dragY = 0.5;

  @override
  Widget build(BuildContext context) {
    final viewModel = widget.viewModel;
    final params = viewModel.params;
    final characters = params.characterPrompts;
    final selectedId =
        viewModel.selectedCharacterId ??
        (characters.isNotEmpty ? characters.first.id : null);

    return LayoutBuilder(
      builder: (context, constraints) {
        final canvasSize = constraints.biggest;
        if (canvasSize.width <= 0 || canvasSize.height <= 0) {
          return const SizedBox.shrink();
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            // 半透明暗化背景层，保证网格和锚点清晰可辨
            const ColoredBox(color: Color(0x38000000)),

            // 网格与交互层
            if (params.model.supportsFreeCharacterPositioning)
              _buildFreePositionLayer(
                viewModel,
                characters,
                selectedId,
                canvasSize,
              )
            else
              _buildGridPositionLayer(
                viewModel,
                characters,
                selectedId,
                canvasSize,
              ),

            // 自由拖拽时的百分比浮签
            if (params.model.supportsFreeCharacterPositioning &&
                _draggingId != null)
              _buildDragTooltip(canvasSize),
          ],
        );
      },
    );
  }

  // ==================== V4 / V4.5 5x5 网格层 ====================

  Widget _buildGridPositionLayer(
    StudioViewModel viewModel,
    List<NaiCharacterPrompt> characters,
    String? selectedId,
    Size canvasSize,
  ) {
    final enabledCharacters = characters.where((c) => c.enabled).toList();
    final selectedChar = characters.firstWhere(
      (c) => c.id == selectedId,
      orElse: () => characters.isNotEmpty
          ? characters.first
          : const NaiCharacterPrompt(id: '', name: '', prompt: ''),
    );

    final currentX = selectedChar.useCustomPosition
        ? selectedChar.positionX
        : selectedChar
              .resolveCenter(
                enabledCharacters.indexOf(selectedChar).clamp(0, 99),
                enabledCharacters.length,
              )
              .x;
    final currentY = selectedChar.useCustomPosition
        ? selectedChar.positionY
        : selectedChar
              .resolveCenter(
                enabledCharacters.indexOf(selectedChar).clamp(0, 99),
                enabledCharacters.length,
              )
              .y;

    final selectedCol = (currentX * 4).round().clamp(0, 4);
    final selectedRow = (currentY * 4).round().clamp(0, 4);

    return Stack(
      fit: StackFit.expand,
      children: [
        // 5x5 网格
        Column(
          children: [
            for (var row = 0; row < 5; row++)
              Expanded(
                child: Row(
                  children: [
                    for (var col = 0; col < 5; col++)
                      Expanded(
                        child: _GridCellTile(
                          col: col,
                          row: row,
                          isSelectedCell:
                              selectedChar.id.isNotEmpty &&
                              selectedCol == col &&
                              selectedRow == row,
                          onTap: () {
                            if (selectedChar.id.isNotEmpty) {
                              viewModel.updateCharacterCoordinates(
                                selectedChar.id,
                                col / 4.0,
                                row / 4.0,
                              );
                            }
                          },
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),

        // 锚点渲染
        for (var i = 0; i < enabledCharacters.length; i++) ...[
          _buildAnchor(
            viewModel,
            enabledCharacters[i],
            i,
            enabledCharacters.length,
            selectedId,
            canvasSize,
            isGridMode: true,
          ),
        ],
      ],
    );
  }

  // ==================== V5 自由坐标层 ====================

  Widget _buildFreePositionLayer(
    StudioViewModel viewModel,
    List<NaiCharacterPrompt> characters,
    String? selectedId,
    Size canvasSize,
  ) {
    final enabledCharacters = characters.where((c) => c.enabled).toList();

    return Stack(
      fit: StackFit.expand,
      children: [
        // 三分参考线
        Center(
          child: Container(
            width: 1,
            color: Colors.white.withValues(alpha: 0.2),
          ),
        ),
        Center(
          child: Container(
            height: 1,
            color: Colors.white.withValues(alpha: 0.2),
          ),
        ),

        // 锚点渲染
        for (var i = 0; i < enabledCharacters.length; i++) ...[
          _buildAnchor(
            viewModel,
            enabledCharacters[i],
            i,
            enabledCharacters.length,
            selectedId,
            canvasSize,
            isGridMode: false,
          ),
        ],
      ],
    );
  }

  // ==================== 锚点渲染与拖拽 ====================

  Widget _buildAnchor(
    StudioViewModel viewModel,
    NaiCharacterPrompt character,
    int index,
    int total,
    String? selectedId,
    Size canvasSize, {
    required bool isGridMode,
  }) {
    final isSelected = character.id == (selectedId ?? '');
    final isDragging = _draggingId == character.id;

    double posX = character.useCustomPosition
        ? character.positionX
        : character.resolveCenter(index, total).x;
    double posY = character.useCustomPosition
        ? character.positionY
        : character.resolveCenter(index, total).y;

    if (isDragging) {
      posX = _dragX;
      posY = _dragY;
    }

    final diameter = isDragging ? 38.0 : (isSelected ? 34.0 : 28.0);
    double centerX;
    double centerY;

    if (isGridMode) {
      if (isDragging) {
        final col = (_dragX * 5).floor().clamp(0, 4);
        final row = (_dragY * 5).floor().clamp(0, 4);
        centerX = (col + 0.5) / 5.0 * canvasSize.width;
        centerY = (row + 0.5) / 5.0 * canvasSize.height;
      } else {
        final col = (posX * 4).round().clamp(0, 4);
        final row = (posY * 4).round().clamp(0, 4);
        centerX = (col + 0.5) / 5.0 * canvasSize.width;
        centerY = (row + 0.5) / 5.0 * canvasSize.height;
      }
    } else {
      centerX = posX * canvasSize.width;
      centerY = posY * canvasSize.height;
    }

    final chipInfo = _resolveChipDisplay(character, index);

    return Positioned(
      key: ValueKey('anchor-${character.id}'),
      left: centerX - diameter / 2,
      top: centerY - diameter / 2,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) {
          viewModel.selectCharacterId(character.id);
          setState(() {
            _draggingId = character.id;
            _dragX = posX;
            _dragY = posY;
          });
        },
        onPanUpdate: (details) {
          setState(() {
            _dragX = (_dragX + details.delta.dx / canvasSize.width).clamp(
              0.0,
              1.0,
            );
            _dragY = (_dragY + details.delta.dy / canvasSize.height).clamp(
              0.0,
              1.0,
            );
          });
        },
        onPanEnd: (_) =>
            _commitDrag(viewModel, character, isGridMode: isGridMode),
        onPanCancel: () =>
            _commitDrag(viewModel, character, isGridMode: isGridMode),
        child: _AnchorCircle(
          index: index + 1,
          diameter: diameter,
          color: chipInfo.color,
          isSelected: isSelected,
          isDragging: isDragging,
          tooltip: character.name,
        ),
      ),
    );
  }

  void _commitDrag(
    StudioViewModel viewModel,
    NaiCharacterPrompt character, {
    required bool isGridMode,
  }) {
    if (_draggingId != character.id) return;
    if (isGridMode) {
      final col = (_dragX * 5).floor().clamp(0, 4);
      final row = (_dragY * 5).floor().clamp(0, 4);
      viewModel.updateCharacterCoordinates(character.id, col / 4.0, row / 4.0);
    } else {
      viewModel.updateCharacterCoordinates(character.id, _dragX, _dragY);
    }
    setState(() => _draggingId = null);
  }

  // ==================== 拖动坐标浮签 ====================

  Widget _buildDragTooltip(Size canvasSize) {
    final centerX = _dragX * canvasSize.width;
    final centerY = _dragY * canvasSize.height;

    return Positioned(
      left: (centerX - 40).clamp(0.0, math.max(0.0, canvasSize.width - 80)),
      top: (centerY - 44).clamp(0.0, math.max(0.0, canvasSize.height - 24)),
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.white24),
          ),
          child: Text(
            '${(_dragX * 100).toInt()}% , ${(_dragY * 100).toInt()}%',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

// ==================== 5x5 网格单元格 ====================

class _GridCellTile extends StatelessWidget {
  final int col;
  final int row;
  final bool isSelectedCell;
  final VoidCallback onTap;

  const _GridCellTile({
    required this.col,
    required this.row,
    required this.isSelectedCell,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        decoration: BoxDecoration(
          color: isSelectedCell
              ? Colors.white.withValues(alpha: 0.22)
              : Colors.transparent,
          border: Border.all(
            color: isSelectedCell
                ? Colors.white.withValues(alpha: 0.95)
                : Colors.white.withValues(alpha: 0.14),
            width: isSelectedCell ? 2.0 : 0.8,
          ),
        ),
      ),
    );
  }
}

// ==================== 圆形锚点 ====================

class _AnchorCircle extends StatelessWidget {
  final int index;
  final double diameter;
  final Color color;
  final bool isSelected;
  final bool isDragging;
  final String tooltip;

  const _AnchorCircle({
    required this.index,
    required this.diameter,
    required this.color,
    required this.isSelected,
    required this.isDragging,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? color : Colors.white,
            width: isSelected ? 2.5 : 2.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: isDragging ? 10 : 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          '$index',
          style: TextStyle(
            fontSize: diameter * 0.42,
            fontWeight: FontWeight.w800,
            color: isSelected ? color : Colors.white,
          ),
        ),
      ),
    );
  }
}

// ==================== 临时占位卡片 (比例不匹配或无图时展示) ====================

class CanvasPositionPlaceholderCard extends StatelessWidget {
  final StudioViewModel viewModel;
  final double maxCardWidth;
  final double maxCardHeight;

  const CanvasPositionPlaceholderCard({
    super.key,
    required this.viewModel,
    required this.maxCardWidth,
    required this.maxCardHeight,
  });

  @override
  Widget build(BuildContext context) {
    final params = viewModel.params;
    final aspectRatio = (params.width > 0 && params.height > 0)
        ? (params.width / params.height)
        : 1.0;

    return Center(
      child: Container(
        constraints: BoxConstraints(
          maxWidth: maxCardWidth,
          maxHeight: maxCardHeight,
        ),
        decoration: BoxDecoration(
          color: AppTheme.pureWhite,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.notionBlue, width: 2.0),
          boxShadow: [
            BoxShadow(
              color: AppTheme.notionBlue.withValues(alpha: 0.12),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 优雅的浅灰微网格底纹
              CustomPaint(painter: _PlaceholderGridPainter()),

              // 尺寸标注
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceElevated,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppTheme.borderSubtle),
                  ),
                  child: Text(
                    '临时画板 · ${params.width} × ${params.height}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ),

              // 叠加角色位置交互层
              CharacterPositionOverlay(viewModel: viewModel),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaceholderGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF000000).withValues(alpha: 0.04)
      ..strokeWidth = 1;

    const step = 32.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ==================== Notion 风格画板悬浮操作栏 ====================

/// 角色位置编辑中悬浮的控制栏 (顶部角色切换芯片 + 右下角完成编辑微胶囊)
///
/// 键盘交互统一由 StudioView 的全局 HardwareKeyboard 处理器负责。
class CanvasPositionFloatingControls extends StatelessWidget {
  final StudioViewModel viewModel;

  const CanvasPositionFloatingControls({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
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
    final display = _resolveChipDisplay(character, index);

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
