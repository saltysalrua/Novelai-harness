import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../tools/agent_tool.dart';
import '../types.dart';
import 'llm_provider.dart';
import 'prompt_cache_policy.dart';
import '../../../data/models/llm_cache_config.dart';

/// OpenAI 兼容格式提供商 (兼容 DeepSeek, Qwen, Moonshot, OpenAI, Ollama, LocalAI 等)
class OpenAiCompatibleProvider implements LlmProvider {
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

  OpenAiCompatibleProvider({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.reasoning = false,
    this.thinkingEffort,
    this.thinkingParamFormat,
    this.cacheConfig = const LlmCacheConfig(),
    http.Client? client,
  }) : _client = client ?? http.Client();

  @override
  String get modelId => model;

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

  bool _isGemini25FlashChatEndpoint() {
    final uri = Uri.tryParse(baseUrl.trim());
    return uri?.host == 'generativelanguage.googleapis.com' &&
        uri?.path.endsWith('/chat/completions') == true &&
        model.trim() == 'gemini-2.5-flash';
  }

  bool _shouldOmitTemperature(String endpoint) {
    final uri = Uri.tryParse(endpoint);
    return uri?.scheme == 'https' &&
        uri?.host == 'api.anthropic.com' &&
        uri?.path == '/v1/chat/completions' &&
        model.trim() == 'claude-sonnet-5';
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

  /// DeepSeek 的工具请求要求完整回传历史 assistant 思考；其他兼容端点
  /// 保持标准 OpenAI 消息形状。空思考不补字段，避免臆造模型未返回的内容。
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
    return json;
  }

  /// 按格式写入思考开关参数 (对齐 pi openai-completions 的 thinkingFormat 分支):
  /// 不同供应商用不同字段开关思维链，格式不匹配时思考会被上游静默丢弃；
  /// 部分格式 (Qwen / DeepSeek / Z.ai) 关闭思考也需显式发送 disabled。
  void _applyThinkingParams(Map<String, dynamic> body) {
    final effort = thinkingEffort?.trim();
    // 模型不具备思考能力时不发送任何思考参数
    if (effort == null || effort.isEmpty) return;
    final thinkingOn = reasoning;
    switch (resolvedThinkingFormat) {
      case 'deepseek':
        body['thinking'] = {'type': thinkingOn ? 'enabled' : 'disabled'};
        if (thinkingOn) body['reasoning_effort'] = effort;
      case 'qwen':
        body['enable_thinking'] = thinkingOn;
        if (thinkingOn) body['reasoning_effort'] = effort;
      case 'qwen_chat_template':
        body['chat_template_kwargs'] = {
          'enable_thinking': thinkingOn,
          'preserve_thinking': true,
        };
      case 'zai':
        body['thinking'] = thinkingOn
            ? {'type': 'enabled', 'clear_thinking': false}
            : {'type': 'disabled'};
        if (thinkingOn) body['reasoning_effort'] = effort;
      case 'openrouter':
        // OpenRouter 用嵌套 reasoning 对象归一化各上游的思考开关
        body['reasoning'] = {'effort': thinkingOn ? effort : 'none'};
      case 'together':
        body['reasoning'] = {'enabled': thinkingOn};
        if (thinkingOn) body['reasoning_effort'] = effort;
      default:
        // OpenAI 风格: 开思考时发送 reasoning_effort，关闭时不发送
        if (thinkingOn) {
          body['reasoning_effort'] = effort;
        } else if (effort == 'none' && _isGemini25FlashChatEndpoint()) {
          // Gemini 2.5 Flash distinguishes an omitted provider default from
          // the explicit none value that disables thinking.
          body['reasoning_effort'] = 'none';
        }
    }
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

    final replayDeepSeekReasoning =
        tools.isNotEmpty && resolvedThinkingFormat == 'deepseek';
    final requestBody = <String, dynamic>{
      'model': model.trim(),
      'messages': messages
          .map(
            (message) => _serializeMessage(
              message,
              replayDeepSeekReasoning: replayDeepSeekReasoning,
            ),
          )
          .toList(),
      'stream': true,
      'temperature': temperature,
    };
    if (_shouldOmitTemperature(endpoint)) {
      requestBody.remove('temperature');
    }

    // 思考参数按供应商兼容矩阵写入 (格式不匹配时思考会被上游静默丢弃)
    _applyThinkingParams(requestBody);

    if (tools.isNotEmpty) {
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
    try {
      streamedResponse = await _send(endpoint, requestBody, cacheHeaders);
    } catch (e) {
      // 连接失败 / 超时 / TLS 握手中断等网络层异常均为瞬态
      yield ErrorEvent('网络请求异常: $e', transient: true);
      return;
    }

    // 仅在明确拒绝缓存字段时逐项降级，最多两次；长度/值错误不能污染能力记录。
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
        yield ErrorEvent('LLM API 响应错误 (HTTP 400): $errBody');
        return;
      }
      _unsupportedCacheFields.add((endpoint, model.trim(), rejectedField));
      requestBody.remove(rejectedField);
      try {
        streamedResponse = await _send(endpoint, requestBody, cacheHeaders);
      } catch (e) {
        yield ErrorEvent('网络请求异常: $e', transient: true);
        return;
      }
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
        if (data == '[DONE]') break;

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
                    yield ContentDeltaEvent(emit);
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
                  yield ContentDeltaEvent(emit);
                }
              }
              rest = rest.substring(idx + tag.length);
              inThinkTag = !inThinkTag;
            }
          }
        }

        // 3. 处理 tool_calls 流式组装
        if (delta.containsKey('tool_calls') && delta['tool_calls'] is List) {
          final deltaToolCalls = delta['tool_calls'] as List<dynamic>;
          for (final tc in deltaToolCalls) {
            final index = tc['index'] as int? ?? 0;
            if (!toolCallsAccumulator.containsKey(index)) {
              toolCallsAccumulator[index] = {
                'id':
                    tc['id'] ??
                    'call_${DateTime.now().millisecondsSinceEpoch}_$index',
                'name': '',
                'arguments': '',
              };
            }

            final current = toolCallsAccumulator[index]!;
            if (tc['id'] != null) {
              current['id'] = tc['id'];
            }
            final func = tc['function'] as Map<String, dynamic>?;
            if (func != null) {
              if (func['name'] != null) {
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
          yield ContentDeltaEvent(pendingTagBuffer);
        }
        pendingTagBuffer = '';
      }

      // 如果有工具调用完成组装，发送 ToolCallEvent
      for (final entry in toolCallsAccumulator.entries) {
        final raw = entry.value;
        final name = raw['name'] as String? ?? '';
        final id = raw['id'] as String? ?? '';
        final argsStr = raw['arguments'] as String? ?? '{}';

        Map<String, dynamic> args = {};
        try {
          args = jsonDecode(argsStr) as Map<String, dynamic>;
        } catch (_) {}

        if (name.isNotEmpty) {
          yield ToolCallEvent(ToolCall(id: id, name: name, arguments: args));
        }
      }
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
}
