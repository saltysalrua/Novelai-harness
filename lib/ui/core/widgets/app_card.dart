import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import '../theme/theme_context_extensions.dart';

/// 统一标准卡片外壳与选区包装器 (Standard Card Shell)
///
/// 代码证据出处：
/// - `prompt_editor_card.dart:106-115` (主提示词输入卡片外框)
/// - `fixed_affixes_panel.dart:28-35` (前置/后置固定词缀卡片)
/// - `prompt_combo_card.dart:124-138` (词组合卡片外框，带选中高亮)
/// - `character_card_item.dart:158-168` (多角色卡片外框)
/// - `model_card.dart:68-76` (LLM 供应商模型卡)
/// - `skill_card.dart:90-100` 与 `tool_card.dart:95-105` (技能/工具卡)
/// - `inline_agent_question_card.dart:82-95` (智能体提问卡片)
///
/// 核心职责：
/// 统一卡片容器的白底/深底背景、统一 12px 大圆角、细边框与选中态高亮边框，
/// 支持可选悬浮阴影与点击/右击手势，消灭全工程手写 `BoxDecoration`。
class AppCard extends StatefulWidget {
  /// 卡片内主体内容
  final Widget child;

  /// 是否处于选中高亮态
  final bool isSelected;

  /// 点击回调；提供时具有鼠标手势与 Hover 悬停边框高亮
  final VoidCallback? onTap;

  /// 右键/次级点击回调 (常用在画板卡片呼出上下文菜单)
  final GestureTapDownCallback? onSecondaryTapDown;

  /// 右键/次级点击回调
  final GestureTapCallback? onSecondaryTap;

  /// 卡片内边距，默认为空 (由子组件或业务决定)
  final EdgeInsetsGeometry? padding;

  /// 卡片外边距，默认为空
  final EdgeInsetsGeometry? margin;

  /// 圆角大小，默认 [AppRadius.lg] (12px)
  final double radius;

  /// 自定义背景色；未指定时默认使用 [AppColorsExtension.cardBackground]
  final Color? backgroundColor;

  /// 选中时的自定义背景色
  final Color? selectedBackgroundColor;

  /// 自定义边框颜色；未指定时默认使用 [AppColorsExtension.borderDefault]
  final Color? borderColor;

  /// 选中时的边框颜色；未指定时默认使用 [AppColorsExtension.primary]
  final Color? selectedBorderColor;

  /// 默认未选状态的边框粗细，默认 1.0
  final double borderWidth;

  /// 选中状态的边框粗细，默认 1.5
  final double selectedBorderWidth;

  /// 是否启用微投影质感 (如悬浮浮起态)，默认 false
  final bool elevated;

  /// 剪裁模式，默认 [Clip.antiAlias] 保证子组件圆角不溢出
  final Clip clipBehavior;

  const AppCard({
    super.key,
    required this.child,
    this.isSelected = false,
    this.onTap,
    this.onSecondaryTapDown,
    this.onSecondaryTap,
    this.padding,
    this.margin,
    this.radius = AppRadius.lg,
    this.backgroundColor,
    this.selectedBackgroundColor,
    this.borderColor,
    this.selectedBorderColor,
    this.borderWidth = 1.0,
    this.selectedBorderWidth = 1.5,
    this.elevated = false,
    this.clipBehavior = Clip.antiAlias,
  });

  @override
  State<AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<AppCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isInteractive = widget.onTap != null || widget.onSecondaryTap != null || widget.onSecondaryTapDown != null;

    final bgColor = widget.isSelected
        ? (widget.selectedBackgroundColor ?? colors.cardBackground)
        : (widget.backgroundColor ?? colors.cardBackground);

    final resolvedBorderColor = widget.isSelected
        ? (widget.selectedBorderColor ?? colors.primary)
        : (_isHovered && isInteractive
            ? colors.borderHover
            : (widget.borderColor ?? colors.borderDefault));

    final resolvedBorderWidth = widget.isSelected ? widget.selectedBorderWidth : widget.borderWidth;

    List<BoxShadow>? shadows;
    if (widget.isSelected) {
      shadows = AppShadows.subtle(colors.primary, brightness: context.themeBrightness);
    } else if (widget.elevated || (_isHovered && isInteractive)) {
      shadows = context.shadowSubtle;
    }

    Widget content = Container(
      padding: widget.padding,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(widget.radius),
        border: Border.all(
          color: resolvedBorderColor,
          width: resolvedBorderWidth,
        ),
        boxShadow: shadows,
      ),
      clipBehavior: widget.clipBehavior,
      child: widget.child,
    );

    if (isInteractive) {
      content = MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          onSecondaryTapDown: widget.onSecondaryTapDown,
          onSecondaryTap: widget.onSecondaryTap,
          behavior: HitTestBehavior.opaque,
          child: content,
        ),
      );
    }

    if (widget.margin != null) {
      content = Padding(padding: widget.margin!, child: content);
    }

    return content;
  }
}
