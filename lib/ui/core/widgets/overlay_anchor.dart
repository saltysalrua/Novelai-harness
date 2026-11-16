/// 坐标换算原子工具：窗口全局坐标 ↔ Overlay 布局坐标系。
///
/// 全局 UI 缩放 ([AppUiZoomScope]) 会把 Navigator 及其 Overlay 整体放进
/// `窗口逻辑尺寸 / zoom` 的缩小坐标系。而指针事件的 `globalPosition` 与
/// `RenderBox.localToGlobal` 产出的是窗口逻辑坐标——直接拿去给
/// OverlayEntry 的 `Positioned` 定位 (或与 `MediaQuery.sizeOf` 比较)，
/// 菜单/浮层会偏移 zoom 倍 (放大时飞向右下、缩小时挤向左上)。
///
/// 统一经 Overlay 的 `RenderBox.globalToLocal` 做逆变换，
/// 对任意祖先变换 (含 UI 缩放) 都天然正确，zoom=1.0 时退化为恒等。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_motion.dart';
import '../theme/app_tokens.dart';
import '../theme/theme_context_extensions.dart';

/// 把窗口全局坐标换算成指定 [overlay] 布局坐标系下的位置。
///
/// [overlay] 必须已挂载且完成布局；否则原样返回全局坐标兜底。
Offset globalToOverlayPosition(OverlayState overlay, Offset global) {
  final box = overlay.context.findRenderObject();
  if (box is RenderBox && box.hasSize) {
    return box.globalToLocal(global);
  }
  return global;
}

/// 便捷入口：取 [context] 所在 Overlay (默认根 Overlay) 并把窗口全局坐标
/// 换算成该 Overlay 布局坐标系下的位置。
Offset globalToOverlayOf(
  BuildContext context,
  Offset global, {
  bool rootOverlay = true,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: rootOverlay);
  return overlay == null ? global : globalToOverlayPosition(overlay, global);
}

Rect? _computeAnchorRect(BuildContext context) {
  if (!context.mounted) return null;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  final renderObject = context.findRenderObject();
  if (renderObject is! RenderBox ||
      !renderObject.hasSize ||
      !renderObject.attached) {
    return null;
  }
  final topLeftGlobal = renderObject.localToGlobal(Offset.zero);
  final bottomRightGlobal = renderObject.localToGlobal(
    renderObject.size.bottomRight(Offset.zero),
  );
  final topLeft = overlay == null
      ? topLeftGlobal
      : globalToOverlayPosition(overlay, topLeftGlobal);
  final bottomRight = overlay == null
      ? bottomRightGlobal
      : globalToOverlayPosition(overlay, bottomRightGlobal);
  return Rect.fromPoints(topLeft, bottomRight);
}

/// 在触发组件附近弹出轻浮层：自动对齐触发区域左右/上下方向并约束在可见安全区内，
/// 点击外部或按 Esc 即可关闭；桌面多栏下不会跑偏到屏幕正中央遮挡画布。
Future<T?> showAnchoredPopover<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  double minWidth = 0,
  double maxWidth = 360,
  double maxHeight = 420,
  double gap = 8,
  double viewportMargin = 8,
  bool preferAbove = true,
}) {
  final navigator = Navigator.of(context, rootNavigator: true);
  final anchorRect = _computeAnchorRect(context);

  final themes = InheritedTheme.capture(from: context, to: navigator.context);
  final barrierLabel = MaterialLocalizations.of(
    context,
  ).modalBarrierDismissLabel;

  return navigator.push<T>(
    _AnchoredPopoverRoute<T>(
      anchorContext: context,
      anchorRect: anchorRect,
      builder: builder,
      themes: themes,
      barrierLabel: barrierLabel,
      minWidth: minWidth,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      gap: gap,
      viewportMargin: viewportMargin,
      preferAbove: preferAbove,
    ),
  );
}

class _AnchoredPopoverRoute<T> extends PopupRoute<T> {
  final BuildContext anchorContext;
  final Rect? anchorRect;
  final WidgetBuilder builder;
  final CapturedThemes themes;
  final double minWidth;
  final double maxWidth;
  final double maxHeight;
  final double gap;
  final double viewportMargin;
  final bool preferAbove;

  _AnchoredPopoverRoute({
    required this.anchorContext,
    required this.anchorRect,
    required this.builder,
    required this.themes,
    required this.barrierLabel,
    required this.minWidth,
    required this.maxWidth,
    required this.maxHeight,
    required this.gap,
    required this.viewportMargin,
    required this.preferAbove,
  });

  Rect? _resolveAnchorRect() => _computeAnchorRect(anchorContext) ?? anchorRect;

  @override
  final String barrierLabel;

  @override
  Color? get barrierColor => Colors.transparent;

  @override
  bool get barrierDismissible => true;

  bool get _reduceMotion {
    final navContext = navigator?.context;
    return navContext != null && MediaQuery.disableAnimationsOf(navContext);
  }

  @override
  Duration get transitionDuration =>
      _reduceMotion ? Duration.zero : AppMotionDurations.dropdownOpen;

  @override
  Duration get reverseTransitionDuration =>
      _reduceMotion ? Duration.zero : AppMotionDurations.dropdownClose;

  Widget _buildAnimatedPopover(
    BuildContext context,
    Animation<double> animation,
    Alignment originAlignment,
    Widget child,
  ) {
    if (_reduceMotion || AppMotion.shouldReduceMotion(context)) {
      return child;
    }
    return AnimatedBuilder(
      animation: animation,
      builder: (context, innerChild) {
        final isClosing = animation.status == AnimationStatus.reverse;
        final t = AppMotionCurves.smoothOut
            .transform(animation.value)
            .clamp(0.0, 1.0);
        final startScale = isClosing
            ? AppMotionScales.dropdownClose
            : AppMotionScales.dropdown;
        final scale = startScale + (1.0 - startScale) * t;
        return Opacity(
          opacity: t,
          child: Transform.scale(
            scale: scale,
            alignment: originAlignment,
            child: innerChild,
          ),
        );
      },
      child: child,
    );
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => themes.wrap(
    LayoutBuilder(
      builder: (layoutContext, constraints) {
        final padding = MediaQuery.paddingOf(layoutContext);
        final insets = MediaQuery.viewInsetsOf(layoutContext);
        final minLeft = padding.left + viewportMargin;
        final maxRight = constraints.maxWidth - padding.right - viewportMargin;
        final availableWidth = (maxRight - minLeft)
            .clamp(120.0, double.infinity)
            .toDouble();
        final double popoverWidth = minWidth > 0
            ? math.max(minWidth, maxWidth).clamp(120.0, availableWidth).toDouble()
            : math.min(maxWidth, availableWidth);

        final minTop = padding.top + viewportMargin;
        final safeBottom =
            constraints.maxHeight -
            padding.bottom -
            insets.bottom -
            viewportMargin;
        final totalAvailableHeight = (safeBottom - minTop)
            .clamp(100.0, double.infinity)
            .toDouble();

        final colors = layoutContext.colors;
        final panelChild = CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                Navigator.of(layoutContext).maybePop(),
          },
          child: Material(
            color: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                color: colors.cardBackground,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: colors.borderDefault),
                boxShadow: layoutContext.shadowElevated,
              ),
              clipBehavior: Clip.antiAlias,
              // 浮层已由 Positioned 限定在安全区内，剥离外层屏幕 SafeArea padding，
              // 防止内部的 ListView 在安卓/iOS 上额外注入状态栏高度的顶部空白。
              child: MediaQuery.removePadding(
                context: layoutContext,
                removeTop: true,
                removeBottom: true,
                removeLeft: true,
                removeRight: true,
                child: Builder(builder: builder),
              ),
            ),
          ),
        );

        final anchor = _resolveAnchorRect();
        if (anchor == null) {
          final fallbackHeight = math.min(maxHeight, totalAvailableHeight);
          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: popoverWidth,
                maxHeight: fallbackHeight,
              ),
              child: _buildAnimatedPopover(
                layoutContext,
                animation,
                Alignment.center,
                panelChild,
              ),
            ),
          );
        }

        final left = anchor.left
            .clamp(minLeft, math.max(minLeft, maxRight - popoverWidth))
            .toDouble();
        final spaceAbove = (anchor.top - gap - minTop)
            .clamp(0.0, double.infinity)
            .toDouble();
        final spaceBelow = (safeBottom - gap - anchor.bottom)
            .clamp(0.0, double.infinity)
            .toDouble();
        final openAbove = preferAbove
            ? (spaceAbove >= 200 || spaceAbove >= spaceBelow)
            : !(spaceBelow >= 200 || spaceBelow >= spaceAbove);

        double? top;
        double? bottom;
        final double effectiveMaxHeight;
        if (openAbove) {
          final edgeY = (anchor.top - gap)
              .clamp(minTop + 80.0, safeBottom)
              .toDouble();
          bottom = constraints.maxHeight - edgeY;
          effectiveMaxHeight = math.min(
            maxHeight,
            (edgeY - minTop).clamp(80.0, maxHeight).toDouble(),
          );
        } else {
          final edgeY = (anchor.bottom + gap)
              .clamp(minTop, math.max(minTop, safeBottom - 80.0))
              .toDouble();
          top = edgeY;
          effectiveMaxHeight = math.min(
            maxHeight,
            (safeBottom - edgeY).clamp(80.0, maxHeight).toDouble(),
          );
        }

        final originX = popoverWidth > 0
            ? (((anchor.center.dx - left) / popoverWidth) * 2.0 - 1.0).clamp(
                -1.0,
                1.0,
              )
            : -1.0;
        final originAlignment = Alignment(originX, openAbove ? 1.0 : -1.0);

        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              bottom: bottom,
              width: popoverWidth,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: effectiveMaxHeight),
                child: _buildAnimatedPopover(
                  layoutContext,
                  animation,
                  originAlignment,
                  panelChild,
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}
