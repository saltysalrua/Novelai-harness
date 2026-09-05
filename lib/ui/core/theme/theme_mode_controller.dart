import 'package:flutter/material.dart';

import '../../../data/services/config_service.dart';

/// 应用主题模式全局单一事实源 (阶段 3.3 实装)。
///
/// - [StudioViewModel.updateConfig] 在配置保存后调用 [syncFromConfig]；
/// - `main.dart` 根节点用 `ValueListenableBuilder` 监听 [mode] 驱动
///   `MaterialApp.themeMode`，主题切换由 MaterialApp 内建动画平滑过渡，
///   不经过 `notifyListeners()`，零全局重绘；
/// - 控制器完全独立于 StudioViewModel，阶段 4 拆解领域 Controller 时零迁移成本。
///
/// 故意不放在 ViewModel/Mixin 上：主题模式是应用级 (MaterialApp 根) 状态，
/// 生命周期长于任何一个工作台会话。
class AppThemeModeController {
  AppThemeModeController._();

  /// 全局唯一实例 (应用生命周期级别，永不 dispose)
  static final AppThemeModeController instance = AppThemeModeController._();

  /// 当前生效主题模式 (初始亮色，main 启动时会按配置立即校正)
  final ValueNotifier<ThemeMode> mode = ValueNotifier<ThemeMode>(
    ThemeMode.light,
  );

  /// [AppThemeModePreference] (纯 Dart 数据层枚举) → Material [ThemeMode]
  static ThemeMode mapPreference(AppThemeModePreference preference) =>
      switch (preference) {
        AppThemeModePreference.system => ThemeMode.system,
        AppThemeModePreference.light => ThemeMode.light,
        AppThemeModePreference.dark => ThemeMode.dark,
      };

  /// 配置保存/加载后同步主题模式；值未变化时不触发通知。
  void syncFromConfig(AppConfig config) {
    final target = mapPreference(config.themeMode);
    if (mode.value != target) {
      mode.value = target;
    }
  }

  /// 测试辅助：复位为出厂亮色，避免用例间串扰。
  @visibleForTesting
  void resetForTest() {
    mode.value = ThemeMode.light;
  }
}
