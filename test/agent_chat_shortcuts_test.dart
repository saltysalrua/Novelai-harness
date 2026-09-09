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
import 'package:novelai_harness/ui/features/studio/widgets/agent_chat_messages.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
}
