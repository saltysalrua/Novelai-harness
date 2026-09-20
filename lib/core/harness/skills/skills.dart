import 'skill_format_exception.dart';
import 'dart:convert';
import 'package:yaml/yaml.dart';

/// 技能模型 (按标准 Pi / Agent Skills 规范定义)
class Skill {
  final String id;
  final String name;
  final String description;
  final String systemPrompt;
  final bool disableModelInvocation;
  final bool isBuiltin;

  /// 应用托管目录的随机键，不接受技能文档中的路径作为存储位置。
  final String? packageId;
  final List<String> resourcePaths;

  /// 保留 license / compatibility / metadata / allowed-tools 等扩展字段。
  /// allowed-tools 仅是文档元数据，不授予运行时权限。
  final Map<String, Object?> extraFrontmatter;

  const Skill({
    required this.id,
    required this.name,
    required this.description,
    required this.systemPrompt,
    this.disableModelInvocation = false,
    this.isBuiltin = false,
    this.packageId,
    this.resourcePaths = const [],
    this.extraFrontmatter = const {},
  });

  Skill copyWith({
    String? id,
    String? name,
    String? description,
    String? systemPrompt,
    bool? disableModelInvocation,
    bool? isBuiltin,
    String? packageId,
    List<String>? resourcePaths,
    Map<String, Object?>? extraFrontmatter,
  }) {
    return Skill(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      disableModelInvocation:
          disableModelInvocation ?? this.disableModelInvocation,
      isBuiltin: isBuiltin ?? this.isBuiltin,
      packageId: packageId ?? this.packageId,
      resourcePaths: resourcePaths ?? this.resourcePaths,
      extraFrontmatter: extraFrontmatter ?? this.extraFrontmatter,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'systemPrompt': systemPrompt,
    'disableModelInvocation': disableModelInvocation,
    'isBuiltin': isBuiltin,
    if (packageId != null) 'packageId': packageId,
    if (resourcePaths.isNotEmpty) 'resourcePaths': resourcePaths,
    if (extraFrontmatter.isNotEmpty) 'extraFrontmatter': extraFrontmatter,
  };

  factory Skill.fromJson(Map<String, dynamic> json) => Skill(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? (json['id'] as String? ?? ''),
    description: json['description'] as String? ?? '',
    systemPrompt: json['systemPrompt'] as String? ?? '',
    disableModelInvocation: json['disableModelInvocation'] as bool? ?? false,
    isBuiltin: json['isBuiltin'] as bool? ?? false,
    packageId: json['packageId'] as String?,
    resourcePaths:
        (json['resourcePaths'] as List?)?.whereType<String>().toList() ??
        const [],
    extraFrontmatter: switch (json['extraFrontmatter']) {
      Map<String, dynamic> fields => Map<String, Object?>.from(fields),
      _ => const {},
    },
  );

  /// 导出标准 YAML；JSON 值语法也是合法 YAML，能无损保留多行及嵌套字段。
  String toSkillMd() {
    final fields = <String, Object?>{
      ...extraFrontmatter,
      'name': id,
      'description': description,
      if (name != id) 'label': name,
      if (disableModelInvocation) 'disable-model-invocation': true,
    };
    return '---\n${fields.entries.map((e) => '${_yamlValue(e.key)}: ${_yamlValue(e.value)}').join('\n')}\n---\n\n${systemPrompt.trim()}\n';
  }

  static String _yamlValue(Object? value) {
    if (value is String &&
        RegExp(
          r'^[a-zA-Z\u4e00-\u9fff][a-zA-Z0-9\u4e00-\u9fff _/-]*$',
        ).hasMatch(value) &&
        value.trim() == value &&
        loadYaml(value) == value) {
      return value;
    }
    return jsonEncode(value);
  }

  /// 从标准 SKILL.md 导入。独立文本仍兼容无 Frontmatter 的旧格式。
  factory Skill.fromSkillMd(String content, {String? defaultId}) {
    final normalized = content
        .replaceFirst(RegExp(r'^\uFEFF'), '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .trimLeft();
    if (!normalized.startsWith('---\n')) {
      final firstLine = normalized.trim().split('\n').first;
      return Skill(
        id: defaultId ?? 'custom-skill',
        name:
            defaultId ??
            (firstLine.startsWith('#')
                ? firstLine.replaceAll('#', '').trim()
                : 'custom-skill'),
        description: '从文本导入的自定义技能',
        systemPrompt: normalized.trim(),
      );
    }
    final end = RegExp(
      r'^---[ 	]*$',
      multiLine: true,
    ).firstMatch(normalized.substring(4));
    if (end == null) {
      throw const SkillFormatException(
        SkillFormatError.yamlDelimiter,
        'SKILL.md 的 YAML 头缺少结束分隔符。',
      );
    }
    final raw = normalized.substring(4, 4 + end.start);
    final Object? yaml;
    try {
      yaml = loadYaml(raw);
    } on YamlException catch (error) {
      throw SkillFormatException(
        SkillFormatError.yamlInvalid,
        'SKILL.md YAML 格式错误：${error.message}',
        detail: error.message,
      );
    }
    if (yaml is! Map) {
      throw const SkillFormatException(
        SkillFormatError.yamlMapping,
        'SKILL.md 的 YAML 头必须是字段映射。',
      );
    }
    var nodes = 0;
    Object? convert(Object? value, [int depth = 0]) {
      if (++nodes > 4096 || depth > 20) {
        throw const SkillFormatException(
          SkillFormatError.yamlDepth,
          'SKILL.md YAML 嵌套过深或字段过多。',
        );
      }
      return switch (value) {
        null || String() || bool() || num() => value,
        List() => value.map((v) => convert(v, depth + 1)).toList(),
        Map() => <String, Object?>{
          for (final entry in value.entries)
            (entry.key is String
                ? entry.key as String
                : throw const SkillFormatException(
                    SkillFormatError.yamlKeys,
                    'YAML 字段名必须是字符串。',
                  )): convert(
              entry.value,
              depth + 1,
            ),
        },
        _ => throw const SkillFormatException(
          SkillFormatError.yamlValue,
          '不支持的 YAML 值。',
        ),
      };
    }

    final fields = convert(yaml) as Map<String, Object?>;
    String text(String key, [String fallback = '']) {
      final value = fields[key];
      if (value == null) return fallback;
      if (value is! String) {
        throw SkillFormatException(
          SkillFormatError.yamlString,
          'SKILL.md 的 $key 必须是字符串。',
          detail: key,
        );
      }
      return value;
    }

    final id = text('name', defaultId ?? 'custom-skill');
    final label = text('label', text('display_name', text('title', id)));
    final desc = text('description', text('desc'));
    final disabled =
        fields['disable-model-invocation'] ??
        fields['disable_model_invocation'] ??
        false;
    if (disabled is! bool) {
      throw const SkillFormatException(
        SkillFormatError.yamlBoolean,
        'disable-model-invocation 必须是布尔值。',
      );
    }
    for (final key in [
      'name',
      'description',
      'desc',
      'label',
      'display_name',
      'title',
      'disable-model-invocation',
      'disable_model_invocation',
    ]) {
      fields.remove(key);
    }
    return Skill(
      id: id,
      name: label,
      description: desc,
      systemPrompt: normalized.substring(4 + end.end).trim(),
      disableModelInvocation: disabled,
      extraFrontmatter: Map.unmodifiable(fields),
    );
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
        '专注于 NovelAI 提示词构思、多主体定位与漫画分镜排版：结合 Danbooru 标签与自然语言，支持万物精准空间布局与动态分镜。',
    systemPrompt: '''把用户的想法重构为适合 NAI (V5/V4.5) 的高质量提示词，排布好空间构图与画面细节。

提示词怎么写：
- 标签与自然语言配合：确切且标准的特征（角色名、作品名、基础动作、核心姿态）优先用标准 Danbooru 标签快速锁定；非用户明确要求，绝对不要擅自添加衣服与发型等 tag（详见下方核心禁令）；复杂的环境氛围、光影质感、细腻表情神态与漫画分镜，用生动连贯的自然语言补充。
- 负向规矩：正向提示词严禁写权重符号（如 {}、()、数字加权，但保留角色标签原本自带的括号）；不要手动追加 master piece、best quality 等空洞质量词（工作台会自动加）；不要输出 XML 标签、BBox 坐标或十六进制色号（使用生动的自然色彩词汇）。

严禁擅自添加衣服/发型等 tag（特别是版权角色与皮肤换装）：
- 非用户明确要求，严禁擅自添加衣服与发型 tag：绘图模型对二次元角色及其服装设定拥有极强的先验还原能力。非用户明确要求，绝对不可擅自追加任何衣服、裙子、鞋袜、发型、发饰等 tag，避免画蛇添足与过度约束（over-prompting）。
- 版权角色自带完整外观：标准版权角色标签（如角色名、作品名）本身已经包含了该角色的默认发型、经典服装与特征外观，无需也不应额外列举服饰与发型 tag。
- 皮肤与限定换装（强绑定机制，严禁干扰）：形如 xxx(角色名) (xxx/皮肤名) (xxx/作品名) 这种格式（例如 amiya (fresh planter) (arknights)、chen (ageless afterglow) (arknights)、miku hatsune (racing 2023) (vocaloid) 等标准皮肤标签）是该角色的专属皮肤/换装。这类标签在模型内部已经强绑定并内化了该皮肤专属的服装款式、专属发型、特殊头饰与设计细节。非用户明确要求，绝对不应该添加任何衣服、发型等 tag 来干扰模型！若额外追加外部衣服或发型 tag，会导致两套服装/发型设定在模型内部打架撕裂，严重破坏原版皮肤的准确还原。
- 常规形态标签同样适用：若角色带有常规形态标签（如 swimsuit、dress、maid 等），这类标签同样已绑定了专属服饰与造型，切勿再额外添加原版默认服装或原版发型标签，避免冲突。
- 仅在用户明确指定时添加：仅在以下情况才允许编写衣服或发型相关描述：
  1. 用户明确要求更改或指定发型（例如：“换成双马尾”、“短发”）；
  2. 用户明确要求换装或指定衣服（例如：“穿常服卫衣”、“换上白色水手服”）；
  3. 原创角色（OC，如 1girl 且无现成角色 tag），按用户设定构思外貌；
  4. 用户对服装细节有动态或微观要求（例如：“被风吹起微扬的裙摆”），用自然语言补充。

如何表达“不要某些东西”（正向物理占位）：
- 绘图模型不理解否定词（写 no xxx、without xxx 反而会强制画出该物品）。
- 做法：用户说不要什么，先在正向词里直接删掉它，需要排斥的概念放进负向词。如果该部位需要露出来或维持身体结构，用你希望实际看到的身体部位或环境去描写它。比如不要头饰就写自然露出的头顶与发丝细节，不要遮挡就描写干净的皮肤或背景，空手就描写放松自然展开的手指。教模型描述“有什么”，而不是“没什么”，根据具体画面自由发挥。

画面文字写在角色槽位里：
- 画面中所有要呈现的文字（台词气泡、霓虹招牌、海报标语、衣服印花等），一律写在对应的角色提示词槽位里，不要写在主提示词中。
- 做法与优势：
  - 角色自己的台词气泡或服装印花，直接写进该角色的提示词槽位；
  - 独立的背景招牌、路标或分镜文字，单独开一个实体槽位（如命名为 prop 或 text）；
  - 结合 position_x/y 精准定位文字出现的画面位置，同时利用槽位隔离避免文字污染全局画面；
  - 语法格式：用载体描述加引号内容，如 text, speech bubble "こんにちは"、text, t-shirt print "HERO"、text, neon sign "BAR 2049"，引号内支持中英日文。V5 自动文字由工作台处理，不重复注入 teXt 段。

画漫画与多样分镜：
- 严禁死板的等分格子（不要画千篇一律的上下对半分或四等分格子）。
- 根据剧情节奏与画面张力设计多样的分镜排版：
  - 景别强烈反差：大特写（抓情绪）与电影感宽画幅全景（交待环境）结合，突出视线焦点。
  - 动态与异形分镜：使用斜切分割（diagonal panels）、破格出框（打破边框的角色或动作）、跨格大画幅（establishing panel），表现战斗冲击力或速度感。
  - 分镜槽位分工：主提示词负责整页漫画风格与排版氛围（如 manga page, dynamic paneling, dramatic layout），用角色槽位配合不同坐标（position_x/y）分别指定各个分镜格子里的独立画面、角色动作与景别，形成流畅的视线阅读流。

画面质感自由发挥：
- 不要机械堆词，从几个核心维度去生动展开：面料的褶皱与垂坠感、不同材质的反光表现（哑光、光泽、透光）、光源方向与边缘轮廓光、身体重心的对立平衡与手指关节微动态，按画面需要灵活构思。

画面不够精细与构图透视修正（在已有元素上写空间关系，严禁乱加东西）：
- 严禁乱加新东西凑细节：用户觉得画面不够精细、细节不足，或者觉得构图透视不对时，绝对不要往画面里加新的物体、新的饰品、碎屑飘花或者多余背景！乱加东西只会让画面变得又乱又挤。
- 怎么干（就用画面里已有的东西，说清楚它们的位置和相互关系）：
  - 谁在前谁在后：讲清楚现有的角色、物体和背景之间谁在前面、谁在后面、谁挡住了谁的一角、彼此隔着多远。
  - 视角怎么看：讲清楚镜头是从什么角度拍的（是从下往上仰视、平视还是从上往下俯视），近处的偏大、远处的收窄。
  - 怎么接触受力：讲清楚角色和现有东西是怎么碰在一起的（比如脚踩在地面上的贴合与受重、手是怎么握紧手里已有道具的、坐下时衣服在椅子上的压痕褶皱）。
  - 影子打在哪：讲清楚光照下来时，现有东西的影子投在什么地方（比如下巴在脖子上的阴影、落在地面上的影子），用影子和贴合关系把立体感带出来。

多主体与画面万物定位：
- 角色槽位（characterPrompts）不局限于角色，场景构件、道具、漫画分镜格子、画面文字等任何需要固定位置或防串色的元素都能用。
- 槽位命名：人物主体以 girl/boy/other 开头（不带数字）；道具、文字或分镜以名称开头（如 prop, text, sword, panel 1）。遵守当前模型数量限制。
- 坐标定位：需要精确定位时，传入 position_x/y（0.0~1.0 连续小数，代表画面中心锚点），并在工作台参数把 character_ai_position 设为 false；设为 true 恢复自动排版。主提示词管总人数与全局环境，各槽位管自己的外观与坐标，避免重复描写。

换角色与未知角色：
- 换角色：彻底去掉旧角色的专属特征，填入新角色的设定；保留未要求改变的场景、姿态与光照。
- 不确定外貌的角色：绝对不要瞎编外貌和衣服。优先向用户确认或查资料；若确需通过生图探查外观，仅使用角色单标签生成一次，不要凭空加修饰；生成图不是设定的事实证据，不强制额外生图探测。

操作执行：
- 提示词长度按当前模型和工作台 Token 状态合理安排，为质量词和自动文字留出余量。
- 按需读取参数 keys，修改时用一次 update_studio_parameters 批量提交，没变的不传。
- 用户确认方案或明确要求生图时才调用 novelai_generate，仅讨论或修改参数时不擅自生成。成图后简短汇报，不重复大段提示词。''',
    isBuiltin: true,
  );

  /// 2. NovelAI 局部修复与图像重绘专家
  static const Skill inpaintSpecialist = Skill(
    id: 'inpaint-specialist',
    name: 'NovelAI 局部修复与图像重绘专家',
    description:
        '专注于 NovelAI 局部重绘 (Inpaint) 与外部大模型整图编辑 (AI Edit)：严格执行基底保持与最小修改原则，支持画板批注联动、同源提示词局部替换、焦点特写超采样与大模型前置保真约束。',
    systemPrompt: '''用最小的必要改动修好画面，保留用户没要求改的所有画风、角色特征、构图、衣服和光照。

核心原则：改哪写哪，其他完全不动
- 修图最忌推倒重写导致画风或容貌走样。用户要改哪里，提示词就只替换目标部位的描述，其他没改的地方（画风、角色面貌特征、服装部件、背景光影）必须和原图提示词保持完全一致。
- 严禁擅自追加衣服与发型 tag：非用户明确要求改动服饰或发型，绝对不要在未改动区域额外添加衣服、发型等描述；特别是涉及版权角色或形如 xxx(角色名) (xxx/皮肤名) (xxx/作品名) 的皮肤换装标签时，保持原有结构，切勿添加多余 tag 干扰模型。
- 不清楚原图参数先查，不凭空捏造。
- 遇到去除物品或修多指，同样用正向描述占位（比如修手写自然张开的五根手指，不要写 without extra fingers）。需要移除的词从正向词中删掉，排除项写入负向词。

NovelAI 局部修复：
- 选区与批注：优先调用 view_image_annotations 获取用户在画板上框选的选区或图钉（通过 annotation_id）。批注只提供几何位置与意图，绝不能当成提示词直接发；如果不需要改词，prompt 留空复用工作台提示词。
- 模式选择：小范围五官、眼睛、手部和细节微雕，优先用 focus 模式（系统自动外延 64 像素并按选区比例等比上采样到约 100 万像素潜空间，贴回原图无损清晰）；大范围换装或大面积修改用 standard 模式。不要假定支持画布外延。
- 参数调整：去噪强度（strength）按修改幅度自行判断（微调修瑕调低，大幅替换调高），附加噪声（noise）通常保持为 0，具体参数范围以工具为准。
- 点数费用：费用以工具返回及账号状态为准，不提前假设免费。

外部大模型整图编辑 (ai_edit_image)：
- 外部模型改图是重新画整张图，没有像素遮罩保护，极容易全图画风漂移。
- 提示词写法：必须先明确要求“严格保持原图的画风、整体构图、角色长相、服饰与光照”，紧接着再说明具体要改动的部位与效果。用户明确要求修改的属性不要自相矛盾地要求保持。
- 避免模糊指令：绝不要直接发一句“把眼睛修好”或“换个背景”，必须带上前置保真要求。

执行与交付：
- 局部瑕疵用 novelai_inpaint，需要全图自然语言大改才考虑 ai_edit_image。
- 画面有多处瑕疵时，分散目标建议分步依次修复，切忌一次同时修改多个分散区域导致效果失控。
- 修复完成后检查边缘过渡与画面协调性，简短向用户汇报；没实际看图时不随意断言效果完美。''',
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
