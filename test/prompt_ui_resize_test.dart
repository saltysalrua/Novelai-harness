import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/data/repositories/novelai_repository.dart';
import 'package:novelai_harness/data/services/config_service.dart';
import 'package:novelai_harness/data/services/novelai_service.dart';
import 'package:novelai_harness/ui/core/theme/app_theme.dart';
import 'package:novelai_harness/ui/features/studio/view_models/studio_view_model.dart';
import 'package:novelai_harness/ui/features/studio/widgets/prompt_editor_card.dart';
import 'package:novelai_harness/ui/features/studio/widgets/prompt_extension_deck.dart';
import 'package:novelai_harness/ui/features/studio/widgets/prompt_resize_handle.dart';

void main() {
  group('PromptResizeHandle Widget Tests', () {
    testWidgets(
      'dragging handle emits onDelta and double tap triggers onReset',
      (WidgetTester tester) async {
        double totalDelta = 0;
        bool resetCalled = false;

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: Center(
                child: PromptResizeHandle(
                  onDelta: (d) => totalDelta += d,
                  onReset: () => resetCalled = true,
                ),
              ),
            ),
          ),
        );

        final handle = find.byType(PromptResizeHandle);
        expect(handle, findsOneWidget);

        // 模拟向下拖动
        await tester.drag(handle, const Offset(0, 50));
        await tester.pump();
        expect(totalDelta, greaterThan(0));

        // 模拟双击重置
        await tester.tap(handle);
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tap(handle);
        await tester.pumpAndSettle();
        expect(resetCalled, isTrue);
      },
    );
  });

  group('PromptEditorCard Resizing & Layout Tests', () {
    testWidgets('PromptEditorCard resizes vertically on handle drag', (
      WidgetTester tester,
    ) async {
      final controller = TextEditingController(
        text: 'masterpiece, best quality',
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: PromptEditorCard(
                controller: controller,
                onChanged: (_) {},
                hintText: 'Enter prompt',
                minLines: 4,
                minHeight: 80,
                maxHeight: 400,
                tokenEstimate: 10,
              ),
            ),
          ),
        ),
      );

      final initialBox = tester.renderObject<RenderBox>(find.byType(TextField));
      final initialHeight = initialBox.size.height;
      expect(initialHeight, greaterThanOrEqualTo(80));

      // 拖拽 PromptResizeHandle 增加高度
      final handle = find.byType(PromptResizeHandle);
      await tester.drag(handle, const Offset(0, 60));
      await tester.pumpAndSettle();

      final updatedBox = tester.renderObject<RenderBox>(find.byType(TextField));
      expect(updatedBox.size.height, greaterThan(initialHeight));

      // 双击手柄重置高度
      await tester.tap(handle);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(handle);
      await tester.pumpAndSettle();

      final resetBox = tester.renderObject<RenderBox>(find.byType(TextField));
      expect(resetBox.size.height, closeTo(initialHeight, 2.0));
    });
  });

  group('PromptExtensionDeck Tests', () {
    late StudioViewModel viewModel;

    setUp(() {
      final configService = ConfigService();
      final novelAiService = NovelAiService();
      final repository = NovelAiRepository(service: novelAiService);
      viewModel = StudioViewModel(
        configService: configService,
        repository: repository,
      );
    });

    tearDown(() {
      viewModel.dispose();
    });

    testWidgets(
      'PromptExtensionDeck switches between Character Prompts and Fixed Affixes',
      (WidgetTester tester) async {
        final prefixController = TextEditingController(text: '0.7::artist::');
        final suffixController = TextEditingController(text: 'masterpiece');
        addTearDown(prefixController.dispose);
        addTearDown(suffixController.dispose);

        // 添加一个角色
        viewModel.addCharacterPrompt();
        viewModel.updateCharacterPrompt(
          viewModel.params.characterPrompts.first.copyWith(
            name: '银发少女',
            prompt: '1girl, silver hair',
          ),
        );
        await tester.pump(const Duration(milliseconds: 350));

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: SingleChildScrollView(
                child: PromptExtensionDeck(
                  viewModel: viewModel,
                  prefixController: prefixController,
                  suffixController: suffixController,
                ),
              ),
            ),
          ),
        );

        // 初始处于 Character Prompts 标签
        expect(find.text('Character Prompts'), findsOneWidget);
        expect(find.text('Fixed Affixes'), findsOneWidget);
        expect(find.text('银发少女'), findsOneWidget);
        expect(find.text('添加角色'), findsOneWidget);

        // 点击切换到 Fixed Affixes 标签
        await tester.tap(find.text('Fixed Affixes'));
        await tester.pumpAndSettle();

        expect(find.text('PREFIX'), findsOneWidget);
        expect(find.text('SUFFIX'), findsOneWidget);
        expect(find.text('0.7::artist::'), findsOneWidget);

        // 点击切回 Character Prompts 标签
        await tester.tap(find.text('Character Prompts'));
        await tester.pumpAndSettle();

        expect(find.text('银发少女'), findsOneWidget);

        // 通过左右手势滑动切换到 Fixed Affixes (在卡片头部空白区域滑动手势)
        final swipeDetector = find.byKey(const ValueKey('deck_swipe_detector'));
        final topLeft = tester.getTopLeft(swipeDetector);
        await tester.dragFrom(
          topLeft + const Offset(20, 20),
          const Offset(-150, 0),
        );
        await tester.pumpAndSettle();

        expect(find.text('PREFIX'), findsOneWidget);

        // 通过左右手势滑动切回 Character Prompts
        await tester.dragFrom(
          topLeft + const Offset(200, 20),
          const Offset(150, 0),
        );
        await tester.pumpAndSettle();

        expect(find.text('银发少女'), findsOneWidget);

        // 角色徽标数量上限展示
        expect(find.text('1/22'), findsOneWidget);
      },
    );
  });
}
