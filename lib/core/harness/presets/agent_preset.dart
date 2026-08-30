/// 预设参数修改权限键定义
///
/// 键名与 NovelAiUpdateParamsTool 的参数键一一对应，单一事实来源。
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
  static const String characterAiPosition = 'character_ai_position';

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
    characterAiPosition: '角色定位模式',
  };

  /// 全部内置生图参数键 (完整权限预设直接复用)
  static final List<String> all = labels.keys.toList();

  static String getLabel(String key) => labels[key] ?? key;
}

/// 预设工具标识定义
///
/// 键名与各 AgentTool 子类的 name 字段一一对应。
/// 注意: 用户自定义工具 (CustomAgentTool) 不在此列，
/// 预设需在 enabledToolNames 中显式列出其名称才会对其开放。
class PresetToolKeys {
  static const String generate = 'novelai_generate';
  static const String upscale = 'novelai_upscale';
  static const String suggestTags = 'novelai_suggest_tags';
  static const String danbooruSearch = 'danbooru_search_tags';
  static const String danbooruRelated = 'danbooru_related_tags';
  static const String danbooruArtists = 'danbooru_recommend_artists';
  static const String accountInfo = 'novelai_account_info';
  static const String askUser = 'ask_user';
  static const String getParams = 'get_studio_parameters';
  static const String updateParams = 'update_studio_parameters';
  static const String listCharacterPrompts = 'list_character_prompts';
  static const String addCharacterPrompt = 'add_character_prompt';
  static const String updateCharacterPrompt = 'update_character_prompt';
  static const String removeCharacterPrompt = 'remove_character_prompt';
  static const String loadSkill = 'load_skill';
  static const String viewCanvasImage = 'view_canvas_image';
  static const String searchPromptLibrary = 'search_prompt_library';
  static const String addPromptLibraryEntry = 'add_prompt_library_entry';
  static const String updatePromptLibraryEntry = 'update_prompt_library_entry';
  static const String deletePromptLibraryEntry = 'delete_prompt_library_entry';

  static const Map<String, String> labels = {
    generate: '图像生成',
    upscale: '图像放大',
    suggestTags: '标签联想',
    danbooruSearch: '语义搜词',
    danbooruRelated: '关联推荐',
    danbooruArtists: '画师推荐',
    accountInfo: '账号查询',
    askUser: '向用户提问',
    getParams: '读取参数',
    updateParams: '修改参数',
    listCharacterPrompts: '角色列表',
    addCharacterPrompt: '添加角色',
    updateCharacterPrompt: '修改角色',
    removeCharacterPrompt: '删除角色',
    loadSkill: '加载技能',
    viewCanvasImage: '查看画板图片',
    searchPromptLibrary: '搜索词库',
    addPromptLibraryEntry: '新增词库条目',
    updatePromptLibraryEntry: '修改词库条目',
    deletePromptLibraryEntry: '删除词库条目',
  };

  /// 全部内置工具键 (完整权限预设直接复用)
  static final List<String> all = labels.keys.toList();
}

/// 内置预设复用的权限常量表 (const 构造使用)
const List<String> _fullTools = [
  PresetToolKeys.generate,
  PresetToolKeys.upscale,
  PresetToolKeys.suggestTags,
  PresetToolKeys.danbooruSearch,
  PresetToolKeys.danbooruRelated,
  PresetToolKeys.danbooruArtists,
  PresetToolKeys.accountInfo,
  PresetToolKeys.askUser,
  PresetToolKeys.getParams,
  PresetToolKeys.updateParams,
  PresetToolKeys.listCharacterPrompts,
  PresetToolKeys.addCharacterPrompt,
  PresetToolKeys.updateCharacterPrompt,
  PresetToolKeys.removeCharacterPrompt,
  PresetToolKeys.loadSkill,
  PresetToolKeys.viewCanvasImage,
  PresetToolKeys.searchPromptLibrary,
  PresetToolKeys.addPromptLibraryEntry,
  PresetToolKeys.updatePromptLibraryEntry,
  PresetToolKeys.deletePromptLibraryEntry,
];

const List<String> _coreTools = [
  PresetToolKeys.generate,
  PresetToolKeys.suggestTags,
  PresetToolKeys.danbooruSearch,
  PresetToolKeys.danbooruRelated,
  PresetToolKeys.danbooruArtists,
  PresetToolKeys.askUser,
  PresetToolKeys.getParams,
  PresetToolKeys.updateParams,
  PresetToolKeys.listCharacterPrompts,
  PresetToolKeys.addCharacterPrompt,
  PresetToolKeys.updateCharacterPrompt,
  PresetToolKeys.removeCharacterPrompt,
  PresetToolKeys.loadSkill,
  PresetToolKeys.viewCanvasImage,
  PresetToolKeys.searchPromptLibrary,
  PresetToolKeys.addPromptLibraryEntry,
  PresetToolKeys.updatePromptLibraryEntry,
  PresetToolKeys.deletePromptLibraryEntry,
];

const List<String> _coreUpscaleTools = [
  PresetToolKeys.generate,
  PresetToolKeys.upscale,
  PresetToolKeys.suggestTags,
  PresetToolKeys.danbooruSearch,
  PresetToolKeys.danbooruRelated,
  PresetToolKeys.danbooruArtists,
  PresetToolKeys.askUser,
  PresetToolKeys.getParams,
  PresetToolKeys.updateParams,
  PresetToolKeys.listCharacterPrompts,
  PresetToolKeys.addCharacterPrompt,
  PresetToolKeys.updateCharacterPrompt,
  PresetToolKeys.removeCharacterPrompt,
  PresetToolKeys.loadSkill,
  PresetToolKeys.viewCanvasImage,
  PresetToolKeys.searchPromptLibrary,
  PresetToolKeys.addPromptLibraryEntry,
  PresetToolKeys.updatePromptLibraryEntry,
  PresetToolKeys.deletePromptLibraryEntry,
];

const List<String> _allParams = [
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
];

/// Agent 预设 (Preset) 数据模型
///
/// 对齐 pi 的 PromptTemplate/Mode 概念：预设 = 系统提示词 + 可按需加载的
/// Skill 清单 + 开放工具与生图参数权限。权限语义为显式列表：
/// [enabledToolNames] / [allowedModifiableParams] 中不存在即视为未开放。
class AgentPreset {
  final String id;
  final String name;
  final String description;

  /// 系统提示词 (核心人设与工作流编排；专业规范细节交给 Skill 按需加载)
  final String systemPrompt;

  /// 允许出现在技能声明清单中、可被 load_skill 加载的技能 ID
  final List<String> enabledSkillIds;

  /// 允许 LLM 调用的工具名 (显式白名单)
  final List<String> enabledToolNames;

  /// 允许 Agent 修改的生图参数键 (显式白名单)
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
  bool isToolEnabled(String toolName) => enabledToolNames.contains(toolName);

  /// 检查某个生图参数是否允许被 Agent 修改
  bool isParamModifiable(String paramKey) =>
      allowedModifiableParams.contains(paramKey);

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
    // 旧版本未持久化权限字段时回退为全量开放；
    // 显式保存的空列表则保持为空 (全部禁止)，保证存取一致。
    List<String> parseList(String key, List<String> legacyAll) {
      final raw = json[key];
      if (raw is! List) return List.from(legacyAll);
      return raw.map((e) => e.toString()).toList();
    }

    return AgentPreset(
      id:
          json['id'] as String? ??
          'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: json['name'] as String? ?? '自定义预设',
      description: json['description'] as String? ?? '',
      systemPrompt: json['systemPrompt'] as String? ?? '',
      enabledSkillIds:
          (json['enabledSkillIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      enabledToolNames: parseList('enabledToolNames', PresetToolKeys.all),
      allowedModifiableParams: parseList(
        'allowedModifiableParams',
        PresetParamKeys.all,
      ),
      isBuiltin: json['isBuiltin'] as bool? ?? false,
    );
  }
}

/// 内置出厂预设集合
///
/// 系统提示词只保留人设与工具编排；V5 构词、标签体系等专业规范
/// 统一收敛在 BuiltinSkills 中由 load_skill 按需加载，避免双份维护。
class BuiltinPresets {
  /// 1. V5 自然语言架构师 (默认出厂预设)
  static const AgentPreset v5Architect = AgentPreset(
    id: 'v5-architect-preset',
    name: 'V5 自然语言架构师',
    description: '擅长 V5 自然语言散文提示词构词、漫画多格分镜排版、中日英文字嵌入、空间万物精准定位以及联动修改生图参数。',
    systemPrompt:
        '''你是由 NovelAI Harness 驱动的顶级动漫艺术总监与自然语言提示词架构师，负责将用户的创意构思转化为高精度 NovelAI 提示词。

【工作流】
1. 动手构词之前，先调用 load_skill 载入 v5-architect 专业技能规范，严格遵循技能中的构词与空间定位准则执行。
2. 构思好提示词或需要调整画面尺寸、步数、模型等参数时，调用 update_studio_parameters 将提示词与参数同步到工作台 UI。
3. 若需要多角色、特定场景物料、分镜或需精确定位的视觉元素，使用角色提示词工具 (add/update/list/remove_character_prompt) 进行空间布局与隔离。
4. 参数就绪后，调用 novelai_generate (无需传参) 直接使用工作台当前参数触发生成。''',
    enabledSkillIds: ['v5-architect'],
    enabledToolNames: _fullTools,
    allowedModifiableParams: _allParams,
    isBuiltin: true,
  );

  /// 2. Danbooru 标签大师
  static const AgentPreset danbooruTags = AgentPreset(
    id: 'danbooru-tags-preset',
    name: 'Danbooru 标签大师',
    description: '精通 Danbooru 标签体系，将用户的描述重构为规范标签序列，并可同步修改参数与生图。',
    systemPrompt:
        '''你是一名精通 Danbooru 标签体系的二次元绘图专家，负责将用户的描述重构为规范的 Danbooru 标签序列 (逗号分隔)。

【工作流】
1. 构思好标签序列或需要调整参数时，调用 update_studio_parameters 将提示词与参数更新到工作台。
2. 确认就绪后调用 novelai_generate 触发绘制。''',
    enabledSkillIds: ['v5-architect'],
    enabledToolNames: _coreTools,
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
    systemPrompt:
        '''你是一名插画与动画电影艺术总监，善于从电影级镜头视角、主光源方向、边缘光、环境色与构图等维度为用户提供专业的画面构思建议。

【工作流】
1. 给出方案前，先调用 load_skill 载入 v5-architect 技能规范并严格遵循。
2. 将构思转化为绘图参数，调用 update_studio_parameters 同步到工作台。
3. 方案确认后调用 novelai_generate 触发生成。''',
    enabledSkillIds: ['v5-architect'],
    enabledToolNames: _coreUpscaleTools,
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
    systemPrompt: '''你是由 NovelAI Harness 驱动的智能绘图助手，根据用户的自由指令协助构思并完成插画绘制。

【工作流】
1. 需要专业构词规范时，调用 load_skill 载入 v5-architect 技能。
2. 调用 update_studio_parameters 修改工作台参数，调用 novelai_generate 触发绘制。''',
    enabledSkillIds: ['v5-architect'],
    enabledToolNames: _fullTools,
    allowedModifiableParams: _allParams,
    isBuiltin: true,
  );

  static List<AgentPreset> get all => [
    v5Architect,
    danbooruTags,
    artDirector,
    freeCreator,
  ];
}
