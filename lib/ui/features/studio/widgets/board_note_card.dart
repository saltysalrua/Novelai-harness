import 'package:flutter/material.dart';
import '../../../../data/models/novelai_models.dart';
import '../../../core/context_l10n.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../view_models/studio_view_model.dart';
import 'board_wire_painter.dart';

/// 自由大画布上的便利贴节点卡片：
/// 顶栏拖拽移动 + 连线状态 + 删除 + 文本编辑 + 左侧连线端口
class BoardNoteCard extends StatefulWidget {
  final StudioViewModel viewModel;
  final CanvasNoteNode noteNode;
  final BoardLiveApi live;

  /// 从左侧端口拉出连线 (参数为端口在画布坐标系中的锚点)
  final ValueChanged<Offset> onStartWireFromNote;

  /// 拖拽连线过程中指针的全局坐标 (由大画布统一转换为画布坐标)
  final ValueChanged<Offset> onUpdateWire;

  /// 松手结束连线 (由大画布统一做落点命中测试)
  final VoidCallback onEndWire;

  const BoardNoteCard({
    super.key,
    required this.viewModel,
    required this.noteNode,
    required this.live,
    required this.onStartWireFromNote,
    required this.onUpdateWire,
    required this.onEndWire,
  });

  @override
  State<BoardNoteCard> createState() => _BoardNoteCardState();
}

class _BoardNoteCardState extends State<BoardNoteCard> {
  late final TextEditingController _textController;

  // 卡片本地拖拽 (结束后才提交到 ViewModel，避免全工作台逐帧重建)
  Offset? _noteDragStart;
  Offset? _liveNoteOffset;

  // 卡片本地缩放 (结束后才提交到 ViewModel，连线层经 live 覆盖跟随)
  Size? _liveNoteSize;
  Size? _noteResizeStartSize;
  Offset? _noteResizeAccumDelta;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.noteNode.text);
  }

  @override
  void didUpdateWidget(covariant BoardNoteCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.noteNode.text != widget.noteNode.text &&
        _textController.text != widget.noteNode.text) {
      _textController.text = widget.noteNode.text;
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final note = widget.noteNode;
    final viewModel = widget.viewModel;
    final color = note.color;
    final notePos = _liveNoteOffset ?? note.offset;
    final noteSize = _liveNoteSize ?? Size(note.width, note.height);
    final colors = context.colors;

    return Positioned(
      left: notePos.dx,
      top: notePos.dy,
      width: noteSize.width,
      height: noteSize.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(AppRadius.md),
              color: colors.cardBackground,
              shadowColor: context.isDarkMode ? Colors.black54 : Colors.black26,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                    color: color.withValues(alpha: 0.6),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. 便利贴顶栏：拖拽移动手柄 + 连线状态 + 删除
                    GestureDetector(
                      onPanStart: (details) {
                        _noteDragStart =
                            _liveNoteOffset ?? widget.noteNode.offset;
                      },
                      onPanUpdate: (details) {
                        if (_noteDragStart == null) return;
                        final next = _noteDragStart! + details.delta;
                        _noteDragStart = next;
                        setState(() => _liveNoteOffset = next);
                        widget.live.setNodeOffset(widget.noteNode.id, next);
                      },
                      onPanEnd: (_) => _commitNoteDrag(),
                      onPanCancel: _commitNoteDrag,
                      child: Container(
                        height: 28,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.20),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(6),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: color,
                              ),
                            ),
                            const SizedBox(width: 6),
                            if (note.isConnected)
                              Row(
                                children: [
                                  Icon(
                                    Icons.link_rounded,
                                    size: 13,
                                    color: colors.textSecondary,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    context.l10n.boardNoteConnected,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: colors.textSecondary,
                                    ),
                                  ),
                                ],
                              )
                            else
                              Text(
                                context.l10n.boardNoteTitle,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: colors.textSecondary,
                                ),
                              ),
                            const Spacer(),
                            if (note.isConnected)
                              AppIconButton(
                                icon: Icons.link_off_rounded,
                                tooltip:
                                    context.l10n.boardNoteDisconnectTooltip,
                                size: 20,
                                iconSize: 14,
                                variant: AppIconButtonVariant.ghost,
                                iconColor: colors.textMuted,
                                onPressed: () =>
                                    viewModel.board.disconnectNote(note.id),
                              ),
                            const SizedBox(width: 4),
                            AppIconButton(
                              icon: Icons.close_rounded,
                              tooltip: context.l10n.boardNoteDeleteTooltip,
                              size: 20,
                              iconSize: 14,
                              variant: AppIconButtonVariant.ghost,
                              iconColor: colors.textMuted,
                              onPressed: () =>
                                  viewModel.board.removeNoteNode(note.id),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // 2. 便利贴文本编辑区 (填满卡片剩余高度，随缩放手柄调节)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                        child: TextField(
                          controller: _textController,
                          maxLines: null,
                          minLines: null,
                          expands: true,
                          textAlignVertical: TextAlignVertical.top,
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.textPrimary,
                            height: 1.35,
                          ),
                          decoration: InputDecoration(
                            hintText: context.l10n.boardNoteHint,
                            hintStyle: TextStyle(
                              fontSize: 12,
                              color: colors.textMuted,
                            ),
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                            border: InputBorder.none,
                          ),
                          onChanged: (val) {
                            viewModel.board.updateNoteNode(note.id, text: val);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 3. ComfyUI 风格左侧连线端口小圆点 (按住拖出连线到选区/图钉)
          Positioned(
            left: -6,
            top: 8,
            child: Tooltip(
              message: context.l10n.boardWireDragSourceTooltip,
              child: GestureDetector(
                onPanStart: (_) {
                  widget.onStartWireFromNote(notePos + const Offset(0, 14));
                },
                onPanUpdate: (details) =>
                    widget.onUpdateWire(details.globalPosition),
                onPanEnd: (_) => widget.onEndWire(),
                onPanCancel: widget.onEndWire,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: colors.cardBackground,
                    shape: BoxShape.circle,
                    border: Border.all(color: color, width: 2.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.26),
                        blurRadius: 3,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 4. 右下角缩放手柄 (拖拽调节便签宽高)
          Positioned(
            right: 0,
            bottom: 0,
            child: BoardCardResizeHandle(
              tooltip: context.l10n.boardNoteResizeTooltip,
              color: color,
              onPanStart: () {
                _noteResizeStartSize =
                    _liveNoteSize ?? Size(note.width, note.height);
                _noteResizeAccumDelta = Offset.zero;
              },
              onPanUpdate: (delta) {
                final start =
                    _noteResizeStartSize ??
                    Size(widget.noteNode.width, widget.noteNode.height);
                final accum = (_noteResizeAccumDelta ?? Offset.zero) + delta;
                _noteResizeAccumDelta = accum;
                final next = Size(
                  (start.width + accum.dx).clamp(
                    kBoardNoteMinWidth,
                    kBoardCardMaxSize,
                  ),
                  (start.height + accum.dy).clamp(
                    kBoardNoteMinHeight,
                    kBoardCardMaxSize,
                  ),
                );
                setState(() => _liveNoteSize = next);
                widget.live.setNodeSize(widget.noteNode.id, next);
              },
              onPanEnd: _commitNoteResize,
            ),
          ),
        ],
      ),
    );
  }

  /// 便利贴拖拽结束：一次性提交到 ViewModel 并清空本地实时位置
  void _commitNoteDrag() {
    _noteDragStart = null;
    final finalPos = _liveNoteOffset;
    if (finalPos != null) {
      widget.viewModel.board.updateNoteNode(
        widget.noteNode.id,
        offset: finalPos,
      );
    }
    setState(() => _liveNoteOffset = null);
    widget.live.clearNodeOffset(widget.noteNode.id);
  }

  /// 便利贴缩放结束：一次性提交到 ViewModel 并清空本地实时尺寸
  void _commitNoteResize() {
    _noteResizeStartSize = null;
    _noteResizeAccumDelta = null;
    final finalSize = _liveNoteSize;
    if (finalSize != null) {
      widget.viewModel.board.updateNoteNode(
        widget.noteNode.id,
        width: finalSize.width,
        height: finalSize.height,
      );
    }
    setState(() => _liveNoteSize = null);
    widget.live.clearNodeSize(widget.noteNode.id);
  }
}
