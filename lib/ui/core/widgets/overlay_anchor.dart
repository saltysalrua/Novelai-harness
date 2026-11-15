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

/// 在触发组件附近弹出轻浮层：自动对齐触发区域左右/上下方向并约束在可见安全区内，
/// 点击外部或按 Esc 即可关闭；桌面多栏下不会跑偏到屏幕正中央遮挡画布。
Future<T?> showAnchoredPopover<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  double maxWidth = 360,
  double maxHeight = 420,
  double gap = 8,
  double viewportMargin = 8,
  bool preferAbove = true,
}) {
  final navigator = Navigator.of(context, rootNavigator: true);
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  final renderObject = context.findRenderObject();
  Rect? anchorRect;
  if (renderObject is RenderBox && renderObject.hasSize) {
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
    anchorRect = Rect.fromPoints(topLeft, bottomRight);
  }

  final themes = InheritedTheme.capture(from: context, to: navigator.context);
  final barrierLabel = MaterialLocalizations.of(
    context,
  ).modalBarrierDismissLabel;

  return navigator.push<T>(
    _AnchoredPopoverRoute<T>(
      anchorRect: anchorRect,
      builder: builder,
      themes: themes,
      barrierLabel: barrierLabel,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      gap: gap,
      viewportMargin: viewportMargin,
      preferAbove: preferAbove,
    ),
  );
}

class _AnchoredPopoverRoute<T> extends PopupRoute<T> {
  final Rect? anchorRect;
  final WidgetBuilder builder;
  final CapturedThemes themes;
  final double maxWidth;
  final double maxHeight;
  final double gap;
  final double viewportMargin;
  final bool preferAbove;

  _AnchoredPopoverRoute({
    required this.anchorRect,
    required this.builder,
    required this.themes,
    required this.barrierLabel,
    required this.maxWidth,
    required this.maxHeight,
    required this.gap,
    required this.viewportMargin,
    required this.preferAbove,
  });

  @override
  final String barrierLabel;

  @override
  Color? get barrierColor => Colors.transparent;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration => Duration.zero;

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
        final popoverWidth = math.min(maxWidth, availableWidth);

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
              child: builder(layoutContext),
            ),
          ),
        );

        final anchor = anchorRect;
        if (anchor == null) {
          final fallbackHeight = math.min(maxHeight, totalAvailableHeight);
          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: popoverWidth,
                maxHeight: fallbackHeight,
              ),
              child: panelChild,
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

        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              bottom: bottom,
              width: popoverWidth,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: effectiveMaxHeight),
                child: panelChild,
              ),
            ),
          ],
        );
      },
    ),
  );
}
