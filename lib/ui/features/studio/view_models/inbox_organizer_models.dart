/// 词库待整理区后台整理日志条目类型
enum InboxOrganizerLogKind {
  system,
  thought,
  content,
  toolCall,
  toolResult,
  error,
}

/// 词库待整理区后台整理单条日志记录
class InboxOrganizerLogEntry {
  final DateTime timestamp;
  final InboxOrganizerLogKind kind;
  final String? title;
  final String text;
  final bool isError;

  const InboxOrganizerLogEntry({
    required this.timestamp,
    required this.kind,
    this.title,
    required this.text,
    this.isError = false,
  });
}
