import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/main.dart';
import 'package:novelai_harness/ui/features/studio/widgets/character_position_canvas_view.dart';
import 'package:novelai_harness/ui/features/studio/widgets/character_card_item.dart';

void main() {
  testWidgets(
    'Character position overlay flow: open, switch character, and ESC exit',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(const NovelAiHarnessApp());
      await tester.pumpAndSettle();

      // 1. 切换到提示词标签页
      await tester.tap(find.text('提示词'));
      await tester.pumpAndSettle();

      // 2. 向上滚动提示词管理页面以露出 Character Prompts 区域
      final promptsTitle = find.text('提示词管理');
      expect(promptsTitle, findsOneWidget);
      await tester.drag(promptsTitle, const Offset(0, -450));
      await tester.pumpAndSettle();

      // 3. 找到添加角色按钮并添加两个角色
      final addBtn = find.text('添加角色');
      expect(addBtn, findsOneWidget);
      await tester.tap(addBtn);
      await tester.pumpAndSettle();
      await tester.tap(addBtn);
      await tester.pumpAndSettle();

      // 验证添加了 2 个角色卡片
      expect(find.byType(CharacterCardItem), findsNWidgets(2));

      // 向上滑动以确保模式行完全在视口内
      await tester.drag(find.text('Character Prompts'), const Offset(0, -100));
      await tester.pumpAndSettle();

      // 4. 点击模式行中的“画板编辑”胶囊按钮进入位置编辑
      final canvasEditBtn = find.text('画板编辑');
      expect(canvasEditBtn, findsOneWidget);
      await tester.tap(canvasEditBtn);
      await tester.pumpAndSettle();

      // 5. 验证中间画板叠加了 CharacterPositionOverlay 与 FloatingControls
      expect(find.byType(CharacterPositionOverlay), findsOneWidget);
      expect(find.byType(CanvasPositionFloatingControls), findsOneWidget);
      expect(find.text('完成编辑'), findsOneWidget);

      // 6. 按键盘右键切换到下一个角色
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();

      // 按键盘左键切换回上一个角色
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();

      // 7. 点击完成编辑按钮，退出画板编辑
      await tester.tap(find.text('完成编辑'));
      await tester.pumpAndSettle();

      expect(find.byType(CharacterPositionOverlay), findsNothing);
      expect(find.byType(CanvasPositionFloatingControls), findsNothing);

      // 8. 再次点击“画板编辑”进入编辑模式，并通过 ESC 键快速退出
      await tester.tap(canvasEditBtn);
      await tester.pumpAndSettle();

      expect(find.byType(CharacterPositionOverlay), findsOneWidget);

      // 按下 ESC 键
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(CharacterPositionOverlay), findsNothing);

      // 9. 再次进入“画板编辑”，点击“AI 自动”胶囊切换模式，验证画板编辑自动退出
      await tester.tap(canvasEditBtn);
      await tester.pumpAndSettle();

      expect(find.byType(CharacterPositionOverlay), findsOneWidget);

      final aiAutoBtn = find.text('AI 自动');
      expect(aiAutoBtn, findsOneWidget);
      await tester.tap(aiAutoBtn);
      await tester.pumpAndSettle();

      expect(find.byType(CharacterPositionOverlay), findsNothing);
      expect(find.byType(CanvasPositionFloatingControls), findsNothing);
    },
  );
}
