import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../tools/agent_tool.dart';
import '../types.dart';
import 'llm_provider.dart';

/// OpenAI 兼容格式提供商 (兼容 DeepSeek, Qwen, Moonshot, OpenAI, Ollama, LocalAI 等)
class OpenAiCompatibleProvider implements LlmProvider {
  final String baseUrl;
  final String apiKey;
  final String model;
  final http.Client _client;

  OpenAiCompatibleProvider({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    http.Client? client,
  }) : _client = client ?? http.Client();

  @override
  Stream<HarnessEvent> streamChat({
    required List<AgentMessage> messages,
    required List<AgentTool> tools,
    double temperature = 0.7,
  }) async* {
    if (apiKey.trim().isEmpty) {
      yield ErrorEvent('未配置 LLM API Key，请先在右上角设置中填写。');
      return;
    }

    String endpoint = baseUrl.trim();
    if (!endpoint.endsWith('/chat/completions')) {
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

    if (tools.isNotEmpty) {
      requestBody['tools'] = tools.map((t) => t.toOpenAiFunction()).toList();
      requestBody['tool_choice'] = 'auto';
    }

    final request = http.Request('POST', Uri.parse(endpoint));
    request.headers['Content-Type'] = 'application/json';
    request.headers['Authorization'] = 'Bearer ${apiKey.trim()}';
    request.body = jsonEncode(requestBody);

    http.StreamedResponse streamedResponse;
    try {
      streamedResponse = await _client.send(request);
    } catch (e) {
      yield ErrorEvent('网络请求异常: $e');
      return;
    }

    if (streamedResponse.statusCode != 200) {
      final errBody = await streamedResponse.stream.bytesToString();
      yield ErrorEvent('LLM API 响应错误 (HTTP ${streamedResponse.statusCode}): $errBody');
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
                'id': tc['id'] ?? 'call_${DateTime.now().millisecondsSinceEpoch}_$index',
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
          yield ToolCallEvent(
            ToolCall(id: id, name: name, arguments: args),
          );
        }
      }
    } catch (e) {
      yield ErrorEvent('解析流式数据异常: $e');
    }
  }
}
