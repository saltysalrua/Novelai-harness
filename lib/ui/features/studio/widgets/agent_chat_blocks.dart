import 'package:flutter/material.dart';
import '../../../../core/harness/reply_marker.dart';
import '../../../core/context_l10n.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_transitions.dart';

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

  /// 是否对状态变更执行平滑折叠动画；批量快捷键切换时可置 false 即时对齐锚点
  final bool animate;

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
    this.animate = true,
    this.backgroundColor,
    this.borderColor,
    this.borderRadius = AppRadius.md,
    this.headerPadding = const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    this.bodyPadding = const EdgeInsets.fromLTRB(10, 0, 10, 10),
  });

  @override
  State<CollapsibleTile> createState() => _CollapsibleTileState();
}

class _CollapsibleTileState extends State<CollapsibleTile>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _controller;
  late final Animation<double> _curved;
  bool _reduceMotion = false;

  bool get _effectiveExpanded => widget.isExpanded ?? _expanded;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppMotionDurations.fast,
      value: _effectiveExpanded ? 1.0 : 0.0,
    );
    _curved = _controller.drive(CurveTween(curve: AppMotionCurves.smoothOut));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = AppMotion.shouldReduceMotion(context);
    if (_reduceMotion) {
      _controller.value = _effectiveExpanded ? 1.0 : 0.0;
    }
  }

  @override
  void didUpdateWidget(covariant CollapsibleTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldExpanded = oldWidget.isExpanded ?? _expanded;
    final nextExpanded = _effectiveExpanded;
    if (oldExpanded != nextExpanded) {
      _syncController(nextExpanded);
    }
  }

  void _syncController(bool expanded) {
    if (_reduceMotion || !widget.animate) {
      _controller.value = expanded ? 1.0 : 0.0;
    } else if (expanded) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleToggle() {
    if (widget.onToggle != null) {
      widget.onToggle!();
    } else {
      setState(() {
        _expanded = !_expanded;
        _syncController(_expanded);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasBody = widget.body != null || widget.bodyBuilder != null;
    final expanded = _effectiveExpanded;
    final hasDecoration =
        widget.backgroundColor != null || widget.borderColor != null;

    final column = Column(
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
                  AnimatedBuilder(
                    animation: _curved,
                    builder: (context, child) {
                      final scaleY = 1.0 - 2.0 * _curved.value;
                      return Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.diagonal3Values(1.0, scaleY, 1.0),
                        child: child,
                      );
                    },
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
        if (hasBody)
          SelectionContainer.disabled(
            child: AnimatedBuilder(
              animation: _curved,
              builder: (context, _) {
                final t = _curved.value.clamp(0.0, 1.0);
                if (t <= 0.0 && !expanded) {
                  return const SizedBox.shrink();
                }
                final bodyContent = Padding(
                  padding: widget.bodyPadding,
                  child: widget.bodyBuilder?.call(context) ?? widget.body,
                );
                if (t >= 1.0 && expanded) {
                  return bodyContent;
                }
                return ClipRect(
                  child: ExcludeFocus(
                    excluding: !expanded,
                    child: Align(
                      alignment: Alignment.topLeft,
                      heightFactor: t,
                      child: Opacity(opacity: t, child: bodyContent),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );

    if (!hasDecoration) {
      return Padding(padding: widget.margin, child: column);
    }

    final bgColor = widget.backgroundColor;
    return AnimatedContainer(
      duration: AppMotion.resolveDuration(context, AppMotionDurations.fast),
      curve: AppMotionCurves.smoothOut,
      margin: widget.margin,
      decoration: BoxDecoration(
        color: (bgColor != null && bgColor.a == 0) ? null : bgColor,
        borderRadius: BorderRadius.circular(widget.borderRadius),
        border: widget.borderColor != null
            ? Border.all(color: widget.borderColor!)
            : null,
      ),
      child: column,
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
  final bool isThinking;

  const ThinkingBlock({
    super.key,
    required this.thoughts,
    this.forceExpanded = false,
    this.isThinking = false,
  });

  @override
  State<ThinkingBlock> createState() => _ThinkingBlockState();
}

class _ThinkingBlockState extends State<ThinkingBlock> {
  bool _expanded = false;
  bool _animateNext = true;

  @override
  void didUpdateWidget(covariant ThinkingBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Ctrl+O 全局切换会同步触发视口锚点补偿，需即时生效避免高度渐缩引起漂移
    if (oldWidget.forceExpanded != widget.forceExpanded) {
      _animateNext = false;
    }
  }

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
    final shimmerActive = widget.isThinking && !expanded;

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
      animate: _animateNext,
      onToggle: () => setState(() {
        _animateNext = true;
        _expanded = !_expanded;
      }),
      header: Row(
        children: [
          Icon(Icons.psychology_outlined, size: 13, color: colors.textMuted),
          const SizedBox(width: 6),
          Expanded(
            child: SelectionContainer.disabled(
              child: shimmerActive
                  ? AppShimmerText(
                      text: headerText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      baseColor: colors.textMuted,
                      highlightColor: colors.textPrimary,
                      style: const TextStyle(fontSize: 12),
                    )
                  : Text(
                      headerText,
                      maxLines: 1,
                      overflow: expanded ? null : TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: colors.textMuted),
                    ),
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
