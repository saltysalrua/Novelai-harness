import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';
import 'config_service.dart';

/// 桌面端窗口尺寸、坐标与最大化状态监听与防抖持久化服务
class WindowStateService with WindowListener {
  static final WindowStateService instance = WindowStateService._();
  WindowStateService._({ConfigService? configService})
      : _configService = configService ?? ConfigService();

  @visibleForTesting
  WindowStateService.forTesting({required ConfigService configService})
      : this._(configService: configService);

  final ConfigService _configService;
  Timer? _saveTimer;
  Future<void>? _lastSaveFuture;
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  @visibleForTesting
  bool get hasPendingSave => _saveTimer != null && _saveTimer!.isActive;

  @visibleForTesting
  Future<void>? get lastSaveFuture => _lastSaveFuture;

  bool get _isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);

  /// 初始化窗口监听
  void initialize() {
    if (_isInitialized) return;
    _isInitialized = true;
    if (_isDesktop) {
      windowManager.addListener(this);
    }
  }

  /// 销毁监听与计时器
  void dispose() {
    if (_isDesktop) {
      windowManager.removeListener(this);
    }
    _saveTimer?.cancel();
    _saveTimer = null;
    _isInitialized = false;
  }

  /// 调度防抖保存 (500ms 节流)
  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), () {
      saveCurrentState();
    });
  }

  /// 立即冲刷保存 (测试与关闭时调用)
  Future<void> flushPendingSave() async {
    final timer = _saveTimer;
    if (timer != null && timer.isActive) {
      timer.cancel();
      _saveTimer = null;
      await saveCurrentState();
    } else if (_lastSaveFuture != null) {
      await _lastSaveFuture;
    }
  }

  /// 立即获取当前窗口状态并持久化
  Future<void> saveCurrentState() async {
    if (!_isDesktop) return;
    try {
      final isMaximized = await windowManager.isMaximized();
      final isFullScreen = await windowManager.isFullScreen();
      if (isMaximized || isFullScreen) {
        _lastSaveFuture = _configService.saveWindowMaximized(isMaximized);
        await _lastSaveFuture;
        return;
      }
      final size = await windowManager.getSize();
      final pos = await windowManager.getPosition();
      _lastSaveFuture = _configService.saveWindowState(
        width: size.width,
        height: size.height,
        posX: pos.dx,
        posY: pos.dy,
        isMaximized: false,
      );
      await _lastSaveFuture;
    } catch (_) {}
  }

  @override
  void onWindowResize() {
    _scheduleSave();
  }

  @override
  void onWindowResized() {
    _scheduleSave();
  }

  @override
  void onWindowMove() {
    _scheduleSave();
  }

  @override
  void onWindowMoved() {
    _scheduleSave();
  }

  @override
  void onWindowMaximize() {
    _saveTimer?.cancel();
    _saveTimer = null;
    _lastSaveFuture = _configService.saveWindowMaximized(true);
  }

  @override
  void onWindowUnmaximize() {
    _saveTimer?.cancel();
    _saveTimer = null;
    _lastSaveFuture = _configService.saveWindowMaximized(false);
    _scheduleSave();
  }

  @override
  void onWindowRestore() {
    _saveTimer?.cancel();
    _saveTimer = null;
    _lastSaveFuture = _configService.saveWindowMaximized(false);
    _scheduleSave();
  }

  @override
  void onWindowClose() {
    _saveTimer?.cancel();
    _saveTimer = null;
    saveCurrentState();
  }
}
