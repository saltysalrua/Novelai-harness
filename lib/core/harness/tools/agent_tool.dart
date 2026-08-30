import 'dart:async';
import '../types.dart';

/// Agent 工具抽象基类
abstract class AgentTool {
  final String name;
  final String label;
  final String description;
  final Map<String, dynamic> parameters;
  final bool isBuiltin;

  const AgentTool({
    required this.name,
    required this.label,
    required this.description,
    required this.parameters,
    this.isBuiltin = true,
  });

  /// 执行工具逻辑
  Future<ToolResult> execute(String toolCallId, Map<String, dynamic> args);

  /// 转换为 OpenAI Function Definition 格式
  Map<String, dynamic> toOpenAiFunction() {
    return {
      'type': 'function',
      'function': {
        'name': name,
        'description': description,
        'parameters': parameters,
      },
    };
  }
}

/// 自定义动态扩展工具 (Pi 风格，支持模板插值与提示词扩展)
class CustomAgentTool extends AgentTool {
  final String outputTemplate;

  CustomAgentTool({
    required super.name,
    required super.label,
    required super.description,
    required super.parameters,
    this.outputTemplate = '',
  }) : super(isBuiltin: false);

  @override
  Future<ToolResult> execute(
      String toolCallId, Map<String, dynamic> args) async {
    if (outputTemplate.isNotEmpty) {
      String result = outputTemplate;
      args.forEach((k, v) {
        result = result.replaceAll('{{$k}}', '$v');
      });
      return ToolResult(toolCallId: toolCallId, content: result);
    }
    return ToolResult(
      toolCallId: toolCallId,
      content: '自定义工具 [$label ($name)] 执行成功，入参: $args',
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'label': label,
        'description': description,
        'parameters': parameters,
        'outputTemplate': outputTemplate,
      };

  factory CustomAgentTool.fromJson(Map<String, dynamic> json) =>
      CustomAgentTool(
        name: json['name'] as String? ?? 'custom_tool',
        label: json['label'] as String? ?? '自定义工具',
        description: json['description'] as String? ?? '',
        parameters: json['parameters'] is Map<String, dynamic>
            ? json['parameters'] as Map<String, dynamic>
            : const {
                'type': 'object',
                'properties': {},
              },
        outputTemplate: json['outputTemplate'] as String? ?? '',
      );
}

/// 工具注册中心 (动态管理内置 + 用户扩展的所有工具)
class ToolRegistry {
  final Map<String, AgentTool> _tools = {};

  void register(AgentTool tool) {
    _tools[tool.name] = tool;
  }

  void registerAll(List<AgentTool> tools) {
    for (final tool in tools) {
      register(tool);
    }
  }

  void clear() {
    _tools.clear();
  }

  bool unregister(String name) {
    final target = _tools[name];
    if (target != null && !target.isBuiltin) {
      _tools.remove(name);
      return true;
    }
    return false;
  }

  AgentTool? get(String name) => _tools[name];

  List<AgentTool> getAll() => List.unmodifiable(_tools.values);

  List<CustomAgentTool> getCustomTools() =>
      _tools.values.whereType<CustomAgentTool>().toList();

  List<String> get names => _tools.keys.toList();

  List<Map<String, dynamic>> toOpenAiFunctionDefinitions() {
    return _tools.values.map((t) => t.toOpenAiFunction()).toList();
  }
}
