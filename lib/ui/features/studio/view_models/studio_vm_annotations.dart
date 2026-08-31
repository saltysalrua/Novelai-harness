part of 'studio_view_model.dart';

/// 画板图片批注与多参考图自由大画布管理
mixin _StudioAnnotationsMixin on _StudioCore {
  /// 是否正在画板上批注当前选中的图片
  bool get isAnnotatingImage => _isAnnotatingImage;

  /// 当前大画布布局防抖落盘 (仅图片持久化开启时生效)
  void _scheduleBoardSave() {
    if (!_config.enableImagePersistence || _config.saveDirectory.isEmpty) {
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
      saveDir: _config.saveDirectory,
      enabled: _config.enableImagePersistence,
    );
  }

  /// 记录大画布视口矩阵 (InteractiveViewer 平移/缩放，仅更新数据并防抖落盘，
  /// 不触发 notifyListeners —— 视口由画板自身控制)
  void updateBoardViewport(double scale, double tx, double ty) {
    final bData = _boardData;
    if (bData == null) return;
    if (bData.viewScale == scale && bData.viewTx == tx && bData.viewTy == ty) {
      return;
    }
    _boardData = bData.copyWith(viewScale: scale, viewTx: tx, viewTy: ty);
    _scheduleBoardSave();
  }

  /// 当前高亮选中的批注 ID
  String? get activeAnnotationId => _activeAnnotationId;

  /// 当前大画布完整数据
  CanvasBoardData get boardData {
    if (_boardData == null) {
      _initBoardData();
    }
    return _boardData!;
  }

  /// 当前选中图片或主图的批注列表
  List<ImageAnnotation> get currentImageAnnotations {
    final bData = _boardData;
    if (bData != null) {
      final mainNode =
          bData.imageNodes.where((n) => n.isMain).firstOrNull ??
          bData.imageNodes.firstOrNull;
      if (mainNode != null) {
        return mainNode.annotations;
      }
    }
    final img = _selectedImage;
    if (img == null) return const [];
    return img.annotations;
  }

  /// 初始化或重置大画布数据
  void _initBoardData() {
    final mainImg =
        _selectedImage ??
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
        _selectedImage = target;
      }
    }
    if (_isAnnotatingImage == annotating && targetImageId == null) return;
    _isAnnotatingImage = annotating;

    // 退出角色位置编辑模式，避免双编辑模式冲突
    if (annotating && _isEditingCharacterPositions) {
      _isEditingCharacterPositions = false;
    }

    if (annotating) {
      final bData = _boardData;
      final mainImg = target ?? _selectedImage;
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
    notifyListeners();
  }

  /// 选中指定批注 (用于高亮选区与卡片定位)
  void selectAnnotationId(String? id) {
    if (_activeAnnotationId == id) return;
    _activeAnnotationId = id;
    notifyListeners();
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
      isMain: curData.imageNodes.isEmpty,
      annotations: image.annotations,
    );

    _boardData = curData.copyWith(imageNodes: [...curData.imageNodes, newNode]);
    notifyListeners();
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
    notifyListeners();
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
    notifyListeners();
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
    notifyListeners();
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
    notifyListeners();
    _scheduleBoardSave();

    // 同步到持久化仓库 (若为主图)
    if (targetNode != null && targetNode!.isMain) {
      await _repository.updateImageAnnotations(
        imageId: targetNode!.image.id,
        annotations: targetNode!.annotations,
        saveDir: _config.saveDirectory,
        enablePersistence: _config.enableImagePersistence,
      );
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
    notifyListeners();
    _scheduleBoardSave();

    // 同步到持久化仓库 (若为主图)
    if (targetNode != null && targetNode!.isMain) {
      await _repository.updateImageAnnotations(
        imageId: targetNode!.image.id,
        annotations: targetNode!.annotations,
        saveDir: _config.saveDirectory,
        enablePersistence: _config.enableImagePersistence,
      );
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
    notifyListeners();
    _scheduleBoardSave();

    // 同步到持久化仓库 (若为主图)
    if (targetNode != null && targetNode!.isMain) {
      await _repository.updateImageAnnotations(
        imageId: targetNode!.image.id,
        annotations: targetNode!.annotations,
        saveDir: _config.saveDirectory,
        enablePersistence: _config.enableImagePersistence,
      );
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
    notifyListeners();
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

    notifyListeners();
    _scheduleBoardSave();
  }

  /// 删除便利贴
  void removeNoteNode(String noteId) {
    if (_boardData == null) return;
    final updated = _boardData!.noteNodes
        .where((node) => node.id != noteId)
        .toList();
    _boardData = _boardData!.copyWith(noteNodes: updated);
    notifyListeners();
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
    notifyListeners();
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
  @override
  Future<bool> replaceImageAnnotations(
    String imageId,
    List<ImageAnnotation> annotations,
  ) async {
    final index = _repository.history.indexWhere((img) => img.id == imageId);
    if (index < 0) return false;

    await _repository.updateImageAnnotations(
      imageId: imageId,
      annotations: annotations,
      saveDir: _config.saveDirectory,
      enablePersistence: _config.enableImagePersistence,
    );

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
    if (_selectedImage?.id == imageId) {
      _selectedImage = _repository.history[index];
    }
    notifyListeners();
    return true;
  }

  // ==================== 向后兼容单图批注接口 ====================

  Future<void> addAnnotationToSelectedImage(ImageAnnotation annotation) async {
    final mainNode =
        boardData.imageNodes.where((n) => n.isMain).firstOrNull ??
        boardData.imageNodes.firstOrNull;
    if (mainNode != null) {
      await addAnnotationToImageNode(mainNode.id, annotation);
    }
  }

  Future<void> updateAnnotationInSelectedImage(
    ImageAnnotation annotation,
  ) async {
    final mainNode =
        boardData.imageNodes.where((n) => n.isMain).firstOrNull ??
        boardData.imageNodes.firstOrNull;
    if (mainNode != null) {
      await updateAnnotationInImageNode(mainNode.id, annotation);
    }
  }

  Future<void> removeAnnotationFromSelectedImage(String annotationId) async {
    final mainNode =
        boardData.imageNodes.where((n) => n.isMain).firstOrNull ??
        boardData.imageNodes.firstOrNull;
    if (mainNode != null) {
      await removeAnnotationFromImageNode(mainNode.id, annotationId);
    }
  }

  Future<void> clearAnnotationsFromSelectedImage() async {
    final mainNode =
        boardData.imageNodes.where((n) => n.isMain).firstOrNull ??
        boardData.imageNodes.firstOrNull;
    if (mainNode != null) {
      for (final a in mainNode.annotations) {
        await removeAnnotationFromImageNode(mainNode.id, a.id);
      }
    }
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
    final refId = 'ref-${DateTime.now().millisecondsSinceEpoch}';

    // 参考图字节落盘 board_refs 目录 (仅画布使用，不进生图历史)
    final ext = fileName != null && fileName.contains('.')
        ? fileName.substring(fileName.lastIndexOf('.'))
        : '.png';
    final refFilePath = _config.enableImagePersistence
        ? _repository.writeBoardReferenceImage(
            bytes,
            saveDir: _config.saveDirectory,
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
      _selectedImage = refImage;
      _isAnnotatingImage = true;
      _initBoardData();
    }
    notifyListeners();
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
      try {
        final renderRes = await renderImageWithAnnotationOverlay(
          mainNode.image.uint8Bytes,
          mainNode.annotations,
        );
        final base64Str = base64Encode(renderRes.bytes);
        messageImages.add(
          AgentMessageImage(base64: base64Str, mimeType: 'image/png'),
        );
      } catch (_) {
        final base64Str = base64Encode(mainNode.image.uint8Bytes);
        messageImages.add(
          AgentMessageImage(base64: base64Str, mimeType: 'image/png'),
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
      messageImages.add(
        AgentMessageImage(
          base64: base64Encode(refNode.image.uint8Bytes),
          mimeType: 'image/png',
        ),
      );
    }

    // 退出批注模式并发送对话
    _isAnnotatingImage = false;
    notifyListeners();

    await sendChatMessage(
      buffer.toString(),
      images: messageImages.isNotEmpty ? messageImages : null,
    );
  }
}
