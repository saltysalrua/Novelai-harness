import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_theme.dart';
import '../view_models/studio_view_model.dart';
import 'agent_chat_input_bar.dart';
import 'agent_chat_messages.dart';
import 'agent_rewind_view.dart';
import 'agent_session_list_view.dart';
import 'inline_agent_question_card.dart';

/// Agent 对话卡主壳: 三视图切换 (对话/会话管理/历史回溯) + 布局组装
///
/// 消息渲染块在 agent_chat_messages.dart，
/// 折叠/思考通用块在 agent_chat_blocks.dart，
/// 底部模型/思考/输入区在 agent_chat_input_bar.dart。
enum _AgentCardView { chat, sessions, rewind }

class AgentChatCard extends StatefulWidget {
  final StudioViewModel viewModel;

  const AgentChatCard({super.key, required this.viewModel});

  @override
  State<AgentChatCard> createState() => AgentChatCardState();
}

/// 公开 State：供根级全局 ESC (StudioView) 通过 GlobalKey 调起回溯视图
class AgentChatCardState extends State<AgentChatCard> {
  final ScrollController _scrollController = ScrollController();
  final FocusNode _cardFocusNode = FocusNode();
  _AgentCardView _currentView = _AgentCardView.chat;
  DateTime? _lastEscPressTime;

  @override
  void dispose() {
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

  /// 切换至历史时刻回溯视图 (流式中则先中断)
  void openRewindView() {
    if (widget.viewModel.isChatStreaming) {
      widget.viewModel.abortChat();
    }
    setState(() {
      _currentView = _AgentCardView.rewind;
    });
  }

  void _handleEscKey() {
    final now = DateTime.now();
    if (_lastEscPressTime != null &&
        now.difference(_lastEscPressTime!) <=
            const Duration(milliseconds: 400)) {
      _lastEscPressTime = null;
      // 连续按两次 ESC：全屏覆盖切换至历史时刻回溯视图
      openRewindView();
      return;
    }

    _lastEscPressTime = now;
    if (widget.viewModel.isEditingCharacterPositions) {
      widget.viewModel.setEditingCharacterPositions(false);
      return;
    }
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
            _buildPresetHeaderBar(),

            // 对话消息流展示区域
            Expanded(child: _buildMessageList()),

            // 底部控制与消息输入区 (单一底栏，高度与左侧生成坞对齐)
            AgentChatInputBar(
              viewModel: widget.viewModel,
              onSent: _scrollToBottom,
            ),
          ],
        ),
      ),
    );
  }

  /// 顶部预设切换栏 + 会话管理入口
  Widget _buildPresetHeaderBar() {
    final currentPreset = widget.viewModel.currentPreset;
    final presets = widget.viewModel.presets;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
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
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: (presetId) {
                    if (presetId != null) {
                      final p = presets.firstWhere((e) => e.id == presetId);
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
    );
  }

  /// 消息流: 历史消息 + 流式输出占位 + 内嵌提问卡片
  Widget _buildMessageList() {
    final messages = widget.viewModel.messages;
    final isStreaming = widget.viewModel.isChatStreaming;
    final activePrompt = widget.viewModel.activeQuestionPrompt;

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(12),
      itemCount:
          messages.length +
          (isStreaming ? 1 : 0) +
          (activePrompt != null ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == messages.length && isStreaming) {
          return StreamingMessageBubble(
            thoughts: widget.viewModel.currentStreamingThoughts,
            content: widget.viewModel.currentStreamingContent,
            thinkingExpanded: widget.viewModel.isThinkingExpanded,
          );
        }
        if (activePrompt != null &&
            index == messages.length + (isStreaming ? 1 : 0)) {
          return InlineAgentQuestionCard(prompt: activePrompt);
        }

        return AgentChatMessageItem(
          message: messages[index],
          thinkingExpanded: widget.viewModel.isThinkingExpanded,
        );
      },
    );
  }
}
