import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../tools/agent_tool.dart';
import '../types.dart';
import 'endpoint_capability_cache.dart';
import 'google_interactions_provider.dart';
import 'llm_provider.dart';
import 'llm_provider_factory.dart';
import 'prompt_cache_policy.dart';
import 'prompt_tool_codec.dart';
import 'protocol_stream_executors.dart';
import 'provider_http_transport.dart';
import 'tool_call_ids.dart';
import '../../../data/models/llm_cache_config.dart';

/// OpenAI 兼容格式提供商 (兼容 DeepSeek, Qwen, Moonshot, OpenAI, Ollama, LocalAI 等)
class OpenAiCompatibleProvider implements LlmProvider, LlmRequestOverhead {
  static String? clampPromptCacheKey(String? key) =>
      PromptCachePolicy.clampKey(key);

  final String baseUrl;
  final String apiKey;
  final String model;
  final bool reasoning;
  final String? thinkingEffort;

  /// 思考参数请求格式 id (null/'auto' = 按端点域名自动识别)，
  /// 对齐 pi openai-completions 的 thinkingFormat 兼容矩阵。
  final String? thinkingParamFormat;
  final http.Client _client;
  final bool _ownsClient;
  final EndpointCapabilityCache _capabilityCache;
  final LlmCacheConfig cacheConfig;

  /// 纯聊天渠道兼容模式：提示词声明工具，正文解析调用。
  final bool promptToolUse;

  /// 关闭后发送非流式请求，并一次性解析完整响应。
  final bool streaming;

  /// 首包响应头 / 非流式完整响应超时上限。
  final Duration requestStartupTimeout;

  /// SSE 流式空闲超时上限。
  final Duration streamIdleTimeout;

  OpenAiCompatibleProvider({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.reasoning = false,
    this.thinkingEffort,
    this.thinkingParamFormat,
    this.cacheConfig = const LlmCacheConfig(),
    this.promptToolUse = false,
    this.streaming = true,
    this.requestStartupTimeout = ProviderHttpTransport.requestStartupTimeout,
    this.streamIdleTimeout = ProviderHttpTransport.streamIdleTimeout,
    http.Client? client,
    EndpointCapabilityCache? capabilityCache,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _capabilityCache = capabilityCache ?? EndpointCapabilityCache.shared;

  @override
  void close() {
    if (_ownsClient) _client.close();
  }

  @override
  String get modelId => model;

  @override
  String get requestProtocolPrompt =>
      promptToolUse ? PromptToolCodec.instructions : '';

  /// Ollama's local OpenAI-compatible endpoint does not require credentials.
  /// Keep the exception exact so an empty key never enables a remote endpoint.
  static bool acceptsEmptyApiKey(String endpoint) {
    final uri = Uri.tryParse(endpoint.trim());
    if (uri == null ||
        uri.scheme != 'http' ||
        uri.port != 11434 ||
        uri.path != '/v1/chat/completions' ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.userInfo.isNotEmpty) {
      return false;
    }
    return switch (uri.host.toLowerCase()) {
      'localhost' || '127.0.0.1' || '::1' => true,
      _ => false,
    };
  }

  String get _normalizedModelLower =>
      model.trim().toLowerCase().replaceFirst(RegExp(r'^models/'), '');

  bool get _isGeminiModel {
    final lower = _normalizedModelLower;
    final bare = lower.split('/').last;
    return bare.startsWith('gemini-') ||
        RegExp(r'(^|[/:\[\]\s_-])gemini-').hasMatch(lower);
  }

  static bool _isSafetyFinishReason(String? reason) {
    final lower = reason?.trim().toLowerCase();
    if (lower == null || lower.isEmpty) return false;
    return const {
      'content_filter',
      'safety',
      'prohibited_content',
      'recitation',
      'blocklist',
      'spii',
    }.contains(lower);
  }

  bool get _isGoogleHost =>
      Uri.tryParse(baseUrl.trim())?.host == 'generativelanguage.googleapis.com';

  bool get _isGoogleOrGemini => _isGoogleHost || _isGeminiModel;

  /// Gemini 2.5 Flash / Flash-Lite 允许通过 `reasoning_effort: "none"` 关闭思考；
  /// Gemini 2.5 Pro、Gemini 3 系列与 Gemini 4 Argon 思考不可关闭，发送 `"none"` 会报 400。
  bool _isGemini25FlashChatEndpoint() {
    final uri = Uri.tryParse(baseUrl.trim());
    return uri?.host == 'generativelanguage.googleapis.com' &&
        uri?.path.endsWith('/chat/completions') == true &&
        _normalizedModelLower.startsWith('gemini-2.5-flash') &&
        !_normalizedModelLower.contains('image');
  }

  static String _clampGeminiReasoningEffort(String effort) {
    return switch (effort) {
      'xhigh' || 'max' => 'high',
      _ => effort,
    };
  }

  bool _shouldOmitTemperature(String endpoint) {
    final uri = Uri.tryParse(endpoint);
    return uri?.scheme == 'https' &&
        uri?.host == 'api.anthropic.com' &&
        uri?.path == '/v1/chat/completions' &&
        model.trim() == 'claude-sonnet-5';
  }

  /// 判定 Responses 请求是否应省略 temperature：
  /// 官方限制端点、开启思考、或 o1/o3/o4/gpt-5 推理模型均不接受 temperature。
  bool _shouldOmitResponsesTemperature(
    String endpoint,
    String? reasoningEffort,
  ) {
    if (_shouldOmitTemperature(endpoint)) return true;
    if (reasoningEffort != null && reasoningEffort.trim().isNotEmpty) {
      return true;
    }
    final id = model.trim().toLowerCase();
    final bare = id.replaceAll('models/', '').replaceAll('openai/', '');
    return bare.startsWith('o1') ||
        bare.startsWith('o3') ||
        bare.startsWith('o4') ||
        bare.startsWith('gpt-5');
  }

  /// 判定 HTTP 状态码是否为瞬态可重试错误 (请求超时 / 频控 / 服务端临时故障)
  static bool isTransientStatus(int code) =>
      ProviderHttpTransport.isTransientStatus(code);

  /// 解析实际生效的思考参数格式 (显式配置优先，auto 按端点域名识别)
  String get resolvedThinkingFormat {
    final configured = thinkingParamFormat?.trim();
    if (configured != null && configured.isNotEmpty && configured != 'auto') {
      return configured;
    }
    final url = baseUrl.toLowerCase();
    final host = Uri.tryParse(baseUrl.trim())?.host.toLowerCase();
    if (url.contains('openrouter.ai')) return 'openrouter';
    if (host == 'api.deepseek.com') return 'deepseek';
    if (url.contains('dashscope') || url.contains('aliyuncs')) {
      return 'qwen';
    }
    if (url.contains('z.ai') ||
        url.contains('zhipu') ||
        url.contains('bigmodel')) {
      return 'zai';
    }
    if (url.contains('together.ai')) return 'together';
    return 'openai';
  }

  /// DeepSeek 的工具请求要求完整回传历史 assistant 思考；
  /// Gemini 3 / Gemini 4 Argon 的 OpenAI 兼容端点要求多轮工具调用在首个 tool_call
  /// 上携带 `extra_content.google.thought_signature` (若历史无签名则回传官方跳过标记)。
  Map<String, dynamic> _serializeMessage(
    AgentMessage message, {
    required bool replayDeepSeekReasoning,
  }) {
    final json = message.toOpenAiJson();
    if (replayDeepSeekReasoning &&
        message.role == AgentRole.assistant &&
        message.thoughts.isNotEmpty) {
      json['reasoning_content'] = message.thoughts;
    }
    if (_isGoogleOrGemini &&
        message.role == AgentRole.assistant &&
        json['tool_calls'] is List) {
      final toolCallsList = json['tool_calls'] as List<dynamic>;
      if (toolCallsList.isNotEmpty &&
          toolCallsList.first is Map<String, dynamic>) {
        final hasSignature = toolCallsList.any(
          (tc) =>
              tc is Map &&
              tc['extra_content'] is Map &&
              (tc['extra_content'] as Map)['google'] is Map &&
              ((tc['extra_content'] as Map)['google']
                      as Map)['thought_signature']
                  is String,
        );
        if (!hasSignature) {
          final firstTc = Map<String, dynamic>.from(
            toolCallsList.first as Map<String, dynamic>,
          );
          final fallbackSig =
              (message.thoughtSignature != null &&
                  message.thoughtSignature!.isNotEmpty)
              ? message.thoughtSignature!
              : 'skip_thought_signature_validator';
          firstTc['extra_content'] = {
            'google': {'thought_signature': fallbackSig},
          };
          toolCallsList[0] = firstTc;
        }
      }
    }
    return json;
  }

  /// 对齐 pi：tool 角色只回传文本；连续工具结果全部配对后，
  /// 再以 user 多模态消息附图，避免兼容网关丢弃 tool 里的 image_url。
  List<Map<String, dynamic>> _serializeMessages(
    List<AgentMessage> messages, {
    required bool replayDeepSeekReasoning,
  }) {
    final result = <Map<String, dynamic>>[];
    final imageBlocks = <Map<String, dynamic>>[];
    void flushToolImages() {
      if (imageBlocks.isEmpty) return;
      result.add({
        'role': 'user',
        'content': [
          {'type': 'text', 'text': '以下是前面工具结果附带的图片，请直接查看。'},
          ...imageBlocks,
        ],
      });
      imageBlocks.clear();
    }

    for (final message in messages) {
      if (message.role != AgentRole.tool) flushToolImages();
      final json = _serializeMessage(
        message,
        replayDeepSeekReasoning: replayDeepSeekReasoning,
      );
      if (message.role == AgentRole.tool && message.hasVisionImages) {
        json['content'] = message.content.isEmpty
            ? '图片见随后的附件。'
            : message.content;
        imageBlocks.addAll([
          {
            'type': 'text',
            'text': jsonEncode({
              'tool_name': message.toolName,
              'tool_call_id': message.toolCallId,
            }),
          },
          {
            'type': 'image_url',
            'image_url': {
              'url':
                  'data:${message.imageMimeType};base64,${message.imageBase64}',
            },
          },
        ]);
      }
      result.add(json);
    }
    flushToolImages();
    return result;
  }

  /// 按格式写入思考开关参数 (对齐 pi openai-completions 的 thinkingFormat 分支):
  /// 不同供应商用不同字段开关思维链，格式不匹配时思考会被上游静默丢弃；
  /// 部分格式 (Qwen / DeepSeek / Z.ai) 关闭思考也需显式发送 disabled。
  void _applyThinkingParams(Map<String, dynamic> body) {
    final effort = thinkingEffort?.trim();
    // 模型不具备思考能力时不发送任何思考参数
    if (effort == null || effort.isEmpty) return;
    final thinkingOn = reasoning;
    final effectiveEffort = _isGoogleOrGemini
        ? _clampGeminiReasoningEffort(effort)
        : effort;
    switch (resolvedThinkingFormat) {
      case 'deepseek':
        body['thinking'] = {'type': thinkingOn ? 'enabled' : 'disabled'};
        if (thinkingOn) body['reasoning_effort'] = effectiveEffort;
      case 'qwen':
        body['enable_thinking'] = thinkingOn;
        if (thinkingOn) body['reasoning_effort'] = effectiveEffort;
      case 'qwen_chat_template':
        body['chat_template_kwargs'] = {
          'enable_thinking': thinkingOn,
          'preserve_thinking': true,
        };
      case 'zai':
        body['thinking'] = thinkingOn
            ? {'type': 'enabled', 'clear_thinking': false}
            : {'type': 'disabled'};
        if (thinkingOn) body['reasoning_effort'] = effectiveEffort;
      case 'openrouter':
        // OpenRouter 用嵌套 reasoning 对象归一化各上游的思考开关；
        // Gemini 2.5 Pro / Gemini 3 / Gemini 4 Argon 不支持关闭思考，不发 none
        if (thinkingOn) {
          body['reasoning'] = {
            'effort': effectiveEffort == 'none' ? 'low' : effectiveEffort,
          };
        } else if (!_isGeminiModel ||
            _normalizedModelLower.startsWith('gemini-2.5-flash')) {
          body['reasoning'] = {'effort': 'none'};
        }
      case 'together':
        body['reasoning'] = {'enabled': thinkingOn};
        if (thinkingOn) body['reasoning_effort'] = effectiveEffort;
      default:
        // OpenAI 风格: 开思考时发送 reasoning_effort，关闭时不发送
        if (thinkingOn) {
          if (_isGoogleOrGemini && effectiveEffort == 'none') {
            if (_isGemini25FlashChatEndpoint()) {
              body['reasoning_effort'] = 'none';
            }
          } else {
            body['reasoning_effort'] = effectiveEffort;
          }
        } else if (effort == 'none' && _isGemini25FlashChatEndpoint()) {
          // Gemini 2.5 Flash distinguishes an omitted provider default from
          // the explicit none value that disables thinking.
          body['reasoning_effort'] = 'none';
        }
    }
  }

  static String? _extractToolCallThoughtSignature(dynamic tc) {
    if (tc is! Map) return null;
    final direct = tc['thought_signature'];
    if (direct is String && direct.isNotEmpty) return direct;
    final extra = tc['extra_content'];
    if (extra is Map) {
      final google = extra['google'];
      if (google is Map) {
        final sig = google['thought_signature'];
        if (sig is String && sig.isNotEmpty) return sig;
      }
    }
    return null;
  }

  /// 内嵌思考标签 (QwQ / Qwen3 等模型把思考过程直接写进 content 流)
  static const String _openThinkTag = '<think>';
  static const String _closeThinkTag = '</think>';

  /// 返回 [s] 尾部与 [tag] 前缀重叠的最长长度 (0 .. tag.length-1)，
  /// 用于把被流式拆分的标签片段缓冲到下一个 chunk 再判定
  static int _tailTagOverlap(String s, String tag) {
    final maxLen = s.length < tag.length ? s.length : tag.length - 1;
    for (var len = maxLen; len > 0; len--) {
      if (s.endsWith(tag.substring(0, len))) return len;
    }
    return 0;
  }

  @override
  Stream<HarnessEvent> streamChat({
    required List<AgentMessage> messages,
    required List<AgentTool> tools,
    double temperature = 0.7,
    String? promptCacheKey,
  }) async* {
    String endpoint = baseUrl.trim();
    if (LlmProviderFactory.isInteractionsEndpoint(endpoint)) {
      final interactionsProvider = GoogleInteractionsProvider(
        apiKey: apiKey,
        baseUrl: endpoint,
        modelId: model,
        reasoning: reasoning,
        thinkingEffort: thinkingEffort ?? 'medium',
        promptToolUse: promptToolUse,
        cacheConfig: cacheConfig,
        streaming: streaming,
        requestStartupTimeout: requestStartupTimeout,
        streamIdleTimeout: streamIdleTimeout,
        client: _client,
      );
      yield* interactionsProvider.streamChat(
        messages: messages,
        tools: tools,
        temperature: temperature,
        promptCacheKey: promptCacheKey,
      );
      return;
    }

    if (!endpoint.endsWith('/chat/completions') &&
        !endpoint.endsWith('/responses') &&
        !endpoint.endsWith('/messages')) {
      if (endpoint.endsWith('/')) {
        endpoint = '${endpoint}chat/completions';
      } else {
        endpoint = '$endpoint/chat/completions';
      }
    }

    if (apiKey.trim().isEmpty && !acceptsEmptyApiKey(endpoint)) {
      yield const ErrorEvent(
        '未配置 LLM API Key，请先在右上角设置中填写。',
        code: HarnessErrorCode.apiKeyMissing,
      );
      return;
    }

    final normalizedMessages = normalizeToolCallIds(messages);
    final promptParser = promptToolUse ? PromptToolStreamParser(tools) : null;
    if (endpoint.endsWith('/responses')) {
      yield* OpenAiResponsesExecutor(
        apiKey: apiKey,
        model: model,
        reasoning: reasoning,
        thinkingEffort: thinkingEffort,
        cacheConfig: cacheConfig,
        promptToolUse: promptToolUse,
        streaming: streaming,
        client: _client,
        capabilityCache: _capabilityCache,
        isGoogleHost: _isGoogleHost,
        isGoogleOrGemini: _isGoogleOrGemini,
        shouldOmitTemperature: _shouldOmitResponsesTemperature,
        clampGeminiReasoningEffort: _clampGeminiReasoningEffort,
        requestStartupTimeout: requestStartupTimeout,
        streamIdleTimeout: streamIdleTimeout,
      ).execute(
        endpoint: endpoint,
        messages: normalizedMessages,
        tools: tools,
        temperature: temperature,
        promptParser: promptParser,
        promptCacheKey: promptCacheKey,
      );
      return;
    }
    if (endpoint.endsWith('/messages')) {
      yield* AnthropicMessagesExecutor(
        apiKey: apiKey,
        model: model,
        reasoning: reasoning,
        thinkingEffort: thinkingEffort,
        cacheConfig: cacheConfig,
        promptToolUse: promptToolUse,
        streaming: streaming,
        client: _client,
        requestStartupTimeout: requestStartupTimeout,
        streamIdleTimeout: streamIdleTimeout,
      ).execute(
        endpoint: endpoint,
        messages: normalizedMessages,
        tools: tools,
        temperature: temperature,
        promptParser: promptParser,
        promptCacheKey: promptCacheKey,
      );
      return;
    }
    final replayDeepSeekReasoning =
        tools.isNotEmpty && resolvedThinkingFormat == 'deepseek';
    final requestBody = <String, dynamic>{
      'model': _isGoogleHost
          ? GoogleInteractionsProvider.normalizeModelId(model)
          : model.trim(),
      'messages': promptToolUse
          ? PromptToolCodec.serialize(normalizedMessages, tools)
          : _serializeMessages(
              normalizedMessages,
              replayDeepSeekReasoning: replayDeepSeekReasoning,
            ),
      'stream': streaming,
      'temperature': temperature,
    };
    if (_shouldOmitTemperature(endpoint)) {
      requestBody.remove('temperature');
    }

    // 思考参数按供应商兼容矩阵写入 (格式不匹配时思考会被上游静默丢弃)
    _applyThinkingParams(requestBody);

    if (tools.isNotEmpty && !promptToolUse) {
      requestBody['tools'] = tools.map((t) => t.toOpenAiFunction()).toList();
      // DeepSeek 带工具时默认 auto；省略可兼容不同版本的思考模式。
      if (resolvedThinkingFormat != 'deepseek') {
        requestBody['tool_choice'] = 'auto';
      }
    }

    final cachePolicy = PromptCachePolicy(
      config: cacheConfig,
      endpoint: Uri.parse(endpoint),
      model: model,
    );
    final cacheHeaders = <String, String>{};
    if (endpoint.endsWith('/chat/completions')) {
      if (streaming) {
        requestBody['stream_options'] = {'include_usage': true};
      }
      cachePolicy.apply(requestBody, promptCacheKey);
      cacheHeaders.addAll(cachePolicy.headers(promptCacheKey));
      for (final field in const [
        'prompt_cache_key',
        'prompt_cache_retention',
      ]) {
        if (_capabilityCache.isCacheFieldUnsupported(endpoint, model, field)) {
          requestBody.remove(field);
        }
      }
    }

    final abortTrigger = Completer<void>();
    http.StreamedResponse streamedResponse;
    String? badRequestBody;
    try {
      final initialResponse = await ProviderHttpTransport.sendJsonPost(
        client: _client,
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
            client: _client,
            apiKey: apiKey,
            model: model,
            endpoint: endpoint,
            requestBody: requestBody,
            cacheHeaders: cacheHeaders,
            capabilityCache: _capabilityCache,
            timeout: requestStartupTimeout,
            abortTrigger: abortTrigger,
          );
      streamedResponse = response;
      badRequestBody = errBody;
    } catch (e) {
      // 连接失败 / 超时 / TLS 握手中断等网络层异常均为瞬态
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

    if (!streaming) {
      final String raw;
      try {
        raw = await ProviderHttpTransport.readResponseText(
          streamedResponse,
          timeout: requestStartupTimeout,
          abortTrigger: abortTrigger,
        );
      } catch (e) {
        yield ErrorEvent('网络请求异常: $e', transient: true);
        return;
      }
      yield* _emitNonStreamingChat(
        raw,
        promptParser: promptParser,
        messages: normalizedMessages,
      );
      return;
    }

    // 累加工具调用片段
    final Map<int, Map<String, dynamic>> toolCallsAccumulator = {};
    bool inThinkTag = false;
    String pendingTagBuffer = '';
    bool streamCompleted = false;
    String? finishReason;
    bool emittedContent = false;
    bool emittedThoughts = false;
    final StringBuffer refusalBuffer = StringBuffer();
    FormatException? promptParseError;

    // 格式错误后仍消费 SSE 尾部，以保留真实 usage；任何调用都不提交。
    List<ContentDeltaEvent> contentEvents(String text) {
      if (promptParseError != null) return const [];
      try {
        final events = promptParser?.add(text) ?? [ContentDeltaEvent(text)];
        if (events.isNotEmpty) emittedContent = true;
        return events;
      } on FormatException catch (error) {
        promptParseError = error;
        return const [];
      }
    }

    // 流式 usage 快照: 部分 newapi 系网关会在每个 SSE chunk 都回传全量累计
    // usage，若逐 chunk 上报会让账本按 chunk 数重复记账 (input 虚增数倍)。
    // 对齐 pi 的 parseChunkUsage 覆盖语义: 逐 chunk 覆盖 (last-wins)，
    // 整条流结束后只发一次 UsageEvent。
    TokenUsage? latestUsage;

    try {
      final lineStream = streamedResponse.stream
          .timeout(streamIdleTimeout)
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter());

      await for (final line in lineStream) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith(':')) continue;
        if (!trimmed.startsWith('data:')) continue;

        final data = trimmed.substring(5).trim();
        if (data == '[DONE]') {
          streamCompleted = true;
          break;
        }

        Map<String, dynamic> json;
        try {
          json = jsonDecode(data) as Map<String, dynamic>;
        } catch (_) {
          continue;
        }

        final choices = json['choices'] as List<dynamic>?;

        // usage chunk (include_usage 时最后一个 chunk 的 choices 为空)
        final firstChoice = choices != null && choices.isNotEmpty
            ? choices.first
            : null;
        if (firstChoice is Map && firstChoice['finish_reason'] is String) {
          finishReason = firstChoice['finish_reason'] as String;
          streamCompleted = true;
        }
        final usageJson = json['usage'] is Map
            ? json['usage']
            : firstChoice is Map
            ? firstChoice['usage']
            : null;
        if (usageJson is Map<String, dynamic>) {
          final usage = TokenUsage.fromOpenAiJson(usageJson);
          if (usage.total > 0) {
            latestUsage = usage;
          }
        }

        if (choices == null || choices.isEmpty) continue;

        final delta = choices[0]['delta'] as Map<String, dynamic>?;
        if (delta == null) continue;

        final deltaSig = _extractToolCallThoughtSignature(delta);
        if (deltaSig != null) {
          yield ThoughtSignatureEvent(deltaSig);
        }

        // 1. 原生思考流字段 (优先级短路，对齐 pi 的 openai-completions 实现):
        //    reasoning_content (llama.cpp / DeepSeek-R1 / Qwen) -> reasoning
        //    (OpenRouter 及多数兼容网关) -> reasoning_text。
        //    只取第一个非空字段，避免个别网关双字段回传同样内容导致思考重复。
        for (final key in const [
          'reasoning_content',
          'reasoning',
          'reasoning_text',
        ]) {
          final raw = delta[key];
          if (raw is String && raw.isNotEmpty) {
            emittedThoughts = true;
            yield ThoughtDeltaEvent(raw);
            break;
          }
        }

        // 2. 处理标准 content (内嵌思考标签容错: 标签可能被流式拆分到多个 chunk)
        final deltaRefusal = delta['refusal'];
        if (deltaRefusal is String && deltaRefusal.isNotEmpty) {
          refusalBuffer.write(deltaRefusal);
        }
        if (delta.containsKey('content') && delta['content'] != null) {
          final contentDelta = delta['content'] as String;
          if (contentDelta.isNotEmpty) {
            String rest = pendingTagBuffer + contentDelta;
            pendingTagBuffer = '';
            while (rest.isNotEmpty) {
              final tag = inThinkTag ? _closeThinkTag : _openThinkTag;
              final idx = rest.indexOf(tag);
              if (idx < 0) {
                // 尾部可能是被拆分标签的前缀: 先缓冲，等下一个 chunk 拼齐再判定
                final overlap = _tailTagOverlap(rest, tag);
                final emitLen = rest.length - overlap;
                if (emitLen > 0) {
                  final emit = rest.substring(0, emitLen);
                    if (inThinkTag) {
                      emittedThoughts = true;
                      yield ThoughtDeltaEvent(emit);
                    } else {
                      for (final evt in contentEvents(emit)) {
                        yield evt;
                      }
                    }
                  }
                  if (overlap > 0) {
                    pendingTagBuffer = rest.substring(emitLen);
                  }
                  break;
                }
                if (idx > 0) {
                  final emit = rest.substring(0, idx);
                  if (inThinkTag) {
                    emittedThoughts = true;
                    yield ThoughtDeltaEvent(emit);
                  } else {
                    for (final evt in contentEvents(emit)) {
                      yield evt;
                    }
                  }
                }
                rest = rest.substring(idx + tag.length);
                inThinkTag = !inThinkTag;
              }
            }
          }

          // 3. 处理 tool_calls 流式组装
          if (!promptToolUse && delta['tool_calls'] is List) {
            final deltaToolCalls = delta['tool_calls'] as List<dynamic>;
            for (var position = 0; position < deltaToolCalls.length; position++) {
              final tc = deltaToolCalls[position];
              final index = tc['index'] as int? ?? position;
              if (!toolCallsAccumulator.containsKey(index)) {
                toolCallsAccumulator[index] = {
                  'id':
                      tc['id'] ??
                      'call_${DateTime.now().millisecondsSinceEpoch}_$index',
                  'name': StringBuffer(),
                  'arguments': StringBuffer(),
                  'thoughtSignature': null,
                };
              }

              final current = toolCallsAccumulator[index]!;
              if (tc['id'] != null) {
                current['id'] = tc['id'];
              }
              final tcSig = _extractToolCallThoughtSignature(tc);
              if (tcSig != null) {
                current['thoughtSignature'] = tcSig;
                yield ThoughtSignatureEvent(tcSig);
              }
              final func = tc['function'] as Map<String, dynamic>?;
              if (func != null) {
                final namePart = func['name'];
                final nameBuf = current['name'] as StringBuffer;
                if (namePart is String &&
                    namePart.isNotEmpty &&
                    namePart != nameBuf.toString()) {
                  nameBuf.write(namePart);
                }
                final argPart = func['arguments'];
                if (argPart is String && argPart.isNotEmpty) {
                  (current['arguments'] as StringBuffer).write(argPart);
                }
              }
            }
          }
        }

      // 流结束: 冲刷残缺标签缓冲 (没等到完整标签出现，按当前状态原文输出)
      if (pendingTagBuffer.isNotEmpty) {
        if (inThinkTag) {
          emittedThoughts = true;
          yield ThoughtDeltaEvent(pendingTagBuffer);
        } else {
          for (final evt in contentEvents(pendingTagBuffer)) {
            yield evt;
          }
        }
        pendingTagBuffer = '';
      }

      if (promptParser != null) {
        if (promptParseError != null) throw promptParseError!;
        if (!streamCompleted) {
          throw StateError('提示词工具调用响应流提前结束，未执行。');
        }
        if (finishReason == 'length' || _isSafetyFinishReason(finishReason)) {
          throw FormatException('提示词工具调用响应未完整生成 ($finishReason)，未执行。');
        }
        for (final evt in promptParser.finish()) {
          yield evt;
        }
      }

      // 整条流成功后一次性提交调用，按 index 排序并统一保证与历史 ID 不冲突。
      final completedCalls = <ToolCall>[...?promptParser?.calls];
      final sortedIndices = toolCallsAccumulator.keys.toList()..sort();
      for (final index in sortedIndices) {
        final raw = toolCallsAccumulator[index]!;
        final name = (raw['name'] as StringBuffer).toString();
        final id = raw['id'] as String? ?? '';
        final argsStr = (raw['arguments'] as StringBuffer).toString().trim();
        final sig = raw['thoughtSignature'] as String?;

        if (name.isEmpty) continue;
        Map<String, dynamic> args = {};
        if (argsStr.isNotEmpty) {
          final decoded = jsonDecode(argsStr);
          if (decoded is! Map) {
            throw FormatException('工具 "$name" 参数不是合法 JSON 对象');
          }
          args = Map<String, dynamic>.from(decoded);
        }

        completedCalls.add(
          ToolCall(
            id: id,
            name: name,
            arguments: args,
            thoughtSignature: sig,
          ),
        );
      }
      final refusal = refusalBuffer.toString().trim();
      if (refusal.isNotEmpty &&
          completedCalls.isEmpty &&
          !emittedContent) {
        yield ErrorEvent(
          '模型拒绝回答: $refusal',
          code: HarnessErrorCode.modelRequestFailed,
        );
        if (latestUsage != null) {
          yield UsageEvent(latestUsage);
        }
        return;
      }
      if (_isSafetyFinishReason(finishReason) &&
          completedCalls.isEmpty &&
          !emittedContent &&
          !emittedThoughts) {
        yield ErrorEvent(
          '模型响应被安全策略拦截 ($finishReason)。建议将敏感提示词或细节描述放入工具参数（如 update_studio_parameters / run_pipeline）执行，正文中只保留中性回复。',
          code: HarnessErrorCode.modelRequestFailed,
        );
        if (latestUsage != null) {
          yield UsageEvent(latestUsage);
        }
        return;
      }
      if (completedCalls.isNotEmpty) {
        for (final call in ProviderHttpTransport.normalizePendingToolCalls(
          normalizedMessages,
          completedCalls,
        )) {
          yield ToolCallEvent(call);
        }
      }
    } on FormatException catch (e) {
      yield ErrorEvent('工具调用格式错误: ${e.message}');
    } catch (e) {
      if (e is TimeoutException && !abortTrigger.isCompleted) {
        abortTrigger.complete();
      }
      // 流中断 / 解码失败多为服务端提前断连，按瞬态处理交给上层退避重试
      yield ErrorEvent('解析流式数据异常: $e', transient: true);
    }

    // 整条流只发一次 usage (含异常中断路径: 已消耗的 token 仍应入账)
    final finalUsage = latestUsage;
    if (finalUsage != null) {
      yield UsageEvent(finalUsage);
    }
  }

  /// 非流式 Chat Completions：读完整 JSON，发出与流式相同的事件。
  Stream<HarnessEvent> _emitNonStreamingChat(
    String raw, {
    required PromptToolStreamParser? promptParser,
    required List<AgentMessage> messages,
  }) async* {
    Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        yield const ErrorEvent('解析响应异常: 非 JSON 响应', transient: true);
        return;
      }
      json = Map<String, dynamic>.from(decoded);
    } catch (e) {
      yield ErrorEvent('解析响应异常: $e', transient: true);
      return;
    }

    final parsed = _readChatCompletion(json);
    final usage = parsed.usage;
    if (parsed.fatalError != null) {
      yield ErrorEvent(parsed.fatalError!, transient: parsed.transient);
      if (usage != null && usage.total > 0) yield UsageEvent(usage);
      return;
    }

    if (parsed.reasoning.isNotEmpty) {
      yield ThoughtDeltaEvent(parsed.reasoning);
    }
    for (final signature in parsed.signatures) {
      yield ThoughtSignatureEvent(signature);
    }

    FormatException? promptParseError;
    if (parsed.text.isNotEmpty) {
      try {
        final events =
            promptParser?.add(parsed.text) ?? [ContentDeltaEvent(parsed.text)];
        for (final event in events) {
          yield event;
        }
      } on FormatException catch (error) {
        promptParseError = error;
      }
    }
    if (promptParseError != null) {
      yield ErrorEvent('工具调用格式错误: ${promptParseError.message}');
      if (usage != null && usage.total > 0) yield UsageEvent(usage);
      return;
    }
    if (promptParser != null) {
      try {
        for (final evt in promptParser.finish()) {
          yield evt;
        }
      } on FormatException catch (error) {
        yield ErrorEvent('工具调用格式错误: ${error.message}');
        if (usage != null && usage.total > 0) yield UsageEvent(usage);
        return;
      }
    }

    if (parsed.toolError != null) {
      yield ErrorEvent(parsed.toolError!);
      if (usage != null && usage.total > 0) yield UsageEvent(usage);
      return;
    }

    final calls = <ToolCall>[...?promptParser?.calls, ...parsed.toolCalls];
    if (calls.isNotEmpty) {
      for (final call in ProviderHttpTransport.normalizePendingToolCalls(
        messages,
        calls,
      )) {
        yield ToolCallEvent(call);
      }
    }
    if (usage != null && usage.total > 0) yield UsageEvent(usage);
  }

  /// 把一条非流式 chat completion 收成正文、思考、工具调用和错误。
  _ChatCompletion _readChatCompletion(Map<String, dynamic> json) {
    final error = json['error'];
    if (error != null) {
      final message = error is Map
          ? (error['message']?.toString() ?? 'LLM API 请求失败')
          : error.toString();
      final type = error is Map ? error['type']?.toString() ?? '' : '';
      final code = error is Map ? error['code']?.toString() ?? '' : '';
      final transient =
          code == '429' ||
          code == '500' ||
          code == '503' ||
          type.contains('overloaded') ||
          type.contains('rate_limit') ||
          message.toLowerCase().contains('rate limit');
      return _ChatCompletion(fatalError: message, transient: transient);
    }

    final choices = json['choices'];
    final choice = choices is List && choices.isNotEmpty ? choices.first : null;
    final message = choice is Map ? choice['message'] : null;
    final finish = choice is Map ? choice['finish_reason']?.toString() : null;
    final usageJson = json['usage'];
    final usage = usageJson is Map<String, dynamic>
        ? TokenUsage.fromOpenAiJson(usageJson)
        : null;

    if (message is! Map) {
      if (finish == 'length' || _isSafetyFinishReason(finish)) {
        return _ChatCompletion(fatalError: '模型响应不完整: $finish', usage: usage);
      }
      return _ChatCompletion(usage: usage);
    }

    final msg = Map<String, dynamic>.from(message);
    var reasoning = '';
    for (final key in const [
      'reasoning_content',
      'reasoning',
      'reasoning_text',
    ]) {
      final raw = msg[key];
      if (raw is String && raw.isNotEmpty) {
        reasoning = raw;
        break;
      }
    }
    final split = _splitThinkTags(_chatMessageText(msg['content']));
    if (split.reasoning.isNotEmpty) {
      reasoning = reasoning.isEmpty
          ? split.reasoning
          : '$reasoning${split.reasoning}';
    }

    final signatures = <String>[];
    final calls = <ToolCall>[];
    String? toolError;
    final rawCalls = msg['tool_calls'];
    if (!promptToolUse && rawCalls is List) {
      for (var index = 0; index < rawCalls.length; index++) {
        final raw = rawCalls[index];
        if (raw is! Map) continue;
        final call = Map<String, dynamic>.from(raw);
        final function = call['function'];
        final name = function is Map ? function['name']?.toString() ?? '' : '';
        final argsRaw = function is Map ? function['arguments'] : null;
        Map<String, dynamic>? arguments;
        var invalid = false;
        if (argsRaw is Map) {
          arguments = Map<String, dynamic>.from(argsRaw);
        } else if (argsRaw is String && argsRaw.isNotEmpty) {
          try {
            final decoded = jsonDecode(argsRaw);
            if (decoded is Map) {
              arguments = Map<String, dynamic>.from(decoded);
            } else {
              invalid = true;
            }
          } catch (_) {
            invalid = true;
          }
        } else {
          arguments = {};
        }
        if (name.isEmpty) continue;
        if (invalid || arguments == null) {
          toolError ??= '工具调用参数不是合法 JSON: $name';
          continue;
        }
        final signature = _extractToolCallThoughtSignature(call);
        if (signature != null) signatures.add(signature);
        final rawId = call['id'];
        calls.add(
          ToolCall(
            id: rawId is String && rawId.isNotEmpty ? rawId : 'call_$index',
            name: name,
            arguments: arguments,
            thoughtSignature: signature,
          ),
        );
      }
    }
    if (toolError != null) calls.clear();

    final refusal = msg['refusal'];
    final refused = refusal is String && refusal.isNotEmpty;
    final visible = split.text;
    if (refused && visible.isEmpty && calls.isEmpty && toolError == null) {
      return _ChatCompletion(
        reasoning: reasoning,
        signatures: signatures,
        fatalError: '模型拒绝回答: $refusal',
        usage: usage,
      );
    }
    if (_isSafetyFinishReason(finish) &&
        visible.isEmpty &&
        calls.isEmpty &&
        reasoning.isEmpty) {
      return _ChatCompletion(
        fatalError: '模型响应不完整: $finish',
        usage: usage,
      );
    }

    return _ChatCompletion(
      text: visible,
      reasoning: reasoning,
      signatures: signatures,
      toolCalls: calls,
      toolError: toolError,
      usage: usage,
    );
  }

  static String _chatMessageText(Object? content) {
    if (content is String) return content;
    if (content is! List) return '';
    final buffer = StringBuffer();
    for (final part in content) {
      if (part is String) {
        buffer.write(part);
      } else if (part is Map) {
        final text = part['text'];
        if (text is String &&
            (part['type'] == null || part['type'] == 'text')) {
          buffer.write(text);
        }
      }
    }
    return buffer.toString();
  }

  static ({String text, String reasoning}) _splitThinkTags(String content) {
    if (content.isEmpty) return (text: '', reasoning: '');
    final text = StringBuffer();
    final reasoning = StringBuffer();
    var rest = content;
    var inThink = false;
    while (rest.isNotEmpty) {
      final tag = inThink ? _closeThinkTag : _openThinkTag;
      final index = rest.indexOf(tag);
      if (index < 0) {
        (inThink ? reasoning : text).write(rest);
        break;
      }
      if (index > 0) {
        (inThink ? reasoning : text).write(rest.substring(0, index));
      }
      rest = rest.substring(index + tag.length);
      inThink = !inThink;
    }
    return (text: text.toString(), reasoning: reasoning.toString());
  }
}

class _ChatCompletion {
  final String text;
  final String reasoning;
  final List<String> signatures;
  final List<ToolCall> toolCalls;
  final TokenUsage? usage;
  final String? fatalError;
  final String? toolError;
  final bool transient;

  const _ChatCompletion({
    this.text = '',
    this.reasoning = '',
    this.signatures = const [],
    this.toolCalls = const [],
    this.usage,
    this.fatalError,
    this.toolError,
    this.transient = false,
  });
}
