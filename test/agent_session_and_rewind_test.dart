import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:novelai_harness/core/harness/types.dart';
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

  testWidgets('AgentChatCard auto-scrolls to bottom during streaming when at bottom, and stays in place when user scrolls up', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    // 填充多条较长消息使 ListView 产生滚动条
    final initialMessages = List.generate(
      15,
      (i) => AgentMessage(
        id: 'msg_$i',
        role: i.isEven ? AgentRole.user : AgentRole.assistant,
        content: 'This is message number $i with long text line 1\nline 2\nline 3 to ensure large height.',
      ),
    );
    viewModel.setMessagesForTesting(initialMessages);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 500,
            width: 400,
            child: ListenableBuilder(
              listenable: viewModel,
              builder: (context, _) => AgentChatCard(viewModel: viewModel),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final scrollableFinder = find.byType(Scrollable).first;
    ScrollableState scrollable = tester.state(scrollableFinder);
    final initialMax = scrollable.position.maxScrollExtent;
    expect(initialMax, greaterThan(0));

    // 1. 空闲状态下 (isChatStreaming == false)：用户向上滚动完全自由，绝对没有任何吸附效果
    scrollable.position.jumpTo(200);
    await tester.pump();
    expect(scrollable.position.pixels, equals(200));

    // 2. 处于最底部时开启流式输出：自动跟随并保持在最底部
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    viewModel.setChatStreamingForTesting(true);
    final updatedMessages = [
      ...initialMessages,
      AgentMessage(
        id: 'msg_stream_1',
        role: AgentRole.assistant,
        content: 'New streaming message chunk 1\nLine 2\nLine 3\nLine 4\nLine 5',
      ),
    ];
    viewModel.setMessagesForTesting(updatedMessages);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    scrollable = tester.state(scrollableFinder);
    final newMax1 = scrollable.position.maxScrollExtent;
    expect(newMax1, greaterThan(initialMax));
    expect(scrollable.position.pixels, equals(newMax1));

    // 3. 用户在流式过程中主动向上翻看历史消息 (例如跳至 300px)
    scrollable.position.jumpTo(300);
    await tester.pump();
    expect(scrollable.position.pixels, equals(300));

    // 4. 流式继续输出更多内容：因为用户当前不在底部 (extentAfter > 32px)，视图严格保持在 300px，绝不强拉
    final moreMessages = [
      ...updatedMessages,
      AgentMessage(
        id: 'msg_stream_2',
        role: AgentRole.assistant,
        content: 'New streaming message chunk 2\nMore Lines\nEven more lines',
      ),
    ];
    viewModel.setMessagesForTesting(moreMessages);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    scrollable = tester.state(scrollableFinder);
    expect(scrollable.position.pixels, equals(300));

    // 5. 用户滚回底部后，新到来的流式内容重新自动跟随到底部
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    await tester.pump();

    final finalMessages = [
      ...moreMessages,
      AgentMessage(
        id: 'msg_stream_3',
        role: AgentRole.assistant,
        content: 'Final chunk tracking bottom',
      ),
    ];
    viewModel.setMessagesForTesting(finalMessages);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    scrollable = tester.state(scrollableFinder);
    expect((scrollable.position.pixels - scrollable.position.maxScrollExtent).abs(), lessThanOrEqualTo(15.0));

    viewModel.setChatStreamingForTesting(false);
  });
}
