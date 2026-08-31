import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Uint8List;
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import '../../../../core/harness/types.dart';
import '../../../core/theme/app_theme.dart';
import 'agent_chat_blocks.dart';
import 'chat_image_attachment.dart';
import 'image_lightbox.dart';

/// 单条对话消息的 Pi 风格平铺渲染入口
/// (system 隐藏 / user 纯文本 / assistant Markdown / tool 结果块)
class AgentChatMessageItem extends StatelessWidget {
  final AgentMessage message;

  /// 思考块全局展开开关 (Ctrl+O)，透传给助手消息的思考块
  final bool thinkingExpanded;

  const AgentChatMessageItem({
    super.key,
    required this.message,
    this.thinkingExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
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
          thinkingExpanded: thinkingExpanded,
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
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.keyboard_arrow_right,
                  size: 16,
                  color: AppTheme.notionBlue,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: SelectableText(
                  message.content,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textPrimary,
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
                      bytes: Uint8List.fromList(base64Decode(img.base64)),
                      size: 72,
                      onTap: () => showImageLightboxBytes(
                        context,
                        Uint8List.fromList(base64Decode(img.base64)),
                      ),
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
              styleSheet: buildAgentMarkdownStyleSheet(),
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
    return CollapsibleTile(
      margin: const EdgeInsets.only(top: 4, bottom: 4),
      header: Row(
        children: [
          const Icon(
            Icons.build_circle_outlined,
            size: 14,
            color: AppTheme.notionBlue,
          ),
          const SizedBox(width: 4),
          Text(
            call.name,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
              color: AppTheme.notionBlue,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              summarizeToolArguments(call.arguments),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
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
            fontSize: 12,
            fontFamily: 'monospace',
            color: AppTheme.textSecondary,
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
    final lineCount = message.content.isEmpty
        ? 0
        : message.content.split('\n').length;
    final firstLine = message.content.isEmpty
        ? '(无输出)'
        : message.content.split('\n').first.trim();
    final accent = message.isError ? AppTheme.error : AppTheme.success;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.only(left: 8),
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: AppTheme.border, width: 2)),
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
                    fontSize: 12.5,
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
                      fontSize: 11.5,
                      fontFamily: 'monospace',
                      color: AppTheme.textMuted,
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
                color: AppTheme.paperWarmth,
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  message.content,
                  style: const TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: AppTheme.textSecondary,
                    height: 1.45,
                  ),
                ),
              ),
            ),
          ),
          // 工具结果附带的图片 (如查看画板图片工具) 不藏在折叠块里，
          // 单独平铺在工具结果下方，收起时也直接可见；点击全屏放大查看。
          // 按面板实际宽度解码 (cacheWidth)，避免 1536px 级全分辨率纹理拖慢滚动
          if (message.imageBase64 != null && message.imageBase64!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 2),
              child: Builder(
                builder: (context) {
                  final bytes = Uint8List.fromList(
                    base64Decode(message.imageBase64!),
                  );
                  final panelWidth = MediaQuery.sizeOf(context).width;
                  final dpr = MediaQuery.devicePixelRatioOf(context);
                  // 对话卡面板宽度为窗口的一小部分，钳到安全上限保留清晰度
                  final cacheWidth = (panelWidth * dpr / 2)
                      .round()
                      .clamp(320, 1600);
                  return GestureDetector(
                    onTap: () => showImageLightboxBytes(context, bytes),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.zoomIn,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(
                          AppTheme.radiusSmall,
                        ),
                        child: Image.memory(
                          bytes,
                          width: double.infinity,
                          fit: BoxFit.contain,
                          cacheWidth: cacheWidth,
                          filterQuality: FilterQuality.medium,
                          gaplessPlayback: true,
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
                        ),
                      ),
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
                color: AppTheme.pureWhite,
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                border: Border.all(color: AppTheme.border),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 11,
                    height: 11,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: AppTheme.textMuted,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      notice!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppTheme.textMuted,
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
            const Row(
              children: [
                SizedBox(
                  width: 11,
                  height: 11,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: AppTheme.textMuted,
                  ),
                ),
                SizedBox(width: 6),
                Text(
                  '正在思考...',
                  style: TextStyle(
                    fontSize: 11.5,
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
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.pureWhite,
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                border: Border.all(color: AppTheme.border),
              ),
              child: Text(
                thoughts,
                maxLines: thinkingExpanded ? null : 6,
                overflow: thinkingExpanded
                    ? TextOverflow.visible
                    : TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontStyle: FontStyle.italic,
                  color: AppTheme.textMuted,
                  height: 1.45,
                ),
              ),
            ),
            const SizedBox(height: 6),
          ],
          MarkdownBody(
            data: content.isEmpty ? '构思中...' : content,
            selectable: true,
            softLineBreak: true,
            styleSheet: buildAgentMarkdownStyleSheet(),
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

/// Agent 对话流统一的 Markdown 渲染样式表
MarkdownStyleSheet buildAgentMarkdownStyleSheet() {
  const baseColor = AppTheme.textPrimary;
  return MarkdownStyleSheet(
    p: const TextStyle(fontSize: 13.5, color: baseColor, height: 1.5),
    h1: const TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w700,
      color: baseColor,
      height: 1.4,
    ),
    h2: const TextStyle(
      fontSize: 15.5,
      fontWeight: FontWeight.w700,
      color: baseColor,
      height: 1.4,
    ),
    h3: const TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: baseColor,
      height: 1.4,
    ),
    h4: const TextStyle(
      fontSize: 13.5,
      fontWeight: FontWeight.w600,
      color: baseColor,
      height: 1.4,
    ),
    h5: const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: baseColor,
      height: 1.4,
    ),
    h6: const TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w600,
      color: baseColor,
      height: 1.4,
    ),
    em: const TextStyle(fontStyle: FontStyle.italic),
    strong: const TextStyle(fontWeight: FontWeight.w700),
    del: const TextStyle(decoration: TextDecoration.lineThrough),
    code: const TextStyle(
      fontSize: 12.5,
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
      fontSize: 13,
      color: AppTheme.textSecondary,
      height: 1.45,
    ),
    blockquoteDecoration: BoxDecoration(
      color: AppTheme.pureWhite,
      border: const Border(
        left: BorderSide(color: AppTheme.notionBlue, width: 3),
      ),
      borderRadius: BorderRadius.circular(2),
    ),
    blockquotePadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    listBullet: const TextStyle(fontSize: 13.5, color: baseColor),
    tableBody: const TextStyle(fontSize: 12.5, color: baseColor),
    tableHead: const TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w600,
      color: baseColor,
    ),
    tableBorder: TableBorder.all(color: AppTheme.border, width: 1),
    tableCellsPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    listIndent: 16,
    pPadding: const EdgeInsets.only(bottom: 6),
    h1Padding: const EdgeInsets.only(top: 8, bottom: 4),
    h2Padding: const EdgeInsets.only(top: 8, bottom: 4),
    h3Padding: const EdgeInsets.only(top: 6, bottom: 2),
    horizontalRuleDecoration: const BoxDecoration(
      border: Border(top: BorderSide(color: AppTheme.border, width: 1)),
    ),
  );
}
