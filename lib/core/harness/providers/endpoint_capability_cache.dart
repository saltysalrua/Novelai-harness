/// 端点能力降级缓存：隔离记录各端点与模型组合拒绝的缓存字段与加密推理字段，
/// 支持注入独立实例（便于测试隔离），默认使用进程内共享缓存 [shared]。
class EndpointCapabilityCache {
  static final EndpointCapabilityCache shared = EndpointCapabilityCache();

  final Set<(String, String, String)> _unsupportedCacheFields = {};
  final Set<(String, String)> _unsupportedEncryptedReasoning = {};

  bool isCacheFieldUnsupported(String endpoint, String model, String field) =>
      _unsupportedCacheFields.contains((endpoint, model.trim(), field));

  void markCacheFieldUnsupported(String endpoint, String model, String field) {
    _unsupportedCacheFields.add((endpoint, model.trim(), field));
  }

  bool isEncryptedReasoningUnsupported(String endpoint, String model) =>
      _unsupportedEncryptedReasoning.contains((endpoint, model.trim()));

  void markEncryptedReasoningUnsupported(String endpoint, String model) {
    _unsupportedEncryptedReasoning.add((endpoint, model.trim()));
  }

  void clear() {
    _unsupportedCacheFields.clear();
    _unsupportedEncryptedReasoning.clear();
  }
}
