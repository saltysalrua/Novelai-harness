import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/main.dart';
import 'package:novelai_harness/ui/features/settings/views/settings_dialog.dart';

void main() {
  // 侧边栏导航项 (13px 文本，区别于 22px 内容区标题)
  Finder sidebarItem(String label) => find.byWidgetPredicate(
    (w) => w is Text && w.data == label && w.style?.fontSize == 13,
  );

  testWidgets('Settings dialog opens and all five tabs render', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

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
}
