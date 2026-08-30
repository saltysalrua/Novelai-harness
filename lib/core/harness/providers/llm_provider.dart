import '../tools/agent_tool.dart';
import '../types.dart';

/// LLM 提供商通用接口
abstract class LlmProvider {
  /// 当前使用的模型 ID (用于会话记录元数据)
  String get modelId;

  /// 发起流式对话并生成 Harness 事件流。
  ///
  /// [promptCacheKey] 为会话级稳定缓存路由键 (可为空)：供应商支持时
  /// 用于把同一会话的请求路由到同一 KV Cache 分片 (OpenAI `prompt_cache_key`)。
  Stream<HarnessEvent> streamChat({
    required List<AgentMessage> messages,
    required List<AgentTool> tools,
    double temperature = 0.7,
    String? promptCacheKey,
  });
}
