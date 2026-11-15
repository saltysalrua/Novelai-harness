import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/core/harness/types.dart';
import 'package:novelai_harness/data/models/novelai_models.dart';
import 'package:novelai_harness/data/repositories/novelai_repository.dart';
import 'package:novelai_harness/l10n/app_localizations.dart';
import 'package:novelai_harness/main.dart';
import 'package:novelai_harness/ui/core/theme/app_accent_controller.dart';
import 'package:novelai_harness/ui/core/theme/app_theme.dart';
import 'package:novelai_harness/ui/core/widgets/app_nav_tile.dart';
import 'package:novelai_harness/ui/core/widgets/app_number_slider.dart';
import 'package:novelai_harness/ui/features/studio/view_models/studio_view_model.dart';
import 'package:novelai_harness/ui/features/studio/views/studio_view.dart';
import 'package:novelai_harness/ui/features/studio/widgets/agent_chat_card.dart';
import 'package:novelai_harness/ui/features/studio/widgets/canvas_overlays.dart';
import 'package:novelai_harness/ui/features/studio/widgets/freeform_annotation_board.dart';
import 'package:novelai_harness/ui/features/studio/widgets/generate_dock.dart';
import 'package:novelai_harness/ui/features/studio/widgets/image_canvas_card.dart';
import 'package:novelai_harness/ui/features/studio/widgets/inpaint_canvas_overlay.dart';
import 'package:novelai_harness/ui/features/studio/widgets/inpaint_page.dart';
import 'package:novelai_harness/ui/features/studio/widgets/parameters_page.dart';
import 'package:novelai_harness/ui/features/studio/widgets/prompt_library_view.dart';
import 'package:novelai_harness/ui/features/studio/widgets/prompts_page.dart';
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

  testWidgets('方案A 窄屏主导航、顶部设置入口与词库覆盖切换', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const NovelAiHarnessApp());
    await tester.pumpAndSettle();

    bool isNavSelected(String key) =>
        tester.widget<AppNavTile>(find.byKey(Key(key))).isSelected;

    expect(isNavSelected('segmented_pill_0'), isTrue);
    expect(isNavSelected('segmented_pill_1'), isFalse);
    expect(isNavSelected('segmented_pill_2'), isFalse);
    expect(isNavSelected('mobile_nav_library'), isFalse);

    final topBar = find.byKey(const ValueKey('mobile_top_bar'));
    expect(topBar, findsOneWidget);
    expect(
      find.descendant(
        of: topBar,
        matching: find.byKey(const Key('mobile_nav_parameters')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: topBar,
        matching: find.byKey(const Key('mobile_nav_prompts')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: topBar,
        matching: find.byKey(const Key('mobile_nav_inpaint')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: topBar,
        matching: find.byKey(const Key('mobile_nav_settings')),
      ),
      findsOneWidget,
    );

    // 打开词库覆盖层，顶部保留设置入口
    await tester.tap(find.byKey(const Key('mobile_nav_library')));
    await tester.pumpAndSettle();
    expect(find.byType(PromptLibraryView), findsOneWidget);
    expect(isNavSelected('mobile_nav_library'), isTrue);
    expect(find.byKey(const Key('mobile_nav_settings')), findsOneWidget);

    // 词库中直接点击底部「画板」应退出词库并切到画板页
    await tester.tap(find.byKey(const Key('segmented_pill_1')));
    await tester.pumpAndSettle();
    expect(find.byType(PromptLibraryView), findsNothing);
    expect(isNavSelected('segmented_pill_1'), isTrue);
    expect(find.byKey(const Key('mobile_nav_settings')), findsOneWidget);

    // 再进词库后点击底部「助手」应退出词库并切到助手页
    await tester.tap(find.byKey(const Key('mobile_nav_library')));
    await tester.pumpAndSettle();
    expect(find.byType(PromptLibraryView), findsOneWidget);
    await tester.tap(find.byKey(const Key('segmented_pill_2')));
    await tester.pumpAndSettle();
    expect(find.byType(PromptLibraryView), findsNothing);
    expect(find.byType(AgentChatCard), findsOneWidget);
    expect(isNavSelected('segmented_pill_2'), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('方案A 手机局部修复一体化工作区不劫持画板页且可折叠参数抽屉', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const NovelAiHarnessApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('mobile_nav_inpaint')));
    await tester.pumpAndSettle();

    expect(find.byType(InpaintRepairCanvas), findsOneWidget);
    expect(find.byType(GenerateDock), findsOneWidget);
    expect(
      find.byKey(const Key('mobile_inpaint_params_toggle')),
      findsOneWidget,
    );
    expect(find.byType(InpaintPage, skipOffstage: false), findsOneWidget);

    // 点击折叠/展开按钮切换参数区可见性，同时保持 InpaintPage State 不断电
    final initiallyVisible = find.byType(InpaintPage).evaluate().isNotEmpty;
    await tester.tap(find.byKey(const Key('mobile_inpaint_params_toggle')));
    await tester.pumpAndSettle();
    expect(
      find.byType(InpaintPage).evaluate().isNotEmpty,
      isNot(initiallyVisible),
    );
    expect(find.byType(InpaintPage, skipOffstage: false), findsOneWidget);

    // 切到画板页：画板页保持独立作品流/画布，不被修复遮罩劫持
    await tester.tap(find.byKey(const Key('segmented_pill_1')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(ImageCanvasCard),
        matching: find.byType(InpaintRepairCanvas),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('方案A 跨页自动跳转（角色定位往返）与批注期间助手页/历史选图可达', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const NovelAiHarnessApp());
    await tester.pumpAndSettle();

    final vm = StudioView.testViewModelHook!;
    bool isNavSelected(String key) =>
        tester.widget<AppNavTile>(find.byKey(Key(key))).isSelected;

    // 角色定位开启自动从生图页跳往画板页；结束定位自动返回生图页
    vm.updateParams(
      vm.params.copyWith(
        characterAiPosition: false,
        characterPrompts: const [
          NaiCharacterPrompt(id: 'c1', name: 'C1', prompt: '1girl'),
        ],
      ),
    );
    vm.setEditingCharacterPositions(true);
    await tester.pumpAndSettle();
    expect(isNavSelected('segmented_pill_1'), isTrue);
    expect(
      tester.widget<PageView>(find.byType(PageView)).physics,
      isA<NeverScrollableScrollPhysics>(),
    );

    vm.setEditingCharacterPositions(false);
    await tester.pumpAndSettle();
    expect(isNavSelected('segmented_pill_0'), isTrue);
    expect(
      tester.widget<PageView>(find.byType(PageView)).physics,
      isNot(isA<NeverScrollableScrollPhysics>()),
    );

    // 进入批注模式自动跳转到画板页、锁定横向手势翻页并展示手机「历史记录」选图入口；
    // 且第 3 页仍可直接切到 Agent 助手对话
    vm.board.setAnnotatingImage(true);
    await tester.pumpAndSettle();
    expect(isNavSelected('segmented_pill_1'), isTrue);
    expect(find.byType(FreeformAnnotationBoard), findsOneWidget);
    expect(
      find.byKey(const Key('board_pick_history_ref_button')),
      findsOneWidget,
    );
    expect(
      tester.widget<PageView>(find.byType(PageView)).physics,
      isA<NeverScrollableScrollPhysics>(),
    );

    await tester.tap(find.byKey(const Key('segmented_pill_2')));
    await tester.pumpAndSettle();
    expect(isNavSelected('segmented_pill_2'), isTrue);
    expect(find.byType(AgentChatCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('方案A 窄屏画板底部统一栏、ActionSheet 与一键送修回调', (tester) async {
    tester.view.physicalSize = const Size(430, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repo = NovelAiRepository();
    final vm = StudioViewModel(repository: repo);
    addTearDown(vm.dispose);

    final testImage = NaiGeneratedImage(
      id: 'mobile-canvas-img',
      bytes: _kTestPngBytes,
      params: const NaiGenerationParams(
        prompt: '1girl, solo',
        width: 832,
        height: 1216,
      ),
      seed: 777888,
      isOpusFree: true,
      createdAt: DateTime(2026, 11, 15, 12),
    );
    repo.addImageForTesting(testImage);
    vm.selectImage(testImage);

    var sentToInpaintCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        theme: AppTheme.darkThemeFor(AppAccentController.instance.state.value),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ImageCanvasCard(
            viewModel: vm,
            compact: true,
            onSentToInpaint: () => sentToInpaintCount++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MobileCanvasActionBar), findsOneWidget);
    expect(find.byKey(const Key('mobile_canvas_action_bar')), findsOneWidget);
    expect(find.byType(CanvasSaveButton), findsNothing);
    expect(find.text('832×1216'), findsOneWidget);
    expect(find.text('777888'), findsOneWidget);

    // 点「更多」弹出 ActionSheet
    await tester.tap(find.byKey(const Key('mobile_canvas_more_button')));
    await tester.pumpAndSettle();
    expect(find.text('查看大图'), findsOneWidget);
    expect(find.text('从历史记录删除'), findsOneWidget);

    // 关闭 ActionSheet
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // 点「局部修复」触发入修图 + 跳回工作台回调
    await tester.tap(find.byKey(const Key('mobile_canvas_inpaint_button')));
    await tester.pumpAndSettle();
    expect(vm.inpaintSourceImage?.id, equals(testImage.id));
    expect(vm.activeSidebarTab, equals(StudioSidebarTab.inpaint));
    expect(sentToInpaintCount, equals(1));
    expect(tester.takeException(), isNull);
  });
}

final Uint8List _kTestPngBytes = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);
