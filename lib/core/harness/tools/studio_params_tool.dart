import '../../../data/models/novelai_models.dart';
import '../presets/agent_preset.dart';
import '../types.dart';
import 'agent_tool.dart';

/// 回调类型：更新生图参数
typedef OnStudioParamsUpdate = void Function(NaiGenerationParams newParams);

/// 回调类型：获取当前生图参数
typedef CurrentParamsGetter = NaiGenerationParams Function();

/// 回调类型：检查参数是否允许修改
typedef ParamPermissionChecker = bool Function(String paramKey);

/// 构建工作台全部生图参数的可读报表 (get_studio_parameters 工具与 /params 指令共用)
String buildStudioParamsReport(
  NaiGenerationParams params, {
  String title = '工作台全部生图参数：',
}) {
  final costStatus = params.isOpusFree
      ? '符合 Opus 免费区间 (0 Anlas)'
      : '超出免费区间 (将消耗点数)';
  final lines = <String>[
    '• 正向提示词: ${params.prompt.isEmpty ? '(空)' : params.prompt}',
    '• 负向提示词: ${params.negativePrompt.isEmpty ? '(空)' : params.negativePrompt}',
    '• 绘图模型: ${params.model.label} (${params.model.id})',
    '• 画面尺寸: ${params.width}x${params.height}',
    '• 采样步数: ${params.steps} 步',
    '• CFG 强度: ${params.scale} (Rescale: ${params.cfgRescale})',
    '• 采样算法: ${params.sampler.label} (${params.sampler.id})',
    '• 噪声调度: ${params.noiseSchedule.label} (${params.noiseSchedule.id})',
    '• 质量标签: ${params.qualityPreset}',
    '• 随机种子: ${params.seed == -1 ? '随机 (-1)' : params.seed}',
    '• Opus 状态: $costStatus',
  ];
  return '$title\n${lines.join('\n')}';
}

/// 工作台当前生图参数读取工具 (按需查询指定参数或查看全部)
class NovelAiGetStudioParamsTool extends AgentTool {
  final CurrentParamsGetter getCurrentParams;

  NovelAiGetStudioParamsTool({required this.getCurrentParams})
    : super(
        name: 'get_studio_parameters',
        label: '读取参数',
        description:
            '按需读取工作台当前生效的生图参数。可传入 keys 参数指定要查看的一个或多个参数字段；未指定 keys 或包含 "all" 时返回全部参数。',
        parameters: const {
          'type': 'object',
          'properties': {
            'keys': {
              'type': 'array',
              'items': {
                'type': 'string',
                'enum': [
                  'prompt',
                  'negative_prompt',
                  'model',
                  'resolution',
                  'width',
                  'height',
                  'steps',
                  'scale',
                  'cfg_rescale',
                  'sampler',
                  'noise_schedule',
                  'quality_preset',
                  'seed',
                  'opus_free_status',
                  'all',
                ],
              },
              'description':
                  '要查询的参数键名列表（支持多选，如 ["prompt", "steps"]；留空或包含 "all" 则返回全部）',
            },
          },
        },
      );

  @override
  Future<ToolResult> execute(
    String toolCallId,
    Map<String, dynamic> args,
  ) async {
    final params = getCurrentParams();
    final rawKeys = args['keys'];
    List<String> requestedKeys = [];
    if (rawKeys is List) {
      requestedKeys = rawKeys
          .map((e) => e.toString().toLowerCase().trim())
          .toList();
    }

    final queryAll = requestedKeys.isEmpty || requestedKeys.contains('all');

    if (queryAll) {
      return ToolResult(
        toolCallId: toolCallId,
        content: buildStudioParamsReport(params),
      );
    }

    final lines = <String>[];

    if (requestedKeys.contains('prompt')) {
      lines.add('• 正向提示词: ${params.prompt.isEmpty ? '(空)' : params.prompt}');
    }
    if (requestedKeys.contains('negative_prompt')) {
      lines.add(
        '• 负向提示词: ${params.negativePrompt.isEmpty ? '(空)' : params.negativePrompt}',
      );
    }
    if (requestedKeys.contains('model')) {
      lines.add('• 绘图模型: ${params.model.label} (${params.model.id})');
    }
    if (requestedKeys.contains('resolution')) {
      lines.add('• 画面尺寸: ${params.width}x${params.height}');
    } else {
      if (requestedKeys.contains('width')) {
        lines.add('• 宽度: ${params.width}');
      }
      if (requestedKeys.contains('height')) {
        lines.add('• 高度: ${params.height}');
      }
    }
    if (requestedKeys.contains('steps')) {
      lines.add('• 采样步数: ${params.steps} 步');
    }
    if (requestedKeys.contains('scale')) {
      lines.add('• CFG 强度: ${params.scale}');
    }
    if (requestedKeys.contains('cfg_rescale')) {
      lines.add('• CFG Rescale: ${params.cfgRescale}');
    }
    if (requestedKeys.contains('sampler')) {
      lines.add('• 采样算法: ${params.sampler.label} (${params.sampler.id})');
    }
    if (requestedKeys.contains('noise_schedule')) {
      lines.add(
        '• 噪声调度: ${params.noiseSchedule.label} (${params.noiseSchedule.id})',
      );
    }
    if (requestedKeys.contains('quality_preset')) {
      lines.add('• 质量标签: ${params.qualityPreset}');
    }
    if (requestedKeys.contains('seed')) {
      lines.add('• 随机种子: ${params.seed == -1 ? '随机 (-1)' : params.seed}');
    }
    if (requestedKeys.contains('opus_free_status')) {
      final costStatus = params.isOpusFree
          ? '符合 Opus 免费区间 (0 Anlas)'
          : '超出免费区间 (将消耗点数)';
      lines.add('• Opus 状态: $costStatus');
    }

    if (lines.isEmpty) {
      return ToolResult(
        toolCallId: toolCallId,
        content:
            '未匹配到指定的参数名称: ${requestedKeys.join(', ')}。支持的键名: prompt, negative_prompt, model, resolution, steps, scale, sampler, seed, opus_free_status 等。',
        isError: true,
      );
    }

    return ToolResult(
      toolCallId: toolCallId,
      content: '工作台查询参数：\n${lines.join('\n')}',
    );
  }
}

/// 工作台生图参数修改工具 (修改生图参数要真正修改 UI 上的参数)
class NovelAiUpdateParamsTool extends AgentTool {
  final CurrentParamsGetter getCurrentParams;
  final OnStudioParamsUpdate onUpdateParams;
  final ParamPermissionChecker? permissionChecker;

  NovelAiUpdateParamsTool({
    required this.getCurrentParams,
    required this.onUpdateParams,
    this.permissionChecker,
  }) : super(
         name: 'update_studio_parameters',
         label: '修改参数',
         description:
             '按需修改工作台的生图参数。只需传入需要修改的一个或多个字段（如 prompt、steps、scale 等），未传入的字段将保持原设置不变。修改后会实时同步更新 UI 界面。',
         parameters: {
           'type': 'object',
           'properties': {
             'prompt': {'type': 'string', 'description': '正向提示词描述'},
             'negative_prompt': {
               'type': 'string',
               'description': '负向提示词 (排除的内容)',
             },
             'model': {
               'type': 'string',
               'enum': [
                 'nai-diffusion-5-full',
                 'nai-diffusion-5-curated',
                 'nai-diffusion-4-5-full',
                 'nai-diffusion-4-5-curated',
                 'nai-diffusion-4-full',
                 'nai-diffusion-3',
               ],
               'description': '生图模型 ID',
             },
             'resolution_preset': {
               'type': 'string',
               'enum': [
                 'portrait',
                 'landscape',
                 'square',
                 'wallpaper',
                 'portrait_large',
                 'landscape_large',
               ],
               'description':
                   '分辨率预设：portrait(832x1216), landscape(1216x832), square(1024x1024), wallpaper(1920x1088)',
             },
             'width': {
               'type': 'integer',
               'description': '自定义宽度 (自动64对齐，如 832, 1024, 1216)',
             },
             'height': {
               'type': 'integer',
               'description': '自定义高度 (自动64对齐，如 1216, 832, 1024)',
             },
             'steps': {
               'type': 'integer',
               'description': '采样步数 (1~50，Opus 免费生图上限为 28)',
             },
             'scale': {
               'type': 'number',
               'description': 'CFG 提示词引导强度 (1.0~20.0，默认5.0)',
             },
             'cfg_rescale': {
               'type': 'number',
               'description': 'CFG Rescale 抗过曝修正 (0.0~1.0)',
             },
             'sampler': {
               'type': 'string',
               'enum': [
                 'k_euler',
                 'k_euler_ancestral',
                 'k_dpmpp_2m',
                 'k_dpmpp_sde',
               ],
               'description': '采样算法',
             },
             'noise_schedule': {
               'type': 'string',
               'enum': ['karras', 'exponential', 'polyexponential', 'native'],
               'description': '噪声调度算法',
             },
             'quality_preset': {
               'type': 'string',
               'enum': ['Standard', 'Heavy', 'Light', 'Off'],
               'description': '官方质量标签词缀预设',
             },
           },
         },
       );

  @override
  Future<ToolResult> execute(
    String toolCallId,
    Map<String, dynamic> args,
  ) async {
    final current = getCurrentParams();
    final updatedEntries = <String>[];
    final blockedEntries = <String>[];

    String prompt = current.prompt;
    String negativePrompt = current.negativePrompt;
    NaiModel model = current.model;
    int width = current.width;
    int height = current.height;
    int steps = current.steps;
    double scale = current.scale;
    double cfgRescale = current.cfgRescale;
    NaiSampler sampler = current.sampler;
    NoiseSchedule noiseSchedule = current.noiseSchedule;
    String qualityPreset = current.qualityPreset;

    bool isAllowed(String key) {
      final checker = permissionChecker;
      if (checker == null) return true;
      return checker(key);
    }

    // 1. 正向提示词
    if (args.containsKey('prompt')) {
      if (isAllowed(PresetParamKeys.prompt)) {
        prompt = args['prompt'] as String? ?? '';
        updatedEntries.add('正向提示词: $prompt');
      } else {
        blockedEntries.add('正向提示词');
      }
    }

    // 2. 负向提示词
    if (args.containsKey('negative_prompt')) {
      if (isAllowed(PresetParamKeys.negativePrompt)) {
        negativePrompt = args['negative_prompt'] as String? ?? '';
        updatedEntries.add('负向提示词: $negativePrompt');
      } else {
        blockedEntries.add('负向提示词');
      }
    }

    // 3. 模型
    if (args.containsKey('model')) {
      if (isAllowed(PresetParamKeys.model)) {
        final modelStr = args['model'] as String?;
        if (modelStr != null) {
          model = NaiModel.fromId(modelStr);
          updatedEntries.add('模型: ${model.label}');
        }
      } else {
        blockedEntries.add('生图模型');
      }
    }

    // 4. 分辨率 / 宽高
    if (args.containsKey('resolution_preset')) {
      if (isAllowed(PresetParamKeys.resolution)) {
        final presetStr = args['resolution_preset'] as String?;
        if (presetStr != null) {
          final preset = ResolutionPreset.fromKey(presetStr);
          width = preset.width;
          height = preset.height;
          updatedEntries.add('分辨率预设: ${preset.label} (${width}x$height)');
        }
      } else {
        blockedEntries.add('分辨率预设');
      }
    } else {
      if (args.containsKey('width')) {
        if (isAllowed(PresetParamKeys.width)) {
          final w = (args['width'] as num?)?.toInt();
          if (w != null) {
            width = ((w ~/ 64) * 64).clamp(64, 2048);
            updatedEntries.add('宽度: $width');
          }
        } else {
          blockedEntries.add('宽度');
        }
      }
      if (args.containsKey('height')) {
        if (isAllowed(PresetParamKeys.height)) {
          final h = (args['height'] as num?)?.toInt();
          if (h != null) {
            height = ((h ~/ 64) * 64).clamp(64, 2048);
            updatedEntries.add('高度: $height');
          }
        } else {
          blockedEntries.add('高度');
        }
      }
    }

    // 5. 步数
    if (args.containsKey('steps')) {
      if (isAllowed(PresetParamKeys.steps)) {
        final s = (args['steps'] as num?)?.toInt();
        if (s != null) {
          steps = s.clamp(1, 50);
          updatedEntries.add('步数: $steps');
        }
      } else {
        blockedEntries.add('步数');
      }
    }

    // 6. CFG Scale
    if (args.containsKey('scale')) {
      if (isAllowed(PresetParamKeys.scale)) {
        final sc = (args['scale'] as num?)?.toDouble();
        if (sc != null) {
          scale = sc.clamp(1.0, 20.0);
          updatedEntries.add('CFG Scale: $scale');
        }
      } else {
        blockedEntries.add('CFG Scale');
      }
    }

    // 7. CFG Rescale
    if (args.containsKey('cfg_rescale')) {
      if (isAllowed(PresetParamKeys.cfgRescale)) {
        final cr = (args['cfg_rescale'] as num?)?.toDouble();
        if (cr != null) {
          cfgRescale = cr.clamp(0.0, 1.0);
          updatedEntries.add('CFG Rescale: $cfgRescale');
        }
      } else {
        blockedEntries.add('CFG Rescale');
      }
    }

    // 8. 采样器
    if (args.containsKey('sampler')) {
      if (isAllowed(PresetParamKeys.sampler)) {
        final samplerStr = args['sampler'] as String?;
        if (samplerStr != null) {
          sampler = NaiSampler.fromId(samplerStr);
          updatedEntries.add('采样器: ${sampler.label}');
        }
      } else {
        blockedEntries.add('采样器');
      }
    }

    // 9. 噪声调度
    if (args.containsKey('noise_schedule')) {
      if (isAllowed(PresetParamKeys.noiseSchedule)) {
        final nsStr = args['noise_schedule'] as String?;
        if (nsStr != null) {
          noiseSchedule = NoiseSchedule.fromId(nsStr);
          updatedEntries.add('噪声调度: ${noiseSchedule.label}');
        }
      } else {
        blockedEntries.add('噪声调度');
      }
    }

    // 10. 质量预设
    if (args.containsKey('quality_preset')) {
      if (isAllowed(PresetParamKeys.qualityPreset)) {
        final qpStr = args['quality_preset'] as String?;
        if (qpStr != null) {
          qualityPreset = qpStr;
          updatedEntries.add('质量预设: $qualityPreset');
        }
      } else {
        blockedEntries.add('质量预设');
      }
    }

    if (updatedEntries.isEmpty) {
      if (blockedEntries.isNotEmpty) {
        return ToolResult(
          toolCallId: toolCallId,
          content: '错误：权限受限，当前预设禁止修改以下生图参数：${blockedEntries.join(', ')}。',
          isError: true,
        );
      }
      return ToolResult(toolCallId: toolCallId, content: '未修改任何参数（传入参数为空）。');
    }

    // 构建新参数并触发 UI 更新
    final newParams = current.copyWith(
      prompt: prompt,
      negativePrompt: negativePrompt,
      model: model,
      width: width,
      height: height,
      steps: steps,
      scale: scale,
      cfgRescale: cfgRescale,
      sampler: sampler,
      noiseSchedule: noiseSchedule,
      qualityPreset: qualityPreset,
    );

    onUpdateParams(newParams);

    final buffer = StringBuffer();
    buffer.writeln('已成功同步修改工作台 UI 生图参数：');
    for (final item in updatedEntries) {
      buffer.writeln('• $item');
    }

    return ToolResult(
      toolCallId: toolCallId,
      content: buffer.toString().trim(),
    );
  }
}
