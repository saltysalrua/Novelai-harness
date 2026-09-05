import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/data/models/tag_models.dart';
import 'package:novelai_harness/ui/core/theme/app_colors_extension.dart';
import 'package:novelai_harness/ui/core/theme/app_theme.dart';
import 'package:novelai_harness/ui/core/theme/theme_context_extensions.dart';
import 'package:novelai_harness/ui/features/studio/widgets/board_wire_painter.dart';
import 'package:novelai_harness/ui/features/studio/widgets/rich_prompt_text_controller.dart';
import 'package:novelai_harness/ui/features/studio/widgets/tag_suggestion_tile.dart';

void main() {
  group('BoardGridPainter 主题重绘判定', () {
    test('dotColor 不变时不重绘，变化时重绘', () {
      const a = Color(0xFFDFDFDC);
      const b = Color(0x40FFFFFF);
      expect(
        const BoardGridPainter(
          dotColor: a,
        ).shouldRepaint(const BoardGridPainter(dotColor: a)),
        isFalse,
      );
      expect(
        const BoardGridPainter(
          dotColor: a,
        ).shouldRepaint(const BoardGridPainter(dotColor: b)),
        isTrue,
      );
    });
  });

  group('标签分类语义色统一映射', () {
    testWidgets('tagCategoryColor 全分类回落到主题调色板字段', (tester) async {
      Color? artistLight;
      Color? artistDark;
      await tester.pumpWidget(
        MaterialApp(
          key: const ValueKey('light'),
          theme: AppTheme.lightTheme,
          home: Builder(
            builder: (context) {
              artistLight = context.tagCategoryColor(
                DanbooruTagCategory.artist,
              );
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          key: const ValueKey('dark'),
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              artistDark = context.tagCategoryColor(DanbooruTagCategory.artist);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(artistLight, AppColorsExtension.light.tagArtist);
      expect(artistDark, AppColorsExtension.dark.tagArtist);
      expect(artistLight, isNot(artistDark));
    });

    testWidgets('general 分类回落正文色', (tester) async {
      Color? generalColor;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Builder(
            builder: (context) {
              generalColor = context.tagCategoryColor(
                DanbooruTagCategory.general,
              );
              return const SizedBox();
            },
          ),
        ),
      );
      expect(generalColor, AppColorsExtension.light.textPrimary);
    });
  });

  group('TagCategoryPill 分类色 SSOT', () {
    testWidgets('胶囊颜色来自主题调色板而非数据模型固定色', (tester) async {
      const pill = TagCategoryPill(category: DanbooruTagCategory.artist);
      Color? lightText;
      await tester.pumpWidget(
        MaterialApp(
          key: const ValueKey('light'),
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: Center(child: pill)),
        ),
      );
      lightText = tester.widget<Text>(find.byType(Text)).style?.color;

      await tester.pumpWidget(
        MaterialApp(
          key: const ValueKey('dark'),
          theme: AppTheme.darkTheme,
          home: const Scaffold(body: Center(child: pill)),
        ),
      );
      final darkText = tester.widget<Text>(find.byType(Text)).style?.color;

      // 与模型固定色 (0xFF8E44AD) 解耦，随主题切换
      expect(lightText, AppColorsExtension.light.tagArtist);
      expect(darkText, AppColorsExtension.dark.tagArtist);
      expect(lightText, isNot(darkText));
    });
  });

  group('RichPromptTextController 主题与内容稳定性', () {
    /// 递归提取叶子 span 文本 (用于原文往返断言)
    String collectLeafText(InlineSpan span) {
      if (span is TextSpan) {
        final own = span.text ?? '';
        final children = span.children ?? const <InlineSpan>[];
        return own + children.map(collectLeafText).join();
      }
      return '';
    }

    /// 递归查找首个匹配文本的叶子 span 颜色
    Color? findLeafColor(InlineSpan span, String target) {
      if (span is TextSpan) {
        if (span.text == target) return span.style?.color;
        for (final child in span.children ?? const <InlineSpan>[]) {
          final hit = findLeafColor(child, target);
          if (hit != null) return hit;
        }
      }
      return null;
    }

    testWidgets('原文往返：span 树拼接后与输入一字不差', (tester) async {
      const source = '{masterpiece}, 1.2::silver hair::, ~bad anatomy~, 1girl';
      final controller = RichPromptTextController(text: source);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Builder(
            builder: (context) {
              final span = controller.buildTextSpan(
                context: context,
                withComposing: false,
              );
              expect(collectLeafText(span), source);
              return RichText(text: span);
            },
          ),
        ),
      );
      // 控制器文本本身不被解析过程改写
      expect(controller.text, source);
    });

    testWidgets('selection 在 buildTextSpan 前后保持不变', (tester) async {
      final controller = RichPromptTextController(text: 'silver hair, 1girl');
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 6,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Builder(
            builder: (context) {
              final span = controller.buildTextSpan(
                context: context,
                withComposing: false,
              );
              return RichText(text: span);
            },
          ),
        ),
      );

      expect(
        controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: 6),
      );
    });

    testWidgets('权重升色随主题切换 (亮蓝 → 暗蓝)', (tester) async {
      final controller = RichPromptTextController(text: '{zzqqxxww}');

      Color? lightColor;
      await tester.pumpWidget(
        MaterialApp(
          key: const ValueKey('light'),
          theme: AppTheme.lightTheme,
          home: Builder(
            builder: (context) {
              final span = controller.buildTextSpan(
                context: context,
                withComposing: false,
              );
              lightColor = findLeafColor(span, 'zzqqxxww');
              return RichText(text: span);
            },
          ),
        ),
      );

      Color? darkColor;
      await tester.pumpWidget(
        MaterialApp(
          key: const ValueKey('dark'),
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              final span = controller.buildTextSpan(
                context: context,
                withComposing: false,
              );
              darkColor = findLeafColor(span, 'zzqqxxww');
              return RichText(text: span);
            },
          ),
        ),
      );

      expect(lightColor, AppColorsExtension.light.primary);
      expect(darkColor, AppColorsExtension.dark.primary);
      expect(lightColor, isNot(darkColor));
    });

    testWidgets('关闭高亮时返回纯文本 span', (tester) async {
      final controller = RichPromptTextController(text: '{masterpiece}, 1girl');

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Builder(
            builder: (context) {
              final span = controller.buildTextSpan(
                context: context,
                withComposing: false,
              );
              return RichText(text: span);
            },
          ),
        ),
      );

      controller.setHighlightOptions(highlightEnabled: false);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Builder(
            builder: (context) {
              final span = controller.buildTextSpan(
                context: context,
                withComposing: false,
              );
              // 关闭高亮：单叶子、无子结构、颜色为正文色
              expect(span.children, isNull);
              expect(collectLeafText(span), '{masterpiece}, 1girl');
              return RichText(text: span);
            },
          ),
        ),
      );
    });
  });
}
