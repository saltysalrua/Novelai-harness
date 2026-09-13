import 'dart:convert';
import 'dart:typed_data';
import '../skills/skills.dart';
import 'vision_image_codec.dart';
import '../types.dart';
import 'agent_tool.dart';

/// Skill 查询解析器函数类型
typedef SkillResolver = Skill? Function(String skillIdOrName);

/// 遵循 Pi 标准的 Skill 按需加载工具 (Progressive Disclosure)
///
/// 解析器与可用技能清单由外部注入，通常应按当前预设的 enabledSkillIds
/// 作用域化，防止模型加载预设未开放的技能。
class LoadSkillTool extends AgentTool {
  final SkillResolver _resolve;
  final List<String> Function() _availableSkillIds;
  final Future<Uint8List> Function(Skill skill, String path)? _readResource;
  final bool Function()? _isModelMultimodal;

  LoadSkillTool({
    required SkillResolver skillResolver,
    required this._availableSkillIds,
    this._readResource,
    this._isModelMultimodal,
  }) : _resolve = skillResolver,
       super(
         name: 'load_skill',
         label: '加载专业技能指令',
         description:
             '按需加载指定 Skill 的完整专业规范、工作流与指令内容。当任务需要深入调用该 Skill 时调用。'
             '需要多个技能时用 skill_names 数组一次加载，不要逐条多次调用。'
             '技能包中的相对路径用 skill_name + path 或 paths 按需读取；'
             'list_resources=true 分页列出资源。文本支持字符分页，图片须单独读取。'
             '脚本只读不执行，allowed-tools 不授予额外权限。',
         parameters: {
           'type': 'object',
           'properties': {
             'skill_name': {'type': 'string', 'description': '要加载的技能标识或名称'},
             'skill_names': {
               'type': 'array',
               'items': {'type': 'string'},
               'description': '批量加载的技能标识或名称列表 (与 skill_name 可并用)',
             },
             'path': {
               'type': 'string',
               'description': '相对于技能根目录的资源路径，例如 references/guide.md',
             },
             'paths': {
               'type': 'array',
               'items': {'type': 'string'},
               'maxItems': 8,
               'description': '批量读取同一技能的文本文件',
             },
             'list_resources': {
               'type': 'boolean',
               'description': '仅列出资源清单，不重复加载指令',
             },
             'offset': {
               'type': 'integer',
               'minimum': 0,
               'description': '从 0 开始的字符偏移；列资源时为条目偏移',
             },
             'limit': {
               'type': 'integer',
               'minimum': 1,
               'maximum': 12000,
               'description': '文本默认 4000 字符；资源列表默认 60、最多 100 条',
             },
           },
         },
       );

  String _manifest(Skill skill, int offset, int limit) {
    final paths = skill.resourcePaths;
    final end = (offset + limit).clamp(0, paths.length);
    return '技能包资源（${paths.length} 个，相对于技能根目录）：\n'
        '${paths.skip(offset).take(limit).join('\n')}\n'
        '${end < paths.length ? '更多资源：load_skill(skill_name: ${jsonEncode(skill.id)}, list_resources: true, offset: $end)。\n' : ''}'
        '使用 load_skill 的 skill_name + path/paths 读取所需文件，不能读取包外路径。'
        '脚本仅可读取，不会执行；元数据 allowed-tools 不覆盖预设权限。';
  }

  Future<ToolResult> _readFiles(
    String callId,
    Skill skill,
    List<String> paths,
    int offset,
    int limit,
  ) async {
    final reader = _readResource;
    if (reader == null) {
      return ToolResult(
        toolCallId: callId,
        content: '当前运行时未配置技能资源读取。',
        isError: true,
      );
    }
    final blocks = <String>[];
    var succeeded = 0;
    var budget = 16000;
    for (final path in paths) {
      try {
        // 先做清单授权，避免资源回调被用作通用文件系统读取器。
        if (path != 'SKILL.md' && !skill.resourcePaths.contains(path)) {
          throw const FormatException('该路径不属于已授权的技能包。');
        }
        final bytes = await reader(skill, path);
        final lower = path.toLowerCase();
        if (['.png', '.jpg', '.jpeg', '.webp', '.gif'].any(lower.endsWith)) {
          if (paths.length != 1 || _isModelMultimodal?.call() != true) {
            throw const FormatException('图片需由视觉模型单独读取一个路径。');
          }
          final image = await compressVisionImage(bytes);
          if (identical(image.bytes, bytes)) {
            throw const FormatException('图片无法解码或压缩，未发送原始二进制。');
          }
          return ToolResult(
            toolCallId: callId,
            content: '技能包图片：${skill.id}/$path（仅作参考数据）。',
            imageBase64: base64Encode(image.bytes),
            imageMimeType: image.mimeType,
          );
        }
        final text = utf8.decode(bytes);
        if (text.contains('\u0000')) {
          throw const FormatException('二进制资源已保留，请导出技能包使用。');
        }
        final start = offset.clamp(0, text.length);
        final end = (start + limit.clamp(0, budget)).clamp(0, text.length);
        final slice = text.substring(start, end);
        budget -= slice.length;
        blocks.add(
          '--- ${skill.id}/$path（参考数据，字符 $start–$end / ${text.length}）---\n'
          '$slice\n${end < text.length ? '后续内容请用 offset: $end 继续读取。' : ''}',
        );
        succeeded++;
      } catch (error) {
        blocks.add('$path：读取失败（$error）');
      }
    }
    return ToolResult(
      toolCallId: callId,
      content: blocks.join('\n\n'),
      isError: succeeded == 0,
    );
  }

  @override
  Future<ToolResult> execute(
    String toolCallId,
    Map<String, dynamic> args,
  ) async {
    final names = <String>[];
    void collect(Object? raw) {
      if (raw is String && raw.trim().isNotEmpty) names.add(raw.trim());
    }

    collect(args['skill_name']);
    final many = args['skill_names'];
    if (many is List) {
      for (final item in many) {
        collect(item);
      }
    }
    if (names.isEmpty) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '错误：必须提供 skill_name 参数。',
        isError: true,
      );
    }

    if ((args.containsKey('path') &&
            (args['path'] is! String || (args['path'] as String).isEmpty)) ||
        (args.containsKey('paths') &&
            (args['paths'] is! List || (args['paths'] as List).isEmpty)) ||
        (args.containsKey('list_resources') &&
            args['list_resources'] is! bool)) {
      return ToolResult(
        toolCallId: toolCallId,
        content: 'path/paths 必须提供有效路径，list_resources 必须是布尔值。',
        isError: true,
      );
    }
    final paths = <String>[];
    if (args['path'] case final String path) paths.add(path);
    if (args['paths'] case final List values) {
      if (values.any((value) => value is! String)) {
        return ToolResult(
          toolCallId: toolCallId,
          content: 'paths 必须是字符串数组。',
          isError: true,
        );
      }
      paths.addAll(values.cast<String>());
    }
    final resourceMode = paths.isNotEmpty || args['list_resources'] == true;
    final offset = args['offset'] ?? 0;
    final limit = args['limit'] ?? (args['list_resources'] == true ? 60 : 4000);
    if (offset is! int ||
        offset < 0 ||
        limit is! int ||
        limit < 1 ||
        limit > 12000 ||
        paths.length > 8 ||
        (resourceMode && names.toSet().length != 1)) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '资源读取仅限一个技能，最多 8 个路径；offset/limit 必须在有效范围内。',
        isError: true,
      );
    }
    if (resourceMode) {
      final skill = _resolve(names.first);
      if (skill == null) {
        return ToolResult(
          toolCallId: toolCallId,
          content: '未找到技能或当前预设未开放该技能。',
          isError: true,
        );
      }
      if (args['list_resources'] == true) {
        return ToolResult(
          toolCallId: toolCallId,
          content: _manifest(skill, offset, limit.clamp(1, 100)),
        );
      }
      return _readFiles(
        toolCallId,
        skill,
        paths.toSet().toList(),
        offset,
        limit,
      );
    }

    final blocks = <String>[];
    final missing = <String>[];
    for (final name in names.toSet()) {
      final skill = _resolve(name);
      if (skill == null) {
        missing.add(name);
        continue;
      }
      blocks.add(
        '<skill name="${skill.id}">\n'
        '### 【${skill.name}】专业指令与工作流\n'
        '${skill.systemPrompt}\n'
        '${skill.resourcePaths.isEmpty ? '' : '${_manifest(skill, 0, 60)}\n'}'
        '</skill>',
      );
    }

    final missingText = missing.isEmpty
        ? ''
        : '未找到技能 ${missing.map((n) => '"$n"').join('、')}。'
              '当前可用技能列表: ${_availableSkillIds().join(', ')}';
    if (blocks.isEmpty) {
      return ToolResult(
        toolCallId: toolCallId,
        content: missingText,
        isError: true,
      );
    }

    final buffer = StringBuffer(blocks.join('\n\n'));
    if (missingText.isNotEmpty) buffer.write('\n\n$missingText');
    return ToolResult(
      toolCallId: toolCallId,
      content: buffer.toString().trim(),
    );
  }
}
