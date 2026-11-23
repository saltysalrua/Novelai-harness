import 'dart:convert';
import '../types.dart';
import 'agent_tool.dart';

/// 按需懒加载工具参数 Schema，减少首轮及每轮请求的工具定义 Token 占用。
///
/// 在精简工具表面（Compact Tool Surface）模式下，二级工具以单行索引呈现在
/// 系统提示词中；模型既可直接通过 `run_pipeline` 调度，也可调用本工具查看
/// 精确参数 Schema。仅返回当前预设白名单允许的工具。
class DescribeToolsTool extends AgentTool {
  final ToolRegistry registry;
  final bool Function(String toolName)? isToolAllowed;

  DescribeToolsTool({
    required this.registry,
    this.isToolAllowed,
  }) : super(
         name: 'describe_tools',
         label: '查看工具参数',
         description:
             '按需查看未在顶层展开的二级工具与已连接 MCP 工具（mcp_*）的完整参数 Schema。传入 names 数组一次查询多个，或用 query 关键词检索。',
         parameters: const {
           'type': 'object',
           'properties': {
             'names': {
               'type': 'array',
               'items': {'type': 'string'},
               'description': '要查询的工具名称列表',
             },
             'query': {
               'type': 'string',
               'description': '按名称或描述关键词过滤（未传 names 时使用）',
             },
           },
         },
       );

  @override
  Future<ToolResult> execute(
    String toolCallId,
    Map<String, dynamic> args,
  ) async {
    final allowed = registry.getAll().where(
      (tool) => isToolAllowed == null || isToolAllowed!(tool.name),
    );
    final rawNames = args['names'];
    final requestedNames = rawNames is List
        ? rawNames
              .map((e) => e.toString().trim())
              .where((s) => s.isNotEmpty)
              .toSet()
        : <String>{};
    final query = (args['query'] as String?)?.trim().toLowerCase() ?? '';

    final matched = <AgentTool>[];
    final missing = <String>[];

    if (requestedNames.isNotEmpty) {
      final byName = {for (final t in allowed) t.name: t};
      for (final req in requestedNames) {
        final tool = byName[req];
        if (tool != null) {
          matched.add(tool);
        } else {
          missing.add(req);
        }
      }
    } else if (query.isNotEmpty) {
      for (final tool in allowed) {
        final haystack =
            '${tool.name} ${tool.label} ${tool.description}'.toLowerCase();
        if (haystack.contains(query)) {
          matched.add(tool);
        }
      }
    } else {
      matched.addAll(allowed);
    }

    if (matched.isEmpty) {
      return ToolResult(
        toolCallId: toolCallId,
        content: missing.isNotEmpty
            ? '未找到或当前预设未启用工具：${missing.join(', ')}'
            : '未匹配到符合条件的可用工具。',
        isError: missing.isNotEmpty,
      );
    }

    final payload = [
      for (final tool in matched)
        {
          'name': tool.name,
          'description': tool.description,
          'parameters': tool.parameters,
        },
    ];
    final buffer = StringBuffer(jsonEncode(payload));
    if (missing.isNotEmpty) {
      buffer.write('\n未找到或未启用的工具：${missing.join(', ')}');
    }
    return ToolResult(toolCallId: toolCallId, content: buffer.toString());
  }
}
