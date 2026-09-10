import 'package:flutter/material.dart';
import '../../../../core/harness/reply_marker.dart';
import '../../../core/context_l10n.dart';
import '../../../core/theme/theme_context_extensions.dart';

/// 通用折叠块: 头部行 + 可展开主体 (Pi 风格，默认折叠)
class CollapsibleTile extends StatefulWidget {
  final Widget header;
  final Widget? body;
  final WidgetBuilder? bodyBuilder;
  final EdgeInsetsGeometry margin;

  /// 外部受控展开状态 (为 null 时使用内部自持状态)
  final bool? isExpanded;

  /// 外部展开切换回调 (为 null 时点击切换内部状态)
  final VoidCallback? onToggle;

  const CollapsibleTile({
    super.key,
    required this.header,
    this.body,
    this.bodyBuilder,
    this.margin = const EdgeInsets.only(bottom: 4),
    this.isExpanded,
    this.onToggle,
  });

  @override
  State<CollapsibleTile> createState() => _CollapsibleTileState();
}

class _CollapsibleTileState extends State<CollapsibleTile> {
  bool _expanded = false;

  bool get _effectiveExpanded => widget.isExpanded ?? _expanded;

  void _handleToggle() {
    if (widget.onToggle != null) {
      widget.onToggle!();
    } else {
      setState(() => _expanded = !_expanded);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasBody = widget.body != null || widget.bodyBuilder != null;
    final expanded = _effectiveExpanded;
    return Container(
      margin: widget.margin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: hasBody ? _handleToggle : null,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  Expanded(child: widget.header),
                  if (hasBody)
                    AnimatedRotation(
                      turns: expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: Icon(
                        Icons.expand_more,
                        size: 14,
                        color: colors.textMuted,
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (hasBody && expanded)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: widget.bodyBuilder?.call(context) ?? widget.body,
            ),
        ],
      ),
    );
  }
}

/// 思考过程块: 暗色斜体，默认折叠只显示单行预览；点击或 Ctrl+O 全局展开
///
/// [forceExpanded] 为 ViewModel 的 Ctrl+O 全局开关，开启时叠加本地展开状态
/// 直接展开全文，关闭后恢复各自的折叠状态。
class ThinkingBlock extends StatefulWidget {
  final String thoughts;
  final bool forceExpanded;

  const ThinkingBlock({
    super.key,
    required this.thoughts,
    this.forceExpanded = false,
  });

  @override
  State<ThinkingBlock> createState() => _ThinkingBlockState();
}

class _ThinkingBlockState extends State<ThinkingBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final expanded = _expanded || widget.forceExpanded;
    // 展示层兜底：模型在思考里回显的 [回复 #N] 标记不进 UI
    final thoughts = ReplyMarker.strip(widget.thoughts);
    final preview = thoughts
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');

    return CollapsibleTile(
      isExpanded: expanded,
      onToggle: () => setState(() => _expanded = !_expanded),
      header: Row(
        children: [
          Icon(Icons.psychology_outlined, size: 14, color: colors.textMuted),
          const SizedBox(width: 4),
          Text(
            context.l10n.chatThinkingProcess,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontStyle: FontStyle.italic,
              color: colors.textMuted,
            ),
          ),
          if (preview.isNotEmpty) ...[
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                preview,
                maxLines: 1,
                overflow: expanded ? null : TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: colors.textMuted,
                ),
              ),
            ),
          ],
        ],
      ),
      bodyBuilder: (context) => SizedBox(
        width: double.infinity,
        child: SelectableText(
          thoughts,
          style: TextStyle(
            fontSize: 12,
            fontStyle: FontStyle.italic,
            color: colors.textMuted,
            height: 1.45,
          ),
        ),
      ),
    );
  }
}

/// 只扫描到第一条有效行，流式更新时不拆分整段思考文本。
String firstNonEmptyLine(String text) {
  var start = 0;
  while (start < text.length) {
    final end = text.indexOf(String.fromCharCode(10), start);
    final line = text.substring(start, end < 0 ? text.length : end).trim();
    if (line.isNotEmpty) return line;
    if (end < 0) break;
    start = end + 1;
  }
  return '';
}

/// 无业务状态的时间线轨道；线条使用 Stack 定位，不额外执行固有高度测量。
/// 相邻节点不留外边距，因此跨消息、跨工具结果的轨道自然连通。
class AgentTimelineStep extends StatelessWidget {
  final Widget child;
  final Color? accent;

  const AgentTimelineStep({super.key, required this.child, this.accent});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Stack(
      children: [
        Positioned(
          left: 7,
          top: 0,
          bottom: 0,
          child: SizedBox(
            width: 1,
            child: ColoredBox(color: colors.borderDefault),
          ),
        ),
        Positioned(
          left: 4,
          top: 13,
          child: Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: accent ?? colors.textMuted,
              shape: BoxShape.circle,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 24, bottom: 8),
          child: child,
        ),
      ],
    );
  }
}
