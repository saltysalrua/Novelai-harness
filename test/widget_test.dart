import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/main.dart';

void main() {
  testWidgets('NovelAiHarnessApp sidebar navigation and tab switching test', (
    WidgetTester tester,
  ) async {
    // Set a large desktop-like window size for tester
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const NovelAiHarnessApp());
    await tester.pumpAndSettle();

    // 0. 验证顶部自定义标题栏
    expect(find.text('NovelAI Harness'), findsOneWidget);

    // 1. 验证侧边栏项目
    expect(find.text('参数'), findsWidgets);
    expect(find.text('提示词'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);

    // 2. 默认参数页内容
    expect(find.text('参数设置'), findsOneWidget);
    expect(find.text('模型'), findsOneWidget);
    expect(find.text('画板暂无图像'), findsOneWidget);
    expect(find.text('生成图片'), findsOneWidget);
    expect(find.textContaining('未获取账号信息'), findsOneWidget);

    // 3. 点击切换至提示词页
    await tester.tap(find.text('提示词'));
    await tester.pumpAndSettle();

    expect(find.text('提示词管理'), findsOneWidget);
    expect(find.text('Prompt'), findsOneWidget);
    expect(find.text('Undesired Content'), findsOneWidget);
    // 固定词缀面板在页面底部，滚动到可见后再断言
    await tester.drag(find.text('提示词管理'), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('Fixed Affixes'), findsOneWidget);
    // 验证生成图片和账号卡片仍然常驻显示
    expect(find.text('生成图片'), findsOneWidget);
    expect(find.textContaining('未获取账号信息'), findsOneWidget);

    // 4. 点击设置按钮弹出全局配置弹窗
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();

    expect(find.text('General'), findsWidgets);
    expect(find.text('保存设置'), findsOneWidget);

    // 关闭设置弹窗
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    // 5. 验证 AgentCard 右上角会话管理按钮与视图切换
    final sessionBtn = find.byTooltip('会话管理');
    expect(sessionBtn, findsOneWidget);

    await tester.tap(sessionBtn);
    await tester.pumpAndSettle();

    // 验证展示了会话管理视图
    expect(find.text('新建会话'), findsOneWidget);
    expect(find.byTooltip('返回对话'), findsOneWidget);

    // 点击返回对话
    await tester.tap(find.byTooltip('返回对话'));
    await tester.pumpAndSettle();

    // 恢复为对话界面
    expect(find.byTooltip('会话管理'), findsOneWidget);
  });
}

