import 'dart:async';
import 'dart:convert';
import 'presets/agent_preset.dart';
import 'providers/llm_provider.dart';
import 'session_recorder.dart';
import 'skills/skills.dart';
import 'tools/agent_tool.dart';
import 'types.dart';

/// 上下文自动压缩 (参考 pi 的 compaction 设计)：
/// - 触发：估算 Token 超过 (模型上下文窗口 - 预留) 时自动触发，逐轮检测；
/// - 切点：从最新消息向前回溯累计估算 Token，保留近期窗口 (keepRecent)，
///   更早的消息交给当前 LLM 生成结构化摘要后从请求上下文移出；
/// - 原始消息仍完整保留在 UI 消息流与会话落盘中 (仅 LLM 请求不再携带)。
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

  // ---------------- 上下文压缩配置 ----------------

  /// 是否启用上下文自动压缩 (按估算 Token 自适应触发)
  bool compactionEnabled = true;

  /// 当前模型的上下文窗口大小 (Token)，由 ViewModel 装配时按模型卡片写入
  int contextWindowTokens = 128000;

  /// 触发压缩的预留空间：估算 Token 超过 (窗口 - 预留) 时触发
  int compactionReserveTokens = 16384;

  /// 压缩时保留的近期消息 Token 预算 (从新到旧回溯)
  int compactionKeepRecentTokens = 20000;

  AgentPreset get currentPreset => _currentPreset ?? BuiltinPresets.v5Architect;
  set currentPreset(AgentPreset preset) => _currentPreset = preset;

  /// 供应商标识 (如 'deepseek')，仅用于会话记录元数据
  String? providerLabel;

  /// 会话记录器 (按 Pi 会话格式落盘，可为空)
  final SessionRecorder? recorder;

  final List<AgentMessage> _messages = [];

  /// 当前发送轮次计数：每调用一次 send 自增。
  /// 只有本轮新产生的图片会真正发给模型 (一次性展示)，
  /// 更早轮次的图片在构建请求时折叠为固定占位文本。
  int _sendEpoch = 0;

  /// 压缩摘要 (压缩后更早消息的替身，仅存在于 LLM 请求上下文中)
  String? _compactionSummary;

  /// 请求上下文的窗口起点：[_messages] 中该索引之前的消息不再发给 LLM
  int _contextStartIndex = 0;

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

  /// 是否已处于压缩状态 (上下文中存在摘要替身)
  bool get isCompacted => _compactionSummary != null;

  /// 当前压缩摘要文本 (未压缩时为 null)
  String? get compactionSummary => _compactionSummary;

  /// 图片折叠占位符 (固定文本，保证提示缓存前缀不被击穿)
  static const String _kCollapsedImagePlaceholder =
      '[图片附件已折叠: 图片数据已在当时的轮次展示过，此处不再重复发送。'
      '如需再次查看画板图片，请调用 view_canvas_image 工具]';

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

    // 新一轮发送：本轮新增的图片对模型可见，更早轮次的图片折叠为占位符
    _sendEpoch++;

    // 1. 记录用户消息
    final userMsgId = 'user_${DateTime.now().millisecondsSinceEpoch}';
    final userMsg = AgentMessage(
      id: userMsgId,
      role: AgentRole.user,
      content: userText.trim(),
      images: images ?? const [],
      imageEpoch: _sendEpoch,
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
    //   强制总结轮，保证对话永远以最终回答收尾而不是悬挂的工具结果；
    // - 每轮请求前自适应检测上下文 Token，超过窗口阈值时自动压缩。
    int completedToolTurns = 0;
    bool wrapUpMode = false;

    while (true) {
      // ---- 上下文自适应压缩 ----
      if (compactionEnabled && contextWindowTokens > 0) {
        final window = contextWindowTokens - compactionReserveTokens;
        if (_estimateContextTokens(systemPrompt) > window) {
          final evt = await compactContext();
          if (evt != null) yield evt;
        }
      }

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
          messages: _buildRequestMessages(systemPrompt),
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
          imageEpoch: _sendEpoch,
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

        // 记录工具结果消息 (含可选的图片附件，供视觉模型查看；
        // 图片只在当前轮次可见，之后的请求折叠为占位符)
        final toolMsg = AgentMessage(
          id: 'tool_${DateTime.now().millisecondsSinceEpoch}_${call.id}',
          role: AgentRole.tool,
          content: result.content,
          toolCallId: call.id,
          toolName: call.name,
          isError: result.isError,
          imageBase64: result.imageBase64,
          imageMimeType: result.imageMimeType,
          imageEpoch: _sendEpoch,
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
          imageEpoch: _sendEpoch,
        );
        _messages.add(nudgeMsg);
        recorder?.recordMessage(nudgeMsg);
        wrapUpMode = true;
      }

      // 继续下一轮循环，让 LLM 根据工具结果生成最终回答
    }
  }

  // ---------------------------------------------------------------------------
  // 请求上下文构建 (图片一次性展示 + 压缩窗口)
  // ---------------------------------------------------------------------------

  /// 构建 LLM 请求消息列表：系统提示词 + 压缩摘要替身 + 近期消息窗口。
  /// 更早轮次的图片附件折叠为固定占位文本 (控制视觉 Token 且维持缓存稳定)。
  List<AgentMessage> _buildRequestMessages(String systemPrompt) {
    final result = <AgentMessage>[
      AgentMessage(
        id: 'system_prompt',
        role: AgentRole.system,
        content: systemPrompt,
      ),
    ];

    final summary = _compactionSummary;
    if (summary != null) {
      result.add(
        AgentMessage(
          id: 'compaction_summary',
          role: AgentRole.user,
          content:
              '以下是本次对话更早内容的压缩摘要 (原始消息已从上下文省略，'
              '用户界面仍保留完整历史)。请基于摘要继续当前任务：\n\n$summary',
        ),
      );
    }

    for (var i = _contextStartIndex; i < _messages.length; i++) {
      final m = _messages[i];
      // 本轮新产生的图片原样发送；更早轮次的图片折叠为占位符
      if (m.imageEpoch == _sendEpoch || !m.hasVisionImages) {
        result.add(m);
      } else {
        result.add(m.withVisionImagesCollapsed(_kCollapsedImagePlaceholder));
      }
    }
    return result;
  }

  // ---------------------------------------------------------------------------
  // 上下文压缩 (参考 pi compaction)
  // ---------------------------------------------------------------------------

  /// 单条消息的粗略 Token 估算 (chars/4 启发式，图片按固定视觉开销计)
  static const int _estimatedImageTokens = 1200;

  int _estimateMessageTokens(AgentMessage m) {
    var chars = m.content.length + m.thoughts.length;
    if (m.hasVisionImages) {
      chars += _estimatedImageTokens * 4 * m.images.length;
      if (m.role == AgentRole.tool) chars += _estimatedImageTokens * 4;
    }
    for (final tc in m.toolCalls ?? const <ToolCall>[]) {
      chars += tc.name.length + jsonEncode(tc.arguments).length;
    }
    return (chars / 4).ceil();
  }

  /// 估算当前请求上下文的 Token 总量。
  /// 优先用窗口内最后一条带用量的 assistant 消息的 totalTokens (含全部输入)，
  /// 之后的消息按 chars/4 估算累加；无任何用量时退化为全量估算。
  int _estimateContextTokens([String? systemPrompt]) {
    final hasSystem = systemPrompt != null;
    var total = hasSystem ? (systemPrompt.length ~/ 4 + 2048) : 0;

    final summary = _compactionSummary;
    if (summary != null) {
      total += summary.length ~/ 4 + 64;
    }

    int usageTokens = 0;
    int trailing = 0;
    bool haveUsage = false;
    for (var i = _messages.length - 1; i >= _contextStartIndex; i--) {
      final m = _messages[i];
      if (!haveUsage &&
          m.role == AgentRole.assistant &&
          (m.usage?.total ?? 0) > 0) {
        // totalTokens = input+output+cache，近似等于当时的完整上下文规模
        usageTokens = m.usage!.total;
        haveUsage = true;
        break;
      }
      trailing += _estimateMessageTokens(m);
    }
    return total + trailing + usageTokens;
  }

  /// 有效的压缩切点：user / assistant 消息 (绝不在 tool 结果上切，
  /// 否则会把工具结果与其调用拆散导致协议错误)
  bool _isValidCutPoint(AgentMessage m) =>
      m.role == AgentRole.user || m.role == AgentRole.assistant;

  /// 计算压缩切点 (保留窗口起点)。
  /// 正常模式：从新到旧累计估算 Token 达到 keepRecent 预算后，取其后最近的
  /// 有效切点；整体不足预算时返回 -1 (无需压缩)。
  /// 强制模式 (/compact)：保留最后一个 user 轮次，压缩其之前的全部内容。
  int _findCutIndex({required bool force}) {
    final start = _contextStartIndex;
    final end = _messages.length;
    if (end <= start) return -1;

    if (force) {
      // 保留最后一轮 user 消息开始的近期对话
      for (var i = end - 1; i >= start; i--) {
        if (_messages[i].role == AgentRole.user && i > start) return i;
      }
      return -1;
    }

    final cutPoints = <int>[
      for (var i = start; i < end; i++)
        if (_isValidCutPoint(_messages[i])) i,
    ];
    if (cutPoints.isEmpty) return -1;

    var acc = 0;
    for (var i = end - 1; i >= start; i--) {
      acc += _estimateMessageTokens(_messages[i]);
      if (acc >= compactionKeepRecentTokens) {
        // 预算在此处耗尽：从该消息往前找最近的有效切点
        for (final c in cutPoints) {
          if (c >= i) return c;
        }
        // 保留窗口内没有切点可落在预算内 → 放弃本次压缩
        return -1;
      }
    }
    // 整个窗口不足保留预算，无需压缩
    return -1;
  }

  /// 压缩摘要序列化上限 (字符)。过长的历史截取尾部，防止摘要请求本身超窗。
  static const int _maxSerializedChars = 300000;

  /// 把待压缩消息序列化为纯文本对话稿 (模型据此生成摘要，不会再续写对话)
  String _serializeForSummary(List<AgentMessage> msgs) {
    final buffer = StringBuffer();
    for (final m in msgs) {
      switch (m.role) {
        case AgentRole.user:
          buffer.writeln('[用户]: ${m.content}');
          if (m.hasVisionImages) {
            buffer.writeln('  (本条消息带有 ${m.images.length} 张图片附件，图片内容略)');
          }
        case AgentRole.assistant:
          if (m.content.isNotEmpty || m.toolCalls != null) {
            buffer.writeln('[助手]: ${m.content}');
            for (final tc in m.toolCalls ?? const <ToolCall>[]) {
              buffer.writeln(
                '  [助手调用了工具 ${tc.name}: ${jsonEncode(tc.arguments)}]',
              );
            }
          }
        case AgentRole.tool:
          buffer.writeln('[工具结果 ${m.toolName ?? ''}]: ${m.content}');
        case AgentRole.system:
          break;
      }
    }
    var text = buffer.toString();
    if (text.length > _maxSerializedChars) {
      text =
          '…… (更早内容已截断)\n'
          '${text.substring(text.length - _maxSerializedChars)}';
    }
    return text;
  }

  static const String _summarizationSystemPrompt =
      '你是对话压缩助手。请把用户提供的对话历史压缩为结构化摘要，'
      '供另一个 AI 助手在不丢失关键信息的前提下无缝接续工作。只输出摘要本身。';

  static const String _summarizationPrompt =
      '请把 <conversation> 中的对话历史压缩为一份上下文检查点摘要，'
      '另一个 AI 助手将只依据它继续工作。严格按以下格式输出：\n'
      '## 目标\n[用户想完成什么]\n'
      '## 约束与偏好\n[用户提过的要求与偏好，无则写 (无)]\n'
      '## 进展\n### 已完成\n- ...\n### 进行中\n- ...\n### 受阻\n- ...\n'
      '## 关键决定\n- **[决定]**: [原因]\n'
      '## 下一步\n1. ...\n'
      '## 关键上下文\n[接续工作必需的具体信息]\n\n'
      '要求：每节保持精炼；完整保留提示词文本、生图参数、图片索引、批注坐标、'
      '报错原文等关键细节；不要遗漏未完成的请求。';

  /// 调用当前 LLM 生成 (或迭代更新) 压缩摘要。
  /// 失败或空摘要返回 null，此时放弃压缩 (绝不破坏现有上下文)。
  Future<String?> _generateSummary(
    List<AgentMessage> toSummarize, {
    String? previousSummary,
  }) async {
    final p = provider;
    if (p == null) return null;

    final conversationText = _serializeForSummary(toSummarize);
    final buffer = StringBuffer();
    buffer.write('<conversation>\n$conversationText</conversation>\n\n');
    if (previousSummary != null) {
      buffer.write(
        '<previous-summary>\n$previousSummary\n</previous-summary>\n\n',
      );
      buffer.write(
        '请在保留既有摘要全部信息的基础上，把新对话内容合并进去并更新摘要，'
        '仍严格按上述格式输出。\n\n',
      );
    }
    buffer.write(_summarizationPrompt);

    final requestMessages = <AgentMessage>[
      AgentMessage(
        id: 'summarization_system',
        role: AgentRole.system,
        content: _summarizationSystemPrompt,
      ),
      AgentMessage(
        id: 'summarization_request',
        role: AgentRole.user,
        content: buffer.toString(),
      ),
    ];

    String summary = '';
    await for (final event in p.streamChat(
      messages: requestMessages,
      tools: const <AgentTool>[],
      temperature: 0.3,
    )) {
      if (event is ContentDeltaEvent) {
        summary += event.delta;
      } else if (event is ErrorEvent) {
        return null;
      }
    }
    final trimmed = summary.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// 执行上下文压缩：把保留窗口之前的消息替换为 LLM 生成的结构化摘要。
  ///
  /// [force] 为 true 时跳过启用开关与 Token 预算判断 (斜杠命令手动触发)，
  /// 保留最后一个 user 轮次开始的近期对话。
  /// 原始消息仍保留在 [messages] 与会话落盘中，仅从 LLM 请求上下文移出。
  /// 无可压缩内容或摘要生成失败时返回 null。
  Future<CompactionEvent?> compactContext({bool force = false}) async {
    if (!force && !compactionEnabled) return null;
    if (provider == null) return null;

    final cut = _findCutIndex(force: force);
    if (cut <= _contextStartIndex) return null;

    final start = _contextStartIndex;
    final toSummarize = _messages.sublist(start, cut);
    if (toSummarize.isEmpty) return null;

    final tokensBefore = _estimateContextTokens();
    final summaryText = await _generateSummary(
      toSummarize,
      previousSummary: _compactionSummary,
    );
    if (summaryText == null) return null;

    _compactionSummary = summaryText;
    _contextStartIndex = cut;

    return CompactionEvent(
      summary: summaryText,
      tokensBefore: tokensBefore,
      tokensAfter: _estimateContextTokens(),
    );
  }

  // ---------------------------------------------------------------------------
  // 消息管理
  // ---------------------------------------------------------------------------

  /// 直接插入一条系统/通知消息
  void addInfoMessage(String text) {
    final msg = AgentMessage(
      id: 'info_${DateTime.now().millisecondsSinceEpoch}',
      role: AgentRole.assistant,
      content: text,
      imageEpoch: _sendEpoch,
    );
    _messages.add(msg);
    recorder?.recordMessage(msg, provider: 'harness');
  }

  /// 从会话快照恢复历史消息 (启动时续接上次会话)。
  /// 恢复的消息图片轮次为 0，不会重新发给模型 (避免重启后旧图灌满上下文)。
  void restoreMessages(List<AgentMessage> messages) {
    _messages.addAll(messages);
    _resetCompaction();
  }

  /// 替换当前消息列表 (切换会话时调用)
  void setMessages(List<AgentMessage> messages) {
    _messages.clear();
    _messages.addAll(messages);
    _resetCompaction();
  }

  /// 回退/撤销到指定 messageId (保留该消息及之前的内容，丢弃之后的所有消息)
  bool rewindToMessage(String messageId) {
    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx < 0) return false;
    final keepCount = idx + 1;
    _messages.removeRange(keepCount, _messages.length);
    recorder?.rewindToMessageCount(keepCount);
    // 回溯点落在压缩窗口之外时，压缩状态已无意义，重置为完整上下文
    if (keepCount <= _contextStartIndex) {
      _resetCompaction();
    }
    return true;
  }

  /// 清空对话记录
  void clearMessages() {
    _messages.clear();
    _resetCompaction();
    recorder?.startNewSession();
  }

  void _resetCompaction() {
    _compactionSummary = null;
    _contextStartIndex = 0;
  }
}
