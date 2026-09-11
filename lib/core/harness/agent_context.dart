part of 'agent_harness.dart';

/// 请求上下文生命周期与会话记忆，不依赖 Flutter。
extension AgentContext on AgentHarness {
  ContextUsage get contextUsage => ContextUsage(
    tokens: _estimateContextTokens(buildSystemPrompt(currentPreset)),
    window: contextWindowTokens,
    compacting: _pendingCompaction != null,
    noteCount: memory.notes.length,
    error: _compactionError,
  );

  int get _hardContextLimit => contextWindowTokens <= 0
      ? 1
      : contextWindowTokens -
            compactionReserveTokens.clamp(
              1,
              (contextWindowTokens ~/ 4).clamp(1, contextWindowTokens),
            );

  void dispose() {
    abort();
    _invalidateCompaction();
    onContextChanged = null;
    onCompactionUsage = null;
  }

  void _invalidateCompaction() {
    _contextRevision++;
    _compactionRun?.cancel();
    _compactionRun = null;
    _pendingCompaction = null;
    _lastBackgroundSize = -1;
  }

  void memoryChanged() {
    _invalidateCompaction();
    _usageFloor = _messages.length + (_activeRun != null ? 1 : 0);
    onContextChanged?.call();
  }

  /// 返回该回复无法释放的原因，可释放时返回 null
  String? _releaseBlocker(int number) {
    final index = _messages.indexWhere((m) => m.replyNumber == number);
    if (index < _contextStartIndex || index < 0) {
      return '不存在或已进入摘要，不能单独释放';
    }
    final lastUser = _messages.lastIndexWhere((m) => m.role == AgentRole.user);
    if (index >= lastUser) return '属于当前用户轮次，不能释放';
    return null;
  }

  String forgetReply(int number) {
    final blocker = _releaseBlocker(number);
    if (blocker != null) throw StateError('该回复$blocker');
    memory.forgetReply(number);
    memoryChanged();
    return '已释放回复 #$number 及其工具结果；原始历史保留。';
  }

  /// 批量释放旧回复：逐项处理，单项失败不影响其余，只触发一次上下文变更通知。
  String forgetReplies(Iterable<int> numbers) {
    final ids = numbers.toSet().toList()..sort();
    if (ids.isEmpty) throw ArgumentError('需要至少一个回复编号');
    final released = <int>[];
    final blocked = <String>[];
    for (final number in ids) {
      final blocker = _releaseBlocker(number);
      if (blocker != null) {
        blocked.add('#$number ($blocker)');
        continue;
      }
      memory.forgetReply(number);
      released.add(number);
    }
    if (released.isEmpty) {
      throw StateError('没有可释放的回复：${blocked.join('、')}');
    }
    memoryChanged();
    final buffer = StringBuffer(
      '已释放回复 ${released.map((n) => '#$n').join('、')} 及其工具结果；',
    );
    if (blocked.isNotEmpty) {
      buffer.write('未释放 ${blocked.join('、')}；');
    }
    buffer.write('原始历史保留。');
    return buffer.toString();
  }

  Map<String, Object?> exportContextState() => {
    'messageIds': _messages.map((m) => m.id).toList(),
    'summary': _compactionSummary,
    'start': _contextStartIndex,
    'replySequence': _replySequence,
    'memory': memory.toJson(),
  };

  void restoreContextState(Map<String, Object?> state) {
    final ids = state['messageIds'];
    if (ids is! List || ids.length > _messages.length) return;
    for (var i = 0; i < ids.length; i++) {
      if (ids[i] != _messages[i].id) return;
    }
    _invalidateCompaction();
    if (state['memory'] case final Map<String, Object?> data) {
      memory.restore(data);
    }
    if (state['start'] case final int start
        when start >= 0 && start <= ids.length) {
      if (state['summary'] case final String summary when summary.isNotEmpty) {
        _contextStartIndex = start;
        _compactionSummary = summary;
      }
    }
    if (state['replySequence'] case final int next when next > _replySequence) {
      _replySequence = next;
    }
    _usageFloor = _messages.length;
  }
}
