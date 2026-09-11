import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:novelai_harness/core/harness/types.dart';
import 'package:novelai_harness/data/models/llm_models.dart';
import 'package:novelai_harness/data/services/config_service.dart';
import 'package:novelai_harness/l10n/app_localizations.dart';
import 'package:novelai_harness/ui/core/theme/app_theme.dart';
import 'package:novelai_harness/ui/core/theme/theme_context_extensions.dart';
import 'package:novelai_harness/ui/core/widgets/app_async_icon_button.dart';
import 'package:novelai_harness/ui/core/widgets/app_card.dart';
import 'package:novelai_harness/ui/core/widgets/app_icon_button.dart';
import 'package:novelai_harness/ui/features/studio/view_models/studio_view_model.dart';
import 'package:novelai_harness/ui/features/studio/widgets/agent_chat_input_bar.dart';
import 'package:novelai_harness/ui/features/studio/widgets/chat_image_attachment.dart';
import 'package:novelai_harness/ui/features/studio/widgets/slash_command_overlay.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 仅记录 UI 发送请求，不初始化服务或访问线上接口。
class _ChatViewModel extends StudioViewModel {
  final _sent = <({String text, List<AgentMessageImage>? images})>[];

  @override
  AppConfig get config => const AppConfig(
    llmProviders: [
      LlmProviderConfig(
        id: 'test',
        name: 'Test',
        models: [
          LlmModelConfig(
            id: 'vision',
            name: 'Vision reasoning model with a long name',
            input: ['text', 'image'],
            reasoning: true,
          ),
        ],
      ),
    ],
  );

  @override
  Future<void> sendChatMessage(
    String text, {
    List<AgentMessageImage>? images,
  }) async {
    _sent.add((text: text, images: images));
  }
}

class _ImagePicker extends FilePicker {
  final _bytes = img.encodePng(img.Image(width: 2, height: 2));

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    expect(type, FileType.image);
    expect(allowMultiple, isTrue);
    expect(withData, isTrue);
    return FilePickerResult([
      PlatformFile(name: 'reference.png', size: _bytes.length, bytes: _bytes),
    ]);
  }
}

Widget _wrap(
  StudioViewModel viewModel, {
  double width = 420,
  Brightness brightness = Brightness.light,
  Locale locale = const Locale('zh'),
  VoidCallback? onSent,
}) => MaterialApp(
  theme: AppTheme.buildTheme(brightness),
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        width: width,
        child: ListenableBuilder(
          listenable: viewModel,
          builder: (context, _) =>
              AgentChatInputBar(viewModel: viewModel, onSent: onSent),
        ),
      ),
    ),
  ),
);

void main() {
  late _ChatViewModel viewModel;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    viewModel = _ChatViewModel();
  });

  tearDown(() => viewModel.dispose());

  for (final brightness in Brightness.values) {
    for (final width in [320.0, 420.0]) {
      testWidgets('$brightness / $width：文本全宽，按钮不随输入行数增长', (tester) async {
        await tester.pumpWidget(
          _wrap(viewModel, width: width, brightness: brightness),
        );
        final field = find.byType(TextField);
        final attachment = find.byType(AppIconButton);
        final send = find.byType(AppAsyncIconButton);
        await tester.enterText(field, '第一行');
        await tester.pump();
        final singleLine = tester.getSize(field);
        final buttonSize = tester.getSize(send);
        expect(buttonSize, const Size(28, 28));
        expect(tester.getSize(attachment), buttonSize);
        expect(
          tester.getSize(find.byType(EditableText)).width,
          closeTo(width - 50, 1),
          reason: '除外边距、边框与文本内边距外，不为按钮预留侧栏',
        );

        await tester.enterText(field, List.filled(6, '多行输入内容').join('\n'));
        await tester.pump();
        final sixLines = tester.getSize(field);
        expect(sixLines.width, singleLine.width);
        expect(sixLines.height, greaterThan(singleLine.height));
        expect(tester.getSize(send), buttonSize);
        expect(tester.getSize(attachment), buttonSize);
        expect(
          tester.getTopLeft(send).dy,
          greaterThanOrEqualTo(tester.getBottomLeft(field).dy),
          reason: '工具栏在正文下面，不能覆盖末行文字',
        );
        expect(tester.getTopLeft(send).dy, tester.getTopLeft(attachment).dy);

        await tester.enterText(field, List.filled(12, '很长的草稿').join('\n'));
        await tester.pump();
        expect(tester.getSize(field), sixLines, reason: '超过六行后内部滚动');
        final card = tester.widget<AppCard>(find.byType(AppCard));
        final colors = tester.element(field).colors;
        expect(card.backgroundColor, colors.canvasBackground);
        expect(card.borderColor, colors.primary);
        await tester.pump(const Duration(milliseconds: 350));
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('按钮与 Enter 均发送，Shift+Enter 换行，保留草稿同步与发送回调', (tester) async {
    var sentCallbacks = 0;
    await tester.pumpWidget(_wrap(viewModel, onSent: () => sentCallbacks++));
    final field = find.byType(TextField);
    await tester.enterText(field, '按钮发送');
    expect(viewModel.chatDraft, '按钮发送');
    await tester.tap(find.byType(AppAsyncIconButton));
    await tester.pump();
    expect(viewModel._sent.single.text, '按钮发送');
    expect(viewModel.chatDraft, isEmpty);
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);

    await tester.enterText(field, '键盘发送');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(viewModel._sent, hasLength(1));
    // 桌面端 Shift+Enter 放行到系统输入法；模拟其多行编辑回传。
    tester.testTextInput.enterText('键盘发送\n');
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text, '键盘发送\n');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(viewModel._sent.last.text, '键盘发送');
    expect(sentCallbacks, 2);
    await tester.pump(const Duration(milliseconds: 350));
    expect(tester.takeException(), isNull);
  });

  testWidgets('流式回复时按钮尺寸稳定且阻止按钮和键盘重复发送', (tester) async {
    await tester.pumpWidget(_wrap(viewModel));
    await tester.enterText(find.byType(TextField), '等待回复时的草稿');
    final send = find.byType(AppAsyncIconButton);
    final size = tester.getSize(send);
    viewModel.setChatStreamingForTesting(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.getSize(send), size);
    expect(tester.widget<AppAsyncIconButton>(send).isLoading, isTrue);
    expect(find.byTooltip('正在回复'), findsOneWidget);
    await tester.tap(send);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(viewModel._sent, isEmpty);
    expect(viewModel.chatDraft, '等待回复时的草稿');
    await tester.pump(const Duration(milliseconds: 350));
    expect(tester.takeException(), isNull);
  });

  testWidgets('斜杠补全保持全宽锚定，Enter 优先补全而非发送', (tester) async {
    await tester.pumpWidget(_wrap(viewModel, width: 320));
    final field = find.byType(TextField);
    await tester.enterText(field, '/hel');
    await tester.pump();
    final panel = find.byType(SlashSuggestionPanel);
    expect(panel, findsOneWidget);
    expect(tester.getSize(panel).width, tester.getSize(field).width);
    expect(
      tester.getBottomLeft(panel).dy,
      lessThan(tester.getTopLeft(field).dy),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text, '/help ');
    expect(viewModel._sent, isEmpty);
    await tester.pump(const Duration(milliseconds: 350));
    expect(tester.takeException(), isNull);
  });

  testWidgets('紧凑附件按钮仍可选图、显示预览并发送纯图片消息', (tester) async {
    FilePicker.platform = _ImagePicker();
    await tester.pumpWidget(_wrap(viewModel));
    final textWidth = tester.getSize(find.byType(TextField)).width;
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('添加附件'));
      // 图像编解码依赖真实事件循环；有处理动画时不能 pumpAndSettle。
      for (var attempt = 0; attempt < 100; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
        if (find.byType(ChatImageThumbnail).evaluate().isNotEmpty) return;
      }
      fail('图片附件未在两秒内完成归一化');
    });
    await tester.pumpAndSettle();
    expect(find.byType(ChatImageThumbnail), findsOneWidget);
    expect(tester.getSize(find.byType(TextField)).width, textWidth);
    await tester.tap(find.byType(AppAsyncIconButton));
    await tester.pump();
    expect(viewModel._sent.single.text, isEmpty);
    expect(viewModel._sent.single.images, hasLength(1));
    expect(find.byType(ChatImageThumbnail), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('英文界面使用本地化的发送提示', (tester) async {
    await tester.pumpWidget(_wrap(viewModel, locale: const Locale('en')));
    expect(find.byTooltip('Send (Enter)'), findsOneWidget);
    viewModel.setChatStreamingForTesting(true);
    await tester.pump();
    expect(find.byTooltip('Replying'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
