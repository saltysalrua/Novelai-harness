import '../../../data/models/novelai_models.dart';
import '../types.dart';
import 'agent_tool.dart';

/// 回调类型：获取当前角色提示词列表
typedef CharacterPromptsGetter = List<NaiCharacterPrompt> Function();

/// 回调类型：整体更新角色提示词列表 (同步工作台 UI)
typedef CharacterPromptsUpdater =
    void Function(List<NaiCharacterPrompt> characters);

/// 回调类型：获取当前模型的角色数量上限 (V5=22，V4/V4.5=6，v3=0)
typedef CharacterLimitGetter = int Function();

/// 回调类型：获取全局角色位置模式 (true = AI 自动布局)
typedef CharacterAiPositionGetter = bool Function();

/// 构建角色提示词列表可读报表 (list 工具与参数报表共用)
String buildCharacterPromptsReport(
  List<NaiCharacterPrompt> characters, {
  bool aiPosition = true,
}) {
  if (characters.isEmpty) {
    return '当前没有角色提示词 (单角色场景无需配置，主提示词即可)。';
  }
  final positionMode = aiPosition
      ? 'AI 自动布局 (官方 AI\'s Choice，不发送位置参数)'
      : '自定义定位 (发送 use_coords 与各角色 center)';
  final lines = characters.asMap().entries.map((entry) {
    final index = entry.key;
    final c = entry.value;
    final position = c.useCustomPosition
        ? '手动 (${(c.positionX * 100).toStringAsFixed(0)}%, ${(c.positionY * 100).toStringAsFixed(0)}%)'
        : '自动布局';
    return [
      '[$index] ${c.name} (id: ${c.id})',
      '    状态: ${c.enabled ? '启用' : '停用'} | 定位: $position',
      '    正向: ${c.prompt.isEmpty ? '(空)' : c.prompt}',
      '    负面: ${c.negativePrompt.isEmpty ? '(空)' : c.negativePrompt}',
    ].join('\n');
  });
  return '共 ${characters.length} 个角色提示词，位置模式: $positionMode。\n${lines.join('\n')}';
}

/// 角色提示词列表查询工具
class NovelAiListCharacterPromptsTool extends AgentTool {
  final CharacterPromptsGetter getCharacterPrompts;
  final CharacterAiPositionGetter? getAiPosition;

  NovelAiListCharacterPromptsTool({
    required this.getCharacterPrompts,
    this.getAiPosition,
  }) : super(
         name: 'list_character_prompts',
         label: '角色列表',
         description: '查看工作台当前的全部多角色提示词 (id、名称、启停、定位与正负提示词) 与全局位置模式。',
         parameters: const {'type': 'object', 'properties': {}},
       );

  @override
  Future<ToolResult> execute(
    String toolCallId,
    Map<String, dynamic> args,
  ) async {
    return ToolResult(
      toolCallId: toolCallId,
      content: buildCharacterPromptsReport(
        getCharacterPrompts(),
        aiPosition: getAiPosition?.call() ?? true,
      ),
    );
  }
}

/// 角色提示词添加工具
class NovelAiAddCharacterPromptTool extends AgentTool {
  final CharacterPromptsGetter getCharacterPrompts;
  final CharacterPromptsUpdater updateCharacterPrompts;
  final CharacterLimitGetter? getCharacterLimit;

  NovelAiAddCharacterPromptTool({
    required this.getCharacterPrompts,
    required this.updateCharacterPrompts,
    this.getCharacterLimit,
  }) : super(
         name: 'add_character_prompt',
         label: '添加角色',
         description:
             '为工作台添加一个多角色提示词 (V5 最多 22 个，V4/V4.5 最多 6 个)。添加后可配合 novelai_generate 进行多角色隔离生图；修改已有角色请用 update_character_prompt。',
         parameters: const {
           'type': 'object',
           'properties': {
             'name': {
               'type': 'string',
               'description': '角色名称 (仅本地标识，如 "左边的银发少女"；留空自动命名)',
             },
             'prompt': {
               'type': 'string',
               'description':
                   '该角色的正向提示词 (以 girl/boy/other 等人数标签开头，不加数字；总人数标签如 2girls 写在主提示词)',
             },
             'negative_prompt': {
               'type': 'string',
               'description': '该角色专属的负面提示词 (留空则不排除)',
             },
             'position_x': {
               'type': 'number',
               'description':
                   '定位坐标 X，0.0=画面最左，1.0=最右 (仅全局自定义定位模式下生效，V5 为连续小数，V4/V4.5 量化到 5x5 网格)',
             },
             'position_y': {
               'type': 'number',
               'description': '定位坐标 Y，0.0=画面最上，1.0=最下',
             },
           },
           'required': ['prompt'],
         },
       );

  @override
  Future<ToolResult> execute(
    String toolCallId,
    Map<String, dynamic> args,
  ) async {
    final characters = getCharacterPrompts();
    final limit = getCharacterLimit?.call() ?? 6;
    if (characters.length >= limit) {
      return ToolResult(
        toolCallId: toolCallId,
        content:
            '错误：当前模型角色提示词已达上限 $limit 个，请先用 remove_character_prompt 删除后再添加。',
        isError: true,
      );
    }

    final prompt = (args['prompt'] as String?)?.trim() ?? '';
    if (prompt.isEmpty) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '错误：prompt (角色正向提示词) 不能为空。',
        isError: true,
      );
    }

    final positionX = ((args['position_x'] as num?)?.toDouble() ?? 0.5).clamp(
      0.0,
      1.0,
    );
    final positionY = ((args['position_y'] as num?)?.toDouble() ?? 0.5).clamp(
      0.0,
      1.0,
    );
    final name = (args['name'] as String?)?.trim().isNotEmpty == true
        ? args['name'] as String
        : '角色 ${characters.length + 1}';

    // 传入了任一坐标即视为手动定位；未传则按启用顺序自动布局
    final hasPosition =
        args['position_x'] != null || args['position_y'] != null;
    final character =
        NaiCharacterPrompt.create(
          name: name,
          prompt: prompt,
          negativePrompt: (args['negative_prompt'] as String?) ?? '',
        ).copyWith(
          useCustomPosition: hasPosition,
          positionX: positionX,
          positionY: positionY,
        );

    updateCharacterPrompts([...characters, character]);

    return ToolResult(
      toolCallId: toolCallId,
      content:
          '已添加角色提示词并同步到工作台 UI：\n'
          '• 名称: ${character.name}\n'
          '• ID: ${character.id}\n'
          '• 正向提示词: ${character.prompt}\n'
          '• 负面提示词: ${character.negativePrompt.isEmpty ? '(空)' : character.negativePrompt}\n'
          '• 定位: ${character.useCustomPosition ? '手动 ($positionX, $positionY)' : '自动布局 (跟随全局 AI 自动 / 自定义模式)'}\n'
          '当前共 ${characters.length + 1} 个角色。后续修改或删除该角色请引用 ID: ${character.id}。',
    );
  }
}

/// 角色提示词修改工具
class NovelAiUpdateCharacterPromptTool extends AgentTool {
  final CharacterPromptsGetter getCharacterPrompts;
  final CharacterPromptsUpdater updateCharacterPrompts;

  NovelAiUpdateCharacterPromptTool({
    required this.getCharacterPrompts,
    required this.updateCharacterPrompts,
  }) : super(
         name: 'update_character_prompt',
         label: '修改角色',
         description:
             '按 ID 修改已有的角色提示词，只需传入要修改的字段 (名称/正负提示词/启停/定位坐标)，未传入的字段保持不变。全局位置模式 (AI 自动 / 自定义) 请用 update_studio_parameters 的 character_ai_position 参数切换。',
         parameters: const {
           'type': 'object',
           'properties': {
             'id': {
               'type': 'string',
               'description':
                   '目标角色的 8 位十六进制 ID (可先用 list_character_prompts 查询)',
             },
             'name': {'type': 'string', 'description': '新的角色名称'},
             'prompt': {'type': 'string', 'description': '新的正向提示词'},
             'negative_prompt': {'type': 'string', 'description': '新的负面提示词'},
             'enabled': {
               'type': 'boolean',
               'description': '是否启用该角色 (false 则不参与生成)',
             },
             'position_x': {
               'type': 'number',
               'description': '定位坐标 X (0.0~1.0，传入即视为手动定位)',
             },
             'position_y': {
               'type': 'number',
               'description': '定位坐标 Y (0.0~1.0)',
             },
             'use_auto_position': {
               'type': 'boolean',
               'description': 'true 时清除手动定位，恢复按启用顺序自动布局',
             },
           },
           'required': ['id'],
         },
       );

  @override
  Future<ToolResult> execute(
    String toolCallId,
    Map<String, dynamic> args,
  ) async {
    final characters = getCharacterPrompts();
    final id = args['id'] as String?;
    if (id == null || id.trim().isEmpty) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '错误：必须传入目标角色的 id (8 位十六进制)。',
        isError: true,
      );
    }
    final index = characters.indexWhere((c) => c.id == id.trim());
    if (index < 0) {
      return ToolResult(
        toolCallId: toolCallId,
        content:
            '错误：未找到 ID 为 ${id.trim()} 的角色。当前角色：'
            '${characters.isEmpty ? '(无)' : characters.map((c) => '${c.name}(${c.id})').join(', ')}。',
        isError: true,
      );
    }

    var updated = characters[index];
    final changes = <String>[];
    if (args.containsKey('name') && (args['name'] as String?) != null) {
      final name = (args['name'] as String).trim();
      if (name.isNotEmpty) {
        updated = updated.copyWith(name: name);
        changes.add('名称: $name');
      }
    }
    if (args.containsKey('prompt') && (args['prompt'] as String?) != null) {
      updated = updated.copyWith(prompt: args['prompt'] as String);
      changes.add('正向提示词: ${updated.prompt}');
    }
    if (args.containsKey('negative_prompt') &&
        (args['negative_prompt'] as String?) != null) {
      updated = updated.copyWith(
        negativePrompt: args['negative_prompt'] as String,
      );
      changes.add('负面提示词: ${updated.negativePrompt}');
    }
    if (args.containsKey('enabled') && args['enabled'] is bool) {
      updated = updated.copyWith(enabled: args['enabled'] as bool);
      changes.add('启用状态: ${updated.enabled ? '启用' : '停用'}');
    }
    if (args['use_auto_position'] == true) {
      updated = updated.copyWith(useCustomPosition: false);
      changes.add('定位: 恢复自动布局');
    }
    if (args.containsKey('position_x') && args['position_x'] is num) {
      updated = updated.copyWith(
        positionX: (args['position_x'] as num).toDouble().clamp(0.0, 1.0),
        useCustomPosition: true,
      );
      changes.add('坐标 X: ${updated.positionX}');
    }
    if (args.containsKey('position_y') && args['position_y'] is num) {
      updated = updated.copyWith(
        positionY: (args['position_y'] as num).toDouble().clamp(0.0, 1.0),
        useCustomPosition: true,
      );
      changes.add('坐标 Y: ${updated.positionY}');
    }

    if (changes.isEmpty) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '未修改任何字段 (没有传入有效的更新内容)。',
      );
    }

    final newList = [...characters];
    newList[index] = updated;
    updateCharacterPrompts(newList);

    return ToolResult(
      toolCallId: toolCallId,
      content:
          '已修改角色「${updated.name}」(${updated.id}) 并同步到工作台 UI：\n'
          '${changes.map((c) => '• $c').join('\n')}',
    );
  }
}

/// 角色提示词删除工具
class NovelAiRemoveCharacterPromptTool extends AgentTool {
  final CharacterPromptsGetter getCharacterPrompts;
  final CharacterPromptsUpdater updateCharacterPrompts;

  NovelAiRemoveCharacterPromptTool({
    required this.getCharacterPrompts,
    required this.updateCharacterPrompts,
  }) : super(
         name: 'remove_character_prompt',
         label: '删除角色',
         description: '按 ID 删除一个角色提示词并同步到工作台 UI。',
         parameters: const {
           'type': 'object',
           'properties': {
             'id': {'type': 'string', 'description': '要删除的角色 ID (8 位十六进制)'},
           },
           'required': ['id'],
         },
       );

  @override
  Future<ToolResult> execute(
    String toolCallId,
    Map<String, dynamic> args,
  ) async {
    final characters = getCharacterPrompts();
    final id = args['id'] as String?;
    if (id == null || id.trim().isEmpty) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '错误：必须传入要删除的角色 id。',
        isError: true,
      );
    }
    final target = characters.where((c) => c.id == id.trim()).toList();
    if (target.isEmpty) {
      return ToolResult(
        toolCallId: toolCallId,
        content:
            '错误：未找到 ID 为 ${id.trim()} 的角色。当前角色：'
            '${characters.isEmpty ? '(无)' : characters.map((c) => '${c.name}(${c.id})').join(', ')}。',
        isError: true,
      );
    }

    updateCharacterPrompts(characters.where((c) => c.id != id.trim()).toList());

    return ToolResult(
      toolCallId: toolCallId,
      content:
          '已删除角色「${target.first.name}」(${target.first.id}) 并同步到工作台 UI。当前剩余 ${characters.length - 1} 个角色。',
    );
  }
}
