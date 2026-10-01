import '../types.dart';

/// 请求侧修复空/非法/重复 ID，并同步配对结果；不改写 UI 或磁盘历史。
/// Claude 的兼容网关要求整个请求中的 tool_use ID 唯一。
List<AgentMessage> normalizeToolCallIds(List<AgentMessage> messages) {
  final validId = RegExp(r'^[a-zA-Z0-9_-]{1,40}$');
  final reserved = {
    for (final message in messages)
      for (final call in message.toolCalls ?? const <ToolCall>[])
        if (validId.hasMatch(call.id)) call.id,
  };
  final used = <String>{};
  final pending = <String, List<ToolCall>>{};
  var sequence = 0;

  String uniqueId(String original) {
    if (validId.hasMatch(original) && used.add(original)) return original;
    String candidate;
    do {
      candidate = 'call_harness_${sequence++}';
    } while (reserved.contains(candidate) || !used.add(candidate));
    return candidate;
  }

  return messages.map((message) {
    if (message.role == AgentRole.assistant &&
        (message.toolCalls?.isNotEmpty ?? false)) {
      final calls = message.toolCalls!.map((call) {
        final normalized = ToolCall(
          id: uniqueId(call.id),
          name: call.name,
          arguments: call.arguments,
        );
        (pending[call.id] ??= []).add(normalized);
        return normalized;
      }).toList();
      return message.copyWith(toolCalls: calls);
    }
    if (message.role == AgentRole.tool) {
      final candidates = pending[message.toolCallId];
      if (candidates != null && candidates.isNotEmpty) {
        final namedIndex = candidates.indexWhere(
          (call) => call.name == message.toolName,
        );
        final paired = candidates.removeAt(namedIndex < 0 ? 0 : namedIndex);
        return message.copyWith(toolCallId: paired.id);
      }
    }
    return message;
  }).toList();
}
