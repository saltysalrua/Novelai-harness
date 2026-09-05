import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/data/services/config_service.dart';
import 'package:novelai_harness/main.dart';
import 'package:novelai_harness/ui/core/locale/app_locale_controller.dart';
import 'package:novelai_harness/ui/features/studio/widgets/agent_rewind_view.dart';

Future<void> doubleEsc(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    AppLocaleController.instance.syncFromConfig(
      const AppConfig(localePreference: AppLocalePreference.zh),
    );
  });
  tearDown(() {
    AppLocaleController.instance.resetForTest();
  });

  // 双击 ESC 计时用真实时钟，测试执行速度快于 400ms 窗口，
  // 必须拆分为独立用例避免跨场景的窗口残留误判
  testWidgets('double ESC opens rewind from root focus (fresh start)', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(const NovelAiHarnessApp());
    await tester.pumpAndSettle();

    await doubleEsc(tester);
    expect(find.byType(AgentRewindView), findsOneWidget);
  });

  testWidgets('double ESC opens rewind from left prompt panel focus', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(const NovelAiHarnessApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('提示词'));
    await tester.pumpAndSettle();
    final promptField = find.widgetWithText(
      TextField,
      '输入核心提示词或自然语言散文描述，如: 1girl, solo, silver hair, masterpiece...',
    );
    await tester.tap(promptField.first);
    await tester.pump();

    await doubleEsc(tester);
    expect(find.byType(AgentRewindView), findsOneWidget);
  });

  testWidgets('double ESC opens rewind from chat input focus', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(const NovelAiHarnessApp());
    await tester.pumpAndSettle();

    final chatField = find.widgetWithText(
      TextField,
      '输入绘画构思，或输入 /nai <词> 快速生图...',
    );
    await tester.tap(chatField);
    await tester.pump();

    await doubleEsc(tester);
    expect(find.byType(AgentRewindView), findsOneWidget);

    // 单击 ESC 退出回溯
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(AgentRewindView), findsNothing);
  });
}
