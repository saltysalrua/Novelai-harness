import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/main.dart';
import 'package:novelai_harness/ui/core/theme/ui_zoom_controller.dart';
import 'package:novelai_harness/ui/core/widgets/custom_title_bar.dart';
import 'package:novelai_harness/ui/core/widgets/resizable_split_view.dart';
import 'package:novelai_harness/ui/features/studio/widgets/agent_chat_card.dart';
import 'package:novelai_harness/ui/features/studio/widgets/image_canvas_card.dart';
import 'package:novelai_harness/ui/features/studio/widgets/parameters_page.dart';
import 'package:novelai_harness/ui/features/studio/widgets/prompt_library_view.dart';
import 'package:novelai_harness/ui/features/studio/widgets/prompts_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 移动端 / 窄屏布局回归：多宽度无溢出、词库往返状态不脱节、缩放不叠加。
///
/// 覆盖 2026-09 安卓适配引入的三类问题：
/// 1. 窄屏三卡片 PageView 与顶部胶囊指示器状态脱节 (页面与高亮不一致 / 点胶囊被吞)；
/// 2. 词库页从未做窄屏适配，顶部固定子项溢出，右侧「新建词组合」被裁到屏外；
/// 3. 窄屏曾硬编码第二层 1.25 缩放，与用户全局 UI 缩放相乘后把可用逻辑宽度压掉约 27%。
Future<void> pumpApp(
  WidgetTester tester,
  Size size, {
  double zoom = 1.0,
}) async {
  SharedPreferences.setMockInitialValues({});
  AppUiZoomController.instance.zoom.value = zoom;
  addTearDown(AppUiZoomController.instance.resetForTest);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(const NovelAiHarnessApp());
  await tester.pumpAndSettle();
}

/// 断言当前帧没有任何渲染异常 (RenderFlex overflow 经 FlutterError 上报)
void expectNoRenderErrors(WidgetTester tester, String step) {
  final error = tester.takeException();
  expect(error, isNull, reason: '$step 出现渲染异常: $error');
}

/// 读取胶囊按钮当前背景色 (选中态为主色浅底，未选中为卡片底色)
Color pillBackground(WidgetTester tester, int index) {
  final container = tester.widget<AnimatedContainer>(
    find.descendant(
      of: find.byKey(Key('segmented_pill_$index')),
      matching: find.byType(AnimatedContainer),
    ),
  );
  return (container.decoration! as BoxDecoration).color!;
}

/// 断言仅指定序号的胶囊处于选中态
void expectOnlyPillSelected(WidgetTester tester, int selected) {
  final selectedColor = pillBackground(tester, selected);
  for (var i = 0; i < 3; i++) {
    if (i == selected) continue;
    expect(
      pillBackground(tester, i),
      isNot(selectedColor),
      reason: '胶囊 $i 不应与已选中的胶囊 $selected 同色',
    );
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('窄屏双层布局：多宽度无溢出', () {
    for (final width in const [
      320.0,
      360.0,
      390.0,
      430.0,
      620.0,
      700.0,
      880.0,
    ]) {
      testWidgets('宽度 ${width.toInt()} 下轮询三卡片与底部导航栏无渲染异常', (tester) async {
        await pumpApp(tester, Size(width, 800));
        expectNoRenderErrors(tester, '首帧');

        // 底部导航 5 项轮询
        for (final key in const [
          'mobile_nav_prompts',
          'mobile_nav_inpaint',
          'mobile_nav_parameters',
        ]) {
          final finder = find.byKey(Key(key));
          if (finder.evaluate().isEmpty) continue;
          await tester.tap(finder, warnIfMissed: false);
          await tester.pumpAndSettle();
          expectNoRenderErrors(tester, '点击 $key');
        }

        // 顶部三卡片胶囊轮询
        for (final index in const [1, 2, 0]) {
          final finder = find.byKey(Key('segmented_pill_$index'));
          if (finder.evaluate().isEmpty) continue;
          await tester.tap(finder, warnIfMissed: false);
          await tester.pumpAndSettle();
          expectNoRenderErrors(tester, '点击胶囊 $index');
        }

        // 词库覆盖层往返
        final libraryEntry = find.byKey(const Key('mobile_nav_library'));
        if (libraryEntry.evaluate().isNotEmpty) {
          await tester.tap(libraryEntry, warnIfMissed: false);
          await tester.pumpAndSettle();
          expectNoRenderErrors(tester, '打开词库');
          expect(find.byType(PromptLibraryView), findsOneWidget);
          await tester.tap(libraryEntry, warnIfMissed: false);
          await tester.pumpAndSettle();
          expectNoRenderErrors(tester, '关闭词库');
        }
      });
    }
  });

  group('宽屏三栏布局：无降级 TabBar 且无溢出', () {
    for (final width in const [900.0, 1000.0, 1280.0]) {
      testWidgets('宽度 ${width.toInt()} 下渲染三栏工作台', (tester) async {
        await pumpApp(tester, Size(width, 900));
        expect(find.byType(CustomTitleBar), findsOneWidget);
        expect(find.byType(ResizableThreeSplitView), findsOneWidget);
        expect(find.byType(TabBar), findsNothing);
        expectNoRenderErrors(tester, '宽屏三栏');
      });
    }
  });

  group('窄屏三卡片状态一致性', () {
    testWidgets('词库往返保留原卡片，词库打开时点胶囊立即生效', (tester) async {
      await pumpApp(tester, const Size(430, 900));

      // 1. 切到助手卡片 (page 2)
      await tester.tap(find.byKey(const Key('segmented_pill_2')));
      await tester.pumpAndSettle();
      expect(find.byType(AgentChatCard), findsOneWidget);
      expectOnlyPillSelected(tester, 2);

      // 2. 打开词库后关闭：必须保留刚才的助手卡片，而不是被重置回第 0 页
      await tester.tap(find.byKey(const Key('mobile_nav_library')));
      await tester.pumpAndSettle();
      expect(find.byType(PromptLibraryView), findsOneWidget);
      await tester.tap(find.byKey(const Key('mobile_nav_library')));
      await tester.pumpAndSettle();
      expect(find.byType(PromptLibraryView), findsNothing);
      expect(
        find.byType(AgentChatCard),
        findsOneWidget,
        reason: '词库往返后应保留原卡片，且胶囊高亮与页面一致',
      );
      expectOnlyPillSelected(tester, 2);

      // 3. 词库打开状态下点胶囊：必须立即切到对应卡片 (此前会被静默忽略)
      await tester.tap(find.byKey(const Key('mobile_nav_library')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('segmented_pill_0')));
      await tester.pumpAndSettle();
      expect(find.byType(PromptLibraryView), findsNothing);
      expect(find.byType(ParametersPage), findsOneWidget);
      expectOnlyPillSelected(tester, 0);
      expectNoRenderErrors(tester, '词库内点胶囊');
    });

    testWidgets('底部导航栏在画板卡片上仍可切回工作台', (tester) async {
      await pumpApp(tester, const Size(390, 844));

      await tester.tap(find.byKey(const Key('segmented_pill_1')));
      await tester.pumpAndSettle();
      expect(find.byType(ImageCanvasCard), findsOneWidget);
      expectOnlyPillSelected(tester, 1);

      await tester.tap(find.byKey(const Key('mobile_nav_prompts')));
      await tester.pumpAndSettle();
      expect(find.byType(PromptsPage), findsOneWidget);
      expectOnlyPillSelected(tester, 0);
      expectNoRenderErrors(tester, '底栏切回工作台');
    });
  });

  group('UI 缩放不与窄屏叠加', () {
    testWidgets('390 宽 + 全局缩放 125% 仍无溢出 (缩放只由根级作用域生效)', (tester) async {
      await pumpApp(tester, const Size(390, 844), zoom: 1.25);
      expectNoRenderErrors(tester, '缩放 125% 首帧');

      await tester.tap(find.byKey(const Key('mobile_nav_library')));
      await tester.pumpAndSettle();
      expectNoRenderErrors(tester, '缩放 125% 打开词库');
    });
  });

  group('窄屏与宽屏形态互斥', () {
    testWidgets('880 宽走窄屏双层，不渲染标题栏与三栏', (tester) async {
      await pumpApp(tester, const Size(880, 900));
      expect(find.byType(CustomTitleBar), findsNothing);
      expect(find.byType(ResizableThreeSplitView), findsNothing);
      expect(find.byType(TabBar), findsNothing);
      expect(find.byType(PageView), findsOneWidget);
      expectNoRenderErrors(tester, '窄屏双层');
    });
  });
}
