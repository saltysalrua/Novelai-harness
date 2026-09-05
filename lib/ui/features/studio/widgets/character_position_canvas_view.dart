import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../../data/models/novelai_models.dart';
import '../view_models/studio_view_model.dart';
import 'canvas_position_floating_controls.dart';
import 'watermark_position_overlay.dart';

// 角色位置交互层文件拆分导出：
// - CanvasPositionFloatingControls / CharacterWheelCycleListener 等 -> canvas_position_floating_controls.dart
// - WatermarkPositionOverlay (水印 2D 交互层) -> watermark_position_overlay.dart
export 'canvas_position_floating_controls.dart';
export 'watermark_position_overlay.dart';

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

    final chipInfo = resolveCharacterChipDisplay(character, index);

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
    final colors = context.colors;
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
          color: colors.cardBackground,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.primary, width: 2.0),
          boxShadow: [
            BoxShadow(
              color: colors.primary.withValues(alpha: 0.12),
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
              CustomPaint(
                painter: _PlaceholderGridPainter(
                  gridColor: colors.borderSubtle,
                ),
              ),

              // 尺寸标注
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: colors.elevatedBackground,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: colors.borderSubtle),
                  ),
                  child: Text(
                    '临时画板 · ${params.width} × ${params.height}',
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ),

              // 叠加角色或水印位置交互层
              if (viewModel.isEditingWatermarkPosition)
                WatermarkPositionOverlay(viewModel: viewModel)
              else
                CharacterPositionOverlay(viewModel: viewModel),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaceholderGridPainter extends CustomPainter {
  final Color gridColor;

  _PlaceholderGridPainter({required this.gridColor});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = gridColor
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
  bool shouldRepaint(covariant _PlaceholderGridPainter oldDelegate) =>
      oldDelegate.gridColor != gridColor;
}
