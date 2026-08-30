import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:novelai_harness/ui/features/studio/view_models/studio_view_model.dart';
import 'package:novelai_harness/ui/features/studio/widgets/agent_chat_card.dart';
import 'package:novelai_harness/ui/features/studio/widgets/agent_rewind_view.dart';
import 'package:novelai_harness/ui/features/studio/widgets/agent_session_list_view.dart';

import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late StudioViewModel viewModel;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('session_widget_test');
    viewModel = StudioViewModel();
    await viewModel.init();
  });

  tearDown(() async {
    viewModel.dispose();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  testWidgets('AgentSessionListView renders and allows switching and creating sessions', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgentSessionListView(
            viewModel: viewModel,
            onBack: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('会话管理'), findsOneWidget);
    expect(find.text('新建会话'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget); // 搜索框
  });

  testWidgets('AgentRewindView renders full card layout and allows rewind', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 800,
            child: AgentRewindView(
              viewModel: viewModel,
              onBack: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('回溯历史时刻'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('回到此时刻'), findsOneWidget);
    expect(find.text('ESC 退出'), findsOneWidget);
  });

  testWidgets('AgentChatCard integrates session view and rewind view toggles', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 800,
            width: 400,
            child: AgentChatCard(viewModel: viewModel),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byTooltip('会话管理'), findsOneWidget);

    // 1. 点击会话管理图标切至会话列表
    await tester.tap(find.byTooltip('会话管理'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('会话管理'), findsOneWidget);
    expect(find.byTooltip('返回对话'), findsOneWidget);

    // 点击返回
    await tester.tap(find.byTooltip('返回对话'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byTooltip('会话管理'), findsOneWidget);

    // 2. 模拟连续双击 ESC 切换至回溯历史时刻视图
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('回溯历史时刻'), findsOneWidget);

    // 点击回溯视图上的返回图标 (返回对话 (ESC))
    await tester.tap(find.byTooltip('返回对话 (ESC)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byTooltip('会话管理'), findsOneWidget);
  });
}
