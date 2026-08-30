import 'types.dart';

/// 会话记录器抽象接口。
///
/// 由数据层实现 (SessionLogService)，按 Pi 官方会话格式将对话历史
/// 落盘为 JSONL。核心 Harness 只依赖此抽象，不感知任何 IO 细节。
abstract class SessionRecorder {
  /// 当前活跃会话的稳定标识。
  ///
  /// 同一会话内保持不变 (跨重启续接时沿用旧 ID)，/clear 后更换。
  /// 核心层将其作为 OpenAI 兼容端点的 `prompt_cache_key` 传给 LLM，
  /// 帮助供应商把同一会话的请求路由到同一 KV Cache 分片，提升缓存命中。
  String? get sessionId => null;

  /// 记录一条对话消息 (user / assistant / toolResult)。
  ///
  /// [provider] 与 [model] 仅对 assistant 消息有意义，用于 Pi 格式的
  /// AssistantMessage 元数据字段。
  void recordMessage(AgentMessage message, {String? provider, String? model});

  /// 记录一次模型切换 (对应 Pi 的 model_change 条目)。
  void recordModelChange(String provider, String modelId);

  /// 记录一次思考强度切换 (对应 Pi 的 thinking_level_change 条目)。
  void recordThinkingLevelChange(String level);

  /// 结束当前会话文件，开启新的空会话 (/clear 时调用)。
  void startNewSession();

  /// 将会话记录回溯截断至指定索引处 (保留前 [keepCount] 条消息)。
  void rewindToMessageCount(int keepCount);
}
