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

  AgentPreset get currentPreset => _currentPreset ?? BuiltinPresets.v5Architect;
  set currentPreset(AgentPreset preset) => _currentPreset = preset;

  /// 兼容老属性：获取当前关联的首个主要 Skill
  Skill get currentSkill {
    if (currentPreset.enabledSkillIds.isNotEmpty) {
      final s = BuiltinSkills.findById(currentPreset.enabledSkillIds.first);
      if (s != null) return s;
    }
    return BuiltinSkills.v5PromptArchitect;
  }

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
    Skill? initialSkill,
  }) : _currentPreset = initialPreset ??
            (initialSkill != null
                ? AgentPreset(
                    id: 'skill_compat_${initialSkill.id}',
                    name: initialSkill.name,
                    description: initialSkill.description,
                    systemPrompt: initialSkill.systemPrompt,
                    enabledSkillIds: [initialSkill.id],
                    enabledToolNames: PresetToolKeys.all,
                    allowedModifiableParams: PresetParamKeys.all,
                  )
                : BuiltinPresets.v5Architect);

  List<AgentMessage> get messages => List.unmodifiable(_messages);

  /// 切换当前激活的预设
  void setPreset(AgentPreset preset) {
    currentPreset = preset;
  }

  /// 兼容老接口：切换当前激活的技能
  void setSkill(Skill skill) {
    currentPreset = AgentPreset(
      id: 'skill_compat_${skill.id}',
      name: skill.name,
      description: skill.description,
      systemPrompt: skill.systemPrompt,
      enabledSkillIds: [skill.id],
      enabledToolNames: PresetToolKeys.all,
      allowedModifiableParams: PresetParamKeys.all,
    );
  }

  /// 发送用户消息并启动 Agent 循环流
  Stream<HarnessEvent> send(
    String userText, {
    double temperature = 0.7,
  }) async* {
    if (userText.trim().isEmpty) return;

    // 1. 记录用户消息
    final userMsgId = 'user_${DateTime.now().millisecondsSinceEpoch}';
    final userMsg = AgentMessage(
      id: userMsgId,
      role: AgentRole.user,
      content: userText.trim(),
    );
    _messages.add(userMsg);
    recorder?.recordMessage(userMsg);

    if (provider == null) {
      yield ErrorEvent('未配置 LLM 提供商，请在设置中配置 API Key。');
      return;
    }

    // 2. 启动执行循环 (最大支持 5 轮工具链式调用)
    int depth = 0;
    const maxDepth = 5;

    while (depth < maxDepth) {
      depth++;

      // 准备完整上下文（注入当前预设的 System Prompt 与 Pi 标准 Skill 声明）
      final promptBuffer = StringBuffer(currentPreset.systemPrompt.trim());
      final enabledSkills = currentPreset.enabledSkillIds
          .map((id) => BuiltinSkills.findById(id))
          .whereType<Skill>()
          .toList();
      if (enabledSkills.isNotEmpty) {
        final skillsXml = Skill.formatSkillsForSystemPrompt(enabledSkills);
        if (skillsXml.isNotEmpty) {
          promptBuffer.writeln('\n\n$skillsXml');
        }
      }

      final contextMessages = <AgentMessage>[
        AgentMessage(
          id: 'system_prompt',
          role: AgentRole.system,
          content: promptBuffer.toString(),
        ),
        ..._messages,
      ];

      final assistantMsgId = 'asst_${DateTime.now().millisecondsSinceEpoch}';
      yield TurnStartEvent(assistantMsgId);

      String content = '';
      String thoughts = '';
      TokenUsage? usage;
      final List<ToolCall> toolCalls = [];

      // 按当前预设配置过滤开放给 LLM 的工具列表
      final activeTools = tools
          .getAll()
          .where((tool) => currentPreset.isToolEnabled(tool.name))
          .toList();

      final stream = provider!.streamChat(
        messages: contextMessages,
        tools: activeTools,
        temperature: temperature,
      );

      bool hasError = false;

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
          hasError = true;
          yield event;
        }
      }

      if (hasError) break;

      // 保存本次 Assistant 消息
      final assistantMsg = AgentMessage(
        id: assistantMsgId,
        role: AgentRole.assistant,
        content: content,
        thoughts: thoughts,
        toolCalls: toolCalls.isNotEmpty ? toolCalls : null,
        usage: usage,
        provider: providerLabel,
        model: provider?.modelId,
      );
      _messages.add(assistantMsg);
      recorder?.recordMessage(
        assistantMsg,
        provider: providerLabel,
        model: provider?.modelId,
      );

      // 如果没有工具调用，本次对话循环正常结束
      if (toolCalls.isEmpty) {
        yield TurnEndEvent(assistantMsg);
        break;
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

        // 记录工具结果消息
        final toolMsg = AgentMessage(
          id: 'tool_${DateTime.now().millisecondsSinceEpoch}_${call.id}',
          role: AgentRole.tool,
          content: result.content,
          toolCallId: call.id,
          toolName: call.name,
          isError: result.isError,
        );
        _messages.add(toolMsg);
        recorder?.recordMessage(toolMsg);
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

