import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/core/harness/types.dart';
import 'package:novelai_harness/l10n/app_localizations.dart';
import 'package:novelai_harness/ui/features/studio/widgets/agent_chat_messages.dart';

void main() {
  testWidgets('历史重复或空工具 ID 不撞键，折叠状态独立且追加重建后保留', (tester) async {
    final calls = [
      ToolCall(
        id: 'toolu_duplicate',
        name: 'echo',
        arguments: {'text': 'first'},
      ),
      ToolCall(
        id: 'toolu_duplicate',
        name: 'echo',
        arguments: {'text': 'second'},
      ),
      ToolCall(id: '', name: 'echo', arguments: {'text': 'third'}),
      ToolCall(id: '', name: 'echo', arguments: {'text': 'fourth'}),
    ];

    Future<void> render({bool updated = false}) => tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: AgentChatMessageItem(
              message: AgentMessage(
                id: 'historical_assistant',
                role: AgentRole.assistant,
                content: '历史回复',
                thoughts: updated ? '后来恢复的思考' : '',
                toolCalls: [
                  ...calls,
                  if (updated)
                    ToolCall(
                      id: 'toolu_duplicate',
                      name: 'echo',
                      arguments: {'text': 'fifth'},
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await render();
    expect(tester.takeException(), isNull);
    expect(find.byType(ToolCallBlock), findsNWidgets(4));
    await tester.tap(
      find.descendant(
        of: find.byType(ToolCallBlock).at(1),
        matching: find.byType(InkWell),
      ),
    );
    await tester.pumpAndSettle();
    const secondBody = '{\n  "text": "second"\n}';
    expect(find.text(secondBody), findsOneWidget);
    expect(find.text('{\n  "text": "first"\n}'), findsNothing);

    await render(updated: true);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(ToolCallBlock), findsNWidgets(5));
    expect(find.text(secondBody), findsOneWidget);
    expect(find.text('{\n  "text": "fifth"\n}'), findsNothing);
    expect(calls.map((call) => call.id), [
      'toolu_duplicate',
      'toolu_duplicate',
      '',
      '',
    ]);
  });
}
