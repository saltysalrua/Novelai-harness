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
}
