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
  final positionMode = aiPosition
      ? 'AI 自动布局 (官方 AI\'s Choice，不发送位置参数)'
      : '自定义定位 (发送 use_coords 与各角色 center)';
  if (characters.isEmpty) {
    return '当前没有角色提示词 (单角色场景无需配置，主提示词即可)。'
        '位置模式: $positionMode。';
  }
  final lines = characters.asMap().entries.map((entry) {
    final index = entry.key;
    final c = entry.value;
    final position = c.useCustomPosition
        ? '手动 (${(c.positionX * 100).toStringAsFixed(0)}%, ${(c.positionY * 100).toStringAsFixed(0)}%)'
        : '自动布局';
    return [
      '[$index] ${c.name} (id: ${c.id})',
      '    状态: ${c.enabled ? '启用' : '停用'} | 定位: $position',
      '    坐标原值: position_x: ${c.positionX} | position_y: ${c.positionY}',
      '    正向: ${c.prompt.isEmpty ? '(空)' : c.prompt}',
      '    负面: ${c.negativePrompt.isEmpty ? '(空)' : c.negativePrompt}',
    ].join('\n');
  });
  return '共 ${characters.length} 个角色提示词，位置模式: $positionMode。\n${lines.join('\n')}';
}

/// 工具参数错误结果
ToolResult _toolError(String toolCallId, String message) =>
    ToolResult(toolCallId: toolCallId, content: message, isError: true);

/// 解析批量参数：未传数组时退化为「当前顶层参数即单条规格」
({List<Map<String, dynamic>> specs, String? error}) _resolveSpecs(
  Map<String, dynamic> args,
  String key,
) {
  final raw = args[key];
  if (raw == null) return (specs: [args], error: null);
  if (raw is! List || raw.isEmpty) {
    return (specs: const [], error: '$key 必须是非空对象数组。');
  }
  final specs = <Map<String, dynamic>>[];
  for (final item in raw) {
    if (item is! Map) {
      return (specs: const [], error: '$key 必须是非空对象数组。');
    }
    specs.add(item.cast<String, dynamic>());
  }
  return (specs: specs, error: null);
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

/// 角色提示词添加工具 (支持 characters 数组一次添加复数角色)
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
             '为工作台添加一个多角色提示词 (V5 最多 22 个，V4/V4.5 最多 6 个)；'
             '需要一次添加复数角色时改用 characters 数组，一次调用即可，不要逐条多次调用。'
             '添加后可配合 novelai_generate 进行多角色隔离生图；修改已有角色请用 update_character_prompt。',
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
             'characters': {
               'type': 'array',
               'description': '批量添加多个角色：每项字段与顶层同名参数一致 (prompt 必填)，本次调用内一次全部添加',
               'items': {
                 'type': 'object',
                 'properties': {
                   'name': {'type': 'string', 'description': '角色名称 (留空自动命名)'},
                   'prompt': {'type': 'string', 'description': '该角色正向提示词'},
                   'negative_prompt': {
                     'type': 'string',
                     'description': '该角色负面提示词',
                   },
                   'position_x': {
                     'type': 'number',
                     'description': '定位坐标 X (0.0~1.0)',
                   },
                   'position_y': {
                     'type': 'number',
                     'description': '定位坐标 Y (0.0~1.0)',
                   },
                 },
                 'required': ['prompt'],
               },
             },
           },
         },
       );

  @override
  Future<ToolResult> execute(
    String toolCallId,
    Map<String, dynamic> args,
  ) async {
    final characters = getCharacterPrompts();
    final limit = getCharacterLimit?.call() ?? 6;
    final batch = args['characters'] != null;
    final resolved = _resolveSpecs(args, 'characters');
    if (resolved.error case final String error) {
      return _toolError(toolCallId, '错误：$error');
    }
    final specs = resolved.specs;

    final prompts = <String>[];
    for (final spec in specs) {
      final prompt = (spec['prompt'] as String?)?.trim() ?? '';
      if (prompt.isEmpty) {
        return _toolError(toolCallId, '错误：prompt (角色正向提示词) 不能为空。');
      }
      prompts.add(prompt);
    }

    final available = limit - characters.length;
    if (specs.length > available) {
      final detail = available <= 0
          ? '当前模型角色提示词已达上限 $limit 个'
          : '当前 $limit 个上限下仅剩 $available 个名额，本次要添加 ${specs.length} 个';
      return _toolError(
        toolCallId,
        '错误：$detail，请先用 remove_character_prompt 删除后再添加。',
      );
    }

    // 传入了任一坐标即视为手动定位；未传则按启用顺序自动布局
    final created = <NaiCharacterPrompt>[];
    for (var i = 0; i < specs.length; i++) {
      final spec = specs[i];
      final positionX = ((spec['position_x'] as num?)?.toDouble() ?? 0.5).clamp(
        0.0,
        1.0,
      );
      final positionY = ((spec['position_y'] as num?)?.toDouble() ?? 0.5).clamp(
        0.0,
        1.0,
      );
      final rawName = (spec['name'] as String?)?.trim();
      created.add(
        NaiCharacterPrompt.create(
          name: (rawName == null || rawName.isEmpty)
              ? '角色 ${characters.length + i + 1}'
              : rawName,
          prompt: prompts[i],
          negativePrompt: (spec['negative_prompt'] as String?) ?? '',
        ).copyWith(
          useCustomPosition:
              spec['position_x'] != null || spec['position_y'] != null,
          positionX: positionX,
          positionY: positionY,
        ),
      );
    }

    updateCharacterPrompts([...characters, ...created]);

    final total = characters.length + created.length;
    final details = created
        .map(
          (c) =>
              '• 名称: ${c.name}\n'
              '• ID: ${c.id}\n'
              '• 正向提示词: 已设置\n'
              '• 负面提示词: ${c.negativePrompt.isEmpty ? '(空)' : '已设置'}\n'
              '• 定位: ${c.useCustomPosition ? '手动 (${c.positionX}, ${c.positionY})' : '自动布局 (跟随全局 AI 自动 / 自定义模式)'}',
        )
        .join('\n');
    final tail = batch
        ? '当前共 $total 个角色。后续修改或删除角色请引用上述 ID。'
        : '当前共 $total 个角色。后续修改或删除该角色请引用 ID: ${created.first.id}。';
    return ToolResult(
      toolCallId: toolCallId,
      content:
          '${batch ? '已添加 ${created.length} 个角色提示词' : '已添加角色提示词'}并同步到工作台 UI：\n'
          '$details\n$tail',
    );
  }
}

/// 角色提示词修改工具 (支持 updates 数组一次修改复数角色)
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
             '按 ID 修改已有的角色提示词，只需传入要修改的字段 (名称/正负提示词/启停/定位坐标)，未传入的字段保持不变。'
             '一次修改复数角色时用 updates 数组 (每项含 id 与要改的字段)，避免逐条多次调用。'
             '全局位置模式 (AI 自动 / 自定义) 请用 update_studio_parameters 的 character_ai_position 参数切换。',
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
             'updates': {
               'type': 'array',
               'description':
                   '批量修改多个角色：每项含 id 与要修改的字段 (字段名与顶层同名参数一致)，本次调用内一次全部应用',
               'items': {
                 'type': 'object',
                 'properties': {
                   'id': {'type': 'string', 'description': '目标角色的 8 位十六进制 ID'},
                   'name': {'type': 'string'},
                   'prompt': {'type': 'string'},
                   'negative_prompt': {'type': 'string'},
                   'enabled': {'type': 'boolean'},
                   'position_x': {'type': 'number'},
                   'position_y': {'type': 'number'},
                   'use_auto_position': {'type': 'boolean'},
                 },
                 'required': ['id'],
               },
             },
           },
         },
       );

  @override
  Future<ToolResult> execute(
    String toolCallId,
    Map<String, dynamic> args,
  ) async {
    final characters = getCharacterPrompts();
    final batch = args['updates'] != null;
    final resolved = _resolveSpecs(args, 'updates');
    if (resolved.error case final String error) {
      return _toolError(toolCallId, '错误：$error');
    }
    final specs = resolved.specs;

    if (!batch) {
      final id = (args['id'] as String?)?.trim() ?? '';
      if (id.isEmpty) {
        return _toolError(toolCallId, '错误：必须传入目标角色的 id (8 位十六进制)。');
      }
      if (!characters.any((c) => c.id == id)) {
        return _toolError(
          toolCallId,
          '错误：未找到 ID 为 $id 的角色。当前角色：'
          '${characters.isEmpty ? '(无)' : characters.map((c) => '${c.name}(${c.id})').join(', ')}。',
        );
      }
    }

    final newList = [...characters];
    final applied = <String>[];
    final failed = <String>[];
    for (final spec in specs) {
      final id = (spec['id'] as String?)?.trim() ?? '';
      if (id.isEmpty) {
        failed.add('缺少角色 id');
        continue;
      }
      final index = newList.indexWhere((c) => c.id == id);
      if (index < 0) {
        failed.add('未找到 ID 为 $id 的角色');
        continue;
      }
      final result = _applyCharacterUpdate(newList[index], spec);
      if (result.changes.isEmpty) {
        failed.add('ID $id 未传入有效修改字段');
        continue;
      }
      newList[index] = result.character;
      applied.add(
        '已修改角色「${result.character.name}」(${result.character.id}) 并同步到工作台 UI：\n'
        '${result.changes.map((c) => '• $c').join('\n')}',
      );
    }

    if (applied.isEmpty) {
      if (batch) {
        return _toolError(toolCallId, '未修改任何角色：${failed.join('；')}。');
      }
      return ToolResult(
        toolCallId: toolCallId,
        content: '未修改任何字段 (没有传入有效的更新内容)。',
      );
    }

    updateCharacterPrompts(newList);
    final buffer = StringBuffer(applied.join('\n'));
    if (failed.isNotEmpty) {
      buffer.write('\n未修改：${failed.join('；')}。');
    }
    return ToolResult(toolCallId: toolCallId, content: buffer.toString());
  }
}

/// 对单个角色应用规格中的字段修改，返回新角色与人类可读的改动清单
({NaiCharacterPrompt character, List<String> changes}) _applyCharacterUpdate(
  NaiCharacterPrompt original,
  Map<String, dynamic> spec,
) {
  var updated = original;
  final changes = <String>[];
  if (spec.containsKey('name') && (spec['name'] as String?) != null) {
    final name = (spec['name'] as String).trim();
    if (name.isNotEmpty) {
      updated = updated.copyWith(name: name);
      changes.add('名称: $name');
    }
  }
  if (spec.containsKey('prompt') && (spec['prompt'] as String?) != null) {
    updated = updated.copyWith(prompt: spec['prompt'] as String);
    changes.add('正向提示词: 已更新');
  }
  if (spec.containsKey('negative_prompt') &&
      (spec['negative_prompt'] as String?) != null) {
    updated = updated.copyWith(
      negativePrompt: spec['negative_prompt'] as String,
    );
    changes.add('负面提示词: 已更新');
  }
  if (spec.containsKey('enabled') && spec['enabled'] is bool) {
    updated = updated.copyWith(enabled: spec['enabled'] as bool);
    changes.add('启用状态: ${updated.enabled ? '启用' : '停用'}');
  }
  if (spec['use_auto_position'] == true) {
    updated = updated.copyWith(useCustomPosition: false);
    changes.add('定位: 恢复自动布局');
  }
  if (spec.containsKey('position_x') && spec['position_x'] is num) {
    updated = updated.copyWith(
      positionX: (spec['position_x'] as num).toDouble().clamp(0.0, 1.0),
      useCustomPosition: true,
    );
    changes.add('坐标 X: ${updated.positionX}');
  }
  if (spec.containsKey('position_y') && spec['position_y'] is num) {
    updated = updated.copyWith(
      positionY: (spec['position_y'] as num).toDouble().clamp(0.0, 1.0),
      useCustomPosition: true,
    );
    changes.add('坐标 Y: ${updated.positionY}');
  }
  return (character: updated, changes: changes);
}

/// 角色提示词删除工具 (支持 ids 数组一次删除复数角色)
class NovelAiRemoveCharacterPromptTool extends AgentTool {
  final CharacterPromptsGetter getCharacterPrompts;
  final CharacterPromptsUpdater updateCharacterPrompts;

  NovelAiRemoveCharacterPromptTool({
    required this.getCharacterPrompts,
    required this.updateCharacterPrompts,
  }) : super(
         name: 'remove_character_prompt',
         label: '删除角色',
         description:
             '按 ID 删除角色提示词并同步到工作台 UI；'
             '删除复数角色时用 ids 数组一次完成，不要逐条多次调用。',
         parameters: const {
           'type': 'object',
           'properties': {
             'id': {'type': 'string', 'description': '要删除的角色 ID (8 位十六进制)'},
             'ids': {
               'type': 'array',
               'items': {'type': 'string'},
               'description': '批量删除的角色 ID 列表 (与 id 可并用)',
             },
           },
         },
       );

  @override
  Future<ToolResult> execute(
    String toolCallId,
    Map<String, dynamic> args,
  ) async {
    final characters = getCharacterPrompts();
    final ids = <String>{};
    final single = (args['id'] as String?)?.trim() ?? '';
    if (single.isNotEmpty) ids.add(single);
    final many = args['ids'];
    if (many != null) {
      if (many is! List || many.isEmpty) {
        return _toolError(toolCallId, '错误：ids 必须是非空字符串数组。');
      }
      for (final item in many) {
        final id = '$item'.trim();
        if (id.isNotEmpty) ids.add(id);
      }
    }
    if (ids.isEmpty) {
      return _toolError(toolCallId, '错误：必须传入要删除的角色 id (或 ids 数组)。');
    }

    final matched = characters.where((c) => ids.contains(c.id)).toList();
    if (matched.isEmpty) {
      return _toolError(
        toolCallId,
        '错误：未找到 ID 为 ${ids.join('、')} 的角色。当前角色：'
        '${characters.isEmpty ? '(无)' : characters.map((c) => '${c.name}(${c.id})').join(', ')}。',
      );
    }

    updateCharacterPrompts(
      characters.where((c) => !ids.contains(c.id)).toList(),
    );

    final removed = matched.map((c) => '「${c.name}」(${c.id})').join('、');
    final missing = ids.where((id) => !matched.any((c) => c.id == id)).toList();
    final buffer = StringBuffer(
      '已删除角色$removed并同步到工作台 UI。当前剩余 ${characters.length - matched.length} 个角色。',
    );
    if (missing.isNotEmpty) buffer.write('未找到 ${missing.join('、')}。');
    return ToolResult(toolCallId: toolCallId, content: buffer.toString());
  }
}
