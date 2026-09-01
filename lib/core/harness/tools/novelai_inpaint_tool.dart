import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Rect;
import '../types.dart';
import '../../../data/models/novelai_models.dart';
import '../../../data/repositories/novelai_repository.dart';
import '../../../data/services/anlas_calculator.dart';
import '../../../data/services/config_service.dart';
import '../../../data/services/inpaint_service.dart';
import 'agent_tool.dart';
import 'novelai_tools.dart';

/// 归一化两点矩形：钳制 0~1 并自动纠正坐标乱序 (模型给出的
/// [ymin, xmin, ymax, xmax] 或 left/top/width/h 都不保证有序合法)
Rect normalizeRectPoints(double x1, double y1, double x2, double y2) {
  final left = x1.clamp(0.0, 1.0);
  final right = x2.clamp(0.0, 1.0);
  final top = y1.clamp(0.0, 1.0);
  final bottom = y2.clamp(0.0, 1.0);
  return Rect.fromLTRB(
    math.min(left, right),
    math.min(top, bottom),
    math.max(left, right),
    math.max(top, bottom),
  );
}

/// 解析工具 rect 参数为归一化矩形，支持两种写法：
/// - [ymin, xmin, ymax, xmax] 归一化数组 (0.0~1.0)
/// - {left, top, width, height} 对象 (兼容 x/y/w/h 键名)
/// 返回 null 表示格式无法解析。
Rect? parseToolRectArg(dynamic rawRect) {
  double? toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  if (rawRect is List && rawRect.length >= 4) {
    final ymin = toDouble(rawRect[0]);
    final xmin = toDouble(rawRect[1]);
    final ymax = toDouble(rawRect[2]);
    final xmax = toDouble(rawRect[3]);
    if (ymin == null || xmin == null || ymax == null || xmax == null) {
      return null;
    }
    return normalizeRectPoints(xmin, ymin, xmax, ymax);
  }
  if (rawRect is Map) {
    final l = toDouble(rawRect['left'] ?? rawRect['x']);
    final t = toDouble(rawRect['top'] ?? rawRect['y']);
    final w = toDouble(rawRect['width'] ?? rawRect['w']);
    final h = toDouble(rawRect['height'] ?? rawRect['h']);
    if (l == null || t == null || w == null || h == null) return null;
    return normalizeRectPoints(l, t, l + w, t + h);
  }
  return null;
}

/// 图钉锚点转修复选区时的半边长 (归一化，短边的 12% 边长)
const double kPointAnnotationHalfExtent = 0.06;

/// 在批注列表中解析 annotation_id 对应的修复选区 (批注 ↔ 修复联动)：
/// - 矩形批注：直接使用其选区
/// - 图钉锚点：转为以锚点为中心的小选区 (边长 12% 短边)
/// - 整图批注：返回错误 (无具体位置)
/// 返回 record：rect 为 null 且 error 非空时表示不可用。
({Rect? rect, String? error}) resolveAnnotationSelection(
  List<ImageAnnotation> annotations,
  String annotationId,
) {
  ImageAnnotation? found;
  for (final ann in annotations) {
    if (ann.id == annotationId) {
      found = ann;
      break;
    }
  }
  if (found == null) {
    return (
      rect: null,
      error:
          '未在目标图片上找到批注 $annotationId。可先调用 view_image_annotations 查看批注列表与其 ID。',
    );
  }
  switch (found.type) {
    case AnnotationType.rect:
      final r = found.rect;
      if (r == null) {
        return (rect: null, error: '批注 $annotationId 是矩形选区但缺少坐标数据。');
      }
      return (rect: r, error: null);
    case AnnotationType.point:
      final p = found.point;
      if (p == null) {
        return (rect: null, error: '批注 $annotationId 是图钉锚点但缺少坐标数据。');
      }
      return (
        rect: normalizeRectPoints(
          p.dx - kPointAnnotationHalfExtent,
          p.dy - kPointAnnotationHalfExtent,
          p.dx + kPointAnnotationHalfExtent,
          p.dy + kPointAnnotationHalfExtent,
        ),
        error: null,
      );
    case AnnotationType.global:
      return (
        rect: null,
        error:
            '批注 $annotationId 是整图修改意见，没有具体位置，无法直接作为修复选区。请改用 rect 参数，或先添加矩形/图钉批注。',
      );
  }
}

/// 局部修复 / 焦点特写重绘工具
class NovelAiInpaintTool extends AgentTool {
  final NovelAiRepository _repository;
  final ConfigService _configService;
  final NaiGenerationParams Function() _getCurrentParams;
  final OnImageGeneratedCallback? _onGenerated;
  final OnStreamProgressCallback? _onProgress;
  final OnConfirmPaidGenerationCallback? _onConfirmPaidGeneration;
  final CurrentAccountInfoGetter? _getAccountInfo;
  final OnBeforeGenerateCallback? _onBeforeGenerate;

  NovelAiInpaintTool({
    required this._repository,
    required this._configService,
    required this._getCurrentParams,
    this._onGenerated,
    this._onProgress,
    this._onConfirmPaidGeneration,
    this._getAccountInfo,
    this._onBeforeGenerate,
  }) : super(
         name: 'novelai_inpaint',
         label: '局部修复 / 焦点特写重绘',
         description:
             '对画板图片或指定本地图片执行局部重绘 (Inpaint) 或高分辨率焦点特写修复 (Focus Inpaint)。\n'
             '在 focus 模式下，算法会自动将选区扩展外延上下文 (Context Padding) 并等比上采样至 1MP (1024x1024) 潜空间，'
             '经 NovelAI 官方 infill 渲染后再高精度无损贴回原图，极大提升眼睛、面部、手部与服饰细节且享受 Opus 免费。\n'
             '修复区域二选一：rect 坐标 ([ymin, xmin, ymax, xmax] 或 {left, top, width, height})，'
             '或 annotation_id 复用画板既有批注 (矩形批注直用其选区，图钉锚点自动转为以锚点为中心的小选区；'
             '未显式传 prompt 时批注文字会自动作为修复提示词)。\n'
             'focus 模式必须提供 rect 或 annotation_id (整图重绘请用 standard 模式)。',
         parameters: {
           'type': 'object',
           'properties': {
             'mode': {
               'type': 'string',
               'enum': ['focus', 'standard'],
               'description': '修复模式：focus (焦点特写修复，默认) 或 standard (常规局部重绘)',
             },
             'rect': {
               'description':
                   '待修复选区坐标，支持 [ymin, xmin, ymax, xmax] 归一化数组 (0.0~1.0) 或包含 left/top/width/height 的对象',
             },
             'annotation_id': {
               'type': 'string',
               'description':
                   '画板上既有批注的 ID (矩形批注直用其选区；图钉锚点自动转为以锚点为中心的小选区；未传 prompt 时批注文字自动作为修复提示词)',
             },
             'prompt': {
               'type': 'string',
               'description': '局部修复的正向提示词 (留空则复用工作台当前提示词)',
             },
             'negative_prompt': {
               'type': 'string',
               'description': '局部修复的负向提示词 (留空则复用工作台当前负向词)',
             },
             'strength': {
               'type': 'number',
               'description': '重绘去噪强度 (0.0 ~ 1.0，默认 0.70)',
             },
             'noise': {
               'type': 'number',
               'description': '重绘附加噪声 (0.0 ~ 1.0，默认 0.00)',
             },
             'context_padding': {
               'type': 'number',
               'description': '焦点特写模式下的外延上下文内边距像素 (默认 64，范围 16~192)',
             },
             'image_index': {
               'type': 'integer',
               'description': '历史图片索引 (0 表示最新图，1 表示次新图，默认 0)',
             },
             'image_path': {
               'type': 'string',
               'description': '本地图片绝对路径 (若指定则优先使用该图片)',
             },
           },
         },
       );

  @override
  Future<ToolResult> execute(
    String toolCallId,
    Map<String, dynamic> args,
  ) async {
    try {
      final config = await _configService.loadConfig();
      if (config.novelAiKey.trim().isEmpty) {
        return ToolResult(
          toolCallId: toolCallId,
          content: '错误：未配置 NovelAI API Key，请先在设置中填写 Token。',
          isError: true,
        );
      }

      // 1. 解析目标底图
      NaiGeneratedImage? targetImage;
      final imagePath = args['image_path'] as String?;
      if (imagePath != null && imagePath.isNotEmpty) {
        final file = File(imagePath);
        if (file.existsSync()) {
          final bytes = file.readAsBytesSync();
          final dims = await AnlasCalculator.decodeImageDimensions(bytes);
          targetImage = NaiGeneratedImage(
            id: 'file_${DateTime.now().millisecondsSinceEpoch}',
            bytes: bytes,
            localFilePath: imagePath,
            params: NaiGenerationParams(
              prompt: '',
              width: dims?.width ?? 1024,
              height: dims?.height ?? 1024,
            ),
            createdAt: DateTime.now(),
            seed: 0,
            isOpusFree: false,
          );
        }
      }

      if (targetImage == null) {
        final imageIndex = (args['image_index'] as num?)?.toInt() ?? 0;
        if (_repository.history.isNotEmpty) {
          final validIndex = imageIndex.clamp(
            0,
            _repository.history.length - 1,
          );
          targetImage = _repository.history[validIndex];
        }
      }

      if (targetImage == null) {
        return ToolResult(
          toolCallId: toolCallId,
          content: '错误：未找到可供修复的底图，请先生成图片或提供本地图片路径。',
          isError: true,
        );
      }

      // 2. 解析选区 Rect：annotation_id 联动画板批注，rect 参数显式坐标
      Rect? selectionRect;
      String? annotationIdUsed;
      String? annotationNote;
      final annotationId = args['annotation_id'] as String?;
      if (annotationId != null && annotationId.isNotEmpty) {
        final resolved = resolveAnnotationSelection(
          targetImage.annotations,
          annotationId,
        );
        if (resolved.error != null) {
          return ToolResult(
            toolCallId: toolCallId,
            content: '错误：$resolved.error',
            isError: true,
          );
        }
        selectionRect = resolved.rect;
        annotationIdUsed = annotationId;
        final matched = targetImage.annotations
            .where((a) => a.id == annotationId)
            .first;
        final note = matched.note.trim();
        if (note.isNotEmpty) annotationNote = note;
      }

      if (selectionRect == null && args['rect'] != null) {
        selectionRect = parseToolRectArg(args['rect']);
        if (selectionRect == null) {
          return ToolResult(
            toolCallId: toolCallId,
            content:
                '错误：rect 参数格式无法解析。支持 [ymin, xmin, ymax, xmax] 归一化数组或包含 left/top/width/height 的对象。',
            isError: true,
          );
        }
      }

      final modeStr = args['mode'] as String? ?? 'focus';
      final mode = InpaintMode.fromId(modeStr);

      // focus 模式必须有修复区域 (与 UI 行为一致，禁止静默回退到图片中心)
      if (mode == InpaintMode.focus && selectionRect == null) {
        return ToolResult(
          toolCallId: toolCallId,
          content:
              '错误：focus 模式需要通过 rect 或 annotation_id 指定待修复区域。若想整图重绘请改用 standard 模式。',
          isError: true,
        );
      }

      final contextPadding =
          (args['context_padding'] as num?)?.toDouble() ?? 64.0;
      final strength = (args['strength'] as num?)?.toDouble() ?? 0.70;
      final noise = (args['noise'] as num?)?.toDouble() ?? 0.00;
      final customPrompt = args['prompt'] as String?;
      final customNegative = args['negative_prompt'] as String?;

      // 批注联动：未显式传 prompt 时，批注文字自动作为修复提示词
      // (与 UI「批注发送到修复」同语义)
      final effectivePrompt =
          (customPrompt != null && customPrompt.trim().isNotEmpty)
          ? customPrompt
          : annotationNote;

      final inpaintParams = InpaintParams(
        mode: mode,
        selectionRect: selectionRect,
        contextPadding: contextPadding,
        strength: strength,
        noise: noise,
        customPrompt: effectivePrompt ?? '',
        customNegativePrompt: customNegative ?? '',
        useMainPrompt:
            effectivePrompt == null || effectivePrompt.trim().isEmpty,
        useMainNegative:
            customNegative == null || customNegative.trim().isEmpty,
      );

      final currentParams = _getCurrentParams();

      // 3. 计算几何与点数估算闸门
      final targetBytes = Uint8List.fromList(targetImage.bytes);
      final resolvedDims = await AnlasCalculator.decodeImageDimensions(
        targetBytes,
      );
      final srcW = resolvedDims?.width ?? targetImage.params.width;
      final srcH = resolvedDims?.height ?? targetImage.params.height;

      final InpaintGeometry geometry;
      if (mode == InpaintMode.focus) {
        final sel = selectionRect!;
        final pixelRect = Rect.fromLTWH(
          sel.left * srcW,
          sel.top * srcH,
          sel.width * srcW,
          sel.height * srcH,
        );
        geometry = InpaintService.resolveGeometry(
          sourceWidth: srcW,
          sourceHeight: srcH,
          selectionRect: pixelRect,
          contextPadding: contextPadding,
        );
      } else {
        final reqSize = InpaintService.resolveStandardRequestSize(srcW, srcH);
        geometry = InpaintGeometry(
          focusBounds: Rect.fromLTWH(0, 0, srcW.toDouble(), srcH.toDouble()),
          contextCrop: Rect.fromLTWH(0, 0, srcW.toDouble(), srcH.toDouble()),
          requestWidth: reqSize.width,
          requestHeight: reqSize.height,
          scale: 1.0,
        );
      }

      final isOpusFree =
          geometry.requestArea <= 1048576 && currentParams.steps <= 28;
      var account = _getAccountInfo?.call();
      if (account == null && !isOpusFree) {
        try {
          account = await _repository.fetchAccountInfo(
            apiKey: config.novelAiKey,
          );
        } catch (_) {}
      }

      final estimatedCost = isOpusFree
          ? 0
          : (account != null
                ? AnlasCalculator.estimateGenerationCost(
                    params: currentParams.copyWith(
                      width: geometry.requestWidth,
                      height: geometry.requestHeight,
                    ),
                    isOpus: account.isOpus,
                    opusQuotaExhausted: account.v5QuotaExhausted,
                  )
                : AnlasCalculator.invalidCost);

      if (estimatedCost != 0 && _onConfirmPaidGeneration != null) {
        final confirmed = await _onConfirmPaidGeneration(
          params: currentParams.copyWith(
            width: geometry.requestWidth,
            height: geometry.requestHeight,
          ),
          estimatedCost: estimatedCost,
        );
        if (!confirmed) {
          return ToolResult(
            toolCallId: toolCallId,
            content: '已取消修复：本次重绘预计消耗 $estimatedCost Anlas 点数，用户已拒绝扣费。',
            isError: true,
          );
        }
      }

      _onBeforeGenerate?.call();

      NaiGeneratedImage? resultImage;
      String? streamError;
      if (config.enableStreamPreview) {
        final stream = _repository.generateInpaintStream(
          apiKey: config.novelAiKey,
          sourceImageBytes: targetBytes,
          inpaintParams: inpaintParams,
          generationParams: currentParams,
          saveDir: config.saveDirectory,
          enablePersistence: config.enableImagePersistence,
          maxImages: config.maxPersistentImages,
          autoSave: config.autoSaveImages,
        );

        await for (final p in stream) {
          // 捕获流内显式报错 (服务端 error 帧/无成图数据)，不再只报笼统的
          // "未能生成修复图像"
          if (p.errorMessage != null) {
            streamError ??= p.errorMessage;
            continue;
          }
          _onProgress?.call(p);
          if (p.isFinal && p.generatedImage != null) {
            resultImage = p.generatedImage;
          }
        }
      } else {
        resultImage = await _repository.generateInpaint(
          apiKey: config.novelAiKey,
          sourceImageBytes: targetBytes,
          inpaintParams: inpaintParams,
          generationParams: currentParams,
          saveDir: config.saveDirectory,
          enablePersistence: config.enableImagePersistence,
          maxImages: config.maxPersistentImages,
          autoSave: config.autoSaveImages,
        );
      }

      if (resultImage == null) {
        return ToolResult(
          toolCallId: toolCallId,
          content: streamError != null ? '局部修复失败：$streamError' : '错误：未能生成修复图像。',
          isError: true,
        );
      }

      _onGenerated?.call(resultImage);

      final buffer = StringBuffer();
      buffer.writeln('局部修复完成：');
      buffer.writeln('• 模式: ${mode.label}');
      buffer.writeln('• 原图分辨率: ${srcW}x$srcH');
      if (annotationIdUsed != null) {
        buffer.writeln('• 修复区域来源: 批注 $annotationIdUsed');
        if (annotationNote != null) {
          buffer.writeln(
            '• 提示词来源: 批注文字 ("${annotationNote.length > 40 ? '${annotationNote.substring(0, 40)}...' : annotationNote}")',
          );
        }
      }
      if (mode == InpaintMode.focus) {
        buffer.writeln(
          '• 选区区域: (${geometry.focusBounds.left.round()}, ${geometry.focusBounds.top.round()}) ${geometry.focusBounds.width.round()}x${geometry.focusBounds.height.round()} px',
        );
        buffer.writeln(
          '• 外延上下文: (${geometry.contextCrop.left.round()}, ${geometry.contextCrop.top.round()}) ${geometry.contextCrop.width.round()}x${geometry.contextCrop.height.round()} px',
        );
        buffer.writeln(
          '• 请求潜空间: ${geometry.requestWidth}x${geometry.requestHeight} (${geometry.scale.toStringAsFixed(2)}x 超采样)',
        );
      }
      buffer.writeln('• 重绘强度: $strength (附加噪声: $noise)');
      buffer.writeln(
        '• 点数状态: ${isOpusFree ? '0 Anlas (Opus 免费)' : '预计 $estimatedCost Anlas'}',
      );

      return ToolResult(
        toolCallId: toolCallId,
        content: buffer.toString().trim(),
      );
    } catch (e) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '局部修复失败: $e',
        isError: true,
      );
    }
  }
}

/// 计算焦点重绘几何信息工具 (只读检查工具)
class NovelAiInpaintGeometryTool extends AgentTool {
  final NovelAiRepository _repository;

  NovelAiInpaintGeometryTool({required this._repository})
    : super(
        name: 'get_inpaint_geometry',
        label: '计算焦点修复几何信息',
        description:
            '计算指定选区在焦点特写修复下的外延上下文区域 (Context Crop)、请求放大尺寸 (Request Size) 与点数免扣状态，'
            '供 Agent 在发起正式修复前核验几何参数。rect 与 annotation_id 二选一。',
        parameters: {
          'type': 'object',
          'properties': {
            'rect': {
              'description':
                  '待修复选区坐标，支持 [ymin, xmin, ymax, xmax] 归一化数组 (0.0~1.0) 或包含 left/top/width/height 的对象',
            },
            'annotation_id': {
              'type': 'string',
              'description': '画板上既有批注的 ID (矩形批注直用其选区；图钉锚点自动转为以锚点为中心的小选区)',
            },
            'context_padding': {
              'type': 'number',
              'description': '焦点外延上下文内边距像素 (默认 64，范围 16~192)',
            },
            'image_index': {
              'type': 'integer',
              'description': '历史图片索引 (0 表示最新图，默认 0)',
            },
          },
          'required': [],
        },
      );

  @override
  Future<ToolResult> execute(
    String toolCallId,
    Map<String, dynamic> args,
  ) async {
    try {
      NaiGeneratedImage? targetImage;
      final imageIndex = (args['image_index'] as num?)?.toInt() ?? 0;
      if (_repository.history.isNotEmpty) {
        final validIndex = imageIndex.clamp(0, _repository.history.length - 1);
        targetImage = _repository.history[validIndex];
      }

      // 按实际图片字节解码尺寸 (导入图 params 可能是假宽高，不能直接信)
      var srcW = targetImage?.params.width ?? 1024;
      var srcH = targetImage?.params.height ?? 1024;
      if (targetImage != null) {
        final bytes = targetImage.bytes is Uint8List
            ? targetImage.bytes as Uint8List
            : Uint8List.fromList(targetImage.bytes);
        final dims = await AnlasCalculator.decodeImageDimensions(bytes);
        srcW = dims?.width ?? srcW;
        srcH = dims?.height ?? srcH;
      }

      // 选区解析：annotation_id 联动批注，rect 参数显式坐标，二选一
      Rect? selectionRect;
      final annotationId = args['annotation_id'] as String?;
      if (annotationId != null && annotationId.isNotEmpty) {
        if (targetImage == null) {
          return ToolResult(
            toolCallId: toolCallId,
            content: '错误：画板没有历史图片，无法解析批注 $annotationId。',
            isError: true,
          );
        }
        final resolved = resolveAnnotationSelection(
          targetImage.annotations,
          annotationId,
        );
        if (resolved.error != null) {
          return ToolResult(
            toolCallId: toolCallId,
            content: '错误：$resolved.error',
            isError: true,
          );
        }
        selectionRect = resolved.rect;
      } else if (args['rect'] != null) {
        selectionRect = parseToolRectArg(args['rect']);
        if (selectionRect == null) {
          return ToolResult(
            toolCallId: toolCallId,
            content:
                '错误：rect 参数格式无法解析。支持 [ymin, xmin, ymax, xmax] 归一化数组或包含 left/top/width/height 的对象。',
            isError: true,
          );
        }
      } else {
        return ToolResult(
          toolCallId: toolCallId,
          content: '错误：缺少 rect 或 annotation_id 参数，无法计算几何。',
          isError: true,
        );
      }
      selectionRect = selectionRect!;

      final contextPadding =
          (args['context_padding'] as num?)?.toDouble() ?? 64.0;
      final pixelRect = Rect.fromLTWH(
        selectionRect.left * srcW,
        selectionRect.top * srcH,
        selectionRect.width * srcW,
        selectionRect.height * srcH,
      );

      final geometry = InpaintService.resolveGeometry(
        sourceWidth: srcW,
        sourceHeight: srcH,
        selectionRect: pixelRect,
        contextPadding: contextPadding,
      );

      final buffer = StringBuffer();
      buffer.writeln('焦点修复几何计算结果：');
      buffer.writeln('• 原图尺寸: ${srcW}x$srcH');
      buffer.writeln(
        '• 目标选区: (${geometry.focusBounds.left.round()}, ${geometry.focusBounds.top.round()}) ${geometry.focusBounds.width.round()}x${geometry.focusBounds.height.round()} px',
      );
      buffer.writeln(
        '• 外延上下文: (${geometry.contextCrop.left.round()}, ${geometry.contextCrop.top.round()}) ${geometry.contextCrop.width.round()}x${geometry.contextCrop.height.round()} px',
      );
      buffer.writeln(
        '• API 请求尺寸: ${geometry.requestWidth}x${geometry.requestHeight} (放大倍率: ${geometry.scale.toStringAsFixed(2)}x)',
      );
      buffer.writeln(
        '• 免点保护: ${geometry.isOpusFree ? 'Opus 免费 (<= 1MP)' : '需消耗 Anlas 点数'}',
      );

      return ToolResult(
        toolCallId: toolCallId,
        content: buffer.toString().trim(),
      );
    } catch (e) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '计算几何失败: $e',
        isError: true,
      );
    }
  }
}
