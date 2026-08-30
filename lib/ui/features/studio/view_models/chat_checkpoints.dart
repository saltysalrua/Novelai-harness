import '../../../../core/harness/types.dart';

/// 对话轮次时刻 (由一次 User 提问以及随后的 Assistant/Tool 回复构成)
class ChatCheckpoint {
  final int index;
  final AgentMessage userMessage;
  final AgentMessage? assistantMessage;
  final List<AgentMessage> toolMessages;

  const ChatCheckpoint({
    required this.index,
    required this.userMessage,
    this.assistantMessage,
    this.toolMessages = const [],
  });
}

/// 将消息流按“用户提问 -> 助手/工具回复”聚合成轮次时刻列表 (回溯视图使用)。
///
/// 规则：每条 user 消息开启一个新轮次；其后连续的 assistant/tool 消息归入该轮。
/// 连续两条 user 消息 (如中途被中止的轮次) 会各自成轮。
List<ChatCheckpoint> extractChatCheckpoints(List<AgentMessage> messages) {
  final checkpoints = <ChatCheckpoint>[];

  AgentMessage? currentUser;
  AgentMessage? currentAssistant;
  final currentTools = <AgentMessage>[];

  void flush() {
    if (currentUser == null) return;
    checkpoints.add(
      ChatCheckpoint(
        index: checkpoints.length + 1,
        userMessage: currentUser!,
        assistantMessage: currentAssistant,
        toolMessages: List.of(currentTools),
      ),
    );
    currentUser = null;
    currentAssistant = null;
    currentTools.clear();
  }

  for (final msg in messages) {
    if (msg.role == AgentRole.user) {
      flush();
      currentUser = msg;
    } else if (msg.role == AgentRole.assistant) {
      currentAssistant = msg;
    } else if (msg.role == AgentRole.tool) {
      currentTools.add(msg);
    }
  }
  flush();

  return checkpoints;
}
