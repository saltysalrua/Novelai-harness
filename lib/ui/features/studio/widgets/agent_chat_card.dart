import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
    // 切换会话或 ask_user 提问弹出时滚动到底部
    if (widget.viewModel.currentSessionId !=
            oldWidget.viewModel.currentSessionId ||
        (widget.viewModel.activeQuestionPrompt != null &&
            oldWidget.viewModel.activeQuestionPrompt !=
                widget.viewModel.activeQuestionPrompt)) {
      _scrollToBottom(animate: false);
    }
  }

  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final pos = _scrollController.position;
      if (pos.pixels < pos.maxScrollExtent) {
        if (animate) {
          _scrollController.animateTo(
            pos.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        } else {
          _scrollController.jumpTo(pos.maxScrollExtent);
        }
      }
    });
  }

  /// 仅在 Agent 正在流式输出时生效：
  /// - 若当前视口已在底部 (距底部 32px 以内)，随新内容输出自动跟随保持在底部；
  /// - 若用户向上滚动翻看历史 (距底部 > 32px)，则保持在原地不打扰，绝不强拉。
  void _autoScrollOnStream() {
    if (!widget.viewModel.isChatStreaming) return;
    if (!_scrollController.hasClients) return;
    final isAtBottom = _scrollController.position.extentAfter <= 32.0;
    if (!isAtBottom) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !widget.viewModel.isChatStreaming ||
          !_scrollController.hasClients) {
        return;
      }
      final pos = _scrollController.position;
      if (pos.pixels < pos.maxScrollExtent) {
        _scrollController.jumpTo(pos.maxScrollExtent);
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
          onBack: () {
            setState(() => _currentView = _AgentCardView.chat);
            _scrollToBottom(animate: false);
          },
        );
      case _AgentCardView.rewind:
        return AgentRewindView(
          viewModel: widget.viewModel,
          onBack: () {
            setState(() => _currentView = _AgentCardView.chat);
            _scrollToBottom(animate: false);
          },
        );
      case _AgentCardView.chat:
        break;
    }

    if (_currentView == _AgentCardView.chat) {
      _autoScrollOnStream();
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
    final currentPresetId = presets.any((p) => p.id == currentPreset.id)
        ? currentPreset.id
        : (presets.isNotEmpty ? presets.first.id : null);

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: AppTheme.pureWhite,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 预设选择框 (与模型选择框统一的圆角边框胶囊样式)
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: AppTheme.pureWhite,
              borderRadius: BorderRadius.circular(AppTheme.radiusButton),
              border: Border.all(color: AppTheme.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: currentPresetId,
                isDense: true,
                dropdownColor: AppTheme.pureWhite,
                icon: const Icon(
                  Icons.arrow_drop_down_rounded,
                  size: 18,
                  color: AppTheme.textSecondary,
                ),
                borderRadius: BorderRadius.circular(8),
                menuMaxHeight: 400.0,
                selectedItemBuilder: (context) {
                  return presets.map((preset) {
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.psychology_outlined,
                          size: 14.5,
                          color: AppTheme.notionBlue,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          preset.name,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ],
                    );
                  }).toList();
                },
                items: presets.map((preset) {
                  final isSelected = preset.id == currentPresetId;
                  return DropdownMenuItem<String>(
                    value: preset.id,
                    child: Tooltip(
                      message: preset.description,
                      waitDuration: const Duration(milliseconds: 500),
                      child: Row(
                        children: [
                          Icon(
                            Icons.psychology_outlined,
                            size: 14.5,
                            color: isSelected
                                ? AppTheme.notionBlue
                                : AppTheme.stone,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              preset.name,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                color: isSelected
                                    ? AppTheme.notionBlue
                                    : AppTheme.textPrimary,
                              ),
                            ),
                          ),
                        ],
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
          ),
          IconButton(
            icon: const Icon(
              Icons.forum_outlined,
              size: 16,
              color: AppTheme.textMuted,
            ),
            tooltip: '会话管理',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
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
