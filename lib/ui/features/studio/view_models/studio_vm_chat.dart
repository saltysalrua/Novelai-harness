part of 'studio_view_model.dart';

/// 对话流 / ask_user 提问 / 付费确认 / Token 用量记录
mixin _StudioChatMixin on _StudioCore {
  /// 立即全局刷新：仅用于低频结构变化 (消息列表变更 / 流开始结束 / 错误等)。
  /// 思考链与正文的高频增量由 [streamingText] 控制器局部刷新，
  /// 不再触发全工作台 notifyListeners()。
  void _notifyNow() => notifyListeners();

  /// 当前 Agent 对话草稿输入文本
  String get chatDraft => _chatDraft;

  /// 更新 Agent 对话草稿输入文本 (300ms 防抖落盘)
  void updateChatDraft(String draft) {
    if (_chatDraft == draft) return;
    _chatDraft = draft;
    _chatDraftSaveTimer?.cancel();
    _chatDraftSaveTimer = Timer(const Duration(milliseconds: 300), () {
      _configService.saveChatDraft(_chatDraft);
    });
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
      _errorMessage = vmL10n.vmChatSlashNoImage;
      notifyListeners();
      return;
    }

    // 流式进行中禁止重入：并发监听会往同一流式缓冲写入，造成重复文本
    if (_isChatStreaming) return;

    // 发送消息后清空草稿
    _chatDraft = '';
    _chatDraftSaveTimer?.cancel();
    unawaited(_configService.saveChatDraft(''));

    // 1. 处理 Slash 指令 (指令内部可能发起网络请求，统一兜底避免未捕获异常)
    if (trimmed.startsWith('/')) {
      try {
        await _handleSlashCommand(trimmed);
      } catch (e) {
        _errorMessage = vmL10n.vmChatSlashFailed('$e');
        notifyListeners();
      }
      return;
    }

    // 2. 正常 Agent 对话循环 (发出前记录参数快照，供回溯时回滚)
    _isChatStreaming = true;
    _streamingText.reset();
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
            // 高频增量：只驱动对话气泡局部刷新 (40ms 批量)
            _streamingText.appendThoughts(event.delta);
          } else if (event is ContentDeltaEvent) {
            _streamingText.appendContent(event.delta);
          } else if (event is TurnStartEvent) {
            // 工具循环每轮开始：清空流式气泡，上一轮正文已作为独立消息
            // 落入列表，若不清会把上一轮文本残留拼进本轮造成“重复语句”
            _streamingText.reset();
            // 上一轮消息已定稿入列，消息列表结构变化需全局通知
            notifyListeners();
          } else if (event is RetryEvent) {
            // 瞬态错误自动重试：在流式气泡顶部提示用户，等待退避后重发
            // (低频但即时可见，局部立即刷新)
            _streamingText.setNotice(
              vmL10n.vmChatRetryNotice(
                event.attempt,
                event.maxAttempts,
                event.reason,
                event.delay.inSeconds > 0
                    ? vmL10n.vmChatRetryDelayed(event.delay.inSeconds)
                    : vmL10n.vmChatRetrySoon,
              ),
            );
          } else if (event is UsageEvent) {
            _recordModelUsage(event.usage);
          } else if (event is CompactionEvent) {
            // 上下文自动压缩完成：状态栏提示 (原始消息仍完整保留在对话流中)
            _statusMessage = vmL10n.vmChatCompacted(
              event.tokensBefore,
              event.tokensAfter,
            );
            _notifyNow();
          } else if (event is ToolResultEvent) {
            _notifyNow();
          } else if (event is ErrorEvent) {
            _errorMessage = event.error;
            _notifyNow();
          }
        },
        onError: (e) {
          _errorMessage = vmL10n.vmChatError('$e');
          if (!completer.isCompleted) completer.complete();
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
        cancelOnError: true,
      );

      await completer.future;
    } catch (e) {
      _errorMessage = vmL10n.vmChatError('$e');
    } finally {
      _chatSubscription = null;
      _isChatStreaming = false;
      _streamingText.reset();
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
    _streamingText.reset();
    _statusMessage = vmL10n.vmChatForceAborted;
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
    final reasonText = reasons.isEmpty
        ? vmL10n.vmCostNoOpusQuota
        : reasons.join('、');
    final costText = estimatedCost > 0
        ? vmL10n.vmCostEstimate(estimatedCost)
        : vmL10n.vmCostWillCost;
    final answer = await _presentQuestionsToUser([
      AgentQuestion(
        header: vmL10n.vmCostTitle,
        question: vmL10n.vmCostGenQuestion(reasonText, costText),
        allowCustomInput: false,
        options: [
          AgentQuestionOption(
            label: vmL10n.vmCostGenConfirm,
            description: vmL10n.vmCostGenConfirmDesc,
          ),
          AgentQuestionOption(
            label: vmL10n.vmCostGenCancel,
            description: vmL10n.vmCostGenCancelDesc,
          ),
        ],
      ),
    ]);

    if (answer == null || answer.isEmpty) return false;
    return answer.first.contains(vmL10n.vmCostGenConfirm);
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
        header: vmL10n.vmCostTitle,
        question: vmL10n.vmCostUpscaleQuestion(
          inputWidth,
          inputHeight,
          estimatedCost,
        ),
        allowCustomInput: false,
        options: [
          AgentQuestionOption(
            label: vmL10n.vmCostUpscaleConfirm,
            description: vmL10n.vmCostUpscaleConfirmDesc,
          ),
          AgentQuestionOption(
            label: vmL10n.vmCostUpscaleCancel,
            description: vmL10n.vmCostUpscaleCancelDesc,
          ),
        ],
      ),
    ]);

    if (answer == null || answer.isEmpty) return false;
    return answer.first.contains(vmL10n.vmCostUpscaleConfirm);
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
