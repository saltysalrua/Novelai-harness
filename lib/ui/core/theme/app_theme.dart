import 'package:flutter/material.dart';
import '../../../data/services/config_service.dart';
import 'app_accent_controller.dart';
import 'app_colors_extension.dart';
import 'app_motion.dart';
import 'app_tokens.dart';
import 'md3_accent.dart';

/// 应用视觉主题与调色板 (Notion 风格暖纸本极简工作台)
///
/// 主题在默认状态下使用 Notion 原生色板；当用户启用 MD3 自适应取色
/// (图片主色/手动种子色) 时，仅强调色族 token (primary/primaryLight/
/// primaryDark/primaryTint/borderFocus/accent) 替换为 DynamicScheme 推导值，
/// 中性色 (背景层级/文字/边框) 保持 Notion 观感，避免整站洗色。
class AppTheme {
  // --- 基础色板 Tokens (Notion Style) ---
  static const Color paperWarmth = Color(0xFFF6F5F4); // Page canvas / 暖纸底色
  static const Color pureWhite = Color(0xFFFFFFFF); // Card surfaces / 纯白卡片
  static const Color notionBlue = Color(0xFF0075DE); // Primary CTA fill / 核心操作蓝
  static const Color skyTint = Color(0xFFE6F3FE); // Ghost CTA bg / 浅蓝底
  static const Color signalBlue = Color(0xFF097FE8);
  static const Color skyWash = Color(0xFF62AEF0);
  static const Color midnightInk = Color(0xFF02093A);

  static const Color inkBlack = Color(0xFF000000);
  static const Color charcoal = Color(0xFF111111);
  static const Color graphite = Color(0xFF615D59);
  static const Color slate = Color(0xFF696969);
  static const Color stone = Color(0xFF757575);

  static const Color marigold = Color(0xFFFFB110);
  static const Color coral = Color(0xFFF64932);
  static const Color saffron = Color(0xFFE89D01);
  static const Color vermillion = Color(0xFFE32D14);
  static const Color mocha = Color(0xFFB18164);

  static const Color success = Color(0xFF0F9960);
  static const Color warning = Color(0xFFD9822B);
  static const Color error = Color(0xFFDB3737);
  static const Color info = Color(0xFF0075DE);

  // --- 语义映射 ---
  static const Color background = paperWarmth;
  static const Color surface = pureWhite;
  static const Color surfaceElevated = Color(0xFFFAFAF9);
  static const Color surfaceMuted = Color(0xFFF0EFEB);
  static const Color surfaceVariant = paperWarmth;
  static const Color border = Color(
    0x14000000,
  ); // 1px hairline border (rgba(0,0,0,0.08))
  static const Color borderSubtle = Color(0x0A000000);
  static const Color borderHover = Color(0x26000000);

  static const Color primary = notionBlue;
  static const Color accent = notionBlue;
  static const Color primaryLight = skyWash;
  static const Color primaryDark = signalBlue;
  static const Color primaryTint = skyTint;

  static const Color textPrimary = charcoal;
  static const Color textSecondary = graphite;
  static const Color textMuted = stone;

  // --- 圆角规范 ---
  static const double radiusSmall = 4.0;
  static const double radiusButton = 8.0;
  static const double radiusCard = 12.0;
  static const double radiusPill = 9999.0;

  static const String fontFamily = 'MiSans';

  /// 默认亮色主题 (Notion 暖纸本)
  static ThemeData get lightTheme => buildTheme(Brightness.light);

  /// 默认暗色主题 (Notion Minimal Dark)
  static ThemeData get darkTheme => buildTheme(Brightness.dark);

  /// 按当前强调色状态构建亮色主题 (main.dart 根节点监听调用)；
  /// [accent] 为 null 或种子色为空时回落 Notion 原生色板。
  static ThemeData lightThemeFor(AccentThemeState? accent) =>
      _buildAccent(Brightness.light, accent);

  /// 按当前强调色状态构建暗色主题
  static ThemeData darkThemeFor(AccentThemeState? accent) =>
      _buildAccent(Brightness.dark, accent);

  static ThemeData _buildAccent(
    Brightness brightness,
    AccentThemeState? accent,
  ) {
    final isDark = brightness == Brightness.dark;
    return buildTheme(
      brightness,
      // 防御兜底：默认蓝模式一律忽略种子 (即使种子意外残留也不注入)，
      // 保证切回默认后必然恢复原生 Notion 蓝
      seed: accent != null && accent.mode == AppAccentMode.defaultBlue
          ? null
          : accent?.seed,
      variant: accent?.variant ?? AppAccentVariant.tonalSpot,
      backgroundMode:
          accent?.backgroundMode ?? AppBackgroundMode.defaultNotion,
      customBackground: isDark
          ? accent?.customDarkBackground
          : accent?.customLightBackground,
    );
  }

  /// 通用主题构建：支持背景层级定制 (默认 Notion / 跟随强调色微染 / 自定义背景)
  /// 与 HCT 护眼 MD3 强调色令牌推导注入。
  static ThemeData buildTheme(
    Brightness brightness, {
    Color? seed,
    AppAccentVariant variant = AppAccentVariant.tonalSpot,
    AppBackgroundMode backgroundMode = AppBackgroundMode.defaultNotion,
    Color? customBackground,
  }) {
    final isDark = brightness == Brightness.dark;
    final baseColors = isDark
        ? AppColorsExtension.dark
        : AppColorsExtension.light;
    final AppSurfaceTokens? surfaceTokens = buildSurfaceTokens(
      brightness: brightness,
      mode: backgroundMode,
      customColor: customBackground,
      accentSeed: seed,
      accentVariant: variant,
    );
    final surfacedColors = _applySurfaceTokens(baseColors, surfaceTokens);
    final bool effectiveDark = surfaceTokens?.isDarkSurface ?? isDark;
    final M3AccentTokens? tokens = seed == null
        ? null
        : buildM3AccentTokens(
            seed: seed,
            brightness: effectiveDark ? Brightness.dark : Brightness.light,
            variant: variant,
            surfaceColor: surfacedColors.cardBackground,
          );
    final colors = _applyAccentTokens(
      surfacedColors,
      tokens,
      harmonizeDefaultTint: surfaceTokens != null,
      isDarkSurface: effectiveDark,
    );

    final Color darkContainerMid =
        Color.lerp(colors.cardBackground, colors.elevatedBackground, 0.5) ??
        colors.elevatedBackground;
    final Color darkSurfaceBright =
        Color.lerp(colors.mutedBackground, Colors.white, 0.06) ??
        colors.mutedBackground;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: colors.canvasBackground,
      extensions: [colors],
      colorScheme: isDark
          ? ColorScheme.dark(
              primary: colors.primary,
              secondary: colors.primaryLight,
              surface: colors.cardBackground,
              // M3 原生组件 (Menu/DatePicker/Dialog) 依赖 surfaceContainer 层级取色，
              // 缺省会回退紫色基底，这里与当前自定义/动态表面层级完全对齐
              surfaceContainerLowest: colors.canvasBackground,
              surfaceContainerLow: colors.cardBackground,
              surfaceContainer: darkContainerMid,
              surfaceContainerHigh: colors.elevatedBackground,
              surfaceContainerHighest: colors.mutedBackground,
              surfaceDim: colors.canvasBackground,
              surfaceBright: darkSurfaceBright,
              error: colors.error,
              onPrimary: colors.onPrimary,
              onSurface: colors.textPrimary,
              onSurfaceVariant: colors.textSecondary,
            )
          : ColorScheme.light(
              primary: colors.primary,
              secondary: colors.primaryLight,
              surface: colors.cardBackground,
              surfaceContainerLowest: colors.canvasBackground,
              surfaceContainerLow: colors.mutedBackground,
              surfaceContainer: colors.mutedBackground,
              surfaceContainerHigh: colors.elevatedBackground,
              surfaceContainerHighest: colors.mutedBackground,
              error: colors.error,
              onPrimary: colors.onPrimary,
              onSurface: colors.textPrimary,
              onSurfaceVariant: colors.textSecondary,
            ),
      hoverColor: Colors.transparent,
      cardTheme: CardThemeData(
        color: colors.cardBackground,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: colors.borderDefault, width: 1),
          borderRadius: BorderRadius.circular(radiusCard),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colors.borderDefault,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.cardBackground,
        hoverColor: colors.cardBackground,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusButton),
          borderSide: BorderSide(color: colors.borderDefault),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusButton),
          borderSide: BorderSide(color: colors.borderDefault),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusButton),
          borderSide: BorderSide(color: colors.primary, width: 1.5),
        ),
        hintStyle: TextStyle(
          fontFamily: fontFamily,
          color: colors.textMuted,
          fontSize: 13,
        ),
        labelStyle: const TextStyle(fontFamily: fontFamily, fontSize: 12),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: colors.primary,
        inactiveTrackColor: colors.mutedBackground,
        thumbColor: colors.primary,
        overlayColor: colors.primary.withValues(alpha: 0.12),
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      ),
      textTheme: TextTheme(
        headlineMedium: TextStyle(
          fontFamily: fontFamily,
          color: colors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
        titleMedium: TextStyle(
          fontFamily: fontFamily,
          color: colors.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        bodyMedium: TextStyle(
          fontFamily: fontFamily,
          color: colors.textPrimary,
          fontSize: 13,
          height: 1.45,
        ),
        bodySmall: TextStyle(
          fontFamily: fontFamily,
          color: colors.textSecondary,
          fontSize: 12,
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(colors.borderHover),
        radius: const Radius.circular(radiusSmall),
        thickness: WidgetStateProperty.all(6),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: AppMotionDurations.tooltipDelay,
        exitDuration: AppMotionDurations.tooltipOut,
        showDuration: const Duration(milliseconds: 1600),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        textStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 12,
          color: effectiveDark ? colors.textPrimary : colors.cardBackground,
        ),
        decoration: BoxDecoration(
          color: effectiveDark ? colors.elevatedBackground : colors.textPrimary,
          borderRadius: BorderRadius.circular(radiusButton),
          border: effectiveDark
              ? Border.all(color: colors.borderDefault)
              : null,
          boxShadow: AppShadows.elevated(
            Colors.black,
            brightness: effectiveDark ? Brightness.dark : Brightness.light,
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.cardBackground,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
          side: BorderSide(color: colors.borderDefault),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.windows: _AppPageTransitionsBuilder(),
          TargetPlatform.macOS: _AppPageTransitionsBuilder(),
          TargetPlatform.linux: _AppPageTransitionsBuilder(),
          TargetPlatform.android: _AppPageTransitionsBuilder(),
          TargetPlatform.iOS: _AppPageTransitionsBuilder(),
        },
      ),
    );
  }

  /// 将背景与中性层级令牌覆盖到基础色板
  static AppColorsExtension _applySurfaceTokens(
    AppColorsExtension base,
    AppSurfaceTokens? tokens,
  ) {
    if (tokens == null) return base;
    return base.copyWith(
          canvasBackground: tokens.canvasBackground,
          cardBackground: tokens.cardBackground,
          elevatedBackground: tokens.elevatedBackground,
          mutedBackground: tokens.mutedBackground,
          borderSubtle: tokens.borderSubtle,
          borderDefault: tokens.borderDefault,
          borderHover: tokens.borderHover,
          textPrimary: tokens.textPrimary,
          textSecondary: tokens.textSecondary,
          textMuted: tokens.textMuted,
        )
        as AppColorsExtension;
  }

  /// 将护眼 MD3 强调色令牌覆盖到色板；自定义/微染背景下的默认蓝也同步融合 primaryTint
  static AppColorsExtension _applyAccentTokens(
    AppColorsExtension base,
    M3AccentTokens? tokens, {
    bool harmonizeDefaultTint = false,
    bool isDarkSurface = false,
  }) {
    if (tokens == null) {
      if (!harmonizeDefaultTint) return base;
      return base.copyWith(
            primaryTint: Color.alphaBlend(
              base.primary.withValues(alpha: isDarkSurface ? 0.14 : 0.10),
              base.cardBackground,
            ),
          )
          as AppColorsExtension;
    }
    return base.copyWith(
          primary: tokens.primary,
          onPrimary: tokens.onPrimary,
          primaryLight: tokens.primaryLight,
          primaryDark: tokens.primaryDark,
          primaryTint: tokens.primaryTint,
          accent: tokens.primary,
          borderFocus: tokens.primary,
        )
        as AppColorsExtension;
  }
}

/// 统一平滑页面过渡构建器 (`08-page-side-by-side` 轻量位移 + 淡入)
class _AppPageTransitionsBuilder extends PageTransitionsBuilder {
  const _AppPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (AppMotion.shouldReduceMotion(context)) {
      return child;
    }
    return AnimatedBuilder(
      animation: animation,
      builder: (context, innerChild) {
        final t = AppMotionCurves.smoothOut
            .transform(animation.value)
            .clamp(0.0, 1.0);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(AppMotionDistances.base * (1.0 - t), 0),
            child: innerChild,
          ),
        );
      },
      child: child,
    );
  }
}
