import 'dart:io';
import 'dart:typed_data';

import '../types.dart';
import '../../../data/models/novelai_models.dart';
import '../../../data/repositories/novelai_repository.dart';
import '../../../data/services/anlas_calculator.dart';
import '../../../data/services/config_service.dart';
import 'agent_tool.dart';
import 'novelai_tools.dart';

/// AI 整图编辑工具：把整张图片发给外部绘图模型 (如 nano banana) 按指令重绘
///
/// 走绘图模型供应商计费 (不消耗 Anlas 点数)；供应商与模型在
/// 设置 → Models 页「AI 整图编辑」中单独配置，独立于对话 LLM。
class AiEditImageTool extends AgentTool {
  final NovelAiRepository _repository;
  final ConfigService _configService;
  final OnImageGeneratedCallback? _onGenerated;
  final OnBeforeGenerateCallback? _onBeforeGenerate;

  AiEditImageTool({
    required this._repository,
    required this._configService,
    this._onGenerated,
    this._onBeforeGenerate,
  }) : super(
         name: 'ai_edit_image',
         label: 'AI 整图编辑',
         description:
             '把整张图片原样发给外部绘图模型 (如 nano banana / gpt-image)，'
             '按自然语言修改指令重绘整张图片。\n'
             '适用场景：全局风格转换、整体构图调整、大幅改动多处区域、'
             '按文字描述改画 (NovelAI 局部修复只擅长小区域细节重绘，整图级改动请用本工具)。\n'
             '不消耗 Anlas 点数，计费走绘图模型供应商 (需在设置 Models 页配置)。\n'
             'prompt 必须是清晰的自然语言修改指令 (如 "把背景换成夕阳下的海滩，保持人物不变")，'
             '不要堆 Danbooru 标签。未传 prompt 时复用工作台当前提示词。',
         parameters: {
           'type': 'object',
           'properties': {
             'prompt': {
               'type': 'string',
               'description': '自然语言修改指令，描述想把整张图片改成什么样 (留空则复用工作台当前提示词)',
             },
             'aspect_ratio': {
               'type': 'string',
               'enum': [
                 'auto',
                 '1:1',
                 '2:3',
                 '3:2',
                 '3:4',
                 '4:3',
                 '4:5',
                 '5:4',
                 '9:16',
                 '16:9',
                 '21:9',
               ],
               'description': '生图比例，auto 或留空 = 跟随原图；不同绘图模型支持的子集不同，不被支持的值会被忽略',
             },
             'resolution': {
               'type': 'string',
               'enum': ['1K', '2K', '4K'],
               'description':
                   '生图分辨率档位，留空 = 默认 (1K)；仅部分模型 (如 Gemini 3 Pro Image) 支持 2K/4K',
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
           'required': [],
         },
       );

  @override
  Future<ToolResult> execute(
    String toolCallId,
    Map<String, dynamic> args,
  ) async {
    try {
      final config = await _configService.loadConfig();
      final provider = config.imageEditProvider;
      if (provider == null) {
        return ToolResult(
          toolCallId: toolCallId,
          content:
              '错误：未配置 AI 整图编辑的绘图模型。请先在设置 → Models 页「AI 整图编辑」'
              '选择具备图像输出能力的供应商与模型 (如 nano banana / gpt-image)。',
          isError: true,
        );
      }
      if (provider.apiKey.trim().isEmpty) {
        return ToolResult(
          toolCallId: toolCallId,
          content: '错误：绘图模型供应商「${provider.name}」未配置 API Key。',
          isError: true,
        );
      }

      // 1. 解析目标底图
      NaiGeneratedImage? targetImage;
      final imagePath = args['image_path'] as String?;
      if (imagePath != null && imagePath.isNotEmpty) {
        final file = File(imagePath);
        if (!file.existsSync()) {
          return ToolResult(
            toolCallId: toolCallId,
            content: '错误：本地图片不存在: $imagePath',
            isError: true,
          );
        }
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
          content: '错误：未找到可供编辑的底图，请先生成图片或提供本地图片路径。',
          isError: true,
        );
      }

      final promptArg = args['prompt'] as String?;
      final prompt = (promptArg != null && promptArg.trim().isNotEmpty)
          ? promptArg
          : targetImage.params.prompt;

      if (prompt.trim().isEmpty) {
        return ToolResult(
          toolCallId: toolCallId,
          content: '错误：缺少修改指令。请在 prompt 参数中描述要把整张图片改成什么样。',
          isError: true,
        );
      }

      // 生图比例与分辨率 (auto = 跟随原图)
      final aspectArg = args['aspect_ratio'] as String?;
      final aspectRatio = (aspectArg == null || aspectArg == 'auto')
          ? ''
          : aspectArg;
      final resolution = args['resolution'] as String? ?? '';

      _onBeforeGenerate?.call();

      final result = await _repository.editImageAi(
        provider: provider,
        modelId: config.imageEditModelId,
        prompt: prompt,
        sourceImageBytes: Uint8List.fromList(targetImage.bytes),
        generationParams: targetImage.params,
        aspectRatio: aspectRatio,
        imageResolution: resolution,
        saveDir: config.saveDirectory,
        enablePersistence: config.enableImagePersistence,
        maxImages: config.maxPersistentImages,
        stripMetadata: config.stripMetadata,
        enableWatermark: config.enableWatermark,
        keepOriginalImage: config.keepOriginalImage,
        watermarkConfig: config.watermarkConfig,
        watermarkBytes: config.watermarkConfig.imageBytes,
        autoSave: config.autoSaveImages,
      );

      _onGenerated?.call(result);

      final buffer = StringBuffer();
      buffer.writeln('AI 整图编辑完成：');
      buffer.writeln('• 绘图模型: ${provider.name} / ${config.imageEditModelId}');
      buffer.writeln(
        '• 修改指令: ${prompt.length > 60 ? '${prompt.substring(0, 60)}...' : prompt}',
      );
      if (aspectRatio.isNotEmpty) {
        buffer.writeln('• 生图比例: $aspectRatio');
      }
      if (resolution.isNotEmpty) {
        buffer.writeln('• 生图分辨率: $resolution');
      }
      buffer.writeln('• 结果分辨率: ${result.params.width}x${result.params.height}');
      buffer.writeln('• 点数状态: 不消耗 Anlas (计费走绘图模型供应商)');
      if (result.localFilePath != null) {
        buffer.writeln('• 本地文件: ${result.localFilePath}');
      }

      return ToolResult(
        toolCallId: toolCallId,
        content: buffer.toString().trim(),
      );
    } catch (e) {
      return ToolResult(
        toolCallId: toolCallId,
        content: 'AI 整图编辑失败: $e',
        isError: true,
      );
    }
  }
}
