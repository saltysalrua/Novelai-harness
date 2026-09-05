import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import '../theme/theme_context_extensions.dart';

/// 统一侧栏与导航列表项 (AppNavTile)
///
/// 代码证据出处：
/// - `prompt_library_view.dart:554-600` (词库左侧分类导航条目)
/// - `settings_dialog.dart:180-230` (_buildSidebarItem 设置窗口左侧分类导航)
/// - `agent_session_list_view.dart:200-260` (智能体侧栏历史会话列表项)
///
/// 核心职责：
/// 统一桌面端侧边栏、模态导航及抽屉列表项，
/// 支持前缀图标、标题、副标题、数量徽标 (Badge) 与激活指示态；
/// Hover 反馈为瞬时无动画变色（避免鼠标快速扫过时连环闪烁），选中态切换同样即时。
class AppNavTile extends StatefulWidget {
  /// 导航条目标题
  final String title;

  /// 前缀小图标 (可选)
  final IconData? icon;

  /// 副标题辅助文案 (可选)
  final String? subtitle;

  /// 数量徽标文本 (如 '12' 或 '全部'，可选)
  final String? badgeText;

  /// 数量数值 (当提供了 [badgeCount] 且 [badgeText] 为空时自动格式化展示)
  final int? badgeCount;

  /// 徽标自定义颜色
  final Color? badgeColor;

  /// 是否处于当前激活/选中状态，默认 false
  final bool isSelected;

  /// 点击回调
  final VoidCallback? onTap;

  /// 激活态强调色 (覆盖默认主题 [AppColorsExtension.primary])
  final Color? activeColor;

  /// 激活态背景色 (覆盖默认主题 [AppColorsExtension.primaryTint])
  final Color? activeBackgroundColor;

  /// 激活态边框颜色
  final Color? activeBorderColor;

  /// 尾部附加小组件 (如快捷操作、箭头等，可选)
  final Widget? trailing;

  /// 圆角大小，默认 [AppRadius.md] (8.0)
  final double radius;

  /// 内边距，默认水平 10，垂直 8
  final EdgeInsetsGeometry padding;

  const AppNavTile({
    super.key,
    required this.title,
    this.icon,
    this.subtitle,
    this.badgeText,
    this.badgeCount,
    this.badgeColor,
    this.isSelected = false,
    this.onTap,
    this.activeColor,
    this.activeBackgroundColor,
    this.activeBorderColor,
    this.trailing,
    this.radius = AppRadius.md,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
  });

  @override
  State<AppNavTile> createState() => _AppNavTileState();
}

class _AppNavTileState extends State<AppNavTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final resolvedActiveColor = widget.activeColor ?? colors.primary;
    final resolvedActiveBg = widget.activeBackgroundColor ?? colors.primaryTint;
    final resolvedActiveBorder =
        widget.activeBorderColor ?? colors.primary.withValues(alpha: 0.35);

    final effectiveBg = widget.isSelected
        ? resolvedActiveBg
        : (_isHovered
              ? colors.mutedBackground.withValues(alpha: 0.6)
              : Colors.transparent);

    final effectiveBorderColor = widget.isSelected
        ? resolvedActiveBorder
        : Colors.transparent;
    final effectiveFg = widget.isSelected
        ? resolvedActiveColor
        : colors.textPrimary;
    final iconFg = widget.isSelected
        ? resolvedActiveColor
        : colors.textSecondary;

    final displayBadge =
        widget.badgeText ??
        (widget.badgeCount != null ? '${widget.badgeCount}' : null);

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: Colors.transparent,
        child: MouseRegion(
          cursor: widget.onTap != null
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(widget.radius),
            hoverColor: Colors.transparent,
            splashColor: resolvedActiveBg.withValues(alpha: 0.3),
            child: Container(
              padding: widget.padding,
              decoration: BoxDecoration(
                color: effectiveBg,
                borderRadius: BorderRadius.circular(widget.radius),
                border: Border.all(color: effectiveBorderColor, width: 1.0),
              ),
              child: Row(
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, size: 16, color: iconFg),
                    // 图标间距对齐旧设置侧栏的 10px 节奏
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: TextStyle(
                            fontSize: 13,
                            // 未选中态 w500 对齐替换前旧侧栏字重，避免 MiSans w400 过细显糊
                            fontWeight: widget.isSelected
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: effectiveFg,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (widget.subtitle != null &&
                            widget.subtitle!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            widget.subtitle!,
                            style: TextStyle(
                              fontSize: 11,
                              color: colors.textMuted,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (displayBadge != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: widget.isSelected
                            ? (widget.badgeColor ?? resolvedActiveColor)
                                  .withValues(alpha: 0.15)
                            : colors.mutedBackground,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text(
                        displayBadge,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: widget.isSelected
                              ? (widget.badgeColor ?? resolvedActiveColor)
                              : colors.textMuted,
                        ),
                      ),
                    ),
                  ],
                  if (widget.trailing != null) ...[
                    const SizedBox(width: 6),
                    widget.trailing!,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
