import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../context_l10n.dart';
import '../theme/app_motion.dart';
import '../theme/app_tokens.dart';
import '../theme/theme_context_extensions.dart';
import 'app_search_field.dart';
import 'overlay_anchor.dart';

/// 下拉组件展示形态变体
enum AppDropdownVariant {
  /// 标准表单形态 (高 38px，带轻边框，圆角 8px，适合模型/采样器等主要表单)
  standard,

  /// 药丸胶囊形态 (高 28px，圆角 9999px，适合行内椭圆切换)
  pill,

  /// 紧凑芯片形态 (高 28px，圆角 6px，暖纸/深灰底轻描边，适合提示词卡工具条与 AppToolChip 并排)
  chip,

  /// 紧凑形态 (高 32px，圆角 8px，适合标题栏/工具条内嵌)
  compact,

  /// 无边框工具栏形态，嵌入已有卡片时避免多层描边。
  inline,
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
/// 采用与 Agent 对话卡片模型选择器一致的锚定吸附浮层 (`showAnchoredPopover`)，
/// 完全基于 [AppColorsExtension] 与 [AppTokens]，支持深浅主题平滑自适应、
/// 窗口缩放重对齐与长列表实时搜索。
///
/// 内置两项防御性保障：
/// 1. **防悬挂兜底**：当 [value] 不在 [items] 中时（动态列表被外部刷新/删除），
///    自动在菜单头部追加一个「未识别」占位项，确保当前值可见；
/// 2. **菜单宽度保护**：胶囊与紧凑变体默认展开宽度扩展至安全最小值，避免选项被截断。
class AppDropdown<T> extends StatefulWidget {
  final T value;
  final List<AppDropdownItem<T>> items;
  final ValueChanged<T> onChanged;
  final bool enabled;
  final AppDropdownVariant variant;
  final String? hintText;
  final double? width;
  final bool isExpanded;

  /// 最小触控高度；手机工具栏设为 48，默认不改变桌面尺寸。
  final double minHeight;

  /// 菜单长标签允许折行 (最多两行后省略)，收起态仍保持单行。
  final bool multilineMenu;

  /// 展开菜单的宽度上限；未指定时自动贴合触发器与变体安全最小宽
  final double? menuWidth;

  /// [value] 不在 [items] 中时，占位项展示的文案
  final String? danglingLabel;

  /// 是否在浮层顶部显示实时搜索框；为 null 时在选项数 >= 8 自动开启
  final bool? searchable;

  const AppDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.enabled = true,
    this.variant = AppDropdownVariant.standard,
    this.hintText,
    this.width,
    this.isExpanded = true,
    this.minHeight = 0,
    this.multilineMenu = false,
    this.menuWidth,
    this.danglingLabel,
    this.searchable,
  });

  /// 便捷工厂：从普通对象列表与标签映射构造
  factory AppDropdown.simple({
    Key? key,
    required T value,
    required List<T> items,
    required String Function(T item) labelOf,
    required ValueChanged<T> onChanged,
    bool enabled = true,
    IconData Function(T item)? iconOf,
    Widget? Function(T item, bool isSelected)? trailingOf,
    AppDropdownVariant variant = AppDropdownVariant.standard,
    double? width,
    bool isExpanded = true,
    double? menuWidth,
    bool? searchable,
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
      enabled: enabled,
      variant: variant,
      width: width,
      isExpanded: isExpanded,
      menuWidth: menuWidth,
      searchable: searchable,
    );
  }

  @override
  State<AppDropdown<T>> createState() => _AppDropdownState<T>();
}

class _AppDropdownState<T> extends State<AppDropdown<T>> {
  bool _isOpen = false;

  Future<void> _openPopover(
    BuildContext triggerContext,
    List<AppDropdownItem<T>> effectiveItems,
    double fontSize,
  ) async {
    final renderBox = triggerContext.findRenderObject() as RenderBox?;
    final triggerWidth = (renderBox != null && renderBox.hasSize)
        ? renderBox.size.width
        : 160.0;
    final defaultMin =
        (widget.variant == AppDropdownVariant.pill ||
            widget.variant == AppDropdownVariant.chip)
        ? 200.0
        : 160.0;
    final defaultMax =
        (widget.variant == AppDropdownVariant.pill ||
            widget.variant == AppDropdownVariant.chip)
        ? 240.0
        : 320.0;
    final effectiveMinWidth =
        widget.menuWidth ?? math.max(triggerWidth, defaultMin);
    final effectiveMaxWidth =
        widget.menuWidth ?? math.max(triggerWidth, defaultMax);

    setState(() => _isOpen = true);
    try {
      final result = await showAnchoredPopover<({T value})>(
        context: triggerContext,
        preferAbove: false,
        gap: 4,
        minWidth: effectiveMinWidth,
        maxWidth: effectiveMaxWidth,
        maxHeight: 380,
        builder: (_) => _AppDropdownPopoverSheet<T>(
          items: effectiveItems,
          selectedValue: widget.value,
          fontSize: fontSize,
          multilineMenu: widget.multilineMenu,
          showSearch: widget.searchable ?? (effectiveItems.length >= 8),
        ),
      );
      if (result != null) {
        widget.onChanged(result.value);
      }
    } finally {
      if (mounted) {
        setState(() => _isOpen = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    // 防悬挂兜底：value 不在 items 时追加占位项，保留选中可见性
    final bool valueExists = widget.items.any(
      (item) => item.value == widget.value,
    );
    final List<AppDropdownItem<T>> effectiveItems = valueExists
        ? widget.items
        : [
            AppDropdownItem<T>(
              value: widget.value,
              label:
                  widget.danglingLabel ??
                  context.maybeL10n?.commonUnrecognizedOption ??
                  '未识别',
              icon: Icons.help_outline_rounded,
            ),
            ...widget.items,
          ];

    final currentItem = effectiveItems.firstWhere(
      (item) => item.value == widget.value,
      orElse: () => effectiveItems.first,
    );

    final (
      double height,
      double radius,
      double fontSize,
      EdgeInsets padding,
    ) = switch (widget.variant) {
      AppDropdownVariant.standard => (
        38.0,
        AppRadius.md,
        13.0,
        const EdgeInsets.symmetric(horizontal: 10),
      ),
      AppDropdownVariant.pill => (
        28.0,
        AppRadius.pill,
        12.0,
        const EdgeInsets.symmetric(horizontal: 9),
      ),
      AppDropdownVariant.chip => (
        28.0,
        6.0,
        12.0,
        const EdgeInsets.symmetric(horizontal: 8),
      ),
      AppDropdownVariant.compact => (
        32.0,
        AppRadius.md,
        12.0,
        const EdgeInsets.symmetric(horizontal: 8),
      ),
      AppDropdownVariant.inline => (
        32.0,
        AppRadius.md,
        12.0,
        const EdgeInsets.symmetric(horizontal: 6),
      ),
    };

    final labelWidget = Text(
      currentItem.label,
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w500,
        color: widget.enabled ? colors.textPrimary : colors.textMuted,
      ),
    );

    final chevronDuration = AppMotion.resolveDuration(
      context,
      AppMotionDurations.dropdownOpen,
    );
    final chevronIcon = Icon(
      Icons.keyboard_arrow_down_rounded,
      size: 16,
      color: widget.enabled
          ? colors.textMuted
          : colors.textMuted.withValues(alpha: 0.45),
    );

    final triggerContent = Material(
      color: switch (widget.variant) {
        AppDropdownVariant.inline => Colors.transparent,
        AppDropdownVariant.chip => colors.canvasBackground,
        _ => colors.cardBackground,
      },
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: widget.variant == AppDropdownVariant.inline
            ? BorderSide.none
            : BorderSide(color: colors.borderDefault),
      ),
      clipBehavior: Clip.antiAlias,
      child: Builder(
        builder: (triggerContext) => InkWell(
          onTap: widget.enabled
              ? () => _openPopover(triggerContext, effectiveItems, fontSize)
              : null,
          borderRadius: BorderRadius.circular(radius),
          child: Container(
            height: widget.minHeight == 0 ? height : null,
            constraints: BoxConstraints(
              minHeight: widget.minHeight > height ? widget.minHeight : height,
            ),
            padding: padding,
            alignment: widget.isExpanded ? Alignment.centerLeft : null,
            child: Row(
              mainAxisSize: widget.isExpanded
                  ? MainAxisSize.max
                  : MainAxisSize.min,
              children: [
                if (currentItem.icon != null) ...[
                  Icon(currentItem.icon, size: 14, color: colors.textMuted),
                  const SizedBox(width: 6),
                ],
                if (widget.isExpanded)
                  Expanded(child: labelWidget)
                else
                  Flexible(child: labelWidget),
                if (currentItem.trailing != null) ...[
                  const SizedBox(width: 6),
                  currentItem.trailing!,
                ],
                const SizedBox(width: 4),
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(end: _isOpen ? -1.0 : 1.0),
                  duration: chevronDuration,
                  curve: AppMotionCurves.smoothOut,
                  builder: (context, scaleY, child) {
                    return Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.diagonal3Values(1.0, scaleY, 1.0),
                      child: child,
                    );
                  },
                  child: chevronIcon,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (widget.width != null) {
      return SizedBox(width: widget.width, child: triggerContent);
    }
    return triggerContent;
  }
}

class _AppDropdownPopoverSheet<T> extends StatefulWidget {
  final List<AppDropdownItem<T>> items;
  final T selectedValue;
  final double fontSize;
  final bool multilineMenu;
  final bool showSearch;

  const _AppDropdownPopoverSheet({
    required this.items,
    required this.selectedValue,
    required this.fontSize,
    required this.multilineMenu,
    required this.showSearch,
  });

  @override
  State<_AppDropdownPopoverSheet<T>> createState() =>
      _AppDropdownPopoverSheetState<T>();
}

class _AppDropdownPopoverSheetState<T>
    extends State<_AppDropdownPopoverSheet<T>> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final filtered = _query.isEmpty
        ? widget.items
        : widget.items
              .where((item) => item.label.toLowerCase().contains(_query))
              .toList();

    return Padding(
      padding: const EdgeInsets.all(6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.showSearch) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
              child: AppSearchField(
                hintText: context.maybeL10n?.settingsSearchModelHint ?? 'Search...',
                debounceDuration: Duration.zero,
                onChanged: (q) =>
                    setState(() => _query = q.trim().toLowerCase()),
              ),
            ),
          ],
          Flexible(
            child: filtered.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Icon(
                        Icons.search_off_rounded,
                        size: 22,
                        color: colors.textMuted,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      final isSelected = item.value == widget.selectedValue;
                      return Tooltip(
                        message: item.tooltip ?? item.label,
                        waitDuration: AppMotionDurations.verySlow,
                        child: Material(
                          color: isSelected
                              ? colors.primaryTint
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            onTap: () => Navigator.of(
                              context,
                            ).pop<({T value})>((value: item.value)),
                            child: DropdownMenuItem<T>(
                              value: item.value,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                child: Row(
                                  children: [
                                    if (item.icon != null) ...[
                                      Icon(
                                        item.icon,
                                        size: 14,
                                        color: isSelected
                                            ? colors.primary
                                            : colors.textMuted,
                                      ),
                                      const SizedBox(width: 7),
                                    ],
                                    Expanded(
                                      child: Text(
                                        item.label,
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: widget.multilineMenu ? 2 : 1,
                                        style: TextStyle(
                                          fontSize: widget.fontSize,
                                          fontWeight: isSelected
                                              ? FontWeight.w600
                                              : FontWeight.w400,
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
                                      const SizedBox(width: 8),
                                      Icon(
                                        Icons.check_rounded,
                                        size: 15,
                                        color: colors.primary,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
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
