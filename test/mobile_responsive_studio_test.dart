import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/main.dart';
import 'package:novelai_harness/ui/core/widgets/app_segmented_controls.dart';
import 'package:novelai_harness/ui/core/widgets/custom_title_bar.dart';
import 'package:novelai_harness/ui/core/widgets/resizable_split_view.dart';
import 'package:novelai_harness/ui/features/settings/views/settings_dialog.dart';
import 'package:novelai_harness/ui/features/studio/widgets/agent_chat_card.dart';
import 'package:novelai_harness/ui/features/studio/widgets/image_canvas_card.dart';
import 'package:novelai_harness/ui/features/studio/widgets/inpaint_page.dart';
import 'package:novelai_harness/ui/features/studio/widgets/parameter_card.dart';
import 'package:novelai_harness/ui/features/studio/widgets/parameters_page.dart';
import 'package:novelai_harness/ui/features/studio/widgets/prompts_page.dart';
import 'package:novelai_harness/ui/features/studio/widgets/studio_sidebar.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    '宽屏桌面模式 (>=900px)：渲染 CustomTitleBar、StudioSidebar 与 ResizableThreeSplitView',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const NovelAiHarnessApp());
      await tester.pumpAndSettle();

      // 宽屏验证：顶部标题栏存在
      expect(find.byType(CustomTitleBar), findsOneWidget);
      // 左侧侧边栏存在
      expect(find.byType(StudioSidebar), findsOneWidget);
      // 三栏可拖拽工作台存在
      expect(find.byType(ResizableThreeSplitView), findsOneWidget);
      // 移动端 PageView 不存在
      expect(find.byType(PageView), findsNothing);
    },
  );

  testWidgets('窄屏模式 (<900px)：无框文字页签三卡片导航 + 底部 5 功能项导航栏', (tester) async {
    // 模拟常见全面屏手机竖屏尺寸：390x844
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const NovelAiHarnessApp());
    await tester.pumpAndSettle();

    // 1. 顶部桌面原生标题栏完全移除，零多余空间浪费
    expect(find.byType(CustomTitleBar), findsNothing);

    // 2. 顶部无框文字页签存在三卡片指示器 [生图] [画板] [助手]
    expect(find.byKey(const Key('segmented_pill_0')), findsOneWidget);
    expect(find.byKey(const Key('segmented_pill_1')), findsOneWidget);
    expect(find.byKey(const Key('segmented_pill_2')), findsOneWidget);
    final navigation = tester.widget<AppSegmentedPillBar<int>>(
      find.byType(AppSegmentedPillBar<int>).first,
    );
    expect(navigation.expand, isTrue);
    // 手机不用圆角胶囊外框，仅以底部细线标记选中项
    expect(navigation.variant, AppPillVariant.underline);
    final firstSize = tester.getSize(find.byKey(const Key('segmented_pill_0')));
    expect(firstSize.height, 32);
    expect(
      tester.getSize(find.byKey(const ValueKey('mobile_top_bar'))).height,
      32,
    );
    for (final index in [1, 2]) {
      final size = tester.getSize(find.byKey(Key('segmented_pill_$index')));
      expect(size.width, closeTo(firstSize.width, 0.01));
      expect(size.height, firstSize.height);
    }

    // 3. 底部导航栏完整包含原左侧 5 个核心功能项 (提示词与修复不漏)
    expect(find.byType(StudioSidebar), findsNothing);
    expect(find.byKey(const Key('mobile_nav_parameters')), findsOneWidget);
    expect(find.byKey(const Key('mobile_nav_prompts')), findsOneWidget);
    expect(find.byKey(const Key('mobile_nav_inpaint')), findsOneWidget);
    expect(find.byKey(const Key('mobile_nav_library')), findsOneWidget);
    expect(find.byKey(const Key('mobile_nav_settings')), findsOneWidget);

    // 4. 三卡片由 PageView 承载，默认在第 0 页 (生图/工作台)
    expect(find.byType(PageView), findsOneWidget);
    expect(find.byType(ResizableThreeSplitView), findsNothing);
    expect(find.byType(ParameterCard), findsOneWidget);
    expect(find.byType(ParametersPage), findsOneWidget);

    // 5. 点击顶部胶囊「画板」切换至第 1 页画布
    await tester.tap(find.byKey(const Key('segmented_pill_1')));
    await tester.pumpAndSettle();
    expect(find.byType(ImageCanvasCard), findsOneWidget);

    // 6. 点击顶部胶囊「助手」切换至第 2 页 AI 助手
    await tester.tap(find.byKey(const Key('segmented_pill_2')));
    await tester.pumpAndSettle();
    expect(find.byType(AgentChatCard), findsOneWidget);

    // 7. 手势横滑：从助手卡片 (page 2) 向右滑动切回画板 (page 1)
    await tester.drag(find.byType(PageView), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(find.byType(ImageCanvasCard), findsOneWidget);

    // 8. 处于画板 (page 1) 时点击底栏「提示词」：自动滑回 Page 0 且展示提示词管理页
    await tester.tap(find.byKey(const Key('mobile_nav_prompts')));
    await tester.pumpAndSettle();
    expect(find.byType(ParameterCard), findsOneWidget);
    expect(find.byType(PromptsPage), findsOneWidget);

    // 9. 点击底栏「修复」：展示局部修复配置页
    await tester.tap(find.byKey(const Key('mobile_nav_inpaint')));
    await tester.pumpAndSettle();
    expect(find.byType(InpaintPage), findsOneWidget);

    // 10. 点击底栏「参数」：切回参数配置页
    await tester.tap(find.byKey(const Key('mobile_nav_parameters')));
    await tester.pumpAndSettle();
    expect(find.byType(ParametersPage), findsOneWidget);

    // 11. 点击底栏「设置」：弹出设置对话框
    await tester.tap(find.byKey(const Key('mobile_nav_settings')));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsDialog), findsOneWidget);
  });
}
