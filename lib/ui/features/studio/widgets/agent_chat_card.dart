import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../../../core/harness/types.dart';
import '../../../../data/models/novelai_models.dart';
import '../../../../data/services/usage_ledger_service.dart';
import '../../../core/theme/app_theme.dart';
import '../view_models/studio_view_model.dart';
import 'agent_rewind_view.dart';
import 'agent_session_list_view.dart';
import 'inline_agent_question_card.dart';

enum _AgentCardView {
  chat,
  sessions,
  rewind,
}

class AgentChatCard extends StatefulWidget {
  final StudioViewModel viewModel;

  const AgentChatCard({super.key, required this.viewModel});

  @override
  State<AgentChatCard> createState() => _AgentChatCardState();
}

class _AgentChatCardState extends State<AgentChatCard> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _cardFocusNode = FocusNode();
  _AgentCardView _currentView = _AgentCardView.chat;
  DateTime? _lastEscPressTime;

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _cardFocusNode.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(AgentChatCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.viewModel.activeQuestionPrompt != null &&
        oldWidget.viewModel.activeQuestionPrompt !=
            widget.viewModel.activeQuestionPrompt) {
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _handleSend() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    _inputController.clear();
    widget.viewModel.sendChatMessage(text);
    _scrollToBottom();
  }

  void _handleEscKey() {
    final now = DateTime.now();
    if (_lastEscPressTime != null &&
        now.difference(_lastEscPressTime!) <=
            const Duration(milliseconds: 400)) {
      _lastEscPressTime = null;
      if (widget.viewModel.isChatStreaming) {
        widget.viewModel.abortChat();
      }
      // 连续按两次 ESC：全屏覆盖切换至历史时刻回溯视图
      setState(() {
        _currentView = _AgentCardView.rewind;
      });
      return;
    }

    _lastEscPressTime = now;
    if (widget.viewModel.isChatStreaming) {
      widget.viewModel.abortChat();
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_currentView) {
      case _AgentCardView.sessions:
        return AgentSessionListView(
          viewModel: widget.viewModel,
          onBack: () => setState(() => _currentView = _AgentCardView.chat),
        );
      case _AgentCardView.rewind:
        return AgentRewindView(
          viewModel: widget.viewModel,
          onBack: () => setState(() => _currentView = _AgentCardView.chat),
        );
      case _AgentCardView.chat:
        break;
    }

    final messages = widget.viewModel.messages;
    final isStreaming = widget.viewModel.isChatStreaming;
    final activePrompt = widget.viewModel.activeQuestionPrompt;
    final currentPreset = widget.viewModel.currentPreset;
    final presets = widget.viewModel.presets;
    final activeProvider = widget.viewModel.config.activeLlmProvider;
    final activeModel = activeProvider.activeModel;
    final currentEffort = widget.viewModel.currentThinkingEffort;

    return Focus(
      focusNode: _cardFocusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _handleEscKey();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Card(
        margin: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 顶部预设选择栏与会话管理按钮
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppTheme.border)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // 1. 预设切换
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.psychology_outlined,
                        size: 15,
                        color: AppTheme.notionBlue,
                      ),
                      const SizedBox(width: 4),
                      DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: presets.any((p) => p.id == currentPreset.id)
                              ? currentPreset.id
                              : (presets.isNotEmpty ? presets.first.id : null),
                          dropdownColor: AppTheme.pureWhite,
                          items: presets.map((preset) {
                            return DropdownMenuItem<String>(
                              value: preset.id,
                              child: Tooltip(
                                message: preset.description,
                                child: Text(
                                  preset.name,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                          onChanged: (presetId) {
                            if (presetId != null) {
                              final p =
                                  presets.firstWhere((e) => e.id == presetId);
                              widget.viewModel.selectPreset(p);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.forum_outlined,
                      size: 16,
                      color: AppTheme.textMuted,
                    ),
                    tooltip: '会话管理',
                    onPressed: () {
                      setState(() {
                        _currentView = _AgentCardView.sessions;
                      });
                      widget.viewModel.refreshSessions();
                    },
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),

          // 对话消息流展示区域
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: messages.length +
                  (isStreaming ? 1 : 0) +
                  (activePrompt != null ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == messages.length && isStreaming) {
                  return _buildStreamingBubble();
                }
                if (activePrompt != null &&
                    index == messages.length + (isStreaming ? 1 : 0)) {
                  return InlineAgentQuestionCard(prompt: activePrompt);
                }

                final msg = messages[index];
                return _buildMessageItem(msg);
              },
            ),
          ),

          // 底部控制与消息输入区 (单一底栏，高度与左侧生成坞对齐)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: const BoxDecoration(
              color: AppTheme.pureWhite,
              border: Border(top: BorderSide(color: AppTheme.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. 模型切换与思考强度控制栏 (扩大版一体化胶囊卡片，自适应防溢出)
                _buildCombinedModelThinkingCard(
                  activeProvider,
                  activeModel,
                  currentEffort,
                ),
                const SizedBox(height: 12),

                // 2. 消息输入框与发送按钮 (通过 IntrinsicHeight + stretch 达到高度像素级 100% 对齐)
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: CallbackShortcuts(
                          bindings: {
                            const SingleActivator(LogicalKeyboardKey.enter):
                                _handleSend,
                          },
                          child: TextField(
                            controller: _inputController,
                            minLines: 1,
                            maxLines: 4,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: AppTheme.textPrimary,
                            ),
                            decoration: InputDecoration(
                              hintText: '输入绘画构思，或输入 /nai <词> 快速生图...',
                              fillColor: AppTheme.paperWarmth,
                              filled: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  AppTheme.radiusButton,
                                ),
                                borderSide:
                                    const BorderSide(color: AppTheme.border),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  AppTheme.radiusButton,
                                ),
                                borderSide:
                                    const BorderSide(color: AppTheme.border),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  AppTheme.radiusButton,
                                ),
                                borderSide: const BorderSide(
                                  color: AppTheme.notionBlue,
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      AspectRatio(
                        aspectRatio: 1.0,
                        child: Material(
                          color: isStreaming
                              ? AppTheme.stone.withValues(alpha: 0.5)
                              : AppTheme.notionBlue,
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusButton,
                          ),
                          child: InkWell(
                            onTap: isStreaming ? null : _handleSend,
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusButton,
                            ),
                            child: Center(
                              child: isStreaming
                                  ? const SizedBox(
                                      width: 15,
                                      height: 15,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                          Colors.white,
                                        ),
                                      ),
                                    )
                                  : const Icon(
                                      Icons.send_rounded,
                                      size: 17,
                                      color: Colors.white,
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

  /// 一体化模型与思考强度控制卡片 (单卡片容器 + 自适应弹性宽度 + 防溢出截断)
  Widget _buildCombinedModelThinkingCard(
    LlmProviderConfig activeProvider,
    LlmModelConfig activeModel,
    ThinkingEffort currentEffort,
  ) {
    final models = activeProvider.models;
    final currentModelId = models.any((m) => m.id == activeModel.id)
        ? activeModel.id
        : (models.isNotEmpty ? models.first.id : null);

    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppTheme.pureWhite,
        borderRadius: BorderRadius.circular(AppTheme.radiusButton),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          // 1. 模型选择区 (使用 Expanded 弹性自适应，长文本自动省略，绝不挤压溢出)
          // 悬停时显示当前会话各模型的 Token 用量
          Expanded(
            child: Tooltip(
              message: _buildSessionUsageTooltip(),
              waitDuration: const Duration(milliseconds: 400),
              textStyle: const TextStyle(
                fontSize: 11,
                color: AppTheme.textPrimary,
                height: 1.5,
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: currentModelId,
                  isDense: true,
                  isExpanded: true,
                  dropdownColor: AppTheme.pureWhite,
                  icon: const Icon(
                    Icons.arrow_drop_down_rounded,
                    size: 18,
                    color: AppTheme.textSecondary,
                  ),
                  selectedItemBuilder: (context) {
                    return models.map((m) {
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.smart_toy_outlined,
                            size: 14.5,
                            color: AppTheme.stone,
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              m.name,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ),
                          if (m.isMultimodal) ...[
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.visibility_outlined,
                              size: 12.5,
                              color: AppTheme.success,
                            ),
                          ],
                          if (m.supportsThinking) ...[
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.psychology_outlined,
                              size: 12.5,
                              color: AppTheme.notionBlue,
                            ),
                          ],
                        ],
                      );
                    }).toList();
                  },
                  menuMaxHeight: 400.0,
                  borderRadius: BorderRadius.circular(8),
                  items: models.map((m) {
                    return DropdownMenuItem(
                      value: m.id,
                      child: Tooltip(
                        message: m.name,
                        waitDuration: const Duration(milliseconds: 500),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.smart_toy_outlined,
                              size: 14.5,
                              color: AppTheme.stone,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                m.name,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ),
                            if (m.isMultimodal) ...[
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.visibility_outlined,
                                size: 12.5,
                                color: AppTheme.success,
                              ),
                            ],
                            if (m.supportsThinking) ...[
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.psychology_outlined,
                                size: 12.5,
                                color: AppTheme.notionBlue,
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: (modelId) {
                    if (modelId != null) {
                      widget.viewModel.switchActiveModel(modelId);
                    }
                  },
                ),
              ),
            ),
          ),

          // 2. 思考强度控制区 (同在一个卡片内，以垂直细线分隔)
          if (activeModel.supportsThinking) ...[
            Container(
              width: 1,
              height: 18,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              color: AppTheme.border,
            ),
            _buildInlineThinkingButtons(activeModel, currentEffort),
          ],
        ],
      ),
    );
  }

  /// 一体化卡片内部的思考强度切换按钮组
  Widget _buildInlineThinkingButtons(
    LlmModelConfig model,
    ThinkingEffort currentEffort,
  ) {
    final availableLevels = model.supportedThinkingLevels.isNotEmpty
        ? [ThinkingEffort.off, ...model.supportedThinkingLevels]
        : [
            ThinkingEffort.off,
            ThinkingEffort.low,
            ThinkingEffort.medium,
            ThinkingEffort.high,
          ];

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.psychology_outlined,
          size: 13.5,
          color: AppTheme.notionBlue,
        ),
        const SizedBox(width: 4),
        const Text(
          '思考:',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(width: 3),
        ...availableLevels.map((effort) {
          final isSelected = currentEffort == effort;
          return InkWell(
            onTap: () => widget.viewModel.setThinkingEffort(effort),
            borderRadius: BorderRadius.circular(AppTheme.radiusPill),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              padding: const EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 3,
              ),
              decoration: BoxDecoration(
                color: isSelected ? AppTheme.notionBlue : Colors.transparent,
                borderRadius: BorderRadius.circular(AppTheme.radiusPill),
              ),
              child: Text(
                effort == ThinkingEffort.off
                    ? '关'
                    : effort == ThinkingEffort.low
                    ? '低'
                    : effort == ThinkingEffort.medium
                    ? '中'
                    : '高',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? Colors.white : AppTheme.textSecondary,
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Pi 风格消息渲染: chat / thinking / toolCall / toolResult 平铺块
  // ---------------------------------------------------------------------------

  Widget _buildMessageItem(AgentMessage msg) {
    switch (msg.role) {
      case AgentRole.system:
        return const SizedBox.shrink();
      case AgentRole.user:
        return _buildUserRow(msg);
      case AgentRole.tool:
        return _buildToolResultBlock(msg);
      case AgentRole.assistant:
        return _buildAssistantItem(msg);
    }
  }

  /// 用户消息: 平铺无气泡，› 前缀 + 纯文本 (与 Pi TUI 一致)
  Widget _buildUserRow(AgentMessage msg) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(
              Icons.keyboard_arrow_right,
              size: 16,
              color: AppTheme.notionBlue,
            ),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: SelectableText(
              msg.content,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: AppTheme.textPrimary,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 助手消息: 思考块 (可折叠) + Markdown 正文 + 工具调用块 (可折叠)
  Widget _buildAssistantItem(AgentMessage msg) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (msg.thoughts.isNotEmpty) _ThinkingBlock(thoughts: msg.thoughts),
          if (msg.content.isNotEmpty) ...[
            if (msg.thoughts.isNotEmpty) const SizedBox(height: 4),
            MarkdownBody(
              data: msg.content,
              selectable: true,
              softLineBreak: true,
              styleSheet: _buildMarkdownStyleSheet(context),
            ),
          ],
          if (msg.toolCalls != null)
            for (final call in msg.toolCalls!) _buildToolCallBlock(call),
        ],
      ),
    );
  }

  /// 工具调用块: 名称 + 参数摘要，展开后显示完整参数 JSON
  Widget _buildToolCallBlock(ToolCall call) {
    return _CollapsibleTile(
      margin: const EdgeInsets.only(top: 4, bottom: 4),
      header: Row(
        children: [
          const Icon(
            Icons.build_circle_outlined,
            size: 13,
            color: AppTheme.notionBlue,
          ),
          const SizedBox(width: 4),
          Text(
            call.name,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
              color: AppTheme.notionBlue,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _summarizeArguments(call.arguments),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10.5,
                fontFamily: 'monospace',
                color: AppTheme.textMuted,
              ),
            ),
          ),
        ],
      ),
      body: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppTheme.paperWarmth,
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        ),
        child: SelectableText(
          const JsonEncoder.withIndent('  ').convert(call.arguments),
          style: const TextStyle(
            fontSize: 11,
            fontFamily: 'monospace',
            color: AppTheme.textSecondary,
            height: 1.4,
          ),
        ),
      ),
    );
  }

  /// 工具结果块: 状态图标 + 工具名 + 行数摘要，展开后显示完整输出
  Widget _buildToolResultBlock(AgentMessage msg) {
    final lineCount = msg.content.isEmpty ? 0 : msg.content.split('\n').length;
    final firstLine = msg.content.isEmpty
        ? '(无输出)'
        : msg.content.split('\n').first.trim();
    final accent = msg.isError ? AppTheme.error : AppTheme.success;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.only(left: 8),
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: AppTheme.border, width: 2)),
      ),
      child: _CollapsibleTile(
        margin: EdgeInsets.zero,
        header: Row(
          children: [
            Icon(
              msg.isError ? Icons.error_outline : Icons.check_circle_outline,
              size: 13,
              color: accent,
            ),
            const SizedBox(width: 4),
            Text(
              msg.toolName ?? 'tool',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
                color: accent,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '$lineCount 行 · $firstLine',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontFamily: 'monospace',
                  color: AppTheme.textMuted,
                ),
              ),
            ),
          ],
        ),
        body: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 260),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.paperWarmth,
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          ),
          child: SingleChildScrollView(
            child: SelectableText(
              msg.content,
              style: const TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: AppTheme.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 流式输出占位: 实时思考块 + 正文 Markdown
  Widget _buildStreamingBubble() {
    final thoughts = widget.viewModel.currentStreamingThoughts;
    final content = widget.viewModel.currentStreamingContent;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (thoughts.isNotEmpty) ...[
            const Row(
              children: [
                SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: AppTheme.textMuted,
                  ),
                ),
                SizedBox(width: 6),
                Text(
                  '正在思考...',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    fontStyle: FontStyle.italic,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.pureWhite,
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                border: Border.all(color: AppTheme.border),
              ),
              child: Text(
                thoughts,
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontStyle: FontStyle.italic,
                  color: AppTheme.textMuted,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 6),
          ],
          MarkdownBody(
            data: content.isEmpty ? '构思中...' : content,
            selectable: true,
            softLineBreak: true,
            styleSheet: _buildMarkdownStyleSheet(context),
          ),
        ],
      ),
    );
  }

  /// 悬停模型选择器时展示的当前会话用量摘要
  String _buildSessionUsageTooltip() {
    final usage = widget.viewModel.sessionModelUsage;
    if (usage.isEmpty) return '当前会话暂无 Token 用量记录';

    final entries = usage.entries.toList()
      ..sort((a, b) => b.value.total.compareTo(a.value.total));
    final buffer = StringBuffer('当前会话 Token 用量');
    for (final entry in entries) {
      final u = entry.value;
      final detail =
          '输入 ${_fmt(u.input)} · 输出 ${_fmt(u.output)} · 总计 ${_fmt(u.total)}';
      buffer.write('\n${entry.key}\n$detail');
    }
    return buffer.toString();
  }

  String _fmt(int value) => UsageLedgerService.formatTokens(value);

  /// 将工具参数压缩为单行摘要: key=value key2="..."
  String _summarizeArguments(Map<String, dynamic> arguments) {
    if (arguments.isEmpty) return '{}';
    return arguments.entries
        .map((e) {
          final value = jsonEncode(e.value);
          final short = value.length > 60
              ? '${value.substring(0, 60)}…'
              : value;
          return '${e.key}=$short';
        })
        .join(' ');
  }

  /// 构建统一的 Markdown 渲染样式表
  MarkdownStyleSheet _buildMarkdownStyleSheet(BuildContext context) {
    const baseColor = AppTheme.textPrimary;
    return MarkdownStyleSheet(
      p: const TextStyle(fontSize: 12, color: baseColor, height: 1.45),
      h1: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: baseColor,
        height: 1.4,
      ),
      h2: const TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w700,
        color: baseColor,
        height: 1.4,
      ),
      h3: const TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: baseColor,
        height: 1.4,
      ),
      h4: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: baseColor,
        height: 1.4,
      ),
      h5: const TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        color: baseColor,
        height: 1.4,
      ),
      h6: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: baseColor,
        height: 1.4,
      ),
      em: const TextStyle(fontStyle: FontStyle.italic),
      strong: const TextStyle(fontWeight: FontWeight.w700),
      del: const TextStyle(decoration: TextDecoration.lineThrough),
      code: const TextStyle(
        fontSize: 11,
        fontFamily: 'monospace',
        backgroundColor: Colors.transparent,
        color: AppTheme.notionBlue,
      ),
      codeblockDecoration: BoxDecoration(
        color: AppTheme.pureWhite,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: AppTheme.border),
      ),
      codeblockPadding: const EdgeInsets.all(8),
      blockquote: const TextStyle(
        fontSize: 11.5,
        color: AppTheme.textSecondary,
        height: 1.4,
      ),
      blockquoteDecoration: BoxDecoration(
        color: AppTheme.pureWhite,
        border: const Border(
          left: BorderSide(color: AppTheme.notionBlue, width: 3),
        ),
        borderRadius: BorderRadius.circular(2),
      ),
      blockquotePadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      listBullet: const TextStyle(fontSize: 12, color: baseColor),
      tableBody: const TextStyle(fontSize: 11.5, color: baseColor),
      tableHead: const TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        color: baseColor,
      ),
      tableBorder: TableBorder.all(color: AppTheme.border, width: 1),
      tableCellsPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      listIndent: 16,
      pPadding: const EdgeInsets.only(bottom: 4),
      h1Padding: const EdgeInsets.only(top: 6, bottom: 4),
      h2Padding: const EdgeInsets.only(top: 6, bottom: 4),
      h3Padding: const EdgeInsets.only(top: 4, bottom: 2),
    );
  }
}

/// 通用折叠块: 头部行 + 可展开主体 (Pi 风格，默认折叠)
class _CollapsibleTile extends StatefulWidget {
  final Widget header;
  final Widget? body;
  final bool initiallyExpanded;
  final EdgeInsetsGeometry margin;

  const _CollapsibleTile({
    required this.header,
    this.body,
    this.margin = const EdgeInsets.only(bottom: 4),
  }) : initiallyExpanded = false;

  @override
  State<_CollapsibleTile> createState() => _CollapsibleTileState();
}

class _CollapsibleTileState extends State<_CollapsibleTile> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final hasBody = widget.body != null;
    return Container(
      margin: widget.margin,
      decoration: BoxDecoration(
        color: AppTheme.pureWhite,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: hasBody
                ? () => setState(() => _expanded = !_expanded)
                : null,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppTheme.radiusSmall),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              child: Row(
                children: [
                  Expanded(child: widget.header),
                  if (hasBody)
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: const Icon(
                        Icons.expand_more,
                        size: 14,
                        color: AppTheme.textMuted,
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (hasBody && _expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: widget.body,
            ),
        ],
      ),
    );
  }
}

/// 思考过程块: 暗色斜体，默认折叠，头部带首行预览
class _ThinkingBlock extends StatelessWidget {
  final String thoughts;

  const _ThinkingBlock({required this.thoughts});

  @override
  Widget build(BuildContext context) {
    final preview = thoughts
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');

    return _CollapsibleTile(
      header: Row(
        children: [
          const Icon(
            Icons.psychology_outlined,
            size: 13,
            color: AppTheme.textMuted,
          ),
          const SizedBox(width: 4),
          const Text(
            '思考过程',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              fontStyle: FontStyle.italic,
              color: AppTheme.textMuted,
            ),
          ),
          if (preview.isNotEmpty) ...[
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                preview,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontStyle: FontStyle.italic,
                  color: AppTheme.textMuted,
                ),
              ),
            ),
          ],
        ],
      ),
      body: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppTheme.paperWarmth,
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        ),
        child: SelectableText(
          thoughts,
          style: const TextStyle(
            fontSize: 11,
            fontStyle: FontStyle.italic,
            color: AppTheme.textMuted,
            height: 1.45,
          ),
        ),
      ),
    );
  }
}
