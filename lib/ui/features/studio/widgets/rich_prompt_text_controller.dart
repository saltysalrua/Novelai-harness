import 'package:flutter/material.dart';
import '../../../../data/models/tag_models.dart';
import '../../../../data/services/prompt_ast_engine.dart';
import '../../../../data/services/tag_dictionary_service.dart';
import '../../../core/theme/app_theme.dart';

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
    final baseStyle =
        style ??
        const TextStyle(
          fontSize: 13.5,
          height: 1.48,
          color: AppTheme.textPrimary,
        );

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
              color: AppTheme.textMuted.withValues(alpha: 0.55),
            ),
          ),
        );
      }

      // 2. 根据 Token 的权重和禁用状态推导样式
      final isUp = tok.effectiveMultiplier > 1.001;
      final isDown = tok.effectiveMultiplier < 0.999;
      final disabled = tok.disabled;

      // 基础文本颜色 (分类着色 vs 默认正文色)
      Color textColor = AppTheme.textPrimary;
      if (disabled) {
        textColor = AppTheme.textMuted.withValues(alpha: 0.45);
      } else if (showCategoryColors && tok.category != null) {
        textColor = switch (tok.category!) {
          DanbooruTagCategory.artist => const Color(0xFF7B1FA2),
          DanbooruTagCategory.character => const Color(0xFF1B5E20),
          DanbooruTagCategory.copyright => const Color(0xFFC2185B),
          DanbooruTagCategory.meta => const Color(0xFFE65100),
          DanbooruTagCategory.general => AppTheme.textPrimary,
        };
      } else if (isUp) {
        textColor = AppTheme.notionBlue;
      } else if (isDown) {
        textColor = AppTheme.warning;
      }

      // 语法记号淡显颜色
      final markerColor = disabled
          ? AppTheme.textMuted.withValues(alpha: 0.35)
          : (isUp
                ? AppTheme.notionBlue.withValues(alpha: 0.45)
                : (isDown
                      ? AppTheme.warning.withValues(alpha: 0.45)
                      : AppTheme.textMuted.withValues(alpha: 0.40)));

      // 权重区间柔和背景微色
      final Color? bgColor = disabled
          ? null
          : (isUp
                ? AppTheme.notionBlue.withValues(alpha: 0.08)
                : (isDown ? AppTheme.warning.withValues(alpha: 0.08) : null));

      final tokenStyle = baseStyle.copyWith(
        color: textColor,
        backgroundColor: bgColor,
        decoration: disabled ? TextDecoration.lineThrough : null,
        decorationColor: AppTheme.textMuted.withValues(alpha: 0.6),
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
            color: AppTheme.textMuted.withValues(alpha: 0.55),
          ),
        ),
      );
    }

    return TextSpan(children: spans, style: baseStyle);
  }
}
