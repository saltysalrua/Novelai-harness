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
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  test('record writes ledger file and aggregates by model', () {
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

    final reloaded = UsageLedgerService();
    await reloaded.init(baseDir: tempDir.path);
    final summary = reloaded.aggregate(BillPeriod.all);
    expect(summary.requests, equals(1));
    expect(summary.models.single.name, equals('kimi/kimi-k3'));
    expect(summary.models.single.usage.output, equals(567));
  });

  test('ledger file follows pi-bill structure', () {
    service.record(
      key: 'usage_struct',
      provider: 'deepseek',
      model: 'deepseek-chat',
      usage: const TokenUsage(input: 100, output: 50, cacheRead: 10),
    );

    final file = File('${tempDir.path}/usage-ledger.json');
    final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    expect(data['version'], equals(1));

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
