import 'package:flutter/material.dart';

/// 单行「图标 + 文字」视觉中轴对齐原子组件 (AppIconLabel)
///
/// 通过 [TextPainter] 实测当前字体在 `PlaceholderAlignment.middle` 下的真实光学中轴
/// 与行盒几何中心之间的差值（零魔法数字，自动适配任意字体、字号、字重与系统缩放并缓存），
/// 将前后图标对齐到字体真实中轴；同时保留独立的 [Text]（或自定义 [labelWidget]）节点，
/// 兼顾视觉居中、截断省略、`AppTextSwap` 等文本动效与 `find.text(...)` 语义完整。
class AppIconLabel extends StatelessWidget {
  final Widget? leading;
  final String label;
  final Widget? labelWidget;
  final Widget? trailing;
  final TextStyle? style;
  final double gap;
  final double trailingGap;
  final int maxLines;
  final TextOverflow overflow;
  final TextAlign textAlign;
  final MainAxisSize mainAxisSize;
  final MainAxisAlignment mainAxisAlignment;

  const AppIconLabel({
    super.key,
    this.leading,
    required this.label,
    this.labelWidget,
    this.trailing,
    this.style,
    this.gap = 6.0,
    this.trailingGap = 6.0,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
    this.textAlign = TextAlign.start,
    this.mainAxisSize = MainAxisSize.min,
    this.mainAxisAlignment = MainAxisAlignment.start,
  });

  static final Map<_OpticalMetricKey, double> _offsetCache =
      <_OpticalMetricKey, double>{};

  static bool _containsNonAscii(String text) {
    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) > 127) return true;
    }
    return false;
  }

  /// 实测 Skia `PlaceholderAlignment.middle` 相对行盒几何中心的纵向偏移 (dy)
  static double _resolveOpticalOffset({
    required TextStyle style,
    required TextDirection textDirection,
    required TextScaler textScaler,
    required bool hasNonAscii,
  }) {
    final fallbackKey = style.fontFamilyFallback?.join(',');
    final key = _OpticalMetricKey(
      fontFamily: style.fontFamily,
      fontFamilyFallback: fallbackKey,
      fontSize: style.fontSize,
      fontWeight: style.fontWeight,
      fontStyle: style.fontStyle,
      height: style.height,
      leadingDistribution: style.leadingDistribution,
      scaledFontSize: textScaler.scale(style.fontSize ?? 14.0),
      textDirection: textDirection,
      hasNonAscii: hasNonAscii,
    );

    final cached = _offsetCache[key];
    if (cached != null) return cached;

    final painter = TextPainter(
      text: TextSpan(
        style: style,
        children: [
          const WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: SizedBox.shrink(),
          ),
          TextSpan(text: hasNonAscii ? '设' : 'A'),
        ],
      ),
      textDirection: textDirection,
      textScaler: textScaler,
      maxLines: 1,
    );
    painter.setPlaceholderDimensions(const [
      PlaceholderDimensions(
        size: Size(1, 1),
        alignment: PlaceholderAlignment.middle,
      ),
    ]);
    painter.layout();

    double dy = 0.0;
    final boxes = painter.inlinePlaceholderBoxes;
    if (boxes != null && boxes.isNotEmpty) {
      final box = boxes.first;
      final middleY = (box.top + box.bottom) / 2.0;
      final geoCenterY = painter.height / 2.0;
      dy = middleY - geoCenterY;
    }
    painter.dispose();

    if (_offsetCache.length >= 128) {
      _offsetCache.clear();
    }
    _offsetCache[key] = dy;
    return dy;
  }

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = DefaultTextStyle.of(context).style
        .merge(style)
        .copyWith(leadingDistribution: TextLeadingDistribution.even);

    final Widget? textNode =
        labelWidget ??
        (label.isNotEmpty
            ? Text(
                label,
                maxLines: maxLines,
                overflow: overflow,
                textAlign: textAlign,
                style: effectiveStyle,
              )
            : null);

    if (leading == null && trailing == null) {
      return textNode ?? const SizedBox.shrink();
    }

    final dy = textNode == null
        ? 0.0
        : _resolveOpticalOffset(
            style: effectiveStyle,
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
            hasNonAscii: _containsNonAscii(label),
          );

    Widget alignIcon(Widget icon) {
      if (dy.abs() < 0.05) return icon;
      return Transform.translate(offset: Offset(0, dy), child: icon);
    }

    return Row(
      mainAxisSize: mainAxisSize,
      mainAxisAlignment: mainAxisAlignment,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (leading != null) ...[
          alignIcon(leading!),
          if (textNode != null) SizedBox(width: gap),
        ],
        if (textNode != null) Flexible(child: textNode),
        if (trailing != null) ...[
          if (textNode != null) SizedBox(width: trailingGap),
          alignIcon(trailing!),
        ],
      ],
    );
  }
}

class _OpticalMetricKey {
  final String? fontFamily;
  final String? fontFamilyFallback;
  final double? fontSize;
  final FontWeight? fontWeight;
  final FontStyle? fontStyle;
  final double? height;
  final TextLeadingDistribution? leadingDistribution;
  final double scaledFontSize;
  final TextDirection textDirection;
  final bool hasNonAscii;

  const _OpticalMetricKey({
    required this.fontFamily,
    required this.fontFamilyFallback,
    required this.fontSize,
    required this.fontWeight,
    required this.fontStyle,
    required this.height,
    required this.leadingDistribution,
    required this.scaledFontSize,
    required this.textDirection,
    required this.hasNonAscii,
  });

  @override
  bool operator ==(Object other) {
    return other is _OpticalMetricKey &&
        other.fontFamily == fontFamily &&
        other.fontFamilyFallback == fontFamilyFallback &&
        other.fontSize == fontSize &&
        other.fontWeight == fontWeight &&
        other.fontStyle == fontStyle &&
        other.height == height &&
        other.leadingDistribution == leadingDistribution &&
        other.scaledFontSize == scaledFontSize &&
        other.textDirection == textDirection &&
        other.hasNonAscii == hasNonAscii;
  }

  @override
  int get hashCode => Object.hash(
    fontFamily,
    fontFamilyFallback,
    fontSize,
    fontWeight,
    fontStyle,
    height,
    leadingDistribution,
    scaledFontSize,
    textDirection,
    hasNonAscii,
  );
}
