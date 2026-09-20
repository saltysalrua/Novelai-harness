import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import '../../../data/services/window_state_service.dart';

/// 桌面窗口控制 (窗口移动 / 双击最大化 / 最小化、最大化、关闭) 共用状态机。
///
/// 宽屏标题栏 [CustomTitleBar] 与窄屏顶部胶囊条 (_MobileTopBar) 共用同一份
/// `windowManager` 监听、最大化判态与三键动作，避免两处各写一套导致行为漂移。
abstract class WindowControlsState<T extends StatefulWidget> extends State<T>
    with WindowListener {
  bool _windowIsMaximized = false;

  /// 当前窗口是否最大化 (驱动最大化/还原按钮图标)
  bool get windowIsMaximized => _windowIsMaximized;

  bool get usesNativeWindowControls =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  bool get showCustomWindowControls =>
      isDesktopWindow && !usesNativeWindowControls;

  /// 是否为桌面平台 (移动端不提供窗口三键与拖拽区)
  bool get isDesktopWindow =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);

  @override
  void initState() {
    super.initState();
    if (isDesktopWindow) {
      windowManager.addListener(this);
      _syncWindowMaximized();
    }
  }

  @override
  void dispose() {
    if (isDesktopWindow) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  Future<void> _syncWindowMaximized() async {
    try {
      final maximized = await windowManager.isMaximized();
      if (mounted) setState(() => _windowIsMaximized = maximized);
    } catch (_) {}
  }

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _windowIsMaximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _windowIsMaximized = false);
  }

  /// 最小化窗口
  Future<void> minimizeWindow() async {
    if (!isDesktopWindow) return;
    try {
      await windowManager.minimize();
    } catch (_) {}
  }

  /// 最大化 / 向下还原
  Future<void> toggleMaximizeWindow() async {
    if (!isDesktopWindow) return;
    try {
      final maximized = await windowManager.isMaximized();
      if (maximized) {
        await windowManager.unmaximize();
      } else {
        await windowManager.maximize();
      }
    } catch (_) {}
  }

  /// 关闭窗口 (经 [WindowStateService] 统一等待参数/会话等待落盘状态)
  Future<void> closeAppWindow() async {
    if (!isDesktopWindow) return;
    try {
      await WindowStateService.instance.closeWindow();
    } catch (_) {}
  }

  /// 窗口拖拽区：桌面端可拖动移动 + 双击最大化；移动端原样返回
  Widget buildWindowDragArea({required Widget child}) {
    if (!isDesktopWindow) return child;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onDoubleTap: toggleMaximizeWindow,
      child: DragToMoveArea(child: child),
    );
  }
}
