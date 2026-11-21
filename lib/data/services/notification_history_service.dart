import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 通知严重级别
enum AppNoticeLevel {
  error,
  warning,
  info;

  static AppNoticeLevel fromName(String? raw) {
    for (final value in values) {
      if (value.name == raw) return value;
    }
    return AppNoticeLevel.error;
  }
}

/// 通知所属业务来源
enum AppNoticeSource {
  generation,
  inpaint,
  agent,
  account,
  comfyUi,
  storage,
  system;

  static AppNoticeSource fromName(String? raw) {
    for (final value in values) {
      if (value.name == raw) return value;
    }
    return AppNoticeSource.system;
  }
}

/// 单条本地持久化的通知/报错记录
@immutable
class AppNoticeRecord {
  final String id;
  final AppNoticeLevel level;
  final AppNoticeSource source;
  final String message;
  final DateTime timestamp;
  final bool read;

  const AppNoticeRecord({
    required this.id,
    required this.level,
    required this.source,
    required this.message,
    required this.timestamp,
    this.read = false,
  });

  AppNoticeRecord copyWith({
    String? id,
    AppNoticeLevel? level,
    AppNoticeSource? source,
    String? message,
    DateTime? timestamp,
    bool? read,
  }) {
    return AppNoticeRecord(
      id: id ?? this.id,
      level: level ?? this.level,
      source: source ?? this.source,
      message: message ?? this.message,
      timestamp: timestamp ?? this.timestamp,
      read: read ?? this.read,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'level': level.name,
    'source': source.name,
    'message': message,
    'timestamp': timestamp.toIso8601String(),
    'read': read,
  };

  static AppNoticeRecord? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final message = json['message'];
    if (id is! String || id.isEmpty || message is! String || message.isEmpty) {
      return null;
    }
    final tsRaw = json['timestamp'];
    final timestamp = (tsRaw is String ? DateTime.tryParse(tsRaw) : null) ??
        DateTime.now();
    return AppNoticeRecord(
      id: id,
      level: AppNoticeLevel.fromName(json['level'] as String?),
      source: AppNoticeSource.fromName(json['source'] as String?),
      message: message,
      timestamp: timestamp,
      read: json['read'] as bool? ?? false,
    );
  }
}

/// 本地持久化通知历史服务：保留最近 100 条通知与报错记录，供通知中心回看、复制与清理。
class NotificationHistoryService {
  static const int _version = 1;
  static const int maxRecords = 100;
  static const String fileName = 'notification_history.json';

  final List<AppNoticeRecord> _records = [];
  File? _historyFile;
  Future<void>? _pendingWrite;
  bool _dirty = false;
  int _seq = 0;

  /// 按最新优先排序的只读记录列表
  List<AppNoticeRecord> get records => List.unmodifiable(_records);

  /// 当前未读条数
  int get unreadCount => _records.where((r) => !r.read).length;

  /// 绑定持久化目录并加载历史记录；启动阶段早于 init 记入内存的记录会合并保留在最前。
  Future<void> init({String? baseDir}) async {
    try {
      final resolvedDir = (baseDir != null && baseDir.isNotEmpty)
          ? baseDir
          : (await getApplicationSupportDirectory()).path;
      final dir = Directory(resolvedDir);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      _historyFile = File(p.join(resolvedDir, fileName));

      final startup = List<AppNoticeRecord>.of(_records);
      final disk = _readFromDisk();
      final seen = <String>{};
      final merged = <AppNoticeRecord>[];
      for (final item in [...startup, ...disk]) {
        if (seen.add(item.id)) {
          merged.add(item);
          if (merged.length >= maxRecords) break;
        }
      }
      _records
        ..clear()
        ..addAll(merged);

      if (startup.isNotEmpty) {
        _dirty = true;
        _schedulePersist();
      }
    } catch (_) {
      // 无插件环境或受限沙盒下退化为内存保留，不阻塞主流程。
    }
  }

  /// 记入一条新通知/错误并异步原子落盘。
  AppNoticeRecord record({
    required String message,
    AppNoticeLevel level = AppNoticeLevel.error,
    AppNoticeSource source = AppNoticeSource.system,
    DateTime? timestamp,
  }) {
    final now = timestamp ?? DateTime.now();
    final item = AppNoticeRecord(
      id: 'notice_${now.microsecondsSinceEpoch}_${++_seq}',
      level: level,
      source: source,
      message: message,
      timestamp: now,
      read: false,
    );
    _records.insert(0, item);
    if (_records.length > maxRecords) {
      _records.removeRange(maxRecords, _records.length);
    }
    _dirty = true;
    _schedulePersist();
    return item;
  }

  /// 将所有记录标为已读，有变化时落盘并返回 true。
  bool markAllRead() {
    var changed = false;
    for (var i = 0; i < _records.length; i++) {
      if (!_records[i].read) {
        _records[i] = _records[i].copyWith(read: true);
        changed = true;
      }
    }
    if (!changed) return false;
    _dirty = true;
    _schedulePersist();
    return true;
  }

  /// 删除单条记录，成功移除时落盘并返回 true。
  bool remove(String id) {
    final before = _records.length;
    _records.removeWhere((r) => r.id == id);
    if (_records.length == before) return false;
    _dirty = true;
    _schedulePersist();
    return true;
  }

  /// 清空全部记录，有条目被清除时落盘并返回 true。
  bool clear() {
    if (_records.isEmpty) return false;
    _records.clear();
    _dirty = true;
    _schedulePersist();
    return true;
  }

  /// 等待挂起的异步写盘完成（用于测试与优雅退出）。
  Future<void> flush() async {
    if (_dirty && _historyFile != null && _pendingWrite == null) {
      _schedulePersist();
    }
    while (_pendingWrite != null) {
      await _pendingWrite;
    }
  }

  List<AppNoticeRecord> _readFromDisk() {
    final file = _historyFile;
    if (file == null || !file.existsSync()) return const [];
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      final List<dynamic>? rawList;
      if (decoded is Map<String, dynamic>) {
        final rawRecords = decoded['records'];
        rawList = rawRecords is List<dynamic> ? rawRecords : null;
      } else if (decoded is List<dynamic>) {
        rawList = decoded;
      } else {
        rawList = null;
      }
      if (rawList == null) return const [];

      final parsed = <AppNoticeRecord>[];
      for (final item in rawList) {
        if (item is! Map<String, dynamic>) continue;
        final record = AppNoticeRecord.fromJson(item);
        if (record != null) {
          parsed.add(record);
          if (parsed.length >= maxRecords) break;
        }
      }
      return parsed;
    } catch (_) {
      return const [];
    }
  }

  void _schedulePersist() {
    if (_historyFile == null) return;
    _pendingWrite ??= _persist().whenComplete(() {
      _pendingWrite = null;
      if (_dirty) _schedulePersist();
    });
  }

  Future<void> _persist() async {
    final file = _historyFile;
    if (file == null) return;
    while (_dirty) {
      _dirty = false;
      try {
        final payload = <String, dynamic>{
          'version': _version,
          'records': [for (final r in _records) r.toJson()],
        };
        final encoded = await Isolate.run(() => jsonEncode(payload));
        final tmp = File('${file.path}.tmp');
        await tmp.writeAsString('$encoded\n', flush: true);
        await tmp.rename(file.path);
      } catch (_) {
        // 写盘失败不影响内存中的实时通知历史展示。
      }
    }
  }
}
