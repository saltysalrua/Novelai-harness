import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import '../theme/theme_context_extensions.dart';

/// 统一手风琴式可折叠面板 (Collapsible Section / Accordion)
///
/// 代码证据出处：
/// - `parameters_page.dart:705-784` (高级生成参数折叠，原采用 ExpansionTile 并临时 hack 清空分割线)
/// - `agent_chat_blocks.dart:42-88` (`_CollapsibleBlock`，智能体思考与工具调用结果块)
/// - `fixed_affixes_panel.dart:38-60` (前置/后置词缀折叠开关)
/// - `metadata_reader_dialog.dart:211-230` (原始 JSON 元数据折叠查看)
///
/// 核心职责：
/// 统一折叠展开动画曲线 (150ms)、旋转箭头微动效、标题栏对齐及边框规范，
/// 支持受控与非受控双模式，替代原生粗糙的 `ExpansionTile`。
class AppCollapsibleSection extends StatefulWidget {
  /// 标题文字 (若提供了 [headerWidget] 则以自定义组件优先)
  final String? title;

  /// 自定义头部组件
  final Widget? headerWidget;

  /// 副标题文字 (可选)
  final String? subtitle;

  /// 头部右侧操作控件 (在展开箭头左侧展示)
  final Widget? trailing;

  /// 折叠面板主体展开内容
  final Widget child;

  /// 外部受控的展开状态；若为 null 则在内部自主维护
  final bool? isExpanded;

  /// 默认初始展开状态 (非受控模式下生效)，默认 false
  final bool initiallyExpanded;

  /// 展开状态变更通知回调
  final ValueChanged<bool>? onExpansionChanged;

  /// 是否以卡片容器形态呈现 (带白底/深底背景与细边框)，默认为 true
  final bool isCard;

  /// 头部内边距，默认 [horizontal: 12, vertical: 8]
  final EdgeInsetsGeometry headerPadding;

  /// 内容体内部边距，默认 [horizontal: 12, vertical: 8]
  final EdgeInsetsGeometry contentPadding;

  /// 外边距，默认为空
  final EdgeInsetsGeometry? margin;

  /// 圆角大小，默认 [AppRadius.md] (8px)
  final double radius;

  const AppCollapsibleSection({
    super.key,
    this.title,
    this.headerWidget,
    this.subtitle,
    this.trailing,
    required this.child,
    this.isExpanded,
    this.initiallyExpanded = false,
    this.onExpansionChanged,
    this.isCard = true,
    this.headerPadding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    this.contentPadding = const EdgeInsets.fromLTRB(12, 0, 12, 10),
    this.margin,
    this.radius = AppRadius.md,
  }) : assert(title != null || headerWidget != null, '必须提供 title 或 headerWidget 其一');

  @override
  State<AppCollapsibleSection> createState() => _AppCollapsibleSectionState();
}

class _AppCollapsibleSectionState extends State<AppCollapsibleSection>
    with SingleTickerProviderStateMixin {
  late bool _expanded;
  late final AnimationController _controller;
  late final Animation<double> _iconTurns;
  late final Animation<double> _heightFactor;

  bool get _isEffectiveExpanded => widget.isExpanded ?? _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.isExpanded ?? widget.initiallyExpanded;
    _controller = AnimationController(
      duration: const Duration(milliseconds: 180),
      vsync: this,
    );
    _iconTurns = _controller.drive(
      Tween<double>(begin: 0.0, end: 0.5).chain(
        CurveTween(curve: Curves.easeInOut),
      ),
    );
    _heightFactor = _controller.drive(
      CurveTween(curve: Curves.easeInOut),
    );

    if (_isEffectiveExpanded) {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(covariant AppCollapsibleSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isExpanded != null && widget.isExpanded != oldWidget.isExpanded) {
      if (widget.isExpanded!) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleToggle() {
    final nextState = !_isEffectiveExpanded;
    if (widget.isExpanded == null) {
      setState(() {
        _expanded = nextState;
        if (_expanded) {
          _controller.forward();
        } else {
          _controller.reverse();
        }
      });
    }
    widget.onExpansionChanged?.call(nextState);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    Widget header = widget.headerWidget ??
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.title != null)
              Text(
                widget.title!,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
            if (widget.subtitle != null && widget.subtitle!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                widget.subtitle!,
                style: TextStyle(
                  fontSize: 11.5,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ],
        );

    Widget headerRow = InkWell(
      onTap: _handleToggle,
      borderRadius: BorderRadius.circular(widget.radius),
      child: Padding(
        padding: widget.headerPadding,
        child: Row(
          children: [
            Expanded(child: header),
            if (widget.trailing != null) ...[
              const SizedBox(width: AppSpacing.sm),
              widget.trailing!,
            ],
            const SizedBox(width: AppSpacing.xs),
            RotationTransition(
              turns: _iconTurns,
              child: Icon(
                Icons.expand_more_rounded,
                size: 18,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );

    Widget body = ClipRect(
      child: AnimatedBuilder(
        animation: _controller.view,
        builder: (context, child) {
          return Align(
            alignment: Alignment.topLeft,
            heightFactor: _heightFactor.value,
            child: child,
          );
        },
        child: Padding(
          padding: widget.contentPadding,
          child: widget.child,
        ),
      ),
    );

    Widget panel = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        headerRow,
        body,
      ],
    );

    if (widget.isCard) {
      panel = Container(
        decoration: BoxDecoration(
          color: colors.cardBackground,
          borderRadius: BorderRadius.circular(widget.radius),
          border: Border.all(color: colors.borderDefault),
        ),
        clipBehavior: Clip.antiAlias,
        child: panel,
      );
    }

    if (widget.margin != null) {
      panel = Padding(padding: widget.margin!, child: panel);
    }

    return panel;
  }
}
