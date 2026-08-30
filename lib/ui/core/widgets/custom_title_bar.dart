import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import '../../../../data/services/window_state_service.dart';
import '../theme/app_theme.dart';

/// 自定义 Notion 风格工作台标题栏 (支持窗口拖动、双击缩放与三键控制)
class CustomTitleBar extends StatefulWidget implements PreferredSizeWidget {
  const CustomTitleBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(38.0);

  @override
  State<CustomTitleBar> createState() => _CustomTitleBarState();
}

class _CustomTitleBarState extends State<CustomTitleBar> with WindowListener {
  bool _isMaximized = false;

  bool get _isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);

  @override
  void initState() {
    super.initState();
    if (_isDesktop) {
      windowManager.addListener(this);
      _checkMaximized();
    }
  }

  @override
  void dispose() {
    if (_isDesktop) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  Future<void> _checkMaximized() async {
    try {
      final maximized = await windowManager.isMaximized();
      if (mounted) {
        setState(() {
          _isMaximized = maximized;
        });
      }
    } catch (_) {}
  }

  @override
  void onWindowMaximize() {
    if (mounted) {
      setState(() {
        _isMaximized = true;
      });
    }
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) {
      setState(() {
        _isMaximized = false;
      });
    }
  }

  Future<void> _minimize() async {
    if (_isDesktop) {
      try {
        await windowManager.minimize();
      } catch (_) {}
    }
  }

  Future<void> _toggleMaximize() async {
    if (_isDesktop) {
      try {
        final maximized = await windowManager.isMaximized();
        if (maximized) {
          await windowManager.unmaximize();
        } else {
          await windowManager.maximize();
        }
      } catch (_) {}
    }
  }

  Future<void> _close() async {
    if (_isDesktop) {
      try {
        await WindowStateService.instance.saveCurrentState();
        await windowManager.close();
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38.0,
      decoration: const BoxDecoration(
        color: AppTheme.paperWarmth,
        border: Border(
          bottom: BorderSide(color: AppTheme.border, width: 1),
        ),
      ),
      child: Row(
        children: [
          // 左侧：可拖动区域包裹的应用 Logo 与标题
          _buildDraggableArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.auto_awesome_rounded,
                    size: 16,
                    color: AppTheme.primary,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'NovelAI Harness',
                    style: TextStyle(
                      fontFamily: AppTheme.fontFamily,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 中间：占据全部剩余空间的窗口拖拽区域（支持双击最大化/向下还原）
          Expanded(
            child: _buildDraggableArea(
              child: const SizedBox.expand(),
            ),
          ),

          // 右侧：窗口控制三键 (最小化、最大化/向下还原、关闭)
          if (_isDesktop) ...[
            _WindowButton(
              icon: Icons.remove,
              iconSize: 14,
              tooltip: '最小化',
              onPressed: _minimize,
            ),
            _WindowButton(
              icon: _isMaximized ? Icons.filter_none_rounded : Icons.crop_square_rounded,
              iconSize: _isMaximized ? 11 : 13,
              tooltip: _isMaximized ? '向下还原' : '最大化',
              onPressed: _toggleMaximize,
            ),
            _WindowButton(
              icon: Icons.close_rounded,
              iconSize: 15,
              tooltip: '关闭',
              isClose: true,
              onPressed: _close,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDraggableArea({required Widget child}) {
    if (_isDesktop) {
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onDoubleTap: _toggleMaximize,
        child: DragToMoveArea(child: child),
      );
    }
    return child;
  }
}

/// 窗口控制按钮组件 (带原生平滑 Hover 动效，关闭键支持红底警示)
class _WindowButton extends StatefulWidget {
  final IconData icon;
  final double iconSize;
  final String tooltip;
  final bool isClose;
  final VoidCallback onPressed;

  const _WindowButton({
    required this.icon,
    required this.iconSize,
    required this.tooltip,
    this.isClose = false,
    required this.onPressed,
  });

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    Color backgroundColor = Colors.transparent;
    Color iconColor = AppTheme.textSecondary;

    if (_isHovered) {
      if (widget.isClose) {
        backgroundColor = const Color(0xFFE81123);
        iconColor = Colors.white;
      } else {
        backgroundColor = AppTheme.borderHover;
        iconColor = AppTheme.textPrimary;
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
            width: 44,
            height: 38,
            color: backgroundColor,
            alignment: Alignment.center,
            child: Icon(
              widget.icon,
              size: widget.iconSize,
              color: iconColor,
            ),
          ),
        ),
      ),
    );
  }
}
