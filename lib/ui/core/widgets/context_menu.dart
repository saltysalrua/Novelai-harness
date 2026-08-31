import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

/// 右键菜单条目 (普通项或分隔线)
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

/// 在指定全局坐标弹出工作台右键菜单 (点击外部、滚轮或 ESC 关闭)。
/// 样式沿用应用统一的 Notion 蓝白设计语言。
void showStudioContextMenu(
  BuildContext context, {
  required Offset position,
  required List<ContextMenuAction> actions,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  late final OverlayEntry entry;
  var removed = false;
  void dismiss() {
    if (removed) return;
    removed = true;
    if (entry.mounted) entry.remove();
  }

  entry = OverlayEntry(
    builder: (_) => _ContextMenuOverlay(
      position: position,
      actions: actions,
      onDismiss: dismiss,
    ),
  );
  overlay.insert(entry);
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

  static const double _menuWidth = 176.0;
  static const double _itemHeight = 34.0;
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
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final left = widget.position.dx.clamp(
      4.0,
      (screenSize.width - _menuWidth - 4.0).clamp(4.0, double.infinity),
    );
    final top = widget.position.dy.clamp(
      4.0,
      (screenSize.height - _menuHeight - 4.0).clamp(4.0, double.infinity),
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
                  width: _menuWidth,
                  padding: const EdgeInsets.all(_menuPadding),
                  decoration: BoxDecoration(
                    color: AppTheme.pureWhite,
                    borderRadius: BorderRadius.circular(
                      AppTheme.radiusButton + 2,
                    ),
                    border: Border.all(color: AppTheme.border),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < widget.actions.length; i++)
                        _buildAction(widget.actions[i], i),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAction(ContextMenuAction action, int index) {
    if (action is ContextMenuDivider) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        child: Container(height: 1, color: AppTheme.border),
      );
    }
    if (action is ContextMenuItem) {
      final isEnabled = action.onTap != null;
      final isDestructive = action.isDestructive;
      final iconColor = !isEnabled
          ? AppTheme.stone
          : (isDestructive ? AppTheme.coral : AppTheme.textSecondary);
      final textColor = !isEnabled
          ? AppTheme.stone
          : (isDestructive ? AppTheme.coral : AppTheme.textPrimary);
      final hoverColor = isDestructive
          ? AppTheme.coral.withValues(alpha: 0.08)
          : AppTheme.surfaceMuted;

      return InkWell(
        onTap: isEnabled
            ? () {
                widget.onDismiss();
                action.onTap!();
              }
            : null,
        borderRadius: BorderRadius.circular(6),
        hoverColor: hoverColor,
        child: Container(
          height: _itemHeight,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              Icon(
                action.icon,
                size: 16,
                color: iconColor,
              ),
              const SizedBox(width: 10),
              Text(
                action.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: textColor,
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
