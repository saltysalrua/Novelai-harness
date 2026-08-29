import 'dart:convert';

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
      'function': {
        'name': name,
        'arguments': jsonEncode(arguments),
      },
    };
  }
}

/// 工具执行结果
class ToolResult {
  final String toolCallId;
  final String content;
  final bool isError;

  const ToolResult({
    required this.toolCallId,
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
  final bool isStreaming;
  final DateTime createdAt;

  AgentMessage({
    required this.id,
    required this.role,
    this.content = '',
    this.thoughts = '',
    this.toolCalls,
    this.toolCallId,
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
      isStreaming: isStreaming ?? this.isStreaming,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toOpenAiJson() {
    final map = <String, dynamic>{
      'role': role.value,
      'content': content,
    };
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

class TurnEndEvent extends HarnessEvent {
  final AgentMessage finalMessage;
  TurnEndEvent(this.finalMessage);
}

class ErrorEvent extends HarnessEvent {
  final String error;
  ErrorEvent(this.error);
}
