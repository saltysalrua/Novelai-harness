import 'package:http/http.dart' as http;
import '../../../data/models/llm_cache_config.dart';
import 'endpoint_capability_cache.dart';
import 'google_interactions_provider.dart';
import 'llm_provider.dart';
import 'openai_provider.dart';

/// 根据配置端点协议装配具体的 [LlmProvider] 实现，避免业务层耦合协议分流细节。
class LlmProviderFactory {
  static bool isInteractionsEndpoint(String baseUrl) {
    final endpoint = baseUrl.trim();
    return endpoint.endsWith('/interactions') ||
        endpoint.endsWith('/interactions/');
  }

  static LlmProvider create({
    required String baseUrl,
    required String apiKey,
    required String model,
    bool reasoning = false,
    String? thinkingEffort,
    String? thinkingParamFormat,
    LlmCacheConfig cacheConfig = const LlmCacheConfig(),
    bool promptToolUse = false,
    bool streaming = true,
    http.Client? client,
    EndpointCapabilityCache? capabilityCache,
  }) {
    final endpoint = baseUrl.trim();
    if (isInteractionsEndpoint(endpoint)) {
      return GoogleInteractionsProvider(
        apiKey: apiKey,
        baseUrl: endpoint,
        modelId: model,
        reasoning: reasoning,
        thinkingEffort: thinkingEffort ?? 'medium',
        promptToolUse: promptToolUse,
        cacheConfig: cacheConfig,
        streaming: streaming,
        client: client,
      );
    }
    return OpenAiCompatibleProvider(
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      reasoning: reasoning,
      thinkingEffort: thinkingEffort,
      thinkingParamFormat: thinkingParamFormat,
      cacheConfig: cacheConfig,
      promptToolUse: promptToolUse,
      streaming: streaming,
      client: client,
      capabilityCache: capabilityCache,
    );
  }
}
