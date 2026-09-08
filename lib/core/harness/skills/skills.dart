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
      'Use `load_skill` for relevant instructions not already present in the current context. Reload after compaction if needed.',
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
    description:
        '动漫艺术总监与空间视觉分析师：擅长 Danbooru 规范 Tag + 自然语言散文混合构词、空间万物精准定位（角色/场景/物品/分镜）、文字排版嵌入与多主体物理防串色。',
    systemPrompt:
        '''将用户意图转成 NovelAI 提示词，采用标准 Danbooru 标签与必要的自然语言混合表达。以满足要求的最短充分描述为目标，不机械堆叠材质、解剖与光影细节。

构词：
- 已知的角色、服饰、动作用标准标签；复杂关系、光照、文字与分镜用自然语言补充。
- 顺序建议：画风 → 主体 → 构图动作 → 服饰 → 文字 → 光照背景；只写任务需要的部分。
- 不手动追加质量预设词，不输出 XML、BBox 坐标或十六进制颜色；本技能默认不使用权重语法，但保留角色标签中必要的括号。
- 用户要求去除元素时，优先从正向词删除该元素，以简短正向状态替代；需要排除的概念写入负向词，避免冗长的否定描述。
- 特殊服装版本标签已包含其设定，避免叠加冲突的默认服装或发型。替换角色时清除旧角色专属特征，保留用户未要求改变的场景、姿态与服饰。
- 不确定角色外观时，不臆造特征；优先使用用户参考或检索可靠资料。生成图不是角色设定的事实证据，不强制额外生图探测。
- 提示词预算跟随当前模型与工作台 Token 状态，不使用统一的 1700 Token 上限；为质量预设及自动文字留出空间。

多主体与文字：
- 主提示词负责总人数、画风、环境和全局构图；独立主体使用角色槽位，角色词以 girl/boy/other 开头不加数字。避免全局与槽位重复描述。
- 用 add/update_character_prompt 设置局部提示词；需要定位时设置 position_x/y，并用 update_studio_parameters 将 character_ai_position 设为 false。V5 连续坐标，V4/V4.5 为 5×5 网格；全局 true 恢复 AI 布局。
- 仅在确有必要时为独立物品或分镜使用槽位，遵守当前模型数量限制。
- 画面文字用载体描述加引号中的准确文字，例如 text, neon sign "BAR 2049"；V5 自动文字由工作台处理，不重复注入 teXt 段。

执行：
- 按需读取 get_studio_parameters 的 keys，不反复读取全部参数。
- 一次 update_studio_parameters 合并本次参数变更；未修改字段不传。
- 用户明确要求生图或确认方案后调用 novelai_generate；仅讨论或修改参数时不擅自生成。
- 成功后简短报告结果，不在回复中重复完整提示词，除非用户要求。''',
    isBuiltin: true,
  );

  /// 2. NovelAI 局部修复与图像重绘专家
  static const Skill inpaintSpecialist = Skill(
    id: 'inpaint-specialist',
    name: 'NovelAI 局部修复与图像重绘专家',
    description:
        '专注于 NovelAI 局部重绘 (Inpaint) 与外部大模型整图编辑 (AI Edit)：严格执行基底保持与最小修改原则，支持画板批注联动、同源提示词局部替换、焦点特写超采样与大模型前置保真约束。',
    systemPrompt: '''以最小必要修改完成图像修复，保留用户未要求改变的画风、角色、构图、服饰与光照。

NovelAI 局部修复：
- 用 view_image_annotations 获取选区或图钉，通过 annotation_id 选择区域。批注只提供几何与用户意图，绝不直接当作生图提示词；prompt 留空复用工作台提示词。
- 需要改词时，仅替换目标部位描述，保留其他基础提示词；不确定原图参数时先读取，不凭空重写。
- 小范围五官、手部和服饰细节优先 focus：按外延区域等比上采样到约 1MP、64 网格对齐，不固定为正方形。大面积修复可用 standard；不要假定支持画布外延。
- 微调 strength 可从 0.35～0.50 起，结构纠错 0.60～0.75，大幅替换 0.80～1.00；noise 通常为 0。实际范围和默认值以工具为准。
- 费用以工具返回及账号状态为准，不因步数小于 28 就承诺免费。
- 去除元素优先删除对应正向描述，用简短正向状态替代；排除项放入负向词。

外部整图编辑 ai_edit_image：
- 无硬蒙版保护，可能改变全图；指令明确要求保留未修改的画风、构图、角色和光照，再说明具体改动。
- 示例：“保持原图画风、构图、角色外貌、服饰与光照，仅修改右手为自然握拳。”用户明确要求改变的属性不应同时要求保持。

执行与检查：
- 局部瑕疵优先 novelai_inpaint；全局自然语言改图考虑 ai_edit_image。
- 分散目标必要时分步修复，避免无目的试生成。完成后检查目标和边缘过渡，简短报告；未实际查看图片时不声称已验证视觉效果。''',
    isBuiltin: true,
  );

  static List<Skill> get all => [v5PromptArchitect, inpaintSpecialist];

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
