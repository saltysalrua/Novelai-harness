import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/core/harness/types.dart';
import 'package:novelai_harness/data/services/usage_ledger_service.dart';

void main() {
  late Directory tempDir;
  late UsageLedgerService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('nai_ledger_test');
    service = UsageLedgerService();
    await service.init(baseDir: tempDir.path);
  });

  tearDown(() async {
    await service.flush();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  test('record writes ledger file and aggregates by model', () async {
    final ok1 = service.record(
      key: 'usage_1',
      provider: 'deepseek',
      model: 'deepseek-chat',
      usage: const TokenUsage(input: 1000, output: 500, cacheRead: 200),
    );
    final ok2 = service.record(
      key: 'usage_2',
      provider: 'deepseek',
      model: 'deepseek-reasoner',
      usage: const TokenUsage(input: 3000, output: 800),
    );

    expect(ok1, isTrue);
    expect(ok2, isTrue);
    await service.flush();
    expect(File('${tempDir.path}/usage-ledger.json').existsSync(), isTrue);

    final summary = service.aggregate(BillPeriod.all);
    expect(summary.requests, equals(2));
    expect(summary.usage.total, equals(5500));
    expect(summary.models.length, equals(2));
    // 按总用量降序: reasoner (3800) 在前
    expect(summary.models.first.name, equals('deepseek/deepseek-reasoner'));
    expect(summary.models.first.usage.input, equals(3000));
  });

  test('duplicate keys are deduplicated', () {
    service.record(
      key: 'usage_x',
      provider: 'p',
      model: 'm',
      usage: const TokenUsage(input: 100),
    );
    final dup = service.record(
      key: 'usage_x',
      provider: 'p',
      model: 'm',
      usage: const TokenUsage(input: 100),
    );

    expect(dup, isFalse);
    final summary = service.aggregate(BillPeriod.all);
    expect(summary.requests, equals(1));
    expect(summary.usage.input, equals(100));
  });

  test('zero usage records are skipped', () {
    final ok = service.record(
      key: 'usage_zero',
      provider: 'p',
      model: 'm',
      usage: const TokenUsage(),
    );
    expect(ok, isFalse);
    expect(service.aggregate(BillPeriod.all).requests, equals(0));
  });

  test('period filtering by day', () {
    final now = DateTime.now();
    final yesterday = DateTime(now.year, now.month, now.day - 1);

    service.record(
      key: 'today_1',
      provider: 'p',
      model: 'm',
      usage: const TokenUsage(input: 10),
    );
    service.record(
      key: 'yesterday_1',
      provider: 'p',
      model: 'm',
      usage: const TokenUsage(input: 20),
      timestamp: yesterday,
    );

    final today = service.aggregate(BillPeriod.today, now: now);
    expect(today.requests, equals(1));
    expect(today.usage.input, equals(10));

    final last7 = service.aggregate(BillPeriod.last7d, now: now);
    expect(last7.requests, equals(2));

    final all = service.aggregate(BillPeriod.all, now: now);
    expect(all.requests, equals(2));
  });

  test('ledger persists across service instances', () async {
    service.record(
      key: 'usage_persist',
      provider: 'kimi',
      model: 'kimi-k3',
      usage: const TokenUsage(input: 1234, output: 567),
    );

    await service.flush();
    final reloaded = UsageLedgerService();
    await reloaded.init(baseDir: tempDir.path);
    final summary = reloaded.aggregate(BillPeriod.all);
    expect(summary.requests, equals(1));
    expect(summary.models.single.name, equals('kimi/kimi-k3'));
    expect(summary.models.single.usage.output, equals(567));
  });

  test('ledger file follows pi-bill structure', () async {
    service.record(
      key: 'usage_struct',
      provider: 'deepseek',
      model: 'deepseek-chat',
      usage: const TokenUsage(input: 100, output: 50, cacheRead: 10),
    );

    await service.flush();
    final file = File('${tempDir.path}/usage-ledger.json');
    final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    expect(data['version'], equals(2));

    final days = data['days'] as Map<String, dynamic>;
    expect(days.length, equals(1));
    final dayUsage = days.values.single as Map<String, dynamic>;
    final providerUsage = dayUsage['deepseek'] as Map<String, dynamic>;
    final modelUsage = providerUsage['deepseek-chat'] as Map<String, dynamic>;
    expect(modelUsage['input'], equals(100));
    expect(modelUsage['output'], equals(50));

    final keys = data['keys'] as Map<String, dynamic>;
    expect(keys.containsKey('usage_struct'), isTrue);
  });

  test(
    'v1 ledger migrates cached input once and retains missing reporting state',
    () async {
      final file = File('${tempDir.path}/usage-ledger.json');
      final legacy = {
        'version': 1,
        'days': <String, dynamic>{},
        'keys': {
          'old': {
            'day': '2026-09-06',
            'provider': 'p',
            'model': 'm',
            'usage': {
              'input': 1000,
              'output': 50,
              'cacheRead': 600,
              'cacheWrite': 0,
            },
          },
        },
      };
      file.writeAsStringSync(jsonEncode(legacy));
      final migrated = UsageLedgerService();
      await migrated.init(baseDir: tempDir.path);
      expect(migrated.aggregate(BillPeriod.all).usage.total, 1050);
      expect(jsonDecode(file.readAsStringSync())['version'], 1);
      migrated.record(
        key: 'new',
        provider: 'p',
        model: 'm',
        usage: const TokenUsage(input: 100),
      );
      await migrated.flush();
      final reloaded = UsageLedgerService();
      await reloaded.init(baseDir: tempDir.path);
      final usage = reloaded.aggregate(BillPeriod.all).usage;
      expect(usage.total, 1150);
      expect(usage.input, 500);
      expect(usage.cacheRead, 600);
      expect(usage.cacheReadReported, isFalse);
      expect(jsonDecode(file.readAsStringSync())['version'], 2);
    },
  );

  test('异步记账期间追加记录，flush 保存最新完整快照', () async {
    for (var i = 0; i < 40; i++) {
      service.record(
        key: 'batch_$i',
        provider: 'p',
        model: 'm',
        usage: const TokenUsage(input: 3, output: 2),
      );
      // 内存用量立即可读，不必等磁盘。
      expect(service.aggregate(BillPeriod.all).requests, i + 1);
      if (i % 5 == 0) await Future<void>.delayed(Duration.zero);
    }
    await service.flush();
    final reloaded = UsageLedgerService();
    await reloaded.init(baseDir: tempDir.path);
    expect(reloaded.aggregate(BillPeriod.all).requests, 40);
    expect(reloaded.aggregate(BillPeriod.all).usage.total, 200);
    expect(File('${tempDir.path}/usage-ledger.json.tmp').existsSync(), isFalse);
  });

  test('formatTokens renders K/M/B units', () {
    expect(UsageLedgerService.formatTokens(999), equals('999'));
    expect(UsageLedgerService.formatTokens(1234), equals('1.2K'));
    expect(UsageLedgerService.formatTokens(1234567), equals('1.2M'));
    expect(UsageLedgerService.formatTokens(1234567890), equals('1.2B'));
  });

  test('uninitialized service is a no-op', () {
    final idle = UsageLedgerService();
    expect(
      idle.record(
        key: 'k',
        provider: 'p',
        model: 'm',
        usage: const TokenUsage(input: 1),
      ),
      isFalse,
    );
    expect(idle.aggregate(BillPeriod.all).requests, equals(0));
  });
}
