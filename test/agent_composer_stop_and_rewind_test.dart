import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/core/harness/types.dart';
import 'package:novelai_harness/l10n/app_localizations.dart';
import 'package:novelai_harness/ui/features/studio/view_models/studio_view_model.dart';
import 'package:novelai_harness/ui/features/studio/widgets/agent_chat_card.dart';
import 'package:novelai_harness/ui/features/studio/widgets/agent_chat_input_bar.dart';
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
    expect(viewModel.statusMessage, contains('放回输入框'));
    expect(viewModel.statusMessage, contains('不会自动发送'));
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
    expect(viewModel.statusMessage, '已强制终止当前生成');

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
    await tester.tap(find.text('要编辑的问题'));
    await tester.pump();
    await tester.tap(find.text('回到此时刻'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

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

    await viewModel.rewindToMessage('edit_user');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(viewModel.isChatStreaming, isFalse);
    expect(viewModel.messages, isEmpty);
    expect(viewModel.composerRestore, isNull);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, '直接撤回');
    expect(find.byType(ChatImageThumbnail), findsOneWidget);
  });
}
