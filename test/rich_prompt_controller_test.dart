import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/ui/features/studio/widgets/rich_prompt_text_controller.dart';

/// 展开富文本 Span 树，返回所有叶子前后顺序的 TextSpan 列表
List<TextSpan> _flatten(TextSpan span) {
  final result = <TextSpan>[];
  void walk(InlineSpan s) {
    if (s is TextSpan) {
      if (s.text != null && s.text!.isNotEmpty) result.add(s);
      s.children?.forEach(walk);
    }
  }

  span.children?.forEach(walk);
  return result;
}

void main() {
  Future<TextSpan> buildSpan(
    WidgetTester tester,
    RichPromptTextController controller,
  ) async {
    TextSpan? span;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              span = controller.buildTextSpan(
                context: context,
                withComposing: false,
              );
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    return span!;
  }

  testWidgets('RichPromptTextController builds formatted TextSpan', (
    tester,
  ) async {
    final controller = RichPromptTextController(
      text: '{masterpiece}, 1.2::silver hair::, ~bad anatomy~, 1girl',
    );

    final span = await buildSpan(tester, controller);

    expect(span.children, isNotNull);
    expect(span.children!.length, greaterThan(1));
  });

  testWidgets('closed numeric weight keeps token tint', (tester) async {
    final controller = RichPromptTextController(
      text: '1.2::silver hair::, 1girl',
    );

    final flat = _flatten(await buildSpan(tester, controller));

    final silver = flat.firstWhere((s) => s.text == 'silver hair');
    final girl = flat.firstWhere((s) => s.text == '1girl');

    expect(silver.style?.backgroundColor, isNotNull);
    expect(girl.style?.backgroundColor, isNull);
  });

  testWidgets('unclosed weight tints across commas until closing ::', (
    tester,
  ) async {
    final controller = RichPromptTextController(text: '1.5::a, b::');

    final flat = _flatten(await buildSpan(tester, controller));

    final headMarker = flat.firstWhere((s) => s.text == '1.5::');
    final a = flat.firstWhere((s) => s.text == 'a');
    final separator = flat.firstWhere((s) => s.text == ', ');
    final b = flat.firstWhere((s) => s.text == 'b');
    final tailMarker = flat.firstWhere((s) => s.text == '::');

    // 从 1.5:: 头到闭合 :: 尾的整段 (含跨逗号的分隔符) 都染权重底色
    expect(headMarker.style?.backgroundColor, isNotNull);
    expect(a.style?.backgroundColor, isNotNull);
    expect(separator.style?.backgroundColor, isNotNull);
    expect(b.style?.backgroundColor, isNotNull);
    expect(tailMarker.style?.backgroundColor, isNotNull);
  });

  testWidgets('unclosed weight tints to end of text when no closing ::', (
    tester,
  ) async {
    final controller = RichPromptTextController(text: '1.5::a, b, c');

    final flat = _flatten(await buildSpan(tester, controller));

    for (final text in ['a', 'b', 'c']) {
      final span = flat.firstWhere((s) => s.text == text);
      expect(span.style?.backgroundColor, isNotNull, reason: '$text 应被染色');
    }
  });

  testWidgets('next weight head terminates the previous region', (
    tester,
  ) async {
    // 1.5 的区域到 0.8:: 头之前结束；0.8 自己的区域照常染色
    final controller = RichPromptTextController(text: '1.5::a, 0.8::b::');

    final flat = _flatten(await buildSpan(tester, controller));

    final head15 = flat.firstWhere((s) => s.text == '1.5::');
    final a = flat.firstWhere((s) => s.text == 'a');
    final separator = flat.firstWhere((s) => s.text == ', ');
    final head08 = flat.firstWhere((s) => s.text == '0.8::');
    final b = flat.firstWhere((s) => s.text == 'b');

    expect(head15.style?.backgroundColor, isNotNull);
    expect(a.style?.backgroundColor, isNotNull);
    // 1.5 区域内的分隔符同样染色，且 0.8 头标记属于新的 0.8 区域
    expect(separator.style?.backgroundColor, isNotNull);
    expect(head08.style?.backgroundColor, isNotNull);
    expect(b.style?.backgroundColor, isNotNull);
  });

  testWidgets('plain prompt without weights has no background tint', (
    tester,
  ) async {
    final controller = RichPromptTextController(text: '1girl, solo');

    final flat = _flatten(await buildSpan(tester, controller));

    for (final span in flat) {
      expect(span.style?.backgroundColor, isNull);
    }
  });
}
