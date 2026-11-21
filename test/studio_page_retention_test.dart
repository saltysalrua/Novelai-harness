import 'dart:typed_data';
import 'package:flutter/gestures.dart';
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
import 'package:novelai_harness/ui/features/studio/widgets/canvas_history_sidebar.dart';
import 'package:novelai_harness/ui/features/studio/widgets/canvas_overlays.dart';
import 'package:novelai_harness/ui/features/studio/widgets/freeform_annotation_board.dart';
import 'package:novelai_harness/ui/features/studio/widgets/generate_dock.dart';
import 'package:novelai_harness/ui/features/studio/widgets/image_canvas_card.dart';
import 'package:novelai_harness/ui/features/studio/widgets/inpaint_canvas_overlay.dart';
import 'package:novelai_harness/ui/features/studio/widgets/inpaint_page.dart';
import 'package:novelai_harness/ui/features/studio/widgets/parameters_page.dart';
import 'package:novelai_harness/ui/features/studio/widgets/prompt_library_view.dart';
import 'package:novelai_harness/ui/features/studio/widgets/prompts_page.dart';
import 'package:novelai_harness/ui/features/studio/widgets/studio_sidebar.dart';
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

  testWidgets('宽屏完全收起左侧栏保留表单状态与滚动位置，点击左缘按钮恢复展开', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const NovelAiHarnessApp());
    await tester.pumpAndSettle();

    final vm = StudioView.testViewModelHook!;
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

    expect(find.byKey(const Key('canvas_expand_sidebar_button')), findsNothing);
    await tester.tap(find.byKey(const Key('sidebar_collapse_button')));
    await tester.pumpAndSettle();

    // 左侧图标条与参数卡片整体完全收起，但在树中保活不丢滚动位置与 State
    expect(vm.isLeftSidebarCollapsed, isTrue);
    expect(find.byType(ParametersPage), findsNothing);
    expect(
      tester.state(find.byType(ParametersPage, skipOffstage: false)),
      same(parametersState),
    );
    expect(find.byKey(const Key('sidebar_collapse_button')), findsNothing);
    expect(
      find.byKey(const Key('canvas_expand_sidebar_button')),
      findsOneWidget,
    );

    // 点击画板左上角轻量展开按钮恢复左侧栏与参数卡片
    await tester.tap(find.byKey(const Key('canvas_expand_sidebar_button')));
    await tester.pumpAndSettle();

    expect(vm.isLeftSidebarCollapsed, isFalse);
    expect(find.byType(ParametersPage), findsOneWidget);
    expect(tester.state(find.byType(ParametersPage)), same(parametersState));
    expect(parameterScroll.pixels, 250);
    expect(find.byKey(const Key('canvas_expand_sidebar_button')), findsNothing);

    // 切换到词库页后收起左侧栏，顶栏显示展开入口，点击恢复
    await tester.tap(find.byIcon(Icons.collections_bookmark_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sidebar_collapse_button')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('library_expand_sidebar_button')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('library_expand_sidebar_button')));
    await tester.pumpAndSettle();
    expect(vm.isLeftSidebarCollapsed, isFalse);
    expect(
      find.byKey(const Key('library_expand_sidebar_button')),
      findsNothing,
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
    expect(
      find.byKey(const Key('mobile_topbar_read_metadata_button')),
      findsOneWidget,
    );
    final canvasEmptyFinder = find.byType(CanvasEmptyState);
    expect(canvasEmptyFinder, findsOneWidget);
    final canvasL10n = AppLocalizations.of(tester.element(canvasEmptyFinder));
    expect(find.text(canvasL10n.canvasActionReadMetadata), findsOneWidget);

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

  testWidgets('窄屏 360px 下未保存图像的保存按钮固定前置可见，无需滑动即可点击', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repo = NovelAiRepository();
    final vm = StudioViewModel(repository: repo);
    addTearDown(vm.dispose);

    final unsavedImage = NaiGeneratedImage(
      id: 'mobile-canvas-unsaved-img',
      bytes: _kTestPngBytes,
      params: const NaiGenerationParams(
        prompt: '1girl, solo',
        width: 832,
        height: 1216,
      ),
      seed: 1523962644,
      isOpusFree: true,
      isUnsaved: true,
      createdAt: DateTime(2026, 11, 15, 12),
    );
    repo.addImageForTesting(unsavedImage);
    vm.selectImage(unsavedImage);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        theme: AppTheme.darkThemeFor(AppAccentController.instance.state.value),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: ImageCanvasCard(viewModel: vm, compact: true)),
      ),
    );
    await tester.pumpAndSettle();

    final barRect = tester.getRect(
      find.byKey(const Key('mobile_canvas_action_bar')),
    );
    final saveFinder = find.byKey(const Key('mobile_canvas_save_button'));
    expect(saveFinder.hitTestable(), findsOneWidget);
    final saveRect = tester.getRect(saveFinder);
    expect(saveRect.left, greaterThanOrEqualTo(barRect.left));
    expect(saveRect.right, lessThanOrEqualTo(barRect.right));
    expect(tester.takeException(), isNull);
  });

  testWidgets('侧边栏导航项等宽对齐且空闲持有参考图时不常驻修复红蓝点', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const NovelAiHarnessApp());
    await tester.pumpAndSettle();

    final vm = StudioView.testViewModelHook!;
    final tiles = tester
        .widgetList<AppNavTile>(
          find.descendant(
            of: find.byType(StudioSidebar),
            matching: find.byType(AppNavTile),
          ),
        )
        .toList();
    expect(tiles.length, greaterThanOrEqualTo(5));
    final firstRect = tester.getRect(find.byWidget(tiles.first));
    for (final tile in tiles) {
      final rect = tester.getRect(find.byWidget(tile));
      expect(rect.left, closeTo(firstRect.left, 0.1));
      expect(rect.width, closeTo(firstRect.width, 0.1));
    }

    vm.setInpaintSourceImage(
      NaiGeneratedImage(
        id: 'img_sidebar_idle',
        bytes: _kTestPngBytes,
        params: const NaiGenerationParams(prompt: 'test'),
        seed: 1,
        isOpusFree: true,
        createdAt: DateTime(2026),
      ),
    );
    await tester.pumpAndSettle();

    final badgeDotFinder = find.descendant(
      of: find.byType(StudioSidebar),
      matching: find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == '_SidebarBadgeDot',
      ),
    );
    expect(badgeDotFinder, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('SelectionArea 搭配保活消息、流式思考与回溯视图切换不触发未布局或溢出异常', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const NovelAiHarnessApp());
    await tester.pumpAndSettle();

    final vm = StudioView.testViewModelHook!;
    final msgs = <AgentMessage>[
      for (var i = 0; i < 30; i++)
        AgentMessage(
          id: 'sel_msg_$i',
          role: AgentRole.assistant,
          content: 'Paragraph 1 of $i\n\nParagraph 2 of $i',
          thoughts: 'Thought line 1\nThought line 2',
          toolCalls: i == 0 || i == 29
              ? const [
                  ToolCall(id: 'tc1', name: 'tool_a', arguments: {'k': 'v'}),
                  ToolCall(id: 'tc2', name: 'tool_b', arguments: {'k': 'v'}),
                  ToolCall(id: 'tc3', name: 'tool_c', arguments: {'k': 'v'}),
                ]
              : null,
        ),
    ];

    vm.setChatStreamingForTesting(true);
    vm.setMessagesForTesting(msgs);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final list = tester.widget<ListView>(
      find.descendant(
        of: find.byType(AgentChatCard),
        matching: find.byType(ListView),
      ),
    );
    list.controller!.jumpTo(0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // 活跃工具调用在离屏保活状态期间完成（配对结果到达，触发 AppShimmerText -> Text 切换）
    vm.setMessagesForTesting([
      ...msgs,
      AgentMessage(
        id: 'sel_tool_res_1',
        role: AgentRole.tool,
        toolCallId: 'tc1',
        toolName: 'tool_a',
        content: 'ok1',
      ),
      AgentMessage(
        id: 'sel_tool_res_2',
        role: AgentRole.tool,
        toolCallId: 'tc2',
        toolName: 'tool_b',
        content: 'ok2',
      ),
      AgentMessage(
        id: 'sel_tool_res_3',
        role: AgentRole.tool,
        toolCallId: 'tc3',
        toolName: 'tool_c',
        content: 'ok3',
      ),
    ]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);

    list.controller!.jumpTo(list.controller!.position.maxScrollExtent);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    vm.streamingText.appendThoughts('Thinking 1\nThinking 2\nThinking 3');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    vm.streamingText.setNotice('Retrying...');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    vm.streamingText.setNotice(null);
    vm.streamingText.appendContent('Hello\n\nWorld\n\nTest');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    vm.setActiveSidebarTab(StudioSidebarTab.library);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    vm.setActiveSidebarTab(StudioSidebarTab.parameters);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final chatState = tester.state<AgentChatCardState>(
      find.byType(AgentChatCard),
    );
    chatState.openRewindView();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    chatState.dismissOverlayView();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    vm.setChatStreamingForTesting(false);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('长对话滚至底部后切换主题不触发 SelectionArea 未布局异常', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final vm = StudioViewModel();
    addTearDown(vm.dispose);

    vm.setMessagesForTesting([
      for (var i = 0; i < 30; i++)
        AgentMessage(
          id: 'm_$i',
          role: AgentRole.assistant,
          content: 'Paragraph 1 of $i\n\nParagraph 2 of $i',
        ),
    ]);

    var useDark = false;
    late StateSetter outerSetState;

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          outerSetState = setState;
          return MaterialApp(
            theme: useDark ? AppTheme.darkTheme : AppTheme.lightTheme,
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SizedBox(
                width: 400,
                height: 600,
                child: AgentChatCard(viewModel: vm),
              ),
            ),
          );
        },
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final list = tester.widget<ListView>(find.byType(ListView));
    list.controller!.jumpTo(list.controller!.position.maxScrollExtent);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    outerSetState(() => useDark = true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(tester.takeException(), isNull);
  });

  testWidgets('画板历史侧栏展开时立即清除提示并收回按钮，无残留叠影', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repo = NovelAiRepository();
    final vm = StudioViewModel(repository: repo);
    addTearDown(vm.dispose);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        theme: AppTheme.darkThemeFor(AppAccentController.instance.state.value),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: ImageCanvasCard(viewModel: vm)),
      ),
    );
    await tester.pumpAndSettle();

    final openButton = find.byKey(const Key('canvas_open_history_button'));
    expect(openButton, findsOneWidget);
    expect(find.byType(CanvasHistorySidebar), findsNothing);

    // 悬停唤出 Tooltip
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(openButton));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('展开历史记录'), findsOneWidget);

    // 点击唤出历史：Tooltip 立即消失，90ms 后按钮已完全退出（早于 250ms 侧栏完成）
    await tester.tap(openButton);
    await tester.pump();
    expect(find.text('展开历史记录'), findsNothing);
    expect(vm.canvasHistoryOpen, isTrue);

    await tester.pump(const Duration(milliseconds: 110));
    expect(openButton, findsNothing);
    expect(find.byType(CanvasHistorySidebar), findsOneWidget);

    await tester.pumpAndSettle();
    expect(openButton, findsNothing);
    expect(find.byType(CanvasHistorySidebar), findsOneWidget);
    expect(find.text('历史记录'), findsOneWidget);

    // 点击收起按钮后恢复展开按钮且无残留
    await tester.tap(find.byKey(const Key('canvas_collapse_history_button')));
    await tester.pumpAndSettle();
    expect(vm.canvasHistoryOpen, isFalse);
    expect(find.byType(CanvasHistorySidebar), findsNothing);
    expect(openButton, findsOneWidget);
    await vm.flushPendingLayoutSave();
    expect(tester.takeException(), isNull);
  });

  testWidgets('宽屏收起左卡片时画板直达生图、词库往返不拉出左卡片，修复模式可直出直退', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const NovelAiHarnessApp());
    await tester.pumpAndSettle();

    final vm = StudioView.testViewModelHook!;
    vm.setInpaintSourceImage(
      NaiGeneratedImage(
        id: 'collapsed-inpaint-src',
        bytes: _kTestPngBytes,
        params: const NaiGenerationParams(
          prompt: '1girl',
          width: 1024,
          height: 1024,
        ),
        seed: 42,
        isOpusFree: true,
        createdAt: DateTime(2026, 11, 16),
      ),
    );
    await tester.pumpAndSettle();

    // 记录顶部收起按钮位置，收起左侧栏与左卡片后校验展开按钮也在顶部对齐
    final collapseRect = tester.getRect(
      find.byKey(const Key('sidebar_collapse_button')),
    );
    await tester.tap(find.byKey(const Key('sidebar_collapse_button')));
    await tester.pumpAndSettle();
    expect(vm.isLeftSidebarCollapsed, isTrue);

    final quickExpandRect = tester.getRect(
      find.byKey(const Key('canvas_expand_sidebar_button')),
    );
    expect((quickExpandRect.top - collapseRect.top).abs(), lessThan(24));

    // 画板保留快捷生图按钮与左上快捷悬浮条 (不含标签灵感库)
    expect(
      find.byKey(const Key('canvas_quick_generate_button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('canvas_collapsed_quick_dock')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('canvas_collapsed_prompts_button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('canvas_collapsed_library_button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('canvas_collapsed_tag_browser_button')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('canvas_collapsed_settings_button')),
      findsOneWidget,
    );

    // 不拉出左卡片直接打开词库，左上角提供返回按钮且关闭词库后仍保持左侧收起
    await tester.tap(find.byKey(const Key('canvas_collapsed_library_button')));
    await tester.pumpAndSettle();
    expect(find.byType(PromptLibraryView), findsOneWidget);
    expect(vm.isLeftSidebarCollapsed, isTrue);

    final libExpandRect = tester.getRect(
      find.byKey(const Key('library_expand_sidebar_button')),
    );
    final closeRect = tester.getRect(
      find.byKey(const Key('library_close_button')),
    );
    expect(libExpandRect.right, lessThanOrEqualTo(closeRect.left));

    await tester.tap(find.byKey(const Key('library_close_button')));
    await tester.pumpAndSettle();
    expect(find.byType(PromptLibraryView), findsNothing);
    expect(vm.isLeftSidebarCollapsed, isTrue);

    // 进入修复模式并收起左侧栏：画板顶部工具坞避让展开按钮，右下提供退出修复与开始修复
    vm.setActiveSidebarTab(StudioSidebarTab.inpaint);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sidebar_collapse_button')));
    await tester.pumpAndSettle();
    expect(vm.isLeftSidebarCollapsed, isTrue);
    expect(find.byKey(const Key('inpaint_exit_button')), findsOneWidget);
    expect(
      find.byKey(const Key('inpaint_canvas_start_button')),
      findsOneWidget,
    );

    final expandRect = tester.getRect(
      find.byKey(const Key('canvas_expand_sidebar_button')),
    );
    final dockRect = tester.getRect(find.byKey(const ValueKey('inpaint-dock')));
    expect(dockRect.left, greaterThanOrEqualTo(expandRect.right));

    // 在画板直接点击退出修复，切回参数页且保持左侧栏收起
    await tester.tap(find.byKey(const Key('inpaint_exit_button')));
    await tester.pumpAndSettle();
    expect(vm.activeSidebarTab, StudioSidebarTab.parameters);
    expect(vm.isLeftSidebarCollapsed, isTrue);
    expect(
      find.byKey(const Key('canvas_quick_generate_button')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('宽屏收起左卡片后点击提示词图标按钮弹出合并式精简浮窗，支持切换编辑与展开完整面板', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const NovelAiHarnessApp());
    await tester.pumpAndSettle();

    final vm = StudioView.testViewModelHook!;
    await tester.tap(find.byKey(const Key('sidebar_collapse_button')));
    await tester.pumpAndSettle();
    expect(vm.isLeftSidebarCollapsed, isTrue);

    // 快捷悬浮条中提示词为纯图标按钮，位于词库右侧、设置左侧，不带文字标签
    final dockFinder = find.byKey(const Key('canvas_collapsed_quick_dock'));
    final libraryRect = tester.getRect(
      find.byKey(const Key('canvas_collapsed_library_button')),
    );
    final promptBtnFinder = find.byKey(
      const Key('canvas_collapsed_prompts_button'),
    );
    final promptRect = tester.getRect(promptBtnFinder);
    final settingsRect = tester.getRect(
      find.byKey(const Key('canvas_collapsed_settings_button')),
    );
    expect(promptRect.left, greaterThanOrEqualTo(libraryRect.right));
    expect(promptRect.right, lessThanOrEqualTo(settingsRect.left));
    expect(
      find.descendant(of: dockFinder, matching: find.text('提示词')),
      findsNothing,
    );

    // 点击图标按钮弹出合并式精简浮窗：无独立标题栏，正向/负向通过分段条切换
    await tester.tap(promptBtnFinder);
    await tester.pumpAndSettle();
    final popoverFinder = find.byKey(const Key('compact_prompt_popover'));
    expect(popoverFinder, findsOneWidget);
    expect(
      find.byKey(const Key('compact_prompt_positive_card')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('compact_prompt_negative_card')), findsNothing);
    expect(
      find.byKey(const Key('compact_prompt_generate_button')),
      findsNothing,
    );
    expect(
      find.descendant(
        of: popoverFinder,
        matching: find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == 'AppCard',
        ),
      ),
      findsNothing,
    );

    // 编辑正向提示词并同步到 ViewModel
    final positiveField = find.descendant(
      of: find.byKey(const Key('compact_prompt_positive_card')),
      matching: find.byType(TextField),
    );
    await tester.enterText(positiveField, '1girl, silver hair, smile');
    await tester.pumpAndSettle();
    expect(vm.params.prompt, '1girl, silver hair, smile');

    // 切换到负向提示词标签页并编辑（切换瞬间与动画中均不得叠加残留旧编辑器）
    await tester.tap(
      find.descendant(
        of: popoverFinder,
        matching: find.byKey(const Key('segmented_card_undesired')),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('compact_prompt_positive_card')), findsNothing);
    expect(
      find.byKey(const Key('compact_prompt_negative_card')),
      findsOneWidget,
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const Key('compact_prompt_positive_card')), findsNothing);
    expect(
      find.byKey(const Key('compact_prompt_negative_card')),
      findsOneWidget,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('compact_prompt_positive_card')), findsNothing);
    expect(
      find.byKey(const Key('compact_prompt_negative_card')),
      findsOneWidget,
    );
    final negativeField = find.descendant(
      of: find.byKey(const Key('compact_prompt_negative_card')),
      matching: find.byType(TextField),
    );
    await tester.enterText(negativeField, 'lowres, bad hands');
    await tester.pumpAndSettle();
    expect(vm.params.negativePrompt, 'lowres, bad hands');

    // 点击外部空白区域关闭浮窗并保持左侧栏收起
    await tester.tapAt(const Offset(900, 600));
    await tester.pumpAndSettle();
    expect(popoverFinder, findsNothing);
    expect(vm.isLeftSidebarCollapsed, isTrue);

    // 再次打开后点击展开完整面板，切入提示词页并展开左侧栏
    await tester.tap(promptBtnFinder);
    await tester.pumpAndSettle();
    expect(popoverFinder, findsOneWidget);

    await tester.tap(find.byKey(const Key('compact_prompt_open_full_button')));
    await tester.pumpAndSettle();
    expect(popoverFinder, findsNothing);
    expect(vm.isLeftSidebarCollapsed, isFalse);
    expect(vm.activeSidebarTab, StudioSidebarTab.prompts);

    await vm.flushPendingLayoutSave();
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏画板常驻快捷生图入口，从画板送修后点击退出修复自动返回画板', (tester) async {
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

    // 切到画板页 (空画布状态)：仍存在快捷生图按钮
    await tester.tap(find.byKey(const Key('segmented_pill_1')));
    await tester.pumpAndSettle();
    expect(isNavSelected('segmented_pill_1'), isTrue);
    expect(
      find.byKey(const Key('canvas_quick_generate_button')),
      findsOneWidget,
    );

    // 注入测试图并选中，再从画板底部一键送入局部修复
    final testImg = NaiGeneratedImage(
      id: 'narrow-roll-img',
      bytes: _kTestPngBytes,
      params: const NaiGenerationParams(
        prompt: '1girl',
        width: 832,
        height: 1216,
      ),
      seed: 999,
      isOpusFree: true,
      createdAt: DateTime(2026, 11, 16),
    );
    vm.setInpaintSourceImage(testImg);
    vm.sendImageToInpaint(testImg);
    await tester.pumpAndSettle();
    expect(isNavSelected('segmented_pill_0'), isTrue);
    expect(vm.activeSidebarTab, StudioSidebarTab.inpaint);
    expect(find.byKey(const Key('inpaint_exit_button')), findsOneWidget);

    // 点击退出修复：恢复参数页并自动回到画板页
    await tester.tap(find.byKey(const Key('inpaint_exit_button')));
    await tester.pumpAndSettle();
    expect(vm.activeSidebarTab, StudioSidebarTab.parameters);
    expect(isNavSelected('segmented_pill_1'), isTrue);
    expect(
      find.byKey(const Key('canvas_quick_generate_button')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

final Uint8List _kTestPngBytes = Uint8List.fromList([
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);
