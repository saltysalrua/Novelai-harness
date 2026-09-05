import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:novelai_harness/core/harness/tools/ask_user_tool.dart';
import 'package:novelai_harness/core/harness/types.dart';
import 'package:novelai_harness/l10n/app_localizations.dart';
import 'package:novelai_harness/ui/features/studio/view_models/studio_view_model.dart';
import 'package:novelai_harness/ui/features/studio/widgets/agent_chat_card.dart';
import 'package:novelai_harness/ui/features/studio/widgets/agent_rewind_view.dart';
import 'package:novelai_harness/ui/features/studio/widgets/agent_session_list_view.dart';
import 'package:novelai_harness/ui/features/studio/widgets/inline_agent_question_card.dart';

import 'package:shared_preferences/shared_preferences.dart';

Widget buildTestApp(Widget child) {
  return MaterialApp(
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}

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

  testWidgets(
    'AgentSessionListView renders and allows switching and creating sessions',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        buildTestApp(AgentSessionListView(viewModel: viewModel, onBack: () {})),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('会话管理'), findsOneWidget);
      expect(find.text('新建会话'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget); // 搜索框
    },
  );

  testWidgets('AgentRewindView renders full card layout and allows rewind', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      buildTestApp(
        SizedBox(
          width: 400,
          height: 800,
          child: AgentRewindView(viewModel: viewModel, onBack: () {}),
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
      buildTestApp(
        SizedBox(
          height: 800,
          width: 400,
          child: AgentChatCard(viewModel: viewModel),
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

  testWidgets(
    'AgentChatCard auto-scrolls to bottom during streaming when at bottom, and stays in place when user scrolls up',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      // 填充多条较长消息使 ListView 产生滚动条
      final initialMessages = List.generate(
        15,
        (i) => AgentMessage(
          id: 'msg_$i',
          role: i.isEven ? AgentRole.user : AgentRole.assistant,
          content:
              'This is message number $i with long text line 1\nline 2\nline 3 to ensure large height.',
        ),
      );
      viewModel.setMessagesForTesting(initialMessages);

      await tester.pumpWidget(
        buildTestApp(
          SizedBox(
            height: 500,
            width: 400,
            child: ListenableBuilder(
              listenable: viewModel,
              builder: (context, _) => AgentChatCard(viewModel: viewModel),
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
          content:
              'New streaming message chunk 1\nLine 2\nLine 3\nLine 4\nLine 5',
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
      expect(
        (scrollable.position.pixels - scrollable.position.maxScrollExtent)
            .abs(),
        lessThanOrEqualTo(15.0),
      );

      viewModel.setChatStreamingForTesting(false);
    },
  );

  testWidgets('近期 Markdown 离屏后保留 Element，同 id 内容更新不读旧缓存', (tester) async {
    final messages = List.generate(
      60,
      (i) => AgentMessage(
        id: 'retained_$i',
        role: AgentRole.assistant,
        content: '''**Message $i**

First paragraph

Second paragraph''',
      ),
    );
    messages[1] = AgentMessage(
      id: 'retained_1',
      role: AgentRole.tool,
      content: 'Image preview',
      imageBase64: base64Encode(
        img.encodePng(img.Image(width: 160, height: 24)),
      ),
    );
    viewModel.setMessagesForTesting(messages);
    await tester.pumpWidget(
      buildTestApp(
        ListenableBuilder(
          listenable: viewModel,
          builder: (context, _) => AgentChatCard(viewModel: viewModel),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    position.jumpTo(0);
    await tester.pumpAndSettle();
    final markdown = find.descendant(
      of: find.byKey(const ValueKey('retained_0')),
      matching: find.byType(MarkdownBody),
    );
    final element = tester.element(markdown);
    final image = find.descendant(
      of: find.byKey(const ValueKey('retained_1')),
      matching: find.byType(Image),
    );
    final imageElement = tester.element(image);
    final imageHeight = tester.getSize(image).height;
    position.jumpTo(2500);
    await tester.pumpAndSettle();
    expect(element.mounted, isTrue);
    expect(imageElement.mounted, isTrue);
    position.jumpTo(0);
    await tester.pumpAndSettle();
    expect(tester.element(markdown), same(element));
    expect(tester.element(image), same(imageElement));
    expect(tester.getSize(image).height, imageHeight);
    expect(position.pixels, 0);

    viewModel.setMessagesForTesting([
      messages.first.copyWith(content: 'Updated content'),
      ...messages.skip(1),
    ]);
    await tester.pumpAndSettle();
    expect(tester.widget<MarkdownBody>(markdown).data, 'Updated content');
  });

  testWidgets('流式中微小向上滚轮也立即取消底部跟随', (tester) async {
    viewModel.setMessagesForTesting(
      List.generate(
        20,
        (i) => AgentMessage(
          id: 'wheel_$i',
          role: AgentRole.assistant,
          content: '''Message $i

Paragraph one

Paragraph two''',
        ),
      ),
    );
    await tester.pumpWidget(
      buildTestApp(
        ListenableBuilder(
          listenable: viewModel,
          builder: (context, _) => AgentChatCard(viewModel: viewModel),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final scrollable = find.byType(Scrollable).first;
    final position = tester.state<ScrollableState>(scrollable).position;
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    viewModel.setChatStreamingForTesting(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final bottom = position.pixels;
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(scrollable),
        scrollDelta: const Offset(0, -20),
      ),
    );
    viewModel.streamingText.appendContent('Streaming content');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(position.pixels, lessThan(bottom - 10));
    final afterWheel = position.pixels;
    viewModel.streamingText.appendContent(' more');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(position.pixels, closeTo(afterWheel, 0.5));
    viewModel.setChatStreamingForTesting(false);
    await tester.pumpAndSettle();
  });

  testWidgets('InlineAgentQuestionCard renders and handles user response', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final completer = Completer<List<String>?>();
    final prompt = AgentQuestionPrompt(
      questions: const [
        AgentQuestion(
          header: '向用户提问',
          question: '请选择生图风格',
          options: [
            AgentQuestionOption(label: '二次元动漫', description: '日系赛璐珞风格'),
            AgentQuestionOption(label: '写实厚涂', description: '半厚涂光影质感'),
          ],
        ),
      ],
      completer: completer,
    );

    await tester.pumpWidget(
      buildTestApp(InlineAgentQuestionCard(prompt: prompt)),
    );
    await tester.pump();

    expect(find.text('向用户提问'), findsOneWidget);
    expect(find.text('待确认'), findsOneWidget);
    expect(find.text('请选择生图风格'), findsOneWidget);
    expect(find.text('二次元动漫'), findsOneWidget);
    expect(find.text('写实厚涂'), findsOneWidget);

    // Tap second option
    await tester.tap(find.text('写实厚涂'));
    await tester.pump();

    // Tap submit button
    await tester.tap(find.text('提交回答'));
    await tester.pump();

    expect(completer.isCompleted, isTrue);
    final result = await completer.future;
    expect(result, equals(['写实厚涂']));
  });

  testWidgets('InlineAgentQuestionCard renders binary confirm card', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final completer = Completer<List<String>?>();
    final prompt = AgentQuestionPrompt(
      questions: const [
        AgentQuestion(
          header: '付费确认 (消耗点数)',
          question: '是否确认消耗 15 点数生成？',
          allowCustomInput: false,
          options: [
            AgentQuestionOption(label: '确认生成'),
            AgentQuestionOption(label: '取消生图'),
          ],
        ),
      ],
      completer: completer,
    );

    await tester.pumpWidget(
      buildTestApp(InlineAgentQuestionCard(prompt: prompt)),
    );
    await tester.pump();

    expect(find.text('付费确认 (消耗点数)'), findsOneWidget);
    expect(find.text('待确认'), findsOneWidget);
    expect(find.text('确认生成'), findsOneWidget);
    expect(find.text('取消生图'), findsOneWidget);

    await tester.tap(find.text('确认生成'));
    await tester.pump();

    expect(completer.isCompleted, isTrue);
    final result = await completer.future;
    expect(result, equals(['确认生成']));
  });
}
