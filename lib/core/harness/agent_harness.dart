import 'dart:async';
import 'providers/llm_provider.dart';
import 'skills/skills.dart';
import 'tools/agent_tool.dart';
import 'types.dart';

/// 核心 Agent Harness 控制器 (借鉴 Pi 的极简响应式设计)
class AgentHarness {
  final ToolRegistry tools;
  LlmProvider? provider;
  Skill currentSkill;
  final List<AgentMessage> _messages = [];

  AgentHarness({
    required this.tools,
    this.provider,
    Skill? initialSkill,
  }) : currentSkill = initialSkill ?? BuiltinSkills.v5PromptArchitect;

  List<AgentMessage> get messages => List.unmodifiable(_messages);

  /// 切换当前激活的技能
  void setSkill(Skill skill) {
    currentSkill = skill;
  }

  /// 发送用户消息并启动 Agent 循环流
  Stream<HarnessEvent> send(String userText, {double temperature = 0.7}) async* {
    if (userText.trim().isEmpty) return;

    // 1. 记录用户消息
    final userMsgId = 'user_${DateTime.now().millisecondsSinceEpoch}';
    final userMsg = AgentMessage(
      id: userMsgId,
      role: AgentRole.user,
      content: userText.trim(),
    );
    _messages.add(userMsg);

    if (provider == null) {
      yield ErrorEvent('未配置 LLM 提供商，请在设置中配置 API Key。');
      return;
    }

    // 2. 启动执行循环 (最大支持 5 轮工具链式调用)
    int depth = 0;
    const maxDepth = 5;

    while (depth < maxDepth) {
      depth++;

      // 准备完整上下文（注入当前技能的 System Prompt）
      final contextMessages = <AgentMessage>[
        AgentMessage(
          id: 'system_prompt',
          role: AgentRole.system,
          content: currentSkill.systemPrompt,
        ),
        ..._messages,
      ];

      final assistantMsgId = 'asst_${DateTime.now().millisecondsSinceEpoch}';
      yield TurnStartEvent(assistantMsgId);

      String content = '';
      String thoughts = '';
      final List<ToolCall> toolCalls = [];

      final stream = provider!.streamChat(
        messages: contextMessages,
        tools: tools.getAll(),
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
      );
      _messages.add(assistantMsg);

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
        );
        _messages.add(toolMsg);
      }

      // 继续下一轮循环，让 LLM 根据工具结果生成最终回答
    }
  }

  /// 直接插入一条系统/通知消息
  void addInfoMessage(String text) {
    _messages.add(
      AgentMessage(
        id: 'info_${DateTime.now().millisecondsSinceEpoch}',
        role: AgentRole.assistant,
        content: text,
      ),
    );
  }

  /// 清空对话记录
  void clearMessages() {
    _messages.clear();
  }
}
