import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import '../../../core/context_l10n.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/smooth_scroll_controller.dart';
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
  /// 平滑滚轮控制器：鼠标滚轮逐格瞬移改为短滑动，消除"一卡一卡"手感
  final SmoothWheelScrollController _scrollController =
      SmoothWheelScrollController();
  final FocusNode _cardFocusNode = FocusNode();
  _AgentCardView _currentView = _AgentCardView.chat;
  DateTime? _lastEscPressTime;

  /// 消息 Widget 缓存 (key = messageId|thinkingExpanded)：
  /// 消息一旦定稿不可变，滚动回视口时复用同一 Widget 实例，
  /// Element 检测到 identical 直接跳过重建，避免 Markdown 反复解析造成的掉帧。
  final Map<String, Widget> _messageWidgetCache = {};

  /// 缓存上限 (超过后整体消空，防长会话内存无限增长)
  static const int _maxCachedMessages = 600;

  @override
  void dispose() {
    _scrollController.dispose();
    _cardFocusNode.dispose();
    _messageWidgetCache.clear();
    super.dispose();
  }

  @override
  void didUpdateWidget(AgentChatCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 思考块展开开关切换后旧缓存失效，整体重建
    if (widget.viewModel.isThinkingExpanded !=
        oldWidget.viewModel.isThinkingExpanded) {
      _messageWidgetCache.clear();
    }
    // 切换会话或 ask_user 提问弹出时滚动到底部
    if (widget.viewModel.currentSessionId !=
            oldWidget.viewModel.currentSessionId ||
        (widget.viewModel.activeQuestionPrompt != null &&
            oldWidget.viewModel.activeQuestionPrompt !=
                widget.viewModel.activeQuestionPrompt)) {
      if (widget.viewModel.currentSessionId !=
          oldWidget.viewModel.currentSessionId) {
        _messageWidgetCache.clear();
      }
      _scrollToBottom(animate: false);
    }
  }

  void _scrollToBottom({bool animate = true}) {
    _scrollToBottomAfterFrames(animate: animate, remainingFrames: 3);
  }

  /// 呖后跳到底部。SliverList 的 maxScrollExtent 是估算值，新内容
  /// (尤其是被 Widget 缓存跳过重建的那一帧) 的 extent 可能晚一帧才结算，
  /// 因此跳完后再链式校验最多 [remainingFrames] 帧，直到估算稳定。
  void _scrollToBottomAfterFrames({
    required bool animate,
    required int remainingFrames,
  }) {
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
        // 静默跳转同样链式校验后续帧的估算修正 (动画模式由流式跟随逻辑兑底)，
        // 不论本轮是否跳转都续链，防止估算晚结算导致停在旧位置
        if (remainingFrames > 0) {
          _scrollToBottomAfterFrames(
            animate: animate,
            remainingFrames: remainingFrames - 1,
          );
        }
      }
    });
  }

  /// 上次跟随跳转的目标像素 (链式校验期间判断用户是否主动上翻)
  double? _lastFollowTarget;

  /// 仅在 Agent 正在流式输出时生效：
  /// - 若当前视口已在底部 (距底部 32px 以内)，随新内容输出自动跟随保持在底部；
  /// - 若用户向上滚动翻看历史 (距底部 > 32px)，则保持在原地不打扰，绝不强拉。
  ///   跟随跳转后链式校验最多 3 帧，兑底 maxScrollExtent 估算延迟结算。
  void _autoScrollOnStream() {
    if (!widget.viewModel.isChatStreaming) return;
    if (!_scrollController.hasClients) return;
    // 估算 maxScrollExtent 结算滞后一到两帧，"跳到底"后可能仍差几十像素，
    // 臂时阈值放宽到 64px；链内用户上翻判定仍按 32px 严格把关
    final isAtBottom = _scrollController.position.extentAfter <= 64.0;
    if (!isAtBottom) return;

    // 臂定时记录基准：后续帧里像素显著低于它即为用户主动上翻
    _lastFollowTarget = _scrollController.position.pixels;
    _followStreamBottom(remainingFrames: 4);
  }

  /// 流式底部跟随的链式校验：双向夹到 maxScrollExtent
  /// (既补上晚结算的增量，也纠正跳到过高估算值后的回落)
  void _followStreamBottom({required int remainingFrames}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !widget.viewModel.isChatStreaming ||
          !_scrollController.hasClients) {
        return;
      }
      final pos = _scrollController.position;
      // 用户主动向上滚离 (低于上次跟随目标 32px 以上) 则停止跟随，绝不强拉
      final last = _lastFollowTarget;
      if (last != null && pos.pixels < last - 32.0) return;
      final target = pos.maxScrollExtent;
      if ((pos.pixels - target).abs() > 0.5) {
        _lastFollowTarget = target;
        _scrollController.jumpTo(target);
      }
      // 只要还在流式且预算未尽就继续校验：估算可能晚一帧才结算，
      // “本轮无需跳转”不代表下一帧不需要
      if (remainingFrames > 0) {
        _followStreamBottom(remainingFrames: remainingFrames - 1);
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
    final colors = context.colors;
    final currentPreset = widget.viewModel.currentPreset;
    final presets = widget.viewModel.presets;
    final currentPresetId = presets.any((p) => p.id == currentPreset.id)
        ? currentPreset.id
        : (presets.isNotEmpty ? presets.first.id : null);

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        border: Border(bottom: BorderSide(color: colors.borderDefault)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 预设选择框 (与模型选择框统一的圆角边框胶囊样式)
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: colors.cardBackground,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: colors.borderDefault),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: currentPresetId,
                isDense: true,
                dropdownColor: colors.cardBackground,
                icon: Icon(
                  Icons.arrow_drop_down_rounded,
                  size: 18,
                  color: colors.textSecondary,
                ),
                borderRadius: BorderRadius.circular(8),
                menuMaxHeight: 400.0,
                selectedItemBuilder: (context) {
                  return presets.map((preset) {
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.psychology_outlined,
                          size: 15,
                          color: colors.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          preset.name,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: colors.textPrimary,
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
                            size: 15,
                            color: isSelected
                                ? colors.primary
                                : colors.textMuted,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              preset.name,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                color: isSelected
                                    ? colors.primary
                                    : colors.textPrimary,
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
            icon: Icon(Icons.forum_outlined, size: 16, color: colors.textMuted),
            tooltip: context.l10n.chatSessionManagementTooltip,
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
    final thinkingExpanded = widget.viewModel.isThinkingExpanded;

    if (_messageWidgetCache.length > _maxCachedMessages) {
      _messageWidgetCache.clear();
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(12),
      // 提高预渲染视口，配合 Widget 缓存让快速滚动不逐帧解析 Markdown
      scrollCacheExtent: const ScrollCacheExtent.pixels(600),
      addAutomaticKeepAlives: false,
      itemCount:
          messages.length +
          (isStreaming ? 1 : 0) +
          (activePrompt != null ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == messages.length && isStreaming) {
          // 流式增量局部刷新：只重建气泡子树，主工作台与参数面板零重绘；
          // 气泡内容增长时顺带驱动底部跟随滚动判定
          return ListenableBuilder(
            listenable: widget.viewModel.streamingText,
            builder: (context, _) {
              _autoScrollOnStream();
              return StreamingMessageBubble(
                thoughts: widget.viewModel.streamingText.thoughts,
                content: widget.viewModel.streamingText.content,
                thinkingExpanded: widget.viewModel.isThinkingExpanded,
                notice: widget.viewModel.streamingText.notice,
              );
            },
          );
        }
        if (activePrompt != null &&
            index == messages.length + (isStreaming ? 1 : 0)) {
          return InlineAgentQuestionCard(prompt: activePrompt);
        }

        final message = messages[index];
        final cacheKey = '${message.id}|$thinkingExpanded';
        final cached = _messageWidgetCache[cacheKey];
        if (cached != null) return cached;

        final built = AgentChatMessageItem(
          message: message,
          thinkingExpanded: thinkingExpanded,
        );
        _messageWidgetCache[cacheKey] = built;
        return built;
      },
    );
  }
}
