import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../../data/models/novelai_models.dart';
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

/// 格式化单条词库条目为可读文本
String formatPromptComboEntry(PromptComboEntry entry) {
  final lines = <String>[
    '• [${entry.id}] ${entry.title} (${entry.category})'
        '${entry.isFavorite ? ' [收藏]' : ''}${entry.isBuiltin ? ' [内置]' : ''}',
    '  提示词: ${entry.prompt}',
    if (entry.isCharacter && entry.negativePrompt.isNotEmpty)
      '  负面提示词: ${entry.negativePrompt}',
    if (entry.previewImagePath != null) '  预览图: 已设置',
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
            return '• [${entry.id}] $title (${entry.category})';
          })
          .join('\n'),
    );
    final next = offset + page.length;
    header.writeln('\n本页 ${page.length} 条；用 id 读取全文。');
    if (next < filtered.length) header.writeln('下一页 offset: $next');
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
      content:
          '已新增词库条目：\n${formatPromptComboEntry(created)}\n'
          '如需为该条目配置预览图，可调用 set_prompt_library_preview 工具。',
    );
  }
}

/// 词库条目预览图设置工具
///
/// 支持三种来源：画板历史图片索引、本地图片文件路径、清除预览图。
class SetPromptLibraryPreviewTool extends AgentTool {
  final PromptLibraryEntriesGetter getEntries;
  final PromptLibraryUpdateEntry updateEntry;

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
        content: '未找到 ID 为 "$id" 的词库条目。可先调用 search_prompt_library 查询。',
        isError: true,
      );
    }

    final current = entries[idx];

    // 1. 清除预览图
    if (args['clear'] is bool && args['clear'] as bool == true) {
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

    // 2. 画板历史图片索引来源
    final hasIndexArg = args.containsKey('index') && args['index'] != null;
    if (hasIndexArg) {
      return _applyFromHistoryIndex(toolCallId, args, current);
    }

    // 3. 本地图片路径来源
    final imagePath = (args['image_path'] as String?)?.trim() ?? '';
    if (imagePath.isNotEmpty) {
      return _applyFromPath(toolCallId, current, imagePath);
    }

    return ToolResult(
      toolCallId: toolCallId,
      content:
          '未指定预览图来源：请传入 index (画板历史图片索引)、image_path (本地图片路径) '
          '或 clear: true (清除预览图)。',
      isError: true,
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
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final source = frame.image;

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
    final picture = recorder.endRecording();
    final rendered = await picture.toImage(outW, outH);
    final data = await rendered.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) return bytes;
    return data.buffer.asUint8List();
  } catch (_) {
    return bytes;
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
