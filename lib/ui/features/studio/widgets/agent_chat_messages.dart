import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
// markdown 只作为 flutter_markdown_plus 的传递依赖出现，这里只用它的元素类型。
// ignore: depend_on_referenced_packages
import 'package:markdown/markdown.dart' as md;
import '../../../../core/harness/reply_marker.dart';
import '../../../../core/harness/types.dart';
import '../../../core/context_l10n.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../../core/widgets/stable_edge_selection.dart';
import 'agent_chat_blocks.dart';
import 'chat_image_attachment.dart';
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

  const AgentChatMessageItem({
    super.key,
    required this.message,
    this.thinkingExpanded = false,
    this.keepAlive = false,
    this.pairedToolResults = const [],
    this.isMergedToolResult = false,
    this.onRewind,
  });

  @override
  State<AgentChatMessageItem> createState() => _AgentChatMessageItemState();
}

class _AgentChatMessageItemState extends State<AgentChatMessageItem>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => widget.keepAlive;

  @override
  void didUpdateWidget(AgentChatMessageItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.keepAlive != widget.keepAlive) updateKeepAlive();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final message = widget.message;
    switch (message.role) {
      case AgentRole.system:
        return const SizedBox.shrink();
      case AgentRole.user:
        return UserMessageRow(message: message, onRewind: widget.onRewind);
      case AgentRole.tool:
        if (widget.isMergedToolResult) return const SizedBox.shrink();
        return ToolResultBlock(message: message);
      case AgentRole.assistant:
        return AssistantMessageItem(
          message: message,
          thinkingExpanded: widget.thinkingExpanded,
          pairedToolResults: widget.pairedToolResults,
          onRewind: widget.onRewind,
        );
    }
  }
}

/// 悬停高亮消息外框 + 固定高度快捷操作栏共享容器
class _HoverableMessageActionScope extends StatefulWidget {
  final Widget Function(BuildContext context, bool hovered) builder;

  const _HoverableMessageActionScope({required this.builder});

  @override
  State<_HoverableMessageActionScope> createState() =>
      _HoverableMessageActionScopeState();
}

class _HoverableMessageActionScopeState
    extends State<_HoverableMessageActionScope> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        if (!_hovered) setState(() => _hovered = true);
      },
      onExit: (_) {
        if (_hovered) setState(() => _hovered = false);
      },
      child: widget.builder(context, _hovered),
    );
  }
}

/// 带即时复制成功反馈的紧凑图标按钮
class _MessageCopyButton extends StatefulWidget {
  final String text;
  final String copyTooltip;
  final String copiedTooltip;

  const _MessageCopyButton({
    super.key,
    required this.text,
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
    return AppIconButton(
      icon: _copied ? Icons.check_rounded : Icons.content_copy_rounded,
      size: 20,
      iconSize: 12,
      iconColor: _copied ? colors.success : colors.textMuted,
      tooltip: _copied ? widget.copiedTooltip : widget.copyTooltip,
      variant: AppIconButtonVariant.ghost,
      onPressed: _copy,
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
        builder: (context, hovered) => Column(
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
                    SelectableText(
                      message.content,
                      style: TextStyle(
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
              AnimatedOpacity(
                opacity: hovered ? 0.9 : 0.35,
                duration: const Duration(milliseconds: 120),
                child: SizedBox(
                  height: 18,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (message.content.isNotEmpty)
                        _MessageCopyButton(
                          key: ValueKey('user_msg_copy_${message.id}'),
                          text: message.content,
                          copyTooltip: l10n?.chatCopyMessageTooltip ?? '复制内容',
                          copiedTooltip: l10n?.chatCopiedTooltip ?? '已复制',
                        ),
                      if (onRewind != null)
                        AppIconButton(
                          key: ValueKey('user_msg_rewind_${message.id}'),
                          icon: Icons.edit_note_rounded,
                          size: 20,
                          iconSize: 13,
                          iconColor: colors.textMuted,
                          tooltip:
                              l10n?.chatEditAndRewindTooltip ?? '编辑并撤回后续对话',
                          variant: AppIconButtonVariant.ghost,
                          onPressed: () => onRewind!(message.id),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
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

  const AssistantMessageItem({
    super.key,
    required this.message,
    this.thinkingExpanded = false,
    this.pairedToolResults = const [],
    this.onRewind,
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
        builder: (context, hovered) => Column(
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
                  ),
                ),
            if (content.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: AgentMarkdownBody(data: content),
              ),
            if (content.isNotEmpty || onRewind != null) ...[
              const SizedBox(height: 3),
              AnimatedOpacity(
                opacity: hovered ? 0.9 : 0.35,
                duration: const Duration(milliseconds: 120),
                child: SizedBox(
                  height: 18,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (content.isNotEmpty)
                        _MessageCopyButton(
                          key: ValueKey('assistant_msg_copy_${message.id}'),
                          text: content,
                          copyTooltip: l10n?.chatCopyMessageTooltip ?? '复制内容',
                          copiedTooltip: l10n?.chatCopiedTooltip ?? '已复制',
                        ),
                      if (onRewind != null)
                        AppIconButton(
                          key: ValueKey('assistant_msg_rewind_${message.id}'),
                          icon: Icons.history_rounded,
                          size: 20,
                          iconSize: 12,
                          iconColor: colors.textMuted,
                          tooltip: l10n?.chatRewindToHereTooltip ?? '回退到此回复',
                          variant: AppIconButtonVariant.ghost,
                          onPressed: () => onRewind!(message.id),
                        ),
                    ],
                  ),
                ),
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

  const ToolCallBlock({super.key, required this.call, this.result});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final pairedResult = result;
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
              Icon(statusIcon, size: 14, color: statusColor),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  call.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              if (summary.isNotEmpty) ...[
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: colors.textMuted),
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
          final cacheWidth = (panelWidth * dpr).round().clamp(320, 1600);
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

/// 流式输出占位: 角色头 + 实时思考块 + 正文 Markdown + 紧凑进度指示
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
    // 展示层兜底：流式气泡里的标记与残渣不上 UI
    final visibleContent = ReplyMarker.strip(content);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (notice != null && notice!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(notice!, style: TextStyle(color: colors.textMuted)),
            ),
          if (thoughts.isNotEmpty)
            ThinkingBlock(thoughts: thoughts, forceExpanded: thinkingExpanded),
          if (visibleContent.isNotEmpty)
            AgentMarkdownBody(data: visibleContent),
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: SizedBox(
              width: 24,
              child: LinearProgressIndicator(minHeight: 2),
            ),
          ),
        ],
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

  const AgentMarkdownBody({super.key, required this.data});

  @override
  State<AgentMarkdownBody> createState() => _AgentMarkdownBodyState();
}

class _AgentMarkdownBodyState extends State<AgentMarkdownBody> {
  Widget? _rendered;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rendered = null;
  }

  @override
  void didUpdateWidget(AgentMarkdownBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) _rendered = null;
  }

  @override
  Widget build(BuildContext context) => _rendered ??= MarkdownBody(
    data: widget.data,
    selectable: false,
    softLineBreak: true,
    builders: {'pre': _AgentCodeBlockBuilder()},
    styleSheet: buildAgentMarkdownStyleSheet(context),
  );
}
