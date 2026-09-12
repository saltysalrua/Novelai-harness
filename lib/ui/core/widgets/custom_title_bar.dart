import 'package:flutter/material.dart';
import '../context_l10n.dart';
import '../theme/app_theme.dart';
import '../theme/theme_context_extensions.dart';
import 'window_controls.dart';

/// 自定义 Notion 风格工作台标题栏 (支持窗口拖动、双击缩放与三键控制)
class CustomTitleBar extends StatefulWidget implements PreferredSizeWidget {
  const CustomTitleBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(38.0);

  @override
  State<CustomTitleBar> createState() => _CustomTitleBarState();
}

class _CustomTitleBarState extends WindowControlsState<CustomTitleBar> {
  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    return Container(
      height: 38.0,
      decoration: BoxDecoration(
        color: colors.canvasBackground,
        border: Border(
          bottom: BorderSide(color: colors.borderDefault, width: 1),
        ),
      ),
      child: Row(
        children: [
          // 左侧：可拖动区域包裹的应用 Logo 与标题
          buildWindowDragArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.auto_awesome_rounded,
                    size: 16,
                    color: colors.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'NovelAI Harness',
                    style: TextStyle(
                      fontFamily: AppTheme.fontFamily,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 中间：占据全部剩余空间的窗口拖拽区域（支持双击最大化/向下还原）
          Expanded(child: buildWindowDragArea(child: const SizedBox.expand())),

          // 右侧：窗口控制三键 (最小化、最大化/向下还原、关闭)
          if (isDesktopWindow) ...[
            AppWindowButton(
              icon: Icons.remove,
              iconSize: 14,
              tooltip: l10n.windowMinimize,
              onPressed: minimizeWindow,
            ),
            AppWindowButton(
              icon: windowIsMaximized
                  ? Icons.filter_none_rounded
                  : Icons.crop_square_rounded,
              iconSize: windowIsMaximized ? 11 : 13,
              tooltip: windowIsMaximized
                  ? l10n.windowRestore
                  : l10n.windowMaximize,
              onPressed: toggleMaximizeWindow,
            ),
            AppWindowButton(
              icon: Icons.close_rounded,
              iconSize: 15,
              tooltip: l10n.close,
              isClose: true,
              onPressed: closeAppWindow,
            ),
          ],
        ],
      ),
    );
  }
}

/// 窗口控制按钮组件 (带原生平滑 Hover 动效，关闭键支持红底警示)
class AppWindowButton extends StatefulWidget {
  final IconData icon;
  final double iconSize;
  final String tooltip;
  final bool isClose;
  final VoidCallback onPressed;
  final double width;
  final double height;

  const AppWindowButton({
    super.key,
    required this.icon,
    required this.iconSize,
    required this.tooltip,
    this.isClose = false,
    required this.onPressed,
    this.width = 44,
    this.height = 38,
  });

  @override
  State<AppWindowButton> createState() => _AppWindowButtonState();
}

class _AppWindowButtonState extends State<AppWindowButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    Color backgroundColor = Colors.transparent;
    Color iconColor = colors.textSecondary;

    if (_isHovered) {
      if (widget.isClose) {
        backgroundColor = const Color(0xFFE81123);
        iconColor = Colors.white;
      } else {
        backgroundColor = colors.borderHover;
        iconColor = colors.textPrimary;
      }
    }

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: Container(
            width: widget.width,
            height: widget.height,
            color: backgroundColor,
            alignment: Alignment.center,
            child: Icon(widget.icon, size: widget.iconSize, color: iconColor),
          ),
        ),
      ),
    );
  }
}
