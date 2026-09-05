import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/ui/core/theme/app_colors_extension.dart';
import 'package:novelai_harness/ui/core/theme/app_theme.dart';
import 'package:novelai_harness/ui/core/theme/app_tokens.dart';
import 'package:novelai_harness/ui/core/widgets/app_resize_divider.dart';
import 'package:novelai_harness/ui/core/widgets/context_menu.dart';
import 'package:novelai_harness/ui/core/widgets/custom_title_bar.dart';
import 'package:novelai_harness/ui/core/widgets/resizable_split_view.dart';
import 'package:novelai_harness/ui/features/studio/widgets/prompt_resize_handle.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CustomTitleBar Shell Theme Tests', () {
    testWidgets('renders light theme semantic colors', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(appBar: CustomTitleBar()),
        ),
      );
      await tester.pumpAndSettle();

      final titleBarContainer = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(CustomTitleBar),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = titleBarContainer.decoration as BoxDecoration;
      expect(decoration.color, AppColorsExtension.light.canvasBackground);
      final border = decoration.border as Border;
      expect(border.bottom.color, AppColorsExtension.light.borderDefault);

      final icon = tester.widget<Icon>(
        find.descendant(
          of: find.byType(CustomTitleBar),
          matching: find.byIcon(Icons.auto_awesome_rounded),
        ),
      );
      expect(icon.color, AppColorsExtension.light.primary);

      final text = tester.widget<Text>(find.text('NovelAI Harness'));
      expect(text.style?.color, AppColorsExtension.light.textPrimary);
    });

    testWidgets('renders dark theme semantic colors', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(appBar: CustomTitleBar()),
        ),
      );
      await tester.pumpAndSettle();

      final titleBarContainer = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(CustomTitleBar),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = titleBarContainer.decoration as BoxDecoration;
      expect(decoration.color, AppColorsExtension.dark.canvasBackground);
      final border = decoration.border as Border;
      expect(border.bottom.color, AppColorsExtension.dark.borderDefault);

      final icon = tester.widget<Icon>(
        find.descendant(
          of: find.byType(CustomTitleBar),
          matching: find.byIcon(Icons.auto_awesome_rounded),
        ),
      );
      expect(icon.color, AppColorsExtension.dark.primary);

      final text = tester.widget<Text>(find.text('NovelAI Harness'));
      expect(text.style?.color, AppColorsExtension.dark.textPrimary);
    });
  });

  group('ContextMenu Shell Theme Tests', () {
    testWidgets('renders light theme colors and preserves identity color', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showStudioContextMenu(
                    context,
                    position: const Offset(100, 100),
                    actions: [
                      ContextMenuItem(
                        icon: Icons.copy,
                        label: '复制图像',
                        onTap: () {},
                      ),
                      const ContextMenuItem(icon: Icons.block, label: '禁用项'),
                      const ContextMenuDivider(),
                      ContextMenuItem(
                        icon: Icons.delete_outline,
                        label: '删除记录',
                        isDestructive: true,
                        onTap: () {},
                      ),
                    ],
                  );
                },
                child: const Text('OpenMenu'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('OpenMenu'));
      await tester.pumpAndSettle();

      final menuContainer = tester.widget<Container>(
        find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).borderRadius ==
                  BorderRadius.circular(AppRadius.md + 2),
        ),
      );
      final decoration = menuContainer.decoration as BoxDecoration;
      expect(decoration.color, AppColorsExtension.light.cardBackground);
      expect(
        (decoration.border as Border).top.color,
        AppColorsExtension.light.borderDefault,
      );
      expect(decoration.boxShadow, isNotNull);

      // 验证普通项文本颜色
      final normalText = tester.widget<Text>(find.text('复制图像'));
      expect(normalText.style?.color, AppColorsExtension.light.textPrimary);

      // 验证禁用项文本颜色
      final disabledText = tester.widget<Text>(find.text('禁用项'));
      expect(disabledText.style?.color, AppColorsExtension.light.textMuted);

      // 验证破坏项使用跨主题身份色 coral (语义令牌)
      final destructiveText = tester.widget<Text>(find.text('删除记录'));
      expect(destructiveText.style?.color, AppColorsExtension.light.coral);

      // 验证分割线颜色
      final dividerContainer = tester.widget<Container>(
        find.byWidgetPredicate(
          (w) => w is Container && w.constraints?.maxHeight == 1.0,
        ),
      );
      expect(dividerContainer.color, AppColorsExtension.light.borderSubtle);
    });

    testWidgets('renders dark theme colors and preserves identity color', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showStudioContextMenu(
                    context,
                    position: const Offset(100, 100),
                    actions: [
                      ContextMenuItem(
                        icon: Icons.copy,
                        label: '复制图像',
                        onTap: () {},
                      ),
                      const ContextMenuItem(icon: Icons.block, label: '禁用项'),
                      const ContextMenuDivider(),
                      ContextMenuItem(
                        icon: Icons.delete_outline,
                        label: '删除记录',
                        isDestructive: true,
                        onTap: () {},
                      ),
                    ],
                  );
                },
                child: const Text('OpenMenu'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('OpenMenu'));
      await tester.pumpAndSettle();

      final menuContainer = tester.widget<Container>(
        find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).borderRadius ==
                  BorderRadius.circular(AppRadius.md + 2),
        ),
      );
      final decoration = menuContainer.decoration as BoxDecoration;
      expect(decoration.color, AppColorsExtension.dark.cardBackground);
      expect(
        (decoration.border as Border).top.color,
        AppColorsExtension.dark.borderDefault,
      );
      expect(decoration.boxShadow, isNotNull);

      final normalText = tester.widget<Text>(find.text('复制图像'));
      expect(normalText.style?.color, AppColorsExtension.dark.textPrimary);

      final disabledText = tester.widget<Text>(find.text('禁用项'));
      expect(disabledText.style?.color, AppColorsExtension.dark.textMuted);

      final destructiveText = tester.widget<Text>(find.text('删除记录'));
      expect(destructiveText.style?.color, AppColorsExtension.dark.coral);

      final dividerContainer = tester.widget<Container>(
        find.byWidgetPredicate(
          (w) => w is Container && w.constraints?.maxHeight == 1.0,
        ),
      );
      expect(dividerContainer.color, AppColorsExtension.dark.borderSubtle);
    });
  });

  group('ResizableThreeSplitView Theme & Interaction Tests', () {
    testWidgets('renders desktop light and dark background', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      // Light
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: ResizableThreeSplitView(
              leftChild: Text('L'),
              centerChild: Text('C'),
              rightChild: Text('R'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      var container = tester.widget<Container>(
        find.byWidgetPredicate(
          (w) => w is Container && w.padding == const EdgeInsets.all(8),
        ),
      );
      expect(container.color, AppColorsExtension.light.canvasBackground);

      // Dark
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(
            body: ResizableThreeSplitView(
              leftChild: Text('L'),
              centerChild: Text('C'),
              rightChild: Text('R'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      container = tester.widget<Container>(
        find.byWidgetPredicate(
          (w) => w is Container && w.padding == const EdgeInsets.all(8),
        ),
      );
      expect(container.color, AppColorsExtension.dark.canvasBackground);
    });

    testWidgets('renders narrow screen TabBar semantic colors', (tester) async {
      tester.view.physicalSize = const Size(600, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(
            body: ResizableThreeSplitView(
              leftChild: Text('L'),
              centerChild: Text('C'),
              rightChild: Text('R'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).last);
      expect(
        scaffold.backgroundColor,
        AppColorsExtension.dark.canvasBackground,
      );

      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.backgroundColor, AppColorsExtension.dark.cardBackground);

      final tabBar = tester.widget<TabBar>(find.byType(TabBar));
      expect(tabBar.indicatorColor, AppColorsExtension.dark.primary);
      expect(tabBar.labelColor, AppColorsExtension.dark.textPrimary);
      expect(
        tabBar.unselectedLabelColor,
        AppColorsExtension.dark.textSecondary,
      );
    });

    testWidgets('dragging split dividers triggers onWidthsChanged callback', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      double changedLeft = 0;
      double changedRight = 0;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: ResizableThreeSplitView(
              initialLeftWidth: 320.0,
              initialRightWidth: 380.0,
              onWidthsChanged: (l, r) {
                changedLeft = l;
                changedRight = r;
              },
              leftChild: const Text('L'),
              centerChild: const Text('C'),
              rightChild: const Text('R'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final splitDividers = find.descendant(
        of: find.byType(ResizableThreeSplitView),
        matching: find.byType(GestureDetector),
      );
      expect(splitDividers, findsNWidgets(2));

      // 拖拽左侧分割条
      await tester.drag(splitDividers.at(0), const Offset(40, 0));
      await tester.pumpAndSettle();
      expect(changedLeft, closeTo(360.0, 0.1));

      // 拖拽右侧分割条
      await tester.drag(splitDividers.at(1), const Offset(-30, 0));
      await tester.pumpAndSettle();
      expect(changedRight, closeTo(410.0, 0.1));
    });
  });

  group('PromptResizeHandle Theme & Interaction Tests', () {
    testWidgets('hover size and color change without animation delay', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: Center(child: PromptResizeHandle(onDelta: (_) {})),
          ),
        ),
      );
      final indicator = find.descendant(
        of: find.byType(AppResizeDivider),
        matching: find.byType(AnimatedContainer),
      );
      expect(tester.getSize(indicator).width, 28);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.byType(PromptResizeHandle)));
      await tester.pump();
      final hovered = tester.widget<AnimatedContainer>(indicator);
      expect(hovered.duration, Duration.zero);
      expect(tester.getSize(indicator).width, 42);
      expect(
        (hovered.decoration as BoxDecoration).color,
        AppColorsExtension.dark.primary.withValues(alpha: 0.65),
      );
      await mouse.moveTo(Offset.zero);
      await tester.pump();
      expect(tester.getSize(indicator).width, 28);
      final idle = tester.widget<AnimatedContainer>(indicator);
      expect(
        (idle.decoration as BoxDecoration).color,
        AppColorsExtension.dark.borderHover,
      );
    });

    testWidgets('renders AppResizeDivider with light theme idle color', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(body: PromptResizeHandle(onDelta: (_) {})),
        ),
      );

      expect(find.byType(PromptResizeHandle), findsOneWidget);
      expect(find.byType(AppResizeDivider), findsOneWidget);

      final animatedContainer = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byType(AppResizeDivider),
          matching: find.byType(AnimatedContainer),
        ),
      );
      final box = animatedContainer.decoration as BoxDecoration;
      expect(box.color, AppColorsExtension.light.borderHover);
    });

    testWidgets('renders AppResizeDivider with dark theme idle color', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(body: PromptResizeHandle(onDelta: (_) {})),
        ),
      );

      final animatedContainer = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byType(AppResizeDivider),
          matching: find.byType(AnimatedContainer),
        ),
      );
      final box = animatedContainer.decoration as BoxDecoration;
      expect(box.color, AppColorsExtension.dark.borderHover);
    });

    testWidgets(
      'dragging handle emits onDelta and double tap triggers onReset',
      (tester) async {
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

        final handleFinder = find.byType(PromptResizeHandle);

        // 向下拖动手柄
        await tester.drag(handleFinder, const Offset(0, 30));
        await tester.pump();
        expect(totalDelta, greaterThan(0));

        // 双击重置
        await tester.tap(handleFinder);
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tap(handleFinder);
        await tester.pumpAndSettle();
        expect(resetCalled, isTrue);
      },
    );

    testWidgets('ResizableTextField resize handle drag and reset', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'masterpiece');
      addTearDown(controller.dispose);
      double currentHeight = 100;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: ResizableTextField(
                controller: controller,
                onChanged: (_) {},
                hintText: 'Prompt',
                defaultHeight: 100,
                onHeightChanged: (h) => currentHeight = h,
                enableAutocomplete: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final handleFinder = find.byType(PromptResizeHandle);
      expect(handleFinder, findsOneWidget);

      await tester.drag(handleFinder, const Offset(0, 50));
      await tester.pumpAndSettle();
      expect(currentHeight, greaterThan(100));

      await tester.tap(handleFinder);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(handleFinder);
      await tester.pumpAndSettle();
      expect(currentHeight, 100);
    });
  });
}
