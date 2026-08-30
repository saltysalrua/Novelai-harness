import '../../../../data/models/novelai_models.dart';

/// 工作台参数时间点快照条目
class ParamSnapshot {
  final DateTime at;
  final NaiGenerationParams params;

  const ParamSnapshot(this.at, this.params);
}

/// 工作台参数时间轴快照账本。
///
/// 在会话时间轴的关键节点 (ViewModel 初始化、每轮用户消息发出前、会话切换/清空)
/// 记录生图参数快照；回溯到某个历史时刻时，用 [stateAt] 取该时刻之前最近一次的
/// 参数状态，把工作台参数一并回滚，保证“回到历史时刻”同时撤销该时刻之后的参数修改。
class ParamSnapshotJournal {
  final List<ParamSnapshot> _entries = [];

  /// 当前时间轴是否已有快照
  bool get isEmpty => _entries.isEmpty;

  /// 清空时间轴并写入新基线 (会话切换/新建/清空时调用)
  void reset(NaiGenerationParams baseline, {DateTime? at}) {
    _entries
      ..clear()
      ..add(ParamSnapshot(at ?? DateTime.now(), baseline));
  }

  /// 记录一次参数状态
  void record(NaiGenerationParams params, {DateTime? at}) {
    _entries.add(ParamSnapshot(at ?? DateTime.now(), params));
  }

  /// 取 [moment] 时刻 (含) 之前最近一次的参数状态；早于全部快照时返回 null。
  /// (快照在用户消息发出之前记录，时间戳恒 <= 该消息的 createdAt。)
  NaiGenerationParams? stateAt(DateTime moment) {
    ParamSnapshot? found;
    for (final entry in _entries) {
      if (!entry.at.isAfter(moment)) found = entry;
    }
    return found?.params;
  }

  /// 丢弃 [moment] 之后的所有快照，使时间轴与回溯后的消息保持同一时间线
  void truncateAfter(DateTime moment) {
    _entries.removeWhere((e) => e.at.isAfter(moment));
  }
}
