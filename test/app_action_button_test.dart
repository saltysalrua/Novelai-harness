import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/ui/core/widgets/app_action_button.dart';
import 'package:novelai_harness/ui/core/widgets/app_number_slider.dart';

void main() {
  testWidgets('AppActionButton outlined 变体渲染图标与文案并响应点击', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: AppActionButton(
              icon: Icons.folder_open_rounded,
              label: '选择',
              onPressed: () => tapped++,
            ),
          ),
        ),
      ),
    );

    expect(find.text('选择'), findsOneWidget);
    expect(find.byIcon(Icons.folder_open_rounded), findsOneWidget);
    expect(find.byType(OutlinedButton), findsOneWidget);

    await tester.tap(find.byType(AppActionButton));
    await tester.pumpAndSettle();
    expect(tapped, 1);
  });

  testWidgets('AppActionButton 无图标时退化为纯文字按钮', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: AppActionButton(label: '导入')),
        ),
      ),
    );
    expect(find.text('导入'), findsOneWidget);
  });

  testWidgets('AppActionButton onPressed 为 null 时禁用且不响应点击', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: AppActionButton(icon: Icons.add_rounded, label: '新建'),
          ),
        ),
      ),
    );

    final button = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
    expect(button.onPressed, isNull);

    await tester.tap(find.byType(AppActionButton));
    await tester.pumpAndSettle();
    // 禁用态点击不抛异常即通过
  });

  testWidgets('AppNumberSlider 标题传 null 时不渲染标题行 (嵌入 tile 场景)', (tester) async {
    var value = 5.0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppNumberSlider(
            title: null,
            value: value,
            min: 0,
            max: 10,
            onChanged: (v) => value = v,
          ),
        ),
      ),
    );

    // 无标题 → 组件只渲染输入框 + 滑块，不出现加粗标题文本
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
  });

  testWidgets('AppNumberSlider 保留标题时正常渲染标题行', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppNumberSlider(
            title: '默认步数 (Steps)',
            value: 5,
            min: 0,
            max: 10,
            onChanged: (v) {},
          ),
        ),
      ),
    );
    expect(find.text('默认步数 (Steps)'), findsOneWidget);
  });
}
