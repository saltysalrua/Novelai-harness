import '../types.dart';

/// Agent 工具抽象基类
abstract class AgentTool {
  final String name;
  final String label;
  final String description;
  final Map<String, dynamic> parameters;

  const AgentTool({
    required this.name,
    required this.label,
    required this.description,
    required this.parameters,
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

/// 工具注册中心
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

  AgentTool? get(String name) => _tools[name];

  List<AgentTool> getAll() => _tools.values.toList();

  List<Map<String, dynamic>> toOpenAiFunctionDefinitions() {
    return _tools.values.map((t) => t.toOpenAiFunction()).toList();
  }
}
