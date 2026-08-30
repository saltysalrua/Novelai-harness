import '../tools/agent_tool.dart';
import '../types.dart';

/// LLM 提供商通用接口
abstract class LlmProvider {
  /// 当前使用的模型 ID (用于会话记录元数据)
  String get modelId;

  /// 发起流式对话并生成 Harness 事件流
  Stream<HarnessEvent> streamChat({
    required List<AgentMessage> messages,
    required List<AgentTool> tools,
    double temperature = 0.7,
  });
}
