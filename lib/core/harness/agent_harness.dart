import 'dart:async';
import 'presets/agent_preset.dart';
import 'providers/llm_provider.dart';
import 'session_recorder.dart';
import 'skills/skills.dart';
import 'tools/agent_tool.dart';
import 'types.dart';

/// 核心 Agent Harness 控制器 (借鉴 Pi 的极简响应式设计)
class AgentHarness {
  final ToolRegistry tools;
  LlmProvider? provider;
  AgentPreset? _currentPreset;

  /// 单次对话 (send 调用) 内允许的最大工具链式调用轮数。
  /// 达到上限后注入收尾提示并追加一轮无工具的强制总结。
  int maxTurns;

  /// 单轮流式请求的总尝试上限 (含首次，瞬态错误指数退避重试 + 空响应保护共用此预算)
  int maxRetryAttempts;

  /// 瞬态重试的基础退避时长，按 2^n 指数增长 (1s / 2s / 4s...)，测试可注入 Duration.zero
  Duration retryBaseDelay;

  AgentPreset get currentPreset => _currentPreset ?? BuiltinPresets.v5Architect;
  set currentPreset(AgentPreset preset) => _currentPreset = preset;

  /// 供应商标识 (如 'deepseek')，仅用于会话记录元数据
  String? providerLabel;

  /// 会话记录器 (按 Pi 会话格式落盘，可为空)
  final SessionRecorder? recorder;

  final List<AgentMessage> _messages = [];

  AgentHarness({
    required this.tools,
    this.provider,
    this.providerLabel,
    this.recorder,
    AgentPreset? initialPreset,
    this.maxTurns = 30,
    this.maxRetryAttempts = 3,
    this.retryBaseDelay = const Duration(seconds: 1),
  }) : _currentPreset = initialPreset ?? BuiltinPresets.v5Architect;

  List<AgentMessage> get messages => List.unmodifiable(_messages);

  /// 切换当前激活的预设
  void setPreset(AgentPreset preset) {
    currentPreset = preset;
  }

  /// 构建本轮对话的完整系统提示词
  /// (预设人设/工作流 + Pi 标准 available_skills 按需加载声明)
  String buildSystemPrompt(AgentPreset preset) {
    final buffer = StringBuffer(preset.systemPrompt.trim());
    final enabledSkills = preset.enabledSkillIds
        .map((id) => BuiltinSkills.findById(id))
        .whereType<Skill>()
        .toList();
    if (enabledSkills.isNotEmpty) {
      final skillsXml = Skill.formatSkillsForSystemPrompt(enabledSkills);
      if (skillsXml.isNotEmpty) {
        buffer.writeln('\n\n$skillsXml');
      }
    }
    return buffer.toString();
  }

  /// 发送用户消息并启动 Agent 循环流
  /// [images] 为可选的用户图片附件 (粘贴/上传，随消息发送给视觉模型)
  Stream<HarnessEvent> send(
    String userText, {
    double temperature = 0.7,
    List<AgentMessageImage>? images,
  }) async* {
    final hasImages = images != null && images.isNotEmpty;
    if (userText.trim().isEmpty && !hasImages) return;

    // 1. 记录用户消息
    final userMsgId = 'user_${DateTime.now().millisecondsSinceEpoch}';
    final userMsg = AgentMessage(
      id: userMsgId,
      role: AgentRole.user,
      content: userText.trim(),
      images: images ?? const [],
    );
    _messages.add(userMsg);
    recorder?.recordMessage(userMsg);

    if (provider == null) {
      yield ErrorEvent('未配置 LLM 提供商，请在设置中配置 API Key。');
      return;
    }

    // 2. 一次性构建本轮上下文：系统提示词与工具白名单在循环内保持不变
    final systemPrompt = buildSystemPrompt(currentPreset);
    final activeTools = tools
        .getAll()
        .where((tool) => currentPreset.isToolEnabled(tool.name))
        .toList();

    // 长程执行循环：
    // - 每轮流式请求对瞬态错误 (网络抖动 / 429 / 5xx / 流中断 / 空响应)
    //   自动指数退避重试，预算耗尽才报错终止；
    // - 工具轮数达到 [maxTurns] 后注入收尾提示，追加一轮无工具的
    //   强制总结轮，保证对话永远以最终回答收尾而不是悬挂的工具结果。
    int completedToolTurns = 0;
    bool wrapUpMode = false;

    while (true) {
      final toolsForTurn = wrapUpMode ? const <AgentTool>[] : activeTools;

      // ---- 单轮流式请求 + 自动重试 ----
      AgentMessage? assistantMsg;
      String? giveUpReason;
      int attempt = 0;

      while (assistantMsg == null && giveUpReason == null) {
        attempt++;
        final assistantMsgId =
            'asst_${DateTime.now().microsecondsSinceEpoch}_$attempt';
        yield TurnStartEvent(assistantMsgId);

        String content = '';
        String thoughts = '';
        TokenUsage? usage;
        String? errorMessage;
        bool errorTransient = false;
        final List<ToolCall> toolCalls = [];

        final stream = provider!.streamChat(
          messages: [
            AgentMessage(
              id: 'system_prompt',
              role: AgentRole.system,
              content: systemPrompt,
            ),
            ..._messages,
          ],
          tools: toolsForTurn,
          temperature: temperature,
          promptCacheKey: recorder?.sessionId,
        );

        await for (final event in stream) {
          if (event is ThoughtDeltaEvent) {
            thoughts += event.delta;
            yield event;
          } else if (event is ContentDeltaEvent) {
            content += event.delta;
            yield event;
          } else if (event is ToolCallEvent) {
            toolCalls.add(event.toolCall);
            yield event;
          } else if (event is UsageEvent) {
            usage = event.usage;
            yield event;
          } else if (event is ErrorEvent) {
            // 错误不直接透传：可重试时用 RetryEvent 呈现，彻底失败才统一报错
            errorMessage = event.error;
            errorTransient = event.transient;
          }
        }

        // 瞬态错误: 指数退避后重试同轮请求 (上下文未变，可安全重发)
        if (errorMessage != null) {
          if (errorTransient && attempt < maxRetryAttempts) {
            final delay = retryBaseDelay * (1 << (attempt - 1));
            yield RetryEvent(
              attempt: attempt + 1,
              maxAttempts: maxRetryAttempts,
              reason: errorMessage,
              delay: delay,
            );
            await Future.delayed(delay);
            continue;
          }
          giveUpReason = errorTransient
              ? '连续 $maxRetryAttempts 次请求失败: $errorMessage'
              : errorMessage;
          break;
        }

        // 空响应保护: 无正文无思考无工具调用视为异常响应，占用同一重试预算
        if (content.isEmpty && thoughts.isEmpty && toolCalls.isEmpty) {
          if (attempt < maxRetryAttempts) {
            const reason = '模型返回空响应';
            final delay = retryBaseDelay * (1 << (attempt - 1));
            yield RetryEvent(
              attempt: attempt + 1,
              maxAttempts: maxRetryAttempts,
              reason: reason,
              delay: delay,
            );
            await Future.delayed(delay);
            continue;
          }
          giveUpReason = '模型连续 $maxRetryAttempts 次返回空响应，请检查模型配置或稍后重试。';
          break;
        }

        assistantMsg = AgentMessage(
          id: assistantMsgId,
          role: AgentRole.assistant,
          content: content,
          thoughts: thoughts,
          toolCalls: toolCalls.isNotEmpty ? toolCalls : null,
          usage: usage,
          provider: providerLabel,
          model: provider?.modelId,
        );
      }

      // 重试预算耗尽: 报错终止本次对话 (半截内容不落盘)
      if (assistantMsg == null) {
        yield ErrorEvent(giveUpReason ?? '模型请求失败');
        return;
      }

      _messages.add(assistantMsg);
      recorder?.recordMessage(
        assistantMsg,
        provider: providerLabel,
        model: provider?.modelId,
      );

      // 没有工具调用，本次对话循环正常结束
      final toolCalls = assistantMsg.toolCalls ?? const <ToolCall>[];
      if (toolCalls.isEmpty) {
        yield TurnEndEvent(assistantMsg);
        return;
      }

      // 收尾轮不再提供工具 (理论不会出现调用)，直接以本轮回答结束
      if (wrapUpMode) {
        yield TurnEndEvent(assistantMsg);
        return;
      }

      // 3. 执行工具调用并加入上下文
      for (final call in toolCalls) {
        final tool = tools.get(call.name);
        ToolResult result;
        if (tool == null) {
          result = ToolResult(
            toolCallId: call.id,
            content: '错误：未知工具 "${call.name}"',
            isError: true,
          );
        } else {
          result = await tool.execute(call.id, call.arguments);
        }

        yield ToolResultEvent(result);

        // 记录工具结果消息 (含可选的图片附件，供视觉模型查看)
        final toolMsg = AgentMessage(
          id: 'tool_${DateTime.now().millisecondsSinceEpoch}_${call.id}',
          role: AgentRole.tool,
          content: result.content,
          toolCallId: call.id,
          toolName: call.name,
          isError: result.isError,
          imageBase64: result.imageBase64,
          imageMimeType: result.imageMimeType,
        );
        _messages.add(toolMsg);
        recorder?.recordMessage(toolMsg);
      }

      completedToolTurns++;

      // 工具轮数达到上限: 注入收尾提示，下一轮进入无工具强制总结模式
      if (completedToolTurns >= maxTurns) {
        final nudgeMsg = AgentMessage(
          id: 'limit_${DateTime.now().millisecondsSinceEpoch}',
          role: AgentRole.user,
          content:
              '已达到本轮对话的最大工具调用轮数上限 ($maxTurns 轮)。'
              '请立即基于已获得的信息给出最终回答，不要再调用任何工具。',
        );
        _messages.add(nudgeMsg);
        recorder?.recordMessage(nudgeMsg);
        wrapUpMode = true;
      }

      // 继续下一轮循环，让 LLM 根据工具结果生成最终回答
    }
  }

  /// 直接插入一条系统/通知消息
  void addInfoMessage(String text) {
    final msg = AgentMessage(
      id: 'info_${DateTime.now().millisecondsSinceEpoch}',
      role: AgentRole.assistant,
      content: text,
    );
    _messages.add(msg);
    recorder?.recordMessage(msg, provider: 'harness');
  }

  /// 从会话快照恢复历史消息 (启动时续接上次会话)
  void restoreMessages(List<AgentMessage> messages) {
    _messages.addAll(messages);
  }

  /// 替换当前消息列表 (切换会话时调用)
  void setMessages(List<AgentMessage> messages) {
    _messages.clear();
    _messages.addAll(messages);
  }

  /// 回退/撤销到指定 messageId (保留该消息及之前的内容，丢弃之后的所有消息)
  bool rewindToMessage(String messageId) {
    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx < 0) return false;
    final keepCount = idx + 1;
    _messages.removeRange(keepCount, _messages.length);
    recorder?.rewindToMessageCount(keepCount);
    return true;
  }

  /// 清空对话记录
  void clearMessages() {
    _messages.clear();
    recorder?.startNewSession();
  }
}
