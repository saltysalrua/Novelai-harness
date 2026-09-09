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

  String forgetReply(int number) {
    final index = _messages.indexWhere((m) => m.replyNumber == number);
    if (index < _contextStartIndex || index < 0) {
      throw StateError('该回复不存在或已进入摘要，不能单独释放');
    }
    final lastUser = _messages.lastIndexWhere((m) => m.role == AgentRole.user);
    if (index >= lastUser) throw StateError('当前用户轮次的回复不能释放');
    memory.forgetReply(number);
    memoryChanged();
    return '已释放回复 #$number 及其工具结果；原始历史保留。';
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
