import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/ui/core/widgets/context_menu.dart';

void main() {
  testWidgets('showStudioContextMenu renders, invokes callback and dismisses', (
    WidgetTester tester,
  ) async {
    var tapped = false;
    final key = GlobalKey();

    var destructiveTapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              key: key,
              onPressed: () {
                showStudioContextMenu(
                  context,
                  position: const Offset(50, 50),
                  actions: [
                    const ContextMenuDivider(),
                    ContextMenuItem(
                      icon: Icons.content_copy_rounded,
                      label: '复制图像',
                      onTap: () => tapped = true,
                    ),
                    const ContextMenuItem(
                      icon: Icons.block_rounded,
                      label: '置灰项',
                    ),
                    ContextMenuItem(
                      icon: Icons.delete_outline_rounded,
                      label: '从历史记录删除',
                      isDestructive: true,
                      onTap: () => destructiveTapped = true,
                    ),
                  ],
                );
              },
              child: const Text('trigger'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();

    // 点击普通菜单项：触发回调并关闭
    await tester.tap(find.text('复制图像'));
    await tester.pumpAndSettle();
    expect(tapped, isTrue);
    expect(find.text('复制图像'), findsNothing);

    // 重新打开，验证破坏性操作项使用 AppTheme.coral 颜色渲染
    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();

    final deleteText = tester.widget<Text>(find.text('从历史记录删除'));
    expect(deleteText.style?.color, equals(const Color(0xFFF64932)));

    // 点击破坏性菜单项：触发回调并关闭
    await tester.tap(find.text('从历史记录删除'));
    await tester.pumpAndSettle();
    expect(destructiveTapped, isTrue);
    expect(find.text('从历史记录删除'), findsNothing);

    // 重新打开，点击外部区域关闭
    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();
    expect(find.text('复制图像'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('复制图像'), findsNothing);
  });
}
