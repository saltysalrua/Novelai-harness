import 'dart:convert';

import '../tools/agent_tool.dart';
import '../types.dart';
import 'prompt_tool_codec.dart';

/// OpenAI Responses API (`POST /v1/responses`) 的请求体与响应解析。
///
/// Chat Completions 仍走 [OpenAiCompatibleProvider] 的原有消息体；
/// 只有 `/responses` 端点使用这里的 `input` / `instructions` 形状。
class OpenAiResponses {
  /// 系统与 developer 提示都进入顶层 instructions，不进入 input。
  static bool isInstructionRole(String role) =>
      role == 'system' || role == 'developer';

  /// 把 Chat Completions 的 tool_choice 收成 Responses 的扁平形状。
  /// 字符串 (`auto` / `none` / `required`) 原样保留；
  /// `{type: function, function: {name}}` 变成 `{type: function, name}`。
  static Object mapToolChoice(Object choice) {
    if (choice is! Map) return choice;
    final type = choice['type']?.toString() ?? 'function';
    final nested = choice['function'];
    final nestedName = nested is Map && nested['name'] is String
        ? nested['name'] as String
        : null;
    final name = choice['name'] is String
        ? choice['name'] as String
        : nestedName;
    if (type == 'function') {
      return {
        'type': 'function',
        if (name != null && name.isNotEmpty) 'name': name,
      };
    }
    final copy = Map<String, dynamic>.from(choice);
    copy.remove('function');
    if (name != null && name.isNotEmpty && copy['name'] == null) {
      copy['name'] = name;
    }
    return copy;
  }

  static Map<String, dynamic> functionTool(AgentTool tool) => {
    'type': 'function',
    'name': tool.name,
    'description': tool.description,
    'parameters': tool.parameters,
  };

  /// 构建 Responses API 请求体。不包含 `messages` 或嵌套的 `function` 工具对象。
  ///
  /// [maxTokens] 对应 Chat Completions 的 `max_tokens`，写出为 `max_output_tokens`。
  /// [previousResponseId] 仅在调用方已经持有上一轮响应 id 时传入，这里不生成新 id。
  static Map<String, dynamic> buildRequestBody({
    required String model,
    required List<AgentMessage> messages,
    required List<AgentTool> tools,
    double? temperature,
    double? topP,
    int? maxTokens,
    bool? stream,
    String? reasoningEffort,
    String? previousResponseId,
    Object? toolChoice,
    bool promptToolUse = false,
    bool includeTemperature = true,
  }) {
    final encoded = promptToolUse
        ? encodeChatMessages(PromptToolCodec.serialize(messages, tools))
        : encodeMessages(messages);
    final effort = reasoningEffort?.trim();
    final previous = previousResponseId?.trim();
    final sendTools = tools.isNotEmpty && !promptToolUse;
    return {
      'model': model.trim(),
      if (encoded.instructions.isNotEmpty) 'instructions': encoded.instructions,
      'input': encoded.input,
      if (sendTools) 'tools': tools.map(functionTool).toList(),
      if (sendTools) 'tool_choice': mapToolChoice(toolChoice ?? 'auto'),
      if (includeTemperature && temperature != null) 'temperature': temperature,
      'top_p': ?topP,
      if (maxTokens != null && maxTokens > 0) 'max_output_tokens': maxTokens,
      if (effort != null && effort.isNotEmpty)
        'reasoning': {'effort': effort, 'summary': 'auto'},
      if (previous != null && previous.isNotEmpty)
        'previous_response_id': previous
      else
        'store': false,
      'stream': ?stream,
    };
  }

  /// 把本应用消息编成 Responses `instructions` + `input`。
  static ({String instructions, List<Map<String, dynamic>> input})
  encodeMessages(List<AgentMessage> messages) {
    final instructionParts = <String>[];
    final input = <Map<String, dynamic>>[];
    // 待回应的 function_call 队列，用于给缺失 toolCallId 的工具结果回填 call_id。
    final pendingCallIds = <String>[];

    for (final (index, message) in messages.indexed) {
      switch (message.role) {
        case AgentRole.system:
          if (message.content.trim().isNotEmpty) {
            instructionParts.add(message.content);
          }
        case AgentRole.user:
          final content = <Map<String, dynamic>>[
            if (message.content.isNotEmpty)
              {'type': 'input_text', 'text': message.content},
            for (final image in message.images)
              if (image.base64.isNotEmpty)
                {'type': 'input_image', 'image_url': image.dataUrl},
          ];
          if (content.isNotEmpty) {
            input.add({'role': 'user', 'content': content});
          }
        case AgentRole.assistant:
          if (message.content.isNotEmpty) {
            input.add({
              'role': 'assistant',
              'content': [
                {'type': 'output_text', 'text': message.content},
              ],
            });
          }
          for (final (callIndex, call)
              in (message.toolCalls ?? const <ToolCall>[]).indexed) {
            // Responses 要求 call_id 非空，缺失时用稳定回退 id 保证输入可复现。
            final callId = call.id.isNotEmpty
                ? call.id
                : 'call_${index}_$callIndex';
            pendingCallIds.add(callId);
            input.add({
              'type': 'function_call',
              'call_id': callId,
              'name': call.name,
              'arguments': jsonEncode(call.arguments),
            });
          }
        case AgentRole.tool:
          final hasImage = message.hasVisionImages;
          var callId = message.toolCallId ?? '';
          if (callId.isEmpty) {
            // 回填最近的未回应调用，保证 function_call 与 output 成对。
            if (pendingCallIds.isNotEmpty) {
              callId = pendingCallIds.removeAt(0);
            }
          } else {
            pendingCallIds.remove(callId);
          }
          if (callId.isEmpty) {
            // 找不到可配对的调用时改发 user 文本，避免 call_id 为空导致 400。
            final fallbackText =
                '[工具 ${message.toolName} 结果] ${message.content}'.trim();
            final content = <Map<String, dynamic>>[
              {'type': 'input_text', 'text': fallbackText},
              if (hasImage)
                {
                  'type': 'input_image',
                  'image_url':
                      'data:${message.imageMimeType};base64,${message.imageBase64}',
                },
            ];
            if (content.length > 1 || fallbackText.isNotEmpty) {
              input.add({'role': 'user', 'content': content});
            }
            break;
          }
          final output = hasImage
              ? [
                  {
                    'type': 'input_text',
                    'text': message.content.isEmpty
                        ? '工具返回了图片。'
                        : message.content,
                  },
                  {
                    'type': 'input_image',
                    'image_url':
                        'data:${message.imageMimeType};base64,${message.imageBase64}',
                  },
                ]
              : message.content;
          input.add({
            'type': 'function_call_output',
            'call_id': callId,
            'output': output,
          });
      }
    }
    return (instructions: instructionParts.join('\n\n'), input: input);
  }

  /// 把 Chat Completions 形状的消息（含 developer / 嵌套 tool_calls / image_url 对象）
  /// 收成 Responses input。提示词工具模式复用这条路径。
  static ({String instructions, List<Map<String, dynamic>> input})
  encodeChatMessages(List<Map<String, dynamic>> messages) {
    final instructionParts = <String>[];
    final input = <Map<String, dynamic>>[];
    // 待回应的 function_call 队列，用于给缺失 tool_call_id 的工具结果回填 call_id。
    final pendingCallIds = <String>[];

    for (final (index, message) in messages.indexed) {
      final role = message['role'] as String? ?? '';
      if (isInstructionRole(role)) {
        final text = _plainText(message['content']);
        if (text.trim().isNotEmpty) instructionParts.add(text);
        continue;
      }
      if (role == 'tool') {
        final images = _imageUrls(message['content']);
        final text = _plainText(message['content']);
        var callId =
            (message['tool_call_id'] ?? message['call_id'] ?? '') as String;
        if (callId.isEmpty) {
          // 回填最近的未回应调用，保证 function_call 与 output 成对。
          if (pendingCallIds.isNotEmpty) {
            callId = pendingCallIds.removeAt(0);
          }
        } else {
          pendingCallIds.remove(callId);
        }
        if (callId.isEmpty) {
          // 找不到可配对的调用时改发 user 文本，避免 call_id 为空导致 400。
          final toolName = message['tool_name'] ?? message['name'] ?? '';
          final fallbackText = '[工具 $toolName 结果] $text'.trim();
          final content = <Map<String, dynamic>>[
            {'type': 'input_text', 'text': fallbackText},
            for (final url in images) {'type': 'input_image', 'image_url': url},
          ];
          if (content.length > 1 || fallbackText.isNotEmpty) {
            input.add({'role': 'user', 'content': content});
          }
          continue;
        }
        final output = images.isNotEmpty
            ? [
                {
                  'type': 'input_text',
                  'text': text.isEmpty ? '工具返回了图片。' : text,
                },
                for (final url in images)
                  {'type': 'input_image', 'image_url': url},
              ]
            : text;
        input.add({
          'type': 'function_call_output',
          'call_id': callId,
          'output': output,
        });
        continue;
      }
      if (role == 'assistant') {
        final text = _plainText(message['content']);
        if (text.isNotEmpty) {
          input.add({
            'role': 'assistant',
            'content': [
              {'type': 'output_text', 'text': text},
            ],
          });
        }
        final calls = message['tool_calls'];
        if (calls is List) {
          for (final (callIndex, call) in calls.indexed) {
            if (call is! Map) continue;
            final function = call['function'];
            final name = call['name'] is String
                ? call['name'] as String
                : function is Map && function['name'] is String
                ? function['name'] as String
                : '';
            if (name.isEmpty) continue;
            final rawArgs = function is Map
                ? function['arguments']
                : call['arguments'];
            final rawCallId = (call['call_id'] ?? call['id'] ?? '') as String;
            // Responses 要求 call_id 非空，缺失时用稳定回退 id 保证输入可复现。
            final callId = rawCallId.isNotEmpty
                ? rawCallId
                : 'call_${index}_$callIndex';
            pendingCallIds.add(callId);
            input.add({
              'type': 'function_call',
              'call_id': callId,
              'name': name,
              'arguments': _encodeArguments(rawArgs),
            });
          }
        }
        continue;
      }
      if (role == 'user') {
        final content = _userParts(message['content']);
        if (content.isNotEmpty) {
          input.add({'role': 'user', 'content': content});
        }
      }
    }
    return (instructions: instructionParts.join('\n\n'), input: input);
  }

  /// 非流式 Responses JSON。读取 `output` 里的 message / function_call / reasoning，
  /// 以及 `usage.input_tokens` / `usage.output_tokens`。
  static OpenAiResponsesCompletion parseResponse(Map<String, dynamic> json) {
    final root = _responseRoot(json);
    final error =
        _errorText(json) ?? (identical(root, json) ? null : _errorText(root));
    final status = root['status'];
    final usage = _usageOf(root) ?? _usageOf(json);
    if (status == 'incomplete') {
      // 截断响应无法还原完整工具调用，直接按失败处理。
      final details = root['incomplete_details'];
      final reason = details is Map ? details['reason'] : null;
      return OpenAiResponsesCompletion(
        error:
            'Responses API 响应不完整: ${reason is String && reason.isNotEmpty ? reason : 'unknown'}',
        usage: usage,
      );
    }
    final failed =
        status == 'failed' || (error != null && root['output'] is! List);
    if (failed) {
      return OpenAiResponsesCompletion(
        error: error ?? 'Responses API 请求失败',
        transientError: _isTransient(json) || _isTransient(root),
        usage: usage,
      );
    }
    final extracted = _readOutput(root['output']);
    if (extracted.callError != null) {
      return OpenAiResponsesCompletion(
        error: extracted.callError,
        usage: usage,
      );
    }
    if (extracted.text.isEmpty && extracted.refusal.isNotEmpty) {
      // 只有拒答没有正文时按失败处理，避免上层误判为空响应触发重试。
      return OpenAiResponsesCompletion(
        error: '模型拒绝回答: ${extracted.refusal}',
        usage: usage,
      );
    }
    return OpenAiResponsesCompletion(
      text: extracted.text,
      reasoning: extracted.reasoning,
      toolCalls: extracted.calls,
      usage: usage,
    );
  }

  /// `usage.input_tokens` 含缓存读时，按本应用互斥口径扣减。
  /// 没有 `input_tokens_details.cached_tokens` 时不把缺失伪装成 0。
  static TokenUsage? parseUsage(Map<String, dynamic> usage) {
    final inputRaw = usage['input_tokens'];
    final outputRaw = usage['output_tokens'];
    if (inputRaw is! num && outputRaw is! num) return null;
    int asCount(Object? value) =>
        value is num && value.isFinite && value > 0 ? value.toInt() : 0;
    final details = usage['input_tokens_details'];
    final cachedRaw = details is Map ? details['cached_tokens'] : null;
    final cacheRead = asCount(cachedRaw);
    final inputTotal = asCount(inputRaw);
    final uncached = inputTotal - cacheRead;
    return TokenUsage(
      input: uncached < 0 ? 0 : uncached,
      output: asCount(outputRaw),
      cacheRead: cacheRead,
      cacheReadReported:
          cachedRaw is num && cachedRaw.isFinite && cachedRaw >= 0,
    );
  }

  static Map<String, dynamic> _responseRoot(Map<String, dynamic> json) {
    if (json['output'] is List) return json;
    final nested = json['response'];
    if (nested is Map) return Map<String, dynamic>.from(nested);
    return json;
  }

  static TokenUsage? _usageOf(Map<String, dynamic> json) {
    final usage = json['usage'];
    if (usage is! Map) return null;
    return parseUsage(Map<String, dynamic>.from(usage));
  }

  static _OutputPieces _readOutput(Object? output) {
    final text = StringBuffer();
    final reasoning = StringBuffer();
    final refusal = StringBuffer();
    final calls = <ToolCall>[];
    String? callError;
    if (output is! List) {
      return _OutputPieces(text: '', reasoning: '', calls: const []);
    }
    for (var index = 0; index < output.length; index++) {
      final item = output[index];
      if (item is! Map) continue;
      final type = item['type'];
      switch (type) {
        case 'message':
          text.write(messageText(item['content']));
          refusal.write(refusalText(item['content']));
        case 'reasoning':
          reasoning.write(reasoningText(item['summary']));
        case 'function_call':
          final call = toolCallFromItem(
            Map<String, dynamic>.from(item),
            fallbackIndex: index,
          );
          if (call != null) {
            calls.add(call);
          } else if (item['name'] is String &&
              hasInvalidArguments(item['arguments'])) {
            callError = '工具调用参数不是合法 JSON: ${item['name']}';
          }
        default:
          break;
      }
    }
    if (callError != null) {
      return _OutputPieces(
        text: text.toString(),
        reasoning: reasoning.toString(),
        calls: const [],
        callError: callError,
      );
    }
    return _OutputPieces(
      text: text.toString(),
      reasoning: reasoning.toString(),
      refusal: refusal.toString(),
      calls: calls,
    );
  }

  /// 读取 message content 里的 `refusal` 部分。
  static String refusalText(Object? content) {
    if (content is! List) return '';
    final buffer = StringBuffer();
    for (final part in content) {
      if (part is! Map) continue;
      if (part['type'] != 'refusal') continue;
      final text = part['refusal'];
      if (text is String) buffer.write(text);
    }
    return buffer.toString();
  }

  static String messageText(Object? content) {
    if (content is String) return content;
    if (content is! List) return '';
    final buffer = StringBuffer();
    for (final part in content) {
      if (part is! Map) continue;
      if (part['type'] != 'output_text') continue;
      final text = part['text'];
      if (text is String) buffer.write(text);
    }
    return buffer.toString();
  }

  static String reasoningText(Object? summary) {
    if (summary is String) return summary;
    if (summary is! List) return '';
    final buffer = StringBuffer();
    for (final part in summary) {
      if (part is String) {
        buffer.write(part);
      } else if (part is Map) {
        final text = part['text'];
        if (text is String) buffer.write(text);
      }
    }
    return buffer.toString();
  }

  static ToolCall? toolCallFromItem(
    Map<String, dynamic> item, {
    required int fallbackIndex,
    String? argumentsOverride,
  }) {
    final name = item['name'];
    if (name is! String || name.isEmpty) return null;
    final callId = item['call_id'];
    final itemId = item['id'];
    final id = callId is String && callId.isNotEmpty
        ? callId
        : itemId is String && itemId.isNotEmpty
        ? itemId
        : 'call_$fallbackIndex';
    final rawArgs = argumentsOverride ?? item['arguments'];
    if (hasInvalidArguments(rawArgs)) return null;
    return ToolCall(id: id, name: name, arguments: decodeArguments(rawArgs));
  }

  /// 参数为非空字符串但不是合法 JSON 对象时返回 true（空串/缺失视为 {}）。
  static bool hasInvalidArguments(Object? raw) {
    if (raw is Map) return false;
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        return jsonDecode(raw) is! Map;
      } catch (_) {
        return true;
      }
    }
    return false;
  }

  static Map<String, dynamic> decodeArguments(Object? raw) {
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return decoded.map((key, value) => MapEntry(key.toString(), value));
        }
      } catch (_) {}
    }
    return {};
  }

  static String? _errorText(Map<String, dynamic> json) {
    final direct = _messageOf(json['error']);
    if (direct != null) return direct;
    if (json['type'] == 'error') {
      final message = json['message'];
      if (message is String && message.isNotEmpty) return message;
    }
    final response = json['response'];
    if (response is Map) {
      final nested = _messageOf(response['error']);
      if (nested != null) return nested;
      if (response['status'] == 'failed') {
        final message = response['message'];
        if (message is String && message.isNotEmpty) return message;
      }
    }
    return null;
  }

  static String? _messageOf(Object? error) {
    if (error is String && error.isNotEmpty) return error;
    if (error is Map) {
      final message = error['message'];
      if (message is String && message.isNotEmpty) return message;
    }
    return null;
  }

  static bool _isTransient(Map<String, dynamic> json) {
    final response = json['response'];
    final error = json['error'] ?? (response is Map ? response['error'] : null);
    // 顶层 error 事件的 code 在根对象上，不在 error 对象里。
    final code = error is Map
        ? '${error['code'] ?? json['code'] ?? ''}'.toLowerCase()
        : '${json['code'] ?? ''}'.toLowerCase();
    final message = (_messageOf(error) ?? '').toLowerCase();
    return code == '429' ||
        code == '500' ||
        code == '502' ||
        code == '503' ||
        code == '504' ||
        code == 'server_error' ||
        code == 'rate_limit_exceeded' ||
        message.contains('rate limit') ||
        message.contains('overloaded') ||
        message.contains('timeout');
  }

  static String _encodeArguments(Object? raw) {
    if (raw is String) return raw.isEmpty ? '{}' : raw;
    if (raw is Map) return jsonEncode(raw);
    return '{}';
  }

  static String _plainText(Object? content) {
    if (content is String) return content;
    if (content is! List) return '';
    final buffer = StringBuffer();
    for (final block in content) {
      if (block is! Map) continue;
      final type = block['type'];
      if (type == 'text' || type == 'input_text' || type == 'output_text') {
        final text = block['text'];
        if (text is String) buffer.write(text);
      }
    }
    return buffer.toString();
  }

  static List<String> _imageUrls(Object? content) {
    if (content is! List) return const [];
    final urls = <String>[];
    for (final block in content) {
      if (block is! Map) continue;
      final type = block['type'];
      if (type != 'image_url' && type != 'input_image') continue;
      final url = _imageUrlString(block['image_url']);
      if (url != null) urls.add(url);
    }
    return urls;
  }

  static List<Map<String, dynamic>> _userParts(Object? content) {
    if (content is String) {
      if (content.isEmpty) return const [];
      return [
        {'type': 'input_text', 'text': content},
      ];
    }
    if (content is! List) return const [];
    final parts = <Map<String, dynamic>>[];
    for (final block in content) {
      if (block is! Map) continue;
      final type = block['type'];
      if (type == 'text' || type == 'input_text') {
        final text = block['text'];
        if (text is String && text.isNotEmpty) {
          parts.add({'type': 'input_text', 'text': text});
        }
      } else if (type == 'image_url' || type == 'input_image') {
        final url = _imageUrlString(block['image_url']);
        if (url != null) {
          parts.add({'type': 'input_image', 'image_url': url});
        }
      }
    }
    return parts;
  }

  /// Responses 的 `image_url` 是字符串（data URL 或 http URL），不是 `{url: ...}`。
  static String? _imageUrlString(Object? imageUrl) {
    if (imageUrl is String && imageUrl.isNotEmpty) return imageUrl;
    if (imageUrl is Map) {
      final url = imageUrl['url'];
      if (url is String && url.isNotEmpty) return url;
    }
    return null;
  }
}

class _OutputPieces {
  final String text;
  final String reasoning;
  final String refusal;
  final List<ToolCall> calls;
  final String? callError;

  const _OutputPieces({
    required this.text,
    required this.reasoning,
    this.refusal = '',
    required this.calls,
    this.callError,
  });
}

/// 非流式解析结果。`error` 非空表示 `response.failed` 或顶层 error。
class OpenAiResponsesCompletion {
  final String text;
  final String reasoning;
  final List<ToolCall> toolCalls;
  final TokenUsage? usage;
  final String? error;
  final bool transientError;

  const OpenAiResponsesCompletion({
    this.text = '',
    this.reasoning = '',
    this.toolCalls = const [],
    this.usage,
    this.error,
    this.transientError = false,
  });

  bool get failed => error != null;
}

/// Responses SSE 解析。用量在 [finish] 时只提交一次。
class OpenAiResponsesStreamParser {
  final List<_StreamCall> _calls = [];
  TokenUsage? _usage;
  bool _usageEmitted = false;
  bool _unindexedText = false;
  bool _unindexedReasoning = false;
  final Set<int> _textIndexes = {};
  final Set<int> _reasoningIndexes = {};
  final StringBuffer _refusalDelta = StringBuffer();
  String? _refusalDone;
  String? _refusalFromItem;

  /// 综合流事件与消息体得到最终拒答文本，只取一路避免重复。
  String get _refusal {
    final done = _refusalDone;
    if (done != null && done.isNotEmpty) return done;
    final delta = _refusalDelta.toString();
    if (delta.isNotEmpty) return delta;
    return _refusalFromItem ?? '';
  }

  List<HarnessEvent> add(Map<String, dynamic> json, {String? eventType}) {
    _captureUsage(json);
    final type = (json['type'] as String?) ?? eventType ?? '';
    switch (type) {
      case 'response.output_text.delta':
        final delta = json['delta'];
        if (delta is String && delta.isNotEmpty) {
          _markText(_indexOf(json));
          return [ContentDeltaEvent(delta)];
        }
        return const [];
      case 'response.reasoning_summary_text.delta':
        final delta = json['delta'];
        if (delta is String && delta.isNotEmpty) {
          _markReasoning(_indexOf(json));
          return [ThoughtDeltaEvent(delta)];
        }
        return const [];
      case 'response.refusal.delta':
        final delta = json['delta'];
        if (delta is String && delta.isNotEmpty) _refusalDelta.write(delta);
        return const [];
      case 'response.refusal.done':
        final refusal = json['refusal'];
        if (refusal is String && refusal.isNotEmpty) _refusalDone = refusal;
        return const [];
      case 'response.output_item.added':
        _absorbFunction(json['item'], index: _indexOf(json));
        return const [];
      case 'response.function_call_arguments.delta':
        final state = _matchCall(
          index: _indexOf(json),
          itemId: json['item_id'] as String?,
        );
        final delta = json['delta'];
        if (delta is String && delta.isNotEmpty) state.arguments.write(delta);
        return const [];
      case 'response.function_call_arguments.done':
        final state = _matchCall(
          index: _indexOf(json),
          itemId: json['item_id'] as String?,
        );
        final arguments = json['arguments'];
        if (arguments is String && arguments.isNotEmpty) {
          state.fullArguments = arguments;
        }
        return const [];
      case 'response.output_item.done':
        return _eventsFromItem(
          json['item'],
          index: _indexOf(json),
          onlyIfMissing: true,
        );
      case 'response.completed':
        final response = json['response'];
        if (response is! Map) return const [];
        final events = <HarnessEvent>[];
        final output = response['output'];
        if (output is List) {
          for (var index = 0; index < output.length; index++) {
            events.addAll(
              _eventsFromItem(output[index], index: index, onlyIfMissing: true),
            );
          }
        }
        return events;
      case 'response.incomplete':
        final response = json['response'];
        final details = response is Map
            ? response['incomplete_details']
            : json['incomplete_details'];
        final reason = details is Map ? details['reason'] : null;
        return [
          ErrorEvent(
            'Responses API 响应不完整: ${reason is String && reason.isNotEmpty ? reason : 'unknown'}',
          ),
        ];
      case 'response.failed':
      case 'error':
        return [
          ErrorEvent(
            OpenAiResponses._errorText(json) ?? 'Responses API 请求失败',
            transient: OpenAiResponses._isTransient(json),
          ),
        ];
      default:
        if (json['error'] != null) {
          return [
            ErrorEvent(
              OpenAiResponses._errorText(json) ?? 'Responses API 请求失败',
              transient: OpenAiResponses._isTransient(json),
            ),
          ];
        }
        return const [];
    }
  }

  /// 冲刷尚未完成的工具调用，报告拒答，并提交唯一一次用量快照。
  List<HarnessEvent> finish() {
    final events = <HarnessEvent>[];
    final refusal = _refusal;
    if (refusal.isNotEmpty) {
      events.add(ErrorEvent('模型拒绝回答: $refusal'));
    }
    for (final state in _calls) {
      final event = _emitCall(state, strictArguments: false);
      if (event != null) events.add(event);
    }
    if (!_usageEmitted && _usage != null && _usage!.total > 0) {
      _usageEmitted = true;
      events.add(UsageEvent(_usage!));
    }
    return events;
  }

  void _captureUsage(Map<String, dynamic> json) {
    final direct = OpenAiResponses._usageOf(json);
    if (direct != null) _usage = direct;
    final response = json['response'];
    if (response is Map) {
      final nested = OpenAiResponses._usageOf(
        Map<String, dynamic>.from(response),
      );
      if (nested != null) _usage = nested;
    }
  }

  int? _indexOf(Map<String, dynamic> json) =>
      (json['output_index'] as num?)?.toInt();

  void _markText(int? index) {
    if (index == null) {
      _unindexedText = true;
    } else {
      _textIndexes.add(index);
    }
  }

  void _markReasoning(int? index) {
    if (index == null) {
      _unindexedReasoning = true;
    } else {
      _reasoningIndexes.add(index);
    }
  }

  bool _textSeen(int? index) =>
      _unindexedText ||
      _textIndexes.isNotEmpty &&
          (index == null || _textIndexes.contains(index));

  bool _reasoningSeen(int? index) =>
      _unindexedReasoning ||
      _reasoningIndexes.isNotEmpty &&
          (index == null || _reasoningIndexes.contains(index));

  List<HarnessEvent> _eventsFromItem(
    Object? raw, {
    required int? index,
    required bool onlyIfMissing,
  }) {
    if (raw is! Map) return const [];
    final item = Map<String, dynamic>.from(raw);
    switch (item['type']) {
      case 'message':
        if (_refusalDone == null && _refusalDelta.isEmpty) {
          final refusal = OpenAiResponses.refusalText(item['content']);
          if (refusal.isNotEmpty) _refusalFromItem = refusal;
        }
        if (onlyIfMissing && _textSeen(index)) return const [];
        final text = OpenAiResponses.messageText(item['content']);
        if (text.isEmpty) return const [];
        _markText(index);
        return [ContentDeltaEvent(text)];
      case 'reasoning':
        if (onlyIfMissing && _reasoningSeen(index)) return const [];
        final text = OpenAiResponses.reasoningText(item['summary']);
        if (text.isEmpty) return const [];
        _markReasoning(index);
        return [ThoughtDeltaEvent(text)];
      case 'function_call':
        final state = _absorbFunction(item, index: index);
        if (state == null) return const [];
        final event = _emitCall(state, strictArguments: true);
        return event == null ? const [] : [event];
      default:
        return const [];
    }
  }

  _StreamCall? _absorbFunction(Object? raw, {required int? index}) {
    if (raw is! Map) return null;
    final item = Map<String, dynamic>.from(raw);
    if (item['type'] != null && item['type'] != 'function_call') return null;
    final callId = item['call_id'] as String?;
    final itemId = item['id'] as String?;
    final state = _matchCall(index: index, itemId: itemId, callId: callId);
    if (index != null) state.outputIndex = index;
    if (itemId != null && itemId.isNotEmpty) state.itemId = itemId;
    if (callId != null && callId.isNotEmpty) state.callId = callId;
    final name = item['name'];
    if (name is String && name.isNotEmpty) state.name = name;
    final arguments = item['arguments'];
    if (arguments is String && arguments.isNotEmpty) {
      state.fullArguments = arguments;
    } else if (arguments is Map) {
      state.fullArguments = jsonEncode(arguments);
    }
    return state;
  }

  _StreamCall _matchCall({int? index, String? itemId, String? callId}) {
    for (final state in _calls) {
      if (index != null && state.outputIndex == index) return state;
      if (itemId != null && itemId.isNotEmpty && state.itemId == itemId) {
        return state;
      }
      if (callId != null && callId.isNotEmpty && state.callId == callId) {
        return state;
      }
    }
    final created = _StreamCall(
      outputIndex: index,
      itemId: itemId,
      callId: callId ?? '',
    );
    _calls.add(created);
    return created;
  }

  /// [strictArguments] 为 true（参数来自权威的 done/completed 事件）时，
  /// 非法 JSON 参数产生非瞬态错误；为 false（finish 冲刷残缺调用）时跳过该调用，
  /// 由上层报告流提前结束。
  HarnessEvent? _emitCall(_StreamCall state, {bool strictArguments = false}) {
    if (state.emitted || state.name.isEmpty) return null;
    state.emitted = true;
    final item = <String, dynamic>{
      'name': state.name,
      if (state.callId.isNotEmpty) 'call_id': state.callId,
      if (state.itemId != null) 'id': state.itemId,
    };
    if (strictArguments &&
        OpenAiResponses.hasInvalidArguments(state.resolvedArguments)) {
      return ErrorEvent('工具调用参数不是合法 JSON: ${state.name}');
    }
    final call = OpenAiResponses.toolCallFromItem(
      item,
      fallbackIndex: state.outputIndex ?? _calls.indexOf(state),
      argumentsOverride: state.resolvedArguments,
    );
    if (call == null) return null;
    return ToolCallEvent(call);
  }
}

class _StreamCall {
  int? outputIndex;
  String? itemId;
  String callId;
  String name = '';
  final StringBuffer arguments = StringBuffer();
  String? fullArguments;
  bool emitted = false;

  _StreamCall({this.outputIndex, this.itemId, this.callId = ''});

  String get resolvedArguments => fullArguments ?? arguments.toString();
}
