import 'package:flutter/material.dart';
import 'app_colors_extension.dart';

/// 应用视觉主题与调色板 (Notion 风格暖纸本极简工作台)
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

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: background,
      extensions: const [AppColorsExtension.light],
      colorScheme: ColorScheme.light(
        primary: primary,
        secondary: primaryLight,
        surface: surface,
        surfaceContainerLowest: AppColorsExtension.light.canvasBackground,
        surfaceContainerLow: AppColorsExtension.light.mutedBackground,
        surfaceContainer: AppColorsExtension.light.mutedBackground,
        surfaceContainerHigh: AppColorsExtension.light.elevatedBackground,
        surfaceContainerHighest: AppColorsExtension.light.mutedBackground,
        error: error,
        onPrimary: Colors.white,
        onSurface: textPrimary,
        onSurfaceVariant: AppColorsExtension.light.textSecondary,
      ),
      hoverColor: Colors.transparent,
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: border, width: 1),
          borderRadius: BorderRadius.circular(radiusCard),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: border,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: pureWhite,
        hoverColor: pureWhite,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusButton),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusButton),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusButton),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
        hintStyle: const TextStyle(
          fontFamily: fontFamily,
          color: textMuted,
          fontSize: 13,
        ),
        labelStyle: const TextStyle(fontFamily: fontFamily, fontSize: 12),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: primary,
        inactiveTrackColor: AppColorsExtension.light.mutedBackground,
        thumbColor: primary,
        overlayColor: primary.withValues(alpha: 0.12),
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      ),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontFamily: fontFamily,
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
        titleMedium: TextStyle(
          fontFamily: fontFamily,
          color: textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        bodyMedium: TextStyle(
          fontFamily: fontFamily,
          color: textPrimary,
          fontSize: 13,
          height: 1.45,
        ),
        bodySmall: TextStyle(
          fontFamily: fontFamily,
          color: textSecondary,
          fontSize: 12,
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(borderHover),
        radius: const Radius.circular(radiusSmall),
        thickness: WidgetStateProperty.all(6),
      ),
    );
  }

  /// 真实暗黑主题 (Notion Minimal Dark)
  static ThemeData get darkTheme {
    const darkColors = AppColorsExtension.dark;
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: darkColors.canvasBackground,
      extensions: const [darkColors],
      colorScheme: ColorScheme.dark(
        primary: darkColors.primary,
        secondary: darkColors.primaryLight,
        surface: darkColors.cardBackground,
        // M3 原生组件 (Menu/DatePicker/Dialog) 依赖 surfaceContainer 层级取色，
        // 缺省会回退紫色基底，与 Notion 冷灰风格撕裂
        surfaceContainerLowest: darkColors.canvasBackground,
        surfaceContainerLow: darkColors.cardBackground,
        surfaceContainer: Color(0xFF242424),
        surfaceContainerHigh: darkColors.elevatedBackground,
        surfaceContainerHighest: darkColors.mutedBackground,
        surfaceDim: darkColors.canvasBackground,
        surfaceBright: Color(0xFF2E2E2E),
        error: darkColors.error,
        onPrimary: Colors.white,
        onSurface: darkColors.textPrimary,
        onSurfaceVariant: darkColors.textSecondary,
      ),
      hoverColor: Colors.transparent,
      cardTheme: CardThemeData(
        color: darkColors.cardBackground,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: darkColors.borderDefault, width: 1),
          borderRadius: BorderRadius.circular(radiusCard),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: darkColors.borderDefault,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkColors.cardBackground,
        hoverColor: darkColors.cardBackground,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusButton),
          borderSide: BorderSide(color: darkColors.borderDefault),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusButton),
          borderSide: BorderSide(color: darkColors.borderDefault),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusButton),
          borderSide: BorderSide(color: darkColors.primary, width: 1.5),
        ),
        hintStyle: TextStyle(
          fontFamily: fontFamily,
          color: darkColors.textMuted,
          fontSize: 13,
        ),
        labelStyle: const TextStyle(fontFamily: fontFamily, fontSize: 12),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: darkColors.primary,
        inactiveTrackColor: darkColors.mutedBackground,
        thumbColor: darkColors.primary,
        overlayColor: darkColors.primary.withValues(alpha: 0.12),
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      ),
      textTheme: TextTheme(
        headlineMedium: TextStyle(
          fontFamily: fontFamily,
          color: darkColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
        titleMedium: TextStyle(
          fontFamily: fontFamily,
          color: darkColors.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        bodyMedium: TextStyle(
          fontFamily: fontFamily,
          color: darkColors.textPrimary,
          fontSize: 13,
          height: 1.45,
        ),
        bodySmall: TextStyle(
          fontFamily: fontFamily,
          color: darkColors.textSecondary,
          fontSize: 12,
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(darkColors.borderHover),
        radius: const Radius.circular(radiusSmall),
        thickness: WidgetStateProperty.all(6),
      ),
    );
  }
}
