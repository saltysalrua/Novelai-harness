import 'package:flutter/material.dart';

/// 应用语义色彩设计令牌 (ThemeExtension 体系)
///
/// 统一管理界面的背景层级、边框、文字、强调色及业务状态色彩，
/// 支持 Light (Notion Warm Paper) 与 Dark (Notion Minimal Dark) 的平滑过渡。
@immutable
class AppColorsExtension extends ThemeExtension<AppColorsExtension> {
  // --- 背景层级 ---
  final Color canvasBackground;
  final Color cardBackground;
  final Color elevatedBackground;
  final Color mutedBackground;

  // --- 边框层级 ---
  final Color borderSubtle;
  final Color borderDefault;
  final Color borderHover;
  final Color borderFocus;

  // --- 文字层级 ---
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  // --- 强调色 ---
  final Color primary;
  final Color primaryLight;
  final Color primaryDark;
  final Color primaryTint;
  final Color accent;

  // --- 状态语义 ---
  final Color success;
  final Color warning;
  final Color error;
  final Color errorSurface;
  final Color info;

  const AppColorsExtension({
    required this.canvasBackground,
    required this.cardBackground,
    required this.elevatedBackground,
    required this.mutedBackground,
    required this.borderSubtle,
    required this.borderDefault,
    required this.borderHover,
    required this.borderFocus,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.primary,
    required this.primaryLight,
    required this.primaryDark,
    required this.primaryTint,
    required this.accent,
    required this.success,
    required this.warning,
    required this.error,
    required this.errorSurface,
    required this.info,
  });

  /// 亮色调色板 (Notion 暖纸本工作台)
  static const AppColorsExtension light = AppColorsExtension(
    canvasBackground: Color(0xFFF6F5F4),
    cardBackground: Color(0xFFFFFFFF),
    elevatedBackground: Color(0xFFFAFAF9),
    mutedBackground: Color(0xFFF0EFEB),
    borderSubtle: Color(0x0A000000),
    borderDefault: Color(0x14000000),
    borderHover: Color(0x26000000),
    borderFocus: Color(0xFF0075DE),
    textPrimary: Color(0xFF111111),
    textSecondary: Color(0xFF615D59),
    textMuted: Color(0xFF757575),
    primary: Color(0xFF0075DE),
    primaryLight: Color(0xFF62AEF0),
    primaryDark: Color(0xFF097FE8),
    primaryTint: Color(0xFFE6F3FE),
    accent: Color(0xFF0075DE),
    success: Color(0xFF0F9960),
    warning: Color(0xFFD9822B),
    error: Color(0xFFDB3737),
    errorSurface: Color(0xFFFDEEED),
    info: Color(0xFF0075DE),
  );

  /// 深色调色板 (Notion Minimal Dark)
  static const AppColorsExtension dark = AppColorsExtension(
    canvasBackground: Color(0xFF191919),
    cardBackground: Color(0xFF202020),
    elevatedBackground: Color(0xFF262626),
    mutedBackground: Color(0xFF2B2B2B),
    borderSubtle: Color(0x14FFFFFF),
    borderDefault: Color(0x26FFFFFF),
    borderHover: Color(0x40FFFFFF),
    borderFocus: Color(0xFF2383E2),
    textPrimary: Color(0xFFE6E6E6),
    textSecondary: Color(0xFF9E9E9E),
    textMuted: Color(0xFF757575),
    primary: Color(0xFF2383E2),
    primaryLight: Color(0xFF529CCA),
    primaryDark: Color(0xFF0C66C2),
    primaryTint: Color(0x262383E2),
    accent: Color(0xFF2383E2),
    success: Color(0xFF2EA043),
    warning: Color(0xFFD29922),
    error: Color(0xFFF85149),
    errorSurface: Color(0xFF331515),
    info: Color(0xFF58A6FF),
  );

  @override
  ThemeExtension<AppColorsExtension> copyWith({
    Color? canvasBackground,
    Color? cardBackground,
    Color? elevatedBackground,
    Color? mutedBackground,
    Color? borderSubtle,
    Color? borderDefault,
    Color? borderHover,
    Color? borderFocus,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? primary,
    Color? primaryLight,
    Color? primaryDark,
    Color? primaryTint,
    Color? accent,
    Color? success,
    Color? warning,
    Color? error,
    Color? errorSurface,
    Color? info,
  }) {
    return AppColorsExtension(
      canvasBackground: canvasBackground ?? this.canvasBackground,
      cardBackground: cardBackground ?? this.cardBackground,
      elevatedBackground: elevatedBackground ?? this.elevatedBackground,
      mutedBackground: mutedBackground ?? this.mutedBackground,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      borderDefault: borderDefault ?? this.borderDefault,
      borderHover: borderHover ?? this.borderHover,
      borderFocus: borderFocus ?? this.borderFocus,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      primary: primary ?? this.primary,
      primaryLight: primaryLight ?? this.primaryLight,
      primaryDark: primaryDark ?? this.primaryDark,
      primaryTint: primaryTint ?? this.primaryTint,
      accent: accent ?? this.accent,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      error: error ?? this.error,
      errorSurface: errorSurface ?? this.errorSurface,
      info: info ?? this.info,
    );
  }

  @override
  ThemeExtension<AppColorsExtension> lerp(
    covariant ThemeExtension<AppColorsExtension>? other,
    double t,
  ) {
    if (other is! AppColorsExtension) return this;
    return AppColorsExtension(
      canvasBackground: Color.lerp(canvasBackground, other.canvasBackground, t)!,
      cardBackground: Color.lerp(cardBackground, other.cardBackground, t)!,
      elevatedBackground:
          Color.lerp(elevatedBackground, other.elevatedBackground, t)!,
      mutedBackground: Color.lerp(mutedBackground, other.mutedBackground, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      borderDefault: Color.lerp(borderDefault, other.borderDefault, t)!,
      borderHover: Color.lerp(borderHover, other.borderHover, t)!,
      borderFocus: Color.lerp(borderFocus, other.borderFocus, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      primaryLight: Color.lerp(primaryLight, other.primaryLight, t)!,
      primaryDark: Color.lerp(primaryDark, other.primaryDark, t)!,
      primaryTint: Color.lerp(primaryTint, other.primaryTint, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      error: Color.lerp(error, other.error, t)!,
      errorSurface: Color.lerp(errorSurface, other.errorSurface, t)!,
      info: Color.lerp(info, other.info, t)!,
    );
  }
}
