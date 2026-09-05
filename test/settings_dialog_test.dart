import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/data/services/config_service.dart';
import 'package:novelai_harness/main.dart';
import 'package:novelai_harness/ui/core/locale/app_locale_controller.dart';
import 'package:novelai_harness/ui/core/widgets/app_nav_tile.dart';
import 'package:novelai_harness/ui/features/settings/views/settings_dialog.dart';

void main() {
  // 侧边栏导航项 (AppNavTile 标题，区别于 22px 内容区标题)
  Finder sidebarItem(String label) =>
      find.descendant(of: find.byType(AppNavTile), matching: find.text(label));

  testWidgets('Settings dialog opens and all five tabs render', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    // 阶段 4A：General 页文案已接入 l10n，测试环境默认 en_US 会切到英文；
    // 直接经 AppLocaleController 注入 zh (同时验证根级 locale 接线)
    AppLocaleController.instance.syncFromConfig(
      const AppConfig(localePreference: AppLocalePreference.zh),
    );
    addTearDown(AppLocaleController.instance.resetForTest);

    await tester.pumpWidget(const NovelAiHarnessApp());
    await tester.pumpAndSettle();

    // 打开设置弹窗
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsDialog), findsOneWidget);
    expect(find.text('SETTINGS'), findsOneWidget);

    // Tab 0: General 默认页
    expect(find.text('NovelAI API Key'), findsOneWidget);
    expect(find.text('Opus 免点数保护'), findsOneWidget);
    expect(find.textContaining('配置 NovelAI 绘图服务凭证'), findsOneWidget);

    // 切到 Models (IndexedStack 常驻构建，用头部副标题断言激活页)
    await tester.tap(sidebarItem('Models'));
    await tester.pumpAndSettle();
    expect(find.textContaining('按供应商管理大语言模型服务'), findsOneWidget);
    expect(find.text('当前供应商'), findsOneWidget);
    expect(find.textContaining('完整接口地址'), findsOneWidget);
    expect(find.text('在线拉取模型'), findsOneWidget);

    // 切到 Presets
    await tester.tap(sidebarItem('Presets'));
    await tester.pumpAndSettle();
    expect(find.textContaining('管理 Agent 预设'), findsOneWidget);
    expect(find.text('当前预设'), findsOneWidget);
    expect(find.text('Available Skills'), findsOneWidget);
    expect(find.text('Enabled Tools'), findsOneWidget);
    expect(find.text('Modifiable Parameters'), findsOneWidget);

    // 切到 Defaults
    await tester.tap(sidebarItem('Defaults'));
    await tester.pumpAndSettle();
    expect(find.textContaining('配置启动时的出厂默认生图模型'), findsOneWidget);
    expect(find.text('默认生图模型'), findsOneWidget);
    expect(find.text('默认 CFG Scale'), findsOneWidget);

    // 切到 Bill
    await tester.tap(sidebarItem('Bill'));
    await tester.pumpAndSettle();
    expect(find.textContaining('按周期统计各模型的 Token 用量账单'), findsOneWidget);
    expect(find.text('Usage Bill'), findsOneWidget);

    // 切回 General 输入内容，再多次切页验证 IndexedStack 状态保持 (输入内容不丢)
    await tester.tap(sidebarItem('General'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'pst-...'),
      'pst-test-key',
    );
    await tester.tap(sidebarItem('Models'));
    await tester.pumpAndSettle();
    await tester.tap(sidebarItem('General'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'pst-test-key'), findsOneWidget);

    // 取消关闭
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsDialog), findsNothing);
  });

  testWidgets('Models tab search filters and counts model grid', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    AppLocaleController.instance.syncFromConfig(
      const AppConfig(localePreference: AppLocalePreference.zh),
    );
    addTearDown(AppLocaleController.instance.resetForTest);

    await tester.pumpWidget(const NovelAiHarnessApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    await tester.tap(sidebarItem('Models'));
    await tester.pumpAndSettle();

    expect(find.text('2 / 2 个模型'), findsOneWidget);
    final inDialog = find.byType(SettingsDialog);
    expect(
      find.descendant(of: inDialog, matching: find.text('DeepSeek V3')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: inDialog, matching: find.text('DeepSeek R1')),
      findsOneWidget,
    );

    // 按 ID 搜索 deepseek-reasoner → 只剩 1 个
    await tester.enterText(
      find.widgetWithText(TextField, '搜索模型名称或 ID'),
      'reasoner',
    );
    await tester.pumpAndSettle();
    expect(find.text('1 / 2 个模型'), findsOneWidget);
    expect(
      find.descendant(of: inDialog, matching: find.text('DeepSeek R1')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: inDialog, matching: find.text('DeepSeek V3')),
      findsNothing,
    );

    // 无匹配关键词 → 空态提示
    await tester.enterText(
      find.widgetWithText(TextField, '搜索模型名称或 ID'),
      'zzzz',
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('没有匹配'), findsOneWidget);

    // 清空搜索恢复全部
    await tester.tap(find.byTooltip('清空输入'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 2 个模型'), findsOneWidget);

    // 取消关闭
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsDialog), findsNothing);
  });

  testWidgets('Settings dialog renders English localized text in en locale', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    AppLocaleController.instance.syncFromConfig(
      const AppConfig(localePreference: AppLocalePreference.en),
    );
    addTearDown(AppLocaleController.instance.resetForTest);

    await tester.pumpWidget(const NovelAiHarnessApp());
    await tester.pumpAndSettle();

    // 打开设置弹窗
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsDialog), findsOneWidget);

    // Tab 0: General 英文副标题
    expect(
      find.textContaining('Configure NovelAI image generation credentials'),
      findsOneWidget,
    );

    // 切到 Defaults 验证英文标题与副标题
    await tester.tap(sidebarItem('Defaults'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Configure startup default image generation model'),
      findsOneWidget,
    );
    expect(find.text('Default Model'), findsOneWidget);
    expect(find.text('Default CFG Scale'), findsOneWidget);

    // 切到 Bill 验证英文表头与周期胶囊
    await tester.tap(sidebarItem('Bill'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Track Token usage bills for each model by period'),
      findsOneWidget,
    );
    expect(find.text('Usage Bill'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Last 7 Days'), findsOneWidget);

    // 取消按钮已切换为英文 Cancel
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsDialog), findsNothing);
  });
}
