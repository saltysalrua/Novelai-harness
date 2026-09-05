import 'package:flutter/material.dart';
import '../../../../data/services/prompt_ast_engine.dart';
import '../../../../data/services/tag_dictionary_service.dart';
import '../../../core/theme/theme_context_extensions.dart';

/// 数值权重染色区域：从 `N::` 头标记延伸到下一个 `::`
/// (无论它是闭合尾标记还是下一个权重的头标记)，跨逗号生效；
/// 若后续再无 `::` 则延伸到文本末尾
@immutable
class _WeightRegion {
  final int start;
  final int end;
  final double multiplier;

  const _WeightRegion({
    required this.start,
    required this.end,
    required this.multiplier,
  });

  bool contains(int pos) => pos >= start && pos < end;

  bool overlaps(int rangeStart, int rangeEnd) =>
      rangeStart < end && rangeEnd > start;
}

/// 扫描整段文本的跨逗号数值权重区域
List<_WeightRegion> _scanWeightRegions(String text) {
  final regions = <_WeightRegion>[];
  final headPattern = RegExp(r'(-?\d+(?:\.\d+)?)::');
  var consumed = 0;

  for (final match in headPattern.allMatches(text)) {
    // 头标记落在前一个区域内部 (已被当作终止符消费) 时跳过
    if (match.start < consumed) continue;

    final mult = double.tryParse(match.group(1)!) ?? 1.0;
    final headEnd = match.end;
    var end = text.length;

    final nextTail = text.indexOf('::', headEnd);
    if (nextTail >= 0) {
      // 终止 :: 前若紧邻数字，说明它是下一个权重头的一部分，
      // 当前区域应结束在数字之前 (头尾皆可作终止符)
      final headNum = RegExp(
        r'(-?\d+(?:\.\d+)?)$',
      ).firstMatch(text.substring(headEnd, nextTail));
      if (headNum != null) {
        end = nextTail - headNum.group(0)!.length;
      } else {
        end = nextTail + 2;
      }
    }
    consumed = end;
    regions.add(_WeightRegion(start: match.start, end: end, multiplier: mult));
  }
  return regions;
}

/// NovelAI 富文本提示词语法高亮控制器
///
/// 特性：
/// - 实时解析 NovelAI 权重语法 (`{}` / `[]` / `N::tag::`) 并施加柔和微调底色/文字染色
/// - 未闭合的 `N::` 权重跨逗号染色，直到下一个 `::` (头尾标记均可) 或文本末尾
/// - 语法记号 (`::`, `{}`, `[]`, `~`) 采用 45% 透明度淡显
/// - 禁用标签 `~tag~` 自动添加中划线 (strikethrough) 与淡灰色彩
/// - 标签分类着色 (画师紫色、角色绿色、作品粉色、元标签橙色、通用默认)
/// - 保持与原生 TextField 绝对同构的字形与行高，光标定位与输入法零漂移
class RichPromptTextController extends TextEditingController {
  bool enableHighlight;
  bool showCategoryColors;

  RichPromptTextController({
    super.text,
    this.enableHighlight = true,
    this.showCategoryColors = true,
  });

  /// 同步高亮开关 (设置项变更时调用)，仅在值真正变化时通知重绘
  void setHighlightOptions({bool? highlightEnabled, bool? categoryColors}) {
    var changed = false;
    if (highlightEnabled != null && highlightEnabled != enableHighlight) {
      enableHighlight = highlightEnabled;
      changed = true;
    }
    if (categoryColors != null && categoryColors != showCategoryColors) {
      showCategoryColors = categoryColors;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    // 全部颜色从当前主题取 (亮暗自适应)，不持有静态色板
    final colors = context.colors;
    final baseStyle =
        style ??
        TextStyle(fontSize: 14, height: 1.48, color: colors.textPrimary);

    final rawText = text;
    if (!enableHighlight || rawText.isEmpty) {
      return TextSpan(text: rawText, style: baseStyle);
    }

    final tokens = PromptAstEngine.parsePromptTokens(
      rawText,
      categoryLookup: (name) => TagDictionaryService.instance.categoryOf(name),
    );

    if (tokens.isEmpty) {
      return TextSpan(text: rawText, style: baseStyle);
    }

    // 跨逗号数值权重区域 (未闭合的 N:: 头会延伸到下一个 :: 或末尾)
    final weightRegions = _scanWeightRegions(rawText);

    Color regionBg(_WeightRegion region) {
      if (region.multiplier > 1.001) {
        return colors.primary.withValues(alpha: 0.08);
      } else if (region.multiplier < 0.999) {
        return colors.warning.withValues(alpha: 0.08);
      }
      return colors.textMuted.withValues(alpha: 0.0);
    }

    _WeightRegion? regionAt(int pos) {
      for (final region in weightRegions) {
        if (region.contains(pos)) return region;
      }
      return null;
    }

    final spans = <InlineSpan>[];
    var lastIndex = 0;

    for (final tok in tokens) {
      // 1. 处理 Token 之前的前导字符 (如逗号、空格、换行、竖线)：
      //    落在权重区域内的分隔符同步染上区域底色，保证跨逗号染色连续
      if (tok.segStart > lastIndex) {
        final separatorText = rawText.substring(lastIndex, tok.segStart);
        Color? separatorBg;
        for (final region in weightRegions) {
          if (region.overlaps(lastIndex, tok.segStart)) {
            separatorBg = regionBg(region);
            break;
          }
        }
        spans.add(
          TextSpan(
            text: separatorText,
            style: baseStyle.copyWith(
              color: colors.textMuted.withValues(alpha: 0.55),
              backgroundColor: separatorBg,
            ),
          ),
        );
      }

      // 2. 根据 Token 的权重和禁用状态推导样式：
      //    优先取光标所在区域 (未闭合权重) 的倍率，其次 Token 自身倍率
      final regionMult = regionAt(tok.nameStart)?.multiplier;
      final effMult = regionMult ?? tok.effectiveMultiplier;
      final isUp = effMult > 1.001;
      final isDown = effMult < 0.999;
      final disabled = tok.disabled;

      // 基础文本颜色 (分类着色 vs 默认正文色)
      Color textColor = colors.textPrimary;
      if (disabled) {
        textColor = colors.textMuted.withValues(alpha: 0.45);
      } else if (showCategoryColors && tok.category != null) {
        textColor = context.tagCategoryColor(tok.category!);
      } else if (isUp) {
        textColor = colors.primary;
      } else if (isDown) {
        textColor = colors.warning;
      }

      // 语法记号淡显颜色
      final markerColor = disabled
          ? colors.textMuted.withValues(alpha: 0.35)
          : (isUp
                ? colors.primary.withValues(alpha: 0.45)
                : (isDown
                      ? colors.warning.withValues(alpha: 0.45)
                      : colors.textMuted.withValues(alpha: 0.40)));

      // 权重区间柔和背景微色
      final Color? bgColor = disabled
          ? null
          : (isUp
                ? colors.primary.withValues(alpha: 0.08)
                : (isDown ? colors.warning.withValues(alpha: 0.08) : null));

      final tokenStyle = baseStyle.copyWith(
        color: textColor,
        backgroundColor: bgColor,
        decoration: disabled ? TextDecoration.lineThrough : null,
        decorationColor: colors.textMuted.withValues(alpha: 0.6),
        decorationThickness: disabled ? 1.5 : null,
      );

      final markerStyle = baseStyle.copyWith(
        color: markerColor,
        backgroundColor: bgColor,
        decoration: disabled ? TextDecoration.lineThrough : null,
      );

      // 3. 构建 Token 内部精细子 Span (记号与核心名称分离)
      if (tok.nameStart > tok.segStart || tok.segEnd > tok.nameEnd) {
        final prefixMarker = rawText.substring(tok.segStart, tok.nameStart);
        final nameBody = rawText.substring(tok.nameStart, tok.nameEnd);
        final suffixMarker = rawText.substring(tok.nameEnd, tok.segEnd);

        if (prefixMarker.isNotEmpty) {
          spans.add(TextSpan(text: prefixMarker, style: markerStyle));
        }
        // 名称末尾的 :: 是跨逗号权重区域的闭合尾标记 → 淡显处理
        final trailingColon =
            nameBody.length >= 2 &&
            nameBody.endsWith('::') &&
            regionAt(tok.nameEnd - 1) != null;
        if (trailingColon) {
          final nameBodyText = nameBody.substring(0, nameBody.length - 2);
          if (nameBodyText.isNotEmpty) {
            spans.add(TextSpan(text: nameBodyText, style: tokenStyle));
          }
          spans.add(TextSpan(text: '::', style: markerStyle));
        } else {
          if (nameBody.isNotEmpty) {
            spans.add(TextSpan(text: nameBody, style: tokenStyle));
          }
        }
        if (suffixMarker.isNotEmpty) {
          spans.add(TextSpan(text: suffixMarker, style: markerStyle));
        }
      } else {
        // 纯无记号 Token：名称末尾的 :: 同样可能是跨逗号权重区域的闭合尾标记
        final body = rawText.substring(tok.segStart, tok.segEnd);
        final trailingColon =
            body.length >= 2 &&
            body.endsWith('::') &&
            regionAt(tok.segEnd - 1) != null;
        if (trailingColon) {
          final nameText = body.substring(0, body.length - 2);
          if (nameText.isNotEmpty) {
            spans.add(TextSpan(text: nameText, style: tokenStyle));
          }
          spans.add(TextSpan(text: '::', style: markerStyle));
        } else {
          spans.add(TextSpan(text: body, style: tokenStyle));
        }
      }

      lastIndex = tok.segEnd;
    }

    // 4. 尾部剩余字符：落在权重区域内时同步染上区域底色
    if (lastIndex < rawText.length) {
      Color? tailBg;
      for (final region in weightRegions) {
        if (region.overlaps(lastIndex, rawText.length)) {
          tailBg = regionBg(region);
          break;
        }
      }
      spans.add(
        TextSpan(
          text: rawText.substring(lastIndex),
          style: baseStyle.copyWith(
            color: colors.textMuted.withValues(alpha: 0.55),
            backgroundColor: tailBg,
          ),
        ),
      );
    }

    return TextSpan(children: spans, style: baseStyle);
  }
}
