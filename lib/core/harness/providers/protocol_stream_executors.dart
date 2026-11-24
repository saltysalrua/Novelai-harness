import 'dart:async';
import 'package:http/http.dart' as http;
import '../../../data/models/llm_cache_config.dart';
import '../tools/agent_tool.dart';
import '../types.dart';
import 'anthropic_messages.dart';
import 'endpoint_capability_cache.dart';
import 'google_interactions_provider.dart';
import 'openai_responses.dart';
import 'prompt_cache_policy.dart';
import 'prompt_tool_codec.dart';
import 'provider_http_transport.dart';

/// `POST /v1/messages`：Anthropic Messages 协议流式与非流式执行器。
class AnthropicMessagesExecutor {
  final String apiKey;
  final String model;
  final bool reasoning;
  final String? thinkingEffort;
  final LlmCacheConfig cacheConfig;
  final bool promptToolUse;
  final bool streaming;
  final http.Client client;
  final Duration requestStartupTimeout;
  final Duration streamIdleTimeout;

  const AnthropicMessagesExecutor({
    required this.apiKey,
    required this.model,
    required this.reasoning,
    required this.thinkingEffort,
    required this.cacheConfig,
    required this.promptToolUse,
    required this.streaming,
    required this.client,
    this.requestStartupTimeout = ProviderHttpTransport.requestStartupTimeout,
    this.streamIdleTimeout = ProviderHttpTransport.streamIdleTimeout,
  });

  Stream<HarnessEvent> execute({
    required String endpoint,
    required List<AgentMessage> messages,
    required List<AgentTool> tools,
    required double temperature,
    required PromptToolStreamParser? promptParser,
    String? promptCacheKey,
  }) async* {
    final requestBody = AnthropicMessages.buildRequestBody(
      model: model.trim(),
      messages: messages,
      tools: tools,
      temperature: temperature,
      reasoning: reasoning,
      thinkingEffort: thinkingEffort,
      promptToolUse: promptToolUse,
      stream: streaming,
    );
    final cachePolicy = PromptCachePolicy(
      config: cacheConfig,
      endpoint: Uri.parse(endpoint),
      model: model,
    );
    final cacheHeaders = cachePolicy.headers(promptCacheKey);
    // 只套用 Anthropic cache_control。OpenAI 的 prompt_cache_key 不是 Messages 字段。
    if (cachePolicy.mode == LlmCacheMode.anthropic &&
        requestBody['messages'] is List) {
      cachePolicy.apply(requestBody, promptCacheKey);
    }

    final abortTrigger = Completer<void>();
    final http.StreamedResponse streamedResponse;
    try {
      streamedResponse = await ProviderHttpTransport.sendJsonPost(
        client: client,
        endpoint: endpoint,
        apiKey: apiKey,
        requestBody: requestBody,
        cacheHeaders: cacheHeaders,
        timeout: requestStartupTimeout,
        abortTrigger: abortTrigger,
      );
    } catch (e) {
      yield ErrorEvent('网络请求异常: $e', transient: true);
      return;
    }

    if (streamedResponse.statusCode != 200) {
      yield await ProviderHttpTransport.readHttpErrorEvent(
        streamedResponse,
        timeout: requestStartupTimeout,
        abortTrigger: abortTrigger,
      );
      return;
    }

    final parser = AnthropicMessagesStreamParser();
    yield* ProviderHttpTransport.executeSseOrJsonProtocolStream(
      streamedResponse: streamedResponse,
      messages: messages,
      promptParser: promptParser,
      completionMarker: 'message_stop',
      prematureEndMessage: 'Anthropic 响应流提前结束，未执行工具调用。',
      streamIdleTimeout: streamIdleTimeout,
      abortTrigger: abortTrigger,
      onSseJson: (json, eventType) => parser.add(json, eventType: eventType),
      onSseFinish: parser.finish,
      parseNonSseJson: (json) {
        final completion = AnthropicMessages.parseResponse(json);
        return (
          error: completion.error,
          transientError: completion.transientError,
          reasoningRecords: completion.reasoningRecords,
          reasoning: completion.reasoning,
          thoughtSignatures: [
            for (final record in completion.reasoningRecords)
              if (record.signature != null && record.signature!.isNotEmpty)
                record.signature!,
          ],
          text: completion.text,
          toolCalls: completion.toolCalls,
          usage: completion.usage,
        );
      },
    );
  }
}

/// `POST /v1/responses`：OpenAI Responses 协议流式与非流式执行器。
class OpenAiResponsesExecutor {
  final String apiKey;
  final String model;
  final bool reasoning;
  final String? thinkingEffort;
  final LlmCacheConfig cacheConfig;
  final bool promptToolUse;
  final bool streaming;
  final http.Client client;
  final EndpointCapabilityCache capabilityCache;
  final bool isGoogleHost;
  final bool isGoogleOrGemini;
  final bool Function(String endpoint, String? effort) shouldOmitTemperature;
  final String Function(String effort) clampGeminiReasoningEffort;
  final Duration requestStartupTimeout;
  final Duration streamIdleTimeout;

  const OpenAiResponsesExecutor({
    required this.apiKey,
    required this.model,
    required this.reasoning,
    required this.thinkingEffort,
    required this.cacheConfig,
    required this.promptToolUse,
    required this.streaming,
    required this.client,
    required this.capabilityCache,
    required this.isGoogleHost,
    required this.isGoogleOrGemini,
    required this.shouldOmitTemperature,
    required this.clampGeminiReasoningEffort,
    this.requestStartupTimeout = ProviderHttpTransport.requestStartupTimeout,
    this.streamIdleTimeout = ProviderHttpTransport.streamIdleTimeout,
  });

  String? _responsesReasoningEffort() {
    if (!reasoning) return null;
    final effort = thinkingEffort?.trim();
    if (effort == null || effort.isEmpty) return null;
    final effective = isGoogleOrGemini
        ? clampGeminiReasoningEffort(effort)
        : effort;
    if (isGoogleOrGemini && effective == 'none') return null;
    return effective;
  }

  Stream<HarnessEvent> execute({
    required String endpoint,
    required List<AgentMessage> messages,
    required List<AgentTool> tools,
    required double temperature,
    required PromptToolStreamParser? promptParser,
    String? promptCacheKey,
  }) async* {
    // 先算出思考强度：非空时官方推理模型不接受 temperature。
    final effort = _responsesReasoningEffort();
    final requestBody = OpenAiResponses.buildRequestBody(
      model: isGoogleHost
          ? GoogleInteractionsProvider.normalizeModelId(model)
          : model.trim(),
      messages: messages,
      tools: tools,
      temperature: temperature,
      stream: streaming,
      reasoningEffort: effort,
      includeEncryptedReasoning: reasoning,
      includeTemperature: !shouldOmitTemperature(endpoint, effort),
      promptToolUse: promptToolUse,
    );
    // 该端点+模型曾拒绝 include 参数时不再附带（推理回放退化为明文/已存项）。
    if (capabilityCache.isEncryptedReasoningUnsupported(endpoint, model)) {
      requestBody.remove('include');
    }

    // 提示缓存：仅 openai 模式在 Responses 请求体上写 prompt_cache_key /
    // prompt_cache_retention；anthropic 模式的 apply 依赖 body['messages']。
    final cachePolicy = PromptCachePolicy(
      config: cacheConfig,
      endpoint: Uri.parse(endpoint),
      model: model,
    );
    final cacheHeaders = <String, String>{};
    if (cachePolicy.mode == LlmCacheMode.openai) {
      cachePolicy.apply(requestBody, promptCacheKey);
      cacheHeaders.addAll(cachePolicy.headers(promptCacheKey));
      for (final field in const [
        'prompt_cache_key',
        'prompt_cache_retention',
      ]) {
        if (capabilityCache.isCacheFieldUnsupported(endpoint, model, field)) {
          requestBody.remove(field);
        }
      }
    }

    final abortTrigger = Completer<void>();
    final http.StreamedResponse streamedResponse;
    final String? badRequestBody;
    try {
      final initialResponse = await ProviderHttpTransport.sendJsonPost(
        client: client,
        endpoint: endpoint,
        apiKey: apiKey,
        requestBody: requestBody,
        cacheHeaders: cacheHeaders,
        timeout: requestStartupTimeout,
        abortTrigger: abortTrigger,
      );
      final (response, errBody) =
          await ProviderHttpTransport.drainRejectedCacheFields(
            initialResponse: initialResponse,
            client: client,
            apiKey: apiKey,
            model: model,
            endpoint: endpoint,
            requestBody: requestBody,
            cacheHeaders: cacheHeaders,
            capabilityCache: capabilityCache,
            timeout: requestStartupTimeout,
            abortTrigger: abortTrigger,
          );
      streamedResponse = response;
      badRequestBody = errBody;
    } catch (e) {
      yield ErrorEvent('网络请求异常: $e', transient: true);
      return;
    }
    if (badRequestBody != null) {
      yield ErrorEvent('LLM API 响应错误 (HTTP 400): $badRequestBody');
      return;
    }

    if (streamedResponse.statusCode != 200) {
      yield await ProviderHttpTransport.readHttpErrorEvent(
        streamedResponse,
        timeout: requestStartupTimeout,
        abortTrigger: abortTrigger,
      );
      return;
    }

    final parser = OpenAiResponsesStreamParser();
    yield* ProviderHttpTransport.executeSseOrJsonProtocolStream(
      streamedResponse: streamedResponse,
      messages: messages,
      promptParser: promptParser,
      completionMarker: 'response.completed',
      prematureEndMessage: 'Responses 响应流提前结束，未执行工具调用。',
      streamIdleTimeout: streamIdleTimeout,
      abortTrigger: abortTrigger,
      onSseJson: (json, eventType) => parser.add(json, eventType: eventType),
      onSseFinish: parser.finish,
      parseNonSseJson: (json) {
        final completion = OpenAiResponses.parseResponse(json);
        return (
          error: completion.error,
          transientError: completion.transientError,
          reasoningRecords: completion.reasoningRecords,
          reasoning: completion.reasoning,
          thoughtSignatures: const <String>[],
          text: completion.text,
          toolCalls: completion.toolCalls,
          usage: completion.usage,
        );
      },
    );
  }
}
