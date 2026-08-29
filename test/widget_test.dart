import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/main.dart';

void main() {
  testWidgets('NovelAiHarnessApp sidebar navigation and tab switching test', (WidgetTester tester) async {
    // Set a large desktop-like window size for tester
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const NovelAiHarnessApp());
    await tester.pumpAndSettle();

    // 1. 验证侧边栏项目
    expect(find.text('参数'), findsWidgets);
    expect(find.text('提示词'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);

    // 2. 默认参数页内容
    expect(find.text('参数设置'), findsOneWidget);
    expect(find.text('模型'), findsOneWidget);
    expect(find.text('图像画板'), findsOneWidget);
    expect(find.text('生成图片'), findsOneWidget);
    expect(find.textContaining('未获取账号信息'), findsOneWidget);

    // 3. 点击切换至提示词页
    await tester.tap(find.text('提示词'));
    await tester.pumpAndSettle();

    expect(find.text('提示词管理'), findsOneWidget);
    expect(find.text('固定前置词 (Prefix)'), findsOneWidget);
    expect(find.text('固定后置词 (Suffix)'), findsOneWidget);
    expect(find.text('负面提示词 (Negative Prompt)'), findsOneWidget);
    // 验证生成图片和账号卡片仍然常驻显示
    expect(find.text('生成图片'), findsOneWidget);
    expect(find.textContaining('未获取账号信息'), findsOneWidget);

    // 4. 点击设置按钮弹出全局配置弹窗
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();

    expect(find.text('全局参数与模型配置'), findsOneWidget);
    expect(find.text('保存设置'), findsOneWidget);
  });
}
