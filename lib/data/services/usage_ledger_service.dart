import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../core/harness/types.dart';

/// 账单统计周期
enum BillPeriod {
  today('今天'),
  last7d('近 7 天'),
  last30d('近 30 天'),
  all('全部');

  final String label;
  const BillPeriod(this.label);
}

/// 单个模型的用量汇总行
class BillModelUsage {
  final String name; // "provider/model"
  final int requests;
  final TokenUsage usage;

  const BillModelUsage({
    required this.name,
    required this.requests,
    required this.usage,
  });
}

/// 一个周期内的账单汇总
class BillSummary {
  final BillPeriod period;
  final int requests;
  final TokenUsage usage;
  final List<BillModelUsage> models;

  const BillSummary({
    required this.period,
    required this.requests,
    required this.usage,
    required this.models,
  });
}

/// Token 用量增量账本 (参考 pi-bill 的 usage-ledger.json 设计)。
///
/// 每次 assistant 响应完成时记录一条，按 key 去重；按 天 -> 供应商 -> 模型
/// 三层聚合存储，支持今天 / 近 7 天 / 近 30 天 / 全部四种周期汇总。
class UsageLedgerService {
  static const int _version = 1;

  File? _ledgerFile;

  /// 内存中的账本数据: {version, days, keys}
  /// 注意: 内层容器必须显式声明为 `Map<String, dynamic>`，否则字面量会被
  /// 推断为 `Map<dynamic, dynamic>`，导致 `_mapOf` 拿到拷贝孤儿、写入丢失。
  Map<String, dynamic> _data = {
    'version': _version,
    'days': <String, dynamic>{},
    'keys': <String, dynamic>{},
  };

  bool get isInitialized => _ledgerFile != null;

  /// 初始化账本文件。[baseDir] 通常与会话日志目录一致。
  Future<void> init({String? baseDir}) async {
    String dirPath;
    if (baseDir != null) {
      dirPath = baseDir;
    } else {
      try {
        final docs = await getApplicationDocumentsDirectory();
        dirPath = p.join(docs.path, 'NovelAI_Sessions');
      } catch (_) {
        return;
      }
    }
    final dir = Directory(dirPath);
    dir.createSync(recursive: true);
    _ledgerFile = File(p.join(dir.path, 'usage-ledger.json'));
    _data = _readLedger();
  }

  /// 记录一次模型用量。key 重复时跳过 (去重)，返回是否真正写入。
  bool record({
    required String key,
    required String provider,
    required String model,
    required TokenUsage usage,
    DateTime? timestamp,
  }) {
    if (_ledgerFile == null) return false;
    if (usage.total <= 0) return false;

    final now = timestamp ?? DateTime.now();
    final day = _localDay(now);
    final keys = _mapOf(_data['keys']);
    if (keys.containsKey(key)) return false;

    keys[key] = {
      'key': key,
      'day': day,
      'provider': provider,
      'model': model,
      'usage': usage.toJson(),
    };

    final days = _mapOf(_data['days']);
    final dayUsage = _mapOf(days.putIfAbsent(day, () => <String, dynamic>{}));
    final providerUsage = _mapOf(
      dayUsage.putIfAbsent(provider, () => <String, dynamic>{}),
    );
    final modelUsage = _mapOf(
      providerUsage.putIfAbsent(model, () => <String, dynamic>{}),
    );
    final existing = TokenUsage.fromJson(modelUsage);
    final merged = existing.add(usage);
    providerUsage[model] = merged.toJson();

    _persist();
    return true;
  }

  /// 按周期聚合账单
  BillSummary aggregate(BillPeriod period, {DateTime? now}) {
    final currentTime = now ?? DateTime.now();
    final startDay = _periodStartDay(period, currentTime);

    var total = const TokenUsage();
    var requests = 0;
    final modelMap = <String, BillModelUsage>{};

    final keys = _mapOf(_data['keys']);
    for (final record in keys.values) {
      if (record is! Map) continue;
      final day = record['day'] as String? ?? '';
      if (startDay != null && day.compareTo(startDay) < 0) continue;

      final provider = record['provider'] as String? ?? 'unknown';
      final model = record['model'] as String? ?? 'unknown';
      final usage = TokenUsage.fromJson(record['usage']);

      requests++;
      total = total.add(usage);

      final name = '$provider/$model';
      final existing = modelMap[name];
      modelMap[name] = BillModelUsage(
        name: name,
        requests: (existing?.requests ?? 0) + 1,
        usage: (existing?.usage ?? const TokenUsage()).add(usage),
      );
    }

    final models = modelMap.values.toList()
      ..sort((a, b) => b.usage.total.compareTo(a.usage.total));

    return BillSummary(
      period: period,
      requests: requests,
      usage: total,
      models: models,
    );
  }

  /// 格式化 token 数: 1.2K / 3.4M / 1.2B
  static String formatTokens(int value) {
    final absolute = value.abs();
    if (absolute >= 1000000000) {
      return '${(value / 1000000000).toStringAsFixed(1)}B';
    }
    if (absolute >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M';
    }
    if (absolute >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}K';
    }
    return value.toString();
  }

  // ---------------------------------------------------------------------------
  // 内部实现
  // ---------------------------------------------------------------------------

  Map<String, dynamic> _readLedger() {
    final file = _ledgerFile;
    if (file == null || !file.existsSync()) {
      return {
        'version': _version,
        'days': <String, dynamic>{},
        'keys': <String, dynamic>{},
      };
    }
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is Map<String, dynamic>) {
        return {
          'version': decoded['version'] ?? _version,
          'days': decoded['days'] ?? <String, dynamic>{},
          'keys': decoded['keys'] ?? <String, dynamic>{},
        };
      }
    } catch (_) {}
    return {
      'version': _version,
      'days': <String, dynamic>{},
      'keys': <String, dynamic>{},
    };
  }

  void _persist() {
    final file = _ledgerFile;
    if (file == null) return;
    try {
      final tmp = File('${file.path}.tmp');
      tmp.writeAsStringSync('${jsonEncode(_data)}\n', flush: true);
      tmp.renameSync(file.path);
    } catch (_) {
      // 落盘失败不影响主流程，内存数据仍可用于本会话统计
    }
  }

  Map<String, dynamic> _mapOf(dynamic value) =>
      value is Map<String, dynamic> ? value : <String, dynamic>{};

  String _localDay(DateTime time) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)}';
  }

  String? _periodStartDay(BillPeriod period, DateTime now) {
    switch (period) {
      case BillPeriod.all:
        return null;
      case BillPeriod.today:
        return _localDay(now);
      case BillPeriod.last7d:
        return _localDay(DateTime(now.year, now.month, now.day - 6));
      case BillPeriod.last30d:
        return _localDay(DateTime(now.year, now.month, now.day - 29));
    }
  }
}
