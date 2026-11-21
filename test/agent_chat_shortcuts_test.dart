import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/core/harness/types.dart';
import 'package:novelai_harness/l10n/app_localizations.dart';
import 'package:novelai_harness/main.dart';
import 'package:novelai_harness/ui/core/locale/app_locale_controller.dart';
import 'package:novelai_harness/data/services/config_service.dart';
import 'package:novelai_harness/ui/features/studio/views/studio_view.dart';
import 'package:novelai_harness/ui/features/studio/view_models/studio_view_model.dart';
import 'package:novelai_harness/ui/features/studio/widgets/agent_chat_card.dart';
import 'package:novelai_harness/ui/features/studio/widgets/agent_chat_input_bar.dart';
import 'package:novelai_harness/ui/features/studio/widgets/agent_chat_messages.dart';
import 'package:novelai_harness/ui/features/studio/widgets/agent_rewind_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _StreamingEscapeViewModel extends StudioViewModel {
  _StreamingEscapeViewModel(String directory)
    : super(sessionLogBaseDir: directory);
  bool _streaming = true;
  int abortCount = 0;

  @override
  bool get isChatStreaming => _streaming;

  @override
  Future<void> abortChat() async {
    abortCount++;
    _streaming = false;
    notifyListeners();
  }
}

Future<void> _sendDoubleEsc(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pumpAndSettle();
}

Widget _wrapChatCard(StudioViewModel viewModel) {
  return MaterialApp(
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: SizedBox(
        height: 500,
        width: 420,
        child: ListenableBuilder(
          listenable: viewModel,
          builder: (context, _) => AgentChatCard(viewModel: viewModel),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('思考块展开与多行粘贴', () {
    late Directory tempDir;
    late StudioViewModel cardViewModel;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tempDir = await Directory.systemTemp.createTemp('ctrl_o_anchor_test');
      cardViewModel = StudioViewModel();
      await cardViewModel.init();
    });

    tearDown(() async {
      cardViewModel.dispose();
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    testWidgets('完整应用: Ctrl+O 经 HardwareKeyboard 全局分发展开思考块', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    AppLocaleController.instance.syncFromConfig(
      const AppConfig(localePreference: AppLocalePreference.zh),
    );
    addTearDown(AppLocaleController.instance.resetForTest);

    await tester.pumpWidget(const NovelAiHarnessApp());
    await tester.pumpAndSettle();

    final viewModel = StudioView.testViewModelHook;
    expect(viewModel, isNotNull);
    viewModel!.setMessagesForTesting([
      AgentMessage(
        id: 'assistant_hw',
        role: AgentRole.assistant,
        content: '硬件链路正文',
        thoughts: '硬件链路思考第一行\n硬件链路思考第二行',
      ),
    ]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final body = find.text('硬件链路思考第一行\n硬件链路思考第二行', findRichText: true);
    expect(body, findsNothing);
    expect(viewModel.isThinkingExpanded, isFalse);

    // 真实按键事件走 HardwareKeyboard 派发 (不经过焦点链)
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(viewModel.isThinkingExpanded, isTrue);
    expect(body, findsOneWidget);

    // 再按一次折叠
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(viewModel.isThinkingExpanded, isFalse);
    expect(body, findsNothing);
  });

  testWidgets('Ctrl+O 全局展开时视口顶部内容锚定不漂移', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    // 用户消息纯文本单行，助手消息携带多行思考 (展开后高度大增)
    final messages = <AgentMessage>[];
    for (var i = 0; i < 20; i++) {
      if (i.isEven) {
        messages.add(
          AgentMessage(
            id: 'user_$i',
            role: AgentRole.user,
            content: 'usermsg$i',
          ),
        );
      } else {
        messages.add(
          AgentMessage(
            id: 'assistant_$i',
            role: AgentRole.assistant,
            content: 'assistantcontent$i',
            thoughts: List.generate(
              12,
              (line) => '思考明细 $i 第 $line 行，展开后的长段落填充高度',
            ).join('\n'),
          ),
        );
      }
    }
    cardViewModel.setMessagesForTesting(messages);

    await tester.pumpWidget(_wrapChatCard(cardViewModel));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final scrollable = find.byType(Scrollable).first;
    final scrollableState = tester.state<ScrollableState>(scrollable);
    expect(scrollableState.position.maxScrollExtent, greaterThan(0));

    // 滚到列表中段，找到视口顶部第一条消息作为锚点
    scrollableState.position.jumpTo(800);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final listTop = tester.getTopLeft(find.byType(ListView)).dy;
    // 与生产 _captureTopAnchor 同判定：底缘跨过视口顶缘的首条消息。
    // 不写死下标：回复编号会抬高助手消息，jumpTo 800 时顶缘条目会随高度变化。
    AgentMessage? anchorMessage;
    double? anchorTop;
    for (final element in find.byType(AgentChatMessageItem).evaluate()) {
      final widget = element.widget as AgentChatMessageItem;
      final rect = tester.getRect(find.byWidget(widget));
      if (rect.bottom > listTop) {
        anchorMessage = widget.message;
        anchorTop = rect.top;
        break;
      }
    }
    expect(anchorMessage, isNotNull, reason: '锚点消息应已布局');
    expect(anchorTop, lessThan(listTop + 78), reason: '锚点应是视口顶缘附近条目');

    // 全局展开思考块：所有助手消息高度暴增，顶部锚点应纹丝不动
    cardViewModel.toggleThinkingExpanded();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    final afterFinder = find.byWidgetPredicate(
      (w) => w is AgentChatMessageItem && w.message.id == anchorMessage!.id,
    );
    expect(afterFinder, findsOneWidget);
    final afterTop = tester.getTopLeft(afterFinder).dy;
    expect(
      (afterTop - anchorTop!).abs(),
      lessThan(2.0),
      reason:
          '展开思考块后视口顶部内容不应漂移 '
          '(前: $anchorTop, 后: $afterTop, 消息: ${anchorMessage!.id})',
    );
  });

  testWidgets('AgentChatInputBar Shift+Enter 与多行粘贴自动滚动到底部', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(_wrapChatCard(cardViewModel));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final inputFinder = find.byType(TextField);
    expect(inputFinder, findsOneWidget);
    await tester.tap(inputFinder);
    await tester.pump();

    // 连续按 Shift+Enter 超过最大可见行数 (5 行)
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    for (var i = 0; i < 8; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final inputScrollable = find.descendant(
      of: inputFinder,
      matching: find.byType(Scrollable),
    );
    expect(inputScrollable, findsOneWidget);
    final posAfterEnter = tester.state<ScrollableState>(inputScrollable).position;
    expect(posAfterEnter.maxScrollExtent, greaterThan(0));
    expect(posAfterEnter.pixels, greaterThan(0));
    expect(
      (posAfterEnter.maxScrollExtent - posAfterEnter.pixels).abs(),
      lessThan(24.0),
    );

    // 清空后测试 Ctrl+V 多行粘贴同样自动滚动到末尾
    String? mockClipboardText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          mockClipboardText = (call.arguments as Map?)?['text'] as String?;
          return null;
        }
        if (call.method == 'Clipboard.getData') {
          return mockClipboardText == null ? null : {'text': mockClipboardText};
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    final tfWidget = tester.widget<TextField>(inputFinder);
    tfWidget.controller!.clear();
    await tester.pump();

    final pastedText = List.generate(12, (i) => 'pasted line $i').join('\n');
    await Clipboard.setData(ClipboardData(text: pastedText));
    await tester.tap(inputFinder);
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(tfWidget.controller!.text, pastedText);
    final posAfterPaste = tester.state<ScrollableState>(inputScrollable).position;
    expect(posAfterPaste.maxScrollExtent, greaterThan(0));
    expect(posAfterPaste.pixels, greaterThan(0));
    expect(
      (posAfterPaste.maxScrollExtent - posAfterPaste.pixels).abs(),
      lessThan(24.0),
    );

    // 等待草稿防抖落盘计时器 (300ms) 触发完毕，避免悬空 Timer 报错
    await tester.pump(const Duration(milliseconds: 350));
  });
  });

  group('ESC 中断与双击回溯', () {
    group('单击 Esc 中断', () {
      late Directory escapeDir;
      late _StreamingEscapeViewModel streamingVm;

      setUp(() async {
        escapeDir = Directory.systemTemp.createTempSync('escape_test_');
        SharedPreferences.setMockInitialValues({});
        streamingVm = _StreamingEscapeViewModel(escapeDir.path);
        await streamingVm.init();
      });

      tearDown(() async {
        streamingVm.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        if (escapeDir.existsSync()) escapeDir.deleteSync(recursive: true);
      });

      testWidgets('输入框聚焦时单击 Esc 中断，长按不触发回溯', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SizedBox(
                width: 400,
                child: AgentChatCard(viewModel: streamingVm),
              ),
            ),
          ),
        );
        await tester.tap(find.byType(TextField).last);
        await tester.pump();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(streamingVm.abortCount, 1);
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.escape);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(streamingVm.abortCount, 1);
        expect(find.text('回溯历史时刻'), findsNothing);
      });
    });

    group('双击 ESC 回溯', () {
      setUp(() {
        SharedPreferences.setMockInitialValues({});
        AppLocaleController.instance.syncFromConfig(
          const AppConfig(localePreference: AppLocalePreference.zh),
        );
      });

      tearDown(() {
        AppLocaleController.instance.resetForTest();
      });

      testWidgets('double ESC opens rewind from root focus (fresh start)', (
        WidgetTester tester,
      ) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        await tester.pumpWidget(const NovelAiHarnessApp());
        await tester.pumpAndSettle();

        await _sendDoubleEsc(tester);
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

        await _sendDoubleEsc(tester);
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

        final chatField = find.descendant(
          of: find.byType(AgentChatInputBar),
          matching: find.byType(TextField),
        );
        await tester.tap(chatField);
        await tester.pump();

        await _sendDoubleEsc(tester);
        expect(find.byType(AgentRewindView), findsOneWidget);

        // 单击 ESC 退出回溯
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(AgentRewindView), findsNothing);
      });
    });
  });

  group('输入法组合与剪贴板快捷键', () {
    late StudioViewModel imeVm;

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'novelai_enable_tag_dictionary_auto_update': false,
        'novelai_enable_image_persistence': false,
      });
      imeVm = StudioViewModel();
      await imeVm.init();
    });

    tearDown(() {
      imeVm.dispose();
    });

    testWidgets(
      'macOS composition Enter keeps the draft; Shift+Enter inserts a line',
      (tester) async {
        var sends = 0;
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: AgentChatInputBar(viewModel: imeVm, onSent: () => sends++),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final field = find.byType(TextField).first;
        await tester.tap(field);
        tester.testTextInput.updateEditingValue(
          const TextEditingValue(
            text: '中文输入',
            selection: TextSelection.collapsed(offset: 4),
            composing: TextRange(start: 0, end: 4),
          ),
        );
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(sends, 0);
        expect(imeVm.chatDraft, '中文输入');

        tester.testTextInput.updateEditingValue(
          const TextEditingValue(
            text: '中文输入',
            selection: TextSelection.collapsed(offset: 4),
          ),
        );
        await tester.pump();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump();
        expect(sends, 0);
        expect(imeVm.chatDraft, '中文输入\n');

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
              if (call.method == 'Clipboard.getData') {
                return {'text': '粘贴😀\n第二行'};
              }
              return null;
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null),
        );
        final controller = tester.widget<TextField>(field).controller!;
        controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: controller.text.length,
        );
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pumpAndSettle();
        expect(imeVm.chatDraft, '粘贴😀\n第二行');
        expect(sends, 0);
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpWidget(const SizedBox.shrink());
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  });
}
