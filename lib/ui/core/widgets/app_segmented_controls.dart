import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import '../theme/theme_context_extensions.dart';

/// 胶囊按钮项配置
class AppSegmentedItem<T> {
  /// 对应的值
  final T value;

  /// 显示文案
  final String label;

  /// 前缀图标 (可选)
  final IconData? icon;

  /// 提示文字 (可选)
  final String? tooltip;

  const AppSegmentedItem({
    required this.value,
    required this.label,
    this.icon,
    this.tooltip,
  });
}

/// 胶囊选中视觉模式
enum AppPillVariant {
  /// 实心模式 (选中态为品牌纯色背景 + 纯白文字/图标)
  solid,

  /// 柔和淡彩模式 (选中态为 12% 浅蓝底色 + 品牌深蓝文字/图标)
  soft,
}

/// 统一水平胶囊分段单选条 (AppSegmentedPillBar)
///
/// 代码证据出处：
/// - `bill_settings_tab.dart:43-78` (账单周期切换全部/月/周/日胶囊组)
/// - `resolution_pad_picker.dart:178-215` (横屏/竖屏/正方形切换三连键)
///
/// 核心职责：
/// 提供轻量统一的水平药丸分段选择控件，消除手动拼装的 `Row + InkWell + Container + Border`，
/// 统一 Notion 药丸圆角、选中蓝底或柔和蓝底、边框过渡与平滑 Hover 动效。
class AppSegmentedPillBar<T> extends StatelessWidget {
  /// 分段项列表
  final List<AppSegmentedItem<T>> items;

  /// 当前选中的值
  final T? selectedValue;

  /// 选中值改变回调
  final ValueChanged<T>? onValueChanged;

  /// 胶囊视觉模式，默认 [AppPillVariant.solid]
  final AppPillVariant variant;

  /// 是否允许横向滚动 (项较多时适用)，默认 false
  final bool scrollable;

  /// 选项之间的水平间距，默认 6.0
  final double spacing;

  /// 单个胶囊的内边距，默认水平 12，垂直 5
  final EdgeInsetsGeometry itemPadding;

  const AppSegmentedPillBar({
    super.key,
    required this.items,
    required this.selectedValue,
    this.onValueChanged,
    this.variant = AppPillVariant.solid,
    this.scrollable = false,
    this.spacing = 6.0,
    this.itemPadding = const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final children = <Widget>[
      for (int i = 0; i < items.length; i++) ...[
        if (i > 0) SizedBox(width: spacing),
        _buildPillItem(context, colors, items[i]),
      ],
    ];

    if (scrollable) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      );
    }

    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }

  Widget _buildPillItem(
    BuildContext context,
    dynamic colors,
    AppSegmentedItem<T> item,
  ) {
    final isSelected = item.value == selectedValue;

    final (Color bg, Color border, Color fg) = switch (variant) {
      AppPillVariant.solid => (
        isSelected ? colors.primary : colors.cardBackground,
        isSelected ? colors.primary : colors.borderDefault,
        isSelected ? Colors.white : colors.textSecondary,
      ),
      AppPillVariant.soft => (
        isSelected ? colors.primaryTint : colors.cardBackground,
        isSelected
            ? colors.primary.withValues(alpha: 0.35)
            : colors.borderDefault,
        isSelected ? colors.primary : colors.textSecondary,
      ),
    };

    Widget pill = InkWell(
      onTap: () => onValueChanged?.call(item.value),
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: itemPadding,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (item.icon != null) ...[
              Icon(item.icon, size: 13, color: fg),
              const SizedBox(width: 4),
            ],
            Text(
              item.label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );

    if (item.tooltip != null && item.tooltip!.isNotEmpty) {
      pill = Tooltip(message: item.tooltip!, child: pill);
    }

    return pill;
  }
}

/// 统一带标题与副标题的双行模式卡片 (AppOptionCard)
///
/// 代码证据出处：
/// - `inpaint_page.dart:109-141 & 450-493` (_buildModeOption 原图/生成背景/纯透明模式选择卡片)
///
/// 核心职责：
/// 统一标题+副标题双行布局的选项卡片，规范选中微蓝底 (10% tint)、蓝细边框与未选平滑过渡。
class AppOptionCard<T> extends StatelessWidget {
  /// 选项值
  final T value;

  /// 是否选中
  final bool isSelected;

  /// 主标题
  final String title;

  /// 副标题 / 详细说明文字 (可选)
  final String? subtitle;

  /// 选项前缀图标 (可选)
  final IconData? icon;

  /// 点击回调
  final VoidCallback? onTap;

  /// 选中值改变回调 (提供时可传入当前项的 value)
  final ValueChanged<T>? onSelected;

  /// 圆角大小，默认 [AppRadius.md] (8.0)
  final double radius;

  /// 内边距，默认水平 10，垂直 8
  final EdgeInsetsGeometry padding;

  const AppOptionCard({
    super.key,
    required this.value,
    required this.isSelected,
    required this.title,
    this.subtitle,
    this.icon,
    this.onTap,
    this.onSelected,
    this.radius = AppRadius.md,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final bgColor = isSelected ? colors.primaryTint : colors.cardBackground;
    final borderColor = isSelected
        ? colors.primary.withValues(alpha: 0.6)
        : colors.borderDefault;
    final borderWidth = isSelected ? 1.5 : 1.0;
    final titleColor = isSelected ? colors.primary : colors.textPrimary;
    final subtitleColor = isSelected
        ? colors.primary.withValues(alpha: 0.75)
        : colors.textSecondary;

    return InkWell(
      onTap: () {
        onTap?.call();
        onSelected?.call(value);
      },
      borderRadius: BorderRadius.circular(radius),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: padding,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: borderColor, width: borderWidth),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: titleColor),
              const SizedBox(width: 8),
            ],
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                    color: titleColor,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(fontSize: 10.5, color: subtitleColor),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
