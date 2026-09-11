import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/core/harness/context_memory.dart';
import 'package:novelai_harness/l10n/app_localizations.dart';
import 'package:novelai_harness/ui/core/theme/app_theme.dart';
import 'package:novelai_harness/ui/features/studio/widgets/chat_context_status.dart';

void main() {
  const usage = ContextUsage(
    tokens: 12000,
    window: 128000,
    compacting: true,
    noteCount: 3,
  );

  Widget buildTestWidget({required bool compact}) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: ChatContextStatus(
          usage: usage,
          modelName: 'deepseek · deepseek-chat',
          sessionUsage: '当前会话 Token 用量\n输入 1.2K · 输出 340 · 总计 1.5K',
          compact: compact,
        ),
      ),
    );
  }

  testWidgets('手机点按上下文摘要展开完整用量，不依赖悬停', (tester) async {
    await tester.pumpWidget(buildTestWidget(compact: true));
    await tester.pumpAndSettle();

    // 摘要本身保留容量、占比、笔记与压缩状态
    expect(find.text('上下文 ≈12000 / 128000'), findsOneWidget);
    expect(find.textContaining('9% · 笔记 3 · 后台压缩中'), findsOneWidget);
    expect(find.textContaining('当前会话 Token 用量'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('chat_context_details')));
    await tester.pumpAndSettle();

    expect(find.text('上下文与用量'), findsWidgets);
    expect(find.text('deepseek · deepseek-chat'), findsOneWidget);
    expect(find.textContaining('当前会话 Token 用量'), findsOneWidget);
    expect(find.textContaining('输入 1.2K'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.textContaining('当前会话 Token 用量'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('桌面保留悬停提示，不抢占点击', (tester) async {
    await tester.pumpWidget(buildTestWidget(compact: false));
    await tester.pumpAndSettle();

    expect(find.byType(Tooltip), findsOneWidget);
    expect(find.byKey(const ValueKey('chat_context_details')), findsNothing);
    expect(find.byType(InkWell), findsNothing);
  });
}
