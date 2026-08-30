import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../tools/agent_tool.dart';
import '../types.dart';
import 'llm_provider.dart';

/// OpenAI 兼容格式提供商 (兼容 DeepSeek, Qwen, Moonshot, OpenAI, Ollama, LocalAI 等)
class OpenAiCompatibleProvider implements LlmProvider {
  /// 进程级降级开关：一旦某个端点对 `prompt_cache_key` 返回 400
  /// ("Unsupported parameter")，后续请求不再携带该字段，避免反复撞墙。
  /// (参考 pi-cache-optimizer 的进程内 fallback 策略)
  static bool promptCacheKeyUnsupported = false;

  /// OpenAI 官方限制 prompt_cache_key 不超过 64 字符，超长截断
  /// (参考 pi 的 clampOpenAIPromptCacheKey)
  static String? clampPromptCacheKey(String? key) {
    if (key == null) return null;
    final chars = key.runes.toList();
    return String.fromCharCodes(
      chars.length <= 64 ? chars : chars.sublist(0, 64),
    );
  }

  final String baseUrl;
  final String apiKey;
  final String model;
  final bool reasoning;
  final String? thinkingEffort;
  final http.Client _client;

  OpenAiCompatibleProvider({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.reasoning = false,
    this.thinkingEffort,
    http.Client? client,
  }) : _client = client ?? http.Client();

  @override
  String get modelId => model;

  @override
  Stream<HarnessEvent> streamChat({
    required List<AgentMessage> messages,
    required List<AgentTool> tools,
    double temperature = 0.7,
    String? promptCacheKey,
  }) async* {
    if (apiKey.trim().isEmpty) {
      yield ErrorEvent('未配置 LLM API Key，请先在右上角设置中填写。');
      return;
    }

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

    final requestBody = <String, dynamic>{
      'model': model.trim(),
      'messages': messages.map((m) => m.toOpenAiJson()).toList(),
      'stream': true,
      'temperature': temperature,
    };

    if (reasoning && thinkingEffort != null && thinkingEffort!.isNotEmpty) {
      requestBody['reasoning_effort'] = thinkingEffort;
    }

    if (tools.isNotEmpty) {
      requestBody['tools'] = tools.map((t) => t.toOpenAiFunction()).toList();
      requestBody['tool_choice'] = 'auto';
    }

    // OpenAI 兼容端点：请求在最后一个 chunk 里携带 usage 统计
    if (endpoint.endsWith('/chat/completions')) {
      requestBody['stream_options'] = {'include_usage': true};
      // 会话级缓存路由键：帮助支持该参数的端点 (OpenAI 官方及兼容代理)
      // 把同一会话的请求路由到同一 KV Cache 分片；不认识的端点一般忽略
      // 未知字段，若严格拒绝则在响应处理中自动降级并重试。
      final cacheKey = clampPromptCacheKey(promptCacheKey);
      if (cacheKey != null &&
          cacheKey.isNotEmpty &&
          !promptCacheKeyUnsupported) {
        requestBody['prompt_cache_key'] = cacheKey;
      }
    }

    http.StreamedResponse streamedResponse;
    try {
      streamedResponse = await _send(endpoint, requestBody);
    } catch (e) {
      yield ErrorEvent('网络请求异常: $e');
      return;
    }

    // 严格端点对 prompt_cache_key 返回 400：进程内降级并去掉该字段重试一次
    if (streamedResponse.statusCode == 400 &&
        requestBody.containsKey('prompt_cache_key')) {
      final errBody = await streamedResponse.stream.bytesToString();
      if (errBody.contains('prompt_cache_key')) {
        promptCacheKeyUnsupported = true;
        requestBody.remove('prompt_cache_key');
        try {
          streamedResponse = await _send(endpoint, requestBody);
        } catch (e) {
          yield ErrorEvent('网络请求异常: $e');
          return;
        }
      } else {
        yield ErrorEvent('LLM API 响应错误 (HTTP 400): $errBody');
        return;
      }
    }

    if (streamedResponse.statusCode != 200) {
      final errBody = await streamedResponse.stream.bytesToString();
      yield ErrorEvent(
        'LLM API 响应错误 (HTTP ${streamedResponse.statusCode}): $errBody',
      );
      return;
    }

    // 累加工具调用片段
    final Map<int, Map<String, dynamic>> toolCallsAccumulator = {};
    bool inThinkTag = false;

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
        final usageJson = json['usage'];
        if (usageJson is Map<String, dynamic>) {
          final usage = TokenUsage.fromJson(usageJson);
          if (usage.total > 0) {
            yield UsageEvent(usage);
          }
        }

        if (choices == null || choices.isEmpty) continue;

        final delta = choices[0]['delta'] as Map<String, dynamic>?;
        if (delta == null) continue;

        // 1. 处理原生 reasoning_content (DeepSeek-R1 / Qwen 等)
        if (delta.containsKey('reasoning_content') &&
            delta['reasoning_content'] != null) {
          final reasoningDelta = delta['reasoning_content'] as String;
          if (reasoningDelta.isNotEmpty) {
            yield ThoughtDeltaEvent(reasoningDelta);
          }
        }

        // 2. 处理标准 content (含 <think> 标签容错)
        if (delta.containsKey('content') && delta['content'] != null) {
          final contentDelta = delta['content'] as String;
          if (contentDelta.isNotEmpty) {
            // 处理嵌入式的 <think> 标签
            if (contentDelta.contains('<think>')) {
              inThinkTag = true;
              final parts = contentDelta.split('<think>');
              if (parts[0].isNotEmpty) {
                yield ContentDeltaEvent(parts[0]);
              }
              if (parts.length > 1 && parts[1].isNotEmpty) {
                yield ThoughtDeltaEvent(parts[1]);
              }
              continue;
            }

            if (inThinkTag) {
              if (contentDelta.contains('</think>')) {
                inThinkTag = false;
                final parts = contentDelta.split('</think>');
                if (parts[0].isNotEmpty) {
                  yield ThoughtDeltaEvent(parts[0]);
                }
                if (parts.length > 1 && parts[1].isNotEmpty) {
                  yield ContentDeltaEvent(parts[1]);
                }
              } else {
                yield ThoughtDeltaEvent(contentDelta);
              }
              continue;
            }

            yield ContentDeltaEvent(contentDelta);
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
      yield ErrorEvent('解析流式数据异常: $e');
    }
  }

  /// 发送 POST 请求 (缓存键降级重试复用)
  Future<http.StreamedResponse> _send(
    String endpoint,
    Map<String, dynamic> requestBody,
  ) {
    final request = http.Request('POST', Uri.parse(endpoint));
    request.headers['Content-Type'] = 'application/json';
    if (endpoint.endsWith('/messages')) {
      request.headers['x-api-key'] = apiKey.trim();
      request.headers['anthropic-version'] = '2023-06-01';
    }
    request.headers['Authorization'] = 'Bearer ${apiKey.trim()}';
    request.body = jsonEncode(requestBody);
    return _client.send(request);
  }
}
