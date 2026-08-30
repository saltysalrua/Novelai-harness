import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/data/models/novelai_models.dart';
import 'package:novelai_harness/ui/features/studio/view_models/param_snapshot_journal.dart';

void main() {
  group('ParamSnapshotJournal', () {
    test('reset 写入基线后 stateAt 返回基线', () {
      final journal = ParamSnapshotJournal();
      final t0 = DateTime(2026, 1, 1, 10, 0, 0);
      final baseline = const NaiGenerationParams(prompt: 'base');

      expect(journal.isEmpty, isTrue);
      journal.reset(baseline, at: t0);

      expect(journal.isEmpty, isFalse);
      expect(journal.stateAt(t0), same(baseline));
      // 晚于基线的时刻也取基线
      expect(journal.stateAt(t0.add(const Duration(hours: 1))), same(baseline));
    });

    test('record 多个快照后 stateAt 取该时刻之前最近一次的状态', () {
      final journal = ParamSnapshotJournal();
      final t0 = DateTime(2026, 1, 1, 10, 0, 0);
      final t1 = t0.add(const Duration(minutes: 1));
      final t2 = t0.add(const Duration(minutes: 2));

      final p0 = const NaiGenerationParams(prompt: 'p0');
      final p1 = p0.copyWith(steps: 10);
      final p2 = p1.copyWith(steps: 20);

      journal.reset(p0, at: t0);
      journal.record(p1, at: t1);
      journal.record(p2, at: t2);

      // 恰好等于某快照时刻 → 取该快照
      expect(journal.stateAt(t1), same(p1));
      // 介于两次快照之间 → 取较早的一次
      expect(journal.stateAt(t1.add(const Duration(seconds: 30))), same(p1));
      expect(journal.stateAt(t2), same(p2));
    });

    test('stateAt 早于全部快照时返回 null', () {
      final journal = ParamSnapshotJournal();
      final t0 = DateTime(2026, 1, 1, 10, 0, 0);
      journal.reset(const NaiGenerationParams(prompt: 'base'), at: t0);

      expect(journal.stateAt(t0.subtract(const Duration(seconds: 1))), isNull);
    });

    test('truncateAfter 丢弃之后的快照，保留时间线一致性', () {
      final journal = ParamSnapshotJournal();
      final t0 = DateTime(2026, 1, 1, 10, 0, 0);
      final t1 = t0.add(const Duration(minutes: 1));
      final t2 = t0.add(const Duration(minutes: 2));

      final p0 = const NaiGenerationParams(prompt: 'p0');
      final p1 = p0.copyWith(steps: 10);
      final p2 = p1.copyWith(steps: 20);

      journal.reset(p0, at: t0);
      journal.record(p1, at: t1);
      journal.record(p2, at: t2);

      journal.truncateAfter(t1);

      // t2 的快照被丢弃：任何时刻查询都拿不到 p2
      expect(journal.stateAt(t2), same(p1));
      expect(journal.stateAt(t1), same(p1));
      expect(journal.stateAt(t0), same(p0));
    });

    test('reset 清空旧时间线重新起算', () {
      final journal = ParamSnapshotJournal();
      final t0 = DateTime(2026, 1, 1, 10, 0, 0);
      final t1 = t0.add(const Duration(minutes: 1));
      final t2 = t0.add(const Duration(minutes: 2));

      journal.reset(const NaiGenerationParams(prompt: 'old'), at: t0);
      journal.reset(const NaiGenerationParams(prompt: 'new'), at: t2);

      // 新基线之前的时刻无快照可用
      expect(journal.stateAt(t1), isNull);
      expect(journal.stateAt(t2)?.prompt, 'new');
    });
  });
}
