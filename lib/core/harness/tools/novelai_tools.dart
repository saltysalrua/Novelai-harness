import 'dart:io';
import 'package:intl/intl.dart';
import '../types.dart';
import '../../../data/models/novelai_models.dart';
import '../../../data/repositories/novelai_repository.dart';
import '../../../data/services/config_service.dart';
import 'agent_tool.dart';

/// 回调类型，用于生图成功后通知 UI 刷新画板
typedef OnImageGeneratedCallback = void Function(NaiGeneratedImage image);

/// 1. 生图工具
class NovelAiGenerateTool extends AgentTool {
  final NovelAiRepository _repository;
  final ConfigService _configService;
  final OnImageGeneratedCallback? _onGenerated;

  NovelAiGenerateTool({
    required this._repository,
    required this._configService,
    this._onGenerated,
  })  : super(
          name: 'novelai_generate',
          label: 'NovelAI 图像生成',
          description:
              '调用 NovelAI 官方绘图接口生成插画。支持自然语言散文、Danbooru 标签、漫画分镜构图以及多角色 | 隔离语法。',
          parameters: {
            'type': 'object',
            'properties': {
              'prompt': {
                'type': 'string',
                'description': '正向提示词描述（支持自然语言、漫画分镜描述、Danbooru 标签或多角色隔离语法）',
              },
              'resolution_preset': {
                'type': 'string',
                'enum': [
                  'portrait',
                  'landscape',
                  'square',
                  'wallpaper',
                  'portrait_large',
                  'landscape_large'
                ],
                'description':
                    '分辨率预设：portrait(832x1216, Opus免费), landscape(1216x832, Opus免费), square(1024x1024, Opus免费), wallpaper(1920x1088)',
              },
              'width': {
                'type': 'integer',
                'description': '自定义宽度 (自动64对齐，如 832, 1024, 1216)',
              },
              'height': {
                'type': 'integer',
                'description': '自定义高度 (自动64对齐，如 1216, 832, 1024)',
              },
              'model': {
                'type': 'string',
                'enum': [
                  'nai-diffusion-5-full',
                  'nai-diffusion-5-curated',
                  'nai-diffusion-4-5-full',
                  'nai-diffusion-4-5-curated',
                  'nai-diffusion-4-full',
                  'nai-diffusion-3'
                ],
                'description': '指定绘画模型 (默认 nai-diffusion-5-full)',
              },
              'steps': {
                'type': 'integer',
                'description': '采样步数 (1~50，默认28，<=28符合Opus免费区间)',
              },
              'scale': {
                'type': 'number',
                'description': 'CFG Scale 提示词引导强度 (1.0~15.0，默认5.0)',
              },
              'cfg_rescale': {
                'type': 'number',
                'description': 'CFG Rescale 色彩过曝抗焦黑修正 (0.0~1.0，推荐0.0或0.15)',
              },
              'sampler': {
                'type': 'string',
                'enum': [
                  'k_euler',
                  'k_euler_ancestral',
                  'k_dpmpp_2m',
                  'k_dpmpp_sde'
                ],
                'description': '采样算法',
              },
              'seed': {
                'type': 'integer',
                'description': '随机种子 (留空则随机生成)',
              },
            },
            'required': ['prompt'],
          },
        );

  @override
  Future<ToolResult> execute(
      String toolCallId, Map<String, dynamic> args) async {
    try {
      final config = await _configService.loadConfig();
      if (config.novelAiKey.trim().isEmpty) {
        return ToolResult(
          toolCallId: toolCallId,
          content: '错误：未配置 NovelAI API Key，请先在设置中填写 Token。',
          isError: true,
        );
      }

      final prompt = args['prompt'] as String? ?? '';
      if (prompt.trim().isEmpty) {
        return ToolResult(
          toolCallId: toolCallId,
          content: '错误：生图提示词不能为空。',
          isError: true,
        );
      }

      // 解析分辨率
      int w = config.customWidth;
      int h = config.customHeight;
      final presetKey = args['resolution_preset'] as String?;
      if (presetKey != null) {
        final preset = ResolutionPreset.fromKey(presetKey);
        w = preset.width;
        h = preset.height;
      } else {
        if (args['width'] is num) {
          w = ((args['width'] as num).toInt() ~/ 64) * 64;
        }
        if (args['height'] is num) {
          h = ((args['height'] as num).toInt() ~/ 64) * 64;
        }
      }
      w = w.clamp(64, 2048);
      h = h.clamp(64, 2048);

      final modelStr = args['model'] as String?;
      final model = modelStr != null
          ? NaiModel.fromId(modelStr)
          : config.defaultModel;

      final steps = (args['steps'] as num?)?.toInt() ?? config.defaultSteps;
      final scale = (args['scale'] as num?)?.toDouble() ?? config.defaultScale;
      final cfgRescale =
          (args['cfg_rescale'] as num?)?.toDouble() ?? config.defaultCfgRescale;

      final samplerStr = args['sampler'] as String?;
      final sampler = samplerStr != null
          ? NaiSampler.fromId(samplerStr)
          : config.defaultSampler;

      final seed = (args['seed'] as num?)?.toInt() ?? -1;

      final params = NaiGenerationParams(
        prompt: prompt,
        negativePrompt: config.negativePrompt,
        model: model,
        width: w,
        height: h,
        steps: steps,
        scale: scale,
        cfgRescale: cfgRescale,
        sampler: sampler,
        noiseSchedule: config.defaultNoiseSchedule,
        seed: seed,
        prefixPrompt: config.prefixPrompt,
        suffixPrompt: config.suffixPrompt,
      );

      final generatedList = await _repository.generate(
        apiKey: config.novelAiKey,
        params: params,
        saveDir: config.saveDirectory,
      );

      if (generatedList.isEmpty) {
        return ToolResult(
          toolCallId: toolCallId,
          content: '错误：未能生成有效图像。',
          isError: true,
        );
      }

      final image = generatedList.first;
      _onGenerated?.call(image);

      final costText = image.isOpusFree
          ? '0 Anlas (Opus 免费区间)'
          : '消耗 Anlas 点数 (超出免费尺寸或步数)';

      final resultBuffer = StringBuffer();
      resultBuffer.writeln('生图完成：');
      if (image.localFilePath != null) {
        resultBuffer.writeln('保存路径: ${image.localFilePath}');
      }
      resultBuffer.writeln('模型: ${model.label}');
      resultBuffer.writeln('尺寸: ${w}x$h');
      resultBuffer.writeln('步数: $steps 步');
      resultBuffer.writeln('CFG: $scale (Rescale: $cfgRescale)');
      resultBuffer.writeln('随机种子: ${image.seed}');
      resultBuffer.writeln('点数消耗: $costText');

      return ToolResult(
        toolCallId: toolCallId,
        content: resultBuffer.toString().trim(),
      );
    } catch (e) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '生图失败: $e',
        isError: true,
      );
    }
  }
}

/// 2. 图像放大工具
class NovelAiUpscaleTool extends AgentTool {
  final NovelAiRepository _repository;
  final ConfigService _configService;
  final OnImageGeneratedCallback? _onUpscaled;

  NovelAiUpscaleTool({
    required this._repository,
    required this._configService,
    this._onUpscaled,
  })  : super(
          name: 'novelai_upscale',
          label: 'NovelAI 图像超分放大',
          description: '调用 NovelAI 官方超分算法将指定图片无损放大 2 倍或 4 倍。',
          parameters: {
            'type': 'object',
            'properties': {
              'image_path': {
                'type': 'string',
                'description': '待放大的本地图片路径（留空则默认放大画板中的最新图像）',
              },
              'scale': {
                'type': 'integer',
                'enum': [2, 4],
                'description': '放大倍数 (2 或 4，默认 4)',
              },
            },
          },
        );

  @override
  Future<ToolResult> execute(
      String toolCallId, Map<String, dynamic> args) async {
    try {
      final config = await _configService.loadConfig();
      if (config.novelAiKey.trim().isEmpty) {
        return ToolResult(
          toolCallId: toolCallId,
          content: '错误：未配置 NovelAI API Key。',
          isError: true,
        );
      }

      final imagePath = args['image_path'] as String?;
      final scale = (args['scale'] as num?)?.toInt() ?? 4;

      NaiGeneratedImage? targetImage;
      if (imagePath != null && imagePath.isNotEmpty) {
        final file = File(imagePath);
        if (file.existsSync()) {
          final bytes = file.readAsBytesSync();
          targetImage = NaiGeneratedImage(
            id: 'file_${DateTime.now().millisecondsSinceEpoch}',
            bytes: bytes,
            localFilePath: imagePath,
            params: const NaiGenerationParams(prompt: 'Upscaled Image'),
            createdAt: DateTime.now(),
            seed: 0,
            isOpusFree: false,
          );
        }
      }

      if (targetImage == null && _repository.history.isNotEmpty) {
        targetImage = _repository.history.first;
      }

      if (targetImage == null) {
        return ToolResult(
          toolCallId: toolCallId,
          content: '错误：未找到可放大的图像，请先生成或提供图片路径。',
          isError: true,
        );
      }

      final upscaled = await _repository.upscale(
        apiKey: config.novelAiKey,
        sourceImage: targetImage,
        scale: scale,
        saveDir: config.saveDirectory,
      );

      _onUpscaled?.call(upscaled);

      return ToolResult(
        toolCallId: toolCallId,
        content: '图像超分放大完成 (${scale}x)\n保存路径: ${upscaled.localFilePath ?? '内存中'}',
      );
    } catch (e) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '图像放大失败: $e',
        isError: true,
      );
    }
  }
}

/// 3. Tag 联想工具
class NovelAiSuggestTagsTool extends AgentTool {
  final NovelAiRepository _repository;
  final ConfigService _configService;

  NovelAiSuggestTagsTool({
    required this._repository,
    required this._configService,
  })  : super(
          name: 'novelai_suggest_tags',
          label: 'NovelAI 标签联想',
          description: '查询官方 Danbooru Tag 联想补全与使用频次。',
          parameters: {
            'type': 'object',
            'properties': {
              'query': {
                'type': 'string',
                'description': '要查询的标签前缀或关键词（例如 silver hair, cat ears）',
              },
            },
            'required': ['query'],
          },
        );

  @override
  Future<ToolResult> execute(
      String toolCallId, Map<String, dynamic> args) async {
    try {
      final config = await _configService.loadConfig();
      final query = args['query'] as String? ?? '';
      if (query.trim().isEmpty) {
        return ToolResult(
          toolCallId: toolCallId,
          content: '错误：查询词不能为空。',
          isError: true,
        );
      }

      final tags = await _repository.suggestTags(
        apiKey: config.novelAiKey,
        query: query,
      );

      if (tags.isEmpty) {
        return ToolResult(
          toolCallId: toolCallId,
          content: '未找到与 "$query" 相关的官方标签。',
        );
      }

      final buffer = StringBuffer();
      buffer.writeln('找到以下标签建议：');
      for (final t in tags.take(10)) {
        buffer.writeln('- ${t.tag} (用量: ${t.count}, 匹配度: ${(t.confidence * 100).toStringAsFixed(1)}%)');
      }

      return ToolResult(
        toolCallId: toolCallId,
        content: buffer.toString().trim(),
      );
    } catch (e) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '标签查询失败: $e',
        isError: true,
      );
    }
  }
}

/// 4. 账号状态与体力查询工具
class NovelAiAccountInfoTool extends AgentTool {
  final NovelAiRepository _repository;
  final ConfigService _configService;

  NovelAiAccountInfoTool({
    required this._repository,
    required this._configService,
  })  : super(
          name: 'novelai_account_info',
          label: 'NovelAI 账号与体力查询',
          description: '查询当前 NovelAI 账号的订阅等级、Anlas 点数余额以及 V5 专属体力池余量。',
          parameters: {
            'type': 'object',
            'properties': {},
          },
        );

  @override
  Future<ToolResult> execute(
      String toolCallId, Map<String, dynamic> args) async {
    try {
      final config = await _configService.loadConfig();
      if (config.novelAiKey.trim().isEmpty) {
        return ToolResult(
          toolCallId: toolCallId,
          content: '错误：未配置 NovelAI API Key。',
          isError: true,
        );
      }

      final info = await _repository.fetchAccountInfo(apiKey: config.novelAiKey);

      final buffer = StringBuffer();
      buffer.writeln('NovelAI 账号状态：');
      buffer.writeln('• 订阅等级: ${info.tierName}');
      buffer.writeln('• 账号状态: ${info.active ? '激活中' : '未激活'}');
      if (info.expiresAt != null) {
        buffer.writeln('• 会员到期时间: ${DateFormat('yyyy-MM-dd HH:mm').format(info.expiresAt!)}');
      }
      buffer.writeln('• V5 专属体力池: ${info.staminaPercent.toStringAsFixed(1)}%');
      if (info.timeUntilNextPercent > 0) {
        buffer.writeln('• 体力恢复: ${info.timeUntilNextPercent} 秒后 +1%');
      }
      buffer.writeln('• 总可用 Anlas: ${info.totalAnlas} (赠送: ${info.fixedAnlas}, 购买: ${info.purchasedAnlas})');

      return ToolResult(
        toolCallId: toolCallId,
        content: buffer.toString().trim(),
      );
    } catch (e) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '查询账号失败: $e',
        isError: true,
      );
    }
  }
}
