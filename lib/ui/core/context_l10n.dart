import 'package:flutter/widgets.dart';

import '../../l10n/app_localizations.dart';

/// 便捷取词扩展：`context.l10n.settingsThemeMode`
///
/// l10n.yaml 配置 nullable-getter: false —— delegates 未挂载时
/// [AppLocalizations.of] 直接抛错 (fail fast)，避免静默回退到错误语言。
extension ContextL10n on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);

  /// 安全取词扩展：delegates 未挂载时返回 null (适用于原子组件容错 fallback)
  AppLocalizations? get maybeL10n =>
      Localizations.of<AppLocalizations>(this, AppLocalizations);
}
