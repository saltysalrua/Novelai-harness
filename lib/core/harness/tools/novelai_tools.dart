import 'dart:io';
import 'package:intl/intl.dart';
import '../types.dart';
import '../../../data/models/novelai_models.dart';
import '../../../data/repositories/novelai_repository.dart';
import '../../../data/services/config_service.dart';
import 'agent_tool.dart';

/// 回调类型，用于生图成功后通知 UI 刷新画板
typedef OnImageGeneratedCallback = void Function(NaiGeneratedImage image);
typedef OnStreamProgressCallback = void Function(NaiStreamProgress progress);
typedef OnParamsUsedCallback = void Function(NaiGenerationParams params);

/// 付费生图确认回调：当生图参数超出 Opus 免费区间时，向用户申请确认；返回 true 则继续生成，false 则取消
typedef OnConfirmPaidGenerationCallback = Future<bool> Function({
  required NaiGenerationParams params,
  required List<String> reasons,
});

/// 1. 生图工具 (以工作台当前参数直接触发 NovelAI 官方绘图)
class NovelAiGenerateTool extends AgentTool {
  final NovelAiRepository repository;
  final ConfigService configService;
  final NaiGenerationParams Function() getCurrentParams;
  final OnImageGeneratedCallback? onGenerated;
  final OnStreamProgressCallback? onProgress;
  final OnConfirmPaidGenerationCallback? onConfirmPaidGeneration;

  NovelAiGenerateTool({
    required this.repository,
    required this.configService,
    required this.getCurrentParams,
    this.onGenerated,
    this.onProgress,
    this.onConfirmPaidGeneration,
  }) : super(
          name: 'novelai_generate',
          label: '图像生成',
          description:
              '以工作台当前的参数配置（提示词、尺寸、步数、CFG、模型等）直接触发 NovelAI 官方绘图。在调用此工具前，如需构思或调整生图提示词与尺寸，必须先通过 update_studio_parameters 工具修改工作台参数。若参数超出 Opus 免费范围，将自动向用户发出点数消耗申请。',
          parameters: const {
            'type': 'object',
            'properties': {},
          },
        );

  @override
  Future<ToolResult> execute(
      String toolCallId, Map<String, dynamic> args) async {
    try {
      final config = await configService.loadConfig();
      if (config.novelAiKey.trim().isEmpty) {
        return ToolResult(
          toolCallId: toolCallId,
          content: '错误：未配置 NovelAI API Key，请先在设置中填写 Token。',
          isError: true,
        );
      }

      final params = getCurrentParams();
      if (params.prompt.trim().isEmpty) {
        return ToolResult(
          toolCallId: toolCallId,
          content: '错误：工作台提示词为空。请先调用 update_studio_parameters 填入提示词后再触发生成。',
          isError: true,
        );
      }

      // 检查是否超出 Opus 免费区间
      if (!params.isOpusFree) {
        final reasons = <String>[];
        if (params.width * params.height > 1048576) {
          reasons.add('尺寸 ${params.width}x${params.height}（像素数超出 1,048,576 限制）');
        }
        if (params.steps > 28) {
          reasons.add('采样步数 ${params.steps} 步（超出 28 步限制）');
        }
        if (params.nSamples > 1) {
          reasons.add('生成张数 ${params.nSamples} 张（超出 1 张限制）');
        }

        if (onConfirmPaidGeneration != null) {
          final confirmed = await onConfirmPaidGeneration!(
            params: params,
            reasons: reasons,
          );
          if (!confirmed) {
            final reasonText = reasons.join('，');
            return ToolResult(
              toolCallId: toolCallId,
              content: '已取消生成：本次生图参数（$reasonText）需消耗 Anlas 点数，用户已拒绝扣费。'
                  '请先调用 update_studio_parameters 将参数调整到免费区间（如尺寸 <= 832x1216 且 步数 <= 28）或征求用户进一步指示。',
              isError: true,
            );
          }
        }
      }

      NaiGeneratedImage? resultImage;

      if (config.enableStreamPreview) {
        final stream = repository.generateStream(
          apiKey: config.novelAiKey,
          params: params,
          saveDir: config.saveDirectory,
        );

        await for (final p in stream) {
          onProgress?.call(p);
          if (p.isFinal && p.generatedImage != null) {
            resultImage = p.generatedImage;
          }
        }
      } else {
        final generatedList = await repository.generate(
          apiKey: config.novelAiKey,
          params: params,
          saveDir: config.saveDirectory,
        );
        if (generatedList.isNotEmpty) {
          resultImage = generatedList.first;
        }
      }

      if (resultImage == null) {
        return ToolResult(
          toolCallId: toolCallId,
          content: '错误：未能生成有效图像。',
          isError: true,
        );
      }

      final image = resultImage;
      onGenerated?.call(image);

      final costText = image.isOpusFree
          ? '0 Anlas (Opus 免费)'
          : '消耗点数';

      final resultBuffer = StringBuffer();
      resultBuffer.writeln('生图完成：');
      if (image.localFilePath != null) {
        resultBuffer.writeln('保存路径: ${image.localFilePath}');
      }
      resultBuffer.writeln('模型: ${params.model.label}');
      resultBuffer.writeln('尺寸: ${params.width}x${params.height}');
      resultBuffer.writeln('步数: ${params.steps} 步');
      resultBuffer.writeln('CFG: ${params.scale} (Rescale: ${params.cfgRescale})');
      resultBuffer.writeln('随机种子: ${image.seed}');
      resultBuffer.writeln('点数状态: $costText');

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
