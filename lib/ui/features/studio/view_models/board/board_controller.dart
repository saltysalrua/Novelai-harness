import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

import '../../../../../core/harness/tools/annotation_tools.dart';
import '../../../../../core/harness/tools/vision_image_codec.dart';
import '../../../../../core/harness/types.dart';
import '../../../../../data/models/novelai_models.dart';
import '../../../../../data/repositories/novelai_repository.dart';
import '../../../../../data/services/anlas_calculator.dart';

/// 自由大画布领域控制器的宿主回调接口。
///
/// 阶段 4D 试点契约 (plans/stage_4d_controller_decision_gate.md §7)：
/// Controller 不持有 StudioViewModel 全貌，仅经本接口触达宿主。
/// 其中 [boardSelectedImage] / [onBoardSelectedImageChanged] /
/// [ensureBoardImageLoaded] / [boardImagePersistenceEnabled] /
/// [boardSaveDirectory] 属宿主共享底座 (决策门 §8：Controller 不得私有化复制)，
/// 其余为决策门点名的最小回调三项 (sendChatMessage / onBoardStatus /
/// requestGlobalNotify) 加跨编辑模式互斥所需的 [exitOtherCanvasEditModes]。
abstract interface class BoardControllerHost {
  /// 宿主当前选中的图片 (共享底座只读)
  NaiGeneratedImage? get boardSelectedImage;

  /// 批注模式需要切换选中图片时回写宿主 (仅回写引用，不加载字节、不广播)
  void onBoardSelectedImageChanged(NaiGeneratedImage image);

  /// 确保大图字节已载入内存 (走宿主共享字节缓存 imageBytesNotifier)
  Future<Uint8List?> ensureBoardImageLoaded(NaiGeneratedImage image);

  /// 发送对话消息到 Agent 对话流 (sendAnnotationsToChat 出口)
  Future<void> sendChatMessage(String text, {List<AgentMessageImage>? images});

  /// 批注模式开启时退出角色位置/水印位置等其他画布编辑模式
  void exitOtherCanvasEditModes();

  /// 大画布状态消息通道 (宿主侧生成展示；当前预留)
  void onBoardStatus(String message);

  /// 图片持久化开关 (布局落盘判定)
  bool get boardImagePersistenceEnabled;

  /// 存储根目录 (布局落盘判定)
  String get boardSaveDirectory;

  /// 借用宿主全局广播刷新 UI (试点期通知策略，决策门 §4-3 推荐方案)
  void requestGlobalNotify();
}

/// 自由大画布领域控制器：图片节点 / 便利贴 / 批注选区 / 连线与布局持久化。
///
/// 阶段 4D 批准的唯一拆分试点，整域自 studio_vm_annotations.dart (930 行)
/// 平移而来，方法签名保持不变；宿主经 [BoardControllerHost] 最小接口交互。
///
/// 通知策略：继承 ChangeNotifier 供未来局部监听，但试点期所有状态变更统一
/// 经 [BoardControllerHost.requestGlobalNotify] 借用宿主广播，自身不直接
/// notifyListeners (避免 UI 层连锁改造)。
///
/// 迟到写入防护：dispose 后所有广播与宿主回调用 [_alive] 卫语句拦截，
/// 异步链 (await 仓库落盘 / 字节解码) 在恢复执行前必须复查存活状态。
class BoardController extends ChangeNotifier {
  BoardController({required this._host, required this._repository});

  final BoardControllerHost _host;
  final NovelAiRepository _repository;

  /// 是否正在画板上批注当前选中的图片
  bool _isAnnotatingImage = false;

  /// 当前高亮选中的批注 ID
  String? _activeAnnotationId;

  /// 当前自由大画布上的完整节点与连接数据
  CanvasBoardData? _boardData;

  /// 大画布布局持久化防抖计时器 (拖拽/缩放/移动后延迟落盘)
  Timer? _boardSaveDebounceTimer;

  /// 迟到写入防护：dispose 后拒绝一切广播与宿主回调
  bool _alive = true;

  /// 是否正在画板上批注当前选中的图片
  bool get isAnnotatingImage => _isAnnotatingImage;

  /// 当前高亮选中的批注 ID (用于高亮选区与卡片定位)
  String? get activeAnnotationId => _activeAnnotationId;

  /// 当前大画布完整数据 (无数据时按当前选中/历史首图懒初始化)
  CanvasBoardData get boardData {
    if (_boardData == null) {
      _initBoardData();
    }
    return _boardData!;
  }

  // ------------------------- 宿主交互封装 -------------------------

  /// 借用宿主全局广播 (dispose 后静默丢弃，保护已释放宿主)
  void _broadcast() {
    if (!_alive) return;
    _host.requestGlobalNotify();
  }

  /// 当前大画布布局防抖落盘 (仅图片持久化开启时生效)
  void _scheduleBoardSave() {
    if (!_host.boardImagePersistenceEnabled ||
        _host.boardSaveDirectory.isEmpty) {
      return;
    }
    _boardSaveDebounceTimer?.cancel();
    _boardSaveDebounceTimer = Timer(const Duration(milliseconds: 600), () {
      unawaited(_flushBoardSave());
    });
  }

  /// 立即写入当前大画布布局 (dispose 与退出持久化时调用)
  Future<void> _flushBoardSave() async {
    final bData = _boardData;
    if (bData == null) return;
    await _repository.saveBoardLayout(
      bData,
      saveDir: _host.boardSaveDirectory,
      enabled: _host.boardImagePersistenceEnabled,
    );
  }

  // ------------------------- 生命周期 -------------------------

  @override
  void dispose() {
    _alive = false;
    // 大画布布局：取消防抖并立即落盘一次 (契约保持与旧宿主 dispose 等价)
    _boardSaveDebounceTimer?.cancel();
    unawaited(_flushBoardSave());
    super.dispose();
  }

  /// 宿主启动时注入持久化恢复的画布布局 (init 流程)
  void restoreLayout(CanvasBoardData data) {
    _boardData = data;
  }

  /// 宿主关闭图片持久化时丢弃内存布局 (不删除磁盘文件，重开开关后可再恢复)
  void discardLayout() {
    _boardData = null;
  }

  /// 其他画布编辑模式 (水印位置编辑等) 开启时静默退出批注模式：
  /// 仅置位不广播，由调用方统一 notify (行为对齐旧内联赋值路径)
  void exitAnnotatingModeQuietly() {
    _isAnnotatingImage = false;
  }

  /// 历史图片删除/清空后同步大画布：
  /// 移除指向已删历史图片的节点 (主图节点可选替换为新选中图)、
  /// 解绑指向已删节点的便签连接与参考图连线。
  void pruneHistoryNodes(
    Set<String> historyImageIds, {
    NaiGeneratedImage? mainReplacement,
  }) {
    final bData = _boardData;
    if (bData == null) return;
    final hasMatch = bData.imageNodes.any(
      (n) => historyImageIds.contains(n.image.id),
    );
    if (!hasMatch) return;

    final remainingNodes = <CanvasImageNode>[];
    for (final node in bData.imageNodes) {
      if (historyImageIds.contains(node.image.id)) {
        if (node.isMain && mainReplacement != null) {
          remainingNodes.add(
            node.copyWith(
              image: mainReplacement,
              annotations: mainReplacement.annotations,
            ),
          );
        }
        // 非主图节点或无替代图时直接移除
      } else {
        remainingNodes.add(node);
      }
    }

    final removedNodeIds = bData.imageNodes
        .where((n) => !remainingNodes.any((rem) => rem.id == n.id))
        .map((n) => n.id)
        .toSet();

    final updatedNotes = bData.noteNodes.map((n) {
      if (removedNodeIds.contains(n.targetImageId)) {
        return n.copyWith(clearConnection: true);
      }
      return n;
    }).toList();

    final updatedLinks = bData.imageLinks
        .where(
          (l) =>
              !removedNodeIds.contains(l.sourceImageId) &&
              !removedNodeIds.contains(l.targetImageId),
        )
        .toList();

    _boardData = bData.copyWith(
      imageNodes: remainingNodes,
      noteNodes: updatedNotes,
      imageLinks: updatedLinks,
    );
    _scheduleBoardSave();
  }

  // ------------------------- 批注模式 -------------------------

  /// 初始化或重置大画布数据 (依据宿主选中图或历史首图)
  void _initBoardData() {
    final mainImg =
        _host.boardSelectedImage ??
        (_repository.history.isNotEmpty ? _repository.history.first : null);

    final imageNodes = <CanvasImageNode>[];
    final noteNodes = <CanvasNoteNode>[];

    if (mainImg != null) {
      final imgW = (mainImg.params.width).toDouble();
      final imgH = (mainImg.params.height).toDouble();
      final scale = 480.0 / (imgH > 0 ? imgH : 1024.0);
      final displayW = imgW * scale;
      final displayH = 480.0;

      final mainNode = CanvasImageNode(
        id: 'main-${mainImg.id}',
        image: mainImg,
        offset: const Offset(3000, 3000),
        width: displayW,
        height: displayH,
        isMain: true,
        annotations: mainImg.annotations,
      );
      imageNodes.add(mainNode);

      // 为既有批注自动创建对应的便利贴
      var noteY = 3000.0;
      for (var i = 0; i < mainImg.annotations.length; i++) {
        final ann = mainImg.annotations[i];
        noteNodes.add(
          CanvasNoteNode(
            id: 'note-${ann.id}',
            text: ann.note,
            offset: Offset(3000 + displayW + 60, noteY),
            colorIndex: ann.colorIndex,
            targetImageId: mainNode.id,
            targetAnnotationId: ann.id,
          ),
        );
        noteY += 140.0;
      }
    }

    _boardData = CanvasBoardData(
      imageNodes: imageNodes,
      noteNodes: noteNodes,
      viewScale: 1.0,
      viewTx: 0.0,
      viewTy: 0.0,
    );
    _scheduleBoardSave();
  }

  /// 开启或退出批注模式 (可指定切换到特定图片)
  ///
  /// 退出时保留大画布数据，下次进入原样恢复；仅当画布不存在或
  /// 目标主图发生变化时才重建，避免清空用户手工摆放的布局。
  void setAnnotatingImage(bool annotating, {String? targetImageId}) {
    NaiGeneratedImage? target;
    if (targetImageId != null) {
      target = _repository.history
          .where((img) => img.id == targetImageId)
          .firstOrNull;
      if (target != null) {
        _host.onBoardSelectedImageChanged(target);
      }
    }
    if (_isAnnotatingImage == annotating && targetImageId == null) return;
    _isAnnotatingImage = annotating;

    // 退出角色与水印位置编辑模式，避免双编辑模式冲突
    if (annotating) {
      _host.exitOtherCanvasEditModes();
      final bData = _boardData;
      final mainImg = target ?? _host.boardSelectedImage;
      final currentMainId = bData?.imageNodes
          .where((n) => n.isMain)
          .firstOrNull
          ?.image
          .id;
      final needsRebuild =
          bData == null || mainImg == null || currentMainId != mainImg.id;
      if (needsRebuild) {
        _initBoardData();
      }
    } else {
      // 保留画布数据供下次进入恢复，仅清理选中高亮
      _activeAnnotationId = null;
    }
    _broadcast();
  }

  /// 记录大画布视口矩阵 (InteractiveViewer 平移/缩放，仅更新数据并防抖落盘，
  /// 不触发广播 —— 视口由画板自身控制)
  void updateBoardViewport(double scale, double tx, double ty) {
    final bData = _boardData;
    if (bData == null) return;
    if (bData.viewScale == scale && bData.viewTx == tx && bData.viewTy == ty) {
      return;
    }
    _boardData = bData.copyWith(viewScale: scale, viewTx: tx, viewTy: ty);
    _scheduleBoardSave();
  }

  /// 选中指定批注 (用于高亮选区与卡片定位)
  void selectAnnotationId(String? id) {
    if (_activeAnnotationId == id) return;
    _activeAnnotationId = id;
    _broadcast();
  }

  // ==================== 大画布节点与便利贴 CRUD ====================

  /// 添加一张参考图卡片到自由大画布中
  void addImageNodeToBoard(NaiGeneratedImage image, {Offset? position}) {
    if (_boardData == null) _initBoardData();
    final curData = boardData;
    final imgW = (image.params.width).toDouble();
    final imgH = (image.params.height).toDouble();
    final scale = 360.0 / (imgH > 0 ? imgH : 1024.0);
    final displayW = imgW * scale;
    final displayH = 360.0;

    final defaultPos =
        position ??
        Offset(
          curData.imageNodes.isEmpty
              ? 3000
              : curData.imageNodes.last.offset.dx +
                    curData.imageNodes.last.width +
                    60,
          curData.imageNodes.isEmpty ? 3000 : curData.imageNodes.last.offset.dy,
        );

    final newNode = CanvasImageNode(
      id: 'ref-${image.id}-${DateTime.now().millisecondsSinceEpoch}',
      image: image,
      offset: defaultPos,
      width: displayW,
      height: displayH,
      // 参考卡片永远不占主图位：主图节点只由 _initBoardData 依据当前
      // 选中/生成图创建，画布无主图时也保持纯参考布局
      isMain: false,
      annotations: image.annotations,
    );

    _boardData = curData.copyWith(imageNodes: [...curData.imageNodes, newNode]);
    _broadcast();
    _scheduleBoardSave();
  }

  /// 调整图片卡片尺寸 (右下角缩放手柄拖拽结束的提交入口)
  void resizeImageNode(String nodeId, double width, double height) {
    if (_boardData == null) return;
    final w = width.clamp(kBoardImageCardMinWidth, kBoardCardMaxSize);
    final h = height.clamp(kBoardImageCardMinHeight, kBoardCardMaxSize);
    final updated = _boardData!.imageNodes.map((node) {
      if (node.id == nodeId) {
        return node.copyWith(width: w, height: h);
      }
      return node;
    }).toList();

    _boardData = _boardData!.copyWith(imageNodes: updated);
    _broadcast();
    _scheduleBoardSave();
  }

  /// 移动图片卡片位置
  void moveImageNode(String nodeId, Offset newOffset) {
    if (_boardData == null) return;
    final updated = _boardData!.imageNodes.map((node) {
      if (node.id == nodeId) {
        return node.copyWith(offset: newOffset);
      }
      return node;
    }).toList();

    _boardData = _boardData!.copyWith(imageNodes: updated);
    _broadcast();
    _scheduleBoardSave();
  }

  /// 移除图片卡片 (主图不可删除)
  void removeImageNode(String nodeId) {
    if (_boardData == null) return;
    final updated = _boardData!.imageNodes
        .where((n) => n.id != nodeId || n.isMain)
        .toList();

    // 同时解绑关联到该图片的便利贴与参考图连线
    final updatedNotes = _boardData!.noteNodes.map((n) {
      if (n.targetImageId == nodeId) {
        return n.copyWith(clearConnection: true);
      }
      return n;
    }).toList();

    final updatedLinks = _boardData!.imageLinks
        .where((l) => l.sourceImageId != nodeId && l.targetImageId != nodeId)
        .toList();

    _boardData = _boardData!.copyWith(
      imageNodes: updated,
      noteNodes: updatedNotes,
      imageLinks: updatedLinks,
    );
    _broadcast();
    _scheduleBoardSave();
  }

  /// 在指定图片节点上添加批注
  Future<void> addAnnotationToImageNode(
    String imageNodeId,
    ImageAnnotation annotation,
  ) async {
    if (_boardData == null) _initBoardData();
    CanvasImageNode? targetNode;

    final updatedNodes = _boardData!.imageNodes.map((node) {
      if (node.id == imageNodeId) {
        final newAnnList = [...node.annotations, annotation];
        targetNode = node.copyWith(annotations: newAnnList);
        return targetNode!;
      }
      return node;
    }).toList();

    // 自动为该选区生成一张相连的便利贴
    CanvasNoteNode? autoNote;
    if (targetNode != null) {
      final noteOffset = Offset(
        targetNode!.offset.dx + targetNode!.width + 40,
        targetNode!.offset.dy +
            (annotation.type == AnnotationType.rect && annotation.rect != null
                ? annotation.rect!.top * targetNode!.height
                : (annotation.point?.dy ?? 0.5) * targetNode!.height),
      );
      autoNote = CanvasNoteNode(
        id: 'note-${annotation.id}',
        text: annotation.note,
        offset: noteOffset,
        colorIndex: annotation.colorIndex,
        targetImageId: targetNode!.id,
        targetAnnotationId: annotation.id,
      );
    }

    _boardData = _boardData!.copyWith(
      imageNodes: updatedNodes,
      noteNodes: autoNote != null
          ? [..._boardData!.noteNodes, autoNote]
          : _boardData!.noteNodes,
    );

    // 先同步刷新 UI (避免选区/图钉松手时闪回旧位置)，再落盘
    _activeAnnotationId = annotation.id;
    _broadcast();
    _scheduleBoardSave();

    // 同步到持久化仓库 (若为主图)
    if (targetNode != null && targetNode!.isMain) {
      await _repository.updateImageAnnotations(
        imageId: targetNode!.image.id,
        annotations: targetNode!.annotations,
        saveDir: _host.boardSaveDirectory,
        enablePersistence: _host.boardImagePersistenceEnabled,
      );
      if (!_alive) return;
    }
  }

  /// 更新图片节点上的批注 (例如移动选区/锚点)
  Future<void> updateAnnotationInImageNode(
    String imageNodeId,
    ImageAnnotation annotation,
  ) async {
    if (_boardData == null) return;
    CanvasImageNode? targetNode;

    final updatedNodes = _boardData!.imageNodes.map((node) {
      if (node.id == imageNodeId) {
        final updatedList = node.annotations.map((a) {
          if (a.id == annotation.id) return annotation;
          return a;
        }).toList();
        targetNode = node.copyWith(annotations: updatedList);
        return targetNode!;
      }
      return node;
    }).toList();

    _boardData = _boardData!.copyWith(imageNodes: updatedNodes);

    // 先同步刷新 UI (避免选区/图钉拖拽结束时闪回旧位置)，再落盘
    _broadcast();
    _scheduleBoardSave();

    // 同步到持久化仓库 (若为主图)
    if (targetNode != null && targetNode!.isMain) {
      await _repository.updateImageAnnotations(
        imageId: targetNode!.image.id,
        annotations: targetNode!.annotations,
        saveDir: _host.boardSaveDirectory,
        enablePersistence: _host.boardImagePersistenceEnabled,
      );
      if (!_alive) return;
    }
  }

  /// 删除图片节点上的批注
  Future<void> removeAnnotationFromImageNode(
    String imageNodeId,
    String annotationId,
  ) async {
    if (_boardData == null) return;
    CanvasImageNode? targetNode;

    final updatedNodes = _boardData!.imageNodes.map((node) {
      if (node.id == imageNodeId) {
        final updatedList = node.annotations
            .where((a) => a.id != annotationId)
            .toList();
        targetNode = node.copyWith(annotations: updatedList);
        return targetNode!;
      }
      return node;
    }).toList();

    // 同时解绑关联到该批注的便利贴与参考图连线
    final updatedNotes = _boardData!.noteNodes.map((n) {
      if (n.targetImageId == imageNodeId &&
          n.targetAnnotationId == annotationId) {
        return n.copyWith(clearConnection: true);
      }
      return n;
    }).toList();

    final updatedLinks = _boardData!.imageLinks
        .where(
          (l) =>
              !(l.targetImageId == imageNodeId &&
                  l.targetAnnotationId == annotationId),
        )
        .toList();

    _boardData = _boardData!.copyWith(
      imageNodes: updatedNodes,
      noteNodes: updatedNotes,
      imageLinks: updatedLinks,
    );
    if (_activeAnnotationId == annotationId) {
      _activeAnnotationId = null;
    }

    // 先同步刷新 UI，再落盘
    _broadcast();
    _scheduleBoardSave();

    // 同步到持久化仓库 (若为主图)
    if (targetNode != null && targetNode!.isMain) {
      await _repository.updateImageAnnotations(
        imageId: targetNode!.image.id,
        annotations: targetNode!.annotations,
        saveDir: _host.boardSaveDirectory,
        enablePersistence: _host.boardImagePersistenceEnabled,
      );
      if (!_alive) return;
    }
  }

  // ==================== 便利贴 (Sticky Notes) 操作 ====================

  /// 添加一张新的便利贴
  void addNoteNode({
    String text = '',
    Offset? position,
    int colorIndex = 0,
    String? targetImageId,
    String? targetAnnotationId,
  }) {
    if (_boardData == null) _initBoardData();
    final newId = 'note-${DateTime.now().millisecondsSinceEpoch}';
    final defaultPos = position ?? const Offset(3600, 3000);

    final newNote = CanvasNoteNode(
      id: newId,
      text: text,
      offset: defaultPos,
      colorIndex: colorIndex,
      targetImageId: targetImageId,
      targetAnnotationId: targetAnnotationId,
    );

    _boardData = _boardData!.copyWith(
      noteNodes: [..._boardData!.noteNodes, newNote],
    );
    _broadcast();
    _scheduleBoardSave();
  }

  /// 更新便利贴 (文本内容、位置、尺寸、颜色或连接关系)
  void updateNoteNode(
    String noteId, {
    String? text,
    Offset? offset,
    double? width,
    double? height,
    int? colorIndex,
    String? targetImageId,
    String? targetAnnotationId,
    bool clearConnection = false,
  }) {
    if (_boardData == null) return;
    final updated = _boardData!.noteNodes.map((node) {
      if (node.id == noteId) {
        return node.copyWith(
          text: text,
          offset: offset,
          width: width,
          height: height,
          colorIndex: colorIndex,
          targetImageId: targetImageId,
          targetAnnotationId: targetAnnotationId,
          clearConnection: clearConnection,
        );
      }
      return node;
    }).toList();

    _boardData = _boardData!.copyWith(noteNodes: updated);

    // 若已连接到批注，同步更新对应批注的文字
    if (text != null) {
      final targetNote = updated.where((n) => n.id == noteId).firstOrNull;
      if (targetNote != null && targetNote.isConnected) {
        final imgNode = _boardData!.imageNodes
            .where((img) => img.id == targetNote.targetImageId)
            .firstOrNull;
        if (imgNode != null) {
          final ann = imgNode.annotations
              .where((a) => a.id == targetNote.targetAnnotationId)
              .firstOrNull;
          if (ann != null && ann.note != text) {
            updateAnnotationInImageNode(imgNode.id, ann.copyWith(note: text));
          }
        }
      }
    }

    _broadcast();
    _scheduleBoardSave();
  }

  /// 删除便利贴
  void removeNoteNode(String noteId) {
    if (_boardData == null) return;
    final updated = _boardData!.noteNodes
        .where((node) => node.id != noteId)
        .toList();
    _boardData = _boardData!.copyWith(noteNodes: updated);
    _broadcast();
    _scheduleBoardSave();
  }

  /// 连接便利贴到指定图片的批注选区
  void connectNoteToAnnotation(
    String noteId,
    String imageId,
    String annotationId,
  ) {
    updateNoteNode(
      noteId,
      targetImageId: imageId,
      targetAnnotationId: annotationId,
    );
  }

  /// 断开便利贴与选区的连接
  void disconnectNote(String noteId) {
    updateNoteNode(noteId, clearConnection: true);
  }

  /// 切换参考图与批注选区/锚点的连线 (重复拖到同一目标即断开，支持一对多)
  void toggleImageLinkToAnnotation(
    String sourceImageId,
    String targetImageId,
    String targetAnnotationId,
  ) {
    if (_boardData == null) return;
    final exists = _boardData!.imageLinks.any(
      (l) => l.matches(sourceImageId, targetImageId, targetAnnotationId),
    );
    final updated = exists
        ? _boardData!.imageLinks
              .where(
                (l) => !l.matches(
                  sourceImageId,
                  targetImageId,
                  targetAnnotationId,
                ),
              )
              .toList()
        : [
            ..._boardData!.imageLinks,
            CanvasImageLink(
              sourceImageId: sourceImageId,
              targetImageId: targetImageId,
              targetAnnotationId: targetAnnotationId,
            ),
          ];

    _boardData = _boardData!.copyWith(imageLinks: updated);
    _broadcast();
    _scheduleBoardSave();
  }

  /// 按批注 ID 删除 (Delete/Backspace 快捷键入口，反查所属图片节点)
  Future<void> removeAnnotationById(String annotationId) async {
    if (_boardData == null) return;
    for (final node in _boardData!.imageNodes) {
      if (node.annotations.any((a) => a.id == annotationId)) {
        await removeAnnotationFromImageNode(node.id, annotationId);
        return;
      }
    }
  }

  // ==================== Agent 批注工具统一写入口 ====================

  /// 全量替换某张历史图片的批注：仓库持久化 + 大画布节点同步 + 选图引用刷新。
  /// Agent 的 add/update/remove/clear 批注工具都经由这一个入口写入。
  Future<bool> replaceImageAnnotations(
    String imageId,
    List<ImageAnnotation> annotations,
  ) async {
    final index = _repository.history.indexWhere((img) => img.id == imageId);
    if (index < 0) return false;

    await _repository.updateImageAnnotations(
      imageId: imageId,
      annotations: annotations,
      saveDir: _host.boardSaveDirectory,
      enablePersistence: _host.boardImagePersistenceEnabled,
    );
    if (!_alive) return false;

    // 同步大画布上的对应节点 (批注模式打开时即时可见)
    final bData = _boardData;
    if (bData != null) {
      final hasNode = bData.imageNodes.any((n) => n.image.id == imageId);
      if (hasNode) {
        final annIds = annotations.map((a) => a.id).toSet();
        final affectedNodeIds = bData.imageNodes
            .where((n) => n.image.id == imageId)
            .map((n) => n.id)
            .toSet();
        final updated = bData.imageNodes.map((node) {
          if (node.image.id == imageId) {
            return node.copyWith(annotations: annotations);
          }
          return node;
        }).toList();
        // Agent 删除/替换批注后，解绑指向已不存在批注的便签与参考图连线，
        // 避免便签变成既不在批注列表也不在自由便签里的"幽灵连接"
        final updatedNotes = bData.noteNodes.map((n) {
          if (affectedNodeIds.contains(n.targetImageId) &&
              !annIds.contains(n.targetAnnotationId)) {
            return n.copyWith(clearConnection: true);
          }
          return n;
        }).toList();
        final updatedLinks = bData.imageLinks
            .where(
              (l) =>
                  !(affectedNodeIds.contains(l.targetImageId) &&
                      !annIds.contains(l.targetAnnotationId)),
            )
            .toList();
        _boardData = bData.copyWith(
          imageNodes: updated,
          noteNodes: updatedNotes,
          imageLinks: updatedLinks,
        );
        _scheduleBoardSave();
      }
    }

    // 刷新选图引用，让普通画板立即反映新批注
    if (_host.boardSelectedImage?.id == imageId) {
      _host.onBoardSelectedImageChanged(_repository.history[index]);
    }
    _broadcast();
    return true;
  }

  // ==================== 导入外部参考图 ====================

  /// 导入外部参考图片 (拖拽、剪贴板粘贴或文件选择) 并自动放置在大画布中作为参考卡片
  /// (纯画布卡片，不污染 NovelAI 历史生图记录；开启图片持久化时字节同步写入
  /// board_refs 子目录，供重启后重建画布布局)
  Future<NaiGeneratedImage?> importReferenceImageFromBytes(
    Uint8List bytes, {
    String? fileName,
    Offset? dropPosition,
  }) async {
    if (bytes.isEmpty) return null;
    final dims = await AnlasCalculator.decodeImageDimensions(bytes);
    if (!_alive) return null;
    final refId = 'ref-${DateTime.now().millisecondsSinceEpoch}';

    // 参考图字节落盘 board_refs 目录 (仅画布使用，不进生图历史)
    final ext = fileName != null && fileName.contains('.')
        ? fileName.substring(fileName.lastIndexOf('.'))
        : '.png';
    final refFilePath = _host.boardImagePersistenceEnabled
        ? _repository.writeBoardReferenceImage(
            bytes,
            saveDir: _host.boardSaveDirectory,
            imageId: refId,
            ext: ext,
          )
        : null;

    final refImage = NaiGeneratedImage(
      id: refId,
      bytes: bytes,
      localFilePath: refFilePath,
      params: NaiGenerationParams(
        prompt: fileName ?? 'Reference Image',
        width: dims?.width ?? 1024,
        height: dims?.height ?? 1024,
      ),
      seed: 0,
      isOpusFree: false,
      createdAt: DateTime.now(),
    );

    if (_isAnnotatingImage) {
      addImageNodeToBoard(refImage, position: dropPosition);
    } else {
      // 进入批注模式展示参考图，但绝不占据主图位、不劫持当前选中图：
      // 主图仍为当前选中/最新生成图 (无历史时画布仅含参考卡片)，
      // 导入的外部图只作为纯参考卡片落位
      _isAnnotatingImage = true;
      _host.exitOtherCanvasEditModes();
      final bData = _boardData;
      final mainImg =
          _host.boardSelectedImage ??
          (_repository.history.isNotEmpty ? _repository.history.first : null);
      final currentMainId = bData?.imageNodes
          .where((n) => n.isMain)
          .firstOrNull
          ?.image
          .id;
      final needsRebuild =
          bData == null || mainImg == null || currentMainId != mainImg.id;
      if (needsRebuild) {
        _initBoardData();
      }
      addImageNodeToBoard(refImage, position: dropPosition);
    }
    _broadcast();
    return refImage;
  }

  // ==================== 发送全部大画布批注与便利贴到 Agent ====================

  /// 发送大画布上的所有批注与便利贴到 Agent 对话流
  Future<void> sendAnnotationsToChat() async {
    final bData = boardData;
    if (bData.imageNodes.isEmpty && bData.noteNodes.isEmpty) return;

    final buffer = StringBuffer();
    buffer.writeln('【画板视觉批注与修改需求】');
    buffer.writeln('我在自由大画布上整理了以下批注与参考信息：\n');

    var totalIndex = 1;
    for (var i = 0; i < bData.imageNodes.length; i++) {
      final imgNode = bData.imageNodes[i];
      final tag = imgNode.isMain ? '主图 (当前生成图)' : '参考图 $i';
      buffer.writeln('---');
      buffer.writeln(
        '📌 [$tag]: 尺寸 ${imgNode.image.params.width}x${imgNode.image.params.height} px',
      );

      if (imgNode.annotations.isEmpty) {
        buffer.writeln('• 该图片暂无独立圈选选区');
      } else {
        for (final ann in imgNode.annotations) {
          final summary = ann.formatCoordinateSummary(
            imgNode.image.params.width,
            imgNode.image.params.height,
          );
          final connectedNote = bData.noteNodes
              .where(
                (n) =>
                    n.targetImageId == imgNode.id &&
                    n.targetAnnotationId == ann.id,
              )
              .firstOrNull;
          final noteText = (connectedNote?.text.trim().isNotEmpty ?? false)
              ? connectedNote!.text.trim()
              : ann.note.trim();

          buffer.writeln('  【批注 $totalIndex】[${ann.type.label}]');
          if (noteText.isNotEmpty) {
            buffer.writeln('  • 批注描述: "$noteText"');
          }
          buffer.writeln('  • 坐标位置: $summary');

          // 关联参考图连线 (一对多)
          final linkedRefs = bData.imageLinks
              .where(
                (l) =>
                    l.targetImageId == imgNode.id &&
                    l.targetAnnotationId == ann.id,
              )
              .map(
                (l) => bData.imageNodes
                    .where((n) => n.id == l.sourceImageId)
                    .firstOrNull,
              )
              .whereType<CanvasImageNode>()
              .toList();
          if (linkedRefs.isNotEmpty) {
            final names = linkedRefs
                .map(
                  (n) =>
                      '参考图 ${bData.imageNodes.indexOf(n)} (${n.image.params.width}x${n.image.params.height})',
                )
                .join('、');
            buffer.writeln('  • 关联参考图: $names (该选区参考对应图片的对应区域)');
          }

          totalIndex++;
        }
      }
      buffer.writeln('');
    }

    // 自由便利贴 (未连接特定选区的全局便签)
    final freeNotes = bData.noteNodes.where((n) => !n.isConnected).toList();
    if (freeNotes.isNotEmpty) {
      buffer.writeln('---');
      buffer.writeln('📝 [全局便签 / 独立修改意见]:');
      for (var j = 0; j < freeNotes.length; j++) {
        final text = freeNotes[j].text.trim();
        if (text.isNotEmpty) {
          buffer.writeln('• 便签 ${j + 1}: "$text"');
        }
      }
      buffer.writeln('');
    }

    buffer.writeln('请结合上述多图圈选选区、像素坐标与便利贴修改意见，帮我更新提示词并进行下一轮生成。');

    // 准备首张主图或合成图作为视觉附件，并附带被连线引用的参考图 (上限共 4 张)
    final messageImages = <AgentMessageImage>[];
    final mainNode =
        bData.imageNodes.where((n) => n.isMain).firstOrNull ??
        bData.imageNodes.firstOrNull;
    if (mainNode != null) {
      final mainBytes =
          await _host.ensureBoardImageLoaded(mainNode.image) ??
          mainNode.image.uint8Bytes;
      if (!_alive) return;
      try {
        final renderRes = await renderImageWithAnnotationOverlay(
          mainBytes,
          mainNode.annotations,
        );
        // 压缩到最长边 1024px 控制视觉 Token (文字批注同时以文本形式附在消息里)
        final payload = await compressVisionImage(renderRes.bytes);
        messageImages.add(
          AgentMessageImage(
            base64: base64Encode(payload.bytes),
            mimeType: payload.mimeType,
          ),
        );
      } catch (_) {
        final payload = await compressVisionImage(mainBytes);
        messageImages.add(
          AgentMessageImage(
            base64: base64Encode(payload.bytes),
            mimeType: payload.mimeType,
          ),
        );
      }
    }

    final linkedRefIds = <String>{};
    for (final link in bData.imageLinks) {
      if (messageImages.length >= 4) break;
      if (linkedRefIds.contains(link.sourceImageId)) continue;
      final refNode = bData.imageNodes
          .where((n) => n.id == link.sourceImageId)
          .firstOrNull;
      if (refNode == null) continue;
      linkedRefIds.add(link.sourceImageId);
      final refBytes =
          await _host.ensureBoardImageLoaded(refNode.image) ??
          refNode.image.uint8Bytes;
      if (!_alive) return;
      final payload = await compressVisionImage(refBytes);
      messageImages.add(
        AgentMessageImage(
          base64: base64Encode(payload.bytes),
          mimeType: payload.mimeType,
        ),
      );
    }

    // 退出批注模式并发送对话
    _isAnnotatingImage = false;
    _broadcast();

    await _host.sendChatMessage(
      buffer.toString(),
      images: messageImages.isNotEmpty ? messageImages : null,
    );
  }
}
