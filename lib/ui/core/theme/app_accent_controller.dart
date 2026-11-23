import 'package:flutter/material.dart';

import '../../../data/services/config_service.dart';

/// 应用主题强调色全局单一事实源 (MD3 自适应取色)。
///
/// - 持有三段运行时状态：来源模式 / 取色方案 / 当前种子色 (null = 默认 Notion 蓝)；
/// - [StudioViewModel.updateConfig] 保存配置后调用 [syncFromConfig]；
/// - 自适应模式下 ViewModel 在选图/生图后调用 [applyAdaptiveSeed] 注入图片主色；
/// - `main.dart` 根节点监听 [state] 局部重建 `MaterialApp.theme/darkTheme`，
///   主题切换由 MaterialApp 内建 200ms 动画平滑过渡，不经过 `notifyListeners()`。
///
/// 故意不放在 ViewModel/Mixin 上：强调色是应用级 (MaterialApp 根) 状态，
/// 生命周期长于任何一个工作台会话 (与 AppThemeModeController 同构)。
@immutable
class AccentThemeState {
  /// 来源模式
  final AppAccentMode mode;

  /// MD3 取色方案
  final AppAccentVariant variant;

  /// 当前种子色 (null = 默认 Notion 蓝，不注入)
  final Color? seed;

  /// 背景色来源模式 (默认 Notion / 跟随强调色微染 / 自定义背景色)
  final AppBackgroundMode backgroundMode;

  /// 自定义亮色画布背景色 (null = 默认暖纸)
  final Color? customLightBackground;

  /// 自定义深色画布背景色 (null = 默认暗灰)
  final Color? customDarkBackground;

  const AccentThemeState({
    required this.mode,
    required this.variant,
    this.seed,
    this.backgroundMode = AppBackgroundMode.defaultNotion,
    this.customLightBackground,
    this.customDarkBackground,
  });

  bool get isAdaptive => mode == AppAccentMode.adaptive;

  /// 种子或方案变化才视为状态变化 (mode 变化但种子未定不触发重建)
  AccentThemeState copyWith({
    Color? seed,
    AppAccentVariant? variant,
    AppBackgroundMode? backgroundMode,
    Color? customLightBackground,
    Color? customDarkBackground,
  }) => AccentThemeState(
    mode: mode,
    variant: variant ?? this.variant,
    seed: seed ?? this.seed,
    backgroundMode: backgroundMode ?? this.backgroundMode,
    customLightBackground: customLightBackground ?? this.customLightBackground,
    customDarkBackground: customDarkBackground ?? this.customDarkBackground,
  );

  @override
  bool operator ==(Object other) =>
      other is AccentThemeState &&
      other.mode == mode &&
      other.variant == variant &&
      other.seed?.toARGB32() == seed?.toARGB32() &&
      other.backgroundMode == backgroundMode &&
      other.customLightBackground?.toARGB32() ==
          customLightBackground?.toARGB32() &&
      other.customDarkBackground?.toARGB32() ==
          customDarkBackground?.toARGB32();

  @override
  int get hashCode => Object.hash(
    mode,
    variant,
    seed?.toARGB32(),
    backgroundMode,
    customLightBackground?.toARGB32(),
    customDarkBackground?.toARGB32(),
  );
}

class AppAccentController {
  AppAccentController._();

  /// 全局唯一实例 (应用生命周期级别，永不 dispose)
  static final AppAccentController instance = AppAccentController._();

  /// 当前生效的强调色与背景色状态 (初始默认蓝 + Notion 背景，main 启动时会按配置立即校正)
  final ValueNotifier<AccentThemeState> state = ValueNotifier(
    const AccentThemeState(
      mode: AppAccentMode.defaultBlue,
      variant: AppAccentVariant.tonalSpot,
    ),
  );

  /// 配置保存/加载后同步；仅状态真正变化时通知。
  void syncFromConfig(AppConfig config) {
    final seedArgb = parseSeedColorText(config.accentSeedColor);
    final lightBgArgb = parseSeedColorText(config.customLightBackgroundColor);
    final darkBgArgb = parseSeedColorText(config.customDarkBackgroundColor);
    final lightBg = lightBgArgb == null ? null : Color(lightBgArgb);
    final darkBg = darkBgArgb == null ? null : Color(darkBgArgb);

    // 自适应模式保留运行时已提取的种子 (配置里没有“当前图片色”)，
    // 只同步方案与背景色配置变化
    if (config.accentMode == AppAccentMode.adaptive) {
      final current = state.value;
      final target = AccentThemeState(
        mode: AppAccentMode.adaptive,
        variant: config.accentVariant,
        seed: current.isAdaptive ? current.seed : null,
        backgroundMode: config.backgroundMode,
        customLightBackground: lightBg,
        customDarkBackground: darkBg,
      );
      if (current != target) {
        state.value = target;
      }
      return;
    }

    final target = AccentThemeState(
      mode: config.accentMode,
      variant: config.accentVariant,
      // 默认蓝模式必须忽略持久化的旧种子：
      // 否则切回默认后旧种子仍被注入，看起来“切不回去”
      seed: config.accentMode == AppAccentMode.defaultBlue || seedArgb == null
          ? null
          : Color(seedArgb),
      backgroundMode: config.backgroundMode,
      customLightBackground: lightBg,
      customDarkBackground: darkBg,
    );
    if (state.value != target) {
      state.value = target;
    }
  }

  /// 自适应模式：注入从当前图片提取的种子色 (非自适应模式忽略)
  void applyAdaptiveSeed(Color seed) {
    final current = state.value;
    if (!current.isAdaptive) return;
    if (current.seed?.toARGB32() == seed.toARGB32()) return;
    state.value = AccentThemeState(
      mode: current.mode,
      variant: current.variant,
      seed: seed,
      backgroundMode: current.backgroundMode,
      customLightBackground: current.customLightBackground,
      customDarkBackground: current.customDarkBackground,
    );
  }

  /// 手动模式：立即应用种子色 (持久化由调用方经 updateConfig 落盘)
  void applyManualSeed(Color seed) {
    final current = state.value;
    state.value = AccentThemeState(
      mode: AppAccentMode.manual,
      variant: current.variant,
      seed: seed,
      backgroundMode: current.backgroundMode,
      customLightBackground: current.customLightBackground,
      customDarkBackground: current.customDarkBackground,
    );
  }

  /// 测试辅助：复位为出厂默认蓝
  @visibleForTesting
  void resetForTest() {
    state.value = const AccentThemeState(
      mode: AppAccentMode.defaultBlue,
      variant: AppAccentVariant.tonalSpot,
    );
  }
}
