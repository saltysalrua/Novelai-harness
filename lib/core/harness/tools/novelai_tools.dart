import 'dart:io';
import 'package:intl/intl.dart';
import '../types.dart';
import '../../../data/models/novelai_models.dart';
import '../../../data/repositories/novelai_repository.dart';
import '../../../data/services/anlas_calculator.dart';
import '../../../data/services/config_service.dart';
import 'agent_tool.dart';

/// 回调类型，用于生图成功后通知 UI 刷新画板
typedef OnImageGeneratedCallback = void Function(NaiGeneratedImage image);
typedef OnStreamProgressCallback = void Function(NaiStreamProgress progress);
typedef OnParamsUsedCallback = void Function(NaiGenerationParams params);

/// 回调类型：生图请求真正发出前通知 UI
/// (供工作台在发起前捕获"是否正在看最新图"快照，与手动生图同语义)
typedef OnBeforeGenerateCallback = void Function();

/// 回调类型：获取当前已缓存的账号信息 (可能为 null，表示未加载)
typedef CurrentAccountInfoGetter = NaiAccountInfo? Function();

/// 付费生图确认回调：当预计消耗非零时，向用户申请确认；返回 true 则继续生成，false 则取消
typedef OnConfirmPaidGenerationCallback =
    Future<bool> Function({
      required NaiGenerationParams params,
      required int estimatedCost,
    });

/// 付费超分确认回调：当超分预计消耗非零时，向用户申请确认；返回 true 则继续，false 则取消
typedef OnConfirmPaidUpscaleCallback =
    Future<bool> Function({
      required int estimatedCost,
      required int inputWidth,
      required int inputHeight,
    });

/// 构建付费生图的原因说明 (供确认弹问与取消提示共用)
///
/// 参数超出 Opus 免费区间时列出具体原因；参数在免费区间内但仍需扣费时
/// (非 Opus 订阅或 V5 体力透支)，返回空列表由调用方补充说明。
List<String> buildPaidGenerationReasons(NaiGenerationParams params) {
  final reasons = <String>[];
  if (params.width * params.height > AnlasCalculator.opusFreeMaxPixels) {
    reasons.add(
      '尺寸 ${params.width}x${params.height}（像素数超出 ${AnlasCalculator.opusFreeMaxPixels} 限制）',
    );
  }
  if (params.steps > AnlasCalculator.opusFreeMaxSteps) {
    reasons.add(
      '采样步数 ${params.steps} 步（超出 ${AnlasCalculator.opusFreeMaxSteps} 步限制）',
    );
  }
  if (params.nSamples > 1) {
    reasons.add('生成张数 ${params.nSamples} 张（超出 1 张限制）');
  }
  return reasons;
}

/// 1. 生图工具 (以工作台当前参数直接触发 NovelAI 官方绘图)
class NovelAiGenerateTool extends AgentTool {
  final NovelAiRepository repository;
  final ConfigService configService;
  final NaiGenerationParams Function() getCurrentParams;
  final OnImageGeneratedCallback? onGenerated;
  final OnStreamProgressCallback? onProgress;
  final OnConfirmPaidGenerationCallback? onConfirmPaidGeneration;
  final CurrentAccountInfoGetter? getAccountInfo;
  final OnBeforeGenerateCallback? onBeforeGenerate;

  NovelAiGenerateTool({
    required this.repository,
    required this.configService,
    required this.getCurrentParams,
    this.onGenerated,
    this.onProgress,
    this.onConfirmPaidGeneration,
    this.getAccountInfo,
    this.onBeforeGenerate,
  }) : super(
         name: 'novelai_generate',
         label: '图像生成',
         description:
             '以工作台当前的参数配置（提示词、尺寸、步数、CFG、模型等）直接触发 NovelAI 官方绘图。在调用此工具前，如需构思或调整生图提示词与尺寸，必须先通过 update_studio_parameters 工具修改工作台参数。若预计消耗非零（超出 Opus 免费区间、非 Opus 订阅或 V5 体力透支），将自动向用户发出点数消耗申请。',
         parameters: const {'type': 'object', 'properties': {}},
       );

  @override
  Future<ToolResult> execute(
    String toolCallId,
    Map<String, dynamic> args,
  ) async {
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

      // 预计消耗闸门: 账号信息未加载且参数超出免费区间时先在线拉取，避免误判
      var account = getAccountInfo?.call();
      if (account == null && !params.isOpusFree) {
        try {
          account = await repository.fetchAccountInfo(
            apiKey: config.novelAiKey,
          );
        } catch (_) {
          // 拉取失败时按保守策略继续 (走参数区间判定)
        }
      }
      final estimatedCost = account != null
          ? AnlasCalculator.estimateGenerationCost(
              params: params,
              isOpus: account.isOpus,
              opusQuotaExhausted: account.v5QuotaExhausted,
            )
          : (params.isOpusFree ? 0 : AnlasCalculator.invalidCost);

      // 检查是否需要扣费: 预计消耗非零时向用户申请确认
      if (estimatedCost != 0) {
        if (onConfirmPaidGeneration != null) {
          final confirmed = await onConfirmPaidGeneration!(
            params: params,
            estimatedCost: estimatedCost,
          );
          if (!confirmed) {
            final reasons = buildPaidGenerationReasons(params);
            final reasonText = estimatedCost > 0
                ? (reasons.isEmpty ? '当前账号无 Opus 免费额度' : reasons.join('，'))
                : '无法估算点数消耗';
            return ToolResult(
              toolCallId: toolCallId,
              content:
                  '已取消生成：本次生图（$reasonText）预计消耗 '
                  '${estimatedCost > 0 ? '$estimatedCost Anlas 点数' : 'Anlas 点数'}，用户已拒绝扣费。'
                  '请先调用 update_studio_parameters 将参数调整到免费区间（如尺寸 <= 832x1216 且 步数 <= 28）或征求用户进一步指示。',
              isError: true,
            );
          }
        }
      }

      NaiGeneratedImage? resultImage;

      // 发起前通知 UI 捕获"是否正在看最新图"快照
      // (此时新图尚未入历史，isViewingLatest 反映的是生成前的真实浏览位置)
      onBeforeGenerate?.call();

      if (config.enableStreamPreview) {
        final stream = repository.generateStream(
          apiKey: config.novelAiKey,
          params: params,
          saveDir: config.saveDirectory,
          enablePersistence: config.enableImagePersistence,
          maxImages: config.maxPersistentImages,
          autoSave: config.autoSaveImages,
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
          enablePersistence: config.enableImagePersistence,
          maxImages: config.maxPersistentImages,
          autoSave: config.autoSaveImages,
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

      final costText = estimatedCost > 0
          ? '预计 $estimatedCost Anlas'
          : (estimatedCost == 0 ? '0 Anlas (Opus 免费)' : '消耗点数 (未能获取账号信息)');

      final resultBuffer = StringBuffer();
      resultBuffer.writeln('生图完成：');
      if (image.isUnsaved) {
        resultBuffer.writeln('状态: 未保存 (已进入缓存，可在画板右下角手动保存)');
      } else if (image.localFilePath != null) {
        resultBuffer.writeln('保存路径: ${image.localFilePath}');
      }
      resultBuffer.writeln('模型: ${params.model.label}');
      resultBuffer.writeln('尺寸: ${params.width}x${params.height}');
      resultBuffer.writeln('步数: ${params.steps} 步');
      resultBuffer.writeln(
        'CFG: ${params.scale} (Rescale: ${params.cfgRescale})',
      );
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
  final CurrentAccountInfoGetter? getAccountInfo;
  final OnConfirmPaidUpscaleCallback? onConfirmPaidUpscale;

  NovelAiUpscaleTool({
    required this._repository,
    required this._configService,
    this._onUpscaled,
    this.getAccountInfo,
    this.onConfirmPaidUpscale,
  }) : super(
         name: 'novelai_upscale',
         label: 'NovelAI 图像超分放大',
         description:
             '调用 NovelAI 官方超分算法 (V5 换代新模型，固定倍率输出) 将指定图片无损放大。'
             '按输入面积分档计费（Opus 用户输入不超 640x640 免费），预计消耗非零时会先向用户确认。',
         parameters: {
           'type': 'object',
           'properties': {
             'image_path': {
               'type': 'string',
               'description': '待放大的本地图片路径（留空则默认放大画板中的最新图像）',
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
          content: '错误：未配置 NovelAI API Key。',
          isError: true,
        );
      }

      final imagePath = args['image_path'] as String?;

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

      // 付费闸门: 按输入面积分档计费，预计消耗非零时先向用户确认
      final dims = await AnlasCalculator.decodeImageDimensions(
        targetImage.bytes,
      );
      var account = getAccountInfo?.call();
      if (account == null) {
        try {
          account = await _repository.fetchAccountInfo(
            apiKey: config.novelAiKey,
          );
        } catch (_) {
          // 拉取失败时按非 Opus 保守估算
        }
      }
      final upscaleCost = dims == null
          ? AnlasCalculator.invalidCost
          : AnlasCalculator.estimateUpscaleCost(
              inputWidth: dims.width,
              inputHeight: dims.height,
              isOpus: account?.isOpus ?? false,
            );
      if (upscaleCost > 0 && onConfirmPaidUpscale != null) {
        final confirmed = await onConfirmPaidUpscale!(
          estimatedCost: upscaleCost,
          inputWidth: dims!.width,
          inputHeight: dims.height,
        );
        if (!confirmed) {
          return ToolResult(
            toolCallId: toolCallId,
            content:
                '已取消放大：将输入尺寸 ${dims.width}x${dims.height} 的图片执行官方超分，'
                '预计消耗 $upscaleCost Anlas，用户已拒绝扣费。',
            isError: true,
          );
        }
      }

      final upscaled = await _repository.upscale(
        apiKey: config.novelAiKey,
        sourceImage: targetImage,
        saveDir: config.saveDirectory,
        enablePersistence: config.enableImagePersistence,
        maxImages: config.maxPersistentImages,
        autoSave: config.autoSaveImages,
      );

      _onUpscaled?.call(upscaled);

      final costSuffix = dims == null
          ? ''
          : '\n点数消耗: ${AnlasCalculator.describeCost(upscaleCost)}';
      final saveSuffix = upscaled.isUnsaved
          ? '\n状态: 未保存 (已进入缓存，可在画板右下角手动保存)'
          : '\n保存路径: ${upscaled.localFilePath ?? '内存中'}';

      return ToolResult(
        toolCallId: toolCallId,
        content:
            '图像超分放大完成 (${upscaled.params.width}x${upscaled.params.height})'
            '$saveSuffix'
            '$costSuffix',
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
  }) : super(
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
    String toolCallId,
    Map<String, dynamic> args,
  ) async {
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
        buffer.writeln(
          '- ${t.tag} (用量: ${t.count}, 匹配度: ${(t.confidence * 100).toStringAsFixed(1)}%)',
        );
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
  }) : super(
         name: 'novelai_account_info',
         label: 'NovelAI 账号与体力查询',
         description: '查询当前 NovelAI 账号的订阅等级、Anlas 点数余额以及 V5 专属体力池余量。',
         parameters: {'type': 'object', 'properties': {}},
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
          content: '错误：未配置 NovelAI API Key。',
          isError: true,
        );
      }

      final info = await _repository.fetchAccountInfo(
        apiKey: config.novelAiKey,
      );

      final buffer = StringBuffer();
      buffer.writeln('NovelAI 账号状态：');
      buffer.writeln('• 订阅等级: ${info.tierName}');
      buffer.writeln('• 账号状态: ${info.active ? '激活中' : '未激活'}');
      if (info.expiresAt != null) {
        buffer.writeln(
          '• 会员到期时间: ${DateFormat('yyyy-MM-dd HH:mm').format(info.expiresAt!)}',
        );
      }
      buffer.writeln('• V5 专属体力池: ${info.staminaPercent.toStringAsFixed(1)}%');
      if (info.v5QuotaExhausted) {
        buffer.writeln('• V5 体力配额已透支，生图将按正常价消耗 Anlas');
      }
      if (info.timeUntilNextPercent > 0) {
        buffer.writeln('• 体力恢复: ${info.timeUntilNextPercent} 秒后 +1%');
      }
      buffer.writeln(
        '• 总可用 Anlas: ${info.totalAnlas} (赠送: ${info.fixedAnlas}, 购买: ${info.purchasedAnlas})',
      );

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
