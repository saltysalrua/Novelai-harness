import '../tools/agent_tool.dart';
import '../types.dart';

/// LLM 提供商通用接口
abstract class LlmProvider {
  /// 发起流式对话并生成 Harness 事件流
  Stream<HarnessEvent> streamChat({
    required List<AgentMessage> messages,
    required List<AgentTool> tools,
    double temperature = 0.7,
  });
}
