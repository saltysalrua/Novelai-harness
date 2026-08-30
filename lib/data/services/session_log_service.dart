import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../core/harness/session_recorder.dart';
import '../../core/harness/types.dart';

/// 会话元数据信息 (供会话管理列表展示与操作)
class SessionInfo {
  final String id;
  final String filePath;
  final String title;
  final DateTime createdAt;
  final DateTime lastModified;
  final int messageCount;
  final String preview;
  final String? provider;
  final String? modelId;
  final int totalTokens;
  final bool isActive;

  const SessionInfo({
    required this.id,
    required this.filePath,
    required this.title,
    required this.createdAt,
    required this.lastModified,
    required this.messageCount,
    required this.preview,
    this.provider,
    this.modelId,
    this.totalTokens = 0,
    this.isActive = false,
  });

  SessionInfo copyWith({
    String? id,
    String? filePath,
    String? title,
    DateTime? createdAt,
    DateTime? lastModified,
    int? messageCount,
    String? preview,
    String? provider,
    String? modelId,
    int? totalTokens,
    bool? isActive,
  }) {
    return SessionInfo(
      id: id ?? this.id,
      filePath: filePath ?? this.filePath,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      lastModified: lastModified ?? this.lastModified,
      messageCount: messageCount ?? this.messageCount,
      preview: preview ?? this.preview,
      provider: provider ?? this.provider,
      modelId: modelId ?? this.modelId,
      totalTokens: totalTokens ?? this.totalTokens,
      isActive: isActive ?? this.isActive,
    );
  }
}

/// 从会话文件恢复出的会话快照
class SessionSnapshot {
  final String? sessionId;
  final String? sessionTitle;
  final List<AgentMessage> messages;
  final String? provider;
  final String? modelId;
  final String? thinkingLevel;

  /// 本会话内各模型 (provider/model) 累计的 Token 用量
  final Map<String, TokenUsage> sessionUsage;

  const SessionSnapshot({
    this.sessionId,
    this.sessionTitle,
    required this.messages,
    this.provider,
    this.modelId,
    this.thinkingLevel,
    this.sessionUsage = const {},
  });
}

/// 按 Pi 官方会话格式 (session-format.md, version 3) 记录对话历史的 JSONL 服务。
///
/// 格式要点：
/// - 首行 session 头：{"type":"session","version":3,"id":uuid,"timestamp":ISO,"cwd":...,"title":...}
/// - 消息条目：{"type":"message","id":"8hex","parentId":"8hex|null","timestamp":ISO,"message":{...}}
/// - assistant 消息 content 为内容块数组：thinking / toolCall / text
/// - tool 消息映射为 role=toolResult，携带 toolCallId / toolName / isError
/// - 另支持 model_change / thinking_level_change / session_info 条目
/// - 条目通过 id/parentId 形成树链 (本应用为线性链与回溯截断)
class SessionLogService implements SessionRecorder {
  static const int _sessionVersion = 3;

  Directory? _baseDir;
  File? _currentFile;
  String? _lastEntryId;
  final Random _random = Random();

  /// 串行写队列，保证 JSONL 行序与写入顺序一致
  Future<void> _queue = Future.value();

  bool get isInitialized => _baseDir != null;

  /// 会话根目录 (供账本等其他服务复用同一目录)
  String? get baseDirPath => _baseDir?.path;

  /// 当前活跃会话文件
  File? get currentSessionFile => _currentFile;

  /// 当前活跃会话的 UUID 标识
  String? get currentSessionId {
    final file = _currentFile;
    if (file == null) return null;
    return _extractSessionIdFromFile(file);
  }

  @override
  String? get sessionId => currentSessionId;

  /// 初始化：解析会话根目录并接管最新会话文件 (续接模式，类似 pi --continue)。
  /// 测试可通过 [baseDir] 注入临时目录。
  Future<void> init({String? baseDir}) async {
    String dirPath;
    if (baseDir != null) {
      dirPath = baseDir;
    } else {
      try {
        final docs = await getApplicationDocumentsDirectory();
        dirPath = p.join(docs.path, 'NovelAI_Sessions');
      } catch (_) {
        dirPath = p.join(Directory.systemTemp.path, 'NovelAI_Sessions');
      }
    }

    final dir = Directory(dirPath);
    dir.createSync(recursive: true);
    _baseDir = dir;

    // 接管最新会话文件：后续记录追加到该文件末尾
    final latest = _latestSessionFile();
    if (latest != null) {
      _currentFile = latest;
      _lastEntryId = _lastEntryIdOfFile(latest);
    }
  }

  // ---------------------------------------------------------------------------
  // SessionRecorder 实现
  // ---------------------------------------------------------------------------

  @override
  void recordMessage(AgentMessage message, {String? provider, String? model}) {
    if (_baseDir == null) return;
    _ensureSession();

    final msg = <String, dynamic>{};
    switch (message.role) {
      case AgentRole.user:
        msg['role'] = 'user';
        msg['content'] = [
          {'type': 'text', 'text': message.content},
        ];
        msg['timestamp'] = message.createdAt.millisecondsSinceEpoch;

      case AgentRole.assistant:
        final parts = <Map<String, dynamic>>[];
        if (message.thoughts.isNotEmpty) {
          parts.add({'type': 'thinking', 'thinking': message.thoughts});
        }
        if (message.toolCalls != null) {
          for (final tc in message.toolCalls!) {
            parts.add({
              'type': 'toolCall',
              'id': tc.id,
              'name': tc.name,
              'arguments': tc.arguments,
            });
          }
        }
        if (message.content.isNotEmpty) {
          parts.add({'type': 'text', 'text': message.content});
        }
        msg['role'] = 'assistant';
        msg['content'] = parts;
        msg['api'] = 'openai-chat';
        msg['provider'] = provider ?? 'unknown';
        msg['model'] = model ?? 'unknown';
        msg['usage'] = _usageJson(message.usage);
        msg['stopReason'] = (message.toolCalls?.isNotEmpty ?? false)
            ? 'toolUse'
            : 'stop';
        msg['timestamp'] = message.createdAt.millisecondsSinceEpoch;

      case AgentRole.tool:
        msg['role'] = 'toolResult';
        msg['toolCallId'] = message.toolCallId ?? '';
        msg['toolName'] = message.toolName ?? '';
        msg['content'] = [
          {'type': 'text', 'text': message.content},
        ];
        msg['isError'] = message.isError;
        msg['timestamp'] = message.createdAt.millisecondsSinceEpoch;

      case AgentRole.system:
        // 系统提示词按需动态注入，不落盘
        return;
    }

    _appendEntry({'type': 'message', 'message': msg});
  }

  @override
  void recordModelChange(String provider, String modelId) {
    if (_baseDir == null) return;
    _ensureSession();
    _appendEntry({
      'type': 'model_change',
      'provider': provider,
      'modelId': modelId,
    });
  }

  @override
  void recordThinkingLevelChange(String level) {
    if (_baseDir == null) return;
    _ensureSession();
    _appendEntry({'type': 'thinking_level_change', 'thinkingLevel': level});
  }

  @override
  void startNewSession() {
    if (_baseDir == null) return;
    _currentFile = null;
    _lastEntryId = null;
    // 立即创建新的空会话文件 (写入头)，保证 /clear 后重启不会误恢复旧会话
    _ensureSession();
  }

  @override
  void rewindToMessageCount(int keepCount) {
    final file = _currentFile;
    if (file == null || !file.existsSync()) return;

    _queue = _queue.then((_) async {
      List<String> lines;
      try {
        lines = file.readAsLinesSync();
      } catch (_) {
        return;
      }
      if (lines.isEmpty) return;

      final keptLines = <String>[];
      keptLines.add(lines.first); // 保留 session 头

      int msgCount = 0;
      String? lastKeptId;

      for (var i = 1; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;
        Map<String, dynamic> entry;
        try {
          entry = jsonDecode(line) as Map<String, dynamic>;
        } catch (_) {
          continue;
        }

        if (entry['type'] == 'message') {
          if (msgCount >= keepCount) {
            // 已达到保留上限，停止保留后续消息与关联条目
            break;
          }
          msgCount++;
        }
        keptLines.add(line);
        lastKeptId = entry['id'] as String? ?? lastKeptId;
      }

      file.writeAsStringSync('${keptLines.join('\n')}\n', flush: true);
      _lastEntryId = lastKeptId;
    });
  }

  /// 等待所有排队的写入落盘 (测试与退出前调用)
  Future<void> flush() => _queue;

  // ---------------------------------------------------------------------------
  // 会话管理 (List / Load / Create / Delete / Rename)
  // ---------------------------------------------------------------------------

  /// 列出所有已保存的会话信息，按最后修改时间倒序排列
  Future<List<SessionInfo>> listSessions() async {
    final dir = _baseDir;
    if (dir == null || !dir.existsSync()) return [];

    await flush();

    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.jsonl'))
        .toList();

    final sessions = <SessionInfo>[];

    for (final file in files) {
      final info = _parseSessionInfoFromFile(file);
      if (info != null) {
        sessions.add(info);
      }
    }

    sessions.sort((a, b) {
      final m = b.lastModified.compareTo(a.lastModified);
      if (m != 0) return m;
      final c = b.createdAt.compareTo(a.createdAt);
      if (c != 0) return c;
      return b.id.compareTo(a.id);
    });
    return sessions;
  }

  /// 切换并加载指定 sessionId 的会话快照
  SessionSnapshot? loadSession(String sessionId) {
    if (_baseDir == null) return null;
    final file = _findSessionFileById(sessionId);
    if (file == null) return null;

    final snapshot = _loadSnapshotFromFile(file);
    if (snapshot != null) {
      _currentFile = file;
      _lastEntryId = _lastEntryIdOfFile(file);
    }
    return snapshot;
  }

  /// 加载最新会话文件的快照 (消息列表 + 最终模型/思考强度状态)。
  /// 文件不存在或无可恢复消息时返回 null。
  SessionSnapshot? loadLatestSession() {
    if (_baseDir == null) return null;
    final file = _latestSessionFile();
    if (file == null) return null;

    final snapshot = _loadSnapshotFromFile(file);
    if (snapshot != null) {
      _currentFile = file;
      _lastEntryId = _lastEntryIdOfFile(file);
    }
    return snapshot;
  }

  /// 创建一个全新的会话文件并设为当前活跃会话
  Future<SessionInfo> createSession({String? title}) async {
    if (_baseDir == null) {
      throw StateError('SessionLogService 未初始化');
    }
    await flush();

    final now = DateTime.now().toUtc();
    final sessionId = _uuidV4();
    final fileName = '${_formatFileTimestamp(now)}_$sessionId.jsonl';
    final file = File(p.join(_baseDir!.path, fileName));
    _currentFile = file;
    _lastEntryId = null;

    final header = <String, dynamic>{
      'type': 'session',
      'version': _sessionVersion,
      'id': sessionId,
      'timestamp': now.toIso8601String(),
      'cwd': Directory.current.path,
      if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
    };

    file.writeAsStringSync('${jsonEncode(header)}\n', flush: true);

    return SessionInfo(
      id: sessionId,
      filePath: file.path,
      title: (title != null && title.trim().isNotEmpty) ? title.trim() : '新会话',
      createdAt: now.toLocal(),
      lastModified: now.toLocal(),
      messageCount: 0,
      preview: '新会话',
      isActive: true,
    );
  }

  /// 删除指定 sessionId 的会话文件
  Future<bool> deleteSession(String sessionId) async {
    if (_baseDir == null) return false;
    await flush();

    final file = _findSessionFileById(sessionId);
    if (file == null || !file.existsSync()) return false;

    if (_currentFile?.path == file.path) {
      _currentFile = null;
      _lastEntryId = null;
    }

    try {
      file.deleteSync();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 重命名会话 (更新 JSONL 文件头中的 title 并写入 session_info 条目)
  Future<void> renameSession(String sessionId, String newTitle) async {
    if (_baseDir == null) return;
    await flush();

    final file = _findSessionFileById(sessionId);
    if (file == null || !file.existsSync()) return;

    final trimmedTitle = newTitle.trim();
    if (trimmedTitle.isEmpty) return;

    List<String> lines;
    try {
      lines = file.readAsLinesSync();
    } catch (_) {
      return;
    }
    if (lines.isEmpty) return;

    // 1. 更新第一行 header 的 title
    try {
      final header = jsonDecode(lines.first) as Map<String, dynamic>;
      header['title'] = trimmedTitle;
      lines[0] = jsonEncode(header);
    } catch (_) {}

    // 2. 写入/更新 session_info 条目 (Pi 标准)
    final infoEntry = <String, dynamic>{
      'type': 'session_info',
      'title': trimmedTitle,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };
    lines.add(jsonEncode(infoEntry));

    file.writeAsStringSync('${lines.join('\n')}\n', flush: true);
    _lastEntryId = _lastEntryIdOfFile(file);
  }

  // ---------------------------------------------------------------------------
  // 内部实现与解析
  // ---------------------------------------------------------------------------

  void _ensureSession() {
    if (_currentFile != null) return;
    final now = DateTime.now().toUtc();
    final sessionId = _uuidV4();
    final fileName = '${_formatFileTimestamp(now)}_$sessionId.jsonl';
    final file = File(p.join(_baseDir!.path, fileName));
    _currentFile = file;
    _lastEntryId = null;
    _queue = _queue.then((_) async {
      final header = <String, dynamic>{
        'type': 'session',
        'version': _sessionVersion,
        'id': sessionId,
        'timestamp': now.toIso8601String(),
        'cwd': Directory.current.path,
      };
      final sink = file.openWrite(mode: FileMode.writeOnly);
      sink.writeln(jsonEncode(header));
      await sink.flush();
      await sink.close();
    });
  }

  void _appendEntry(Map<String, dynamic> entry) {
    final file = _currentFile;
    if (file == null) return;
    final id = _hexId(8);
    entry['id'] = id;
    entry['parentId'] = _lastEntryId;
    entry['timestamp'] = DateTime.now().toUtc().toIso8601String();
    _lastEntryId = id;
    final line = jsonEncode(entry);
    _queue = _queue.then((_) async {
      final sink = file.openWrite(mode: FileMode.append);
      sink.writeln(line);
      await sink.flush();
      await sink.close();
    });
  }

  File? _latestSessionFile() {
    final dir = _baseDir;
    if (dir == null || !dir.existsSync()) return null;
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.jsonl'))
        .toList();
    if (files.isEmpty) return null;
    files.sort((a, b) {
      final mtime = b.lastModifiedSync().compareTo(a.lastModifiedSync());
      if (mtime != 0) return mtime;
      return p.basename(b.path).compareTo(p.basename(a.path));
    });
    return files.first;
  }

  File? _findSessionFileById(String sessionId) {
    final dir = _baseDir;
    if (dir == null || !dir.existsSync()) return null;
    final files = dir.listSync().whereType<File>().where(
      (f) => f.path.endsWith('.jsonl'),
    );
    for (final f in files) {
      if (f.path.contains(sessionId)) return f;
      final id = _extractSessionIdFromFile(f);
      if (id == sessionId) return f;
    }
    return null;
  }

  String? _extractSessionIdFromFile(File file) {
    final base = p.basenameWithoutExtension(file.path);
    if (base.contains('_')) {
      return base.substring(base.indexOf('_') + 1);
    }
    try {
      final line = file.readAsLinesSync().firstOrNull;
      if (line != null) {
        final header = jsonDecode(line) as Map<String, dynamic>;
        return header['id'] as String?;
      }
    } catch (_) {}
    return null;
  }

  String? _lastEntryIdOfFile(File file) {
    try {
      final lines = file.readAsLinesSync();
      for (final line in lines.reversed) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        try {
          final entry = jsonDecode(trimmed) as Map<String, dynamic>;
          return entry['id'] as String?;
        } catch (_) {
          continue;
        }
      }
    } catch (_) {}
    return null;
  }

  SessionSnapshot? _loadSnapshotFromFile(File file) {
    final messages = <AgentMessage>[];
    final sessionUsage = <String, TokenUsage>{};
    String? sessionId = _extractSessionIdFromFile(file);
    String? sessionTitle;
    String? provider;
    String? modelId;
    String? thinkingLevel;

    List<String> lines;
    try {
      lines = file.readAsLinesSync();
    } catch (_) {
      return null;
    }

    for (var i = 0; i < lines.length; i++) {
      final trimmed = lines[i].trim();
      if (trimmed.isEmpty) continue;
      Map<String, dynamic> entry;
      try {
        entry = jsonDecode(trimmed) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }

      final type = entry['type'] as String?;
      if (i == 0 && type == 'session') {
        sessionId = entry['id'] as String? ?? sessionId;
        sessionTitle = entry['title'] as String?;
        continue;
      }

      switch (type) {
        case 'message':
          final msg = _parseMessageEntry(entry);
          if (msg != null) {
            messages.add(msg);
            if (msg.role == AgentRole.assistant &&
                msg.providerModelKey != null &&
                (msg.usage?.total ?? 0) > 0) {
              final key = msg.providerModelKey!;
              sessionUsage[key] = (sessionUsage[key] ?? const TokenUsage()).add(
                msg.usage!,
              );
            }
          }
        case 'model_change':
          provider = entry['provider'] as String?;
          modelId = entry['modelId'] as String?;
        case 'thinking_level_change':
          thinkingLevel = entry['thinkingLevel'] as String?;
        case 'session_info':
          sessionTitle = entry['title'] as String? ?? sessionTitle;
      }
    }

    if (messages.isEmpty && sessionTitle == null) return null;
    return SessionSnapshot(
      sessionId: sessionId,
      sessionTitle: sessionTitle,
      messages: messages,
      provider: provider,
      modelId: modelId,
      thinkingLevel: thinkingLevel,
      sessionUsage: sessionUsage,
    );
  }

  SessionInfo? _parseSessionInfoFromFile(File file) {
    try {
      final lines = file.readAsLinesSync();
      if (lines.isEmpty) return null;

      final headerLine = lines.first.trim();
      final header = jsonDecode(headerLine) as Map<String, dynamic>;
      final id =
          (header['id'] as String?) ??
          _extractSessionIdFromFile(file) ??
          'unknown';
      var title = header['title'] as String?;
      final createdAt =
          DateTime.tryParse(header['timestamp'] as String? ?? '')?.toLocal() ??
          file.lastModifiedSync();
      var lastModified = file.lastModifiedSync();

      int messageCount = 0;
      int totalTokens = 0;
      String preview = '';
      String? firstUserPrompt;
      String? provider;
      String? modelId;

      for (var i = 1; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;
        Map<String, dynamic> entry;
        try {
          entry = jsonDecode(line) as Map<String, dynamic>;
        } catch (_) {
          continue;
        }

        final entryTsStr = entry['timestamp'] as String?;
        if (entryTsStr != null) {
          final entryTs = DateTime.tryParse(entryTsStr)?.toLocal();
          if (entryTs != null && entryTs.isAfter(lastModified)) {
            lastModified = entryTs;
          }
        }

        final type = entry['type'] as String?;
        if (type == 'session_info') {
          title = entry['title'] as String? ?? title;
        } else if (type == 'model_change') {
          provider = entry['provider'] as String? ?? provider;
          modelId = entry['modelId'] as String? ?? modelId;
        } else if (type == 'message') {
          messageCount++;
          final msg = entry['message'] as Map<String, dynamic>?;
          if (msg != null) {
            final role = msg['role'] as String?;
            final content = _joinContentText(msg['content']);
            if (role == 'user') {
              firstUserPrompt ??= content;
              preview = content;
            } else if (role == 'assistant') {
              provider ??= msg['provider'] as String?;
              modelId ??= msg['modelId'] as String?;
              if (content.isNotEmpty) {
                preview = content;
              }
              final usage = msg['usage'] as Map<String, dynamic>?;
              if (usage != null) {
                totalTokens += (usage['totalTokens'] as num?)?.toInt() ?? 0;
              }
            }
          }
        }
      }

      if (title == null || title.trim().isEmpty) {
        if (firstUserPrompt != null && firstUserPrompt.trim().isNotEmpty) {
          final clean = firstUserPrompt.trim().replaceAll('\n', ' ');
          title = clean.length > 25 ? '${clean.substring(0, 25)}...' : clean;
        } else {
          title = messageCount == 0
              ? '新会话'
              : '会话 ${id.substring(0, min(8, id.length))}';
        }
      }

      if (preview.isEmpty) {
        preview = messageCount == 0 ? '空会话' : title;
      }

      final isActive =
          _currentFile != null &&
          p.canonicalize(_currentFile!.path) == p.canonicalize(file.path);

      return SessionInfo(
        id: id,
        filePath: file.path,
        title: title,
        createdAt: createdAt,
        lastModified: lastModified,
        messageCount: messageCount,
        preview: preview,
        provider: provider,
        modelId: modelId,
        totalTokens: totalTokens,
        isActive: isActive,
      );
    } catch (_) {
      return null;
    }
  }

  AgentMessage? _parseMessageEntry(Map<String, dynamic> entry) {
    final msg = entry['message'] as Map<String, dynamic>?;
    if (msg == null) return null;

    final entryId = entry['id'] as String?;
    final fallbackId = 'restored_${entryId ?? _hexId(8)}';
    final epochMs = (msg['timestamp'] as num?)?.toInt();
    final createdAt = epochMs != null
        ? DateTime.fromMillisecondsSinceEpoch(epochMs)
        : DateTime.tryParse(entry['timestamp'] as String? ?? '');

    switch (msg['role'] as String?) {
      case 'user':
        return AgentMessage(
          id: fallbackId,
          role: AgentRole.user,
          content: _joinContentText(msg['content']),
          createdAt: createdAt,
        );

      case 'assistant':
        var thoughts = '';
        var content = '';
        TokenUsage? usage;
        final toolCalls = <ToolCall>[];
        final parts = msg['content'];
        if (parts is List) {
          for (final part in parts) {
            if (part is! Map<String, dynamic>) continue;
            switch (part['type'] as String?) {
              case 'thinking':
                thoughts += part['thinking'] as String? ?? '';
              case 'text':
                content += part['text'] as String? ?? '';
              case 'toolCall':
                final args = part['arguments'];
                toolCalls.add(
                  ToolCall(
                    id: part['id'] as String? ?? _hexId(8),
                    name: part['name'] as String? ?? '',
                    arguments: args is Map<String, dynamic>
                        ? args
                        : <String, dynamic>{},
                  ),
                );
            }
          }
        }
        if (msg['usage'] != null) {
          usage = TokenUsage.fromJson(msg['usage']);
        }
        return AgentMessage(
          id: fallbackId,
          role: AgentRole.assistant,
          content: content,
          thoughts: thoughts,
          toolCalls: toolCalls.isNotEmpty ? toolCalls : null,
          usage: usage,
          provider: msg['provider'] as String?,
          model: msg['model'] as String?,
          createdAt: createdAt,
        );

      case 'toolResult':
        return AgentMessage(
          id: fallbackId,
          role: AgentRole.tool,
          content: _joinContentText(msg['content']),
          toolCallId: msg['toolCallId'] as String?,
          toolName: msg['toolName'] as String?,
          isError: msg['isError'] as bool? ?? false,
          createdAt: createdAt,
        );

      default:
        return null;
    }
  }

  String _joinContentText(dynamic content) {
    if (content is String) return content;
    if (content is List) {
      final buffer = StringBuffer();
      for (final part in content) {
        if (part is Map<String, dynamic> && part['type'] == 'text') {
          buffer.write(part['text'] as String? ?? '');
        }
      }
      return buffer.toString();
    }
    return '';
  }

  Map<String, dynamic> _usageJson(TokenUsage? u) => {
    'input': u?.input ?? 0,
    'output': u?.output ?? 0,
    'cacheRead': u?.cacheRead ?? 0,
    'cacheWrite': u?.cacheWrite ?? 0,
    'totalTokens': u?.total ?? 0,
    'cost': {
      'input': 0.0,
      'output': 0.0,
      'cacheRead': 0.0,
      'cacheWrite': 0.0,
      'total': 0.0,
    },
  };

  /// Pi 风格文件名时间戳: 2026-08-29T15-40-19-709Z
  String _formatFileTimestamp(DateTime utc) {
    String two(int n) => n.toString().padLeft(2, '0');
    String three(int n) => n.toString().padLeft(3, '0');
    return '${utc.year}-${two(utc.month)}-${two(utc.day)}'
        'T${two(utc.hour)}-${two(utc.minute)}-${two(utc.second)}-${three(utc.millisecond)}Z';
  }

  /// 8 位十六进制短 ID (Pi 条目 ID 风格)
  String _hexId(int length) {
    const chars = '0123456789abcdef';
    return List.generate(
      length,
      (_) => chars[_random.nextInt(chars.length)],
    ).join();
  }

  /// 随机 UUID v4 形态字符串
  String _uuidV4() {
    final hex = _hexId(32);
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-4${hex.substring(13, 16)}'
        '-a${hex.substring(17, 20)}-${hex.substring(20, 32)}';
  }
}
