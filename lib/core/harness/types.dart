import 'dart:convert';

/// Token 用量 (对齐 Pi 的 Usage 结构，cost 由账单服务另行估算)
class TokenUsage {
  final int input;
  final int output;
  final int cacheRead;
  final int cacheWrite;

  const TokenUsage({
    this.input = 0,
    this.output = 0,
    this.cacheRead = 0,
    this.cacheWrite = 0,
  });

  int get total => input + output + cacheRead + cacheWrite;

  /// 缓存命中率 (缓存读 / 总输入)。总输入为 0 时返回 null。
  /// 口径与 pi 的 footer CH 标记一致：cached input / total input。
  double? get cacheHitRate => input > 0 ? cacheRead / input : null;

  TokenUsage add(TokenUsage other) => TokenUsage(
    input: input + other.input,
    output: output + other.output,
    cacheRead: cacheRead + other.cacheRead,
    cacheWrite: cacheWrite + other.cacheWrite,
  );

  Map<String, dynamic> toJson() => {
    'input': input,
    'output': output,
    'cacheRead': cacheRead,
    'cacheWrite': cacheWrite,
  };

  factory TokenUsage.fromJson(dynamic json) {
    if (json is! Map) return const TokenUsage();
    int asInt(dynamic v) => v is num ? v.toInt() : 0;
    return TokenUsage(
      input: asInt(json['input']) + asInt(json['prompt_tokens']),
      output: asInt(json['output']) + asInt(json['completion_tokens']),
      cacheRead:
          asInt(json['cacheRead']) +
          asInt(json['prompt_cache_hit_tokens']) +
          asInt(
            json['prompt_tokens_details'] is Map
                ? (json['prompt_tokens_details'] as Map)['cached_tokens']
                : null,
          ),
      cacheWrite: asInt(json['cacheWrite']),
    );
  }
}

/// 对话角色
enum AgentRole {
  system('system'),
  user('user'),
  assistant('assistant'),
  tool('tool');

  final String value;
  const AgentRole(this.value);
}

/// 工具调用定义
class ToolCall {
  final String id;
  final String name;
  final Map<String, dynamic> arguments;

  const ToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  Map<String, dynamic> toOpenAiJson() {
    return {
      'id': id,
      'type': 'function',
      'function': {'name': name, 'arguments': jsonEncode(arguments)},
    };
  }
}

/// 工具执行结果
class ToolResult {
  final String toolCallId;
  final String toolName;
  final String content;
  final bool isError;

  const ToolResult({
    required this.toolCallId,
    this.toolName = '',
    required this.content,
    this.isError = false,
  });
}

/// 对话单条消息
class AgentMessage {
  final String id;
  final AgentRole role;
  final String content;
  final String thoughts; // 思考过程 (Reasoning / Thinking)
  final List<ToolCall>? toolCalls;
  final String? toolCallId;
  final String? toolName; // 工具结果消息对应的工具名 (仅 role == tool)
  final bool isError; // 工具结果是否出错 (仅 role == tool)
  final TokenUsage? usage; // 本条 assistant 消息的 Token 用量
  final String? provider; // 产生本条消息的供应商标识 (仅 assistant)
  final String? model; // 产生本条消息的模型 ID (仅 assistant)
  final bool isStreaming;
  final DateTime createdAt;

  /// "provider/model" 聚合键 (用量统计用)
  String? get providerModelKey =>
      (provider == null || provider!.isEmpty || model == null || model!.isEmpty)
      ? null
      : '$provider/$model';

  AgentMessage({
    required this.id,
    required this.role,
    this.content = '',
    this.thoughts = '',
    this.toolCalls,
    this.toolCallId,
    this.toolName,
    this.isError = false,
    this.usage,
    this.provider,
    this.model,
    this.isStreaming = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  AgentMessage copyWith({
    String? id,
    AgentRole? role,
    String? content,
    String? thoughts,
    List<ToolCall>? toolCalls,
    String? toolCallId,
    String? toolName,
    bool? isError,
    TokenUsage? usage,
    String? provider,
    String? model,
    bool? isStreaming,
    DateTime? createdAt,
  }) {
    return AgentMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
      thoughts: thoughts ?? this.thoughts,
      toolCalls: toolCalls ?? this.toolCalls,
      toolCallId: toolCallId ?? this.toolCallId,
      toolName: toolName ?? this.toolName,
      isError: isError ?? this.isError,
      usage: usage ?? this.usage,
      provider: provider ?? this.provider,
      model: model ?? this.model,
      isStreaming: isStreaming ?? this.isStreaming,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toOpenAiJson() {
    final map = <String, dynamic>{'role': role.value, 'content': content};
    if (toolCalls != null && toolCalls!.isNotEmpty) {
      map['tool_calls'] = toolCalls!.map((t) => t.toOpenAiJson()).toList();
    }
    if (toolCallId != null) {
      map['tool_call_id'] = toolCallId;
    }
    return map;
  }
}

/// Harness 事件抽象
sealed class HarnessEvent {}

class TurnStartEvent extends HarnessEvent {
  final String messageId;
  TurnStartEvent(this.messageId);
}

class ThoughtDeltaEvent extends HarnessEvent {
  final String delta;
  ThoughtDeltaEvent(this.delta);
}

class ContentDeltaEvent extends HarnessEvent {
  final String delta;
  ContentDeltaEvent(this.delta);
}

class ToolCallEvent extends HarnessEvent {
  final ToolCall toolCall;
  ToolCallEvent(this.toolCall);
}

class ToolResultEvent extends HarnessEvent {
  final ToolResult result;
  ToolResultEvent(this.result);
}

class UsageEvent extends HarnessEvent {
  final TokenUsage usage;
  UsageEvent(this.usage);
}

class TurnEndEvent extends HarnessEvent {
  final AgentMessage finalMessage;
  TurnEndEvent(this.finalMessage);
}

class ErrorEvent extends HarnessEvent {
  final String error;
  ErrorEvent(this.error);
}
