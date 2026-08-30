import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/ui/features/studio/widgets/rich_prompt_text_controller.dart';

void main() {
  testWidgets('RichPromptTextController builds formatted TextSpan', (tester) async {
    final controller = RichPromptTextController(
      text: '{masterpiece}, 1.2::silver hair::, ~bad anatomy~, 1girl',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              final span = controller.buildTextSpan(
                context: context,
                withComposing: false,
              );

              expect(span.children, isNotNull);
              expect(span.children!.length, greaterThan(1));
              return RichText(text: span);
            },
          ),
        ),
      ),
    );

    expect(find.byType(RichText), findsOneWidget);
  });
}
