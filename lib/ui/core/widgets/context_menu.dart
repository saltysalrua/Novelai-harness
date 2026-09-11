import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_tokens.dart';
import '../theme/theme_context_extensions.dart';
import 'overlay_anchor.dart';

/// 统一上下文手势入口：鼠标右键与触屏长按共用全局坐标回调。
/// 仅注册菜单手势，不接管子组件的点击、双击或拖拽。
class StudioContextMenuRegion extends StatelessWidget {
  final Widget child;
  final ValueChanged<Offset>? onShow;

  const StudioContextMenuRegion({super.key, required this.child, this.onShow});

  @override
  Widget build(BuildContext context) {
    final show = onShow;
    if (show == null) return child;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onSecondaryTapUp: (details) => show(details.globalPosition),
      onLongPressStart: (details) => show(details.globalPosition),
      child: child,
    );
  }
}

/// 上下文菜单条目 (普通项或分隔线)
sealed class ContextMenuAction {
  const ContextMenuAction();
}

/// 可点击菜单项 (onTap 为 null 时置灰)
class ContextMenuItem extends ContextMenuAction {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool isDestructive;

  const ContextMenuItem({
    required this.icon,
    required this.label,
    this.onTap,
    this.isDestructive = false,
  });
}

/// 菜单分隔线
class ContextMenuDivider extends ContextMenuAction {
  const ContextMenuDivider();
}

/// 在指定窗口全局坐标弹出工作台右键菜单 (点击外部、滚轮或 ESC 关闭)。
/// 入参 [position] 传指针事件的 `globalPosition` 即可：内部会经
/// [globalToOverlayPosition] 换算到根 Overlay 布局坐标系，UI 缩放 (Ctrl+=/-)
/// 下依然精准落在点击处。样式沿用应用统一的 Notion 蓝白设计语言。
void showStudioContextMenu(
  BuildContext context, {
  required Offset position,
  required List<ContextMenuAction> actions,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  // 窗口全局坐标 → 根 Overlay 布局坐标 (UI 缩放感知，zoom=1 时恒等)
  final overlayPosition = globalToOverlayPosition(overlay, position);

  final navigator = Navigator.of(context, rootNavigator: true);
  navigator.push(
    _StudioContextMenuRoute(
      position: overlayPosition,
      actions: actions,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    ),
  );
}

/// 菜单独立占一层路由：Android 返回先关闭菜单，不受工作台 PopScope
/// 的 canPop=false 拦截，也不会触发其回退卡片/退出编辑动作。
class _StudioContextMenuRoute extends PopupRoute<void> {
  final Offset position;
  final List<ContextMenuAction> actions;
  final CapturedThemes themes;

  _StudioContextMenuRoute({
    required this.position,
    required this.actions,
    required this.themes,
    required this.barrierLabel,
  });

  @override
  final String barrierLabel;

  @override
  Color? get barrierColor => null;

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
    _ContextMenuOverlay(
      position: position,
      actions: actions,
      onDismiss: () {
        if (isActive) navigator?.removeRoute(this);
      },
    ),
  );
}

class _ContextMenuOverlay extends StatefulWidget {
  final Offset position;
  final List<ContextMenuAction> actions;
  final VoidCallback onDismiss;

  const _ContextMenuOverlay({
    required this.position,
    required this.actions,
    required this.onDismiss,
  });

  @override
  State<_ContextMenuOverlay> createState() => _ContextMenuOverlayState();
}

class _ContextMenuOverlayState extends State<_ContextMenuOverlay> {
  bool _visible = false;

  static const double _menuWidth = 200.0;
  double get _itemHeight => switch (Theme.of(context).platform) {
    TargetPlatform.android || TargetPlatform.iOS => 48.0,
    _ => 34.0,
  };
  static const double _dividerHeight = 9.0;
  static const double _menuPadding = 4.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _visible = true);
    });
  }

  double get _menuHeight {
    final contentHeight = widget.actions
        .map((a) => a is ContextMenuDivider ? _dividerHeight : _itemHeight)
        .fold<double>(0, (sum, h) => sum + h);
    return contentHeight + _menuPadding * 2;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: _buildOverlay);

  Widget _buildOverlay(BuildContext context, BoxConstraints constraints) {
    final padding = MediaQuery.paddingOf(context);
    final insets = MediaQuery.viewInsetsOf(context);
    final minLeft = padding.left + 4;
    final minTop = padding.top + 4;
    final availableWidth = (constraints.maxWidth - minLeft - padding.right - 4)
        .clamp(0.0, double.infinity);
    final availableHeight =
        (constraints.maxHeight - minTop - padding.bottom - insets.bottom - 4)
            .clamp(0.0, double.infinity);
    final menuWidth = _menuWidth.clamp(0.0, availableWidth);
    final menuHeight = _menuHeight.clamp(0.0, availableHeight);
    final left = widget.position.dx.clamp(
      minLeft,
      minLeft + availableWidth - menuWidth,
    );
    final top = widget.position.dy.clamp(
      minTop,
      minTop + availableHeight - menuHeight,
    );

    return Stack(
      children: [
        // 全屏屏障：点击、右键或滚轮任意处关闭菜单
        Positioned.fill(
          child: Focus(
            autofocus: true,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.escape) {
                widget.onDismiss();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Listener(
              onPointerSignal: (_) => widget.onDismiss(),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (_) => widget.onDismiss(),
                onSecondaryTapDown: (_) => widget.onDismiss(),
              ),
            ),
          ),
        ),

        // 菜单本体 (淡入 + 轻微缩放动画)
        Positioned(
          left: left,
          top: top,
          child: AnimatedOpacity(
            opacity: _visible ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
            child: AnimatedScale(
              scale: _visible ? 1.0 : 0.96,
              duration: const Duration(milliseconds: 100),
              curve: Curves.easeOut,
              alignment: Alignment.topLeft,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: menuWidth,
                  constraints: BoxConstraints(maxHeight: menuHeight),
                  padding: const EdgeInsets.all(_menuPadding),
                  decoration: BoxDecoration(
                    color: context.colors.cardBackground,
                    borderRadius: BorderRadius.circular(AppRadius.md + 2),
                    border: Border.all(color: context.colors.borderDefault),
                    boxShadow: context.shadowElevated,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < widget.actions.length; i++)
                          _buildAction(context, widget.actions[i], i),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAction(
    BuildContext context,
    ContextMenuAction action,
    int index,
  ) {
    final colors = context.colors;
    if (action is ContextMenuDivider) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        child: Container(height: 1, color: colors.borderSubtle),
      );
    }
    if (action is ContextMenuItem) {
      final isEnabled = action.onTap != null;
      final isDestructive = action.isDestructive;
      final iconColor = !isEnabled
          ? colors.textMuted
          : (isDestructive ? colors.coral : colors.textSecondary);
      final textColor = !isEnabled
          ? colors.textMuted
          : (isDestructive ? colors.coral : colors.textPrimary);
      final hoverColor = isDestructive
          ? colors.coral.withValues(alpha: 0.08)
          : colors.mutedBackground;

      return InkWell(
        onTap: isEnabled
            ? () {
                widget.onDismiss();
                action.onTap!();
              }
            : null,
        borderRadius: BorderRadius.circular(AppRadius.md - 2),
        hoverColor: hoverColor,
        child: Container(
          height: _itemHeight,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              Icon(action.icon, size: 16, color: iconColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  action.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: textColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
