import 'dart:convert';

import '../tools/agent_tool.dart';
import '../types.dart';
import 'prompt_tool_codec.dart';

/// Anthropic Messages API (`POST /v1/messages`) 的请求体与响应解析。
///
/// 思考开启时，历史 assistant 必须先回放 `thinking`（含 signature）和
/// `redacted_thinking`，再跟 text 与 tool_use；工具结果放在随后的 user
/// `tool_result` 里。签名和 redacted data 原样保留，不重排、不丢弃。
class AnthropicMessages {
  static int thinkingBudget(String? effort) {
    return switch (effort?.trim()) {
      'minimal' || 'low' => 1024,
      'high' || 'xhigh' || 'max' => 16384,
      _ => 4096,
    };
  }

  static Map<String, dynamic> buildRequestBody({
    required String model,
    required List<AgentMessage> messages,
    required List<AgentTool> tools,
    double? temperature,
    bool stream = true,
    bool reasoning = false,
    String? thinkingEffort,
    bool promptToolUse = false,
  }) {
    final budget = thinkingBudget(thinkingEffort);
    // budget_tokens 必须小于 max_tokens。
    final maxTokens = reasoning ? budget + 4096 : 8192;
    final encoded = promptToolUse
        ? encodeChatMessages(PromptToolCodec.serialize(messages, tools))
        : encodeMessages(messages);
    final sendTools = tools.isNotEmpty && !promptToolUse;
    return {
      'model': model.trim(),
      'max_tokens': maxTokens,
      if (encoded.system.isNotEmpty) 'system': encoded.system,
      'messages': encoded.messages,
      if (sendTools)
        'tools': [
          for (final tool in tools)
            {
              'name': tool.name,
              'description': tool.description,
              'input_schema': tool.parameters,
            },
        ],
      if (sendTools) 'tool_choice': {'type': 'auto'},
      if (reasoning) 'thinking': {'type': 'enabled', 'budget_tokens': budget},
      // 开启 thinking 时 temperature 只能是 1，省略以免 400。
      if (!reasoning && temperature != null) 'temperature': temperature,
      'stream': stream,
    };
  }

  static ({String system, List<Map<String, dynamic>> messages}) encodeMessages(
    List<AgentMessage> messages,
  ) {
    final systemParts = <String>[];
    final encoded = <Map<String, dynamic>>[];
    final pendingResults = <Map<String, dynamic>>[];

    void flushResults() {
      if (pendingResults.isEmpty) return;
      encoded.add({
        'role': 'user',
        'content': [for (final block in pendingResults) block],
      });
      pendingResults.clear();
    }

    for (final message in messages) {
      switch (message.role) {
        case AgentRole.system:
          if (message.content.trim().isNotEmpty) {
            systemParts.add(message.content);
          }
        case AgentRole.user:
          flushResults();
          final content = _userContent(message);
          if (content.isNotEmpty) {
            encoded.add({'role': 'user', 'content': content});
          }
        case AgentRole.assistant:
          flushResults();
          final blocks = assistantBlocks(message);
          if (blocks.isNotEmpty) {
            encoded.add({'role': 'assistant', 'content': blocks});
          }
        case AgentRole.tool:
          pendingResults.add(_toolResult(message));
      }
    }
    flushResults();
    return (system: systemParts.join('\n\n'), messages: encoded);
  }

  /// 提示词工具模式把对话收成纯文本，不发送 tool_use。
  static ({String system, List<Map<String, dynamic>> messages})
  encodeChatMessages(List<Map<String, dynamic>> messages) {
    final systemParts = <String>[];
    final encoded = <Map<String, dynamic>>[];
    for (final message in messages) {
      final role = message['role'] as String? ?? '';
      final text = _plainText(message['content']);
      if (role == 'system' || role == 'developer') {
        if (text.trim().isNotEmpty) systemParts.add(text);
        continue;
      }
      if (text.isEmpty) continue;
      final anthropicRole = role == 'assistant' ? 'assistant' : 'user';
      encoded.add({
        'role': anthropicRole,
        'content': [
          {'type': 'text', 'text': text},
        ],
      });
    }
    return (system: systemParts.join('\n\n'), messages: encoded);
  }

  /// thinking / redacted_thinking 在 text 与 tool_use 之前，顺序与保存时一致。
  static List<Map<String, dynamic>> assistantBlocks(AgentMessage message) {
    final blocks = <Map<String, dynamic>>[];
    if (message.reasoningRecords.isNotEmpty) {
      for (final record in message.reasoningRecords) {
        final block = record.toAnthropicBlock();
        if (block != null) blocks.add(block);
      }
      _attachMessageSignature(blocks, message.thoughtSignature);
    } else if (message.thoughts.isNotEmpty ||
        (message.thoughtSignature != null &&
            message.thoughtSignature!.isNotEmpty)) {
      blocks.add({
        'type': 'thinking',
        'thinking': message.thoughts,
        if (message.thoughtSignature != null &&
            message.thoughtSignature!.isNotEmpty)
          'signature': message.thoughtSignature,
      });
    }
    if (message.content.isNotEmpty) {
      blocks.add({'type': 'text', 'text': message.content});
    }
    final calls = message.toolCalls ?? const <ToolCall>[];
    for (var index = 0; index < calls.length; index++) {
      final call = calls[index];
      blocks.add({
        'type': 'tool_use',
        'id': call.id.isNotEmpty ? call.id : 'toolu_$index',
        'name': call.name,
        'input': call.arguments,
      });
    }
    return blocks;
  }

  static void _attachMessageSignature(
    List<Map<String, dynamic>> blocks,
    String? signature,
  ) {
    if (signature == null || signature.isEmpty) return;
    for (final block in blocks) {
      final existing = block['signature'];
      if (block['type'] == 'thinking' &&
          existing is String &&
          existing.isNotEmpty) {
        return;
      }
    }
    for (final block in blocks) {
      if (block['type'] == 'thinking') {
        block['signature'] = signature;
        return;
      }
    }
  }

  static List<Map<String, dynamic>> _userContent(AgentMessage message) {
    return [
      if (message.content.isNotEmpty) {'type': 'text', 'text': message.content},
      for (final image in message.images)
        if (image.base64.isNotEmpty)
          {
            'type': 'image',
            'source': {
              'type': 'base64',
              'media_type': image.mimeType,
              'data': image.base64,
            },
          },
    ];
  }

  static Map<String, dynamic> _toolResult(AgentMessage message) {
    final hasImage =
        message.imageBase64 != null && message.imageBase64!.isNotEmpty;
    final output = hasImage
        ? [
            {
              'type': 'text',
              'text': message.content.isEmpty ? '工具返回了图片。' : message.content,
            },
            {
              'type': 'image',
              'source': {
                'type': 'base64',
                'media_type': message.imageMimeType,
                'data': message.imageBase64,
              },
            },
          ]
        : message.content;
    return {
      'type': 'tool_result',
      'tool_use_id': message.toolCallId ?? '',
      'content': output,
      if (message.isError) 'is_error': true,
    };
  }

  static String _plainText(Object? content) {
    if (content is String) return content;
    if (content is! List) return '';
    final buffer = StringBuffer();
    for (final part in content) {
      if (part is String) {
        buffer.write(part);
      } else if (part is Map) {
        final text = part['text'] ?? part['content'];
        if (text is String) buffer.write(text);
      }
    }
    return buffer.toString();
  }

  static AnthropicMessagesCompletion parseResponse(Map<String, dynamic> json) {
    final error = _errorText(json);
    if (error != null && json['content'] is! List) {
      return AnthropicMessagesCompletion(
        error: error,
        transientError: _isTransient(json),
      );
    }
    final content = json['content'];
    final text = StringBuffer();
    final reasoning = StringBuffer();
    final records = <ReasoningRecord>[];
    final calls = <ToolCall>[];
    if (content is List) {
      for (var index = 0; index < content.length; index++) {
        final block = content[index];
        if (block is! Map) continue;
        final item = Map<String, dynamic>.from(block);
        switch (item['type']) {
          case 'thinking':
            final record = _thinkingRecord(item);
            if (!record.isEmpty) records.add(record);
            final thinking = item['thinking'];
            if (thinking is String && thinking.isNotEmpty) {
              reasoning.write(thinking);
            }
          case 'redacted_thinking':
            final data = item['data'];
            if (data is String && data.isNotEmpty) {
              records.add(ReasoningRecord(redactedData: data));
            }
          case 'text':
            final value = item['text'];
            if (value is String) text.write(value);
          case 'tool_use':
            final call = _toolCall(item, index);
            if (call != null) calls.add(call);
        }
      }
    }
    final usage = json['usage'];
    return AnthropicMessagesCompletion(
      text: text.toString(),
      reasoning: reasoning.toString(),
      reasoningRecords: records,
      toolCalls: calls,
      usage: usage is Map ? parseUsage(Map<String, dynamic>.from(usage)) : null,
    );
  }

  static ReasoningRecord _thinkingRecord(Map<String, dynamic> block) {
    final thinking = block['thinking'];
    final signature = block['signature'];
    return ReasoningRecord(
      content: thinking is String && thinking.isNotEmpty
          ? [
              {'type': 'reasoning_text', 'text': thinking},
            ]
          : const [],
      signature: signature is String && signature.isNotEmpty ? signature : null,
    );
  }

  static ToolCall? _toolCall(Map<String, dynamic> block, int index) {
    final name = block['name'];
    if (name is! String || name.isEmpty) return null;
    final rawId = block['id'];
    final id = rawId is String && rawId.isNotEmpty ? rawId : 'toolu_$index';
    final input = block['input'];
    Map<String, dynamic> arguments = {};
    if (input is Map) {
      arguments = Map<String, dynamic>.from(input);
    } else if (input is String && input.isNotEmpty) {
      try {
        final decoded = jsonDecode(input);
        if (decoded is Map) arguments = Map<String, dynamic>.from(decoded);
      } catch (_) {
        return null;
      }
    }
    return ToolCall(id: id, name: name, arguments: arguments);
  }

  static TokenUsage? parseUsage(Map<String, dynamic> usage) {
    final inputRaw = usage['input_tokens'];
    final outputRaw = usage['output_tokens'];
    if (inputRaw is! num && outputRaw is! num) return null;
    int asCount(Object? value) =>
        value is num && value.isFinite && value > 0 ? value.toInt() : 0;
    final rawRead = usage['cache_read_input_tokens'];
    final rawWrite = usage['cache_creation_input_tokens'];
    return TokenUsage(
      input: asCount(inputRaw),
      output: asCount(outputRaw),
      cacheRead: asCount(rawRead),
      cacheWrite: asCount(rawWrite),
      cacheReadReported: rawRead is num && rawRead.isFinite && rawRead >= 0,
    );
  }

  static String? _errorText(Map<String, dynamic> json) {
    final error = json['error'];
    if (error is String && error.isNotEmpty) return error;
    if (error is Map) {
      final message = error['message'];
      if (message is String && message.isNotEmpty) return message;
    }
    if (json['type'] == 'error') {
      final message = json['message'];
      if (message is String && message.isNotEmpty) return message;
    }
    return null;
  }

  static bool _isTransient(Map<String, dynamic> json) {
    final error = json['error'];
    final type = error is Map ? error['type']?.toString() : null;
    return type == 'overloaded_error' ||
        type == 'rate_limit_error' ||
        type == 'api_error' ||
        type == 'timeout_error';
  }
}

class AnthropicMessagesCompletion {
  final String text;
  final String reasoning;
  final List<ReasoningRecord> reasoningRecords;
  final List<ToolCall> toolCalls;
  final TokenUsage? usage;
  final String? error;
  final bool transientError;

  const AnthropicMessagesCompletion({
    this.text = '',
    this.reasoning = '',
    this.reasoningRecords = const [],
    this.toolCalls = const [],
    this.usage,
    this.error,
    this.transientError = false,
  });

  bool get failed => error != null;
}

/// Anthropic SSE：thinking_delta、signature_delta、redacted_thinking、tool_use。
class AnthropicMessagesStreamParser {
  final Map<int, _AnthropicBlock> _blocks = {};
  TokenUsage? _usage;
  bool _usageEmitted = false;

  List<HarnessEvent> add(Map<String, dynamic> json, {String? eventType}) {
    _captureUsage(json);
    final type = (json['type'] as String?) ?? eventType ?? '';
    switch (type) {
      case 'content_block_start':
        return _onStart(json);
      case 'content_block_delta':
        return _onDelta(json);
      case 'content_block_stop':
        return _onStop(json);
      case 'error':
        return [
          ErrorEvent(
            AnthropicMessages._errorText(json) ?? 'Anthropic Messages 请求失败',
            transient: AnthropicMessages._isTransient(json),
          ),
        ];
      case 'message_start':
      case 'message_delta':
      case 'message_stop':
      case 'ping':
        return const [];
      default:
        if (json['error'] != null) {
          return [
            ErrorEvent(
              AnthropicMessages._errorText(json) ?? 'Anthropic Messages 请求失败',
              transient: AnthropicMessages._isTransient(json),
            ),
          ];
        }
        return const [];
    }
  }

  List<HarnessEvent> finish() {
    final events = <HarnessEvent>[];
    final records = <ReasoningRecord>[];
    final indexes = _blocks.keys.toList()..sort();
    for (final index in indexes) {
      final block = _blocks[index]!;
      final record = block.toRecord();
      if (record != null && !record.isEmpty) records.add(record);
      if (block.type == 'tool_use' && !block.emitted) {
        final event = block.emitCall(index, strict: false);
        if (event != null) events.add(event);
      }
    }
    if (records.isNotEmpty) {
      events.insert(0, ReasoningSnapshotEvent(records));
    }
    if (!_usageEmitted && _usage != null && _usage!.total > 0) {
      _usageEmitted = true;
      events.add(UsageEvent(_usage!));
    }
    return events;
  }

  List<HarnessEvent> _onStart(Map<String, dynamic> json) {
    final index = (json['index'] as num?)?.toInt() ?? _blocks.length;
    final raw = json['content_block'];
    if (raw is! Map) return const [];
    final block = _blocks.putIfAbsent(index, _AnthropicBlock.new);
    return block.absorbStart(Map<String, dynamic>.from(raw));
  }

  List<HarnessEvent> _onDelta(Map<String, dynamic> json) {
    final index = (json['index'] as num?)?.toInt() ?? 0;
    final raw = json['delta'];
    if (raw is! Map) return const [];
    final block = _blocks.putIfAbsent(index, _AnthropicBlock.new);
    return block.absorbDelta(Map<String, dynamic>.from(raw));
  }

  List<HarnessEvent> _onStop(Map<String, dynamic> json) {
    final index = (json['index'] as num?)?.toInt();
    if (index == null) return const [];
    final block = _blocks[index];
    if (block == null || block.type != 'tool_use' || block.emitted) {
      return const [];
    }
    final event = block.emitCall(index, strict: true);
    return event == null ? const [] : [event];
  }

  void _captureUsage(Map<String, dynamic> json) {
    final direct = json['usage'];
    if (direct is Map) {
      _mergeUsage(Map<String, dynamic>.from(direct));
    }
    final message = json['message'];
    if (message is Map) {
      final nested = message['usage'];
      if (nested is Map) _mergeUsage(Map<String, dynamic>.from(nested));
    }
  }

  void _mergeUsage(Map<String, dynamic> usage) {
    final parsed = AnthropicMessages.parseUsage(usage);
    if (parsed == null) return;
    final prev = _usage;
    if (prev == null) {
      _usage = parsed;
      return;
    }
    _usage = TokenUsage(
      input: parsed.input > 0 ? parsed.input : prev.input,
      output: parsed.output > 0 ? parsed.output : prev.output,
      cacheRead: parsed.cacheReadReported ? parsed.cacheRead : prev.cacheRead,
      cacheWrite: parsed.cacheWrite > 0 ? parsed.cacheWrite : prev.cacheWrite,
      cacheReadReported: parsed.cacheReadReported || prev.cacheReadReported,
    );
  }
}

class _AnthropicBlock {
  String type = '';
  final StringBuffer text = StringBuffer();
  String? signature;
  String? redactedData;
  String id = '';
  String name = '';
  final StringBuffer arguments = StringBuffer();
  Map<String, dynamic>? parsedArguments;
  bool emitted = false;

  List<HarnessEvent> absorbStart(Map<String, dynamic> block) {
    final rawType = block['type'];
    if (rawType is String && rawType.isNotEmpty) type = rawType;
    final events = <HarnessEvent>[];
    switch (type) {
      case 'thinking':
        final thinking = block['thinking'];
        if (thinking is String && thinking.isNotEmpty && text.isEmpty) {
          text.write(thinking);
          events.add(ThoughtDeltaEvent(thinking));
        }
        final sig = block['signature'];
        if (sig is String && sig.isNotEmpty) {
          signature = sig;
          events.add(ThoughtSignatureEvent(sig));
        }
      case 'redacted_thinking':
        final data = block['data'];
        if (data is String && data.isNotEmpty) redactedData = data;
      case 'text':
        final value = block['text'];
        if (value is String && value.isNotEmpty && text.isEmpty) {
          text.write(value);
          events.add(ContentDeltaEvent(value));
        }
      case 'tool_use':
        final rawId = block['id'];
        if (rawId is String && rawId.isNotEmpty) id = rawId;
        final rawName = block['name'];
        if (rawName is String && rawName.isNotEmpty) name = rawName;
        final input = block['input'];
        if (input is Map && input.isNotEmpty) {
          parsedArguments = Map<String, dynamic>.from(input);
        }
    }
    return events;
  }

  List<HarnessEvent> absorbDelta(Map<String, dynamic> delta) {
    final deltaType = delta['type'] as String? ?? '';
    switch (deltaType) {
      case 'thinking_delta':
        type = type.isEmpty ? 'thinking' : type;
        final thinking = delta['thinking'];
        if (thinking is String && thinking.isNotEmpty) {
          text.write(thinking);
          return [ThoughtDeltaEvent(thinking)];
        }
        return const [];
      case 'signature_delta':
        type = type.isEmpty ? 'thinking' : type;
        final sig = delta['signature'];
        if (sig is String && sig.isNotEmpty) {
          signature = sig;
          return [ThoughtSignatureEvent(sig)];
        }
        return const [];
      case 'text_delta':
        type = type.isEmpty ? 'text' : type;
        final value = delta['text'];
        if (value is String && value.isNotEmpty) {
          text.write(value);
          return [ContentDeltaEvent(value)];
        }
        return const [];
      case 'input_json_delta':
        type = 'tool_use';
        final partial = delta['partial_json'];
        if (partial is String && partial.isNotEmpty) arguments.write(partial);
        return const [];
      default:
        return const [];
    }
  }

  ReasoningRecord? toRecord() {
    if (type == 'redacted_thinking') {
      final data = redactedData;
      if (data == null || data.isEmpty) return null;
      return ReasoningRecord(redactedData: data);
    }
    if (type != 'thinking') return null;
    final value = text.toString();
    return ReasoningRecord(
      content: value.isNotEmpty
          ? [
              {'type': 'reasoning_text', 'text': value},
            ]
          : const [],
      signature: signature,
    );
  }

  HarnessEvent? emitCall(int index, {required bool strict}) {
    if (emitted || name.isEmpty) return null;
    emitted = true;
    Map<String, dynamic> arguments = parsedArguments ?? {};
    if (arguments.isEmpty && this.arguments.isNotEmpty) {
      final raw = this.arguments.toString();
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          arguments = Map<String, dynamic>.from(decoded);
        } else if (strict) {
          return ErrorEvent('工具调用参数不是合法 JSON: $name');
        }
      } catch (_) {
        if (strict) return ErrorEvent('工具调用参数不是合法 JSON: $name');
        return null;
      }
    }
    return ToolCallEvent(
      ToolCall(
        id: id.isNotEmpty ? id : 'toolu_$index',
        name: name,
        arguments: arguments,
      ),
    );
  }
}
