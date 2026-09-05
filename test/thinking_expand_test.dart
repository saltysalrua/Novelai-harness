import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/core/harness/types.dart';
import 'package:novelai_harness/l10n/app_localizations.dart';
import 'package:novelai_harness/ui/features/studio/widgets/agent_chat_blocks.dart';
import 'package:novelai_harness/ui/features/studio/widgets/agent_chat_messages.dart';

void main() {
  const thoughts = '第一行构思：先确定画面主体。\n第二行构思：再补充光影与氛围。';
  const secondLine = '第二行构思：再补充光影与氛围。';

  Widget wrap(Widget child) => MaterialApp(
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData(useMaterial3: true),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  /// 思考块正文使用 SelectableText，折叠时整个组件不渲染
  /// (仅在 ThinkingBlock 子树内查找，避免 Markdown 正文的干扰)
  Finder findThoughtsBody() => find.descendant(
    of: find.byType(ThinkingBlock),
    matching: find.byType(SelectableText),
  );
  bool bodyVisible(WidgetTester tester, String line) {
    if (findThoughtsBody().evaluate().isEmpty) return false;
    final widget = tester.widget<SelectableText>(findThoughtsBody().first);
    return (widget.data ?? '').contains(line);
  }

  group('ThinkingBlock fold & Ctrl+O expand', () {
    testWidgets('默认折叠：只显示单行预览，正文不渲染', (tester) async {
      await tester.pumpWidget(wrap(const ThinkingBlock(thoughts: thoughts)));

      expect(find.text('思考过程'), findsOneWidget);
      expect(find.textContaining('第一行构思'), findsOneWidget); // 头部预览
      expect(findThoughtsBody(), findsNothing);
    });

    testWidgets('点击头部可手动展开与再次折叠', (tester) async {
      await tester.pumpWidget(wrap(const ThinkingBlock(thoughts: thoughts)));

      await tester.tap(find.text('思考过程'));
      await tester.pumpAndSettle();
      expect(bodyVisible(tester, secondLine), isTrue);

      await tester.tap(find.text('思考过程'));
      await tester.pumpAndSettle();
      expect(findThoughtsBody(), findsNothing);
    });

    testWidgets('forceExpanded (Ctrl+O) 强制展开，关闭后恢复折叠', (tester) async {
      await tester.pumpWidget(
        wrap(const ThinkingBlock(thoughts: thoughts, forceExpanded: true)),
      );
      expect(bodyVisible(tester, secondLine), isTrue);

      // 全局开关关闭后恢复折叠
      await tester.pumpWidget(
        wrap(const ThinkingBlock(thoughts: thoughts, forceExpanded: false)),
      );
      await tester.pumpAndSettle();
      expect(findThoughtsBody(), findsNothing);
    });

    testWidgets('AssistantMessageItem 透传 thinkingExpanded 给思考块', (
      tester,
    ) async {
      final message = AgentMessage(
        id: 'asst_1',
        role: AgentRole.assistant,
        content: '正文回答',
        thoughts: thoughts,
      );

      await tester.pumpWidget(wrap(AssistantMessageItem(message: message)));
      expect(findThoughtsBody(), findsNothing);

      await tester.pumpWidget(
        wrap(AssistantMessageItem(message: message, thinkingExpanded: true)),
      );
      expect(bodyVisible(tester, secondLine), isTrue);
    });
  });

  group('StreamingMessageBubble expanded', () {
    testWidgets('流式思考渲染全文，展开开关不截断', (tester) async {
      await tester.pumpWidget(
        wrap(const StreamingMessageBubble(thoughts: thoughts, content: '')),
      );
      expect(find.textContaining('第一行构思'), findsOneWidget);

      await tester.pumpWidget(
        wrap(
          const StreamingMessageBubble(
            thoughts: thoughts,
            content: '',
            thinkingExpanded: true,
          ),
        ),
      );
      expect(find.textContaining(secondLine), findsOneWidget);
    });
  });
}
