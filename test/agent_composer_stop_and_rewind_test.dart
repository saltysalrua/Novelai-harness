import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/core/harness/types.dart';
import 'package:novelai_harness/data/models/novelai_models.dart';
import 'package:novelai_harness/l10n/app_localizations.dart';
import 'package:novelai_harness/ui/features/studio/view_models/studio_view_model.dart';
import 'package:novelai_harness/ui/features/studio/widgets/agent_chat_card.dart';
import 'package:novelai_harness/ui/features/studio/widgets/agent_chat_input_bar.dart';
import 'package:novelai_harness/ui/features/studio/widgets/agent_chat_messages.dart';
import 'package:novelai_harness/ui/features/studio/widgets/agent_rewind_view.dart';
import 'package:novelai_harness/ui/features/studio/widgets/chat_image_attachment.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 1x1 PNG，供回溯后的附件缩略图在测试里解码。
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

Widget _wrap(Widget child) {
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
    tempDir = await Directory.systemTemp.createTemp('composer_stop_rewind');
    viewModel = StudioViewModel();
    await viewModel.init();
  });

  tearDown(() async {
    viewModel.dispose();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  test('回溯用户消息会截断该条及之后的记录，并把文本和图片放回草稿', () async {
    final image = AgentMessageImage.fromBytes(bytes: _png);
    viewModel.setMessagesForTesting([
      AgentMessage(id: 'keep_user', role: AgentRole.user, content: '更早保留'),
      AgentMessage(
        id: 'keep_reply',
        role: AgentRole.assistant,
        content: '保留答复',
      ),
      AgentMessage(
        id: 'edit_user',
        role: AgentRole.user,
        content: '要编辑的问题',
        images: [image],
      ),
      AgentMessage(
        id: 'edit_reply',
        role: AgentRole.assistant,
        content: '稍后答复',
      ),
    ]);

    await viewModel.rewindToMessage('edit_user');

    expect(viewModel.isChatStreaming, isFalse);
    expect(viewModel.messages.map((m) => m.id), ['keep_user', 'keep_reply']);
    expect(viewModel.chatDraft, '要编辑的问题');
    expect(viewModel.composerRestore?.text, '要编辑的问题');
    expect(viewModel.composerRestore?.images.single.base64, image.base64);
    expect(
      viewModel.statusMessage,
      anyOf(contains('放回输入框'), contains('back in the input')),
    );
    expect(
      viewModel.statusMessage,
      anyOf(contains('不会自动发送'), contains('Nothing was sent')),
    );
  });

  test('/undo 把最后一条用户消息放回草稿，不启动新的生成', () async {
    final image = AgentMessageImage.fromBytes(bytes: _png);
    viewModel.setMessagesForTesting([
      AgentMessage(id: 'u1', role: AgentRole.user, content: '第一句'),
      AgentMessage(id: 'a1', role: AgentRole.assistant, content: '答复'),
      AgentMessage(
        id: 'u2',
        role: AgentRole.user,
        content: '第二句',
        images: [image],
      ),
      AgentMessage(id: 'a2', role: AgentRole.assistant, content: '答复二'),
    ]);

    await viewModel.sendChatMessage('/undo');

    expect(viewModel.isChatStreaming, isFalse);
    expect(viewModel.messages.map((m) => m.id), ['u1', 'a1']);
    expect(viewModel.chatDraft, '第二句');
    expect(viewModel.composerRestore?.images, isNotEmpty);

    viewModel.acknowledgeComposerRestore(viewModel.composerRestore!.epoch);
    viewModel.setMessagesForTesting([
      AgentMessage(id: 'only', role: AgentRole.user, content: '只有这句'),
    ]);
    await viewModel.sendChatMessage('/undo');
    expect(viewModel.messages.where((m) => m.role == AgentRole.user), isEmpty);
    expect(viewModel.chatDraft, '只有这句');
    expect(viewModel.isChatStreaming, isFalse);
  });

  testWidgets('桌面端生成时发送键变成停止键，顶栏不再有第二颗停止键', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      _wrap(
        SizedBox(
          width: 420,
          height: 640,
          child: ListenableBuilder(
            listenable: viewModel,
            builder: (context, _) => AgentChatCard(viewModel: viewModel),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('chat_send_button')), findsOneWidget);
    expect(find.byIcon(Icons.stop_rounded), findsNothing);
    expect(find.byTooltip('发送（Enter）'), findsOneWidget);

    viewModel.setChatStreamingForTesting(true);
    await tester.pump();

    expect(find.byKey(const ValueKey('chat_stop_button')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat_send_button')), findsNothing);
    expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
    expect(find.byTooltip('停止输出 (Esc)'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('chat_stop_button')));
    await tester.pump();
    expect(
      viewModel.statusMessage,
      anyOf('已强制终止当前生成', 'Current generation force-terminated'),
    );

    viewModel.setChatStreamingForTesting(false);
    await tester.pump();
    expect(find.byKey(const ValueKey('chat_send_button')), findsOneWidget);
    expect(find.byIcon(Icons.stop_rounded), findsNothing);
  });

  testWidgets('窄屏生成时停止键仍在发送键位置，提示不带 Esc', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    viewModel.setChatStreamingForTesting(true);
    await tester.pumpWidget(
      _wrap(
        SizedBox(
          width: 360,
          height: 700,
          child: AgentChatInputBar(viewModel: viewModel, compact: true),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('chat_stop_button')), findsOneWidget);
    expect(find.byTooltip('停止输出'), findsOneWidget);
    expect(find.byTooltip('停止输出 (Esc)'), findsNothing);
  });

  testWidgets('生成中按 Enter 不发送草稿，也不停止', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    var sends = 0;
    viewModel.setChatStreamingForTesting(true);
    await tester.pumpWidget(
      _wrap(
        SizedBox(
          width: 420,
          height: 320,
          child: AgentChatInputBar(viewModel: viewModel, onSent: () => sends++),
        ),
      ),
    );
    await tester.pump();

    final field = find.byType(TextField);
    await tester.tap(field);
    await tester.pump();
    await tester.enterText(field, '还没发出的草稿');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(sends, 0);
    expect(viewModel.isChatStreaming, isTrue);
    expect(viewModel.chatDraft, '还没发出的草稿');
    expect(find.byKey(const ValueKey('chat_stop_button')), findsOneWidget);
    // 草稿防抖落盘计时器必须走完，否则用例结束时仍有未触发的 Timer。
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('从回溯视图确认后，消息回到输入框且不会重新发送', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final image = AgentMessageImage.fromBytes(bytes: _png);
    viewModel.setMessagesForTesting([
      AgentMessage(id: 'keep_user', role: AgentRole.user, content: '更早保留'),
      AgentMessage(
        id: 'keep_reply',
        role: AgentRole.assistant,
        content: '保留答复',
      ),
      AgentMessage(
        id: 'edit_user',
        role: AgentRole.user,
        content: '要编辑的问题',
        images: [image],
      ),
      AgentMessage(
        id: 'edit_reply',
        role: AgentRole.assistant,
        content: '稍后答复',
      ),
    ]);

    await tester.pumpWidget(
      _wrap(
        SizedBox(
          width: 420,
          height: 720,
          child: ListenableBuilder(
            listenable: viewModel,
            builder: (context, _) => AgentChatCard(viewModel: viewModel),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('回溯历史时刻'), findsOneWidget);
    await tester.tap(find.text('#2'));
    // 列表项同时有双击确认，单击要等双击窗口结束才会选中。
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('已选择第 #'), findsOneWidget);
    await tester.tap(find.text('回到此时刻'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('回溯历史时刻'), findsNothing);
    expect(viewModel.isChatStreaming, isFalse);
    expect(viewModel.messages.map((m) => m.id), ['keep_user', 'keep_reply']);
    expect(find.byType(ChatImageThumbnail), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, '要编辑的问题');
    expect(
      find.byWidgetPredicate(
        (widget) => widget is SelectableText && widget.data == '要编辑的问题',
      ),
      findsNothing,
    );
  });

  testWidgets('输入栏已打开时回溯，文本和图片也会写回输入框', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final image = AgentMessageImage.fromBytes(bytes: _png);
    viewModel.setMessagesForTesting([
      AgentMessage(
        id: 'edit_user',
        role: AgentRole.user,
        content: '直接撤回',
        images: [image],
      ),
      AgentMessage(id: 'edit_reply', role: AgentRole.assistant, content: '答复'),
    ]);

    await tester.pumpWidget(
      _wrap(
        SizedBox(
          width: 420,
          height: 640,
          child: ListenableBuilder(
            listenable: viewModel,
            builder: (context, _) => AgentChatInputBar(viewModel: viewModel),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.runAsync(() => viewModel.rewindToMessage('edit_user'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 400));

    expect(viewModel.isChatStreaming, isFalse);
    expect(viewModel.messages, isEmpty);
    expect(viewModel.composerRestore, isNull);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, '直接撤回');
    expect(find.byType(ChatImageThumbnail), findsOneWidget);
  });

  testWidgets('配对的工具调用与结果合并渲染为单张步骤卡，点击同时展开入参与输出', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    viewModel.setMessagesForTesting([
      AgentMessage(id: 'u1', role: AgentRole.user, content: '帮我查词库'),
      AgentMessage(
        id: 'a1',
        role: AgentRole.assistant,
        content: '查询完成。',
        toolCalls: const [
          ToolCall(
            id: 'call_1',
            name: 'search_danbooru_tags',
            arguments: {'query': 'silver_hair'},
          ),
        ],
      ),
      AgentMessage(
        id: 't1',
        role: AgentRole.tool,
        toolCallId: 'call_1',
        toolName: 'search_danbooru_tags',
        content: 'matched: silver_hair (99999)\ndetail: count=42',
      ),
    ]);

    await tester.pumpWidget(
      _wrap(
        SizedBox(
          width: 480,
          height: 600,
          child: ListenableBuilder(
            listenable: viewModel,
            builder: (context, _) => AgentChatCard(viewModel: viewModel),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(ToolCallBlock), findsOneWidget);
    expect(find.byType(ToolResultBlock), findsNothing);
    expect(find.textContaining('"query": "silver_hair"'), findsNothing);
    expect(find.textContaining('detail: count=42'), findsNothing);

    await tester.tap(
      find.descendant(
        of: find.byType(ToolCallBlock),
        matching: find.byType(InkWell),
      ),
    );
    await tester.pump();

    expect(find.textContaining('"query": "silver_hair"'), findsOneWidget);
    expect(find.textContaining('detail: count=42'), findsOneWidget);
  });

  testWidgets('用户气泡行内编辑撤回按钮将消息恢复到输入框，顶栏回溯按钮可打开回溯视图', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final image = AgentMessageImage.fromBytes(bytes: _png);
    viewModel.setMessagesForTesting([
      AgentMessage(id: 'keep_user', role: AgentRole.user, content: '保留的问题'),
      AgentMessage(
        id: 'keep_reply',
        role: AgentRole.assistant,
        content: '保留的答复',
      ),
      AgentMessage(
        id: 'edit_user',
        role: AgentRole.user,
        content: '二次编辑问题',
        images: [image],
      ),
      AgentMessage(
        id: 'edit_reply',
        role: AgentRole.assistant,
        content: '稍后的答复',
      ),
    ]);

    await tester.pumpWidget(
      _wrap(
        SizedBox(
          width: 480,
          height: 640,
          child: ListenableBuilder(
            listenable: viewModel,
            builder: (context, _) => AgentChatCard(viewModel: viewModel),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final rewindBtn = find.byKey(const ValueKey('user_msg_rewind_edit_user'));
    await tester.ensureVisible(rewindBtn);
    await tester.tap(rewindBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 400));

    expect(viewModel.messages.map((m) => m.id).toList(), [
      'keep_user',
      'keep_reply',
    ]);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, '二次编辑问题');
    expect(find.byType(ChatImageThumbnail), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('chat_rewind_button')));
    await tester.pump();
    expect(find.byType(AgentRewindView), findsOneWidget);
  });

  testWidgets('空会话不渲染欢迎页与建议按钮，合并模型思考选择器支持搜索与档位切换', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      _wrap(
        SizedBox(
          width: 480,
          height: 640,
          child: ListenableBuilder(
            listenable: viewModel,
            builder: (context, _) => AgentChatCard(viewModel: viewModel),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('chat_empty_suggestion_0')), findsNothing);
    expect(find.byKey(const ValueKey('chat_model_selector')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('chat_model_selector')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('chat_model_search_field')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('chat_thinking_selector')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('chat_model_option_deepseek-flash')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('chat_model_option_deepseek-v4-pro')),
      findsOneWidget,
    );

    final thinkingBar = find.byKey(const ValueKey('chat_thinking_selector'));
    final l10n = AppLocalizations.of(tester.element(thinkingBar));
    await tester.tap(
      find.descendant(
        of: thinkingBar,
        matching: find.text(l10n.chatThinkingEffortLow),
      ),
    );
    await tester.pump();
    expect(viewModel.currentThinkingEffort, ThinkingEffort.low);

    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('chat_model_search_field')),
        matching: find.byType(TextField),
      ),
      'pro',
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('chat_model_option_deepseek-flash')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('chat_model_option_deepseek-v4-pro')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('chat_model_option_deepseek-v4-pro')),
    );
    await tester.pumpAndSettle();

    // 选择模型后弹窗保持打开，便于顺手修改思考强度；直到点击外部或关闭才收回
    expect(
      viewModel.config.activeLlmProvider.activeModel.id,
      'deepseek-v4-pro',
    );
    expect(
      find.byKey(const ValueKey('chat_model_search_field')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('chat_thinking_selector')),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('chat_thinking_selector')),
        matching: find.text(l10n.chatThinkingEffortHigh),
      ),
    );
    await tester.pump();
    expect(viewModel.currentThinkingEffort, ThinkingEffort.high);

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat_model_search_field')), findsNothing);
  });

  testWidgets('360px 窄屏一体化底部工具栏同时容纳合并模型思考触发器、上下文与发送键且不溢出', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    expect(
      viewModel.config.activeLlmProvider.activeModel.supportsThinking,
      isTrue,
    );

    await tester.pumpWidget(
      _wrap(
        SizedBox(
          width: 360,
          height: 260,
          child: AgentChatInputBar(viewModel: viewModel, compact: true),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('chat_model_selector')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat_context_details')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat_send_button')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('chat_model_selector')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('chat_model_search_field')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('chat_thinking_selector')),
      findsOneWidget,
    );
  });

  testWidgets('桌面端右侧栏打开模型思考与上下文浮层时锚定在触发器所在右侧栏，不居中遮挡画布', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      _wrap(
        Align(
          alignment: Alignment.bottomRight,
          child: SizedBox(
            width: 360,
            child: AgentChatInputBar(viewModel: viewModel),
          ),
        ),
      ),
    );
    await tester.pump();

    // 验证底部触发的模型/思考浮层出现在右侧栏内且位于触发按钮上方
    final modelTriggerRect = tester.getRect(
      find.byKey(const ValueKey('chat_model_selector')),
    );
    await tester.tap(find.byKey(const ValueKey('chat_model_selector')));
    await tester.pumpAndSettle();

    final searchRect = tester.getRect(
      find.byKey(const ValueKey('chat_model_search_field')),
    );
    expect(searchRect.left, greaterThanOrEqualTo(1000));
    expect(searchRect.bottom, lessThan(modelTriggerRect.top));

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    // 验证上下文记忆详情浮层也锚定在右侧栏内，而不是窗口底部居中
    await tester.tap(find.byKey(const ValueKey('chat_context_details')));
    await tester.pumpAndSettle();

    final contextTitle = find.text(
      AppLocalizations.of(
        tester.element(find.byKey(const ValueKey('chat_context_details'))),
      ).chatContextTitle,
    );
    final contextTitleRect = tester.getRect(contextTitle);
    expect(contextTitleRect.left, greaterThanOrEqualTo(1000));
    expect(contextTitleRect.bottom, lessThan(modelTriggerRect.top));
  });
}
