import 'package:flutter/material.dart' show Color, Offset;
import 'image_annotation.dart';
import 'nai_image_result.dart';

/// 图片卡片拖拽缩放的最小尺寸与全局上限 (UI 手柄与 ViewModel 共用)
const double kBoardImageCardMinWidth = 140.0;
const double kBoardImageCardMinHeight = 120.0;

/// 便利贴卡片拖拽缩放的最小尺寸
const double kBoardNoteMinWidth = 120.0;
const double kBoardNoteMinHeight = 80.0;

/// 卡片尺寸上限 (画布为 6000x6000，留出边距)
const double kBoardCardMaxSize = 4096.0;

/// 自由大画布上的图片节点 (包含主图与参考图卡片)
class CanvasImageNode {
  final String id;
  final NaiGeneratedImage image;
  final Offset offset;
  final double width;
  final double height;
  final bool isMain;
  final List<ImageAnnotation> annotations;

  const CanvasImageNode({
    required this.id,
    required this.image,
    required this.offset,
    required this.width,
    required this.height,
    this.isMain = false,
    this.annotations = const [],
  });

  CanvasImageNode copyWith({
    String? id,
    NaiGeneratedImage? image,
    Offset? offset,
    double? width,
    double? height,
    bool? isMain,
    List<ImageAnnotation>? annotations,
  }) {
    return CanvasImageNode(
      id: id ?? this.id,
      image: image ?? this.image,
      offset: offset ?? this.offset,
      width: width ?? this.width,
      height: height ?? this.height,
      isMain: isMain ?? this.isMain,
      annotations: annotations ?? this.annotations,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'imageId': image.id,
      'offsetX': offset.dx,
      'offsetY': offset.dy,
      'width': width,
      'height': height,
      'isMain': isMain,
      'annotations': annotations.map((a) => a.toJson()).toList(),
      // 图片来源信息：优先从历史记录按 imageId 解析；
      // 参考图不在历史里时按文件路径 + 元信息从 board_refs 目录重建
      'imageFilePath': image.localFilePath,
      if (image.originalFilePath != null)
        'imageOriginalFilePath': image.originalFilePath,
      'imageMeta': {
        'prompt': image.params.prompt,
        'width': image.params.width,
        'height': image.params.height,
        'createdAt': image.createdAt.toIso8601String(),
        'seed': image.seed,
        'isImportedReference': image.isImportedReference,
      },
    };
  }

  factory CanvasImageNode.fromJson(
    Map<String, dynamic> json, {
    required NaiGeneratedImage image,
  }) {
    final rawAnnotations = json['annotations'] as List<dynamic>? ?? [];
    return CanvasImageNode(
      id: json['id'] as String? ?? image.id,
      image: image,
      offset: Offset(
        (json['offsetX'] as num?)?.toDouble() ?? 0.0,
        (json['offsetY'] as num?)?.toDouble() ?? 0.0,
      ),
      width: (json['width'] as num?)?.toDouble() ?? 360.0,
      height: (json['height'] as num?)?.toDouble() ?? 480.0,
      isMain: json['isMain'] as bool? ?? false,
      annotations: rawAnnotations
          .map((item) => ImageAnnotation.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// 自由大画布上的便利贴节点 (Notion 风格便签卡片)
class CanvasNoteNode {
  final String id;
  final String text;
  final Offset offset;
  final double width;

  /// 便签卡片高度 (可拖拽右下角手柄调节)
  final double height;
  final int colorIndex;
  final String? targetImageId;
  final String? targetAnnotationId;

  const CanvasNoteNode({
    required this.id,
    required this.text,
    required this.offset,
    this.width = 220.0,
    this.height = 132.0,
    this.colorIndex = 0,
    this.targetImageId,
    this.targetAnnotationId,
  });

  Color get color => kAnnotationPalette[colorIndex % kAnnotationPalette.length];

  bool get isConnected =>
      targetImageId != null &&
      targetImageId!.isNotEmpty &&
      targetAnnotationId != null &&
      targetAnnotationId!.isNotEmpty;

  CanvasNoteNode copyWith({
    String? id,
    String? text,
    Offset? offset,
    double? width,
    double? height,
    int? colorIndex,
    String? targetImageId,
    String? targetAnnotationId,
    bool clearConnection = false,
  }) {
    return CanvasNoteNode(
      id: id ?? this.id,
      text: text ?? this.text,
      offset: offset ?? this.offset,
      width: width ?? this.width,
      height: height ?? this.height,
      colorIndex: colorIndex ?? this.colorIndex,
      targetImageId: clearConnection
          ? null
          : (targetImageId ?? this.targetImageId),
      targetAnnotationId: clearConnection
          ? null
          : (targetAnnotationId ?? this.targetAnnotationId),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'offsetX': offset.dx,
      'offsetY': offset.dy,
      'width': width,
      'height': height,
      'colorIndex': colorIndex,
      'targetImageId': targetImageId,
      'targetAnnotationId': targetAnnotationId,
    };
  }

  factory CanvasNoteNode.fromJson(Map<String, dynamic> json) {
    return CanvasNoteNode(
      id:
          json['id'] as String? ??
          'note-${DateTime.now().millisecondsSinceEpoch}',
      text: json['text'] as String? ?? '',
      offset: Offset(
        (json['offsetX'] as num?)?.toDouble() ?? 0.0,
        (json['offsetY'] as num?)?.toDouble() ?? 0.0,
      ),
      width: (json['width'] as num?)?.toDouble() ?? 220.0,
      height: (json['height'] as num?)?.toDouble() ?? 132.0,
      colorIndex: json['colorIndex'] as int? ?? 0,
      targetImageId: json['targetImageId'] as String?,
      targetAnnotationId: json['targetAnnotationId'] as String?,
    );
  }
}

/// 自由大画布上的参考图连线 (参考图卡片 → 目标图片上的选区/锚点，一个批注可挂多条)
class CanvasImageLink {
  final String sourceImageId;
  final String targetImageId;
  final String targetAnnotationId;

  const CanvasImageLink({
    required this.sourceImageId,
    required this.targetImageId,
    required this.targetAnnotationId,
  });

  bool matches(
    String sourceImageId,
    String targetImageId,
    String targetAnnotationId,
  ) {
    return this.sourceImageId == sourceImageId &&
        this.targetImageId == targetImageId &&
        this.targetAnnotationId == targetAnnotationId;
  }

  Map<String, dynamic> toJson() {
    return {
      'sourceImageId': sourceImageId,
      'targetImageId': targetImageId,
      'targetAnnotationId': targetAnnotationId,
    };
  }

  factory CanvasImageLink.fromJson(Map<String, dynamic> json) {
    return CanvasImageLink(
      sourceImageId: json['sourceImageId'] as String? ?? '',
      targetImageId: json['targetImageId'] as String? ?? '',
      targetAnnotationId: json['targetAnnotationId'] as String? ?? '',
    );
  }
}

/// 自由大画布整体持久化数据
class CanvasBoardData {
  final List<CanvasImageNode> imageNodes;
  final List<CanvasNoteNode> noteNodes;
  final List<CanvasImageLink> imageLinks;

  /// 视口矩阵 (InteractiveViewer 平移量与缩放，恢复上次浏览位置)
  final double viewScale;
  final double viewTx;
  final double viewTy;

  const CanvasBoardData({
    required this.imageNodes,
    required this.noteNodes,
    this.imageLinks = const [],
    this.viewScale = 1.0,
    this.viewTx = 0.0,
    this.viewTy = 0.0,
  });

  /// 是否保存过非默认视口 (用于恢复时判断走居中还是还原矩阵)
  bool get hasSavedViewport =>
      viewScale != 1.0 || viewTx != 0.0 || viewTy != 0.0;

  CanvasBoardData copyWith({
    List<CanvasImageNode>? imageNodes,
    List<CanvasNoteNode>? noteNodes,
    List<CanvasImageLink>? imageLinks,
    double? viewScale,
    double? viewTx,
    double? viewTy,
  }) {
    return CanvasBoardData(
      imageNodes: imageNodes ?? this.imageNodes,
      noteNodes: noteNodes ?? this.noteNodes,
      imageLinks: imageLinks ?? this.imageLinks,
      viewScale: viewScale ?? this.viewScale,
      viewTx: viewTx ?? this.viewTx,
      viewTy: viewTy ?? this.viewTy,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'imageNodes': imageNodes.map((n) => n.toJson()).toList(),
      'noteNodes': noteNodes.map((n) => n.toJson()).toList(),
      'imageLinks': imageLinks.map((l) => l.toJson()).toList(),
      'viewScale': viewScale,
      'viewTx': viewTx,
      'viewTy': viewTy,
    };
  }

  factory CanvasBoardData.fromJson(
    Map<String, dynamic> json, {
    required List<NaiGeneratedImage> gallery,
  }) {
    final rawImages = json['imageNodes'] as List<dynamic>? ?? [];
    final rawNotes = json['noteNodes'] as List<dynamic>? ?? [];

    final imageMap = {for (final img in gallery) img.id: img};

    final imageNodes = <CanvasImageNode>[];
    for (final raw in rawImages) {
      if (raw is Map<String, dynamic>) {
        final imgId = raw['imageId'] as String? ?? raw['id'] as String?;
        if (imgId != null && imageMap.containsKey(imgId)) {
          imageNodes.add(
            CanvasImageNode.fromJson(raw, image: imageMap[imgId]!),
          );
        }
      }
    }

    final noteNodes = rawNotes
        .whereType<Map<String, dynamic>>()
        .map((raw) => CanvasNoteNode.fromJson(raw))
        .toList();

    final rawLinks = json['imageLinks'] as List<dynamic>? ?? [];
    final imageLinks = rawLinks
        .whereType<Map<String, dynamic>>()
        .map((raw) => CanvasImageLink.fromJson(raw))
        .where(
          (l) =>
              l.sourceImageId.isNotEmpty &&
              l.targetImageId.isNotEmpty &&
              l.targetAnnotationId.isNotEmpty,
        )
        .toList();

    return CanvasBoardData(
      imageNodes: imageNodes,
      noteNodes: noteNodes,
      imageLinks: imageLinks,
      viewScale: (json['viewScale'] as num?)?.toDouble() ?? 1.0,
      viewTx: (json['viewTx'] as num?)?.toDouble() ?? 0.0,
      viewTy: (json['viewTy'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
