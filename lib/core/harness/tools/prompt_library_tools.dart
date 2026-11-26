import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../../data/models/novelai_models.dart';
import '../../../data/models/prompt_library_models.dart';
import '../types.dart';
import 'agent_tool.dart';
import 'vision_image_codec.dart';

/// 词库条目列表读取器
typedef PromptLibraryEntriesGetter = List<PromptComboEntry> Function();

/// 待整理区条目列表读取器
typedef PromptLibraryInboxGetter = List<PromptInboxItem> Function();

/// 待整理区批量删除回调 (返回实际删除条数)
typedef PromptLibraryInboxDelete = Future<int> Function(Iterable<String> ids);

/// 当前模型视觉能力检查器
typedef PromptLibraryVisionChecker = bool Function();

/// 词库条目新增回调
typedef PromptLibraryAddEntry =
    Future<PromptComboEntry> Function(PromptComboEntry entry);

/// 词库条目更新回调
typedef PromptLibraryUpdateEntry =
    Future<void> Function(PromptComboEntry entry);

/// 词库条目删除回调
typedef PromptLibraryDeleteEntry = Future<void> Function(String id);

/// 画板历史图片列表获取器 (从新到旧，索引 0 为最新)
typedef PromptLibraryHistoryGetter = List<NaiGeneratedImage> Function();

/// 历史大图字节加载器 (内存缺失时按需从磁盘缓存回载)
typedef PromptLibraryImageBytesLoader =
    Future<Uint8List?> Function(NaiGeneratedImage image);

/// 预览图字节落盘器 (写入托管预览目录并返回持久化路径)
typedef PromptLibraryPreviewBytesSaver =
    Future<String?> Function(Uint8List bytes);

/// 外部图片路径复制器 (拷入托管预览目录并返回新路径)
typedef PromptLibraryPreviewPathCopier =
    Future<String?> Function(String sourcePath);

/// 将当前工作台精准参考落盘为词库托管条目
typedef PromptLibraryWorkspacePreciseSnapshot =
    Future<List<PromptLibraryPreciseRef>> Function();

/// 将当前工作台 Vibe Transfer 落盘为词库托管条目
typedef PromptLibraryWorkspaceVibeSnapshot =
    Future<List<PromptLibraryVibeRef>> Function();

/// 选择性应用词库条目回调（提示词 + 精准参考 + Vibe）
typedef PromptLibraryApplyEntryCallback =
    Future<({bool appliedPrompt, int appliedPreciseCount, int appliedVibeCount})>
    Function(
      PromptComboEntry entry, {
      bool applyPrompt,
      bool replacePrompt,
      bool asCharacter,
      bool asStyle,
      bool applyPreciseReferences,
      bool applyVibeReferences,
      bool replaceReferences,
      Set<String>? selectedPreciseRefIds,
      Set<String>? selectedVibeRefIds,
    });

/// 格式化单条词库条目为可读文本
String formatPromptComboEntry(
  PromptComboEntry entry, {
  List<PromptComboEntry>? allEntries,
}) {
  final linkedSummary = <String>[];
  if (allEntries != null && allEntries.isNotEmpty) {
    final byId = <String, PromptComboEntry>{
      for (final e in allEntries)
        if (e.id.isNotEmpty) e.id: e,
    };
    final seen = <String>{entry.id};
    for (final id in entry.linkedEntryIds) {
      final found = byId[id];
      if (found != null && seen.add(found.id)) {
        linkedSummary.add('[${found.id}] ${found.title} (${found.category})');
      }
    }
  } else if (entry.linkedEntryIds.isNotEmpty) {
    linkedSummary.addAll(entry.linkedEntryIds);
  }

  final lines = <String>[
    '• [${entry.id}] ${entry.title} (${entry.category})'
        '${entry.isFavorite ? ' [收藏]' : ''}${entry.isBuiltin ? ' [内置]' : ''}',
    if (entry.isStyle && entry.prefixPrompt.trim().isNotEmpty)
      '  前置词: ${entry.prefixPrompt}',
    if (entry.isStyle && entry.suffixPrompt.trim().isNotEmpty)
      '  后置词: ${entry.suffixPrompt}',
    if (!entry.isStyle && entry.prompt.trim().isNotEmpty)
      '  提示词: ${entry.prompt}',
    if (entry.isStyle && entry.prompt.trim().isNotEmpty)
      '  提示词: ${entry.prompt}',
    if (entry.supportsNegative && entry.negativePrompt.isNotEmpty)
      '  负面提示词: ${entry.negativePrompt}',
    if (entry.characterPrompts.isNotEmpty) ...[
      '  多角色提示词 (${entry.characterPrompts.length} 个):',
      for (var i = 0; i < entry.characterPrompts.length; i++) ...[
        '    - 角色 ${i + 1}'
            '${entry.characterPrompts[i].name.trim().isNotEmpty ? ' (${entry.characterPrompts[i].name.trim()})' : ''}: '
            '${entry.characterPrompts[i].prompt.trim()}',
        if (entry.characterPrompts[i].negativePrompt.trim().isNotEmpty)
          '      负面词: ${entry.characterPrompts[i].negativePrompt.trim()}',
      ],
    ],
    if (linkedSummary.isNotEmpty) '  关联条目: ${linkedSummary.join('、')}',
    if (entry.previewImagePath != null) '  预览图: 已设置',
    if (entry.preciseReferences.isNotEmpty)
      '  精准参考 (${entry.preciseReferences.length} 张): '
          '${entry.preciseReferences.map((r) => '[${r.id}] ${r.type.id}(strength:${r.strength.toStringAsFixed(2)})').join(', ')}',
    if (entry.vibeReferences.isNotEmpty)
      '  Vibe Transfer (${entry.vibeReferences.length} 条): '
          '${entry.vibeReferences.map((v) => '[${v.id}] ${v.displayName}(strength:${v.strength.toStringAsFixed(2)}${v.encodingsByModel.isNotEmpty ? ', 已编码' : ''})').join(', ')}',
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
            '传入 id 可精确读取单条条目的完整内容。默认分页返回 ID、标题与分类；用 id 读取完整提示词。'
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
            'offset': {
              'type': 'integer',
              'minimum': 0,
              'description': '分页偏移，默认 0',
            },
            'limit': {
              'type': 'integer',
              'minimum': 1,
              'maximum': 50,
              'description': '每页条数，默认 10',
            },
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
        content: '词库条目详情：\n${formatPromptComboEntry(match.first, allEntries: entries)}',
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
          entry.prefixPrompt.toLowerCase().contains(query) ||
          entry.suffixPrompt.toLowerCase().contains(query) ||
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
    final offset = ((args['offset'] as num?)?.toInt() ?? 0).clamp(
      0,
      filtered.length,
    );
    final limit = ((args['limit'] as num?)?.toInt() ?? 10).clamp(1, 50);
    final page = filtered.skip(offset).take(limit).toList();
    header.write(
      page
          .map((entry) {
            final title = entry.title.length > 120
                ? '${entry.title.substring(0, 120)}…'
                : entry.title;
            final refTags = <String>[
              if (entry.preciseReferences.isNotEmpty)
                '精准参考×${entry.preciseReferences.length}',
              if (entry.vibeReferences.isNotEmpty)
                'Vibe×${entry.vibeReferences.length}',
            ];
            final refSuffix = refTags.isNotEmpty ? ' [${refTags.join(', ')}]' : '';
            return '• [${entry.id}] $title (${entry.category})$refSuffix';
          })
          .join('\n'),
    );
    final next = offset + page.length;
    header.writeln('\n本页 ${page.length} 条；用 id 读取全文。');
    if (next < filtered.length) header.writeln('下一页 offset: $next');
    return ToolResult(toolCallId: toolCallId, content: header.toString());
  }
}

/// 格式化单条待整理区条目为可读文本
String formatPromptInboxItem(PromptInboxItem item) {
  final ts = item.createdAt
      .toLocal()
      .toIso8601String()
      .replaceAll('T', ' ')
      .split('.')
      .first;
  final lines = <String>[
    '• [${item.id}] 保存时间: $ts${item.hasImage ? ' [有图片]' : ' [无图片]'}',
    if (item.prompt.trim().isNotEmpty) '  主提示词: ${item.prompt.trim()}',
    if (item.negativePrompt.trim().isNotEmpty)
      '  主负面提示词: ${item.negativePrompt.trim()}',
    if (item.characterPrompts.isNotEmpty) ...[
      '  角色提示词 (${item.characterPrompts.length} 个):',
      for (var i = 0; i < item.characterPrompts.length; i++) ...[
        '    - 角色 ${i + 1}'
            '${item.characterPrompts[i].name.trim().isNotEmpty ? ' (${item.characterPrompts[i].name.trim()})' : ''}: '
            '${item.characterPrompts[i].prompt.trim()}',
        if (item.characterPrompts[i].negativePrompt.trim().isNotEmpty)
          '      负面词: ${item.characterPrompts[i].negativePrompt.trim()}',
      ],
    ],
    if (item.note != null && item.note!.trim().isNotEmpty)
      '  备注: ${item.note!.trim()}',
  ];
  return lines.join('\n');
}

/// 词库条目新增工具
class AddPromptLibraryEntryTool extends AgentTool {
  final PromptLibraryEntriesGetter getEntries;
  final PromptLibraryAddEntry addEntry;
  final PromptLibraryInboxGetter? getInboxItems;
  final Set<String>? excludedCategories;
  final PromptLibraryWorkspacePreciseSnapshot? snapshotWorkspacePrecise;
  final PromptLibraryWorkspaceVibeSnapshot? snapshotWorkspaceVibe;

  AddPromptLibraryEntryTool({
    required this.getEntries,
    required this.addEntry,
    this.getInboxItems,
    this.excludedCategories,
    this.snapshotWorkspacePrecise,
    this.snapshotWorkspaceVibe,
  }) : super(
        name: 'add_prompt_library_entry',
        label: '新增词库条目',
        description:
            '向本地词库新增词组合预设。title 必填；分类建议使用标准分类名 '
            '(角色/风格/服装/构图/环境/特效/其他)。「风格」分类支持 prefix_prompt、suffix_prompt 与 negative_prompt '
            '(四项提示词字段至少填一项)；「角色」与「风格」分类支持 negative_prompt，其他分类的负面与前后缀会被自动清空。'
            '新增成功后返回条目 ID。需要一次新增多条时用 entries 数组，不要逐条多次调用。',
        parameters: const {
          'type': 'object',
          'properties': {
            'title': {'type': 'string', 'description': '条目标题 (如「初音未来」「赛博水彩风」)'},
            'prompt': {
              'type': 'string',
              'description': '正向提示词组合 (非风格分类必填；风格分类可留空改用前后缀)',
            },
            'category': {
              'type': 'string',
              'enum': ['角色', '风格', '服装', '构图', '环境', '特效', '其他'],
              'description': '分类 (默认 其他)',
            },
            'prefix_prompt': {
              'type': 'string',
              'description': '前置词 (仅风格分类生效，对应工作台固定前置词缀)',
            },
            'suffix_prompt': {
              'type': 'string',
              'description': '后置词 (仅风格分类生效，对应工作台固定后置词缀)',
            },
            'negative_prompt': {
              'type': 'string',
              'description': '负面提示词 (角色与风格分类生效)',
            },
            'tags': {
              'type': 'array',
              'items': {'type': 'string'},
              'description': '检索用标签列表',
            },
            'favorite': {'type': 'boolean', 'description': '是否收藏'},
            'preview_inbox_id': {
              'type': 'string',
              'description': '可选：复用指定待整理区条目 (inbox_id) 的图片作为本条目的预览图',
            },
            'entries': {
              'type': 'array',
              'description':
                  '批量新增多个条目：每项字段与顶层同名参数一致 (title 必填)，本次调用内一次全部新增',
              'items': {
                'type': 'object',
                'properties': {
                  'title': {'type': 'string'},
                  'prompt': {'type': 'string'},
                  'category': {'type': 'string'},
                  'prefix_prompt': {'type': 'string'},
                  'suffix_prompt': {'type': 'string'},
                  'negative_prompt': {'type': 'string'},
                  'tags': {
                    'type': 'array',
                    'items': {'type': 'string'},
                  },
                  'favorite': {'type': 'boolean'},
                  'preview_inbox_id': {'type': 'string'},
                },
                'required': ['title'],
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
    final rawSpecs = args['entries'];
    final specs = <Map<String, dynamic>>[];
    if (rawSpecs != null) {
      if (rawSpecs is! List || rawSpecs.isEmpty) {
        return ToolResult(
          toolCallId: toolCallId,
          content: 'entries 必须是非空对象数组。',
          isError: true,
        );
      }
      for (final item in rawSpecs) {
        if (item is! Map) {
          return ToolResult(
            toolCallId: toolCallId,
            content: 'entries 必须是非空对象数组。',
            isError: true,
          );
        }
        specs.add(item.cast<String, dynamic>());
      }
    } else {
      specs.add(args);
    }

    // 先整体校验，避免批量新增到一半才发现重名或字段缺失
    final seen = <String>{};
    for (final spec in specs) {
      final title = (spec['title'] as String?)?.trim() ?? '';
      final category = (spec['category'] as String?)?.trim().isNotEmpty == true
          ? (spec['category'] as String).trim()
          : PromptComboCategories.other;
      final excluded = excludedCategories;
      if (excluded != null &&
          excluded.isNotEmpty &&
          excluded.any(
            (ex) => ex.trim().toLowerCase() == category.toLowerCase(),
          )) {
        final allowed = PromptComboCategories.defaults
            .where(
              (c) => !excluded.any(
                (ex) => ex.trim().toLowerCase() == c.toLowerCase(),
              ),
            )
            .toList(growable: false);
        return ToolResult(
          toolCallId: toolCallId,
          content:
              '用户已禁用后台整理拆分「$category」分类，请不要创建该分类条目'
              '${allowed.isNotEmpty ? '（当前允许的分类：${allowed.join(' / ')}）' : ''}。',
          isError: true,
        );
      }
      final isStyle = PromptComboEntry.isStyleCategory(category);
      final prompt = (spec['prompt'] as String?)?.trim() ?? '';
      final prefix = (spec['prefix_prompt'] as String?)?.trim() ?? '';
      final suffix = (spec['suffix_prompt'] as String?)?.trim() ?? '';
      final negative = (spec['negative_prompt'] as String?)?.trim() ?? '';
      final chars = _parseCharacterPrompts(spec['character_prompts']);
      final hasStyleContent =
          prompt.isNotEmpty ||
          prefix.isNotEmpty ||
          suffix.isNotEmpty ||
          negative.isNotEmpty ||
          chars.isNotEmpty;
      final willAttachRefs =
          spec['attach_workspace_references'] == true ||
          spec['attach_workspace_vibes'] == true;
      if (title.isEmpty ||
          (!willAttachRefs &&
              (isStyle ? !hasStyleContent : (prompt.isEmpty && chars.isEmpty)))) {
        return ToolResult(
          toolCallId: toolCallId,
          content: isStyle
              ? '风格分类下 title 为必填项，且 prompt / prefix_prompt / suffix_prompt / negative_prompt 至少需填一项（或附带工作台参考图）。'
              : 'title 与 prompt (或 character_prompts) 为必填项，不能为空（若仅保存参考图可传 attach_workspace_references / attach_workspace_vibes）。',
          isError: true,
        );
      }
      if (getEntries().any((e) => e.title == title) || !seen.add(title)) {
        return ToolResult(
          toolCallId: toolCallId,
          content:
              '已存在同名条目「$title」。如需覆盖请先用 prompt_library(action: "search") 查到 ID 后调用更新。',
          isError: true,
        );
      }
      final previewInboxId =
          (spec['preview_inbox_id'] as String?)?.trim() ?? '';
      if (previewInboxId.isNotEmpty) {
        final inboxItems = getInboxItems?.call() ?? const <PromptInboxItem>[];
        if (!inboxItems.any((e) => e.id == previewInboxId)) {
          return ToolResult(
            toolCallId: toolCallId,
            content: '未找到 ID 为 "$previewInboxId" 的待整理区条目，无法复用其图片作为预览图。',
            isError: true,
          );
        }
      }
    }

    final inboxById = <String, PromptInboxItem>{
      for (final item in getInboxItems?.call() ?? const <PromptInboxItem>[])
        item.id: item,
    };

    final created = <PromptComboEntry>[];
    final createdIdByTitle = <String, String>{};
    for (var i = 0; i < specs.length; i++) {
      final spec = specs[i];
      final now = DateTime.now();
      final category = (spec['category'] as String?)?.trim().isNotEmpty == true
          ? (spec['category'] as String).trim()
          : PromptComboCategories.other;
      final allowNeg = PromptComboEntry.supportsNegativePrompt(category);
      final allowStyle = PromptComboEntry.isStyleCategory(category);
      final attachedPrecise =
          spec['attach_workspace_references'] == true &&
              snapshotWorkspacePrecise != null
          ? await snapshotWorkspacePrecise!()
          : const <PromptLibraryPreciseRef>[];
      final attachedVibes =
          spec['attach_workspace_vibes'] == true &&
              snapshotWorkspaceVibe != null
          ? await snapshotWorkspaceVibe!()
          : const <PromptLibraryVibeRef>[];
      final promptText = (spec['prompt'] as String?)?.trim() ?? '';
      final prefixText = allowStyle
          ? ((spec['prefix_prompt'] as String?)?.trim() ?? '')
          : '';
      final suffixText = allowStyle
          ? ((spec['suffix_prompt'] as String?)?.trim() ?? '')
          : '';
      final negativeText = allowNeg
          ? ((spec['negative_prompt'] as String?)?.trim() ?? '')
          : '';
      final charPrompts = _parseCharacterPrompts(spec['character_prompts']);
      final linkedIds = _resolveLinkedIds(
        rawIds: spec['linked_entry_ids'],
        rawTitles: spec['linked_entry_titles'],
        existingEntries: getEntries(),
        batchIdByTitle: createdIdByTitle,
      );
      final previewInboxId =
          (spec['preview_inbox_id'] as String?)?.trim() ?? '';
      String? resolvedPreviewPath;
      if (previewInboxId.isNotEmpty) {
        final candidatePath = inboxById[previewInboxId]?.imagePath?.trim();
        if (candidatePath != null &&
            candidatePath.isNotEmpty &&
            File(candidatePath).existsSync()) {
          resolvedPreviewPath = candidatePath;
        }
      }
      final hasAnyContent =
          promptText.isNotEmpty ||
          prefixText.isNotEmpty ||
          suffixText.isNotEmpty ||
          negativeText.isNotEmpty ||
          charPrompts.isNotEmpty ||
          attachedPrecise.isNotEmpty ||
          attachedVibes.isNotEmpty;
      if (!hasAnyContent) {
        return ToolResult(
          toolCallId: toolCallId,
          content: '工作台当前没有可附带的参考图/Vibe，且条目提示词为空，未创建条目。',
          isError: true,
        );
      }
      final entryTitle = (spec['title'] as String).trim();
      final newId =
          'combo_${now.millisecondsSinceEpoch}'
          '${specs.length > 1 ? '_$i' : ''}';
      final saved = await addEntry(
        PromptComboEntry(
          id: newId,
          title: entryTitle,
          category: category,
          prompt: promptText,
          negativePrompt: negativeText,
          prefixPrompt: prefixText,
          suffixPrompt: suffixText,
          previewImagePath: resolvedPreviewPath,
          characterPrompts: charPrompts,
          linkedEntryIds: linkedIds,
          preciseReferences: attachedPrecise,
          vibeReferences: attachedVibes,
          createdAt: now,
          updatedAt: now,
          isFavorite: spec['favorite'] is bool
              ? spec['favorite'] as bool
              : false,
          tags: _parseTags(spec['tags']),
        ),
      );
      created.add(saved);
      createdIdByTitle[entryTitle.toLowerCase()] = saved.id;
    }

    final details = created
        .map(
          (e) =>
              '• ${e.title} (id: ${e.id}) | 分类: ${e.category}'
              '${e.isFavorite ? ' | 已收藏' : ''}',
        )
        .join('\n');
    final buffer = StringBuffer(
      specs.length == 1
          ? '已新增词库条目：\n${formatPromptComboEntry(created.first)}'
          : '已新增 ${created.length} 个词库条目：\n$details',
    );
    buffer.write('\n如需为条目配置预览图，可调用 set_prompt_library_preview 工具。');
    return ToolResult(toolCallId: toolCallId, content: buffer.toString());
  }
}

/// 词库条目预览图设置工具
///
/// 支持三种来源：画板历史图片索引、本地图片文件路径、清除预览图。
class SetPromptLibraryPreviewTool extends AgentTool {
  final PromptLibraryEntriesGetter getEntries;
  final PromptLibraryUpdateEntry updateEntry;
  final PromptLibraryInboxGetter? getInboxItems;

  /// 画板历史图片列表 (从新到旧，索引 0 为最新)
  final PromptLibraryHistoryGetter? getHistory;

  /// 历史图片大图字节按需加载器 (内存缺失时从磁盘缓存回载)
  final PromptLibraryImageBytesLoader? loadImageBytes;

  /// 预览图字节落盘器
  final PromptLibraryPreviewBytesSaver? savePreviewBytes;

  /// 外部图片路径复制器
  final PromptLibraryPreviewPathCopier? copyPreviewFromPath;

  SetPromptLibraryPreviewTool({
    required this.getEntries,
    required this.updateEntry,
    this.getInboxItems,
    this.getHistory,
    this.loadImageBytes,
    this.savePreviewBytes,
    this.copyPreviewFromPath,
  }) : super(
         name: 'set_prompt_library_preview',
         label: '设置词库预览图',
         description:
             '为词库条目设置预览图 (词库画廊卡片上展示的缩略图)。'
             '三种来源任选其一：index 指定画板历史图片索引 (从新到旧，0 为最新，'
             '典型用法是先生成图片再取 index 0)；image_path 指定本地图片文件路径；'
             'clear 为 true 时清除该条目的预览图。'
             '超过 1024px 长边的图片会自动等比压缩为 PNG 后存入托管预览目录。',
         parameters: const {
           'type': 'object',
           'required': ['id'],
           'properties': {
             'id': {'type': 'string', 'description': '词库条目 ID'},
             'index': {
               'type': 'integer',
               'description': '画板历史图片索引 (从新到旧，0 为最新一张)',
             },
             'image_path': {
               'type': 'string',
               'description': '本地图片文件绝对路径 (如保存目录中的 PNG)',
             },
             'clear': {'type': 'boolean', 'description': '为 true 时清除该条目的预览图'},
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
        content: '未找到 ID 为 "$id" 的词库条目。可先调用 prompt_library(action: "search") 查询。',
        isError: true,
      );
    }

    final current = entries[idx];

    // 1. 清除预览图 (兼容 clear / clear_preview)
    final clearFlag =
        (args['clear'] is bool && args['clear'] as bool) ||
        (args['clear_preview'] is bool && args['clear_preview'] as bool);
    if (clearFlag) {
      if (current.previewImagePath == null) {
        return ToolResult(
          toolCallId: toolCallId,
          content: '条目「${current.title}」($id) 本就没有预览图，无需清除。',
        );
      }
      final updated = current.copyWith(
        clearPreviewImage: true,
        updatedAt: DateTime.now(),
      );
      await updateEntry(updated);
      return ToolResult(
        toolCallId: toolCallId,
        content: '已清除条目「${current.title}」($id) 的预览图。',
      );
    }

    // 2. 待整理区图片索引来源
    final inboxId = (args['inbox_id'] as String?)?.trim() ?? '';
    if (inboxId.isNotEmpty) {
      return _applyFromInbox(toolCallId, current, inboxId);
    }

    // 3. 画板历史图片索引来源 (兼容 index / image_index)
    final rawHistoryIndex = args.containsKey('index')
        ? args['index']
        : args['image_index'];
    if (rawHistoryIndex != null) {
      return _applyFromHistoryIndex(
        toolCallId,
        {'index': rawHistoryIndex},
        current,
      );
    }

    // 4. 本地图片路径来源
    final imagePath = (args['image_path'] as String?)?.trim() ?? '';
    if (imagePath.isNotEmpty) {
      return _applyFromPath(toolCallId, current, imagePath);
    }

    return ToolResult(
      toolCallId: toolCallId,
      content:
          '未指定预览图来源：请传入 index / image_index (画板历史图片索引)、inbox_id (待整理区条目 ID)、'
          'image_path (本地图片路径) 或 clear: true (清除预览图)。',
      isError: true,
    );
  }

  Future<ToolResult> _applyFromInbox(
    String toolCallId,
    PromptComboEntry current,
    String inboxId,
  ) async {
    final inboxItems = getInboxItems?.call() ?? const <PromptInboxItem>[];
    final target = inboxItems.where((e) => e.id == inboxId).firstOrNull;
    if (target == null) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '未找到 ID 为 "$inboxId" 的待整理区条目。',
        isError: true,
      );
    }
    final path = target.imagePath?.trim();
    if (path == null || path.isEmpty || !File(path).existsSync()) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '待整理区条目 "$inboxId" 没有可用的图片文件。',
        isError: true,
      );
    }
    final updated = current.copyWith(
      previewImagePath: path,
      updatedAt: DateTime.now(),
    );
    await updateEntry(updated);
    return ToolResult(
      toolCallId: toolCallId,
      content:
          '已为条目「${current.title}」(${current.id}) 设置预览图 (来源: 待整理区 $inboxId)。\n'
          '${formatPromptComboEntry(updated)}',
    );
  }

  Future<ToolResult> _applyFromHistoryIndex(
    String toolCallId,
    Map<String, dynamic> args,
    PromptComboEntry current,
  ) async {
    final history = getHistory?.call() ?? const <NaiGeneratedImage>[];
    if (history.isEmpty) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '画板当前没有任何历史图片，无法按索引取图。可改用 image_path 指定本地图片。',
        isError: true,
      );
    }

    final rawIndex = args['index'];
    int index = -1;
    if (rawIndex is int) {
      index = rawIndex;
    } else if (rawIndex is num) {
      index = rawIndex.toInt();
    } else if (rawIndex is String) {
      index = int.tryParse(rawIndex) ?? -1;
    }
    if (index < 0 || index >= history.length) {
      return ToolResult(
        toolCallId: toolCallId,
        content:
            '指定的图片索引 $index 超出范围。当前共有 ${history.length} 张历史图片，'
            '有效索引范围为 0 到 ${history.length - 1}。',
        isError: true,
      );
    }

    final image = history[index];
    final loader = loadImageBytes;
    Uint8List? bytes;
    if (loader != null) {
      try {
        bytes = await loader(image);
      } catch (_) {
        bytes = null;
      }
    }
    if (bytes == null || bytes.isEmpty) {
      bytes = image.bytes.isNotEmpty ? image.bytes : null;
    }
    if (bytes == null || bytes.isEmpty) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '未能加载索引 $index 图片「${image.id}」的图像字节 (磁盘缓存可能已失效)。',
        isError: true,
      );
    }

    final saver = savePreviewBytes;
    if (saver == null) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '当前环境未接入预览图存储服务。',
        isError: true,
      );
    }

    final scaled = await downscalePreviewBytes(bytes);
    final savedPath = await saver(scaled);
    if (savedPath == null) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '预览图保存失败 (写入托管预览目录时出错)。',
        isError: true,
      );
    }

    final updated = current.copyWith(
      previewImagePath: savedPath,
      updatedAt: DateTime.now(),
    );
    await updateEntry(updated);

    return ToolResult(
      toolCallId: toolCallId,
      content:
          '已为条目「${current.title}」(${current.id}) 设置预览图 '
          '(来源: 画板历史图片 索引 $index, ${bytes.lengthInBytes ~/ 1024} KB → '
          '${scaled.lengthInBytes ~/ 1024} KB)。\n'
          '${formatPromptComboEntry(updated)}',
    );
  }

  Future<ToolResult> _applyFromPath(
    String toolCallId,
    PromptComboEntry current,
    String imagePath,
  ) async {
    final copier = copyPreviewFromPath;
    if (copier == null) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '当前环境未接入预览图存储服务。',
        isError: true,
      );
    }

    final savedPath = await copier(imagePath);
    if (savedPath == null) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '未能从路径读取图片: "$imagePath" (文件不存在或读取失败)。',
        isError: true,
      );
    }

    final updated = current.copyWith(
      previewImagePath: savedPath,
      updatedAt: DateTime.now(),
    );
    await updateEntry(updated);

    return ToolResult(
      toolCallId: toolCallId,
      content:
          '已为条目「${current.title}」(${current.id}) 设置预览图 (来源: $imagePath)。\n'
          '${formatPromptComboEntry(updated)}',
    );
  }
}

/// 预览图最大长边 (超过则等比压缩，控制词库画廊的磁盘与内存占用)
const int kPromptPreviewMaxDimension = 1024;

/// 将图片字节等比压缩到最长边不超过 [maxDimension] 的 PNG。
///
/// 解码失败或尺寸本就不超限时原样返回原始字节。
Future<Uint8List> downscalePreviewBytes(
  Uint8List bytes, {
  int maxDimension = kPromptPreviewMaxDimension,
}) async {
  ui.Codec? codec;
  ui.Image? source;
  ui.Picture? picture;
  ui.Image? rendered;
  try {
    codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    source = frame.image;

    final longSide = math.max(source.width, source.height);
    if (longSide <= maxDimension) {
      return bytes;
    }

    final scale = maxDimension / longSide;
    final outW = math.max(1, (source.width * scale).round());
    final outH = math.max(1, (source.height * scale).round());

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      ui.Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble()),
    );
    canvas.drawImageRect(
      source,
      ui.Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
      ui.Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.medium,
    );
    picture = recorder.endRecording();
    rendered = await picture.toImage(outW, outH);
    final data = await rendered.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) return bytes;
    return data.buffer.asUint8List();
  } catch (_) {
    return bytes;
  } finally {
    rendered?.dispose();
    picture?.dispose();
    source?.dispose();
    codec?.dispose();
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
             'ID 可先用 search_prompt_library 查询获取；一次修改复数条目时用 updates 数组，'
             '不要逐条多次调用。',
         parameters: const {
           'type': 'object',
           'properties': {
             'id': {'type': 'string', 'description': '要修改的条目 ID'},
             'title': {'type': 'string', 'description': '新标题'},
             'prompt': {'type': 'string', 'description': '新正向提示词'},
             'category': {
               'type': 'string',
               'enum': ['角色', '风格', '服装', '构图', '环境', '特效', '其他'],
               'description': '新分类',
             },
             'prefix_prompt': {
               'type': 'string',
               'description': '新前置词 (仅风格分类保留，传入空字符串可清除)',
             },
             'suffix_prompt': {
               'type': 'string',
               'description': '新后置词 (仅风格分类保留，传入空字符串可清除)',
             },
             'negative_prompt': {
               'type': 'string',
               'description': '新负面提示词 (角色与风格分类保留，传入空字符串可清除)',
             },
             'tags': {
               'type': 'array',
               'items': {'type': 'string'},
               'description': '新标签列表 (整体替换)',
             },
             'favorite': {'type': 'boolean', 'description': '是否收藏'},
             'updates': {
               'type': 'array',
               'description':
                   '批量修改多个条目：每项含 id 与要修改的字段 (字段名与顶层同名参数一致)，本次调用内一次全部应用',
               'items': {
                 'type': 'object',
                 'properties': {
                   'id': {'type': 'string'},
                   'title': {'type': 'string'},
                   'prompt': {'type': 'string'},
                   'category': {'type': 'string'},
                   'prefix_prompt': {'type': 'string'},
                   'suffix_prompt': {'type': 'string'},
                   'negative_prompt': {'type': 'string'},
                   'tags': {
                     'type': 'array',
                     'items': {'type': 'string'},
                   },
                   'favorite': {'type': 'boolean'},
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
    final batch = args['updates'] != null;
    final rawSpecs = args['updates'];
    final specs = <Map<String, dynamic>>[];
    if (rawSpecs != null) {
      if (rawSpecs is! List || rawSpecs.isEmpty) {
        return ToolResult(
          toolCallId: toolCallId,
          content: 'updates 必须是非空对象数组。',
          isError: true,
        );
      }
      for (final item in rawSpecs) {
        if (item is! Map) {
          return ToolResult(
            toolCallId: toolCallId,
            content: 'updates 必须是非空对象数组。',
            isError: true,
          );
        }
        specs.add(item.cast<String, dynamic>());
      }
    } else {
      specs.add(args);
    }

    if (!batch) {
      final id = (args['id'] as String?)?.trim() ?? '';
      if (id.isEmpty) {
        return ToolResult(
          toolCallId: toolCallId,
          content: 'id 为必填项。',
          isError: true,
        );
      }
      if (!getEntries().any((e) => e.id == id)) {
        return ToolResult(
          toolCallId: toolCallId,
          content: '未找到 ID 为 "$id" 的词库条目。可先调用 prompt_library(action: "search") 查询。',
          isError: true,
        );
      }
    }

    final applied = <String>[];
    final failed = <String>[];
    for (final spec in specs) {
      final id = (spec['id'] as String?)?.trim() ?? '';
      if (id.isEmpty) {
        failed.add('缺少条目 id');
        continue;
      }
      // 每次重新读取，保证同一批次内对同一条目的多次修改依次生效
      final current = getEntries().where((e) => e.id == id).firstOrNull;
      if (current == null) {
        failed.add('未找到 ID 为 $id 的词库条目');
        continue;
      }

      final hasLinkedField =
          spec.containsKey('linked_entry_ids') ||
          spec.containsKey('linked_entry_titles');
      final resolvedLinked = hasLinkedField
          ? _resolveLinkedIds(
              rawIds: spec['linked_entry_ids'],
              rawTitles: spec['linked_entry_titles'],
              existingEntries: getEntries(),
              excludeId: current.id,
            )
          : null;

      final updated = current.copyWith(
        title: (spec['title'] as String?)?.trim().isNotEmpty == true
            ? (spec['title'] as String).trim()
            : null,
        prompt: spec.containsKey('prompt')
            ? ((spec['prompt'] as String?)?.trim() ?? '')
            : null,
        category: (spec['category'] as String?)?.trim().isNotEmpty == true
            ? (spec['category'] as String).trim()
            : null,
        prefixPrompt: spec.containsKey('prefix_prompt')
            ? ((spec['prefix_prompt'] as String?)?.trim() ?? '')
            : null,
        suffixPrompt: spec.containsKey('suffix_prompt')
            ? ((spec['suffix_prompt'] as String?)?.trim() ?? '')
            : null,
        negativePrompt: spec.containsKey('negative_prompt')
            ? ((spec['negative_prompt'] as String?)?.trim() ?? '')
            : null,
        characterPrompts: spec.containsKey('character_prompts')
            ? _parseCharacterPrompts(spec['character_prompts'])
            : null,
        linkedEntryIds: resolvedLinked,
        isFavorite: spec['favorite'] is bool ? spec['favorite'] as bool : null,
        tags: spec.containsKey('tags') ? _parseTags(spec['tags']) : null,
        updatedAt: DateTime.now(),
      );

      await updateEntry(updated);
      applied.add('已修改词库条目：\n${formatPromptComboEntry(updated)}');
    }

    if (applied.isEmpty) {
      if (batch) {
        return ToolResult(
          toolCallId: toolCallId,
          content: '未修改任何条目：${failed.join('；')}。',
          isError: true,
        );
      }
      return ToolResult(
        toolCallId: toolCallId,
        content: '未修改任何字段 (没有传入有效的更新内容)。',
      );
    }

    final buffer = StringBuffer(applied.join('\n'));
    if (failed.isNotEmpty) buffer.write('\n未修改：${failed.join('；')}。');
    return ToolResult(toolCallId: toolCallId, content: buffer.toString());
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
             '按 ID 删除本地词库中的词组合条目 (不可恢复)。ID 可先用 search_prompt_library 查询获取；'
             '删除复数条目时用 ids 数组一次完成，不要逐条多次调用。',
         parameters: const {
           'type': 'object',
           'properties': {
             'id': {'type': 'string', 'description': '要删除的单个条目 ID'},
             'ids': {
               'type': 'array',
               'items': {'type': 'string'},
               'description': '批量删除的条目 ID 列表 (与 id 可并用)',
             },
           },
         },
       );

  @override
  Future<ToolResult> execute(
    String toolCallId,
    Map<String, dynamic> args,
  ) async {
    final ids = <String>{};
    final single = (args['id'] as String?)?.trim() ?? '';
    if (single.isNotEmpty) ids.add(single);
    final many = args['ids'];
    if (many != null) {
      if (many is! List || many.isEmpty) {
        return ToolResult(
          toolCallId: toolCallId,
          content: 'ids 必须是非空字符串数组。',
          isError: true,
        );
      }
      for (final item in many) {
        final value = '$item'.trim();
        if (value.isNotEmpty) ids.add(value);
      }
    }
    if (ids.isEmpty) {
      return ToolResult(
        toolCallId: toolCallId,
        content: 'id 为必填项。',
        isError: true,
      );
    }

    final entries = getEntries();
    final targets = entries.where((e) => ids.contains(e.id)).toList();
    if (targets.isEmpty) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '未找到 ID 为 ${ids.join('、')} 的词库条目。',
        isError: true,
      );
    }

    for (final target in targets) {
      await deleteEntry(target.id);
    }

    final missing = ids.where((id) => !targets.any((e) => e.id == id)).toList();
    final buffer = StringBuffer(
      targets.length == 1
          ? '已删除词库条目「${targets.first.title}」(${targets.first.id})。'
          : '已删除 ${targets.length} 个词库条目：'
                '${targets.map((e) => '“${e.title}”(${e.id})').join('、')}。',
    );
    if (missing.isNotEmpty) buffer.write('未找到 ${missing.join('、')}。');
    return ToolResult(toolCallId: toolCallId, content: buffer.toString());
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

/// 解析多角色提示词数组 ([{name, prompt, negative_prompt}])
List<PromptInboxCharacter> _parseCharacterPrompts(dynamic raw) {
  if (raw is! List) return const [];
  final out = <PromptInboxCharacter>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final map = item.cast<String, dynamic>();
    final prompt = (map['prompt'] as String?)?.trim() ?? '';
    if (prompt.isEmpty) continue;
    final name = (map['name'] as String?)?.trim() ?? '';
    final neg =
        ((map['negative_prompt'] as String?) ??
                (map['negativePrompt'] as String?))
            ?.trim() ??
        '';
    out.add(
      PromptInboxCharacter(name: name, prompt: prompt, negativePrompt: neg),
    );
  }
  return out;
}

/// 解析关联条目 ID 列表（同时支持直接传 linked_entry_ids 与按标题查找 linked_entry_titles）
List<String> _resolveLinkedIds({
  dynamic rawIds,
  dynamic rawTitles,
  required List<PromptComboEntry> existingEntries,
  Map<String, String> batchIdByTitle = const {},
  String? excludeId,
}) {
  final result = <String>[];
  final seen = <String>{if (excludeId != null && excludeId.isNotEmpty) excludeId};

  if (rawIds is List) {
    for (final item in rawIds) {
      final id = item.toString().trim();
      if (id.isNotEmpty && seen.add(id)) {
        result.add(id);
      }
    }
  }
  if (rawTitles is List) {
    final existingByTitle = <String, String>{
      for (final e in existingEntries) e.title.trim().toLowerCase(): e.id,
    };
    for (final item in rawTitles) {
      final key = item.toString().trim().toLowerCase();
      if (key.isEmpty) continue;
      final resolved = batchIdByTitle[key] ?? existingByTitle[key];
      if (resolved != null && resolved.isNotEmpty && seen.add(resolved)) {
        result.add(resolved);
      }
    }
  }
  return result;
}

/// 独立后台预览图生成回调签名（用于待整理区分离后自动重跑预览图，不污染工作台与画板历史）
typedef GenerateLibraryPreviewCallback =
    Future<({bool ok, String message})> Function({
      required PromptComboEntry entry,
      required String prompt,
      String negativePrompt,
      List<PromptInboxCharacter> characterPrompts,
      int width,
      int height,
    });

/// 词库条目独立预览图重跑工具（仅后台整理 Agent 在开启「分离后自动重跑预览图」时注册）
class GenerateLibraryPreviewTool extends AgentTool {
  final PromptLibraryEntriesGetter getEntries;
  final GenerateLibraryPreviewCallback generatePreview;

  GenerateLibraryPreviewTool({
    required this.getEntries,
    required this.generatePreview,
  }) : super(
         name: 'generate_library_preview',
         label: '重跑词库预览图',
         description:
             '为指定词库条目独立生成一张专属预览图并自动绑定（不会覆盖工作台参数也不会污染画板历史；'
             '严格限制在 Opus 免费区间尺寸内）。适合把一张图拆出的角色/服装/构图/环境分别重跑独立预览图。',
         parameters: const {
           'type': 'object',
           'required': ['entry_id', 'prompt'],
           'properties': {
             'entry_id': {'type': 'string', 'description': '要更新预览图的词库条目 ID'},
             'prompt': {
               'type': 'string',
               'description': '用于生成该条目专属预览图的正向提示词（英文 Danbooru 标签；服装可结合所属角色，构图可用简洁主体展示）',
             },
             'negative_prompt': {
               'type': 'string',
               'description': '可选：负面提示词',
             },
             'character_prompts': {
               'type': 'array',
               'description': '可选：多角色提示词数组 [{name, prompt, negative_prompt}]',
               'items': {
                 'type': 'object',
                 'properties': {
                   'name': {'type': 'string'},
                   'prompt': {'type': 'string'},
                   'negative_prompt': {'type': 'string'},
                 },
               },
             },
             'width': {
               'type': 'integer',
               'description': '可选宽度 (64 倍数，默认 832；像素总数不超过 1048576)',
             },
             'height': {
               'type': 'integer',
               'description': '可选高度 (64 倍数，默认 1216；像素总数不超过 1048576)',
             },
           },
         },
       );

  @override
  Future<ToolResult> execute(
    String toolCallId,
    Map<String, dynamic> args,
  ) async {
    final entryId =
        ((args['entry_id'] as String?) ?? (args['id'] as String?))?.trim() ?? '';
    final prompt = (args['prompt'] as String?)?.trim() ?? '';
    if (entryId.isEmpty || prompt.isEmpty) {
      return ToolResult(
        toolCallId: toolCallId,
        content: 'entry_id 与 prompt 均为必填项。',
        isError: true,
      );
    }
    final entry = getEntries().where((e) => e.id == entryId).firstOrNull;
    if (entry == null) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '未找到 ID 为 "$entryId" 的词库条目。',
        isError: true,
      );
    }

    var width = ((args['width'] as num?)?.toInt() ?? 832).clamp(512, 1216);
    var height = ((args['height'] as num?)?.toInt() ?? 1216).clamp(512, 1216);
    width = (width ~/ 64) * 64;
    height = (height ~/ 64) * 64;
    if (width * height > 1048576) {
      width = 832;
      height = 1216;
    }

    final negative = (args['negative_prompt'] as String?)?.trim() ?? '';
    final chars = _parseCharacterPrompts(args['character_prompts']);
    final outcome = await generatePreview(
      entry: entry,
      prompt: prompt,
      negativePrompt: negative,
      characterPrompts: chars,
      width: width,
      height: height,
    );
    return ToolResult(
      toolCallId: toolCallId,
      content: outcome.message,
      isError: !outcome.ok,
    );
  }
}

/// 统一本地词组合预设库管理工具（合并 search / add / update / delete / set_preview / apply / 待整理区管理 为单工具）
class PromptLibraryTool extends AgentTool {
  final SearchPromptLibraryTool _searchTool;
  final AddPromptLibraryEntryTool _addTool;
  final UpdatePromptLibraryEntryTool _updateTool;
  final DeletePromptLibraryEntryTool _deleteTool;
  final SetPromptLibraryPreviewTool _previewTool;
  final PromptLibraryEntriesGetter _getEntries;
  final PromptLibraryInboxGetter? _getInboxItems;
  final PromptLibraryInboxDelete? deleteInboxItems;
  final PromptLibraryVisionChecker? isModelMultimodal;
  final PromptLibraryApplyEntryCallback? applyEntry;

  PromptLibraryTool({
    required PromptLibraryEntriesGetter getEntries,
    required PromptLibraryAddEntry addEntry,
    required PromptLibraryUpdateEntry updateEntry,
    required PromptLibraryDeleteEntry deleteEntry,
    PromptLibraryInboxGetter? getInboxItems,
    this.deleteInboxItems,
    this.isModelMultimodal,
    Set<String>? excludedCategories,
    required PromptLibraryHistoryGetter getHistory,
    required PromptLibraryImageBytesLoader loadImageBytes,
    PromptLibraryPreviewBytesSaver? savePreviewBytes,
    PromptLibraryPreviewPathCopier? copyPreviewFromPath,
    PromptLibraryWorkspacePreciseSnapshot? snapshotWorkspacePrecise,
    PromptLibraryWorkspaceVibeSnapshot? snapshotWorkspaceVibe,
    this.applyEntry,
  }) : _getEntries = getEntries,
       _getInboxItems = getInboxItems,
       _searchTool = SearchPromptLibraryTool(getEntries: getEntries),
       _addTool = AddPromptLibraryEntryTool(
         getEntries: getEntries,
         addEntry: addEntry,
         getInboxItems: getInboxItems,
         excludedCategories: excludedCategories,
         snapshotWorkspacePrecise: snapshotWorkspacePrecise,
         snapshotWorkspaceVibe: snapshotWorkspaceVibe,
       ),
       _updateTool = UpdatePromptLibraryEntryTool(
         getEntries: getEntries,
         updateEntry: updateEntry,
       ),
       _deleteTool = DeletePromptLibraryEntryTool(
         getEntries: getEntries,
         deleteEntry: deleteEntry,
       ),
       _previewTool = SetPromptLibraryPreviewTool(
         getEntries: getEntries,
         updateEntry: updateEntry,
         getInboxItems: getInboxItems,
         getHistory: getHistory,
         loadImageBytes: loadImageBytes,
         savePreviewBytes: savePreviewBytes,
         copyPreviewFromPath: copyPreviewFromPath,
       ),
       super(
         name: 'prompt_library',
         label: '本地词库管理',
         description:
             '统一检索、管理与应用本地词组合预设库（画风/角色/光影/构图/服装/关联精准参考与 Vibe）及词库待整理区。通过 action 选择操作：\n'
             '- search: 按关键词/分类检索正式词库条目，或按 id 读取详情（含已关联参考图与 Vibe）；\n'
             '- add: 新增单个或批量词库条目（可传 preview_inbox_id 复用待整理区图片作预览图，或传 attach_workspace_references / attach_workspace_vibes 一并保存当前工作台参考图）；\n'
             '- update: 按 id 或 updates 数组修改正式词库条目；\n'
             '- delete: 按 id 或 ids 数组删除正式词库条目；\n'
             '- set_preview: 为词库条目设置/替换预览图（来自画板历史图 image_index、待整理区 inbox_id 或本地路径 image_path）；\n'
             '- apply: 按 id 选择性应用条目到工作台（可自由控制是否应用提示词、精准参考、Vibe 及追加/替换模式）；\n'
             '- list_inbox: 列出词库待整理区中的所有暂存条目（含主提示词、角色提示词数量与是否有图）；\n'
             '- read_inbox: 按 inbox_id 读取单条待整理项的完整主提示词、全部角色提示词及对应图片（多模态模型默认附带 ≤1024px 图片供视觉审查）；\n'
             '- delete_inbox: 按 inbox_id 或 inbox_ids 批量删除已整理完毕的待整理区条目（复用为正式词库预览图的图片文件会自动保留）。',
         parameters: const {
           'type': 'object',
           'properties': {
             'action': {
               'type': 'string',
               'enum': [
                 'search',
                 'add',
                 'update',
                 'delete',
                 'set_preview',
                 'apply',
                 'list_inbox',
                 'read_inbox',
                 'delete_inbox',
               ],
               'description':
                   '操作类型：search / add / update / delete / set_preview / apply / list_inbox / read_inbox / delete_inbox',
             },
             'query': {'type': 'string', 'description': '搜索关键词 (search)'},
             'category': {'type': 'string', 'description': '条目分类 (search / add / update)'},
             'offset': {'type': 'integer', 'description': '分页偏移，默认 0 (search / list_inbox)'},
             'limit': {'type': 'integer', 'description': '返回数量上限 (search / list_inbox)'},
             'id': {'type': 'string', 'description': '条目 ID (search / update / delete / set_preview / apply)'},
             'ids': {
               'type': 'array',
               'items': {'type': 'string'},
               'description': '批量删除的条目 ID 列表 (delete / delete_inbox)',
             },
             'inbox_id': {
               'type': 'string',
               'description': '待整理区条目 ID (read_inbox / delete_inbox / set_preview)',
             },
             'inbox_ids': {
               'type': 'array',
               'items': {'type': 'string'},
               'description': '批量删除的待整理区条目 ID 列表 (delete_inbox)',
             },
             'include_image': {
               'type': 'boolean',
               'description': '读取待整理项时是否附带图片供视觉查看，多模态模型默认 true (read_inbox)',
             },
             'preview_inbox_id': {
               'type': 'string',
               'description': '新增条目时复用指定待整理区条目的图片作预览图 (add)',
             },
             'title': {'type': 'string', 'description': '条目标题 (add / update)'},
             'prompt': {'type': 'string', 'description': '正向提示词 (add / update)'},
             'prefix_prompt': {'type': 'string', 'description': '前置词，仅风格分类生效 (add / update)'},
             'suffix_prompt': {'type': 'string', 'description': '后置词，仅风格分类生效 (add / update)'},
             'negative_prompt': {'type': 'string', 'description': '负向提示词 (add / update)'},
             'character_prompts': {
               'type': 'array',
               'items': {'type': 'object'},
               'description': '多角色提示词数组 [{name, prompt, negative_prompt}]，用于同时含主提示词和角色提示词的条目 (add / update)',
             },
             'linked_entry_ids': {
               'type': 'array',
               'items': {'type': 'string'},
               'description': '关联的其他词库条目 ID 列表，例如服装关联所属角色 (add / update)',
             },
             'linked_entry_titles': {
               'type': 'array',
               'items': {'type': 'string'},
               'description': '按标题关联词库条目（支持引用同一批 entries 中先创建的角色标题）(add / update)',
             },
             'tags': {'description': '标签数组或逗号分隔字符串 (add / update)'},
             'favorite': {'type': 'boolean', 'description': '是否收藏 (add / update)'},
             'attach_workspace_references': {
               'type': 'boolean',
               'description': '新增条目时一并保存当前工作台精准参考图 (add)',
             },
             'attach_workspace_vibes': {
               'type': 'boolean',
               'description': '新增条目时一并保存当前工作台 Vibe Transfer (add)',
             },
             'apply_prompt': {
               'type': 'boolean',
               'description': '应用条目时是否应用提示词，默认 true (apply)',
             },
             'replace_prompt': {
               'type': 'boolean',
               'description': '应用提示词时是否替换而非追加，默认 false (apply)',
             },
             'as_character': {
               'type': 'boolean',
               'description': '角色条目是否作为多角色卡添加，默认 false (apply)',
             },
             'as_style': {
               'type': 'boolean',
               'description': '风格条目是否应用到固定前后缀，默认风格条目为 true (apply)',
             },
             'apply_precise_references': {
               'type': 'boolean',
               'description': '是否应用条目保存的精准参考图，默认 true (apply)',
             },
             'apply_vibe_references': {
               'type': 'boolean',
               'description': '是否应用条目保存的 Vibe Transfer，默认 true (apply)',
             },
             'replace_references': {
               'type': 'boolean',
               'description': '应用参考图/Vibe 时是否先清空同类型已有项，默认 false (apply)',
             },
             'entries': {
               'type': 'array',
               'items': {'type': 'object'},
               'description': '批量新增的条目数组，每项可含 preview_inbox_id (add)',
             },
             'updates': {
               'type': 'array',
               'items': {'type': 'object'},
               'description': '批量修改的条目数组，每项需含 id (update)',
             },
             'image_index': {
               'type': 'integer',
               'description': '画板历史图索引，0 表示最新图 (set_preview)',
             },
             'image_path': {
               'type': 'string',
               'description': '本地图片绝对路径 (set_preview)',
             },
             'clear_preview': {
               'type': 'boolean',
               'description': '是否清除预览图 (set_preview)',
             },
           },
           'required': ['action'],
         },
       );

  @override
  Future<ToolResult> execute(
    String toolCallId,
    Map<String, dynamic> args,
  ) async {
    final action = (args['action'] as String?)?.trim().toLowerCase() ?? '';
    return switch (action) {
      'search' || 'list' => _searchTool.execute(toolCallId, args),
      'add' => _addTool.execute(toolCallId, args),
      'update' => _updateTool.execute(toolCallId, args),
      'delete' || 'remove' => _deleteTool.execute(toolCallId, args),
      'set_preview' || 'preview' => _previewTool.execute(toolCallId, args),
      'apply' => _executeApply(toolCallId, args),
      'list_inbox' || 'inbox' => _executeListInbox(toolCallId, args),
      'read_inbox' || 'inspect_inbox' => _executeReadInbox(toolCallId, args),
      'delete_inbox' || 'remove_inbox' => _executeDeleteInbox(toolCallId, args),
      _ => ToolResult(
        toolCallId: toolCallId,
        content:
            '错误：prompt_library 的 action 必须是 search / add / update / delete / set_preview / apply / list_inbox / read_inbox / delete_inbox。',
        isError: true,
      ),
    };
  }

  Future<ToolResult> _executeListInbox(
    String toolCallId,
    Map<String, dynamic> args,
  ) async {
    final getter = _getInboxItems;
    if (getter == null) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '当前环境未接入词库待整理区。',
        isError: true,
      );
    }

    final singleId =
        ((args['inbox_id'] as String?) ?? (args['id'] as String?))?.trim() ??
        '';
    if (singleId.isNotEmpty) {
      return _executeReadInbox(toolCallId, {...args, 'inbox_id': singleId});
    }

    final items = getter();
    if (items.isEmpty) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '词库待整理区当前为空。',
      );
    }

    final offset = ((args['offset'] as num?)?.toInt() ?? 0).clamp(
      0,
      items.length,
    );
    final limit = ((args['limit'] as num?)?.toInt() ?? 10).clamp(1, 50);
    final page = items.skip(offset).take(limit).toList(growable: false);

    final buf = StringBuffer('词库待整理区 (共 ${items.length} 条)：\n');
    for (final item in page) {
      final ts = item.createdAt
          .toLocal()
          .toIso8601String()
          .replaceAll('T', ' ')
          .split('.')
          .first;
      final summary = item.displaySummary.replaceAll('\n', ' ');
      final preview = summary.length > 140
          ? '${summary.substring(0, 140)}…'
          : summary;
      final tags = <String>[
        if (item.hasImage) '有图',
        if (item.characterPrompts.isNotEmpty)
          '角色×${item.characterPrompts.length}',
      ];
      final badge = tags.isNotEmpty ? ' [${tags.join(', ')}]' : '';
      buf.writeln('• [${item.id}] $ts$badge');
      if (preview.isNotEmpty) {
        buf.writeln('  摘要: $preview');
      }
    }
    final next = offset + page.length;
    buf.writeln(
      '本页 ${page.length} 条；请用 action: "read_inbox" + inbox_id 查看完整主/角色提示词及图片，'
      '整理入库时可用 action: "add"（传 preview_inbox_id 复用图片），完成后用 action: "delete_inbox" 清理。',
    );
    if (next < items.length) {
      buf.writeln('下一页 offset: $next');
    }
    return ToolResult(toolCallId: toolCallId, content: buf.toString());
  }

  Future<ToolResult> _executeReadInbox(
    String toolCallId,
    Map<String, dynamic> args,
  ) async {
    final getter = _getInboxItems;
    if (getter == null) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '当前环境未接入词库待整理区。',
        isError: true,
      );
    }

    final inboxId =
        ((args['inbox_id'] as String?) ?? (args['id'] as String?))?.trim() ??
        '';
    if (inboxId.isEmpty) {
      return ToolResult(
        toolCallId: toolCallId,
        content: 'read_inbox 操作必须提供 inbox_id。',
        isError: true,
      );
    }

    final item = getter().where((e) => e.id == inboxId).firstOrNull;
    if (item == null) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '未找到 ID 为 "$inboxId" 的待整理区条目。可先调用 list_inbox 查看列表。',
        isError: true,
      );
    }

    final includeImage = args['include_image'] is bool
        ? args['include_image'] as bool
        : true;
    final multimodal = isModelMultimodal?.call() ?? false;

    String? imageBase64;
    String imageMimeType = 'image/png';
    String? imageNote;

    if (item.hasImage && includeImage) {
      if (!multimodal) {
        imageNote = '提示：当前对话模型不支持视觉输入，本次仅返回文本提示词（整理入库仍可用 preview_inbox_id 复用该图片）。';
      } else {
        final file = File(item.imagePath!.trim());
        if (file.existsSync()) {
          try {
            final rawBytes = await file.readAsBytes();
            if (rawBytes.isNotEmpty) {
              final compressed = await compressVisionImage(rawBytes);
              imageBase64 = base64Encode(compressed.bytes);
              imageMimeType = compressed.mimeType;
              imageNote = '对应图片已作为视觉附件返回（最长边 ≤ 1024px）。';
            }
          } catch (_) {
            imageNote = '对应图片读取失败，本次仅返回文本提示词。';
          }
        } else {
          imageNote = '对应图片文件已丢失，本次仅返回文本提示词。';
        }
      }
    }

    final buf = StringBuffer('待整理区条目详情：\n')
      ..writeln(formatPromptInboxItem(item));
    if (imageNote != null) {
      buf.writeln(imageNote);
    }
    buf.write(
      '整理建议：可将可复用的角色、风格、服装、构图、环境或特效拆解后用 action: "add" 存入正式词库'
      '（传 preview_inbox_id: "${item.id}" 即可直接复用此图作为预览图），整理完毕后用 action: "delete_inbox" 移除本项。',
    );

    return ToolResult(
      toolCallId: toolCallId,
      content: buf.toString(),
      imageBase64: imageBase64,
      imageMimeType: imageMimeType,
    );
  }

  Future<ToolResult> _executeDeleteInbox(
    String toolCallId,
    Map<String, dynamic> args,
  ) async {
    final getter = _getInboxItems;
    final deleter = deleteInboxItems;
    if (getter == null || deleter == null) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '当前环境未接入词库待整理区删除能力。',
        isError: true,
      );
    }

    final ids = <String>{};
    final single =
        ((args['inbox_id'] as String?) ?? (args['id'] as String?))?.trim() ??
        '';
    if (single.isNotEmpty) ids.add(single);

    final rawList = args['inbox_ids'] ?? args['ids'];
    if (rawList != null) {
      if (rawList is! List || rawList.isEmpty) {
        return ToolResult(
          toolCallId: toolCallId,
          content: 'inbox_ids 必须是非空字符串数组。',
          isError: true,
        );
      }
      for (final item in rawList) {
        final v = '$item'.trim();
        if (v.isNotEmpty) ids.add(v);
      }
    }

    if (ids.isEmpty) {
      return ToolResult(
        toolCallId: toolCallId,
        content: 'delete_inbox 必须提供 inbox_id 或 inbox_ids。',
        isError: true,
      );
    }

    final existingIds = getter().map((e) => e.id).toSet();
    final found = ids.where(existingIds.contains).toList(growable: false);
    if (found.isEmpty) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '未找到待整理区条目：${ids.join('、')}。',
        isError: true,
      );
    }

    final removed = await deleter(found);
    final missing = ids
        .where((id) => !existingIds.contains(id))
        .toList(growable: false);
    final buf = StringBuffer('已从待整理区删除 $removed 项：${found.join('、')}。');
    if (missing.isNotEmpty) {
      buf.write('未找到：${missing.join('、')}。');
    }
    return ToolResult(toolCallId: toolCallId, content: buf.toString());
  }

  Future<ToolResult> _executeApply(
    String toolCallId,
    Map<String, dynamic> args,
  ) async {
    final applier = applyEntry;
    if (applier == null) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '当前环境不支持直接应用词库条目。',
        isError: true,
      );
    }
    final id = (args['id'] as String?)?.trim() ?? '';
    if (id.isEmpty) {
      return ToolResult(
        toolCallId: toolCallId,
        content: 'apply 操作必须提供条目 id。',
        isError: true,
      );
    }
    final entry = _getEntries().where((e) => e.id == id).firstOrNull;
    if (entry == null) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '未找到 ID 为 "$id" 的词库条目。',
        isError: true,
      );
    }
    final applyPrompt = args['apply_prompt'] is bool
        ? args['apply_prompt'] as bool
        : true;
    final replacePrompt = args['replace_prompt'] == true;
    final asCharacter = args['as_character'] == true;
    final asStyle = args['as_style'] is bool
        ? args['as_style'] as bool
        : entry.isStyle;
    final applyPrecise = args['apply_precise_references'] is bool
        ? args['apply_precise_references'] as bool
        : true;
    final applyVibe = args['apply_vibe_references'] is bool
        ? args['apply_vibe_references'] as bool
        : true;
    final replaceRefs = args['replace_references'] == true;

    final outcome = await applier(
      entry,
      applyPrompt: applyPrompt,
      replacePrompt: replacePrompt,
      asCharacter: asCharacter,
      asStyle: asStyle,
      applyPreciseReferences: applyPrecise,
      applyVibeReferences: applyVibe,
      replaceReferences: replaceRefs,
    );
    final parts = <String>[
      if (outcome.appliedPrompt) '提示词',
      if (outcome.appliedPreciseCount > 0)
        '精准参考 ${outcome.appliedPreciseCount} 张',
      if (outcome.appliedVibeCount > 0) 'Vibe ${outcome.appliedVibeCount} 条',
    ];
    if (parts.isEmpty) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '词库条目「${entry.title}」没有符合条件的可应用内容。',
        isError: true,
      );
    }
    return ToolResult(
      toolCallId: toolCallId,
      content: '已应用词库条目「${entry.title}」到工作台：${parts.join(' + ')}。',
    );
  }
}
