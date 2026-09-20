import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:novelai_harness/l10n/app_localizations.dart';
import 'package:novelai_harness/ui/features/studio/view_models/studio_view_model.dart';
import 'package:novelai_harness/ui/features/studio/widgets/agent_chat_input_bar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StudioViewModel vm;
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'novelai_enable_tag_dictionary_auto_update': false,
      'novelai_enable_image_persistence': false,
    });
    vm = StudioViewModel();
    await vm.init();
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
            body: AgentChatInputBar(viewModel: vm, onSent: () => sends++),
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
      expect(vm.chatDraft, '中文输入');

      // Commit composition through the platform input channel, then a newline.
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
      expect(vm.chatDraft, '中文输入\n');

      // Cmd+V replaces a selection and preserves Unicode and line breaks.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.getData') {
              return {'text': '粘贴😀\n第二行'};
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
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
      expect(vm.chatDraft, '粘贴😀\n第二行');
      expect(sends, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      vm.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
