part of 'studio_view_model.dart';

/// 会话列表 / 切换 / 新建 / 删除 / 回溯
mixin _StudioSessionsMixin on _StudioCore {
  int _sessionNavigationEpoch = 0;

  /// 刷新会话列表
  @override
  Future<void> refreshSessions() async {
    if (!_sessionLog.isInitialized) return;
    _sessions = await _sessionLog.listSessions();
    notifyListeners();
  }

  /// 切换至指定会话
  Future<void> switchSession(String sessionId) async {
    final epoch = ++_sessionNavigationEpoch;
    if (_isChatStreaming) {
      await abortChat();
    }
    _harness.memoryChanged();
    await _sessionLog.flush();
    if (epoch != _sessionNavigationEpoch) return;
    final snapshot = await _sessionLog.loadSessionAsync(sessionId);
    if (epoch != _sessionNavigationEpoch) return;
    if (snapshot != null) {
      _harness.setMessages(snapshot.messages);
      _harness.restoreContextState(_sessionLog.loadContextState());
      _sessionModelUsage = {
        for (final e in snapshot.sessionUsage.entries)
          displayNameForModelKey(e.key): e.value,
      };
      if (snapshot.thinkingLevel != null) {
        final effort = _config.activeLlmProvider.activeModel
            .normalizeThinkingEffort(
              ThinkingEffort.fromId(snapshot.thinkingLevel),
            );
        if (effort != _currentThinkingEffort) {
          _currentThinkingEffort = effort;
          // 恢复的思考强度必须重建 Provider，否则只刷新 UI 不生效
          _setupHarnessAndTools();
        }
      }
      _statusMessage = vmL10n.vmSessionSwitched(
        snapshot.sessionTitle ?? sessionId,
      );
    } else {
      _harness.setMessages([]);
      _sessionModelUsage = {};
    }
    // 新时间线：以当前工作台参数为基线重新起算
    _paramJournal.reset(_params);
    _composerRestore = null;
    await refreshSessions();
    notifyListeners();
  }

  /// 创建全新会话
  @override
  Future<void> createNewSession({String? title}) async {
    final epoch = ++_sessionNavigationEpoch;
    if (_isChatStreaming) {
      await abortChat();
    }
    _harness.memoryChanged();
    if (epoch != _sessionNavigationEpoch) return;
    await _sessionLog.createSession(title: title);
    if (epoch != _sessionNavigationEpoch) return;
    _harness.setMessages([]);
    _sessionModelUsage = {};
    _paramJournal.reset(_params);
    _composerRestore = null;
    _statusMessage = vmL10n.vmSessionCreated;
    await refreshSessions();
    notifyListeners();
  }

  /// 删除指定会话
  Future<void> deleteSession(String sessionId) => deleteSessions([sessionId]);

  /// 批量删除只刷新一次；先中止当前会话，避免删除后又被流式记录重新写回。
  Future<void> deleteSessions(Iterable<String> sessionIds) async {
    final ids = sessionIds.toSet();
    if (ids.isEmpty) return;
    _sessionNavigationEpoch++;
    final isCurrent = ids.contains(currentSessionId);
    if (isCurrent && _isChatStreaming) await abortChat();
    if (isCurrent) _harness.memoryChanged();
    for (final id in ids) {
      await _sessionLog.deleteSession(id);
    }
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
    _statusMessage = vmL10n.vmSessionDeleted;
    notifyListeners();
  }

  /// 重命名指定会话
  @override
  Future<void> renameSession(String sessionId, String newTitle) async {
    await _sessionLog.renameSession(sessionId, newTitle);
    await refreshSessions();
    notifyListeners();
  }

  // ------------------------- 历史回溯 -------------------------

  /// 回退到指定历史消息。
  ///
  /// 用户消息：截断该条及之后的对话，文本和图片放回输入框，不发送。
  /// 其他消息：保留该条，只丢弃其后的内容。
  @override
  Future<void> rewindToMessage(String messageId) async {
    if (_isChatStreaming) {
      await abortChat();
    }

    AgentMessage? target;
    for (final msg in _harness.messages) {
      if (msg.id == messageId) {
        target = msg;
        break;
      }
    }
    if (target == null) return;

    final targetTime = target.createdAt;
    final restoreToInput = target.role == AgentRole.user;
    final removed = restoreToInput
        ? _harness.rewindBeforeMessage(messageId)
        : null;
    final truncated = restoreToInput
        ? removed != null
        : _harness.rewindToMessage(messageId);
    if (!truncated) return;

    final restoredParams = _paramJournal.stateAt(targetTime);
    if (restoredParams != null) {
      _paramJournal.truncateAfter(targetTime);
    }
    if (removed != null) {
      _publishComposerRestore(removed.content, removed.images);
    }
    var paramsRewound = false;
    if (restoredParams != null) {
      updateParams(restoredParams);
      paramsRewound = true;
    }
    _recomputeSessionUsage();
    _statusMessage = restoreToInput
        ? (paramsRewound
              ? vmL10n.vmRewindToInputWithParams
              : vmL10n.vmRewindToInput)
        : (paramsRewound
              ? vmL10n.vmRewindChatAndParams
              : vmL10n.vmRewindChatOnly);
    await refreshSessions();
    notifyListeners();
  }

  void _publishComposerRestore(String text, List<AgentMessageImage> images) {
    _composerRestoreEpoch++;
    _composerRestore = ComposerRestore(
      epoch: _composerRestoreEpoch,
      text: text,
      images: List<AgentMessageImage>.unmodifiable(images),
    );
    _chatDraft = text;
    _chatDraftSaveTimer?.cancel();
    unawaited(_configService.saveChatDraft(text));
  }
}
