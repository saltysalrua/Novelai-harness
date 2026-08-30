/// 预设参数修改权限键定义
class PresetParamKeys {
  static const String prompt = 'prompt';
  static const String negativePrompt = 'negative_prompt';
  static const String model = 'model';
  static const String resolution = 'resolution';
  static const String width = 'width';
  static const String height = 'height';
  static const String steps = 'steps';
  static const String scale = 'scale';
  static const String cfgRescale = 'cfg_rescale';
  static const String sampler = 'sampler';
  static const String noiseSchedule = 'noise_schedule';
  static const String qualityPreset = 'quality_preset';

  /// 所有支持的生图参数列表与中文标签映射
  static const Map<String, String> labels = {
    prompt: '提示词',
    negativePrompt: '负向提示词',
    model: '模型',
    resolution: '分辨率',
    width: '宽度',
    height: '高度',
    steps: '步数',
    scale: 'CFG',
    cfgRescale: 'CFG Rescale',
    sampler: '采样器',
    noiseSchedule: '噪声调度',
    qualityPreset: '质量标签',
  };

  static List<String> get all => labels.keys.toList();

  static String getLabel(String key) => labels[key] ?? key;
}

/// 预设工具标识定义
class PresetToolKeys {
  static const String generate = 'novelai_generate';
  static const String upscale = 'novelai_upscale';
  static const String suggestTags = 'novelai_suggest_tags';
  static const String accountInfo = 'novelai_account_info';
  static const String askUser = 'ask_user';
  static const String getParams = 'get_studio_parameters';
  static const String updateParams = 'update_studio_parameters';
  static const String loadSkill = 'load_skill';

  static const Map<String, String> labels = {
    generate: '图像生成',
    upscale: '图像放大',
    suggestTags: '标签联想',
    accountInfo: '账号查询',
    askUser: '向用户提问',
    getParams: '读取参数',
    updateParams: '修改参数',
    loadSkill: '加载技能',
  };

  static List<String> get all => labels.keys.toList();
}

/// Agent 预设 (Preset) 数据模型
///
/// 包含三大核心要素：
/// 1. 系统提示词 (systemPrompt)：核心人设与指引
/// 2. 可用 Skill 列表 (enabledSkillIds)：按需加载的标准 Skill 清单
/// 3. 开放工具与生图参数控制 (enabledToolNames / allowedModifiableParams)
class AgentPreset {
  final String id;
  final String name;
  final String description;
  final String systemPrompt;
  final List<String> enabledSkillIds;
  final List<String> enabledToolNames;
  final List<String> allowedModifiableParams;
  final bool isBuiltin;

  const AgentPreset({
    required this.id,
    required this.name,
    required this.description,
    required this.systemPrompt,
    this.enabledSkillIds = const [],
    this.enabledToolNames = const [],
    this.allowedModifiableParams = const [],
    this.isBuiltin = false,
  });

  /// 检查某项工具是否在该预设中开放
  bool isToolEnabled(String toolName) {
    if (enabledToolNames.isEmpty) return true;
    return enabledToolNames.contains(toolName);
  }

  /// 检查某个生图参数是否允许被 Agent 修改
  bool isParamModifiable(String paramKey) {
    if (allowedModifiableParams.isEmpty) return true;
    return allowedModifiableParams.contains(paramKey);
  }

  AgentPreset copyWith({
    String? id,
    String? name,
    String? description,
    String? systemPrompt,
    List<String>? enabledSkillIds,
    List<String>? enabledToolNames,
    List<String>? allowedModifiableParams,
    bool? isBuiltin,
  }) {
    return AgentPreset(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      enabledSkillIds: enabledSkillIds ?? List.from(this.enabledSkillIds),
      enabledToolNames: enabledToolNames ?? List.from(this.enabledToolNames),
      allowedModifiableParams:
          allowedModifiableParams ?? List.from(this.allowedModifiableParams),
      isBuiltin: isBuiltin ?? this.isBuiltin,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'systemPrompt': systemPrompt,
      'enabledSkillIds': enabledSkillIds,
      'enabledToolNames': enabledToolNames,
      'allowedModifiableParams': allowedModifiableParams,
      'isBuiltin': isBuiltin,
    };
  }

  factory AgentPreset.fromJson(Map<String, dynamic> json) {
    return AgentPreset(
      id: json['id'] as String? ?? 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: json['name'] as String? ?? '自定义预设',
      description: json['description'] as String? ?? '',
      systemPrompt: json['systemPrompt'] as String? ?? '',
      enabledSkillIds: (json['enabledSkillIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      enabledToolNames: (json['enabledToolNames'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      allowedModifiableParams:
          (json['allowedModifiableParams'] as List<dynamic>?)
                  ?.map((e) => e.toString())
                  .toList() ??
              const [],
      isBuiltin: json['isBuiltin'] as bool? ?? false,
    );
  }
}

/// 内置出厂预设集合
class BuiltinPresets {
  /// 1. V5 自然语言架构师 (默认出厂预设)
  static const AgentPreset v5Architect = AgentPreset(
    id: 'v5-architect-preset',
    name: 'V5 自然语言架构师',
    description: '擅长 V5 自然语言散文提示词构词、漫画多格分镜排版、中日英文字嵌入以及多角色物理防串色隔离，并能联动修改生图参数。',
    systemPrompt: '''你是由 NovelAI Harness 驱动的顶级动漫艺术总监与自然语言提示词架构师。
你的任务是将用户的创意构思转化为最适合 NovelAI Diffusion (V5/V4.5) 渲染的高精度提示词，并在需要时调整工作台参数或直接生图。

【核心工作流与规范】
1. 自然语言散文构词：使用富有画面张力、透视与光影细节的英文连续段落。
2. 漫画多格分镜架构：当用户需要漫画、四格或分镜时，明确声明页面布局 (e.g. A dynamic manga page layout, multiple sequential panels...)。
3. 原生文字排版：需要台词或文字招牌时，使用语法：text, <样式与载体描述> "<精准文字内容>"。
4. 多角色防串色隔离：当画面出现两个或以上角色时，使用竖线管道符 | 物理分段：[全局环境光影] | [左侧角色A] | [右侧角色B]。
5. 参数修改：当构思好提示词或需要调整画面尺寸、步数、模型等参数时，必须先调用 `update_studio_parameters` 将提示词与参数同步修改到工作台 UI。
6. 生图收尾：完成参数配置后，调用 `novelai_generate`（无需传参）直接使用工作台当前参数触发生成画面。''',
    enabledSkillIds: ['v5-architect', 'danbooru-tags', 'art-director'],
    enabledToolNames: [
      PresetToolKeys.generate,
      PresetToolKeys.upscale,
      PresetToolKeys.suggestTags,
      PresetToolKeys.accountInfo,
      PresetToolKeys.askUser,
      PresetToolKeys.getParams,
      PresetToolKeys.updateParams,
      PresetToolKeys.loadSkill,
    ],
    allowedModifiableParams: [
      PresetParamKeys.prompt,
      PresetParamKeys.negativePrompt,
      PresetParamKeys.model,
      PresetParamKeys.resolution,
      PresetParamKeys.width,
      PresetParamKeys.height,
      PresetParamKeys.steps,
      PresetParamKeys.scale,
      PresetParamKeys.cfgRescale,
      PresetParamKeys.sampler,
      PresetParamKeys.noiseSchedule,
      PresetParamKeys.qualityPreset,
    ],
    isBuiltin: true,
  );

  /// 2. Danbooru 标签大师
  static const AgentPreset danbooruTags = AgentPreset(
    id: 'danbooru-tags-preset',
    name: 'Danbooru 标签大师',
    description: '精通 Danbooru 标签体系，将用户的描述重构为规范标签序列，并可同步修改参数与生图。',
    systemPrompt: '''你是一名精通 Danbooru 标签体系的二次元绘图专家。
你的任务是将用户的描述重构为规范的 Danbooru 标签序列（逗号分隔），并能根据风格推荐最佳的生图模型与采样参数。
必须先调用 `update_studio_parameters` 将提示词与参数更新到工作台，确认就绪后再调用 `novelai_generate` 触发绘制。''',
    enabledSkillIds: ['danbooru-tags'],
    enabledToolNames: [
      PresetToolKeys.generate,
      PresetToolKeys.suggestTags,
      PresetToolKeys.askUser,
      PresetToolKeys.getParams,
      PresetToolKeys.updateParams,
      PresetToolKeys.loadSkill,
    ],
    allowedModifiableParams: [
      PresetParamKeys.prompt,
      PresetParamKeys.negativePrompt,
      PresetParamKeys.model,
      PresetParamKeys.resolution,
      PresetParamKeys.steps,
      PresetParamKeys.scale,
      PresetParamKeys.sampler,
    ],
    isBuiltin: true,
  );

  /// 3. 艺术指导总监
  static const AgentPreset artDirector = AgentPreset(
    id: 'art-director-preset',
    name: '艺术指导总监',
    description: '专注于镜头机位、光影色调与画面构图建议，帮助用户规划顶级插画方案并配置参数。',
    systemPrompt: '''你是一名插画与动画电影艺术总监。
你善于从电影级镜头视角、主光源方向、边缘光、环境色与构图等维度，为用户提供专业的画面构思建议，并先通过 `update_studio_parameters` 转化为工作台绘图参数，最后调用 `novelai_generate` 触发生成。''',
    enabledSkillIds: ['art-director', 'v5-architect'],
    enabledToolNames: [
      PresetToolKeys.generate,
      PresetToolKeys.upscale,
      PresetToolKeys.suggestTags,
      PresetToolKeys.askUser,
      PresetToolKeys.getParams,
      PresetToolKeys.updateParams,
      PresetToolKeys.loadSkill,
    ],
    allowedModifiableParams: [
      PresetParamKeys.prompt,
      PresetParamKeys.negativePrompt,
      PresetParamKeys.resolution,
      PresetParamKeys.width,
      PresetParamKeys.height,
      PresetParamKeys.steps,
      PresetParamKeys.scale,
      PresetParamKeys.cfgRescale,
    ],
    isBuiltin: true,
  );

  /// 4. 自由创作助手
  static const AgentPreset freeCreator = AgentPreset(
    id: 'free-creator-preset',
    name: '自由创作助手',
    description: '全能极简创作助手，拥有全部工具与参数控制权限，随心所欲完成绘图。',
    systemPrompt: '''你是由 NovelAI Harness 驱动的智能绘图助手。
根据用户的自由指令，协助用户构思并在需要时调用 `update_studio_parameters` 修改工作台参数，调用 `novelai_generate` 触发插画绘制。''',
    enabledSkillIds: ['v5-architect', 'danbooru-tags', 'art-director'],
    enabledToolNames: [
      PresetToolKeys.generate,
      PresetToolKeys.upscale,
      PresetToolKeys.suggestTags,
      PresetToolKeys.accountInfo,
      PresetToolKeys.askUser,
      PresetToolKeys.getParams,
      PresetToolKeys.updateParams,
      PresetToolKeys.loadSkill,
    ],
    allowedModifiableParams: [
      PresetParamKeys.prompt,
      PresetParamKeys.negativePrompt,
      PresetParamKeys.model,
      PresetParamKeys.resolution,
      PresetParamKeys.width,
      PresetParamKeys.height,
      PresetParamKeys.steps,
      PresetParamKeys.scale,
      PresetParamKeys.cfgRescale,
      PresetParamKeys.sampler,
      PresetParamKeys.noiseSchedule,
      PresetParamKeys.qualityPreset,
    ],
    isBuiltin: true,
  );

  static List<AgentPreset> get all => [
        v5Architect,
        danbooruTags,
        artDirector,
        freeCreator,
      ];
}
