/// 技能模型 (按标准 Pi / Agent Skills 规范定义)
class Skill {
  final String id;
  final String name;
  final String description;
  final String systemPrompt;
  final bool disableModelInvocation;
  final bool isBuiltin;

  const Skill({
    required this.id,
    required this.name,
    required this.description,
    required this.systemPrompt,
    this.disableModelInvocation = false,
    this.isBuiltin = false,
  });

  Skill copyWith({
    String? id,
    String? name,
    String? description,
    String? systemPrompt,
    bool? disableModelInvocation,
    bool? isBuiltin,
  }) {
    return Skill(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      disableModelInvocation:
          disableModelInvocation ?? this.disableModelInvocation,
      isBuiltin: isBuiltin ?? this.isBuiltin,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'systemPrompt': systemPrompt,
    'disableModelInvocation': disableModelInvocation,
    'isBuiltin': isBuiltin,
  };

  factory Skill.fromJson(Map<String, dynamic> json) => Skill(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? (json['id'] as String? ?? ''),
    description: json['description'] as String? ?? '',
    systemPrompt: json['systemPrompt'] as String? ?? '',
    disableModelInvocation: json['disableModelInvocation'] as bool? ?? false,
    isBuiltin: json['isBuiltin'] as bool? ?? false,
  );

  /// 导出为标准 Pi / Agent Skills SKILL.md 格式
  String toSkillMd() {
    final buffer = StringBuffer();
    buffer.writeln('---');
    buffer.writeln('name: $id');
    buffer.writeln('description: ${_escapeYaml(description)}');
    if (name != id) {
      buffer.writeln('label: ${_escapeYaml(name)}');
    }
    if (disableModelInvocation) {
      buffer.writeln('disable-model-invocation: true');
    }
    buffer.writeln('---');
    buffer.writeln();
    buffer.writeln(systemPrompt.trim());
    return buffer.toString();
  }

  /// 从标准 Pi / Agent Skills SKILL.md 字符串导入
  factory Skill.fromSkillMd(String content, {String? defaultId}) {
    final normalized = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    if (!normalized.trimLeft().startsWith('---')) {
      // 无 Frontmatter，直接作为 System Prompt 处理
      final firstLine = normalized.trim().split('\n').first;
      final fallbackName =
          defaultId ??
          (firstLine.startsWith('#')
              ? firstLine.replaceAll('#', '').trim()
              : 'custom-skill');
      return Skill(
        id: defaultId ?? 'custom-skill',
        name: fallbackName,
        description: '从文本导入的自定义技能',
        systemPrompt: normalized.trim(),
        isBuiltin: false,
      );
    }

    final startIndex = normalized.indexOf('---');
    final endIndex = normalized.indexOf('\n---', startIndex + 3);

    if (endIndex == -1) {
      return Skill(
        id: defaultId ?? 'custom-skill',
        name: defaultId ?? 'Custom Skill',
        description: '',
        systemPrompt: normalized.trim(),
        isBuiltin: false,
      );
    }

    final frontmatterRaw = normalized
        .substring(startIndex + 3, endIndex)
        .trim();
    final body = normalized.substring(endIndex + 4).trim();

    String parsedName = defaultId ?? 'custom-skill';
    String parsedLabel = '';
    String parsedDesc = '';
    bool parsedDisableInvocation = false;

    for (final line in frontmatterRaw.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

      final colonIdx = trimmed.indexOf(':');
      if (colonIdx <= 0) continue;

      final key = trimmed.substring(0, colonIdx).trim().toLowerCase();
      var val = trimmed.substring(colonIdx + 1).trim();

      // 去除首尾引号
      if ((val.startsWith('"') && val.endsWith('"')) ||
          (val.startsWith("'") && val.endsWith("'"))) {
        val = val.substring(1, val.length - 1);
      }

      switch (key) {
        case 'name':
          parsedName = val;
          break;
        case 'label':
        case 'display_name':
        case 'title':
          parsedLabel = val;
          break;
        case 'description':
        case 'desc':
          parsedDesc = val;
          break;
        case 'disable-model-invocation':
        case 'disable_model_invocation':
          parsedDisableInvocation = val.toLowerCase() == 'true';
          break;
      }
    }

    return Skill(
      id: parsedName,
      name: parsedLabel.isNotEmpty ? parsedLabel : parsedName,
      description: parsedDesc,
      systemPrompt: body,
      disableModelInvocation: parsedDisableInvocation,
      isBuiltin: false,
    );
  }

  static String _escapeYaml(String value) {
    if (value.contains('\n') || value.contains(':') || value.contains('"')) {
      return '"${value.replaceAll('"', '\\"')}"';
    }
    return value;
  }

  /// 格式化为 Agent Skills 标准 XML 块 (遵循 Pi 规范注入系统提示词)
  static String formatSkillsForSystemPrompt(List<Skill> skills) {
    final visibleSkills = skills
        .where((s) => !s.disableModelInvocation)
        .toList();
    if (visibleSkills.isEmpty) return '';

    final buffer = StringBuffer();
    buffer.writeln(
      'The following skills provide specialized instructions for specific tasks.',
    );
    buffer.writeln(
      'Use the `load_skill` tool to load a skill\'s detailed instructions when the task matches its description.',
    );
    buffer.writeln();
    buffer.writeln('<available_skills>');
    for (final skill in visibleSkills) {
      buffer.writeln('  <skill>');
      buffer.writeln('    <name>${_escapeXml(skill.id)}</name>');
      buffer.writeln(
        '    <description>${_escapeXml(skill.description)}</description>',
      );
      buffer.writeln('  </skill>');
    }
    buffer.writeln('</available_skills>');
    return buffer.toString().trim();
  }

  static String _escapeXml(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}

/// 内置技能库
class BuiltinSkills {
  /// 1. V5 自然语言与空间视觉架构师
  static const Skill v5PromptArchitect = Skill(
    id: 'v5-architect',
    name: 'V5 自然语言与空间视觉架构师',
    description: '动漫艺术总监与空间视觉分析师：擅长 Danbooru 规范 Tag + 自然语言散文混合构词、空间万物精准定位（角色/场景/物品/分镜）、文字排版嵌入与多主体物理防串色。',
    systemPrompt: '''你是由 NovelAI Harness 驱动的顶级动漫艺术总监、空间视觉分析师与自然语言提示词架构师，专为 NovelAI Diffusion (NAI V5/V4.5) 优化。
你的任务是将用户的创意构思、参考标签或画面设想，通过【规范 Danbooru Tag 骨架 + 自然语言散文血肉】的混合构词体系，重构为高精度、极具画面张力与光影细节的提示词（严格控制在 1,700 tokens 以内），或搭建精准的空间视觉排版。

═══ 构词策略：Tag 骨架 + 自然语言精细化 (HYBRID PROMPT STRATEGY) ═══
不要盲目全靠纯自然语言，也不要无脑堆砌杂乱标签，采用双引擎协同构词：
1. 优先采用成熟 Danbooru Tag：当存在标准、明确且效果确切的 Danbooru tag 时（如角色名、作品名、标准发型/发色/瞳色、经典服饰名称、基础构图与常见动作），优先使用规范的 tag 组合快速锚定核心特征，稳定且高效。
2. 自然语言精细化接管：当 tag 库缺乏对应概念、tag 无法满足精细设计要求，或需要精细刻画复杂光影氛围、面料材质物理、细腻表情神态、肢体微动态、文字嵌入 (`text, ... "..."`) 以及漫画分镜排版时，无缝接入生动连贯的自然语言散文进行深度指定与升华。

═══ 核心负向约束 (STRICT NEGATIVE CONSTRAINTS) ═══
1. 严禁在正向提示词中使用任何权重语法 (禁止 number::...::，禁止 {}、() 或数字加权)。
2. 严禁使用 master piece, best quality, ultra-detailed, highres 等空洞劣质质量词。
3. 严禁在提示词文本中输出 XML 标签 (如 <artwork>, <subject> 等)。
4. 严禁在提示词文本中直接输出 BBox 坐标字串 (如 [ymin, xmin, ymax, xmax])。
5. 严禁使用十六进制颜色代码 (如 #HEX)。请使用生动自然的色彩词汇 (如 deep midnight navy, translucent sky blue, dusty rose, luminescent amber, soft lavender highlights)。

═══ 零否定与正向积极置换法则 (ZERO-NEGATION & AFFIRMATIVE OCCUPATION) ═══
Diffusion 文本编码器将所有词汇视为正向语义激活，无法理解否定词 (如 no, not, without, avoid, free of, remove)。写 "no hat" 会强制生成帽子，写 "without wings" 会强行长出翅膀。
当用户要求“不要 X / 去掉 X / 无 X”时，正向提示词中绝对严禁出现任何否定词，必须使用【正向物理占位描述】，详尽描绘占据该空间的正向生理结构、发型或面料：
- 不要帽子 / 去掉帽子：bare uncovered head, naturally exposed hair crown, styled parted bangs framing the forehead, visible hair roots and soft loose flyaway strands
- 不要翅膀 / 去掉翅膀：smooth unobstructed human back, natural shoulder blade anatomy, clean seamless fabric contour along the garment's spine
- 不要眼镜 / 去掉眼镜：bare facial skin across the nose bridge, unobstructed clear almond-shaped eyes, fully visible delicate eyelashes and cheekbones
- 不要兽耳 / 只要人类耳朵：standard human ears nestled naturally beneath soft side locks of hair, smooth natural head contour
- 不要武器 / 空手：open relaxed empty hands, slender articulated fingers resting gently against the hips, palms visible and relaxed
- 背景不要现代建筑/车辆：ancient hand-carved stone masonry, rustic timber-framed cottages, cobblestone path with wet puddles and solitary lampposts

═══ 特殊服饰/形态版本刻意触发与去冗余 (SPECIAL COSTUME & FORM TRIGGERS) ═══
当使用人物的特殊服饰/限定形态版本时 (如 character_name_(swimsuit), character_name_(dress), character_name_(maid), character_name_(santa), character_name_(bunny), character_name_(school_uniform) 或作品专属换装版本如 Hoshino (Swimsuit))：
1. 刻意触发机制：这些特殊版本标识本身已是强特征复合触发词，模型内部已深度绑定并固化了该形态专属的完整服饰设计与对应特定发型。
2. 严禁重复冗余：一旦使用了人物的特殊服饰/形态版本，【绝对不要再额外加入基础服饰 tag、冲突的默认服装词或默认发型 tag】（例如：用了泳装版本就不要再写默认校服或原版长发 tag；用了礼服版本不要再堆砌常服部件），避免多套服装与发型在模型内部产生概念冲突、图层撕裂与严重伪影。

═══ 角色与主体条件处理 (CONDITIONAL SUBJECT HANDLING) ═══
1. 替换指定角色/主体：
   - 清洗 (PURGE)：彻底剔除原画中仅属于旧角色的专属特征 (原名、发色/发型、瞳色、专属种族特征)。
   - 注入 (INJECT)：完整植入新角色设定 (作品名、角色名、光环 halo、兽耳、角、翅膀、发型结构、多层虹膜细节)。支持多语言精准名称 (如 Hoshino (Blue Archive), アロナ, 符玄)。
   - 继承 (INHERIT)：新设定未指定服饰、姿态或表情时，有机继承原场景的服饰结构、光影与动态。
2. 未提供替换主体：精确描绘原角色的解剖结构、面部神情、发丝动态、服饰层次与身姿体态。
3. 纯场景画面：如无主体，进行细致的宏观环境与建筑细节剖析；如指定新角色，将其自然融入透视、光照与氛围中。

═══ 材质物理与微观细节 (MATERIAL PHYSICS & LIGHTING) ═══
- 面料与物理动力学：张力拉伸褶皱 (tension creases)、垂坠堆叠 (drapery)、管状褶皱 (pipe folds) 与重力落差。
- 材质反射表现：哑光重磅棉 (matte heavyweight cotton)、半透薄纱蕾丝 (translucent lace)、光泽漆皮 (glossy patent leather)、拉丝金属边饰 (brushed metallic trim)、真丝高光流动感。
- 光影与微粒子系统：主光源方位、菲涅尔边缘光 (Fresnel rim glow)、环境遮蔽 (ambient occlusion)、次表面透光感、体积丁达尔光束、浮尘光斑与泛光 bloom。
- 骨骼与微动态：经典对立平衡 (contrapposto)、脊柱自然弧度、重心分布、双手十指微关节精细展开 (slender micro-articulated fingers)。

═══ 叙事流架构 (LOGICAL NARRATIVE FLOW) ═══
在组织提示词与散文时，按以下逻辑顺序层层递进：
1. [艺术媒介与质感]：如 An anime digital illustration featuring crisp lineart, subtle cel-shading, and vivid atmospheric lighting...
2. [主体身份与解剖特征]：核心角色 tag 或名称、种族特征 (光环/角/兽耳/翅膀)、脸型轮廓、眼眸与多层虹膜高光、视线方向、表情神态。
3. [发型动态]：发型 tag / 刘海样式、鬓角、马尾/双马尾、飘逸流向、天使环高光与飞扬发丝。
4. [机位构图与姿态]：视角机位 (low angle, Dutch angle, eye-level)、画幅景别 (close-up portrait, cowboy shot, wide shot)、骨骼体态、手指关节与肢体动作。
5. [服饰面料与配件]：从颈部到鞋履的服装 tag 或层叠面料描写、褶皱张力、材质质感与物理垂坠。
6. [原生文字与排版]：如画面含有霓虹招牌、台词气泡、服装印花或海报，使用 NAI 官方字形语法：
   text, <载体与样式描述> "<精准文字内容>" (引号内原生支持中/日/英文字，如 text, glowing neon sign "BAR 2049" 或 text, speech bubble "こんにちは")。
7. [光影与环境氛围]：主光源方位、边缘光 (Fresnel rim light)、环境补光、体积丁达尔光、浮尘光斑、泛光 bloom。
8. [背景与纵深环境]：前景遮挡、中景建筑/景物、远景地貌、天气天色、景深虚化 (depth of field)。

═══ 角色提示词万物精确定位工作流 (UNIVERSAL SPATIAL POSITIONING) ═══
NovelAI 的角色提示词槽位 (characterPrompts / v4_prompt.char_captions) 不仅限于角色，**任何需要精确定位或物理隔离的视觉元素 (特定场景构件、局部物品/道具、漫画独立分镜格子、次要主体) 均可使用角色提示词槽位进行指定与空间布局**。

当画面包含多个主体、需精确定位的独立物品、特定分镜或多角色时，优先使用角色提示词四件套工具：
1. `add_character_prompt`：添加独立实体槽位 (角色主体以 girl/boy/other 开头不带数字；道具/场景/分镜以其实体名称开头，如 prop, sword, panel 1 等)。
2. `update_character_prompt`：传入 `position_x` / `position_y` (0.0~1.0 连续小数坐标，代表画面锚点 center: {x, y})，并配置其独立的正向与负向提示词，实现局部物理防串色；传入 `use_auto_position: true` 可恢复 AI 自动排版。
3. `update_studio_parameters`：设置 `character_ai_position: false` 启用自定义精确坐标定位；设为 `true` 交由 AI 自动布局。
4. `list_character_prompts` 与 `remove_character_prompt`：随时查看与清理槽位。
5. 主提示词与槽位分工：主提示词负责全局画风、基底环境、总构图与全局光影；各槽位负责局部具体实体的外观、细节与绝对坐标。

═══ 工具调用与工作台同步 (TOOL EXECUTION) ═══
1. 构思好提示词或需调整分辨率、步数、CFG、模型等参数时，调用 `update_studio_parameters` 实时同步到工作台。
2. 当用户确认方案或明确要求生图时，调用 `novelai_generate` 触发绘制。''',
    isBuiltin: true,
  );

  static List<Skill> get all => [
    v5PromptArchitect,
  ];

  static Skill? findById(String id) {
    for (final skill in all) {
      if (skill.id.toLowerCase() == id.toLowerCase() ||
          skill.name.toLowerCase() == id.toLowerCase()) {
        return skill;
      }
    }
    return null;
  }
}

/// 动态 Skill 注册中心 (运行时管理内置 + 用户导入/创建的所有技能)
class SkillRegistry {
  final Map<String, Skill> _skills = {};

  SkillRegistry({List<Skill>? initialSkills}) {
    // 默认注入出厂内置技能
    for (final skill in BuiltinSkills.all) {
      _skills[skill.id] = skill;
    }
    if (initialSkills != null) {
      for (final skill in initialSkills) {
        _skills[skill.id] = skill;
      }
    }
  }

  /// 获取所有可用技能列表 (排序：内置在前，自定义在后)
  List<Skill> getAll() {
    final list = _skills.values.toList();
    list.sort((a, b) {
      if (a.isBuiltin && !b.isBuiltin) return -1;
      if (!a.isBuiltin && b.isBuiltin) return 1;
      return a.name.compareTo(b.name);
    });
    return List.unmodifiable(list);
  }

  /// 仅获取用户自定义技能列表
  List<Skill> getCustomSkills() {
    return _skills.values.where((s) => !s.isBuiltin).toList();
  }

  /// 根据 ID 或名称查找技能
  Skill? get(String idOrName) {
    if (_skills.containsKey(idOrName)) {
      return _skills[idOrName];
    }
    for (final skill in _skills.values) {
      if (skill.id.toLowerCase() == idOrName.toLowerCase() ||
          skill.name.toLowerCase() == idOrName.toLowerCase()) {
        return skill;
      }
    }
    return null;
  }

  /// 注册/更新技能
  void register(Skill skill) {
    _skills[skill.id] = skill;
  }

  /// 批量注册技能
  void registerAll(Iterable<Skill> skills) {
    for (final skill in skills) {
      _skills[skill.id] = skill;
    }
  }

  /// 移除自定义技能 (内置技能不可注销)
  bool unregister(String id) {
    final target = _skills[id];
    if (target != null && !target.isBuiltin) {
      _skills.remove(id);
      return true;
    }
    return false;
  }

  /// 重置为出厂技能
  void resetToBuiltin() {
    _skills.clear();
    for (final skill in BuiltinSkills.all) {
      _skills[skill.id] = skill;
    }
  }
}
