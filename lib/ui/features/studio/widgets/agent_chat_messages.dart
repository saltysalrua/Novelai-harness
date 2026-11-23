import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show RenderProxyBox, Selectable, SelectionRegistrar;
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
// markdown 只作为 flutter_markdown_plus 的传递依赖出现，这里只用它的元素类型。
// ignore: depend_on_referenced_packages
import 'package:markdown/markdown.dart' as md;
import '../../../../core/harness/reply_marker.dart';
import '../../../../core/harness/types.dart';
import '../../../../data/services/prompt_library_mention.dart';
import '../../../core/context_l10n.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../../core/widgets/app_transitions.dart';
import '../../../core/widgets/stable_edge_selection.dart';
import 'agent_chat_blocks.dart';
import 'chat_image_attachment.dart';
import 'chat_mention_text_controller.dart';
import 'image_lightbox.dart';

/// 单条对话消息的现代 AI Chat 渲染入口
/// (system 隐藏 / user 右侧气泡 / assistant 左侧消息+合并工具步骤卡 / 未配对 tool 结果兜底)
class AgentChatMessageItem extends StatefulWidget {
  final AgentMessage message;

  /// 思考块全局展开开关 (Ctrl+O)，透传给助手消息的思考块
  final bool thinkingExpanded;

  /// 只保活近期消息，避免长会话无限持有 Markdown 和图片子树。
  final bool keepAlive;

  /// 与 [message.toolCalls] 按下标配对的工具执行结果列表
  final List<AgentMessage?> pairedToolResults;

  /// 当前消息是否作为已合并到前一条助手卡片中的工具结果 (若是则隐藏重复行)
  final bool isMergedToolResult;

  /// 回溯/编辑该消息的回调
  final ValueChanged<String>? onRewind;

  /// 是否播放新消息入场动效 (仅实时新入列消息开启，历史与滚动复用保持静止)
  final bool animateEntry;

  /// 当前消息中的未配对工具调用是否处于实时执行中
  final bool isActiveTool;

  const AgentChatMessageItem({
    super.key,
    required this.message,
    this.thinkingExpanded = false,
    this.keepAlive = false,
    this.pairedToolResults = const [],
    this.isMergedToolResult = false,
    this.onRewind,
    this.animateEntry = false,
    this.isActiveTool = false,
  });

  @override
  State<AgentChatMessageItem> createState() => _AgentChatMessageItemState();
}

class _AgentChatMessageItemState extends State<AgentChatMessageItem>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  AnimationController? _entryController;
  CurvedAnimation? _entryCurve;
  Animation<double>? _entryOpacity;
  Animation<Offset>? _entryOffset;

  @override
  bool get wantKeepAlive => widget.keepAlive;

  @override
  void initState() {
    super.initState();
    if (widget.animateEntry) {
      final controller = AnimationController(
        vsync: this,
        duration: AppMotionDurations.fast,
      );
      final curved = CurvedAnimation(
        parent: controller,
        curve: AppMotionCurves.smoothOut,
      );
      _entryController = controller;
      _entryCurve = curved;
      _entryOpacity = Tween<double>(begin: 0.25, end: 1.0).animate(curved);
      _entryOffset = Tween<Offset>(
        begin: const Offset(0, 0.08),
        end: Offset.zero,
      ).animate(curved);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = _entryController;
    if (controller == null || controller.isCompleted) return;
    if (AppMotion.shouldReduceMotion(context)) {
      controller.value = 1.0;
    } else if (!controller.isAnimating && controller.value == 0.0) {
      controller.forward(from: 0.0);
    }
  }

  @override
  void didUpdateWidget(AgentChatMessageItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.keepAlive != widget.keepAlive) updateKeepAlive();
  }

  @override
  void dispose() {
    _entryCurve?.dispose();
    _entryController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final message = widget.message;
    final Widget content;
    switch (message.role) {
      case AgentRole.system:
        return const SizedBox.shrink();
      case AgentRole.user:
        content = UserMessageRow(message: message, onRewind: widget.onRewind);
      case AgentRole.tool:
        if (widget.isMergedToolResult) return const SizedBox.shrink();
        content = ToolResultBlock(message: message);
      case AgentRole.assistant:
        content = AssistantMessageItem(
          message: message,
          thinkingExpanded: widget.thinkingExpanded,
          pairedToolResults: widget.pairedToolResults,
          onRewind: widget.onRewind,
          isActiveTool: widget.isActiveTool,
        );
    }
    if (_entryController == null) {
      return _KeepAliveSafeSelectionScope(child: content);
    }
    // FadeTransition 在 opacity == 1.0 时底层跳过 OpacityLayer，无需拆树即可实现零常驻 saveLayer。
    return _KeepAliveSafeSelectionScope(
      child: FadeTransition(
        opacity: _entryOpacity!,
        child: SlideTransition(position: _entryOffset!, child: content),
      ),
    );
  }
}

/// 隔离 SliverList 离屏保活节点与外层 SelectionArea 的注册时序：
/// 离屏 _keepAliveBucket 中的消息在依赖刷新时可能重建新 Text，但 SliverList 不会
/// 对其执行 layout。本代理仅在子级实际完成 performLayout 且对应 RenderBox 具备
/// hasSize 后，才将 Selectable 转发给上级 SelectionRegistrar，防止 SelectionArea
/// 在帧末排序时读取未布局 RenderParagraph.size 触发断言。
class _KeepAliveSafeSelectionScope extends StatefulWidget {
  final Widget child;

  const _KeepAliveSafeSelectionScope({required this.child});

  @override
  State<_KeepAliveSafeSelectionScope> createState() =>
      _KeepAliveSafeSelectionScopeState();
}

class _KeepAliveSafeSelectionScopeState
    extends State<_KeepAliveSafeSelectionScope> {
  final _DeferredSelectionRegistrar _proxyRegistrar =
      _DeferredSelectionRegistrar();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _proxyRegistrar.updateParent(SelectionContainer.maybeOf(context));
  }

  @override
  void deactivate() {
    _proxyRegistrar.detachAllForwarded();
    super.deactivate();
  }

  @override
  void dispose() {
    _proxyRegistrar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SelectionRegistrarScope(
      registrar: _proxyRegistrar,
      child: _LayoutFlushProxy(
        onLayout: _scheduleFlushAfterLayout,
        child: widget.child,
      ),
    );
  }

  void _scheduleFlushAfterLayout() {
    if (!mounted || !_proxyRegistrar.hasPending) return;
    _proxyRegistrar.scheduleFlush(() => mounted);
  }
}

class _DeferredSelectionRegistrar implements SelectionRegistrar {
  SelectionRegistrar? _parent;
  final Set<Selectable> _pending = <Selectable>{};
  final Set<Selectable> _forwarded = <Selectable>{};
  bool _flushScheduled = false;

  bool get hasPending => _pending.isNotEmpty;

  void updateParent(SelectionRegistrar? nextParent) {
    if (identical(_parent, nextParent)) return;
    detachAllForwarded();
    _parent = nextParent;
  }

  void detachAllForwarded() {
    final parent = _parent;
    if (parent != null && _forwarded.isNotEmpty) {
      for (final s in _forwarded) {
        parent.remove(s);
      }
      _pending.addAll(_forwarded);
      _forwarded.clear();
    }
  }

  @override
  void add(Selectable selectable) {
    if (_forwarded.contains(selectable)) return;
    _pending.add(selectable);
  }

  @override
  void remove(Selectable selectable) {
    _pending.remove(selectable);
    if (_forwarded.remove(selectable)) {
      _parent?.remove(selectable);
    }
  }

  void scheduleFlush(bool Function() isScopeMounted) {
    if (_flushScheduled || _pending.isEmpty || _parent == null) return;
    _flushScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _flushScheduled = false;
      if (!isScopeMounted()) return;
      flushLaidOut();
    });
  }

  void flushLaidOut() {
    final parent = _parent;
    if (parent == null || _pending.isEmpty) return;
    final ready = <Selectable>[];
    for (final s in _pending) {
      if (_isSelectableLaidOut(s)) {
        ready.add(s);
      }
    }
    for (final s in ready) {
      _pending.remove(s);
      if (_forwarded.add(s)) {
        parent.add(s);
      }
    }
  }

  bool _isSelectableLaidOut(Selectable s) {
    if (s is State) {
      final state = s as State;
      if (!state.mounted) return false;
      final ctx = state.context;
      if (ctx is Element && !ctx.mounted) return false;
      final ro = ctx.findRenderObject();
      return ro is RenderBox && ro.attached && ro.hasSize;
    }
    return true;
  }

  void dispose() {
    detachAllForwarded();
    _forwarded.clear();
    _pending.clear();
    _parent = null;
  }
}

class _LayoutFlushProxy extends SingleChildRenderObjectWidget {
  final VoidCallback onLayout;

  const _LayoutFlushProxy({required this.onLayout, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderLayoutFlushProxy(onLayout);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderLayoutFlushProxy renderObject,
  ) {
    renderObject.onLayout = onLayout;
  }
}

class _RenderLayoutFlushProxy extends RenderProxyBox {
  VoidCallback onLayout;

  _RenderLayoutFlushProxy(this.onLayout);

  @override
  void performLayout() {
    super.performLayout();
    onLayout();
  }
}

/// 悬停高亮消息外框 + 固定高度快捷操作栏共享容器：
/// 鼠标悬停仅更新局部 [ValueNotifier]，不重建正文 Markdown / 工具块 / 气泡内容。
class _HoverableMessageActionScope extends StatefulWidget {
  final Widget Function(
    BuildContext context,
    ValueListenable<bool> hoveredListenable,
  )
  builder;

  const _HoverableMessageActionScope({required this.builder});

  @override
  State<_HoverableMessageActionScope> createState() =>
      _HoverableMessageActionScopeState();
}

class _HoverableMessageActionScopeState
    extends State<_HoverableMessageActionScope> {
  final ValueNotifier<bool> _hovered = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _hovered.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        if (!_hovered.value) _hovered.value = true;
      },
      onExit: (_) {
        if (_hovered.value) _hovered.value = false;
      },
      child: widget.builder(context, _hovered),
    );
  }
}

/// 消息底部紧凑操作栏（复制 + 回退）：
/// 通过图标颜色透明通道渐变替代整栏 [AnimatedOpacity]，避免每条消息产生离屏 `saveLayer`。
class _MessageActionBar extends StatelessWidget {
  final ValueListenable<bool> hoveredListenable;
  final String? copyText;
  final Key? copyKey;
  final String copyTooltip;
  final String copiedTooltip;
  final Key? rewindKey;
  final IconData rewindIcon;
  final double rewindIconSize;
  final String? rewindTooltip;
  final VoidCallback? onRewind;

  const _MessageActionBar({
    required this.hoveredListenable,
    required this.copyTooltip,
    required this.copiedTooltip,
    required this.rewindIcon,
    required this.rewindIconSize,
    this.copyText,
    this.copyKey,
    this.rewindKey,
    this.rewindTooltip,
    this.onRewind,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: hoveredListenable,
      builder: (context, hovered, _) {
        final colors = context.colors;
        return TweenAnimationBuilder<double>(
          tween: Tween<double>(end: hovered ? 0.9 : 0.35),
          duration: AppMotion.resolveDuration(context, AppMotionDurations.micro),
          curve: AppMotionCurves.smoothOut,
          builder: (context, alpha, _) {
            final mutedColor = colors.textMuted.withValues(alpha: alpha);
            return SizedBox(
              height: 18,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (copyText != null)
                    _MessageCopyButton(
                      key: copyKey,
                      text: copyText!,
                      iconColor: mutedColor,
                      copyTooltip: copyTooltip,
                      copiedTooltip: copiedTooltip,
                    ),
                  if (onRewind != null)
                    AppIconButton(
                      key: rewindKey,
                      icon: rewindIcon,
                      size: 20,
                      iconSize: rewindIconSize,
                      iconColor: mutedColor,
                      tooltip: rewindTooltip,
                      variant: AppIconButtonVariant.ghost,
                      onPressed: onRewind,
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// 带即时复制成功反馈的紧凑图标按钮
class _MessageCopyButton extends StatefulWidget {
  final String text;
  final Color iconColor;
  final String copyTooltip;
  final String copiedTooltip;

  const _MessageCopyButton({
    super.key,
    required this.text,
    required this.iconColor,
    required this.copyTooltip,
    required this.copiedTooltip,
  });

  @override
  State<_MessageCopyButton> createState() => _MessageCopyButtonState();
}

class _MessageCopyButtonState extends State<_MessageCopyButton> {
  bool _copied = false;
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (!mounted) return;
    setState(() => _copied = true);
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tooltip = _copied ? widget.copiedTooltip : widget.copyTooltip;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            onTap: _copy,
            child: SizedBox(
              width: 20,
              height: 20,
              child: Center(
                child: AppIconSwap(
                  swapKey: _copied,
                  enableBlur: false,
                  duration: AppMotionDurations.quick,
                  child: _copied
                      ? AppSuccessCheck(
                          key: const ValueKey(true),
                          visible: true,
                          size: 13,
                          strokeWidth: 1.8,
                          color: colors.success,
                          bobDistance: 3.0,
                        )
                      : Icon(
                          Icons.content_copy_rounded,
                          key: const ValueKey(false),
                          size: 12,
                          color: widget.iconColor,
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 用户消息: 右侧圆角气泡 + 图片附件缩略图 + 底部复制/编辑撤回操作栏
class UserMessageRow extends StatelessWidget {
  final AgentMessage message;
  final ValueChanged<String>? onRewind;

  const UserMessageRow({super.key, required this.message, this.onRewind});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.maybeL10n;
    final images = message.images;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 36),
      child: _HoverableMessageActionScope(
        builder: (context, hoveredListenable) => Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: colors.elevatedBackground,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: colors.borderSubtle),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (images.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final img in images)
                          ChatImageThumbnail(
                            bytes: img.bytes,
                            size: 72,
                            onTap: () =>
                                showImageLightboxBytes(context, img.bytes),
                          ),
                      ],
                    ),
                  if (images.isNotEmpty && message.content.isNotEmpty)
                    const SizedBox(height: 6),
                  if (message.content.isNotEmpty)
                    _buildUserContent(
                      message.content,
                      TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        color: colors.textPrimary,
                        height: 1.5,
                      ),
                    ),
                ],
              ),
            ),
            if (message.content.isNotEmpty || onRewind != null) ...[
              const SizedBox(height: 2),
              _MessageActionBar(
                hoveredListenable: hoveredListenable,
                copyText: message.content.isNotEmpty ? message.content : null,
                copyKey: ValueKey('user_msg_copy_${message.id}'),
                copyTooltip: l10n?.chatCopyMessageTooltip ?? '复制内容',
                copiedTooltip: l10n?.chatCopiedTooltip ?? '已复制',
                rewindKey: ValueKey('user_msg_rewind_${message.id}'),
                rewindIcon: Icons.edit_note_rounded,
                rewindIconSize: 13,
                rewindTooltip: l10n?.chatEditAndRewindTooltip ?? '编辑并撤回后续对话',
                onRewind: onRewind != null ? () => onRewind!(message.id) : null,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildUserContent(String content, TextStyle baseStyle) {
    final matches = bracketMentionRegex.allMatches(content).toList();
    if (matches.isEmpty) {
      return SelectableText(content, style: baseStyle);
    }
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final match in matches) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: content.substring(cursor, match.start)));
      }
      final title = match.group(1)?.trim() ?? '';
      if (title.isNotEmpty) {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: CharacterMentionChip(title: title),
          ),
        );
      } else {
        spans.add(TextSpan(text: match.group(0)));
      }
      cursor = match.end;
    }
    if (cursor < content.length) {
      spans.add(TextSpan(text: content.substring(cursor)));
    }
    return SelectableText.rich(TextSpan(style: baseStyle, children: spans));
  }
}

/// 助手消息: 思考块 + 合并工具步骤卡 + Markdown 正文 + 紧凑底部操作栏
class AssistantMessageItem extends StatelessWidget {
  final AgentMessage message;

  /// 思考块全局展开开关 (Ctrl+O)
  final bool thinkingExpanded;

  /// 按调用顺序配对的工具执行结果
  final List<AgentMessage?> pairedToolResults;

  /// 回退到此回复的回调
  final ValueChanged<String>? onRewind;

  /// 是否正在进行本轮流式执行（未配对的工具调用将显示激活态动画）
  final bool isActiveTool;

  const AssistantMessageItem({
    super.key,
    required this.message,
    this.thinkingExpanded = false,
    this.pairedToolResults = const [],
    this.onRewind,
    this.isActiveTool = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.maybeL10n;
    // 展示层兜底：正文里的 [回复 #N] 标记与残渣一律不上 UI
    // (历史会话、陈旧落盘数据也一并洗干净)
    final content = ReplyMarker.strip(message.content);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _HoverableMessageActionScope(
        builder: (context, hoveredListenable) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.replyNumber != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: SelectableText(
                  '#${message.replyNumber}',
                  style: TextStyle(fontSize: 11, color: colors.textMuted),
                ),
              ),
            if (message.thoughts.isNotEmpty)
              ThinkingBlock(
                thoughts: message.thoughts,
                forceExpanded: thinkingExpanded,
              ),
            if (message.toolCalls != null)
              for (final (index, call) in message.toolCalls!.indexed)
                Padding(
                  // 协议 ID 在旧历史中可能重复或为空，不能直接当组件身份。
                  // 消息 + 调用位置保证唯一，追加调用/思考块时保留各自折叠状态。
                  key: ValueKey((message.id, call.id, index)),
                  padding: const EdgeInsets.only(bottom: 6),
                  child: ToolCallBlock(
                    call: call,
                    result: index < pairedToolResults.length
                        ? pairedToolResults[index]
                        : null,
                    isActive:
                        isActiveTool &&
                        (index >= pairedToolResults.length ||
                            pairedToolResults[index] == null),
                  ),
                ),
            if (content.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: AgentMarkdownBody(data: content),
              ),
            if (content.isNotEmpty || onRewind != null) ...[
              const SizedBox(height: 3),
              _MessageActionBar(
                hoveredListenable: hoveredListenable,
                copyText: content.isNotEmpty ? content : null,
                copyKey: ValueKey('assistant_msg_copy_${message.id}'),
                copyTooltip: l10n?.chatCopyMessageTooltip ?? '复制内容',
                copiedTooltip: l10n?.chatCopiedTooltip ?? '已复制',
                rewindKey: ValueKey('assistant_msg_rewind_${message.id}'),
                rewindIcon: Icons.history_rounded,
                rewindIconSize: 12,
                rewindTooltip: l10n?.chatRewindToHereTooltip ?? '回退到此回复',
                onRewind: onRewind != null ? () => onRewind!(message.id) : null,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 工具步骤卡: 合并展示调用入参与配对结果 (无配对结果时仅显示调用态)，附图直出
class ToolCallBlock extends StatelessWidget {
  final ToolCall call;
  final AgentMessage? result;
  final bool isActive;

  const ToolCallBlock({
    super.key,
    required this.call,
    this.result,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final pairedResult = result;
    final running = pairedResult == null && isActive;
    final statusColor = pairedResult == null
        ? colors.primary
        : (pairedResult.isError ? colors.error : colors.success);
    final statusIcon = pairedResult == null
        ? Icons.build_circle_outlined
        : (pairedResult.isError
              ? Icons.error_outline_rounded
              : Icons.check_circle_outline_rounded);

    final resultSummary =
        pairedResult != null && pairedResult.content.trim().isNotEmpty
        ? firstNonEmptyLine(pairedResult.content)
        : '';
    final summary = resultSummary.isNotEmpty
        ? resultSummary
        : summarizeToolArguments(call.arguments);

    final leadingIndicator = AppIconSwap(
      swapKey: running
          ? 'running'
          : (pairedResult == null ? 'pending' : pairedResult.isError),
      enableBlur: false,
      duration: AppMotionDurations.quick,
      child: running
          ? SizedBox(
              key: const ValueKey('running'),
              width: 14,
              height: 14,
              child: Center(
                child: AppMatrixDotLoader(
                  variant: AppMatrixDotVariant.orbit,
                  rounded: true,
                  dotSize: 2.0,
                  gap: 1.5,
                  baseColor: colors.primary.withValues(alpha: 0.25),
                  activeColor: colors.primary,
                ),
              ),
            )
          : Icon(
              statusIcon,
              key: ValueKey(
                pairedResult == null ? 'pending' : pairedResult.isError,
              ),
              size: 14,
              color: statusColor,
            ),
    );

    final nameStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      color: colors.textPrimary,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CollapsibleTile(
          margin: EdgeInsets.zero,
          backgroundColor: colors.mutedBackground.withValues(alpha: 0.4),
          borderColor: colors.borderSubtle,
          borderRadius: AppRadius.md,
          headerPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 6,
          ),
          header: Row(
            children: [
              leadingIndicator,
              const SizedBox(width: 6),
              Flexible(
                child: SelectionContainer.disabled(
                  child: running
                      ? AppShimmerText(
                          text: call.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          baseColor: colors.textPrimary,
                          highlightColor: colors.primary,
                          style: nameStyle,
                        )
                      : Text(
                          call.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: nameStyle,
                        ),
                ),
              ),
              if (summary.isNotEmpty) ...[
                const SizedBox(width: 6),
                Expanded(
                  child: SelectionContainer.disabled(
                    child: Text(
                      summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: colors.textMuted),
                    ),
                  ),
                ),
              ],
            ],
          ),
          bodyBuilder: (context) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SelectableText(
                const JsonEncoder.withIndent('  ').convert(call.arguments),
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: colors.textSecondary,
                  height: 1.45,
                ),
              ),
              if (pairedResult != null && pairedResult.content.isNotEmpty) ...[
                Divider(height: 12, color: colors.borderSubtle),
                BoundedSelectableText(
                  text: pairedResult.content,
                  maxHeight: 280,
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: colors.textSecondary,
                    height: 1.45,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (pairedResult?.imageBase64 != null &&
            pairedResult!.imageBase64!.isNotEmpty)
          _ToolOutputImagePreview(bytes: pairedResult.imageBytes!),
      ],
    );
  }
}

/// 独立工具结果块 (无前序配对调用时的兜底渲染): 状态图标 + 工具名 + 行数摘要，附图直出
class ToolResultBlock extends StatelessWidget {
  final AgentMessage message;

  const ToolResultBlock({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.maybeL10n;
    final lineCount = message.content.isEmpty
        ? 0
        : message.content.split('\n').length;
    final firstLine = message.content.isEmpty
        ? (l10n?.chatToolNoOutput ?? '(无输出)')
        : message.content.split('\n').first.trim();
    final accent = message.isError ? colors.error : colors.success;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CollapsibleTile(
            margin: EdgeInsets.zero,
            backgroundColor: colors.mutedBackground.withValues(alpha: 0.4),
            borderColor: colors.borderSubtle,
            borderRadius: AppRadius.md,
            headerPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 6,
            ),
            header: Row(
              children: [
                Icon(
                  message.isError
                      ? Icons.error_outline_rounded
                      : Icons.check_circle_outline_rounded,
                  size: 14,
                  color: accent,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    message.toolName ?? (l10n?.toolFallbackName ?? '工具'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l10n?.chatToolResultSummary(lineCount, firstLine) ??
                        '$lineCount 行 · $firstLine',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: colors.textMuted),
                  ),
                ),
              ],
            ),
            bodyBuilder: (context) => BoundedSelectableText(
              text: message.content,
              maxHeight: 320,
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: colors.textSecondary,
                height: 1.45,
              ),
            ),
          ),
          if (message.imageBase64 != null && message.imageBase64!.isNotEmpty)
            _ToolOutputImagePreview(bytes: message.imageBytes!),
        ],
      ),
    );
  }
}

/// 工具结果附带的图片预览：按面板宽度缓存解码尺寸，并用文件头尺寸预留 AspectRatio 高度。
class _ToolOutputImagePreview extends StatelessWidget {
  final Uint8List bytes;

  const _ToolOutputImagePreview({required this.bytes});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final panelWidth = constraints.maxWidth;
          final dpr = MediaQuery.devicePixelRatioOf(context);
          // 按 128px 档位量化解码缓存宽度，拖拽分栏/缩放窗口时不逐像素触发重解码
          final rawCacheWidth = (panelWidth * dpr).round();
          final cacheWidth = (((rawCacheWidth + 127) ~/ 128) * 128).clamp(
            320,
            1600,
          );
          final image = GestureDetector(
            onTap: () => showImageLightboxBytes(context, bytes),
            child: MouseRegion(
              cursor: SystemMouseCursors.zoomIn,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: Image.memory(
                  bytes,
                  fit: BoxFit.contain,
                  cacheWidth: cacheWidth,
                  filterQuality: FilterQuality.medium,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
          );
          final probed = probeImageHeaderSize(bytes);
          if (probed == null) {
            return SizedBox(width: double.infinity, child: image);
          }
          return ColoredBox(
            color: colors.canvasBackground,
            child: AspectRatio(
              aspectRatio: probed.width / probed.height,
              child: image,
            ),
          );
        },
      ),
    );
  }
}

/// 流式输出占位: 角色头 + 实时思考块 + 推理预览 + 正文 Markdown + 矩阵点进度指示
class StreamingMessageBubble extends StatelessWidget {
  final String thoughts;
  final String content;

  /// 思考块全局展开开关 (Ctrl+O)，开启时流式思考不截断行数
  final bool thinkingExpanded;

  /// 自动重试提示 (瞬态错误退避等待期间显示，null 则不渲染)
  final String? notice;

  const StreamingMessageBubble({
    super.key,
    required this.thoughts,
    required this.content,
    this.thinkingExpanded = false,
    this.notice,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.maybeL10n;
    // 展示层兜底：流式气泡里的标记与残渣不上 UI
    final visibleContent = ReplyMarker.strip(content);
    final hasNotice = notice != null && notice!.isNotEmpty;
    final isThinkingActive =
        thoughts.isNotEmpty && visibleContent.isEmpty && !hasNotice;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasNotice)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: SelectionContainer.disabled(
                child: AppThinkingStatus(
                  status: notice!,
                  enableBlur: false,
                  style: TextStyle(fontSize: 12, color: colors.textMuted),
                  baseColor: colors.textMuted,
                  highlightColor: colors.textPrimary,
                ),
              ),
            ),
          if (thoughts.isNotEmpty)
            ThinkingBlock(
              thoughts: thoughts,
              forceExpanded: thinkingExpanded,
              isThinking: isThinkingActive,
            ),
          if (isThinkingActive && !thinkingExpanded)
            SelectionContainer.disabled(
              child: _ReasoningStreamPreview(
                thoughts: ReplyMarker.strip(thoughts),
              ),
            ),
          if (visibleContent.isNotEmpty)
            AgentMarkdownBody(data: visibleContent, isStreaming: true),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: visibleContent.isEmpty && !hasNotice
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppMatrixDotLoader(
                        variant: AppMatrixDotVariant.scan,
                        rounded: true,
                        dotSize: 2.2,
                        gap: 1.8,
                        baseColor: colors.primary.withValues(alpha: 0.25),
                        activeColor: colors.primary,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: SelectionContainer.disabled(
                          child: AppThinkingStatus(
                            status: isThinkingActive
                                ? (l10n?.chatThinkingProgress ?? '正在思考...')
                                : (l10n?.chatConceiving ?? '构思中...'),
                            enableBlur: false,
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.textMuted,
                            ),
                            baseColor: colors.textMuted,
                            highlightColor: colors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  )
                : AppMatrixDotLoader(
                    variant: AppMatrixDotVariant.scan,
                    rounded: true,
                    dotSize: 2.2,
                    gap: 1.8,
                    baseColor: colors.primary.withValues(alpha: 0.25),
                    activeColor: colors.primary,
                  ),
          ),
        ],
      ),
    );
  }
}

/// 折叠流式推理的 2 行实时尾段预览：随推理增量平滑上滑切换（禁用 blur/saveLayer）
class _ReasoningStreamPreview extends StatelessWidget {
  final String thoughts;

  const _ReasoningStreamPreview({required this.thoughts});

  static String _tailSnippet(String raw) {
    final lines = raw
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.length <= 1) return '';
    final tail = lines.length >= 2
        ? lines.sublist(lines.length - 2).join('\n')
        : lines.last;
    return tail;
  }

  @override
  Widget build(BuildContext context) {
    final snippet = _tailSnippet(thoughts);
    if (snippet.isEmpty) return const SizedBox.shrink();
    final colors = context.colors;
    final duration = AppMotion.resolveDuration(
      context,
      AppMotionDurations.quick,
    );
    return Padding(
      padding: const EdgeInsets.only(left: 10, top: 2, bottom: 4),
      child: ClipRect(
        child: AnimatedSwitcher(
          duration: duration,
          switchInCurve: AppMotionCurves.smoothOut,
          switchOutCurve: AppMotionCurves.smoothOut,
          layoutBuilder: (currentChild, previousChildren) => Stack(
            alignment: Alignment.topLeft,
            children: [
              ...previousChildren,
              ?currentChild,
            ],
          ),
          transitionBuilder: (child, animation) {
            final offset = Tween<Offset>(
              begin: const Offset(0, 0.25),
              end: Offset.zero,
            ).animate(animation);
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(position: offset, child: child),
            );
          },
          child: Text(
            snippet,
            key: ValueKey(snippet),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.4,
              color: colors.textMuted.withValues(alpha: 0.85),
            ),
          ),
        ),
      ),
    );
  }
}

/// 将工具参数压缩为单行摘要: key=value key2="..."
String summarizeToolArguments(Map<String, dynamic> arguments) {
  if (arguments.isEmpty) return '{}';
  return arguments.entries
      .map((e) {
        final value = jsonEncode(e.value);
        final short = value.length > 60 ? '${value.substring(0, 60)}…' : value;
        return '${e.key}=$short';
      })
      .join(' ');
}

/// Agent 对话流统一的 Markdown 渲染样式表 (主题感知: 亮暗色随当前上下文语义色取值)
MarkdownStyleSheet buildAgentMarkdownStyleSheet(BuildContext context) {
  final colors = context.colors;
  final baseColor = colors.textPrimary;
  return MarkdownStyleSheet(
    p: TextStyle(fontSize: 14, color: baseColor, height: 1.5),
    h1: TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w700,
      color: baseColor,
      height: 1.4,
    ),
    h2: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      color: baseColor,
      height: 1.4,
    ),
    h3: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: baseColor,
      height: 1.4,
    ),
    h4: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: baseColor,
      height: 1.4,
    ),
    h5: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: baseColor,
      height: 1.4,
    ),
    h6: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: baseColor,
      height: 1.4,
    ),
    em: const TextStyle(fontStyle: FontStyle.italic),
    strong: const TextStyle(fontWeight: FontWeight.w700),
    del: const TextStyle(decoration: TextDecoration.lineThrough),
    code: TextStyle(
      fontSize: 13,
      fontFamily: 'monospace',
      backgroundColor: Colors.transparent,
      color: colors.primary,
    ),
    codeblockDecoration: BoxDecoration(
      color: colors.cardBackground,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      border: Border.all(color: colors.borderDefault),
    ),
    codeblockPadding: const EdgeInsets.all(8),
    blockquote: TextStyle(
      fontSize: 13,
      color: colors.textSecondary,
      height: 1.45,
    ),
    blockquoteDecoration: BoxDecoration(
      color: colors.cardBackground,
      border: Border(left: BorderSide(color: colors.primary, width: 3)),
      borderRadius: BorderRadius.circular(2),
    ),
    blockquotePadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    listBullet: TextStyle(fontSize: 14, color: baseColor),
    tableBody: TextStyle(fontSize: 13, color: baseColor),
    tableHead: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: baseColor,
    ),
    tableBorder: TableBorder.all(color: colors.borderDefault, width: 1),
    tableCellsPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    listIndent: 16,
    pPadding: const EdgeInsets.only(bottom: 6),
    h1Padding: const EdgeInsets.only(top: 8, bottom: 4),
    h2Padding: const EdgeInsets.only(top: 8, bottom: 4),
    h3Padding: const EdgeInsets.only(top: 6, bottom: 2),
    horizontalRuleDecoration: BoxDecoration(
      border: Border(top: BorderSide(color: colors.borderDefault, width: 1)),
    ),
  );
}

/// 代码块单独横向滚动。用 [SelectableText] 而不是外层 [SelectionArea] 的普通文本，
/// 否则列表的边缘自动滚动会把又宽又矮的代码视口来回拽，行尾选不中。
class _AgentCodeBlockBuilder extends MarkdownElementBuilder {
  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    var text = element.textContent;
    if (text.endsWith('\n')) {
      text = text.substring(0, text.length - 1);
    }
    return _AgentCodeBlock(
      text: text,
      style:
          preferredStyle ??
          const TextStyle(fontSize: 13, fontFamily: 'monospace'),
    );
  }
}

class _AgentCodeBlock extends StatefulWidget {
  final String text;
  final TextStyle style;

  const _AgentCodeBlock({required this.text, required this.style});

  @override
  State<_AgentCodeBlock> createState() => _AgentCodeBlockState();
}

class _AgentCodeBlockState extends State<_AgentCodeBlock> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StableEdgeSelection(
      controller: _controller,
      axis: Axis.horizontal,
      child: SingleChildScrollView(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        physics: const StableSelectionScrollPhysics(),
        padding: const EdgeInsets.all(8),
        child: SelectableText(
          widget.text,
          style: widget.style,
          scrollPhysics: const StableSelectionScrollPhysics(),
        ),
      ),
    );
  }
}

/// 正文与思考增量分开缓存；仅正文或主题变化时重新创建 Markdown 子树。
///
/// 段落用普通文本，交给消息列表外层的 [SelectionArea] 一次划选。
/// 思考块和工具输出仍用 [SelectableText]，避免展开时把尚未布局的段落塞进选区容器。
class AgentMarkdownBody extends StatefulWidget {
  final String data;
  final bool isStreaming;

  const AgentMarkdownBody({
    super.key,
    required this.data,
    this.isStreaming = false,
  });

  @override
  State<AgentMarkdownBody> createState() => _AgentMarkdownBodyState();
}

class _AgentMarkdownBodyState extends State<AgentMarkdownBody> {
  Widget? _rendered;
  String _stablePrefix = '';
  Widget? _stableRendered;
  int _tailBlockIndex = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rendered = null;
    _stableRendered = null;
  }

  @override
  void didUpdateWidget(AgentMarkdownBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data ||
        oldWidget.isStreaming != widget.isStreaming) {
      _rendered = null;
      if (!widget.isStreaming) {
        _stablePrefix = '';
        _stableRendered = null;
        _tailBlockIndex = 0;
      }
    }
  }

  /// 在闭合围栏代码块之外切分最后一个空行分隔点，保证已稳定段落不重复解析，
  /// 仅对新开启的尾部段落执行轻量淡入（禁止逐词 blur/saveLayer）。
  static (String stable, String tail) _splitStreamingBlocks(String source) {
    final lines = source.split('\n');
    String? fenceMarker;
    var lastSplitLine = -1;
    for (var i = 0; i < lines.length; i++) {
      final trimmed = lines[i].trimLeft();
      if (fenceMarker == null) {
        if (trimmed.startsWith('```')) {
          fenceMarker = '```';
        } else if (trimmed.startsWith('~~~')) {
          fenceMarker = '~~~';
        } else if (trimmed.isEmpty && i > 0 && i < lines.length - 1) {
          lastSplitLine = i;
        }
      } else if (trimmed.startsWith(fenceMarker)) {
        fenceMarker = null;
      }
    }
    if (lastSplitLine <= 0) return ('', source);
    final stable = lines.sublist(0, lastSplitLine).join('\n');
    final tail = lines.sublist(lastSplitLine + 1).join('\n');
    return (stable, tail);
  }

  MarkdownBody _buildMarkdown(BuildContext context, String text) =>
      MarkdownBody(
        data: text,
        selectable: false,
        softLineBreak: true,
        builders: {'pre': _AgentCodeBlockBuilder()},
        styleSheet: buildAgentMarkdownStyleSheet(context),
      );

  @override
  Widget build(BuildContext context) {
    if (!widget.isStreaming) {
      return _rendered ??= _buildMarkdown(context, widget.data);
    }

    final (stable, tail) = _splitStreamingBlocks(widget.data);
    if (stable != _stablePrefix) {
      if (stable.length > _stablePrefix.length) {
        _tailBlockIndex++;
      } else if (stable.isEmpty) {
        _tailBlockIndex = 0;
      }
      _stablePrefix = stable;
      _stableRendered = stable.isEmpty ? null : _buildMarkdown(context, stable);
    }
    final stableWidget =
        _stableRendered ??= (stable.isEmpty
            ? null
            : _buildMarkdown(context, stable));

    if (stableWidget == null) {
      return _buildMarkdown(context, tail);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        RepaintBoundary(child: stableWidget),
        if (tail.isNotEmpty) ...[
          const SizedBox(height: 8),
          _StreamingBlockFade(
            key: ValueKey(_tailBlockIndex),
            child: _buildMarkdown(context, tail),
          ),
        ],
      ],
    );
  }
}

/// 新流式段落出现时的轻量淡入；完成后自动卸载 Opacity 避免长列表常驻 saveLayer。
class _StreamingBlockFade extends StatefulWidget {
  final Widget child;

  const _StreamingBlockFade({super.key, required this.child});

  @override
  State<_StreamingBlockFade> createState() => _StreamingBlockFadeState();
}

class _StreamingBlockFadeState extends State<_StreamingBlockFade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _curved;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppMotionDurations.quick,
    );
    _curved = CurvedAnimation(
      parent: _controller,
      curve: AppMotionCurves.smoothOut,
    );
    _opacity = Tween<double>(begin: 0.35, end: 1.0).animate(_curved);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller.isCompleted) return;
    if (AppMotion.shouldReduceMotion(context)) {
      _controller.value = 1.0;
    } else if (!_controller.isAnimating && _controller.value == 0.0) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _curved.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _opacity, child: widget.child);
  }
}
