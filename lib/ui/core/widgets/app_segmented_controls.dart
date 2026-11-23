import 'package:flutter/material.dart';
import '../theme/app_motion.dart';
import '../theme/app_tokens.dart';
import '../theme/app_colors_extension.dart';
import '../theme/theme_context_extensions.dart';
import 'app_badge.dart';

/// 胶囊按钮项配置
class AppSegmentedItem<T> {
  /// 可选控件 Key (透传给单个分段按钮，便于测试定位)
  final Key? key;

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
    this.key,
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

/// 统一水平胶囊分段单选条 (`AppSegmentedPillBar`, `16-tabs-sliding`)
///
/// 代码证据出处：
/// - `bill_settings_tab.dart:43-78` (账单周期切换全部/月/周/日胶囊组)
/// - `resolution_pad_picker.dart:178-215` (横屏/竖屏/正方形切换三连键)
///
/// 核心职责：
/// 提供轻量统一的水平药丸分段选择控件，选中激活胶囊在轨道间平滑滑动 (`250ms smoothOut`)，
/// 支持实心/柔和/下划线三种变体、自动适配减弱动画。
class AppSegmentedPillBar<T> extends StatefulWidget {
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
  State<AppSegmentedPillBar<T>> createState() => _AppSegmentedPillBarState<T>();
}

class _AppSegmentedPillBarState<T> extends State<AppSegmentedPillBar<T>>
    with SingleTickerProviderStateMixin {
  final GlobalKey _stackKey = GlobalKey();
  late List<GlobalKey> _itemKeys;
  late final AnimationController _slideController;
  late final CurvedAnimation _curvedAnimation;

  List<Rect> _itemRects = const [];
  Rect? _fromRect;
  Rect? _toRect;
  bool _measureScheduled = false;

  @override
  void initState() {
    super.initState();
    _itemKeys = List.generate(widget.items.length, (_) => GlobalKey());
    _slideController = AnimationController(
      vsync: this,
      duration: AppMotionDurations.fast,
    );
    _curvedAnimation = CurvedAnimation(
      parent: _slideController,
      curve: AppMotionCurves.smoothOut,
    );
    _scheduleMeasure(animate: false);
  }

  @override
  void didUpdateWidget(covariant AppSegmentedPillBar<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.items.length != _itemKeys.length) {
      _itemKeys = List.generate(widget.items.length, (_) => GlobalKey());
      _itemRects = const [];
    }

    if (widget.selectedValue != oldWidget.selectedValue) {
      final currentVisualRect = _currentVisualRect();
      _scheduleMeasure(animate: true, fromOverride: currentVisualRect);
    } else if (widget.items.length != oldWidget.items.length ||
        widget.expand != oldWidget.expand ||
        widget.spacing != oldWidget.spacing ||
        widget.variant != oldWidget.variant) {
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

  void _syncIndicator({required bool animate, Rect? fromOverride}) {
    final stackBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (stackBox == null || !stackBox.hasSize) return;

    final measuredRects = <Rect>[];
    for (final key in _itemKeys) {
      final box = key.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) {
        measuredRects.clear();
        break;
      }
      final topLeft = box.localToGlobal(Offset.zero, ancestor: stackBox);
      measuredRects.add(topLeft & box.size);
    }

    final selectedIndex = widget.items.indexWhere(
      (item) => item.value == widget.selectedValue,
    );
    final Rect? targetRect =
        (selectedIndex >= 0 && selectedIndex < measuredRects.length)
        ? measuredRects[selectedIndex]
        : null;

    if (targetRect == null) {
      if (_toRect != null || _fromRect != null || _itemRects.isNotEmpty) {
        setState(() {
          _itemRects = measuredRects;
          _fromRect = null;
          _toRect = null;
        });
      }
      return;
    }

    final disableAnimations = AppMotion.shouldReduceMotion(context);
    final startRect = fromOverride ?? _toRect;

    if (!animate || disableAnimations || startRect == null) {
      _slideController.stop();
      setState(() {
        _itemRects = measuredRects;
        _fromRect = targetRect;
        _toRect = targetRect;
      });
      _slideController.value = 1.0;
      return;
    }

    if (startRect == targetRect) {
      if (measuredRects.length != _itemRects.length) {
        setState(() => _itemRects = measuredRects);
      }
      return;
    }

    setState(() {
      _itemRects = measuredRects;
      _fromRect = startRect;
      _toRect = targetRect;
    });
    _slideController.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final disableAnimations = AppMotion.shouldReduceMotion(context);
    final hasMeasured =
        _itemRects.length == widget.items.length && _toRect != null;

    final selectedIndex = widget.items.indexWhere(
      (item) => item.value == widget.selectedValue,
    );
    final selectedItem = selectedIndex >= 0
        ? widget.items[selectedIndex]
        : null;
    final accent = selectedItem?.activeColor ?? colors.primary;
    final activeBackground = selectedItem?.activeColor == null
        ? colors.primaryTint
        : accent.withValues(alpha: 0.12);

    final (Color activeBg, Color activeBorder) = switch (widget.variant) {
      AppPillVariant.solid => (accent, accent),
      AppPillVariant.soft => (activeBackground, accent.withValues(alpha: 0.35)),
      AppPillVariant.underline => (Colors.transparent, accent),
    };

    final children = <Widget>[
      for (int i = 0; i < widget.items.length; i++) ...[
        if (i > 0) SizedBox(width: widget.spacing),
        _wrapExpanded(
          context,
          colors,
          disableAnimations,
          hasMeasured,
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
            if (hasMeasured && widget.variant != AppPillVariant.underline)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _PillSlotsBackgroundPainter(
                      rects: _itemRects,
                      radius: widget.radius,
                      fillColor: colors.cardBackground,
                      borderColor: colors.borderDefault,
                    ),
                  ),
                ),
              ),
            if (hasMeasured)
              AnimatedBuilder(
                animation: _curvedAnimation,
                builder: (context, _) {
                  final rect = (_fromRect != null && _toRect != null)
                      ? Rect.lerp(_fromRect, _toRect, _curvedAnimation.value)
                      : _toRect;
                  if (rect == null) return const SizedBox.shrink();

                  if (widget.variant == AppPillVariant.underline) {
                    return Positioned(
                      left: rect.left,
                      top: (rect.bottom - 2).clamp(0.0, double.infinity),
                      width: rect.width.clamp(0.0, double.infinity),
                      height: 2,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(color: activeBorder),
                        ),
                      ),
                    );
                  }

                  return Positioned(
                    left: rect.left,
                    top: rect.top,
                    width: rect.width.clamp(0.0, double.infinity),
                    height: rect.height.clamp(0.0, double.infinity),
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: activeBg,
                          borderRadius: BorderRadius.circular(widget.radius),
                          border: Border.all(color: activeBorder),
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

    if (widget.scrollable) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: stack,
      );
    }

    return stack;
  }

  /// expand 模式下用 Expanded 均分
  Widget _wrapExpanded(
    BuildContext context,
    AppColorsExtension colors,
    bool disableAnimations,
    bool hasMeasured,
    AppSegmentedItem<T> item,
    GlobalKey itemKey,
  ) {
    final pill = _buildPillItem(
      context,
      colors,
      disableAnimations,
      hasMeasured,
      item,
      itemKey,
    );
    if (!widget.expand) return pill;
    return Expanded(child: pill);
  }

  Widget _buildPillItem(
    BuildContext context,
    AppColorsExtension colors,
    bool disableAnimations,
    bool hasMeasured,
    AppSegmentedItem<T> item,
    GlobalKey itemKey,
  ) {
    final isSelected = item.value == widget.selectedValue;
    final accent = item.activeColor ?? colors.primary;
    final activeBackground = item.activeColor == null
        ? colors.primaryTint
        : accent.withValues(alpha: 0.12);

    final (Color bg, Color border, Color fg) = switch (widget.variant) {
      AppPillVariant.solid => (
        isSelected ? accent : colors.cardBackground,
        isSelected ? accent : colors.borderDefault,
        isSelected
            ? (item.activeColor == null ? colors.onPrimary : Colors.white)
            : colors.textSecondary,
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

    final effectiveDuration = disableAnimations
        ? Duration.zero
        : AppMotionDurations.fast;

    Widget pill = InkWell(
      key: Key('segmented_pill_${item.value}'),
      onTap: () => widget.onValueChanged?.call(item.value),
      borderRadius: BorderRadius.circular(widget.radius),
      hoverColor: widget.variant == AppPillVariant.underline
          ? colors.textPrimary.withValues(alpha: 0.04)
          : Colors.transparent,
      splashColor: Colors.transparent,
      child: Container(
        key: itemKey,
        constraints: BoxConstraints(minHeight: widget.minHeight),
        padding: widget.itemPadding,
        decoration: hasMeasured
            ? null
            : BoxDecoration(
                color: bg,
                borderRadius: widget.variant == AppPillVariant.underline
                    ? null
                    : BorderRadius.circular(widget.radius),
                border: widget.variant == AppPillVariant.underline
                    ? Border(bottom: BorderSide(color: border, width: 2))
                    : Border.all(color: border),
              ),
        child: Row(
          mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (item.icon != null) ...[
              Icon(item.icon, size: 13, color: fg),
              if (item.label.isNotEmpty) const SizedBox(width: 4),
            ],
            if (item.label.isNotEmpty)
              Flexible(
                child: AnimatedDefaultTextStyle(
                  duration: effectiveDuration,
                  curve: AppMotionCurves.smoothOut,
                  style: DefaultTextStyle.of(context).style.copyWith(
                    fontSize: widget.variant == AppPillVariant.underline
                        ? 14
                        : 12,
                    fontWeight: isSelected
                        ? FontWeight.w600
                        : FontWeight.normal,
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

class _PillSlotsBackgroundPainter extends CustomPainter {
  final List<Rect> rects;
  final double radius;
  final Color fillColor;
  final Color borderColor;

  const _PillSlotsBackgroundPainter({
    required this.rects,
    required this.radius,
    required this.fillColor,
    required this.borderColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (final rect in rects) {
      final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
      canvas.drawRRect(rrect, fillPaint);
      canvas.drawRRect(rrect.deflate(0.5), borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _PillSlotsBackgroundPainter oldDelegate) {
    if (oldDelegate.radius != radius ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.borderColor != borderColor ||
        oldDelegate.rects.length != rects.length) {
      return true;
    }
    for (var i = 0; i < rects.length; i++) {
      if (oldDelegate.rects[i] != rects[i]) return true;
    }
    return false;
  }
}

/// 通用弹性滑动选择指示器容器 (`AppSlidingSelectionBar`)
///
/// 负责测量选中子项的边界矩形，并以弹性曲线 (`AppMotionCurves.bounce`)
/// 将背景指示器平滑滑动到目标项位置；供 [AppSegmentedCardBar] 与移动端导航栏复用。
class AppSlidingSelectionBar extends StatefulWidget {
  /// 当前选中的子项索引；小于 0 或越界时隐藏指示器
  final int selectedIndex;

  /// 子项列表
  final List<Widget> children;

  /// 子项之间的水平间距，默认 0.0
  final double spacing;

  /// 是否均分满宽排布，默认 false
  final bool expand;

  /// 是否允许横向滚动 (仅 [expand] 为 false 时生效)，默认 false
  final bool scrollable;

  /// 指示器装饰构建器 (传入当前选中的索引)
  final BoxDecoration Function(BuildContext context, int selectedIndex)
  indicatorDecorationBuilder;

  /// 滑移动画时长，默认 [AppMotionDurations.fast]
  final Duration duration;

  /// 滑移动画曲线，默认 [AppMotionCurves.bounce]
  final Curve curve;

  const AppSlidingSelectionBar({
    super.key,
    required this.selectedIndex,
    required this.children,
    required this.indicatorDecorationBuilder,
    this.spacing = 0.0,
    this.expand = false,
    this.scrollable = false,
    this.duration = AppMotionDurations.fast,
    this.curve = AppMotionCurves.bounce,
  });

  @override
  State<AppSlidingSelectionBar> createState() => _AppSlidingSelectionBarState();
}

class _AppSlidingSelectionBarState extends State<AppSlidingSelectionBar>
    with SingleTickerProviderStateMixin {
  final GlobalKey _stackKey = GlobalKey();
  late List<GlobalKey> _itemKeys;
  late final AnimationController _slideController;
  late CurvedAnimation _curvedAnimation;

  Rect? _fromRect;
  Rect? _toRect;
  bool _measureScheduled = false;
  bool _pendingAnimate = false;
  Rect? _pendingFromOverride;

  @override
  void initState() {
    super.initState();
    _itemKeys = List.generate(widget.children.length, (_) => GlobalKey());
    _slideController = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _curvedAnimation = CurvedAnimation(
      parent: _slideController,
      curve: widget.curve,
    );
    _scheduleMeasure(animate: false);
  }

  @override
  void didUpdateWidget(covariant AppSlidingSelectionBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.duration != oldWidget.duration) {
      _slideController.duration = widget.duration;
    }
    if (widget.curve != oldWidget.curve) {
      _curvedAnimation.dispose();
      _curvedAnimation = CurvedAnimation(
        parent: _slideController,
        curve: widget.curve,
      );
    }
    if (widget.children.length != _itemKeys.length) {
      _itemKeys = List.generate(widget.children.length, (_) => GlobalKey());
    }

    if (widget.selectedIndex != oldWidget.selectedIndex) {
      final currentVisualRect = _currentVisualRect();
      _scheduleMeasure(animate: true, fromOverride: currentVisualRect);
    } else if (widget.children.length != oldWidget.children.length ||
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
    if (_measureScheduled) {
      if (animate) {
        _pendingAnimate = true;
        _pendingFromOverride = fromOverride;
      }
      return;
    }
    _measureScheduled = true;
    _pendingAnimate = animate;
    _pendingFromOverride = fromOverride;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final shouldAnimate = _pendingAnimate;
      final overrideRect = _pendingFromOverride;
      _measureScheduled = false;
      _pendingAnimate = false;
      _pendingFromOverride = null;
      if (!mounted) return;
      _syncIndicator(animate: shouldAnimate, fromOverride: overrideRect);
    });
  }

  Rect? _measureSelectedRect() {
    final index = widget.selectedIndex;
    if (index < 0 || index >= _itemKeys.length) {
      return null;
    }

    final stackBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    final itemBox =
        _itemKeys[index].currentContext?.findRenderObject() as RenderBox?;
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

    final disableAnimations = AppMotion.shouldReduceMotion(context);
    final startRect = fromOverride ?? _toRect;

    if (!animate || disableAnimations || startRect == null) {
      // 布局尺寸微调（如滚动条显隐）若发生在滑动动画进行中，仅修正终点矩形而不掐断动画
      if (!disableAnimations && _slideController.isAnimating && startRect != null) {
        if (_toRect != targetRect) {
          setState(() => _toRect = targetRect);
        }
        return;
      }
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
    final rowChildren = <Widget>[
      for (int i = 0; i < widget.children.length; i++) ...[
        if (i > 0 && widget.spacing > 0) SizedBox(width: widget.spacing),
        if (widget.expand)
          Expanded(
            child: KeyedSubtree(
              key: _itemKeys[i],
              child: widget.children[i],
            ),
          )
        else
          KeyedSubtree(
            key: _itemKeys[i],
            child: widget.children[i],
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
                      decoration: widget.indicatorDecorationBuilder(
                        context,
                        widget.selectedIndex,
                      ),
                    ),
                  ),
                );
              },
            ),
            Row(
              mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
              children: rowChildren,
            ),
          ],
        ),
      ),
    );

    if (widget.scrollable && !widget.expand) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: stack,
      );
    }
    return stack;
  }
}

/// 统一水平圆角矩形分段单选条 (AppSegmentedCardBar)
///
/// 核心职责：
/// 覆盖横向选项切换、模式选择与标签页切换场景，外层以柔和灰底圆角矩形 (`AppRadius.md`)
/// 作为轨道容器包裹所有选项，选中项指示器在轨道内以弹性滑动 (`AppMotionCurves.bounce`)
/// 跟随切换，未选中项透明融入灰底轨道。
class AppSegmentedCardBar<T> extends StatelessWidget {
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

  /// 文字字号，默认 13.0
  final double fontSize;

  /// 图标尺寸，默认 14.0
  final double iconSize;

  /// 是否在未指定 [AppSegmentedItem.activeColor] 时，为选中项图标叠加主题主色高亮
  final bool highlightSelectedIcon;

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
    this.fontSize = 13.0,
    this.iconSize = 14.0,
    this.highlightSelectedIcon = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final innerRadius = (radius - 2).clamp(2.0, radius);
    final disableAnimations = AppMotion.shouldReduceMotion(context);
    final selectedIndex = items.indexWhere(
      (item) => item.value == selectedValue,
    );

    return Container(
      padding: trackPadding,
      decoration: BoxDecoration(
        color: colors.mutedBackground,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: AppSlidingSelectionBar(
        selectedIndex: selectedIndex,
        spacing: spacing,
        expand: expand,
        scrollable: scrollable,
        indicatorDecorationBuilder: (context, index) {
          final item = (index >= 0 && index < items.length)
              ? items[index]
              : null;
          final accent = item?.activeColor ?? colors.primary;
          final selectedBg = item?.activeColor != null
              ? accent.withValues(alpha: 0.14)
              : (isDark
                    ? Color.alphaBlend(
                        Colors.white.withValues(alpha: 0.08),
                        colors.mutedBackground,
                      )
                    : colors.cardBackground);

          return BoxDecoration(
            color: selectedBg,
            borderRadius: BorderRadius.circular(innerRadius),
            border: item?.activeColor != null
                ? Border.all(color: accent.withValues(alpha: 0.35))
                : null,
            boxShadow: item?.activeColor == null && !isDark
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          );
        },
        children: [
          for (final item in items)
            _buildCardItem(
              context,
              colors,
              innerRadius,
              disableAnimations,
              item,
            ),
        ],
      ),
    );
  }

  Widget _buildCardItem(
    BuildContext context,
    AppColorsExtension colors,
    double innerRadius,
    bool disableAnimations,
    AppSegmentedItem<T> item,
  ) {
    final isSelected = item.value == selectedValue;
    final accent = item.activeColor ?? colors.primary;
    final fg = isSelected
        ? (item.activeColor != null ? accent : colors.textPrimary)
        : colors.textSecondary;
    final iconFg = (isSelected && highlightSelectedIcon && item.activeColor == null)
        ? colors.primary
        : fg;
    final colorDuration = disableAnimations
        ? Duration.zero
        : AppMotionDurations.fast;

    Widget card = InkWell(
      key: item.key ?? Key('segmented_card_${item.value}'),
      onTap: () => onValueChanged?.call(item.value),
      borderRadius: BorderRadius.circular(innerRadius),
      hoverColor: colors.textPrimary.withValues(alpha: 0.04),
      splashColor: Colors.transparent,
      child: Container(
        constraints: BoxConstraints(minHeight: minHeight),
        padding: itemPadding,
        child: Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (item.icon != null) ...[
              Icon(item.icon, size: iconSize, color: iconFg),
              if (item.label.isNotEmpty) const SizedBox(width: 5),
            ],
            if (item.label.isNotEmpty)
              Flexible(
                child: AnimatedDefaultTextStyle(
                  duration: colorDuration,
                  curve: AppMotionCurves.smoothOut,
                  style: DefaultTextStyle.of(context).style.copyWith(
                    fontSize: fontSize,
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
/// 统一标题+副标题双行布局的选项卡片，规范选中微蓝底 (10% tint)、蓝细边框、
/// 悬停高亮与平滑过渡，同时尊重系统减弱动画设置。
class AppOptionCard<T> extends StatefulWidget {
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
  State<AppOptionCard<T>> createState() => _AppOptionCardState<T>();
}

class _AppOptionCardState<T> extends State<AppOptionCard<T>> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final reduceMotion = AppMotion.shouldReduceMotion(context);
    final duration = AppMotion.resolveDuration(
      context,
      AppMotionDurations.quick,
    );

    final bgColor = widget.isSelected
        ? colors.primaryTint
        : colors.cardBackground;
    final borderColor = widget.isSelected
        ? colors.primary.withValues(alpha: 0.6)
        : (_isHovered ? colors.borderHover : colors.borderDefault);
    final borderWidth = widget.isSelected ? 1.5 : 1.0;
    final titleColor = widget.isSelected ? colors.primary : colors.textPrimary;
    final subtitleColor = widget.isSelected
        ? colors.primary.withValues(alpha: 0.75)
        : colors.textSecondary;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: InkWell(
        onTap: () {
          widget.onTap?.call();
          widget.onSelected?.call(widget.value);
        },
        borderRadius: BorderRadius.circular(widget.radius),
        hoverColor: Colors.transparent,
        child: AnimatedContainer(
          duration: duration,
          curve: AppMotionCurves.smoothOut,
          transform: Matrix4.translationValues(
            0,
            (_isHovered && !widget.isSelected && !reduceMotion) ? -1.5 : 0.0,
            0,
          ),
          transformAlignment: Alignment.center,
          padding: widget.padding,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(widget.radius),
            border: Border.all(color: borderColor, width: borderWidth),
            boxShadow: _isHovered && !widget.isSelected
                ? context.shadowSubtle
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 18, color: titleColor),
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
                      widget.title,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: widget.isSelected
                            ? FontWeight.w700
                            : FontWeight.w600,
                        color: titleColor,
                      ),
                    ),
                    if (widget.subtitle != null &&
                        widget.subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        widget.subtitle!,
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
      ),
    );
  }
}
