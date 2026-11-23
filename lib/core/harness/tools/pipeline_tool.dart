import 'dart:convert';
import '../types.dart';
import 'agent_tool.dart';

/// 轻量纯 Dart CodeMode 编排工具：单轮内串联多步工具调用、变量拼装与中间结果过滤。
///
/// 设计目标：
/// - 减少多轮 LLM 往返与中间大段结果对上下文的污染；
/// - 支持模块化字符串/数组拼装，便于在工具参数内完成提示词构造与隔离；
/// - 严格复用 [ToolRegistry] 与预设白名单校验，不绕过任何权限约束。
class RunPipelineTool extends AgentTool {
  static const int _maxSteps = 20;

  final ToolRegistry registry;
  final bool Function(String toolName)? isToolAllowed;
  final bool Function()? isCancelled;

  RunPipelineTool({
    required this.registry,
    this.isToolAllowed,
    this.isCancelled,
  }) : super(
         name: 'run_pipeline',
         label: '批量编排',
         description:
             '单轮顺序编排多个工具（含内置二级工具与已连接的 MCP 工具），支持变量组合与中间结果过滤，减少往返与上下文膨胀。\n'
             '• vars: 可选变量表，支持 {"join": [", ", "@a", [...]]} / {"concat": [...]} 组合字符串；\n'
             '• steps: 步骤数组 {id?, tool, args?, when?, continue_on_error?, filter?}；\n'
             '• 引用上步输出: @id / @id.tags / @id.tags_list / @id.lines / @id.first_line / "{{id}}"；\n'
             '• filter: {extract_tags?, grep?, max_lines?, max_chars?, silent?}；return_steps: 仅返回指定步骤详情（支持 "last"）。',
         parameters: const {
           'type': 'object',
           'properties': {
             'vars': {
               'type': 'object',
               'description': '可选初始变量映射，可用于分段拼装提示词或复用参数',
             },
             'steps': {
               'type': 'array',
               'description': '按顺序执行的工具步骤列表（最多 20 步）',
               'items': {
                 'type': 'object',
                 'properties': {
                   'id': {'type': 'string', 'description': '步骤标识，供后续步骤通过 @id 引用'},
                   'tool': {'type': 'string', 'description': '要调用的工具名'},
                   'args': {'type': 'object', 'description': '传给该工具的参数对象'},
                   'when': {
                     'description': '可选条件（布尔值或 @var / !@var），为 false 时跳过此步',
                   },
                   'continue_on_error': {
                     'type': 'boolean',
                     'description': '单步失败时是否继续后续步骤，默认 false',
                   },
                   'filter': {
                     'type': 'object',
                     'description': '对本步输出做过滤/裁剪，减少进入上下文的噪声',
                     'properties': {
                       'extract_tags': {'type': 'boolean'},
                       'grep': {'type': 'string'},
                       'max_lines': {'type': 'integer', 'minimum': 1},
                       'max_chars': {'type': 'integer', 'minimum': 1},
                       'silent': {'type': 'boolean'},
                     },
                   },
                 },
                 'required': ['tool'],
               },
             },
             'return_steps': {
               'type': 'array',
               'items': {'type': 'string'},
               'description': '仅详细返回这些步骤 ID 的输出（支持 "last"）',
             },
           },
           'required': ['steps'],
         },
       );

  @override
  Future<ToolResult> execute(
    String toolCallId,
    Map<String, dynamic> args,
  ) async {
    final rawSteps = args['steps'];
    if (rawSteps is! List || rawSteps.isEmpty) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '错误：steps 必须是非空步骤数组。',
        isError: true,
      );
    }
    if (rawSteps.length > _maxSteps) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '错误：单次编排最多支持 $_maxSteps 步（收到 ${rawSteps.length} 步）。',
        isError: true,
      );
    }

    final env = <String, Object?>{};
    final rawVars = args['vars'];
    if (rawVars is Map) {
      final varsScope = <String, Object?>{};
      for (final entry in rawVars.entries) {
        final key = '${entry.key}';
        final resolved = _resolveValue(entry.value, env);
        env[key] = resolved;
        varsScope[key] = resolved;
      }
      env['vars'] = varsScope;
    }

    final stepOutputs = <String, _PipelineStepRecord>{};
    final orderedRecords = <_PipelineStepRecord>[];
    String? latestImageBase64;
    String latestImageMimeType = 'image/png';
    var hadAnyError = false;

    for (var i = 0; i < rawSteps.length; i++) {
      if (isCancelled?.call() == true) {
        return ToolResult(
          toolCallId: toolCallId,
          content: _formatAborted(orderedRecords),
          isError: true,
        );
      }

      final rawStep = rawSteps[i];
      if (rawStep is! Map) {
        return ToolResult(
          toolCallId: toolCallId,
          content: '错误：第 ${i + 1} 步必须是对象。',
          isError: true,
        );
      }

      final step = Map<String, dynamic>.from(rawStep);
      final stepId = (step['id'] as String?)?.trim().isNotEmpty == true
          ? (step['id'] as String).trim()
          : 'step_${i + 1}';
      final toolName = (step['tool'] as String?)?.trim() ?? '';
      if (toolName.isEmpty) {
        return ToolResult(
          toolCallId: toolCallId,
          content: '错误：步骤 [$stepId] 缺少 tool 名称。',
          isError: true,
        );
      }
      if (toolName == name) {
        return ToolResult(
          toolCallId: toolCallId,
          content: '错误：步骤 [$stepId] 不允许递归调用 $name。',
          isError: true,
        );
      }

      final whenValue = step['when'];
      if (whenValue != null && !_evalCondition(whenValue, env)) {
        final skipped = _PipelineStepRecord(
          id: stepId,
          toolName: toolName,
          content: '(已跳过)',
          isError: false,
          silent: true,
          skipped: true,
        );
        stepOutputs[stepId] = skipped;
        orderedRecords.add(skipped);
        continue;
      }

      final targetTool = registry.get(toolName);
      if (targetTool == null) {
        return ToolResult(
          toolCallId: toolCallId,
          content: '错误：步骤 [$stepId] 引用了未知工具 "$toolName"。',
          isError: true,
        );
      }
      if (isToolAllowed != null && !isToolAllowed!(toolName)) {
        return ToolResult(
          toolCallId: toolCallId,
          content: '错误：步骤 [$stepId] 的工具 "$toolName" 未在当前预设中启用。',
          isError: true,
        );
      }

      final rawArgs = step['args'];
      if (rawArgs != null && rawArgs is! Map) {
        return ToolResult(
          toolCallId: toolCallId,
          content: '错误：步骤 [$stepId] 的 args 必须是对象。',
          isError: true,
        );
      }
      final resolvedArgs = rawArgs is Map
          ? Map<String, dynamic>.from(_resolveValue(rawArgs, env) as Map)
          : <String, dynamic>{};

      final ToolResult stepResult;
      try {
        stepResult = await targetTool.execute(
          '${toolCallId}_$stepId',
          resolvedArgs,
        );
      } catch (e) {
        return ToolResult(
          toolCallId: toolCallId,
          content: '步骤 [$stepId] 工具 "$toolName" 执行异常: $e',
          isError: true,
        );
      }

      if (stepResult.imageBase64 != null && stepResult.imageBase64!.isNotEmpty) {
        latestImageBase64 = stepResult.imageBase64;
        latestImageMimeType = stepResult.imageMimeType;
      }

      final filterMap = step['filter'] is Map
          ? Map<String, dynamic>.from(step['filter'] as Map)
          : null;
      final filteredText = _applyFilter(stepResult.content, filterMap);
      final silent = filterMap?['silent'] == true;

      final record = _PipelineStepRecord(
        id: stepId,
        toolName: toolName,
        content: filteredText,
        rawLength: stepResult.content.length,
        isError: stepResult.isError,
        silent: silent,
      );
      stepOutputs[stepId] = record;
      orderedRecords.add(record);

      env[stepId] = filteredText;
      env['last'] = filteredText;

      if (stepResult.isError) {
        hadAnyError = true;
        final continueOnError = step['continue_on_error'] == true;
        if (!continueOnError) {
          return ToolResult(
            toolCallId: toolCallId,
            content: _formatReport(orderedRecords, args['return_steps']),
            isError: true,
            imageBase64: latestImageBase64,
            imageMimeType: latestImageMimeType,
          );
        }
      }
    }

    return ToolResult(
      toolCallId: toolCallId,
      content: _formatReport(orderedRecords, args['return_steps']),
      isError: hadAnyError && orderedRecords.every((r) => r.isError || r.skipped),
      imageBase64: latestImageBase64,
      imageMimeType: latestImageMimeType,
    );
  }

  Object? _resolveValue(Object? value, Map<String, Object?> env) {
    if (value is String) {
      return _resolveString(value, env);
    }
    if (value is List) {
      return [for (final item in value) _resolveValue(item, env)];
    }
    if (value is Map) {
      if (value.length == 1 && value.containsKey('join')) {
        return _evalJoin(value['join'], env);
      }
      if (value.length == 1 && value.containsKey('concat')) {
        return _evalConcat(value['concat'], env);
      }
      return {
        for (final entry in value.entries)
          '${entry.key}': _resolveValue(entry.value, env),
      };
    }
    return value;
  }

  Object? _resolveString(String raw, Map<String, Object?> env) {
    if (raw.startsWith('@') && !raw.contains(RegExp(r'\s'))) {
      return _lookupRef(raw.substring(1), env);
    }
    if (!raw.contains('{{')) return raw;
    return raw.replaceAllMapped(RegExp(r'\{\{\s*([a-zA-Z0-9_.-]+)\s*\}\}'), (
      match,
    ) {
      final resolved = _lookupRef(match.group(1)!, env);
      return _stringify(resolved);
    });
  }

  Object? _lookupRef(String path, Map<String, Object?> env) {
    if (env.containsKey(path)) return env[path];
    final dot = path.indexOf('.');
    if (dot <= 0) return '@$path';
    final root = path.substring(0, dot);
    final member = path.substring(dot + 1);
    if (!env.containsKey(root)) return '@$path';
    final base = env[root];
    if (base is Map && base.containsKey(member)) {
      return base[member];
    }
    final text = _stringify(base);
    return switch (member) {
      'lines' => _nonEmptyLines(text),
      'first_line' => _nonEmptyLines(text).firstOrNull ?? '',
      'tags' => _extractTagsList(text).join(', '),
      'tags_list' => _extractTagsList(text),
      _ => '@$path',
    };
  }

  String _evalJoin(Object? spec, Map<String, Object?> env) {
    String sep = ', ';
    List<Object?> items = const [];
    if (spec is List && spec.isNotEmpty) {
      sep = _stringify(_resolveValue(spec.first, env));
      items = spec.skip(1).toList();
    } else if (spec is Map) {
      sep = _stringify(_resolveValue(spec['sep'] ?? ', ', env));
      final rawItems = spec['items'];
      if (rawItems is List) items = rawItems;
    }
    final flattened = <String>[];
    void collect(Object? item) {
      final resolved = _resolveValue(item, env);
      if (resolved is List) {
        for (final child in resolved) {
          collect(child);
        }
      } else if (resolved != null) {
        final s = _stringify(resolved).trim();
        if (s.isNotEmpty) flattened.add(s);
      }
    }

    for (final item in items) {
      collect(item);
    }
    return flattened.join(sep);
  }

  String _evalConcat(Object? spec, Map<String, Object?> env) {
    if (spec is! List) return _stringify(_resolveValue(spec, env));
    final buffer = StringBuffer();
    for (final item in spec) {
      final resolved = _resolveValue(item, env);
      if (resolved != null) buffer.write(_stringify(resolved));
    }
    return buffer.toString();
  }

  bool _evalCondition(Object? cond, Map<String, Object?> env) {
    if (cond is bool) return cond;
    if (cond is String) {
      final trimmed = cond.trim();
      final negate = trimmed.startsWith('!');
      final expr = negate ? trimmed.substring(1).trim() : trimmed;
      final resolved = _resolveValue(expr, env);
      final truthy = switch (resolved) {
        bool b => b,
        num n => n != 0,
        String s => s.trim().isNotEmpty && s.trim().toLowerCase() != 'false',
        List l => l.isNotEmpty,
        Map m => m.isNotEmpty,
        null => false,
        _ => true,
      };
      return negate ? !truthy : truthy;
    }
    return cond != null;
  }

  static String _stringify(Object? value) {
    return switch (value) {
      null => '',
      String s => s,
      List l => l.map(_stringify).where((s) => s.isNotEmpty).join(', '),
      Map m => jsonEncode(m),
      _ => '$value',
    };
  }

  static List<String> _nonEmptyLines(String text) => text
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();

  /// 从 Danbooru / 建议工具输出中提取纯净标签名列表
  static List<String> _extractTagsList(String text) {
    final tags = <String>[];
    final seen = <String>{};
    for (final rawLine in _nonEmptyLines(text)) {
      if (!rawLine.startsWith('- ')) continue;
      var body = rawLine.substring(2).trim();
      final cutIndices = [
        body.indexOf(' ('),
        body.indexOf(' ['),
        body.indexOf(' --'),
      ].where((idx) => idx >= 0);
      if (cutIndices.isNotEmpty) {
        final cut = cutIndices.reduce((a, b) => a < b ? a : b);
        body = body.substring(0, cut).trim();
      }
      if (body.isNotEmpty && seen.add(body)) {
        tags.add(body);
      }
    }
    if (tags.isNotEmpty) return tags;
    // 回退：逗号分隔格式
    for (final part in text.split(',')) {
      final clean = part.trim();
      if (clean.isNotEmpty && !clean.contains('\n') && seen.add(clean)) {
        tags.add(clean);
      }
    }
    return tags;
  }

  static String _applyFilter(String text, Map<String, dynamic>? filter) {
    if (filter == null || filter.isEmpty) return text;
    var current = text;

    if (filter['extract_tags'] == true) {
      final tags = _extractTagsList(current);
      if (tags.isNotEmpty) {
        current = tags.join(', ');
      }
    }

    final grep = (filter['grep'] as String?)?.trim();
    if (grep != null && grep.isNotEmpty) {
      RegExp? pattern;
      try {
        pattern = RegExp(grep, caseSensitive: false);
      } catch (_) {}
      final matched = _nonEmptyLines(current).where((line) {
        if (pattern != null) return pattern.hasMatch(line);
        return line.toLowerCase().contains(grep.toLowerCase());
      }).toList();
      current = matched.join('\n');
    }

    final maxLines = (filter['max_lines'] as num?)?.toInt();
    if (maxLines != null && maxLines > 0) {
      final lines = _nonEmptyLines(current);
      if (lines.length > maxLines) {
        current = '${lines.take(maxLines).join('\n')}\n…(共 ${lines.length} 行)';
      }
    }

    final maxChars = (filter['max_chars'] as num?)?.toInt();
    if (maxChars != null && maxChars > 0 && current.length > maxChars) {
      current = '${current.substring(0, maxChars)}…(已截断，原长 ${current.length})';
    }

    return current;
  }

  static String _formatAborted(List<_PipelineStepRecord> records) {
    final prefix = records.isEmpty
        ? ''
        : '${_formatReport(records, null)}\n';
    return '$prefix用户已中断，后续编排步骤未执行。';
  }

  static String _formatReport(
    List<_PipelineStepRecord> records,
    Object? rawReturnSteps,
  ) {
    if (records.isEmpty) return '编排未执行任何步骤。';
    Set<String>? selectedIds;
    if (rawReturnSteps is List && rawReturnSteps.isNotEmpty) {
      selectedIds = rawReturnSteps.map((e) => e.toString().trim()).toSet();
      if (selectedIds.remove('last')) {
        selectedIds.add(records.last.id);
      }
    }

    final buffer = StringBuffer();
    for (var i = 0; i < records.length; i++) {
      final r = records[i];
      final isLast = i == records.length - 1;
      if (r.skipped) {
        buffer.writeln('[${r.id}] ${r.toolName}: 已跳过');
        continue;
      }
      final includeDetail = selectedIds != null
          ? (selectedIds.contains(r.id) || r.isError)
          : (!r.silent || isLast || r.isError);
      if (!includeDetail) {
        buffer.writeln('[${r.id}] ${r.toolName}: 完成 (${r.rawLength} 字符)');
      } else {
        final header = r.isError
            ? '[${r.id}] ${r.toolName} (失败):'
            : '[${r.id}] ${r.toolName}:';
        buffer.writeln(header);
        buffer.writeln(r.content);
      }
    }
    return buffer.toString().trim();
  }
}

class _PipelineStepRecord {
  final String id;
  final String toolName;
  final String content;
  final int rawLength;
  final bool isError;
  final bool silent;
  final bool skipped;

  const _PipelineStepRecord({
    required this.id,
    required this.toolName,
    required this.content,
    this.rawLength = 0,
    required this.isError,
    this.silent = false,
    this.skipped = false,
  });
}
