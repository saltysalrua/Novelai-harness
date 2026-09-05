import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import '../theme/theme_context_extensions.dart';

/// 工具坞按钮视觉呈现风格
enum AppToolChipVariant {
  /// 实心主色填充模式 (选中态为 Primary 蓝底白字，未选为透明底深色字)
  filled,

  /// 浅色主色浸染模式 (选中态为 PrimaryTint 浅蓝底 + Primary 蓝字，未选为透明底深色字)
  tinted,
}

/// 统一工具坞小按钮与操作胶囊 (Tool Dock Chip / Toolbar Item)
///
/// 代码证据出处：
/// - `board_toolbar.dart:104-135` (`BoardToolbarItem`，选中态蓝底白字)
/// - `inpaint_canvas_overlay.dart:794-798` (`_DockChip` 与 `toolChip` 模式切换)
/// - `prompt_edit_actions.dart:45-75` (提示词编辑辅助微型操作钮)
///
/// 核心职责：
/// 统一画板工具栏、修图工具坞及操作面板内单选/动作小按钮的尺寸规范 (图标 14~16px，文字 12px)、
/// 选中态高亮与鼠标悬停反馈，消除业务组件各自复制 `InkWell + BoxDecoration`。
class AppToolChip extends StatefulWidget {
  /// 按钮图标
  final IconData? icon;

  /// 按钮文本标签
  final String label;

  /// 是否处于选中/激活状态
  final bool isSelected;

  /// 点击回调
  final VoidCallback? onTap;

  /// 呈现风格，默认 [AppToolChipVariant.filled]
  final AppToolChipVariant variant;

  /// 图标尺寸，默认 14.0
  final double iconSize;

  /// 文字字号，默认 12.0
  final double fontSize;

  /// 内部内边距，默认 [horizontal: 8, vertical: 6]
  final EdgeInsetsGeometry padding;

  /// 圆角大小，默认 [AppRadius.sm] (4px) 或 6px
  final double radius;

  /// 悬浮提示文案
  final String? tooltip;

  const AppToolChip({
    super.key,
    this.icon,
    required this.label,
    this.isSelected = false,
    this.onTap,
    this.variant = AppToolChipVariant.filled,
    this.iconSize = 14.0,
    this.fontSize = 12.0,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    this.radius = 6.0,
    this.tooltip,
  });

  @override
  State<AppToolChip> createState() => _AppToolChipState();
}

class _AppToolChipState extends State<AppToolChip> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isSelected = widget.isSelected;
    final isEnabled = widget.onTap != null;

    final Color bgColor = switch (widget.variant) {
      AppToolChipVariant.filled =>
        isSelected
            ? colors.primary
            : (_isHovered && isEnabled
                  ? colors.borderSubtle
                  : Colors.transparent),
      AppToolChipVariant.tinted =>
        isSelected
            ? colors.primaryTint
            : (_isHovered && isEnabled
                  ? colors.borderSubtle
                  : Colors.transparent),
    };

    final Color fgColor = switch (widget.variant) {
      AppToolChipVariant.filled =>
        isSelected
            ? Colors.white
            : (isEnabled ? colors.textPrimary : colors.textMuted),
      AppToolChipVariant.tinted =>
        isSelected
            ? colors.primary
            : (isEnabled ? colors.textPrimary : colors.textMuted),
    };

    Widget content = Container(
      padding: widget.padding,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(widget.radius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.icon != null) ...[
            Icon(widget.icon, size: widget.iconSize, color: fgColor),
            const SizedBox(width: 4),
          ],
          Text(
            widget.label,
            style: TextStyle(
              fontSize: widget.fontSize,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              color: fgColor,
            ),
          ),
        ],
      ),
    );

    if (isEnabled) {
      content = MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: content,
        ),
      );
    }

    if (widget.tooltip != null && widget.tooltip!.isNotEmpty) {
      content = Tooltip(
        message: widget.tooltip!,
        waitDuration: const Duration(milliseconds: 500),
        child: content,
      );
    }

    return content;
  }
}
