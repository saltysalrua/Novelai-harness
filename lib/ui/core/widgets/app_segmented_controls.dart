import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import '../theme/app_colors_extension.dart';
import '../theme/theme_context_extensions.dart';
import 'app_badge.dart';

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

  /// 是否显示微徽章/提示点 (可选)
  final bool badge;

  /// 尾部计数徽标文案 (可选，如分类条目数)
  final String? badgeLabel;

  /// 选中态强调色 (可选，默认使用品牌主色，如角色分类用警示红)
  final Color? activeColor;

  const AppSegmentedItem({
    required this.value,
    required this.label,
    this.icon,
    this.tooltip,
    this.badge = false,
    this.badgeLabel,
    this.activeColor,
  });
}

/// 胶囊选中视觉模式
enum AppPillVariant {
  /// 实心模式 (选中态为品牌纯色背景 + 纯白文字/图标)
  solid,

  /// 柔和淡彩模式 (选中态为 12% 浅蓝底色 + 品牌深蓝文字/图标)
  soft,

  /// 无底色文字页签，仅以底部细线标记选中项 (移动端页面导航)。
  underline,
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

  /// 是否均分满宽排布 (每项等宽拉伸，适合两栏对半等对称场景)，默认 false
  final bool expand;

  /// 默认药丸圆角；导航等场景可复用应用标准小圆角。
  final double radius;

  /// 最小点击高度；触屏导航可设为 48，桌面紧凑控件保持原尺寸。
  final double minHeight;

  const AppSegmentedPillBar({
    super.key,
    required this.items,
    required this.selectedValue,
    this.onValueChanged,
    this.variant = AppPillVariant.solid,
    this.scrollable = false,
    this.spacing = 6.0,
    this.itemPadding = const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    this.expand = false,
    this.radius = AppRadius.pill,
    this.minHeight = 0,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final children = <Widget>[
      for (int i = 0; i < items.length; i++) ...[
        if (i > 0) SizedBox(width: spacing),
        _wrapExpanded(
          context,
          colors,
          items[i],
          index: i,
          isLast: i == items.length - 1,
        ),
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

  /// expand 模式下用 Expanded 均分；间距项只插在非末尾项后
  Widget _wrapExpanded(
    BuildContext context,
    AppColorsExtension colors,
    AppSegmentedItem<T> item, {
    required int index,
    required bool isLast,
  }) {
    final pill = _buildPillItem(context, colors, item);
    if (!expand) return pill;
    return Expanded(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [Expanded(child: pill)],
      ),
    );
  }

  Widget _buildPillItem(
    BuildContext context,
    AppColorsExtension colors,
    AppSegmentedItem<T> item,
  ) {
    final isSelected = item.value == selectedValue;
    final accent = item.activeColor ?? colors.primary;
    final activeBackground = item.activeColor == null
        ? colors.primaryTint
        : accent.withValues(alpha: 0.12);

    final (Color bg, Color border, Color fg) = switch (variant) {
      AppPillVariant.solid => (
        isSelected ? accent : colors.cardBackground,
        isSelected ? accent : colors.borderDefault,
        isSelected ? Colors.white : colors.textSecondary,
      ),
      AppPillVariant.soft => (
        isSelected ? activeBackground : colors.cardBackground,
        isSelected ? accent.withValues(alpha: 0.35) : colors.borderDefault,
        isSelected ? accent : colors.textSecondary,
      ),
      AppPillVariant.underline => (
        Colors.transparent,
        isSelected ? accent : Colors.transparent,
        isSelected ? colors.textPrimary : colors.textMuted,
      ),
    };

    Widget pill = InkWell(
      key: Key('segmented_pill_${item.value}'),
      onTap: () => onValueChanged?.call(item.value),
      borderRadius: BorderRadius.circular(radius),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        constraints: BoxConstraints(minHeight: minHeight),
        padding: itemPadding,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: variant == AppPillVariant.underline
              ? null
              : BorderRadius.circular(radius),
          border: variant == AppPillVariant.underline
              ? Border(bottom: BorderSide(color: border, width: 2))
              : Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (item.icon != null) ...[
              Icon(item.icon, size: 13, color: fg),
              if (item.label.isNotEmpty) const SizedBox(width: 4),
            ],
            if (item.label.isNotEmpty)
              Flexible(
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: variant == AppPillVariant.underline ? 14 : 12,
                    fontWeight: isSelected
                        ? FontWeight.w600
                        : FontWeight.normal,
                    color: fg,
                  ),
                ),
              ),
            if (item.badge) ...[
              const SizedBox(width: 4),
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  // 未选中项的前景色是次级灰，徽点改用强调色，
                  // 后台流式输出在其它页签也能被看见
                  color: isSelected ? fg : accent,
                  shape: BoxShape.circle,
                ),
              ),
            ],
            if (item.badgeLabel != null) ...[
              const SizedBox(width: 5),
              AppBadge(
                label: item.badgeLabel!,
                shape: AppBadgeShape.pill,
                fontSize: 10,
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                customBackgroundColor: fg.withValues(alpha: 0.12),
                customForegroundColor: fg,
                customBorderColor: fg.withValues(alpha: 0.2),
              ),
            ],
          ],
        ),
      ),
    );

    if (item.tooltip != null && item.tooltip!.isNotEmpty) {
      pill = Tooltip(message: item.tooltip!, child: pill);
    }

    return Semantics(selected: isSelected, button: true, child: pill);
  }
}

/// 统一水平圆角矩形分段单选条 (AppSegmentedCardBar)
///
/// 核心职责：
/// 覆盖横向选项切换、模式选择与标签页切换场景，外层以柔和灰底圆角矩形 (`AppRadius.md`)
/// 作为轨道容器包裹所有选项，选中项指示器在轨道内以弹性滑动 (`Cubic(0.34, 1.36, 0.64, 1)`)
/// 跟随切换，未选中项透明融入灰底轨道。
class AppSegmentedCardBar<T> extends StatefulWidget {
  /// 分段项列表
  final List<AppSegmentedItem<T>> items;

  /// 当前选中的值
  final T? selectedValue;

  /// 选中值改变回调
  final ValueChanged<T>? onValueChanged;

  /// 是否允许横向滚动 (项较多时适用)，默认 false
  final bool scrollable;

  /// 选项之间的水平间距，默认 3.0
  final double spacing;

  /// 轨道容器内边距，默认全向 3.0
  final EdgeInsetsGeometry trackPadding;

  /// 单个选项的内边距，默认水平 12，垂直 6
  final EdgeInsetsGeometry itemPadding;

  /// 是否均分满宽排布 (每项等宽拉伸)，默认 false
  final bool expand;

  /// 外层轨道圆角大小，默认 [AppRadius.md] (8.0)；内层选项自动按同心圆角收敛
  final double radius;

  /// 最小点击高度，默认 0
  final double minHeight;

  const AppSegmentedCardBar({
    super.key,
    required this.items,
    required this.selectedValue,
    this.onValueChanged,
    this.scrollable = false,
    this.spacing = 3.0,
    this.trackPadding = const EdgeInsets.all(3),
    this.itemPadding = const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    this.expand = false,
    this.radius = AppRadius.md,
    this.minHeight = 0,
  });

  @override
  State<AppSegmentedCardBar<T>> createState() => _AppSegmentedCardBarState<T>();
}

class _AppSegmentedCardBarState<T> extends State<AppSegmentedCardBar<T>>
    with SingleTickerProviderStateMixin {
  static const Duration _slideDuration = Duration(milliseconds: 280);
  static const Curve _elasticCurve = Cubic(0.34, 1.36, 0.64, 1);
  static const Curve _smoothCurve = Cubic(0.22, 1, 0.36, 1);

  final GlobalKey _stackKey = GlobalKey();
  late List<GlobalKey> _itemKeys;
  late final AnimationController _slideController;
  late final CurvedAnimation _curvedAnimation;

  Rect? _fromRect;
  Rect? _toRect;
  bool _measureScheduled = false;

  @override
  void initState() {
    super.initState();
    _itemKeys = List.generate(widget.items.length, (_) => GlobalKey());
    _slideController = AnimationController(
      vsync: this,
      duration: _slideDuration,
    );
    _curvedAnimation = CurvedAnimation(
      parent: _slideController,
      curve: _elasticCurve,
    );
    _scheduleMeasure(animate: false);
  }

  @override
  void didUpdateWidget(covariant AppSegmentedCardBar<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.items.length != _itemKeys.length) {
      _itemKeys = List.generate(widget.items.length, (_) => GlobalKey());
    }

    if (widget.selectedValue != oldWidget.selectedValue) {
      final currentVisualRect = _currentVisualRect();
      _scheduleMeasure(animate: true, fromOverride: currentVisualRect);
    } else if (widget.items.length != oldWidget.items.length ||
        widget.expand != oldWidget.expand ||
        widget.spacing != oldWidget.spacing) {
      _scheduleMeasure(animate: false);
    }
  }

  @override
  void dispose() {
    _curvedAnimation.dispose();
    _slideController.dispose();
    super.dispose();
  }

  Rect? _currentVisualRect() {
    if (_fromRect != null && _toRect != null && _slideController.isAnimating) {
      return Rect.lerp(_fromRect, _toRect, _curvedAnimation.value);
    }
    return _toRect;
  }

  void _scheduleMeasure({required bool animate, Rect? fromOverride}) {
    if (_measureScheduled && !animate) return;
    _measureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureScheduled = false;
      if (!mounted) return;
      _syncIndicator(animate: animate, fromOverride: fromOverride);
    });
  }

  Rect? _measureSelectedRect() {
    final selectedIndex = widget.items.indexWhere(
      (item) => item.value == widget.selectedValue,
    );
    if (selectedIndex < 0 || selectedIndex >= _itemKeys.length) {
      return null;
    }

    final stackBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    final itemBox =
        _itemKeys[selectedIndex].currentContext?.findRenderObject()
            as RenderBox?;
    if (stackBox == null ||
        itemBox == null ||
        !stackBox.hasSize ||
        !itemBox.hasSize) {
      return null;
    }

    final topLeft = itemBox.localToGlobal(Offset.zero, ancestor: stackBox);
    return topLeft & itemBox.size;
  }

  void _syncIndicator({required bool animate, Rect? fromOverride}) {
    final targetRect = _measureSelectedRect();
    if (targetRect == null) {
      if (_toRect != null || _fromRect != null) {
        setState(() {
          _fromRect = null;
          _toRect = null;
        });
      }
      return;
    }

    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final startRect = fromOverride ?? _toRect;

    if (!animate || disableAnimations || startRect == null) {
      _slideController.stop();
      setState(() {
        _fromRect = targetRect;
        _toRect = targetRect;
      });
      _slideController.value = 1.0;
      return;
    }

    if (startRect == targetRect) return;

    setState(() {
      _fromRect = startRect;
      _toRect = targetRect;
    });
    _slideController.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final innerRadius = (widget.radius - 2).clamp(2.0, widget.radius);
    final disableAnimations = MediaQuery.disableAnimationsOf(context);

    final selectedIndex = widget.items.indexWhere(
      (item) => item.value == widget.selectedValue,
    );
    final selectedItem = selectedIndex >= 0
        ? widget.items[selectedIndex]
        : null;
    final accent = selectedItem?.activeColor ?? colors.primary;
    final selectedBg = selectedItem?.activeColor != null
        ? accent.withValues(alpha: 0.14)
        : (isDark
              ? Color.alphaBlend(
                  Colors.white.withValues(alpha: 0.08),
                  colors.mutedBackground,
                )
              : colors.cardBackground);

    final children = <Widget>[
      for (int i = 0; i < widget.items.length; i++) ...[
        if (i > 0) SizedBox(width: widget.spacing),
        _wrapItem(
          context,
          colors,
          innerRadius,
          disableAnimations,
          widget.items[i],
          _itemKeys[i],
        ),
      ],
    ];

    final Widget stack = NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (_) {
        _scheduleMeasure(animate: false);
        return false;
      },
      child: SizeChangedLayoutNotifier(
        child: Stack(
          key: _stackKey,
          children: [
            AnimatedBuilder(
              animation: _curvedAnimation,
              builder: (context, _) {
                final rect = (_fromRect != null && _toRect != null)
                    ? Rect.lerp(_fromRect, _toRect, _curvedAnimation.value)
                    : _toRect;
                if (rect == null) return const SizedBox.shrink();

                return Positioned(
                  left: rect.left,
                  top: rect.top,
                  width: rect.width.clamp(0.0, double.infinity),
                  height: rect.height.clamp(0.0, double.infinity),
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        color: selectedBg,
                        borderRadius: BorderRadius.circular(innerRadius),
                        border: selectedItem?.activeColor != null
                            ? Border.all(color: accent.withValues(alpha: 0.35))
                            : null,
                        boxShadow:
                            selectedItem?.activeColor == null && !isDark
                            ? [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.06),
                                  blurRadius: 4,
                                  offset: const Offset(0, 1),
                                ),
                              ]
                            : null,
                      ),
                    ),
                  ),
                );
              },
            ),
            Row(
              mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
              children: children,
            ),
          ],
        ),
      ),
    );

    final Widget content = widget.scrollable
        ? SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: stack,
          )
        : stack;

    return Container(
      padding: widget.trackPadding,
      decoration: BoxDecoration(
        color: colors.mutedBackground,
        borderRadius: BorderRadius.circular(widget.radius),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: content,
    );
  }

  Widget _wrapItem(
    BuildContext context,
    AppColorsExtension colors,
    double innerRadius,
    bool disableAnimations,
    AppSegmentedItem<T> item,
    GlobalKey itemKey,
  ) {
    final card = _buildCardItem(
      context,
      colors,
      innerRadius,
      disableAnimations,
      item,
      itemKey,
    );
    if (!widget.expand) return card;
    return Expanded(child: card);
  }

  Widget _buildCardItem(
    BuildContext context,
    AppColorsExtension colors,
    double innerRadius,
    bool disableAnimations,
    AppSegmentedItem<T> item,
    GlobalKey itemKey,
  ) {
    final isSelected = item.value == widget.selectedValue;
    final accent = item.activeColor ?? colors.primary;
    final fg = isSelected
        ? (item.activeColor != null ? accent : colors.textPrimary)
        : colors.textSecondary;
    final colorDuration = disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 220);

    Widget card = InkWell(
      key: Key('segmented_card_${item.value}'),
      onTap: () => widget.onValueChanged?.call(item.value),
      borderRadius: BorderRadius.circular(innerRadius),
      hoverColor: colors.textPrimary.withValues(alpha: 0.04),
      splashColor: Colors.transparent,
      child: Container(
        key: itemKey,
        constraints: BoxConstraints(minHeight: widget.minHeight),
        padding: widget.itemPadding,
        child: Row(
          mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (item.icon != null) ...[
              Icon(item.icon, size: 14, color: fg),
              if (item.label.isNotEmpty) const SizedBox(width: 5),
            ],
            if (item.label.isNotEmpty)
              Flexible(
                child: AnimatedDefaultTextStyle(
                  duration: colorDuration,
                  curve: _smoothCurve,
                  style: DefaultTextStyle.of(context).style.copyWith(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: fg,
                  ),
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            if (item.badge) ...[
              const SizedBox(width: 5),
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: isSelected ? fg : accent,
                  shape: BoxShape.circle,
                ),
              ),
            ],
            if (item.badgeLabel != null) ...[
              const SizedBox(width: 5),
              AppBadge(
                label: item.badgeLabel!,
                shape: AppBadgeShape.pill,
                fontSize: 10,
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                customBackgroundColor: fg.withValues(alpha: 0.12),
                customForegroundColor: fg,
                customBorderColor: fg.withValues(alpha: 0.2),
              ),
            ],
          ],
        ),
      ),
    );

    if (item.tooltip != null && item.tooltip!.isNotEmpty) {
      card = Tooltip(message: item.tooltip!, child: card);
    }

    return Semantics(selected: isSelected, button: true, child: card);
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
            // Flexible 防溢出：字体回退 (测试环境 Ahem 等宽字形) 或超长文案时
            // 允许文本列收缩换行，而不是把 Row 撑爆
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w600,
                      color: titleColor,
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                      style: TextStyle(fontSize: 11, color: subtitleColor),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
