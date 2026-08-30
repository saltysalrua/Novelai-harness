import '../../../data/models/prompt_library_models.dart';
import '../types.dart';
import 'agent_tool.dart';

/// 词库条目列表读取器
typedef PromptLibraryEntriesGetter = List<PromptComboEntry> Function();

/// 词库条目新增回调
typedef PromptLibraryAddEntry =
    Future<PromptComboEntry> Function(PromptComboEntry entry);

/// 词库条目更新回调
typedef PromptLibraryUpdateEntry =
    Future<void> Function(PromptComboEntry entry);

/// 词库条目删除回调
typedef PromptLibraryDeleteEntry = Future<void> Function(String id);

/// 格式化单条词库条目为可读文本
String formatPromptComboEntry(PromptComboEntry entry) {
  final lines = <String>[
    '• [${entry.id}] ${entry.title} (${entry.category})'
        '${entry.isFavorite ? ' [收藏]' : ''}${entry.isBuiltin ? ' [内置]' : ''}',
    '  提示词: ${entry.prompt}',
    if (entry.isCharacter && entry.negativePrompt.isNotEmpty)
      '  负面提示词: ${entry.negativePrompt}',
    if (entry.tags.isNotEmpty) '  标签: ${entry.tags.join(', ')}',
  ];
  return lines.join('\n');
}

/// 词库条目检索/阅读工具 (无参数时列出全部条目)
class SearchPromptLibraryTool extends AgentTool {
  final PromptLibraryEntriesGetter getEntries;

  SearchPromptLibraryTool({required this.getEntries})
    : super(
        name: 'search_prompt_library',
        label: '搜索词库',
        description:
            '检索本地词组合预设库 (词库)。传入 query 可按标题、提示词内容或标签模糊搜索；'
            '传入 category 可按分类过滤 (角色/风格/服装/构图/环境/特效/其他)；'
            '传入 id 可精确读取单条条目的完整内容。不传任何参数时返回全部条目列表。'
            '返回的条目 id 可用于 add/update/delete 工具的精确引用。',
        parameters: const {
          'type': 'object',
          'properties': {
            'query': {
              'type': 'string',
              'description': '搜索关键词 (匹配标题、提示词与标签，不区分大小写)',
            },
            'category': {
              'type': 'string',
              'enum': ['角色', '风格', '服装', '构图', '环境', '特效', '其他'],
              'description': '按分类过滤',
            },
            'id': {'type': 'string', 'description': '精确条目 ID，传入时直接返回该条目的完整内容'},
          },
        },
      );

  @override
  Future<ToolResult> execute(
    String toolCallId,
    Map<String, dynamic> args,
  ) async {
    final entries = getEntries();

    // 1. 按 ID 精确读取
    final id = args['id'] as String?;
    if (id != null && id.trim().isNotEmpty) {
      final match = entries.where((e) => e.id == id.trim()).toList();
      if (match.isEmpty) {
        return ToolResult(
          toolCallId: toolCallId,
          content: '未找到 ID 为 "$id" 的词库条目。可先不带参数搜索查看全部条目及其 ID。',
          isError: true,
        );
      }
      return ToolResult(
        toolCallId: toolCallId,
        content: '词库条目详情：\n${formatPromptComboEntry(match.first)}',
      );
    }

    // 2. 关键词 + 分类过滤
    final query = (args['query'] as String?)?.trim().toLowerCase() ?? '';
    final category = (args['category'] as String?)?.trim() ?? '';

    final filtered = entries.where((entry) {
      if (category.isNotEmpty && entry.category != category) return false;
      if (query.isEmpty) return true;
      return entry.title.toLowerCase().contains(query) ||
          entry.prompt.toLowerCase().contains(query) ||
          entry.negativePrompt.toLowerCase().contains(query) ||
          entry.tags.any((t) => t.toLowerCase().contains(query)) ||
          entry.category.toLowerCase().contains(query);
    }).toList();

    if (filtered.isEmpty) {
      return ToolResult(
        toolCallId: toolCallId,
        content: entries.isEmpty
            ? '词库当前为空。可调用 add_prompt_library_entry 新增条目。'
            : '没有匹配的词库条目 (关键词: "${args['query'] ?? ''}", 分类: "$category")。',
      );
    }

    final header = StringBuffer('词库条目 (共 ${filtered.length} 条');
    if (query.isNotEmpty) header.write(', 关键词 "$query"');
    if (category.isNotEmpty) header.write(', 分类 "$category"');
    header.writeln(')：');
    header.write(filtered.map(formatPromptComboEntry).join('\n'));
    return ToolResult(toolCallId: toolCallId, content: header.toString());
  }
}

/// 词库条目新增工具
class AddPromptLibraryEntryTool extends AgentTool {
  final PromptLibraryEntriesGetter getEntries;
  final PromptLibraryAddEntry addEntry;

  AddPromptLibraryEntryTool({required this.getEntries, required this.addEntry})
    : super(
        name: 'add_prompt_library_entry',
        label: '新增词库条目',
        description:
            '向本地词库新增一条词组合预设。title 与 prompt 必填；分类建议使用标准分类名 '
            '(角色/风格/服装/构图/环境/特效/其他)。注意：只有「角色」分类支持负面提示词，'
            '其他分类的负面提示词会被自动清空。新增成功后返回条目 ID。',
        parameters: const {
          'type': 'object',
          'required': ['title', 'prompt'],
          'properties': {
            'title': {'type': 'string', 'description': '条目标题 (如「初音未来」「赛博水彩风」)'},
            'prompt': {
              'type': 'string',
              'description': '正向提示词组合 (Danbooru 标签或自然语言)',
            },
            'category': {
              'type': 'string',
              'enum': ['角色', '风格', '服装', '构图', '环境', '特效', '其他'],
              'description': '分类 (默认 其他)',
            },
            'negative_prompt': {
              'type': 'string',
              'description': '负面提示词 (仅角色分类生效)',
            },
            'tags': {
              'type': 'array',
              'items': {'type': 'string'},
              'description': '检索用标签列表',
            },
            'favorite': {'type': 'boolean', 'description': '是否收藏'},
          },
        },
      );

  @override
  Future<ToolResult> execute(
    String toolCallId,
    Map<String, dynamic> args,
  ) async {
    final title = (args['title'] as String?)?.trim() ?? '';
    final prompt = (args['prompt'] as String?)?.trim() ?? '';
    if (title.isEmpty || prompt.isEmpty) {
      return ToolResult(
        toolCallId: toolCallId,
        content: 'title 与 prompt 为必填项，不能为空。',
        isError: true,
      );
    }

    final existing = getEntries();
    if (existing.any((e) => e.title == title)) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '已存在同名条目「$title」。如需覆盖请先用 search_prompt_library 查到 ID 后调用更新工具。',
        isError: true,
      );
    }

    final now = DateTime.now();
    final entry = PromptComboEntry(
      id: 'combo_${now.millisecondsSinceEpoch}',
      title: title,
      category: (args['category'] as String?)?.trim().isNotEmpty == true
          ? (args['category'] as String).trim()
          : PromptComboCategories.other,
      prompt: prompt,
      negativePrompt: (args['negative_prompt'] as String?)?.trim() ?? '',
      createdAt: now,
      updatedAt: now,
      isFavorite: args['favorite'] is bool ? args['favorite'] as bool : false,
      tags: _parseTags(args['tags']),
    );

    final created = await addEntry(entry);

    return ToolResult(
      toolCallId: toolCallId,
      content: '已新增词库条目：\n${formatPromptComboEntry(created)}',
    );
  }
}

/// 词库条目更新工具
class UpdatePromptLibraryEntryTool extends AgentTool {
  final PromptLibraryEntriesGetter getEntries;
  final PromptLibraryUpdateEntry updateEntry;

  UpdatePromptLibraryEntryTool({
    required this.getEntries,
    required this.updateEntry,
  }) : super(
         name: 'update_prompt_library_entry',
         label: '修改词库条目',
         description:
             '按 ID 修改本地词库中的词组合条目。只需传入要修改的字段，未传入的字段保持原值。'
             'ID 可先用 search_prompt_library 查询获取。',
         parameters: const {
           'type': 'object',
           'required': ['id'],
           'properties': {
             'id': {'type': 'string', 'description': '要修改的条目 ID'},
             'title': {'type': 'string', 'description': '新标题'},
             'prompt': {'type': 'string', 'description': '新正向提示词'},
             'category': {
               'type': 'string',
               'enum': ['角色', '风格', '服装', '构图', '环境', '特效', '其他'],
               'description': '新分类',
             },
             'negative_prompt': {
               'type': 'string',
               'description': '新负面提示词 (仅角色分类保留，传入空字符串可清除)',
             },
             'tags': {
               'type': 'array',
               'items': {'type': 'string'},
               'description': '新标签列表 (整体替换)',
             },
             'favorite': {'type': 'boolean', 'description': '是否收藏'},
           },
         },
       );

  @override
  Future<ToolResult> execute(
    String toolCallId,
    Map<String, dynamic> args,
  ) async {
    final id = (args['id'] as String?)?.trim() ?? '';
    if (id.isEmpty) {
      return ToolResult(
        toolCallId: toolCallId,
        content: 'id 为必填项。',
        isError: true,
      );
    }

    final entries = getEntries();
    final idx = entries.indexWhere((e) => e.id == id);
    if (idx == -1) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '未找到 ID 为 "$id" 的词库条目。可先调用 search_prompt_library 查询。',
        isError: true,
      );
    }

    final current = entries[idx];
    final updated = current.copyWith(
      title: (args['title'] as String?)?.trim().isNotEmpty == true
          ? (args['title'] as String).trim()
          : null,
      prompt: args.containsKey('prompt')
          ? ((args['prompt'] as String?)?.trim() ?? '')
          : null,
      category: (args['category'] as String?)?.trim().isNotEmpty == true
          ? (args['category'] as String).trim()
          : null,
      negativePrompt: args.containsKey('negative_prompt')
          ? ((args['negative_prompt'] as String?)?.trim() ?? '')
          : null,
      isFavorite: args['favorite'] is bool ? args['favorite'] as bool : null,
      tags: args.containsKey('tags') ? _parseTags(args['tags']) : null,
      updatedAt: DateTime.now(),
    );

    await updateEntry(updated);

    return ToolResult(
      toolCallId: toolCallId,
      content: '已修改词库条目：\n${formatPromptComboEntry(updated)}',
    );
  }
}

/// 词库条目删除工具
class DeletePromptLibraryEntryTool extends AgentTool {
  final PromptLibraryEntriesGetter getEntries;
  final PromptLibraryDeleteEntry deleteEntry;

  DeletePromptLibraryEntryTool({
    required this.getEntries,
    required this.deleteEntry,
  }) : super(
         name: 'delete_prompt_library_entry',
         label: '删除词库条目',
         description:
             '按 ID 删除本地词库中的词组合条目 (不可恢复)。ID 可先用 search_prompt_library 查询获取。',
         parameters: const {
           'type': 'object',
           'required': ['id'],
           'properties': {
             'id': {'type': 'string', 'description': '要删除的条目 ID'},
           },
         },
       );

  @override
  Future<ToolResult> execute(
    String toolCallId,
    Map<String, dynamic> args,
  ) async {
    final id = (args['id'] as String?)?.trim() ?? '';
    if (id.isEmpty) {
      return ToolResult(
        toolCallId: toolCallId,
        content: 'id 为必填项。',
        isError: true,
      );
    }

    final entries = getEntries();
    final idx = entries.indexWhere((e) => e.id == id);
    if (idx == -1) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '未找到 ID 为 "$id" 的词库条目。',
        isError: true,
      );
    }

    final target = entries[idx];
    await deleteEntry(id);

    return ToolResult(
      toolCallId: toolCallId,
      content: '已删除词库条目「${target.title}」($id)。',
    );
  }
}

/// 解析 tags 参数 (字符串数组或逗号分隔字符串)
List<String> _parseTags(dynamic raw) {
  if (raw is List) {
    return raw
        .map((e) => e.toString().trim())
        .where((t) => t.isNotEmpty)
        .toList();
  }
  if (raw is String && raw.trim().isNotEmpty) {
    return raw
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
  }
  return const [];
}
