import 'package:flutter/material.dart';
import '../../../../core/harness/reply_marker.dart';
import '../../../core/context_l10n.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';

/// 通用折叠块: 头部行 + 可展开主体 (现代卡片/胶囊风格，默认折叠)
class CollapsibleTile extends StatefulWidget {
  final Widget header;
  final Widget? body;
  final WidgetBuilder? bodyBuilder;
  final EdgeInsetsGeometry margin;

  /// 外部受控展开状态 (为 null 时使用内部自持状态)
  final bool? isExpanded;

  /// 外部展开切换回调 (为 null 时点击切换内部状态)
  final VoidCallback? onToggle;

  /// 可选背景色与边框色 (未指定时保持透明无框)
  final Color? backgroundColor;
  final Color? borderColor;
  final double borderRadius;
  final EdgeInsetsGeometry headerPadding;
  final EdgeInsetsGeometry bodyPadding;

  const CollapsibleTile({
    super.key,
    required this.header,
    this.body,
    this.bodyBuilder,
    this.margin = const EdgeInsets.only(bottom: 4),
    this.isExpanded,
    this.onToggle,
    this.backgroundColor,
    this.borderColor,
    this.borderRadius = AppRadius.md,
    this.headerPadding = const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    this.bodyPadding = const EdgeInsets.fromLTRB(10, 0, 10, 10),
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
    final hasDecoration =
        widget.backgroundColor != null || widget.borderColor != null;

    return Container(
      margin: widget.margin,
      decoration: hasDecoration
          ? BoxDecoration(
              color: widget.backgroundColor,
              borderRadius: BorderRadius.circular(widget.borderRadius),
              border: widget.borderColor != null
                  ? Border.all(color: widget.borderColor!)
                  : null,
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: hasBody ? _handleToggle : null,
            borderRadius: BorderRadius.circular(widget.borderRadius),
            child: Padding(
              padding: widget.headerPadding,
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
              padding: widget.bodyPadding,
              child: widget.bodyBuilder?.call(context) ?? widget.body,
            ),
        ],
      ),
    );
  }
}

/// 思考过程块: 柔和胶囊卡片，默认折叠只显示单行预览；点击或 Ctrl+O 全局展开
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
    final preview = firstNonEmptyLine(thoughts);
    final headerText = preview.isNotEmpty
        ? preview
        : (context.maybeL10n?.chatThinkingProcess ?? '...');

    return CollapsibleTile(
      margin: const EdgeInsets.only(bottom: 4),
      backgroundColor: expanded
          ? colors.mutedBackground.withValues(alpha: 0.35)
          : Colors.transparent,
      borderColor: expanded ? colors.borderSubtle : null,
      borderRadius: AppRadius.md,
      headerPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      bodyPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      isExpanded: expanded,
      onToggle: () => setState(() => _expanded = !_expanded),
      header: Row(
        children: [
          Icon(Icons.psychology_outlined, size: 13, color: colors.textMuted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              headerText,
              maxLines: 1,
              overflow: expanded ? null : TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: colors.textMuted),
            ),
          ),
        ],
      ),
      bodyBuilder: (context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.only(left: 10),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: colors.borderDefault, width: 2),
          ),
        ),
        child: SelectableText(
          thoughts,
          style: TextStyle(
            fontSize: 12,
            color: colors.textSecondary,
            height: 1.5,
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

/// 步骤间距容器 (保留组件名以兼容既有调用方)
class AgentTimelineStep extends StatelessWidget {
  final Widget child;
  final Color? accent;

  const AgentTimelineStep({super.key, required this.child, this.accent});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: child,
    );
  }
}
