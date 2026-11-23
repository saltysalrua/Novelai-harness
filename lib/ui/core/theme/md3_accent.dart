import 'dart:math' as math;

import 'package:flutter/material.dart' show Brightness, Color, Colors, immutable;
import 'package:material_color_utilities/material_color_utilities.dart';

import '../../../data/services/config_service.dart';

/// 亮色模式精选背景预设 (首个为默认 Notion 暖纸)
const List<Color> kLightBackgroundPresets = [
  Color(0xFFF6F5F4), // 暖纸默认
  Color(0xFFFFFFFF), // 纯白
  Color(0xFFF1F5F9), // 晨雾冷灰
  Color(0xFFF6F0E4), // 羊皮纸
  Color(0xFFEFF4F1), // 鼠尾草雾
  Color(0xFFF7F1F4), // 樱花浅雾
  Color(0xFFF2F1F8), // 淡薰衣草
];

/// 深色模式精选背景预设 (首个为默认 Notion 暗灰)
const List<Color> kDarkBackgroundPresets = [
  Color(0xFF191919), // Notion 暗灰
  Color(0xFF0D0D0F), // 极夜纯黑
  Color(0xFF131822), // 午夜蓝灰
  Color(0xFF181622), // 曜石紫灰
  Color(0xFF131B18), // 深林墨绿
  Color(0xFF1C1917), // 暖炭深褐
  Color(0xFF1E222A), // 北极石板
];

/// MD3 动态取色推导出的主题强调色令牌组。
///
/// 种子色经 [DislikeAnalyzer] 修正后，先按选定方案 ([SchemeTonalSpot] 等 8 种)
/// 提取色相与风格偏好，再在 HCT 感知色彩空间执行彩度收敛、黄绿护眼修正与
/// 目标表面对比度校准，避免高饱和动漫图在 UI 上产生刺眼霓虹感或暗色白字看不清。
@immutable
class M3AccentTokens {
  /// 主强调色 (亮色 tone ~44，暗色 tone ~62~66，兼顾按钮填充与正文可读性)
  final Color primary;

  /// 主强调色上的前景文字/图标色 (经 HCT 对比度自动择优，保证 >= 4.5:1)
  final Color onPrimary;

  /// 次级强调 (轻量高亮/滑块轨道/选中态装饰)
  final Color primaryLight;

  /// 深档强调 (按压/悬浮加深态)
  final Color primaryDark;

  /// 极浅底色 (Ghost CTA 背景/选中行底色，与当前卡片表面柔和融合)
  final Color primaryTint;

  const M3AccentTokens({
    required this.primary,
    required this.onPrimary,
    required this.primaryLight,
    required this.primaryDark,
    required this.primaryTint,
  });
}

/// 推导出的背景、边框与文字中性层级令牌组。
///
/// 由「跟随强调色微染」或「自定义背景色」自动生成四层背景层级
/// (`canvas` / `card` / `elevated` / `muted`) 与对比度安全的边框和文字色。
@immutable
class AppSurfaceTokens {
  final Color canvasBackground;
  final Color cardBackground;
  final Color elevatedBackground;
  final Color mutedBackground;
  final Color borderSubtle;
  final Color borderDefault;
  final Color borderHover;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  /// 当前背景的实际明暗极性 (自定义背景跨明暗选色时确保文字与强调色不反转失效)
  final bool isDarkSurface;

  const AppSurfaceTokens({
    required this.canvasBackground,
    required this.cardBackground,
    required this.elevatedBackground,
    required this.mutedBackground,
    required this.borderSubtle,
    required this.borderDefault,
    required this.borderHover,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.isDarkSurface,
  });
}

/// 从种子色推导护眼且高可读性的 MD3 强调色令牌。
///
/// [seed] 任意图片主色或手动种子；[variant] 取色方案；[brightness] 目标主题亮度；
/// [surfaceColor] 可选的当前卡片表面色，用于校准对比度与融合 [M3AccentTokens.primaryTint]。
M3AccentTokens buildM3AccentTokens({
  required Color seed,
  required Brightness brightness,
  required AppAccentVariant variant,
  Color? surfaceColor,
}) {
  // Android 同款处理：种子色落在「被嫌弃」色域 (浑浊橙/棕) 时先拉回可用的种子
  final source = DislikeAnalyzer.fixIfDisliked(Hct.fromInt(seed.toARGB32()));
  final effectiveSurface =
      surfaceColor ??
      (brightness == Brightness.dark
          ? const Color(0xFF202020)
          : const Color(0xFFFFFFFF));
  final surfaceHct = Hct.fromInt(effectiveSurface.toARGB32());
  final isDarkSurface = surfaceHct.tone < 55.0;

  final DynamicScheme scheme = _buildScheme(
    source: source,
    isDark: isDarkSurface,
    variant: variant,
  );

  final primaryPalette = scheme.primaryPalette;
  final double hue = primaryPalette.hue;
  final double chroma = _tameAccentChroma(
    rawChroma: primaryPalette.chroma,
    hue: hue,
    variant: variant,
    isDark: isDarkSurface,
  );

  final bool inYellowBand = hue >= 72.0 && hue <= 118.0;

  if (!isDarkSurface) {
    final double baseTone = inYellowBand ? 41.0 : 44.0;
    final double contrastTone = _darkerWithFallback(
      surfaceHct.tone,
      4.6,
      fallback: 26.0,
    );
    final double primaryTone = math.min(baseTone, contrastTone).clamp(24.0, 46.0);
    final Color primary = Color(Hct.from(hue, chroma, primaryTone).toInt());
    final Color primaryLight = Color(
      Hct.from(hue, chroma * 0.76, (primaryTone + 18.0).clamp(56.0, 74.0))
          .toInt(),
    );
    final Color primaryDark = Color(
      Hct.from(hue, chroma, (primaryTone - 10.0).clamp(20.0, 38.0)).toInt(),
    );
    final Color primaryTint = Color.alphaBlend(
      primary.withValues(alpha: 0.10),
      effectiveSurface,
    );
    return M3AccentTokens(
      primary: primary,
      onPrimary: resolveOnPrimary(primary, hue: hue, chroma: chroma),
      primaryLight: primaryLight,
      primaryDark: primaryDark,
      primaryTint: primaryTint,
    );
  }

  // 深色背景：收敛在 tone 62~68 的柔和缎面亮度 (替代 MD3 刺眼 tone 80 荧光粉彩)，
  // 同时保证相对卡片背景 >= 5.0:1 对比度，并由 resolveOnPrimary 自动匹配深色文字。
  final double baseTone = inYellowBand ? 66.0 : 63.0;
  final double contrastTone = _lighterWithFallback(
    surfaceHct.tone,
    5.0,
    fallback: 74.0,
  );
  final double primaryTone = math.max(baseTone, contrastTone).clamp(58.0, 78.0);
  final Color primary = Color(Hct.from(hue, chroma, primaryTone).toInt());
  final Color primaryLight = Color(
    Hct.from(hue, chroma * 0.80, (primaryTone + 10.0).clamp(70.0, 84.0))
        .toInt(),
  );
  final Color primaryDark = Color(
    Hct.from(hue, chroma, (primaryTone - 14.0).clamp(38.0, 54.0)).toInt(),
  );
  final Color primaryTint = Color.alphaBlend(
    primary.withValues(alpha: 0.14),
    effectiveSurface,
  );

  return M3AccentTokens(
    primary: primary,
    onPrimary: resolveOnPrimary(primary, hue: hue, chroma: chroma),
    primaryLight: primaryLight,
    primaryDark: primaryDark,
    primaryTint: primaryTint,
  );
}

/// 根据背景模式与配置推导四层背景、边框及文字中性色。
///
/// 返回 `null` 表示沿用默认 Notion 色板 (`AppColorsExtension.light/dark`)。
AppSurfaceTokens? buildSurfaceTokens({
  required Brightness brightness,
  required AppBackgroundMode mode,
  Color? customColor,
  Color? accentSeed,
  AppAccentVariant accentVariant = AppAccentVariant.tonalSpot,
}) {
  return switch (mode) {
    AppBackgroundMode.defaultNotion => null,
    AppBackgroundMode.followAccent => _buildFollowAccentSurfaces(
      brightness: brightness,
      accentSeed: accentSeed,
      accentVariant: accentVariant,
    ),
    AppBackgroundMode.custom =>
      customColor == null ? null : _buildCustomSurfaces(customColor),
  };
}

/// 为任意填充主色计算高可读性的前景文字/图标色 (优先纯白，亮度偏高时切深色墨迹)。
Color resolveOnPrimary(Color primary, {double? hue, double? chroma}) {
  final hct = Hct.fromInt(primary.toARGB32());
  final double contrastWhite = Contrast.ratioOfTones(hct.tone, 100.0);
  final double contrastDark = Contrast.ratioOfTones(hct.tone, 12.0);
  if (contrastWhite >= 4.5 || contrastWhite >= contrastDark) {
    return Colors.white;
  }
  final double inkHue = hue ?? hct.hue;
  final double inkChroma = math.min((chroma ?? hct.chroma) * 0.35, 10.0);
  return Color(Hct.from(inkHue, inkChroma, 12.0).toInt());
}

DynamicScheme _buildScheme({
  required Hct source,
  required bool isDark,
  required AppAccentVariant variant,
}) {
  return switch (variant) {
    AppAccentVariant.tonalSpot => SchemeTonalSpot(
      sourceColorHct: source,
      isDark: isDark,
      contrastLevel: 0.0,
    ),
    AppAccentVariant.vibrant => SchemeVibrant(
      sourceColorHct: source,
      isDark: isDark,
      contrastLevel: 0.0,
    ),
    AppAccentVariant.expressive => SchemeExpressive(
      sourceColorHct: source,
      isDark: isDark,
      contrastLevel: 0.0,
    ),
    AppAccentVariant.content => SchemeContent(
      sourceColorHct: source,
      isDark: isDark,
      contrastLevel: 0.0,
    ),
    AppAccentVariant.neutral => SchemeNeutral(
      sourceColorHct: source,
      isDark: isDark,
      contrastLevel: 0.0,
    ),
    AppAccentVariant.monochrome => SchemeMonochrome(
      sourceColorHct: source,
      isDark: isDark,
      contrastLevel: 0.0,
    ),
    AppAccentVariant.rainbow => SchemeRainbow(
      sourceColorHct: source,
      isDark: isDark,
      contrastLevel: 0.0,
    ),
    AppAccentVariant.fruitSalad => SchemeFruitSalad(
      sourceColorHct: source,
      isDark: isDark,
      contrastLevel: 0.0,
    ),
  };
}

/// 将动漫图提取出的高饱和彩度收敛到工作台耐看区间，暗色模式下进一步克制荧光感。
double _tameAccentChroma({
  required double rawChroma,
  required double hue,
  required AppAccentVariant variant,
  required bool isDark,
}) {
  if (variant == AppAccentVariant.monochrome) return 0.0;

  final double maxChroma = switch (variant) {
    AppAccentVariant.monochrome => 0.0,
    AppAccentVariant.neutral => isDark ? 14.0 : 16.0,
    AppAccentVariant.tonalSpot => isDark ? 32.0 : 38.0,
    AppAccentVariant.content => isDark ? 35.0 : 42.0,
    AppAccentVariant.vibrant ||
    AppAccentVariant.expressive ||
    AppAccentVariant.rainbow ||
    AppAccentVariant.fruitSalad => isDark ? 40.0 : 48.0,
  };

  // 使用软压缩曲线：低饱和保持原貌，高饱和平滑收敛到 maxChroma，不生硬截断色阶差异
  double tamed = rawChroma <= maxChroma * 0.65
      ? rawChroma
      : maxChroma * 0.65 +
            (maxChroma * 0.35) *
                (1.0 - math.exp(-(rawChroma - maxChroma * 0.65) / 28.0));

  // 黄/黄绿段额外护眼收敛，避免荧光黄或浑浊泥绿
  if (hue >= 70.0 && hue <= 125.0) {
    final double yellowCap = isDark ? 26.0 : 30.0;
    tamed = math.min(tamed * 0.80, yellowCap);
  }

  return tamed.clamp(0.0, maxChroma);
}

/// 跟随强调色微染：以极低彩度 (chroma 4~6) 轻染四层中性表面，与动态强调色浑然一体。
AppSurfaceTokens _buildFollowAccentSurfaces({
  required Brightness brightness,
  required Color? accentSeed,
  required AppAccentVariant accentVariant,
}) {
  final isDark = brightness == Brightness.dark;
  final Color effectiveSeed = accentSeed ?? const Color(0xFF0075DE);
  final source = DislikeAnalyzer.fixIfDisliked(
    Hct.fromInt(effectiveSeed.toARGB32()),
  );
  final scheme = _buildScheme(
    source: source,
    isDark: isDark,
    variant: accentVariant,
  );
  final double hue = scheme.primaryPalette.hue;
  final bool isMono = accentVariant == AppAccentVariant.monochrome;
  final double baseChroma = isMono ? 0.0 : (isDark ? 6.0 : 5.0);

  if (!isDark) {
    return AppSurfaceTokens(
      canvasBackground: Color(Hct.from(hue, baseChroma, 96.4).toInt()),
      cardBackground: Color(Hct.from(hue, baseChroma * 0.45, 99.5).toInt()),
      elevatedBackground: Color(Hct.from(hue, baseChroma * 0.65, 98.0).toInt()),
      mutedBackground: Color(Hct.from(hue, baseChroma * 1.15, 93.2).toInt()),
      borderSubtle: const Color(0x0A000000),
      borderDefault: const Color(0x14000000),
      borderHover: const Color(0x26000000),
      textPrimary: const Color(0xFF111111),
      textSecondary: Color(Hct.from(hue, math.min(baseChroma, 5.0), 38.0).toInt()),
      textMuted: Color(Hct.from(hue, math.min(baseChroma, 4.0), 49.0).toInt()),
      isDarkSurface: false,
    );
  }

  return AppSurfaceTokens(
    canvasBackground: Color(Hct.from(hue, baseChroma, 10.2).toInt()),
    cardBackground: Color(Hct.from(hue, baseChroma * 1.05, 13.8).toInt()),
    elevatedBackground: Color(Hct.from(hue, baseChroma * 1.10, 17.5).toInt()),
    mutedBackground: Color(Hct.from(hue, baseChroma * 1.15, 20.6).toInt()),
    borderSubtle: const Color(0x14FFFFFF),
    borderDefault: const Color(0x26FFFFFF),
    borderHover: const Color(0x40FFFFFF),
    textPrimary: const Color(0xFFE6E6E6),
    textSecondary: Color(Hct.from(hue, math.min(baseChroma, 5.0), 66.0).toInt()),
    textMuted: Color(Hct.from(hue, math.min(baseChroma, 4.0), 50.0).toInt()),
    isDarkSurface: true,
  );
}

/// 从用户任选的画布背景色推导完整四层背景、边框与高对比文字色。
///
/// 保留用户选择的 [customCanvas] 作为精确 `canvasBackground`，其余层级与文字
/// 按实际 HCT 明度极性自动推导，杜绝黑底黑字或白底白字。
AppSurfaceTokens _buildCustomSurfaces(Color customCanvas) {
  final hct = Hct.fromInt(customCanvas.toARGB32());
  final double hue = hct.hue;
  final double chroma = hct.chroma;
  final double tone = hct.tone;
  final bool isDarkSurface = tone < 55.0;

  if (!isDarkSurface) {
    final bool isNearWhite = tone >= 97.5;
    final Color card = isNearWhite
        ? customCanvas
        : Color(
            Hct.from(
              hue,
              math.min(chroma * 0.55, 16.0),
              math.min(100.0, tone + 4.5),
            ).toInt(),
          );
    final Color elevated = isNearWhite
        ? Color(Hct.from(hue, math.min(chroma, 10.0), 97.2).toInt())
        : Color(
            Hct.from(
              hue,
              math.min(chroma * 0.72, 20.0),
              math.min(99.4, tone + 2.4),
            ).toInt(),
          );
    final Color muted = isNearWhite
        ? Color(Hct.from(hue, math.min(chroma, 14.0), 94.0).toInt())
        : Color(
            Hct.from(
              hue,
              math.min(chroma * 0.92, 24.0),
              math.max(42.0, tone - 4.2),
            ).toInt(),
          );

    final double cardTone = Hct.fromInt(card.toARGB32()).tone;
    final double secTone = math.min(
      38.0,
      _darkerWithFallback(cardTone, 5.0, fallback: 22.0),
    );
    final double mutedTone = math.min(
      49.0,
      _darkerWithFallback(cardTone, 3.6, fallback: 32.0),
    );

    return AppSurfaceTokens(
      canvasBackground: customCanvas,
      cardBackground: card,
      elevatedBackground: elevated,
      mutedBackground: muted,
      borderSubtle: isNearWhite
          ? const Color(0x0E000000)
          : const Color(0x0B000000),
      borderDefault: isNearWhite
          ? const Color(0x18000000)
          : const Color(0x15000000),
      borderHover: isNearWhite
          ? const Color(0x2C000000)
          : const Color(0x28000000),
      textPrimary: const Color(0xFF111111),
      textSecondary: Color(
        Hct.from(hue, math.min(chroma * 0.22, 6.0), secTone).toInt(),
      ),
      textMuted: Color(
        Hct.from(hue, math.min(chroma * 0.18, 5.0), mutedTone).toInt(),
      ),
      isDarkSurface: false,
    );
  }

  // 深色自定义背景 (含 OLED 纯黑 #000000 ~ 中深灰/深彩背景)
  final double cardLift = tone < 4.0 ? 7.5 : 4.5;
  final double cardTone = math.min(62.0, tone + cardLift);
  final double elevatedTone = math.min(66.0, cardTone + 4.0);
  final double mutedTone = math.min(70.0, elevatedTone + 3.2);
  final double cCap = math.min(chroma, 26.0);

  final Color card = Color(Hct.from(hue, cCap * 0.95, cardTone).toInt());
  final Color elevated = Color(Hct.from(hue, cCap * 0.90, elevatedTone).toInt());
  final Color muted = Color(Hct.from(hue, cCap * 0.85, mutedTone).toInt());

  final double secTone = math
      .max(66.0, _lighterWithFallback(cardTone, 5.0, fallback: 86.0))
      .clamp(62.0, 92.0);
  final double mutedTextTone = math
      .max(52.0, _lighterWithFallback(cardTone, 3.5, fallback: 74.0))
      .clamp(48.0, 82.0);

  return AppSurfaceTokens(
    canvasBackground: customCanvas,
    cardBackground: card,
    elevatedBackground: elevated,
    mutedBackground: muted,
    borderSubtle: const Color(0x14FFFFFF),
    borderDefault: const Color(0x26FFFFFF),
    borderHover: const Color(0x40FFFFFF),
    textPrimary: const Color(0xFFE8E8E8),
    textSecondary: Color(
      Hct.from(hue, math.min(chroma * 0.20, 6.0), secTone).toInt(),
    ),
    textMuted: Color(
      Hct.from(hue, math.min(chroma * 0.15, 5.0), mutedTextTone).toInt(),
    ),
    isDarkSurface: true,
  );
}

double _darkerWithFallback(
  double tone,
  double ratio, {
  required double fallback,
}) {
  final result = Contrast.darker(tone: tone, ratio: ratio);
  return result >= 0 ? result : fallback;
}

double _lighterWithFallback(
  double tone,
  double ratio, {
  required double fallback,
}) {
  final result = Contrast.lighter(tone: tone, ratio: ratio);
  return result >= 0 ? result : fallback;
}
