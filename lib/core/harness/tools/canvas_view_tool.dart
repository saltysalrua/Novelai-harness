import 'dart:convert';
import 'dart:typed_data';

import '../../../data/models/novelai_models.dart';
import '../../../data/services/anlas_calculator.dart';
import '../types.dart';
import 'agent_tool.dart';
import 'vision_image_codec.dart';

/// 历史图片列表获取器 (从新到旧排序，索引 0 为最新生成的一张)
typedef CanvasHistoryGetter = List<NaiGeneratedImage> Function();

/// 仓储原图加载器：历史条目可能只保留缩略图，原图需从 LRU/磁盘读取。
typedef CanvasImageBytesLoader =
    Future<Uint8List?> Function(NaiGeneratedImage image);

/// 工具层不自行读盘，统一复用宿主注入的仓储原图加载管线。
Future<Uint8List?> resolveCanvasImageBytes(
  NaiGeneratedImage image,
  CanvasImageBytesLoader? loader,
) async {
  if (image.bytes.isNotEmpty) return image.bytes;
  try {
    final bytes = await loader?.call(image);
    return bytes == null || bytes.isEmpty ? null : bytes;
  } catch (_) {
    return null;
  }
}

/// 不允许空图片编码成空字符串后假报“图片已作为附件返回”。
ToolResult unavailableCanvasImageResult(String toolCallId, int index) =>
    ToolResult(
      toolCallId: toolCallId,
      content:
          '无法读取历史图片 (索引: $index) 的原图数据。文件可能已被移走、删除或无法访问；'
          '本次没有图片附件，请用户重新导入图片后再查看。',
      isError: true,
    );

/// 视觉能力检查器 (当前对话模型是否支持图像输入)
typedef ModelVisionChecker = bool Function();

/// 覆盖层渲染结果
class OverlayRenderResult {
  final Uint8List bytes;
  final int width;
  final int height;
  final bool overlayApplied;

  const OverlayRenderResult({
    required this.bytes,
    required this.width,
    required this.height,
    required this.overlayApplied,
  });
}

/// 离屏绘制角色位置覆盖层的回调签名（由数据/渲染层注入，保持 core 纯 Dart）。
typedef CharacterOverlayRenderFn =
    Future<OverlayRenderResult> Function(
      Uint8List imageBytes,
      NaiGenerationParams params, {
      int maxDimension,
      bool whiteBackground,
    });

/// 画板历史图片查看工具：按索引 (0 为最新，从新到旧) 获取已生成的图片 (可叠加角色位置覆盖层) 供 Agent 视觉检查。
class ViewCanvasImageTool extends AgentTool {
  final CanvasHistoryGetter getHistory;
  final ModelVisionChecker isModelMultimodal;
  final CanvasImageBytesLoader? loadImageBytes;
  final CharacterOverlayRenderFn? renderOverlay;

  ViewCanvasImageTool({
    required this.getHistory,
    required this.isModelMultimodal,
    this.loadImageBytes,
    this.renderOverlay,
  }) : super(
         name: 'view_canvas_image',
         label: '查看画板图片',
         description:
             '获取画板历史图片供视觉检查（index=0 为最新图；仅在用户要求审查画面时调用）。'
             '默认附带角色定位覆盖层并压缩至最长边 1024px；可传 with_overlay=false 看原图、full_resolution=true 看未压缩原尺寸。',
         parameters: const {
           'type': 'object',
           'properties': {
             'index': {
               'type': 'integer',
               'description':
                   '要查看的图片索引（从新到旧排序，0 表示最新生成的一张，1 表示倒数第二张，以此类推。默认 0）。',
             },
             'with_overlay': {
               'type': 'boolean',
               'description': '是否叠加角色位置覆盖层 (默认 true)。false 时返回原图。',
             },
             'full_resolution': {
               'type': 'boolean',
               'description':
                   '是否返回未压缩的原始尺寸图片 (默认 false，压缩到最长边 1024px)。仅在压缩版看不清细节时使用，原图会消耗更多视觉 Token。',
             },
           },
         },
       );

  @override
  Future<ToolResult> execute(
    String toolCallId,
    Map<String, dynamic> args,
  ) async {
    if (!isModelMultimodal()) {
      return ToolResult(
        toolCallId: toolCallId,
        content:
            '当前对话模型不支持图像输入，无法查看图片。请提示用户在设置中切换到具备视觉能力的多模态模型 (如 GPT-4o、Gemini、Claude)。',
        isError: true,
      );
    }

    final history = getHistory();
    if (history.isEmpty) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '画板当前没有已生成的图片历史。请先生成图片后再查看。',
        isError: true,
      );
    }

    final rawIndex = args['index'];
    final int index;
    if (rawIndex is int) {
      index = rawIndex;
    } else if (rawIndex is num) {
      index = rawIndex.toInt();
    } else if (rawIndex is String) {
      index = int.tryParse(rawIndex) ?? 0;
    } else {
      index = 0;
    }

    if (index < 0 || index >= history.length) {
      return ToolResult(
        toolCallId: toolCallId,
        content:
            '指定的图片索引 $index 超出范围。当前共有 ${history.length} 张历史图片，有效索引范围为 0 到 ${history.length - 1}（0 表示最新生成的一张，${history.length - 1} 表示最早的一张）。',
        isError: true,
      );
    }

    final targetImage = history[index];
    final imageBytes = await resolveCanvasImageBytes(
      targetImage,
      loadImageBytes,
    );
    if (imageBytes == null) {
      return unavailableCanvasImageResult(toolCallId, index);
    }

    final params = targetImage.params;
    final withOverlay = args['with_overlay'] is bool
        ? args['with_overlay'] as bool
        : true;
    final fullResolution = args['full_resolution'] is bool
        ? args['full_resolution'] as bool
        : false;

    final enabledCharacters = params.characterPrompts
        .where((c) => c.enabled)
        .toList();

    Uint8List finalBytes = imageBytes;
    var overlayApplied = false;
    String? overlayNote;

    if (withOverlay && enabledCharacters.isNotEmpty) {
      if (params.model.maxCharacterPrompts <= 0) {
        overlayNote = '当前模型 (${params.model.label}) 不支持多角色提示词，已返回原图。';
      } else if (renderOverlay == null) {
        overlayNote = '未配置覆盖层渲染器，已返回原图。';
      } else {
        try {
          final rendered = await renderOverlay!(
            imageBytes,
            params,
            maxDimension: fullResolution ? 1536 : kVisionImageMaxSide,
            whiteBackground: !fullResolution,
          );
          finalBytes = rendered.bytes;
          overlayApplied = true;
        } catch (_) {
          overlayNote = '覆盖层渲染失败，已回退返回原图。';
        }
      }
    } else if (withOverlay) {
      overlayNote = '该图片生成时没有启用的角色提示词，已返回原图。';
    }

    // 视觉附件压缩：默认压到最长边 1024px 控制视觉 Token，
    // 覆盖层已在非原图模式下一次性直出 ≤1024px 白底 PNG，无需二次编解码
    String mime = overlayApplied ? 'image/png' : sniffImageMimeType(finalBytes);
    if (!fullResolution && !overlayApplied) {
      final compressed = await compressVisionImage(finalBytes);
      finalBytes = compressed.bytes;
      mime = compressed.mimeType;
    }

    final dims = await AnlasCalculator.decodeImageDimensions(imageBytes);

    final isLatest = index == 0;
    final timeStr = targetImage.createdAt
        .toIso8601String()
        .replaceAll('T', ' ')
        .split('.')
        .first;

    final lines = <String>[
      '已获取历史图片 (索引: $index, ${isLatest ? '最新生成' : '从新到旧第 ${index + 1} 张'}，共 ${history.length} 张)${overlayApplied ? ' (已叠加角色位置覆盖层)' : ''}：',
      '• 索引编号: $index (${isLatest ? '最新图片' : '从新到旧第 ${index + 1} 张'})',
      '• 生成时间: $timeStr',
      if (targetImage.seed >= 0) '• 随机种子: ${targetImage.seed}',
      '• 图片尺寸: ${dims?.width ?? params.width}x${dims?.height ?? params.height}',
      '• 绘图模型: ${params.model.label}',
      '• 位置模式: ${params.characterAiPosition ? 'AI 自动布局 (AI\'s Choice)' : '自定义定位 (use_coords)'}',
      if (overlayApplied) ...[
        '• 启用角色: ${enabledCharacters.length} 个，锚点编号对应启用顺序',
        '• 锚点配色: 粉色=女性角色, 蓝色=男性角色, 紫色=其他；标签为角色名',
        if (!params.model.supportsFreeCharacterPositioning)
          '• V4/V4.5 网格模式: 锚点吸附到 5x5 网格格心',
      ],
      if (overlayNote != null) '• $overlayNote',
      fullResolution
          ? '• 本次为原始尺寸图片 (未压缩)。'
          : '• 本次附件已压缩到最长边 1024px。若看不清细节（小字、纹理等），请再次调用本工具并传 full_resolution: true 获取原图。',
      '图片已作为附件随本条结果返回，请直接查看图片内容进行检查。',
    ];

    return ToolResult(
      toolCallId: toolCallId,
      content: lines.join('\n'),
      imageBase64: base64Encode(finalBytes),
      imageMimeType: mime,
    );
  }
}
