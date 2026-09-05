import 'package:flutter/widgets.dart';

import '../../../data/services/config_service.dart';

/// 应用语言全局单一事实源 (阶段 4A 实装)。
///
/// - [StudioViewModel.updateConfig] 在配置保存后调用 [syncFromConfig]；
/// - `main.dart` 根节点用 `ValueListenableBuilder` 监听 [locale] 驱动
///   `MaterialApp.locale`，语言切换只重建 Localizations 层，零全局重绘；
/// - 控制器完全独立于 StudioViewModel，阶段 4 拆解领域 Controller 时零迁移成本。
///
/// 故意不放在 ViewModel/Mixin 上：语言是应用级 (MaterialApp 根) 状态，
/// 生命周期长于任何一个工作台会话。
///
/// 现阶段为阶段 4A 试点：仅设置页文案接入 AppLocalizations，
/// 其余界面随 4B 分模块逐步迁移；未接入区域不受本控制器影响。
class AppLocaleController {
  AppLocaleController._();

  /// 全局唯一实例 (应用生命周期级别，永不 dispose)
  static final AppLocaleController instance = AppLocaleController._();

  /// 当前生效 locale；null = 跟随系统 (交由 MaterialApp 解析)
  final ValueNotifier<Locale?> locale = ValueNotifier<Locale?>(null);

  /// [AppLocalePreference] (纯 Dart 数据层枚举) → Flutter [Locale]
  static Locale? mapPreference(AppLocalePreference preference) =>
      switch (preference) {
        AppLocalePreference.system => null,
        AppLocalePreference.zh => const Locale('zh'),
        AppLocalePreference.en => const Locale('en'),
      };

  /// 配置保存/加载后同步语言；值未变化时不触发通知。
  void syncFromConfig(AppConfig config) {
    final target = mapPreference(config.localePreference);
    if (locale.value != target) {
      locale.value = target;
    }
  }

  /// 测试辅助：复位为跟随系统，避免用例间串扰。
  @visibleForTesting
  void resetForTest() {
    locale.value = null;
  }
}
