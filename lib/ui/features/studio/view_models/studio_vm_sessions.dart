part of 'studio_view_model.dart';

/// 会话列表 / 切换 / 新建 / 删除 / 回溯
mixin _StudioSessionsMixin on _StudioCore {
  /// 刷新会话列表
  @override
  Future<void> refreshSessions() async {
    if (!_sessionLog.isInitialized) return;
    _sessions = await _sessionLog.listSessions();
    notifyListeners();
  }

  /// 切换至指定会话
  Future<void> switchSession(String sessionId) async {
    if (_isChatStreaming) {
      await abortChat();
    }
    final snapshot = _sessionLog.loadSession(sessionId);
    if (snapshot != null) {
      _harness.setMessages(snapshot.messages);
      _sessionModelUsage = {
        for (final e in snapshot.sessionUsage.entries)
          displayNameForModelKey(e.key): e.value,
      };
      if (snapshot.thinkingLevel != null) {
        final effort = ThinkingEffort.fromId(snapshot.thinkingLevel);
        if (effort != _currentThinkingEffort) {
          _currentThinkingEffort = effort;
          // 恢复的思考强度必须重建 Provider，否则只刷新 UI 不生效
          _setupHarnessAndTools();
        }
      }
      _statusMessage = '已切换会话: ${snapshot.sessionTitle ?? sessionId}';
    } else {
      _harness.setMessages([]);
      _sessionModelUsage = {};
    }
    // 新时间线：以当前工作台参数为基线重新起算
    _paramJournal.reset(_params);
    await refreshSessions();
    notifyListeners();
  }

  /// 创建全新会话
  Future<void> createNewSession({String? title}) async {
    if (_isChatStreaming) {
      await abortChat();
    }
    await _sessionLog.createSession(title: title);
    _harness.setMessages([]);
    _sessionModelUsage = {};
    _paramJournal.reset(_params);
    _statusMessage = '已创建新会话';
    await refreshSessions();
    notifyListeners();
  }

  /// 删除指定会话
  Future<void> deleteSession(String sessionId) async {
    final isCurrent = sessionId == currentSessionId;
    await _sessionLog.deleteSession(sessionId);
    if (isCurrent) {
      final remaining = await _sessionLog.listSessions();
      if (remaining.isNotEmpty) {
        await switchSession(remaining.first.id);
      } else {
        await createNewSession();
      }
    } else {
      await refreshSessions();
    }
    _statusMessage = '会话已删除';
    notifyListeners();
  }

  /// 重命名指定会话
  Future<void> renameSession(String sessionId, String newTitle) async {
    await _sessionLog.renameSession(sessionId, newTitle);
    await refreshSessions();
    notifyListeners();
  }

  // ------------------------- 历史回溯 -------------------------

  /// 回退/撤销到指定历史消息时刻 (按两次 ESC 触发选择)
  Future<void> rewindToMessage(String messageId) async {
    if (_isChatStreaming) {
      await abortChat();
    }

    // 截断前先取目标时刻，用于回滚工作台参数
    DateTime? targetTime;
    for (final msg in _harness.messages) {
      if (msg.id == messageId) {
        targetTime = msg.createdAt;
        break;
      }
    }

    final success = _harness.rewindToMessage(messageId);
    if (success) {
      // 将工作台参数一并回滚到目标时刻之前最近的状态
      var paramsRewound = false;
      final restored = targetTime == null
          ? null
          : _paramJournal.stateAt(targetTime);
      if (restored != null) {
        _paramJournal.truncateAfter(targetTime!);
        updateParams(restored);
        paramsRewound = true;
      }
      _recomputeSessionUsage();
      _statusMessage = paramsRewound
          ? '已回到历史时刻，后续对话与参数修改已撤回'
          : '已回到历史时刻，后续对话与修改已撤回';
      await refreshSessions();
      notifyListeners();
    }
  }
}
