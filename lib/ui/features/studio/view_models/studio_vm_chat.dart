part of 'studio_view_model.dart';

/// 对话流 / ask_user 提问 / 付费确认 / Token 用量记录
mixin _StudioChatMixin on _StudioCore {
  /// 流式增量通知节流计时器：Thought/Content 增量按 ~40ms 批量刷新，
  /// 避免每个 token 触发一次全工作台重建导致的掉帧。
  Timer? _streamNotifyTimer;
  bool _streamNotifyPending = false;

  /// 流式增量专用：合并 40ms 窗口内的连续增量后统一 notifyListeners
  void _notifyStreamDelta() {
    _streamNotifyPending = true;
    final timer = _streamNotifyTimer;
    if (timer == null || !timer.isActive) {
      _streamNotifyTimer = Timer(
        const Duration(milliseconds: 40),
        _flushStreamDeltaNotify,
      );
    }
  }

  void _flushStreamDeltaNotify() {
    _streamNotifyTimer = null;
    if (!_streamNotifyPending) return;
    _streamNotifyPending = false;
    notifyListeners();
  }

  /// 立即刷新：取消挂起的节流批次，保证状态即时可见
  void _notifyNow() {
    _streamNotifyTimer?.cancel();
    _streamNotifyTimer = null;
    _streamNotifyPending = false;
    notifyListeners();
  }

  /// 发送对话消息 (支持 Slash 命令行；[images] 为用户粘贴/上传的图片附件，
  /// 仅普通对话路径生效，斜杠指令不支持附带图片)
  @override
  Future<void> sendChatMessage(
    String text, {
    List<AgentMessageImage>? images,
  }) async {
    final trimmed = text.trim();
    final hasImages = images != null && images.isNotEmpty;
    if (trimmed.isEmpty && !hasImages) return;

    // 斜杠指令不支持附带图片
    if (trimmed.startsWith('/') && hasImages) {
      _errorMessage = '斜杠指令不支持附带图片，请直接发送对话消息';
      notifyListeners();
      return;
    }

    // 流式进行中禁止重入：并发监听会往同一流式缓冲写入，造成重复文本
    if (_isChatStreaming) return;

    // 1. 处理 Slash 指令 (指令内部可能发起网络请求，统一兜底避免未捕获异常)
    if (trimmed.startsWith('/')) {
      try {
        await _handleSlashCommand(trimmed);
      } catch (e) {
        _errorMessage = '指令执行失败: $e';
        notifyListeners();
      }
      return;
    }

    // 2. 正常 Agent 对话循环 (发出前记录参数快照，供回溯时回滚)
    _isChatStreaming = true;
    _currentStreamingThoughts = '';
    _currentStreamingContent = '';
    _streamingRetryNotice = null;
    _errorMessage = null;
    _paramJournal.record(_params);
    notifyListeners();

    final completer = Completer<void>();

    try {
      final stream = _harness.send(
        trimmed,
        temperature: _config.llmTemperature,
        images: images,
      );

      _chatSubscription = stream.listen(
        (event) {
          if (event is ThoughtDeltaEvent) {
            _currentStreamingThoughts += event.delta;
            _notifyStreamDelta();
          } else if (event is ContentDeltaEvent) {
            _currentStreamingContent += event.delta;
            _notifyStreamDelta();
          } else if (event is TurnStartEvent) {
            // 工具循环每轮开始：清空流式气泡，上一轮正文已作为独立消息
            // 落入列表，若不清会把上一轮文本残留拼进本轮造成“重复语句”
            _currentStreamingThoughts = '';
            _currentStreamingContent = '';
            _streamingRetryNotice = null;
            notifyListeners();
          } else if (event is RetryEvent) {
            // 瞬态错误自动重试：在流式气泡顶部提示用户，等待退避后重发
            _streamingRetryNotice =
                '请求失败自动重试 (${event.attempt}/${event.maxAttempts}): '
                '${event.reason} · '
                '${event.delay.inSeconds > 0 ? '${event.delay.inSeconds} 秒后' : '即将'}重试';
            _notifyNow();
          } else if (event is UsageEvent) {
            _recordModelUsage(event.usage);
          } else if (event is ToolResultEvent) {
            _notifyNow();
          } else if (event is ErrorEvent) {
            _errorMessage = event.error;
            _notifyNow();
          }
        },
        onError: (e) {
          _errorMessage = '对话异常: $e';
          if (!completer.isCompleted) completer.complete();
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
        cancelOnError: true,
      );

      await completer.future;
    } catch (e) {
      _errorMessage = '对话异常: $e';
    } finally {
      _chatSubscription = null;
      _isChatStreaming = false;
      _currentStreamingThoughts = '';
      _currentStreamingContent = '';
      _streamingRetryNotice = null;
      await refreshSessions();
      _notifyNow();
    }
  }

  /// 强行中止当前对话生成与工具执行 (ESC 触发)
  @override
  Future<void> abortChat() async {
    if (!_isChatStreaming) return;
    await _chatSubscription?.cancel();
    _chatSubscription = null;
    _isChatStreaming = false;
    _currentStreamingThoughts = '';
    _currentStreamingContent = '';
    _streamingRetryNotice = null;
    _statusMessage = '已强制终止当前生成';
    _notifyNow();
  }

  // ------------------------- ask_user 与付费确认 -------------------------

  /// 呈现 AI 提问卡片 (内嵌于 AgentCard 对话流中)
  @override
  Future<List<String>?> _presentQuestionsToUser(
    List<AgentQuestion> questions,
  ) async {
    final completer = Completer<List<String>?>();
    _activeQuestionPrompt = AgentQuestionPrompt(
      questions: questions,
      completer: completer,
    );
    notifyListeners();

    try {
      final answers = await completer.future;
      return answers;
    } finally {
      _activeQuestionPrompt = null;
      notifyListeners();
    }
  }

  /// 付费生图申请确认 (内嵌于对话流，纯选择按钮，禁止自定义文本框)
  @override
  Future<bool> _confirmPaidGeneration({
    required NaiGenerationParams params,
    required int estimatedCost,
  }) async {
    final reasons = buildPaidGenerationReasons(params);
    final reasonText = reasons.isEmpty ? '当前账号无 Opus 免费额度' : reasons.join('、');
    final costText = estimatedCost > 0
        ? '预计消耗 $estimatedCost Anlas 点数'
        : '将消耗 Anlas 点数';
    final answer = await _presentQuestionsToUser([
      AgentQuestion(
        header: '点数消耗申请',
        question: '本次生图参数（$reasonText）$costText。是否确认生成？',
        allowCustomInput: false,
        options: const [
          AgentQuestionOption(label: '确认生成', description: '使用当前参数直接生图并扣除点数'),
          AgentQuestionOption(label: '取消生图', description: '取消本次生成，调整参数至免费区间'),
        ],
      ),
    ]);

    if (answer == null || answer.isEmpty) return false;
    return answer.first.contains('确认生成');
  }

  /// 付费超分确认 (内嵌于对话流，纯选择按钮)
  @override
  Future<bool> _confirmPaidUpscale({
    required int estimatedCost,
    required int inputWidth,
    required int inputHeight,
  }) async {
    final answer = await _presentQuestionsToUser([
      AgentQuestion(
        header: '点数消耗申请',
        question:
            '将输入尺寸 ${inputWidth}x$inputHeight 的图片执行官方超分放大，'
            '预计消耗 $estimatedCost Anlas 点数。是否确认放大？',
        allowCustomInput: false,
        options: const [
          AgentQuestionOption(label: '确认放大', description: '执行官方超分并扣除点数'),
          AgentQuestionOption(label: '取消放大', description: '取消本次超分操作'),
        ],
      ),
    ]);

    if (answer == null || answer.isEmpty) return false;
    return answer.first.contains('确认放大');
  }

  // ------------------------- Token 用量 -------------------------

  /// 记录一次模型响应的 Token 用量: 会话内聚合 + 持久化账本
  void _recordModelUsage(TokenUsage usage) {
    final providerId = _harness.providerLabel ?? 'unknown';
    final modelId = _harness.provider?.modelId ?? 'unknown';
    final key = '$providerId/$modelId';
    _sessionModelUsage[key] = (_sessionModelUsage[key] ?? const TokenUsage())
        .add(usage);
    _usageLedger.record(
      key: 'usage_${DateTime.now().microsecondsSinceEpoch}',
      provider: providerId,
      model: modelId,
      usage: usage,
    );
    notifyListeners();
  }

  /// 从剩余消息中重新聚合本会话各模型用量 (回溯/清空后调用)
  @override
  void _recomputeSessionUsage() {
    final updatedUsage = <String, TokenUsage>{};
    for (final msg in _harness.messages) {
      if (msg.role == AgentRole.assistant &&
          msg.providerModelKey != null &&
          (msg.usage?.total ?? 0) > 0) {
        final key = displayNameForModelKey(msg.providerModelKey!);
        updatedUsage[key] = (updatedUsage[key] ?? const TokenUsage()).add(
          msg.usage!,
        );
      }
    }
    _sessionModelUsage = updatedUsage;
  }
}
