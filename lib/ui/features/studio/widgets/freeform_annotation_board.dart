import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../data/models/novelai_models.dart';
import '../../../../data/services/image_metadata_service.dart';
import '../../../core/context_l10n.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_floating_dock.dart';
import '../view_models/studio_view_model.dart';
import 'board_image_card.dart';
import 'board_note_card.dart';
import 'board_toolbar.dart';
import 'board_wire_painter.dart';
import 'image_canvas_actions.dart';

/// 画布中心基准点 (6000x6000 视口高性能画板)
const double kBoardCanvasSize = 6000.0;
const double kBoardCenterOrigin = 3000.0;

/// 缩放范围 (鼠标光标不动点缩放与 InteractiveViewer 保持一致)
const double kBoardMinScale = 0.15;
const double kBoardMaxScale = 3.0;

/// 自由大画布 (ComfyUI 风格动态连线 + Miro/PureRef 风格多参考图便签画板)
///
/// 交互模型：
/// - 空白区域左键拖拽直接漫游 (无需切换工具)；中键/右键/按住空格同样漫游
/// - 图片卡/便签卡自身可拖拽移动与删除，选区图钉可拉出连线
/// - 滚轮以光标为不动点缩放；Ctrl+V 粘贴图片；拖入文件导入参考图
class FreeformAnnotationBoard extends StatefulWidget {
  final StudioViewModel viewModel;

  const FreeformAnnotationBoard({super.key, required this.viewModel});

  @override
  State<FreeformAnnotationBoard> createState() =>
      _FreeformAnnotationBoardState();
}

class _FreeformAnnotationBoardState extends State<FreeformAnnotationBoard> {
  final TransformationController _transformController =
      TransformationController();
  AnnotationToolMode _toolMode = AnnotationToolMode.rect;
  bool _isPanMode = false;
  bool _isDraggingExternalOver = false;

  // 连线拖拽与实时覆盖层 (ValueNotifier 驱动连线层局部重绘，拖拽过程不重建整棵工作台)
  final ValueNotifier<BoardWireDragState?> _wireDrag =
      ValueNotifier<BoardWireDragState?>(null);
  final ValueNotifier<BoardLiveOverrides> _liveOverlays =
      ValueNotifier<BoardLiveOverrides>(BoardLiveOverrides.empty);
  late final BoardLiveApi _liveApi = BoardLiveApi(_liveOverlays);
  bool _isSpacePressed = false;
  bool _isBoardDragging = false;

  // 记录鼠标在画板上的全局坐标
  Offset _lastPointerLocal = const Offset(400, 300);
  bool _hasInitialCentered = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleGlobalKey);
    // 视口矩阵同步到 ViewModel (防抖落盘到 canvas_board.json)
    _transformController.addListener(_syncViewport);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleGlobalKey);
    _transformController.removeListener(_syncViewport);
    _wireDrag.dispose();
    _liveOverlays.dispose();
    _transformController.dispose();
    super.dispose();
  }

  /// 把当前视口矩阵 (缩放/平移) 同步给 ViewModel 用于恢复布局
  void _syncViewport() {
    final m = _transformController.value;
    widget.viewModel.updateBoardViewport(
      m.storage[0],
      m.storage[12],
      m.storage[13],
    );
  }

  /// 首帧定位：保存过视口则原样还原，否则居中到内容包围盒
  void _applyInitialViewport(Size viewSize) {
    final bData = widget.viewModel.boardData;
    if (bData.hasSavedViewport) {
      _transformController.value = Matrix4.identity()
        ..storage[0] = bData.viewScale
        ..storage[5] = bData.viewScale
        ..storage[10] = 1.0
        ..storage[12] = bData.viewTx
        ..storage[13] = bData.viewTy
        ..storage[15] = 1.0;
    } else {
      _centerViewport(viewSize);
    }
  }

  /// 焦点落在文本输入框 (便利贴编辑等) 时不得吞键，否则空格无法上屏
  bool _isTypingText() {
    final currentFocus = FocusManager.instance.primaryFocus;
    if (currentFocus == null || currentFocus.context == null) return false;
    final focusedWidget = currentFocus.context!.widget;
    if (focusedWidget is EditableText) return true;
    return currentFocus.context!
            .findAncestorWidgetOfExactType<EditableText>() !=
        null;
  }

  bool _handleGlobalKey(KeyEvent event) {
    if (!mounted || !widget.viewModel.isAnnotatingImage) return false;
    // 空格漫游与 Ctrl+V 粘贴仅在非文本输入状态下接管
    if (_isTypingText()) return false;
    if (event.logicalKey == LogicalKeyboardKey.space) {
      final isDown = event is KeyDownEvent || event is KeyRepeatEvent;
      if (_isSpacePressed != isDown) {
        setState(() => _isSpacePressed = isDown);
      }
      return true;
    }
    if (event is KeyDownEvent &&
        (HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed) &&
        event.logicalKey == LogicalKeyboardKey.keyV) {
      _handlePaste();
      return true;
    }
    // Delete/Backspace 删除当前选中的选区/锚点
    if (event is KeyDownEvent &&
        (event.logicalKey == LogicalKeyboardKey.delete ||
            event.logicalKey == LogicalKeyboardKey.backspace)) {
      final activeId = widget.viewModel.activeAnnotationId;
      if (activeId != null) {
        widget.viewModel.removeAnnotationById(activeId);
        return true;
      }
    }
    return false;
  }

  /// 鼠标滚轮以光标为不动点精准缩放 (Focal Point Zoom，对齐 ComfyUI / Miro)
  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final scrollDelta = event.scrollDelta.dy;
    if (scrollDelta == 0) return;

    // 缩放步进：向上滚放大，向下滚缩小
    final zoomFactor = scrollDelta < 0 ? 1.08 : 0.92;

    final currentMatrix = _transformController.value;
    final currentScale = currentMatrix.storage[0];
    final targetScale = (currentScale * zoomFactor).clamp(
      kBoardMinScale,
      kBoardMaxScale,
    );
    final actualFactor = targetScale / currentScale;

    if ((actualFactor - 1.0).abs() < 0.001) return;

    final mousePos = event.localPosition;

    // 计算鼠标光标在当前画布中的绝对坐标
    final inverse = Matrix4.inverted(currentMatrix);
    final boardPoint = MatrixUtils.transformPoint(inverse, mousePos);

    // 以鼠标光标位置为不动点重新计算平移量
    final newTx = mousePos.dx - boardPoint.dx * targetScale;
    final newTy = mousePos.dy - boardPoint.dy * targetScale;

    final newMatrix = Matrix4.identity()
      ..storage[0] = targetScale
      ..storage[5] = targetScale
      ..storage[10] = 1.0
      ..storage[12] = newTx
      ..storage[13] = newTy
      ..storage[15] = 1.0;

    _transformController.value = newMatrix;
  }

  void _centerViewport(Size viewSize) {
    if (viewSize.width <= 0 || viewSize.height <= 0) return;
    final bData = widget.viewModel.boardData;
    double minX = kBoardCenterOrigin;
    double minY = kBoardCenterOrigin;
    double maxX = kBoardCenterOrigin + 360;
    double maxY = kBoardCenterOrigin + 480;

    if (bData.imageNodes.isNotEmpty) {
      final xs = bData.imageNodes.map((n) => n.offset.dx);
      final ys = bData.imageNodes.map((n) => n.offset.dy);
      final maxXs = bData.imageNodes.map((n) => n.offset.dx + n.width);
      final maxYs = bData.imageNodes.map((n) => n.offset.dy + n.height);
      minX = xs.reduce((a, b) => a < b ? a : b);
      minY = ys.reduce((a, b) => a < b ? a : b);
      maxX = maxXs.reduce((a, b) => a > b ? a : b);
      maxY = maxYs.reduce((a, b) => a > b ? a : b);
    }
    for (final note in bData.noteNodes) {
      if (note.offset.dx < minX) minX = note.offset.dx;
      if (note.offset.dy < minY) minY = note.offset.dy;
      if (note.offset.dx + note.width > maxX) {
        maxX = note.offset.dx + note.width;
      }
      if (note.offset.dy + 120 > maxY) maxY = note.offset.dy + 120;
    }

    final contentCenterX = (minX + maxX) / 2;
    final contentCenterY = (minY + maxY) / 2;

    final tx = viewSize.width / 2 - contentCenterX;
    final ty = viewSize.height / 2 - contentCenterY;
    _transformController.value = Matrix4.translationValues(tx, ty, 0);
  }

  Offset _localToBoard(Offset localPos) {
    final inverse = Matrix4.inverted(_transformController.value);
    return MatrixUtils.transformPoint(inverse, localPos);
  }

  Offset _globalToBoard(Offset globalPos) {
    final box = context.findRenderObject() as RenderBox?;
    final local = box != null ? box.globalToLocal(globalPos) : globalPos;
    return _localToBoard(local);
  }

  Future<void> _handlePaste() async {
    try {
      final (imageBytes, fileName) =
          await ImageMetadataService.readClipboardImageAsync();
      if (imageBytes != null && imageBytes.isNotEmpty) {
        final boardPos = _localToBoard(_lastPointerLocal);
        await widget.viewModel.importReferenceImageFromBytes(
          imageBytes,
          fileName: fileName,
          dropPosition: boardPos,
        );
        if (mounted) {
          showCanvasSnackBar(context, context.l10n.boardPastedImage);
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = widget.viewModel;
    final boardData = viewModel.boardData;
    final colors = context.colors;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (!_hasInitialCentered &&
            constraints.maxWidth > 0 &&
            constraints.maxHeight > 0) {
          _hasInitialCentered = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _applyInitialViewport(constraints.biggest);
          });
        }

        return DropTarget(
          onDragEntered: (_) => setState(() => _isDraggingExternalOver = true),
          onDragExited: (_) => setState(() => _isDraggingExternalOver = false),
          onDragDone: (details) async {
            setState(() => _isDraggingExternalOver = false);
            final dropPos = _localToBoard(details.localPosition);
            for (final file in details.files) {
              final bytes = await file.readAsBytes();
              if (bytes.isNotEmpty) {
                await viewModel.importReferenceImageFromBytes(
                  bytes,
                  fileName: file.name,
                  dropPosition: dropPos,
                );
                if (context.mounted) {
                  showCanvasSnackBar(
                    context,
                    context.l10n.boardImportedReferenceNamed(file.name),
                  );
                }
                break;
              }
            }
          },
          child: DragTarget<NaiGeneratedImage>(
            onAcceptWithDetails: (details) {
              final boardPos = _globalToBoard(details.offset);
              viewModel.addImageNodeToBoard(details.data, position: boardPos);
              showCanvasSnackBar(context, context.l10n.boardAddedHistoryImage);
            },
            builder: (context, candidateData, rejectedData) {
              final isInternalDragOver = candidateData.isNotEmpty;

              return MouseRegion(
                onHover: (e) => _lastPointerLocal = e.localPosition,
                child: Container(
                  color: colors.canvasBackground,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // 1. 无限大画布 InteractiveViewer (支持全向无界漫游与鼠标光标不动点缩放)
                      Listener(
                        onPointerSignal: _handlePointerSignal,
                        onPointerDown: (e) {
                          if (e.buttons == kSecondaryMouseButton ||
                              e.buttons == kMiddleMouseButton ||
                              _isSpacePressed ||
                              _isPanMode) {
                            _isBoardDragging = true;
                          }
                        },
                        onPointerMove: (e) {
                          if (_isBoardDragging && _wireDrag.value == null) {
                            final currentMatrix = _transformController.value;
                            final newMatrix = Matrix4.copy(currentMatrix);
                            newMatrix.storage[12] += e.delta.dx;
                            newMatrix.storage[13] += e.delta.dy;
                            _transformController.value = newMatrix;
                          }
                        },
                        onPointerUp: (_) => _isBoardDragging = false,
                        onPointerCancel: (_) => _isBoardDragging = false,
                        child: InteractiveViewer(
                          transformationController: _transformController,
                          // 关键：不把子树压到视口大小，否则 6000x6000 画布内
                          // 所有节点的命中测试全部失效 (卡片不可拖/删/圈选)
                          constrained: false,
                          boundaryMargin: const EdgeInsets.all(double.infinity),
                          minScale: kBoardMinScale,
                          maxScale: kBoardMaxScale,
                          panEnabled: false,
                          scaleEnabled: false,
                          child: Container(
                            width: kBoardCanvasSize,
                            height: kBoardCanvasSize,
                            color: colors.canvasBackground,
                            child: CustomPaint(
                              // 网格点阵画在卡片之下，连线画在卡片之上 (前景) 不被图片遮挡
                              painter: BoardGridPainter(
                                dotColor: colors.borderHover,
                              ),
                              foregroundPainter: BoardWirePainter(
                                boardData: boardData,
                                liveOverlays: _liveOverlays,
                                wireDrag: _wireDrag,
                                dragColor: colors.primary,
                              ),
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  // 1.0 背景层：左键在空白处直接拖拽漫游，单击空白处取消高亮
                                  Positioned.fill(
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () =>
                                          viewModel.selectAnnotationId(null),
                                      onPanUpdate: (details) {
                                        if (_wireDrag.value != null) return;
                                        final currentMatrix =
                                            _transformController.value;
                                        final newMatrix = Matrix4.copy(
                                          currentMatrix,
                                        );
                                        newMatrix.storage[12] +=
                                            details.delta.dx;
                                        newMatrix.storage[13] +=
                                            details.delta.dy;
                                        _transformController.value = newMatrix;
                                      },
                                    ),
                                  ),

                                  for (final imgNode in boardData.imageNodes)
                                    BoardImageCard(
                                      key: ValueKey(imgNode.id),
                                      viewModel: viewModel,
                                      imageNode: imgNode,
                                      toolMode: _toolMode,
                                      isPanMode: _isPanMode,
                                      isWireDragging: _wireDrag.value != null,
                                      live: _liveApi,
                                      onStartWireFromImage: (anchor) =>
                                          _beginWireDragFromImage(
                                            imgNode.id,
                                            anchor,
                                          ),
                                      onUpdateWire: _updateWireFromGlobal,
                                      onEndWire: _endWireDrag,
                                    ),

                                  // 1.2 便利贴节点渲染 (左侧端口拖拽连线)
                                  for (final noteNode in boardData.noteNodes)
                                    BoardNoteCard(
                                      key: ValueKey(noteNode.id),
                                      viewModel: viewModel,
                                      noteNode: noteNode,
                                      live: _liveApi,
                                      onStartWireFromNote: (anchor) =>
                                          _beginWireDragFromNote(
                                            noteNode.id,
                                            anchor,
                                          ),
                                      onUpdateWire: _updateWireFromGlobal,
                                      onEndWire: _endWireDrag,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                      // 2. 拖入高亮指示器 (外部文件或内部 History 拖入)
                      if (_isDraggingExternalOver || isInternalDragOver)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: Container(
                              decoration: BoxDecoration(
                                color: colors.primary.withValues(alpha: 0.10),
                                border: Border.all(
                                  color: colors.primary,
                                  width: 3.0,
                                ),
                              ),
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colors.cardBackground,
                                    borderRadius: BorderRadius.circular(
                                      AppRadius.md,
                                    ),
                                    boxShadow: context.shadowElevated,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.file_download_outlined,
                                        color: colors.primary,
                                        size: 22,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        isInternalDragOver
                                            ? context.l10n.boardDropInternalHint
                                            : context
                                                  .l10n
                                                  .boardDropExternalHint,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: colors.textPrimary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),

                      // 3. 顶部居中浮动工具坞
                      Positioned(
                        top: 14,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: BoardAnnotationToolbar(
                            toolMode: _toolMode,
                            isPanMode: _isPanMode,
                            onToolModeChanged: (mode) {
                              setState(() {
                                _toolMode = mode;
                                _isPanMode = false;
                              });
                            },
                            onPanModeToggled: () {
                              setState(() {
                                _isPanMode = !_isPanMode;
                              });
                            },
                            onResetView: () =>
                                _centerViewport(constraints.biggest),
                            onAddNote: () {
                              final pos = _localToBoard(
                                Offset(
                                  constraints.maxWidth / 2 + 100,
                                  constraints.maxHeight / 2 - 50,
                                ),
                              );
                              viewModel.addNoteNode(position: pos);
                            },
                            onImportImage: () => pickAndImportReferenceImage(
                              context,
                              viewModel,
                              dropPosition: _localToBoard(
                                const Offset(400, 300),
                              ),
                            ),
                            onPasteImage: _handlePaste,
                          ),
                        ),
                      ),

                      // 4. 底部右下角操作浮动坞
                      Positioned(
                        bottom: 18,
                        right: 18,
                        child: AppFloatingDock(
                          padding: const EdgeInsets.all(4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextButton.icon(
                                onPressed: () =>
                                    viewModel.setAnnotatingImage(false),
                                icon: const Icon(Icons.close_rounded, size: 15),
                                label: Text(
                                  context.l10n.boardExitAnnotation,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                style: TextButton.styleFrom(
                                  foregroundColor: colors.textSecondary,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              ElevatedButton.icon(
                                onPressed: () =>
                                    viewModel.sendAnnotationsToChat(),
                                icon: const Icon(
                                  Icons.smart_toy_outlined,
                                  size: 15,
                                ),
                                label: Text(
                                  context.l10n.boardSendAllToAi,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: colors.primary,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 9,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      AppRadius.sm,
                                    ),
                                  ),
                                  elevation: 0,
                                ),
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
        );
      },
    );
  }

  // ------------------------- 连线拖拽与落点命中 -------------------------

  /// 从便利贴端口开始拉线 (锚点由便签卡计算传入)
  void _beginWireDragFromNote(String noteId, Offset anchorBoardPos) {
    setState(() {
      _wireDrag.value = BoardWireDragState(
        noteId: noteId,
        startBoardPos: anchorBoardPos,
      );
    });
  }

  /// 从图片卡片顶栏端口开始拉线 (锚点由图片卡计算传入)
  void _beginWireDragFromImage(String imageId, Offset anchorBoardPos) {
    setState(() {
      _wireDrag.value = BoardWireDragState(
        imageId: imageId,
        startBoardPos: anchorBoardPos,
      );
    });
  }

  /// 拖拽连线中：把指针全局坐标转换为画布坐标，仅重绘连线层
  void _updateWireFromGlobal(Offset globalPos) {
    final drag = _wireDrag.value;
    if (drag == null) return;
    _wireDrag.value = drag.withCurrent(_globalToBoard(globalPos));
  }

  /// 松手结束连线：对落点做命中测试 (选区/图钉)，未命中则取消
  void _endWireDrag() {
    final drag = _wireDrag.value;
    if (drag == null) return;
    setState(() => _wireDrag.value = null);

    final viewModel = widget.viewModel;
    final hit = _findWireDropAnnotation(drag.currentBoardPos);

    if (drag.noteId != null) {
      if (hit != null) {
        viewModel.connectNoteToAnnotation(
          drag.noteId!,
          hit.imageId,
          hit.annotationId,
        );
      } else {
        // 落空取消连线，不误断既有连接 (断开请用便签顶栏的断开按钮)
        if (mounted) {
          showCanvasSnackBar(context, context.l10n.boardWireMissedTarget);
        }
      }
      return;
    }

    if (drag.imageId != null) {
      if (hit != null) {
        // 参考图连线到选区/锚点：重复拖到同一目标即断开 (toggle)，支持一对多
        viewModel.toggleImageLinkToAnnotation(
          drag.imageId!,
          hit.imageId,
          hit.annotationId,
        );
      } else {
        if (mounted) {
          showCanvasSnackBar(context, context.l10n.boardWireMissedTarget);
        }
      }
    }
  }

  /// 连线落点命中测试：优先命中小目标 (图钉锚点)，再命中选框选区
  _WireDropTarget? _findWireDropAnnotation(Offset boardPos) {
    final bData = widget.viewModel.boardData;
    final live = _liveOverlays.value;
    for (var i = bData.imageNodes.length - 1; i >= 0; i--) {
      final imgNode = bData.imageNodes[i];

      // 1. 图钉锚点 (半径容差命中)
      for (final ann in imgNode.annotations) {
        if (ann.type == AnnotationType.point && ann.point != null) {
          final anchor = boardAnnotationAnchor(imgNode, ann, live: live);
          if ((boardPos - anchor).distance <= 22) {
            return _WireDropTarget(
              imageId: imgNode.id,
              annotationId: ann.id,
              annotation: ann,
            );
          }
        }
      }

      // 2. 选框选区 (包围盒命中，带少量外扩容差)
      for (final ann in imgNode.annotations) {
        if (ann.type == AnnotationType.rect && ann.rect != null) {
          final bounds = boardAnnotationRectBounds(imgNode, ann, live: live);
          if (bounds != null && bounds.inflate(6).contains(boardPos)) {
            return _WireDropTarget(
              imageId: imgNode.id,
              annotationId: ann.id,
              annotation: ann,
            );
          }
        }
      }
    }
    return null;
  }
}

/// 连线落点命中结果
class _WireDropTarget {
  final String imageId;
  final String annotationId;
  final ImageAnnotation annotation;

  const _WireDropTarget({
    required this.imageId,
    required this.annotationId,
    required this.annotation,
  });
}
