import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/core/harness/types.dart';
import 'package:novelai_harness/main.dart';
import 'package:novelai_harness/ui/core/widgets/app_number_slider.dart';
import 'package:novelai_harness/ui/features/studio/view_models/studio_view_model.dart';
import 'package:novelai_harness/ui/features/studio/views/studio_view.dart';
import 'package:novelai_harness/ui/features/studio/widgets/agent_chat_card.dart';
import 'package:novelai_harness/ui/features/studio/widgets/image_canvas_card.dart';
import 'package:novelai_harness/ui/features/studio/widgets/inpaint_page.dart';
import 'package:novelai_harness/ui/features/studio/widgets/prompts_page.dart';
import 'package:novelai_harness/ui/features/studio/widgets/parameters_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('隐藏表单暂停 VM 订阅，重新激活显示最新参数', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const NovelAiHarnessApp());
    await tester.pumpAndSettle();
    final vm = StudioView.testViewModelHook!;
    vm.setActiveSidebarTab(StudioSidebarTab.inpaint);
    await tester.pumpAndSettle();
    vm.setActiveSidebarTab(StudioSidebarTab.prompts);
    await tester.pumpAndSettle();
    final parametersList = find.descendant(
      of: find.byType(ParametersPage, skipOffstage: false),
      matching: find.byType(ListView, skipOffstage: false),
      skipOffstage: false,
    );
    final inpaintList = find.descendant(
      of: find.byType(InpaintPage, skipOffstage: false),
      matching: find.byType(SingleChildScrollView, skipOffstage: false),
      skipOffstage: false,
    );
    final parameterWidget = tester.widget(parametersList);
    final inpaintWidget = tester.widget(inpaintList);
    vm.updateParams(vm.params.copyWith(steps: 42));
    vm.setInpaintUseMainPrompt(false);
    vm.setInpaintCustomPrompt('刷新修复提示词');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(tester.widget(parametersList), same(parameterWidget));
    expect(tester.widget(inpaintList), same(inpaintWidget));
    vm.setActiveSidebarTab(StudioSidebarTab.parameters);
    await tester.pumpAndSettle();
    final delegate =
        tester.widget<ListView>(parametersList).childrenDelegate
            as SliverChildListDelegate;
    expect(delegate.children.whereType<AppNumberSlider>().first.value, 42);
    vm.setActiveSidebarTab(StudioSidebarTab.inpaint);
    await tester.pumpAndSettle();
    expect(find.text('刷新修复提示词', skipOffstage: false), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('词库往返保留工作台、聊天滚动位置并显示隐藏期间的新消息', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const NovelAiHarnessApp());
    await tester.pumpAndSettle();
    final vm = StudioView.testViewModelHook!;
    expect(find.byType(PromptsPage, skipOffstage: false), findsNothing);
    expect(find.byType(InpaintPage, skipOffstage: false), findsNothing);
    vm.setMessagesForTesting([
      for (var i = 0; i < 40; i++)
        AgentMessage(
          id: 'retain-$i',
          role: AgentRole.user,
          content: '消息 $i\n内容\n内容',
        ),
    ]);
    await tester.pumpAndSettle();
    final chat = tester.state(find.byType(AgentChatCard));
    final canvas = tester.state(find.byType(ImageCanvasCard));
    final list = tester.widget<ListView>(
      find.descendant(
        of: find.byType(AgentChatCard),
        matching: find.byType(ListView),
      ),
    );
    final scroll = list.controller!;
    scroll.jumpTo(120);
    await tester.pumpAndSettle();
    final offset = scroll.offset;
    final parameters = tester.state(find.byType(ParametersPage));
    final parameterScroll = tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(ParametersPage),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;
    parameterScroll.jumpTo(250);
    await tester.pumpAndSettle();
    expect(parameterScroll.pixels, 250);
    vm.setActiveSidebarTab(StudioSidebarTab.library);
    await tester.pumpAndSettle();
    expect(find.byType(AgentChatCard), findsNothing);
    expect(
      tester.state(find.byType(AgentChatCard, skipOffstage: false)),
      same(chat),
    );
    vm.setMessagesForTesting([
      ...vm.messages,
      AgentMessage(
        id: 'while-hidden',
        role: AgentRole.user,
        content: '隐藏期间的新消息',
      ),
    ]);
    await tester.pumpAndSettle();
    vm.setActiveSidebarTab(StudioSidebarTab.parameters);
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(AgentChatCard)), same(chat));
    expect(tester.state(find.byType(ImageCanvasCard)), same(canvas));
    expect(scroll.offset, closeTo(offset, 1));
    expect(tester.state(find.byType(ParametersPage)), same(parameters));
    expect(parameterScroll.pixels, 250);
    expect(
      tester
          .widget<ListView>(
            find.descendant(
              of: find.byType(AgentChatCard),
              matching: find.byType(ListView),
            ),
          )
          .childrenDelegate
          .estimatedChildCount,
      41,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏三卡片往返保留工作台滚动位置与控件 State', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const NovelAiHarnessApp());
    await tester.pumpAndSettle();

    final parametersState = tester.state(find.byType(ParametersPage));
    final parameterScroll = tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(ParametersPage),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;
    parameterScroll.jumpTo(250);
    await tester.pumpAndSettle();
    expect(parameterScroll.pixels, 250);

    // 窄屏 PageView 视口只构建当前页：离开视口的卡片必须保活，
    // 不能因为切页就把整张工作台卡片卸载重建 (表现为滚动位置回顶、
    // 折叠状态与输入框高度一起被重置)。
    await tester.tap(find.byKey(const Key('segmented_pill_2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('segmented_pill_0')));
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(ParametersPage)), same(parametersState));
    expect(parameterScroll.pixels, 250);

    // 底部导航栏在同一张工作台卡片内切页 (参数 ↔ 提示词) 同样不得重置位置
    await tester.tap(find.byKey(const Key('mobile_nav_prompts')));
    await tester.pumpAndSettle();
    expect(find.byType(PromptsPage), findsOneWidget);
    await tester.tap(find.byKey(const Key('mobile_nav_parameters')));
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(ParametersPage)), same(parametersState));
    expect(parameterScroll.pixels, 250);

    // 画板与助手卡片同样保留 State，往返不重建
    await tester.tap(find.byKey(const Key('segmented_pill_2')));
    await tester.pumpAndSettle();
    final chatState = tester.state(find.byType(AgentChatCard));
    await tester.tap(find.byKey(const Key('segmented_pill_1')));
    await tester.pumpAndSettle();
    final canvasState = tester.state(find.byType(ImageCanvasCard));
    await tester.tap(find.byKey(const Key('segmented_pill_2')));
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(AgentChatCard)), same(chatState));
    await tester.tap(find.byKey(const Key('segmented_pill_1')));
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(ImageCanvasCard)), same(canvasState));
    expect(tester.takeException(), isNull);
  });
}
