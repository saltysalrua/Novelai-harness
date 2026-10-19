import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../tools/agent_tool.dart';
import '../types.dart';
import 'anthropic_messages.dart';
import 'google_interactions_provider.dart';
import 'llm_provider.dart';
import 'openai_responses.dart';
import 'prompt_cache_policy.dart';
import 'prompt_tool_codec.dart';
import 'tool_call_ids.dart';
import '../../../data/models/llm_cache_config.dart';

/// OpenAI 兼容格式提供商 (兼容 DeepSeek, Qwen, Moonshot, OpenAI, Ollama, LocalAI 等)
class OpenAiCompatibleProvider implements LlmProvider, LlmRequestOverhead {
  /// 拒绝记录按端点、模型、字段隔离，不能让一个中转站关闭所有供应商的缓存键。
  static final Set<(String, String, String)> _unsupportedCacheFields = {};

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
  final LlmCacheConfig cacheConfig;

  /// 纯聊天渠道兼容模式：提示词声明工具，正文解析调用。
  final bool promptToolUse;

  OpenAiCompatibleProvider({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.reasoning = false,
    this.thinkingEffort,
    this.thinkingParamFormat,
    this.cacheConfig = const LlmCacheConfig(),
    this.promptToolUse = false,
    http.Client? client,
  }) : _client = client ?? http.Client();

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

  bool get _isGeminiModel => _normalizedModelLower.startsWith('gemini-');

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
      code == 408 || code == 429 || (code >= 500 && code <= 599);

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
      if (toolCallsList.isNotEmpty && toolCallsList.first is Map<String, dynamic>) {
        final hasSignature = toolCallsList.any(
          (tc) =>
              tc is Map &&
              tc['extra_content'] is Map &&
              (tc['extra_content'] as Map)['google'] is Map &&
              ((tc['extra_content'] as Map)['google'] as Map)['thought_signature']
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
    if (endpoint.endsWith('/interactions') ||
        endpoint.endsWith('/interactions/')) {
      final interactionsProvider = GoogleInteractionsProvider(
        apiKey: apiKey,
        baseUrl: endpoint,
        modelId: model,
        reasoning: reasoning,
        thinkingEffort: thinkingEffort ?? 'medium',
        promptToolUse: promptToolUse,
        cacheConfig: cacheConfig,
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
      yield* _streamResponses(
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
      yield* _streamAnthropic(
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
      'stream': true,
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
      requestBody['stream_options'] = {'include_usage': true};
      cachePolicy.apply(requestBody, promptCacheKey);
      cacheHeaders.addAll(cachePolicy.headers(promptCacheKey));
      for (final field in const [
        'prompt_cache_key',
        'prompt_cache_retention',
      ]) {
        if (_unsupportedCacheFields.contains((endpoint, model.trim(), field))) {
          requestBody.remove(field);
        }
      }
    }

    http.StreamedResponse streamedResponse;
    String? badRequestBody;
    try {
      final (response, errBody) = await _drainRejectedCacheFields(
        await _send(endpoint, requestBody, cacheHeaders),
        endpoint,
        requestBody,
        cacheHeaders,
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
      final errBody = await streamedResponse.stream.bytesToString();
      yield ErrorEvent(
        'LLM API 响应错误 (HTTP ${streamedResponse.statusCode}): $errBody',
        transient: isTransientStatus(streamedResponse.statusCode),
      );
      return;
    }

    // 累加工具调用片段
    final Map<int, Map<String, dynamic>> toolCallsAccumulator = {};
    bool inThinkTag = false;
    String pendingTagBuffer = '';
    bool streamCompleted = false;
    String? finishReason;
    FormatException? promptParseError;

    // 格式错误后仍消费 SSE 尾部，以保留真实 usage；任何调用都不提交。
    List<ContentDeltaEvent> contentEvents(String text) {
      if (promptParseError != null) return const [];
      try {
        return promptParser?.add(text) ?? [ContentDeltaEvent(text)];
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
          .transform(utf8.decoder)
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
            yield ThoughtDeltaEvent(raw);
            break;
          }
        }

        // 2. 处理标准 content (内嵌思考标签容错: 标签可能被流式拆分到多个 chunk)
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
                    yield ThoughtDeltaEvent(emit);
                  } else {
                    yield* Stream.fromIterable(contentEvents(emit));
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
                  yield ThoughtDeltaEvent(emit);
                } else {
                  yield* Stream.fromIterable(contentEvents(emit));
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
                'name': '',
                'arguments': '',
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
              if (func['name'] != null && func['name'] != current['name']) {
                current['name'] = '${current['name']}${func['name']}';
              }
              if (func['arguments'] != null) {
                current['arguments'] =
                    '${current['arguments']}${func['arguments']}';
              }
            }
          }
        }
      }

      // 流结束: 冲刷残缺标签缓冲 (没等到完整标签出现，按当前状态原文输出)
      if (pendingTagBuffer.isNotEmpty) {
        if (inThinkTag) {
          yield ThoughtDeltaEvent(pendingTagBuffer);
        } else {
          yield* Stream.fromIterable(contentEvents(pendingTagBuffer));
        }
        pendingTagBuffer = '';
      }

      if (promptParser != null) {
        if (promptParseError != null) throw promptParseError!;
        if (!streamCompleted) {
          throw StateError('提示词工具调用响应流提前结束，未执行。');
        }
        if (finishReason == 'length' || finishReason == 'content_filter') {
          throw FormatException('提示词工具调用响应未完整生成 ($finishReason)，未执行。');
        }
        yield* Stream.fromIterable(promptParser.finish());
      }

      // 整条流成功后一次性提交调用，统一保证与历史 ID 不冲突。
      final completedCalls = <ToolCall>[...?promptParser?.calls];
      for (final entry in toolCallsAccumulator.entries) {
        final raw = entry.value;
        final name = raw['name'] as String? ?? '';
        final id = raw['id'] as String? ?? '';
        final argsStr = raw['arguments'] as String? ?? '{}';
        final sig = raw['thoughtSignature'] as String?;

        Map<String, dynamic> args = {};
        try {
          args = jsonDecode(argsStr) as Map<String, dynamic>;
        } catch (_) {}

        if (name.isNotEmpty) {
          completedCalls.add(
            ToolCall(
              id: id,
              name: name,
              arguments: args,
              thoughtSignature: sig,
            ),
          );
        }
      }
      if (completedCalls.isNotEmpty) {
        final normalized = normalizeToolCallIds([
          ...normalizedMessages,
          AgentMessage(
            id: 'pending_tool_calls',
            role: AgentRole.assistant,
            toolCalls: completedCalls,
          ),
        ]).last.toolCalls!;
        for (final call in normalized) {
          yield ToolCallEvent(call);
        }
      }
    } on FormatException catch (e) {
      yield ErrorEvent('工具调用格式错误: ${e.message}');
    } catch (e) {
      // 流中断 / 解码失败多为服务端提前断连，按瞬态处理交给上层退避重试
      yield ErrorEvent('解析流式数据异常: $e', transient: true);
    }

    // 整条流只发一次 usage (含异常中断路径: 已消耗的 token 仍应入账)
    final finalUsage = latestUsage;
    if (finalUsage != null) {
      yield UsageEvent(finalUsage);
    }
  }

  /// HTTP 400 降级重试：错误体明确拒绝 prompt_cache_key / prompt_cache_retention
  /// 时移除该字段、记入能力记录并重发，最多重试两次；其余 400 原样返回给调用方。
  /// Chat Completions 与 Responses 两条路径共用。
  Future<(http.StreamedResponse, String?)> _drainRejectedCacheFields(
    http.StreamedResponse streamedResponse,
    String endpoint,
    Map<String, dynamic> requestBody,
    Map<String, String> cacheHeaders,
  ) async {
    while (streamedResponse.statusCode == 400) {
      final errBody = await streamedResponse.stream.bytesToString();
      final lower = errBody.toLowerCase();
      String? rejectedField;
      if (RegExp(
        r'unsupported|not supported|unknown|unrecognized|not permitted|not allowed|extra inputs',
      ).hasMatch(lower)) {
        for (final field in const [
          'prompt_cache_key',
          'prompt_cache_retention',
        ]) {
          if (requestBody.containsKey(field) && lower.contains(field)) {
            rejectedField = field;
            break;
          }
        }
      }
      if (rejectedField == null) {
        return (streamedResponse, errBody);
      }
      _unsupportedCacheFields.add((endpoint, model.trim(), rejectedField));
      requestBody.remove(rejectedField);
      streamedResponse = await _send(endpoint, requestBody, cacheHeaders);
    }
    return (streamedResponse, null);
  }

  /// 发送 POST 请求 (缓存键降级重试复用)
  Future<http.StreamedResponse> _send(
    String endpoint,
    Map<String, dynamic> requestBody,
    Map<String, String> cacheHeaders,
  ) {
    final request = http.Request('POST', Uri.parse(endpoint));
    request.headers['Content-Type'] = 'application/json';
    request.headers.addAll(cacheHeaders);
    if (endpoint.endsWith('/messages')) {
      request.headers['x-api-key'] = apiKey.trim();
      request.headers['anthropic-version'] = '2023-06-01';
    }
    final trimmedKey = apiKey.trim();
    if (trimmedKey.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $trimmedKey';
    }
    request.body = jsonEncode(requestBody);
    return _client.send(request);
  }

  /// `POST /v1/messages`：请求体与 SSE 按 Anthropic Messages，回放 thinking 块。
  Stream<HarnessEvent> _streamAnthropic({
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

    http.StreamedResponse streamedResponse;
    try {
      streamedResponse = await _send(endpoint, requestBody, cacheHeaders);
    } catch (e) {
      yield ErrorEvent('网络请求异常: $e', transient: true);
      return;
    }

    if (streamedResponse.statusCode != 200) {
      final errBody = await streamedResponse.stream.bytesToString();
      yield ErrorEvent(
        'LLM API 响应错误 (HTTP ${streamedResponse.statusCode}): $errBody',
        transient: isTransientStatus(streamedResponse.statusCode),
      );
      return;
    }

    FormatException? promptParseError;
    var streamCompleted = false;
    var failed = false;
    final calls = <ToolCall>[];
    TokenUsage? latestUsage;
    final parser = AnthropicMessagesStreamParser();

    List<ContentDeltaEvent> contentEvents(String text) {
      if (text.isEmpty || promptParseError != null) return const [];
      try {
        return promptParser?.add(text) ?? [ContentDeltaEvent(text)];
      } on FormatException catch (error) {
        promptParseError = error;
        return const [];
      }
    }

    Iterable<HarnessEvent> absorb(List<HarnessEvent> events) sync* {
      for (final event in events) {
        if (event is ContentDeltaEvent) {
          yield* contentEvents(event.delta);
        } else if (event is ToolCallEvent) {
          calls.add(event.toolCall);
        } else if (event is ErrorEvent) {
          failed = true;
          yield event;
        } else if (event is UsageEvent) {
          latestUsage = event.usage;
        } else {
          yield event;
        }
      }
    }

    final prelude = StringBuffer();
    var sawSse = false;
    String? pendingEvent;

    try {
      final lineStream = streamedResponse.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      await for (final line in lineStream) {
        final trimmed = line.trim();
        if (!sawSse) {
          if (trimmed.startsWith('data:') || trimmed.startsWith('event:')) {
            sawSse = true;
          } else {
            prelude.writeln(line);
            continue;
          }
        }
        if (trimmed.isEmpty) {
          pendingEvent = null;
          continue;
        }
        if (trimmed.startsWith(':')) continue;
        if (trimmed.startsWith('event:')) {
          pendingEvent = trimmed.substring(6).trim();
          continue;
        }
        if (!trimmed.startsWith('data:')) continue;

        final data = trimmed.substring(5).trim();
        if (data.isEmpty) continue;
        if (data == '[DONE]') {
          streamCompleted = true;
          pendingEvent = null;
          break;
        }

        Map<String, dynamic> json;
        try {
          final decoded = jsonDecode(data);
          if (decoded is! Map) {
            pendingEvent = null;
            continue;
          }
          json = Map<String, dynamic>.from(decoded);
        } catch (_) {
          pendingEvent = null;
          continue;
        }

        if (json['type'] == 'message_stop' || pendingEvent == 'message_stop') {
          streamCompleted = true;
        }
        yield* Stream.fromIterable(
          absorb(parser.add(json, eventType: pendingEvent)),
        );
        pendingEvent = null;
      }
    } catch (e) {
      failed = true;
      yield ErrorEvent('解析流式数据异常: $e', transient: true);
    }

    if (!sawSse) {
      final raw = prelude.toString().trim();
      if (raw.isEmpty) return;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) {
          yield const ErrorEvent('解析流式数据异常: 非 JSON 响应', transient: true);
          return;
        }
        final completion = AnthropicMessages.parseResponse(
          Map<String, dynamic>.from(decoded),
        );
        if (completion.error != null) {
          failed = true;
          yield ErrorEvent(
            completion.error!,
            transient: completion.transientError,
          );
        } else {
          if (completion.reasoningRecords.isNotEmpty) {
            yield ReasoningSnapshotEvent(completion.reasoningRecords);
          }
          if (completion.reasoning.isNotEmpty) {
            yield ThoughtDeltaEvent(completion.reasoning);
          }
          for (final record in completion.reasoningRecords) {
            final sig = record.signature;
            if (sig != null && sig.isNotEmpty) {
              yield ThoughtSignatureEvent(sig);
            }
          }
          yield* Stream.fromIterable(contentEvents(completion.text));
          calls.addAll(completion.toolCalls);
          streamCompleted = true;
        }
        latestUsage = completion.usage;
      } catch (e) {
        yield ErrorEvent('解析流式数据异常: $e', transient: true);
        return;
      }
    } else {
      yield* Stream.fromIterable(absorb(parser.finish()));
    }

    if (promptParser != null && !failed) {
      final parseError = promptParseError;
      if (parseError != null) {
        failed = true;
        yield ErrorEvent('工具调用格式错误: ${parseError.message}');
      } else if (!streamCompleted) {
        failed = true;
        yield const ErrorEvent('提示词工具调用响应流提前结束，未执行。');
      } else {
        try {
          yield* Stream.fromIterable(promptParser.finish());
        } on FormatException catch (e) {
          failed = true;
          yield ErrorEvent('工具调用格式错误: ${e.message}');
        }
      }
    } else if (promptParser == null && !failed && !streamCompleted) {
      failed = true;
      yield const ErrorEvent('Anthropic 响应流提前结束，未执行工具调用。', transient: true);
    }

    final promptCalls =
        !failed && promptParser != null && promptParseError == null
        ? promptParser.calls
        : const <ToolCall>[];
    if (!failed && (calls.isNotEmpty || promptCalls.isNotEmpty)) {
      final normalized = normalizeToolCallIds([
        ...messages,
        AgentMessage(
          id: 'pending_tool_calls',
          role: AgentRole.assistant,
          toolCalls: [...calls, ...promptCalls],
        ),
      ]).last.toolCalls!;
      for (final call in normalized) {
        yield ToolCallEvent(call);
      }
    }

    final usage = latestUsage;
    if (usage != null && usage.total > 0) {
      yield UsageEvent(usage);
    }
  }

  /// Responses API 的思考强度。只在开启思考时发送 `reasoning.effort`。
  String? _responsesReasoningEffort() {
    if (!reasoning) return null;
    final effort = thinkingEffort?.trim();
    if (effort == null || effort.isEmpty) return null;
    final effective = _isGoogleOrGemini
        ? _clampGeminiReasoningEffort(effort)
        : effort;
    if (_isGoogleOrGemini && effective == 'none') return null;
    return effective;
  }

  /// `POST /v1/responses`：请求体与 SSE 都按 Responses API，不复用 Chat Completions。
  Stream<HarnessEvent> _streamResponses({
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
      model: _isGoogleHost
          ? GoogleInteractionsProvider.normalizeModelId(model)
          : model.trim(),
      messages: messages,
      tools: tools,
      temperature: temperature,
      stream: true,
      reasoningEffort: effort,
      includeEncryptedReasoning: reasoning,
      includeTemperature: !_shouldOmitResponsesTemperature(endpoint, effort),
      promptToolUse: promptToolUse,
    );

    // 提示缓存：仅 openai 模式在 Responses 请求体上写 prompt_cache_key /
    // prompt_cache_retention；anthropic 模式的 apply 依赖 body['messages']，
    // 在 Responses 请求体 (input/instructions) 上调用会崩溃，故不调用。
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
        if (_unsupportedCacheFields.contains((endpoint, model.trim(), field))) {
          requestBody.remove(field);
        }
      }
    }

    http.StreamedResponse streamedResponse;
    String? badRequestBody;
    try {
      final (response, errBody) = await _drainRejectedCacheFields(
        await _send(endpoint, requestBody, cacheHeaders),
        endpoint,
        requestBody,
        cacheHeaders,
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
      final errBody = await streamedResponse.stream.bytesToString();
      yield ErrorEvent(
        'LLM API 响应错误 (HTTP ${streamedResponse.statusCode}): $errBody',
        transient: isTransientStatus(streamedResponse.statusCode),
      );
      return;
    }

    FormatException? promptParseError;
    var streamCompleted = false;
    var failed = false;
    final calls = <ToolCall>[];
    TokenUsage? latestUsage;
    final parser = OpenAiResponsesStreamParser();

    List<ContentDeltaEvent> contentEvents(String text) {
      if (text.isEmpty || promptParseError != null) return const [];
      try {
        return promptParser?.add(text) ?? [ContentDeltaEvent(text)];
      } on FormatException catch (error) {
        promptParseError = error;
        return const [];
      }
    }

    Iterable<HarnessEvent> absorb(List<HarnessEvent> events) sync* {
      for (final event in events) {
        if (event is ContentDeltaEvent) {
          yield* contentEvents(event.delta);
        } else if (event is ToolCallEvent) {
          calls.add(event.toolCall);
        } else if (event is ErrorEvent) {
          failed = true;
          yield event;
        } else if (event is UsageEvent) {
          latestUsage = event.usage;
        } else {
          yield event;
        }
      }
    }

    final prelude = StringBuffer();
    var sawSse = false;
    String? pendingEvent;

    try {
      final lineStream = streamedResponse.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      await for (final line in lineStream) {
        final trimmed = line.trim();
        if (!sawSse) {
          if (trimmed.startsWith('data:') || trimmed.startsWith('event:')) {
            sawSse = true;
          } else {
            prelude.writeln(line);
            continue;
          }
        }
        if (trimmed.isEmpty) {
          pendingEvent = null;
          continue;
        }
        if (trimmed.startsWith(':')) continue;
        if (trimmed.startsWith('event:')) {
          pendingEvent = trimmed.substring(6).trim();
          continue;
        }
        if (!trimmed.startsWith('data:')) continue;

        final data = trimmed.substring(5).trim();
        if (data.isEmpty) continue;
        if (data == '[DONE]') {
          streamCompleted = true;
          pendingEvent = null;
          break;
        }

        Map<String, dynamic> json;
        try {
          final decoded = jsonDecode(data);
          if (decoded is! Map) {
            pendingEvent = null;
            continue;
          }
          json = Map<String, dynamic>.from(decoded);
        } catch (_) {
          pendingEvent = null;
          continue;
        }

        if (json['type'] == 'response.completed' ||
            pendingEvent == 'response.completed') {
          streamCompleted = true;
        }
        yield* Stream.fromIterable(
          absorb(parser.add(json, eventType: pendingEvent)),
        );
        pendingEvent = null;
      }
    } catch (e) {
      failed = true;
      yield ErrorEvent('解析流式数据异常: $e', transient: true);
    }

    if (!sawSse) {
      final raw = prelude.toString().trim();
      if (raw.isEmpty) return;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) {
          yield const ErrorEvent('解析流式数据异常: 非 JSON 响应', transient: true);
          return;
        }
        final completion = OpenAiResponses.parseResponse(
          Map<String, dynamic>.from(decoded),
        );
        if (completion.error != null) {
          failed = true;
          yield ErrorEvent(
            completion.error!,
            transient: completion.transientError,
          );
        } else {
          if (completion.reasoningRecords.isNotEmpty) {
            yield ReasoningSnapshotEvent(completion.reasoningRecords);
          }
          if (completion.reasoning.isNotEmpty) {
            yield ThoughtDeltaEvent(completion.reasoning);
          }
          yield* Stream.fromIterable(contentEvents(completion.text));
          calls.addAll(completion.toolCalls);
          streamCompleted = true;
        }
        latestUsage = completion.usage;
      } catch (e) {
        yield ErrorEvent('解析流式数据异常: $e', transient: true);
        return;
      }
    } else {
      yield* Stream.fromIterable(absorb(parser.finish()));
    }

    if (promptParser != null && !failed) {
      final parseError = promptParseError;
      if (parseError != null) {
        failed = true;
        yield ErrorEvent('工具调用格式错误: ${parseError.message}');
      } else if (!streamCompleted) {
        failed = true;
        yield const ErrorEvent('提示词工具调用响应流提前结束，未执行。');
      } else {
        try {
          yield* Stream.fromIterable(promptParser.finish());
        } on FormatException catch (e) {
          failed = true;
          yield ErrorEvent('工具调用格式错误: ${e.message}');
        }
      }
    } else if (promptParser == null && !failed && !streamCompleted) {
      // 原生工具模式：流未正常结束（无 completed/[DONE]）时，残缺的
      // 工具调用参数不可信，报瞬态错误并跳过执行。
      failed = true;
      yield const ErrorEvent('Responses 响应流提前结束，未执行工具调用。', transient: true);
    }

    final promptCalls =
        !failed && promptParser != null && promptParseError == null
        ? promptParser.calls
        : const <ToolCall>[];
    if (!failed && (calls.isNotEmpty || promptCalls.isNotEmpty)) {
      final normalized = normalizeToolCallIds([
        ...messages,
        AgentMessage(
          id: 'pending_tool_calls',
          role: AgentRole.assistant,
          toolCalls: [...calls, ...promptCalls],
        ),
      ]).last.toolCalls!;
      for (final call in normalized) {
        yield ToolCallEvent(call);
      }
    }

    final usage = latestUsage;
    if (usage != null && usage.total > 0) {
      yield UsageEvent(usage);
    }
  }
}
