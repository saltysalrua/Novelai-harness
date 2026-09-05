import 'package:flutter/material.dart';
import '../../../../data/services/prompt_ast_engine.dart';
import '../../../../data/services/tag_dictionary_service.dart';
import '../../../core/theme/theme_context_extensions.dart';

/// NovelAI 富文本提示词语法高亮控制器
///
/// 特性：
/// - 实时解析 NovelAI 权重语法 (`{}` / `[]` / `N::tag::`) 并施加柔和微调底色/文字染色
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

    final spans = <InlineSpan>[];
    var lastIndex = 0;

    for (final tok in tokens) {
      // 1. 处理 Token 之前的前导字符 (如逗号、空格、换行、竖线)
      if (tok.segStart > lastIndex) {
        final separatorText = rawText.substring(lastIndex, tok.segStart);
        spans.add(
          TextSpan(
            text: separatorText,
            style: baseStyle.copyWith(
              color: colors.textMuted.withValues(alpha: 0.55),
            ),
          ),
        );
      }

      // 2. 根据 Token 的权重和禁用状态推导样式
      final isUp = tok.effectiveMultiplier > 1.001;
      final isDown = tok.effectiveMultiplier < 0.999;
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
        if (nameBody.isNotEmpty) {
          spans.add(TextSpan(text: nameBody, style: tokenStyle));
        }
        if (suffixMarker.isNotEmpty) {
          spans.add(TextSpan(text: suffixMarker, style: markerStyle));
        }
      } else {
        // 纯无记号 Token
        spans.add(
          TextSpan(
            text: rawText.substring(tok.segStart, tok.segEnd),
            style: tokenStyle,
          ),
        );
      }

      lastIndex = tok.segEnd;
    }

    // 4. 尾部剩余字符
    if (lastIndex < rawText.length) {
      spans.add(
        TextSpan(
          text: rawText.substring(lastIndex),
          style: baseStyle.copyWith(
            color: colors.textMuted.withValues(alpha: 0.55),
          ),
        ),
      );
    }

    return TextSpan(children: spans, style: baseStyle);
  }
}
