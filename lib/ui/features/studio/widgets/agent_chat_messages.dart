import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import '../../../../core/harness/types.dart';
import '../../../core/context_l10n.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import 'agent_chat_blocks.dart';
import 'chat_image_attachment.dart';
import 'image_lightbox.dart';

/// 单条对话消息的 Pi 风格平铺渲染入口
/// (system 隐藏 / user 纯文本 / assistant Markdown / tool 结果块)
class AgentChatMessageItem extends StatefulWidget {
  final AgentMessage message;

  /// 思考块全局展开开关 (Ctrl+O)，透传给助手消息的思考块
  final bool thinkingExpanded;

  /// 只保活近期消息，避免长会话无限持有 Markdown 和图片子树。
  final bool keepAlive;

  const AgentChatMessageItem({
    super.key,
    required this.message,
    this.thinkingExpanded = false,
    this.keepAlive = false,
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
        return UserMessageRow(message: message);
      case AgentRole.tool:
        return ToolResultBlock(message: message);
      case AgentRole.assistant:
        return AssistantMessageItem(
          message: message,
          thinkingExpanded: widget.thinkingExpanded,
        );
    }
  }
}

/// 用户消息: 平铺无气泡，› 前缀 + 纯文本 (与 Pi TUI 一致) + 图片附件缩略图
class UserMessageRow extends StatelessWidget {
  final AgentMessage message;

  const UserMessageRow({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final images = message.images;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.keyboard_arrow_right,
                  size: 16,
                  color: colors.primary,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: SelectableText(
                  message.content,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: colors.textPrimary,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
          if (images.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final img in images)
                    ChatImageThumbnail(
                      bytes: img.bytes,
                      size: 72,
                      onTap: () => showImageLightboxBytes(context, img.bytes),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 助手消息: 思考块 (可折叠，Ctrl+O 全局展开) + Markdown 正文 + 工具调用块 (可折叠)
class AssistantMessageItem extends StatelessWidget {
  final AgentMessage message;

  /// 思考块全局展开开关 (Ctrl+O)
  final bool thinkingExpanded;

  const AssistantMessageItem({
    super.key,
    required this.message,
    this.thinkingExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (message.thoughts.isNotEmpty)
            ThinkingBlock(
              thoughts: message.thoughts,
              forceExpanded: thinkingExpanded,
            ),
          if (message.content.isNotEmpty) ...[
            if (message.thoughts.isNotEmpty) const SizedBox(height: 4),
            MarkdownBody(
              data: message.content,
              selectable: true,
              softLineBreak: true,
              styleSheet: buildAgentMarkdownStyleSheet(context),
            ),
          ],
          if (message.toolCalls != null)
            for (final call in message.toolCalls!) ToolCallBlock(call: call),
        ],
      ),
    );
  }
}

/// 工具调用块: 名称 + 参数摘要，展开后显示完整参数 JSON
class ToolCallBlock extends StatelessWidget {
  final ToolCall call;

  const ToolCallBlock({super.key, required this.call});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return CollapsibleTile(
      margin: const EdgeInsets.only(top: 4, bottom: 4),
      header: Row(
        children: [
          Icon(Icons.build_circle_outlined, size: 14, color: colors.primary),
          const SizedBox(width: 4),
          Text(
            call.name,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
              color: colors.primary,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              summarizeToolArguments(call.arguments),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: colors.textMuted,
              ),
            ),
          ),
        ],
      ),
      body: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: colors.canvasBackground,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: SelectableText(
          const JsonEncoder.withIndent('  ').convert(call.arguments),
          style: TextStyle(
            fontSize: 12,
            fontFamily: 'monospace',
            color: colors.textSecondary,
            height: 1.45,
          ),
        ),
      ),
    );
  }
}

/// 工具结果块: 状态图标 + 工具名 + 行数摘要，展开后显示完整输出
class ToolResultBlock extends StatelessWidget {
  final AgentMessage message;

  const ToolResultBlock({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final lineCount = message.content.isEmpty
        ? 0
        : message.content.split('\n').length;
    final firstLine = message.content.isEmpty
        ? context.l10n.chatToolNoOutput
        : message.content.split('\n').first.trim();
    final accent = message.isError ? colors.error : colors.success;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: colors.borderDefault, width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CollapsibleTile(
            margin: EdgeInsets.zero,
            header: Row(
              children: [
                Icon(
                  message.isError
                      ? Icons.error_outline
                      : Icons.check_circle_outline,
                  size: 14,
                  color: accent,
                ),
                const SizedBox(width: 4),
                Text(
                  message.toolName ?? 'tool',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                    color: accent,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    context.l10n.chatToolResultSummary(lineCount, firstLine),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: colors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
            body: Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 320),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colors.canvasBackground,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  message.content,
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: colors.textSecondary,
                    height: 1.45,
                  ),
                ),
              ),
            ),
          ),
          // 工具结果附带的图片 (如查看画板图片工具) 不藏在折叠块里，
          // 单独平铺在工具结果下方，收起时也直接可见；点击全屏放大查看。
          // 按面板实际宽度解码 (cacheWidth)，避免 1536px 级全分辨率纹理拖慢滚动。
          // 图片异步解码完成前没有内在尺寸，先用文件头同步读出的宽高以
          // AspectRatio 预留布局高度 (底色占位)，滚动历史时高度不再突变跳动。
          if (message.imageBase64 != null && message.imageBase64!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 2),
              child: Builder(
                builder: (context) {
                  final bytes = message.imageBytes!;
                  final panelWidth = MediaQuery.sizeOf(context).width;
                  final dpr = MediaQuery.devicePixelRatioOf(context);
                  // 对话卡面板宽度为窗口的一小部分，钳到安全上限保留清晰度
                  final cacheWidth = (panelWidth * dpr / 2).round().clamp(
                    320,
                    1600,
                  );
                  final image = GestureDetector(
                    onTap: () => showImageLightboxBytes(context, bytes),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.zoomIn,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
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
                    // 文件头解析失败 (罕见)：回退到宽度撑满、解码后才定高的旧行为
                    return SizedBox(width: double.infinity, child: image);
                  }
                  return ColoredBox(
                    // 解码完成前的占位底色，避免预留区白闪一帧
                    color: colors.canvasBackground,
                    child: AspectRatio(
                      aspectRatio: probed.width / probed.height,
                      child: image,
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// 流式输出占位: 实时思考块 + 正文 Markdown
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
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (notice != null && notice!.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: colors.cardBackground,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: colors.borderDefault),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 11,
                    height: 11,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: colors.textMuted,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      notice!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textMuted,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
          ],
          if (thoughts.isNotEmpty) ...[
            Row(
              children: [
                SizedBox(
                  width: 11,
                  height: 11,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: colors.textMuted,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  context.l10n.chatThinkingProgress,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontStyle: FontStyle.italic,
                    color: colors.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colors.cardBackground,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: colors.borderDefault),
              ),
              child: Text(
                thoughts,
                maxLines: thinkingExpanded ? null : 6,
                overflow: thinkingExpanded
                    ? TextOverflow.visible
                    : TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: colors.textMuted,
                  height: 1.45,
                ),
              ),
            ),
            const SizedBox(height: 6),
          ],
          MarkdownBody(
            data: content.isEmpty ? context.l10n.chatConceiving : content,
            selectable: true,
            softLineBreak: true,
            styleSheet: buildAgentMarkdownStyleSheet(context),
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
