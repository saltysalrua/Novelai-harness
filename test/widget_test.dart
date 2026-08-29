import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/main.dart';

void main() {
  testWidgets('NovelAiHarnessApp basic rendering test', (WidgetTester tester) async {
    // Set a large desktop-like window size for tester
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const NovelAiHarnessApp());
    await tester.pumpAndSettle();

    // Verify Title and 3 Panes
    expect(find.text('NovelAI Harness'), findsOneWidget);
    expect(find.text('参数设置'), findsOneWidget);
    expect(find.text('图像画板'), findsOneWidget);
    expect(find.text('直接生图 (Generate)'), findsOneWidget);
  });
}
