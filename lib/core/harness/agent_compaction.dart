part of 'agent_harness.dart';

/// 单飞后台压缩：快照计算，版本校验后原子提交。
extension AgentCompaction on AgentHarness {
  Future<CompactionEvent?> compactContext({bool force = false}) {
    final pending = _pendingCompaction;
    if (pending != null) return pending;
    final run = _HarnessRun();
    _compactionRun = run;
    final revision = _contextRevision;
    final future = _compactSnapshot(force: force, run: run);
    _pendingCompaction = future;
    onContextChanged?.call();
    return future.whenComplete(() {
      if (revision == _contextRevision) {
        _pendingCompaction = null;
        _compactionRun = null;
        onContextChanged?.call();
      }
    });
  }

  Future<CompactionEvent?> _compactSnapshot({
    required bool force,
    required _HarnessRun run,
  }) async {
    if ((!force && !compactionEnabled) || provider == null) return null;
    final cut = _findCutIndex(force: force);
    if (cut <= _contextStartIndex) return null;
    final revision = _contextRevision;
    final tokensBefore = _estimateContextTokens();
    // 使用请求替身，避免已释放回复在摘要中复活。
    final ids = _messages
        .sublist(_contextStartIndex, cut)
        .map((m) => m.id)
        .toSet();
    final snapshot = _buildRequestMessages(
      '',
    ).where((m) => ids.contains(m.id)).toList();
    _compactionError = null;
    try {
      // 小窗口压缩模型分批迭代；保守字符预算确保中文也不会超窗。
      final budget = ((compactionModelWindowTokens * 0.45).floor() - 2048);
      if (budget < 256) throw StateError('压缩模型上下文窗口过小');
      final batches = <List<AgentMessage>>[];
      var batch = <AgentMessage>[];
      var used = 0;
      for (final m in snapshot) {
        final text = _serializeForSummary([m]);
        final chunkSize = budget.clamp(256, 50000);
        for (var start = 0; start < text.length; start += chunkSize) {
          final end = (start + chunkSize).clamp(0, text.length);
          final chunk = AgentMessage(
            id: m.id,
            role: AgentRole.user,
            content: text.substring(start, end),
          );
          final cost = AgentHarness._estimateTextTokens(chunk.content) + 16;
          if (used + cost > budget && batch.isNotEmpty) {
            batches.add(batch);
            batch = [];
            used = 0;
          }
          batch.add(chunk);
          used += cost;
        }
      }
      if (batch.isNotEmpty) batches.add(batch);
      String? summary = _compactionSummary;
      for (final part in batches) {
        summary = await _generateSummary(
          part,
          previousSummary: summary,
          run: run,
        );
        if (run.isCancelled || revision != _contextRevision) return null;
        if (summary == null) throw StateError('压缩模型未返回摘要');
        if (AgentHarness._estimateTextTokens(summary) >
            compactionModelWindowTokens ~/ 4) {
          throw StateError('压缩摘要过长，已保留原始上下文');
        }
      }
      if (summary == null || run.isCancelled || revision != _contextRevision) {
        return null;
      }
      final originalTokens =
          snapshot.fold<int>(0, (n, m) => n + _estimateMessageTokens(m)) +
          AgentHarness._estimateTextTokens(_compactionSummary ?? '');
      if (AgentHarness._estimateTextTokens(summary) >= originalTokens) {
        throw StateError('摘要未缩短上下文');
      }
      _compactionSummary = summary;
      _contextStartIndex = cut;
      // 当前主请求可能仍使用旧快照，连同其下一条响应用量一起失效。
      _usageFloor = _messages.length + (_activeRun != null ? 1 : 0);
      return CompactionEvent(
        summary: summary,
        tokensBefore: tokensBefore,
        tokensAfter: _estimateContextTokens(),
      );
    } catch (error) {
      if (!run.isCancelled && revision == _contextRevision) {
        _compactionError = '压缩失败：$error';
      }
      return null;
    }
  }
}
