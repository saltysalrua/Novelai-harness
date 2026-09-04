import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import '../theme/theme_context_extensions.dart';

/// 下拉组件展示形态变体
enum AppDropdownVariant {
  /// 标准表单形态 (高 38px，带轻边框，圆角 8px，适合模型/采样器等主要表单)
  standard,

  /// 药丸胶囊形态 (高 28px，圆角 9999px，适合 Quality / UC 等行内紧凑切换)
  pill,

  /// 紧凑形态 (高 32px，圆角 8px，适合标题栏/工具条内嵌)
  compact,
}

/// 下拉选项数据契约
class AppDropdownItem<T> {
  final T value;
  final String label;
  final IconData? icon;
  final Widget? trailing;
  final String? tooltip;

  const AppDropdownItem({
    required this.value,
    required this.label,
    this.icon,
    this.trailing,
    this.tooltip,
  });
}

/// 统一现代化下拉选择器组件
///
/// 完全基于 [AppColorsExtension] 与 [AppTokens]，支持深浅主题平滑自适应，
/// 统一收拢标准表单下拉、胶囊药丸下拉与紧凑小下拉三种场景。
///
/// 内置两项防御性保障：
/// 1. **防悬挂兜底**：当 [value] 不在 [items] 中时（动态列表被外部刷新/删除），
///    自动在菜单头部追加一个「未识别」占位项，避免 DropdownButton 断言崩溃；
/// 2. **菜单宽度保护**：胶囊变体默认展开宽度 220，不再被窄按钮宽度截断。
class AppDropdown<T> extends StatelessWidget {
  final T value;
  final List<AppDropdownItem<T>> items;
  final ValueChanged<T> onChanged;
  final AppDropdownVariant variant;
  final String? hintText;
  final double? width;
  final bool isExpanded;

  /// 展开菜单的宽度上限；胶囊变体默认 220 防截断，其余变体默认跟随按钮宽
  final double? menuWidth;

  /// [value] 不在 [items] 中时，占位项展示的文案
  final String danglingLabel;

  const AppDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.variant = AppDropdownVariant.standard,
    this.hintText,
    this.width,
    this.isExpanded = true,
    this.menuWidth,
    this.danglingLabel = '未识别',
  });

  /// 便捷工厂：从普通对象列表与标签映射构造
  factory AppDropdown.simple({
    Key? key,
    required T value,
    required List<T> items,
    required String Function(T item) labelOf,
    required ValueChanged<T> onChanged,
    IconData Function(T item)? iconOf,
    Widget Function(T item, bool isSelected)? trailingOf,
    AppDropdownVariant variant = AppDropdownVariant.standard,
    double? width,
    bool isExpanded = true,
    double? menuWidth,
  }) {
    return AppDropdown<T>(
      key: key,
      value: value,
      items: items.map((item) {
        final isSelected = item == value;
        return AppDropdownItem<T>(
          value: item,
          label: labelOf(item),
          icon: iconOf?.call(item),
          trailing: trailingOf?.call(item, isSelected),
        );
      }).toList(),
      onChanged: onChanged,
      variant: variant,
      width: width,
      isExpanded: isExpanded,
      menuWidth: menuWidth,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    // 防悬挂兜底：value 不在 items 时追加占位项，保留选中可见性，
    // 避免 DropdownButton "value == null || items contains" 断言崩溃
    // (吸收 models_settings_tab.dart 的既有防护经验)
    final bool valueExists = items.any((item) => item.value == value);
    final List<AppDropdownItem<T>> effectiveItems = valueExists
        ? items
        : [
            AppDropdownItem<T>(
              value: value,
              label: danglingLabel,
              icon: Icons.help_outline_rounded,
            ),
            ...items,
          ];

    final (
      double height,
      double radius,
      double fontSize,
      EdgeInsets padding,
    ) = switch (variant) {
      AppDropdownVariant.standard => (
        38.0,
        AppRadius.md,
        12.5,
        const EdgeInsets.symmetric(horizontal: 10),
      ),
      AppDropdownVariant.pill => (
        28.0,
        AppRadius.pill,
        11.5,
        const EdgeInsets.symmetric(horizontal: 9),
      ),
      AppDropdownVariant.compact => (
        32.0,
        AppRadius.md,
        12.0,
        const EdgeInsets.symmetric(horizontal: 8),
      ),
    };

    // 胶囊变体按钮较窄，菜单宽度默认 220 防止选项文本被截断
    // (继承旧 PillDropdown 的 minWidth 195 / maxWidth 300 保护语义)
    final double? effectiveMenuWidth =
        menuWidth ?? (variant == AppDropdownVariant.pill ? 220.0 : null);

    return Container(
      width: width,
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: colors.borderDefault),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: isExpanded,
          isDense: true,
          dropdownColor: colors.cardBackground,
          borderRadius: BorderRadius.circular(AppRadius.md),
          menuMaxHeight: 400.0,
          menuWidth: effectiveMenuWidth,
          icon: Icon(
            Icons.arrow_drop_down_rounded,
            size: 20,
            color: colors.textSecondary,
          ),
          selectedItemBuilder: (context) {
            return effectiveItems.map((item) {
              return Row(
                children: [
                  if (item.icon != null) ...[
                    Icon(item.icon, size: 14, color: colors.textMuted),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      item.label,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: fontSize,
                        fontWeight: FontWeight.w500,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  if (item.trailing != null) ...[
                    const SizedBox(width: 6),
                    item.trailing!,
                  ],
                ],
              );
            }).toList();
          },
          items: effectiveItems.map((item) {
            final isSelected = item.value == value;

            return DropdownMenuItem<T>(
              value: item.value,
              child: Tooltip(
                message: item.tooltip ?? item.label,
                waitDuration: const Duration(milliseconds: 500),
                child: Row(
                  children: [
                    if (item.icon != null) ...[
                      Icon(
                        item.icon,
                        size: 14,
                        color: isSelected ? colors.primary : colors.textMuted,
                      ),
                      const SizedBox(width: 7),
                    ],
                    Expanded(
                      child: Text(
                        item.label,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: fontSize,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: isSelected
                              ? colors.primary
                              : colors.textPrimary,
                        ),
                      ),
                    ),
                    if (item.trailing != null) ...[
                      const SizedBox(width: 6),
                      item.trailing!,
                    ] else if (isSelected) ...[
                      const SizedBox(width: 6),
                      Icon(
                        Icons.check_rounded,
                        size: 14,
                        color: colors.primary,
                      ),
                    ],
                  ],
                ),
              ),
            );
          }).toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}
