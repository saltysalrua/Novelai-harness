import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/data/services/tag_dictionary_service.dart';
import 'package:novelai_harness/ui/features/studio/widgets/prompt_resize_handle.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sampleTsv = '''
1girl\t6008644\t1个女孩\t1girls,sole_female
solo\t5000954\t单人\tfemale_solo,solo_female
long_hair\t4350743\t长发\t/lh,longhair
blue_eyes\t1762765\t蓝眼\tblueeyes,light_blue_eyes
''';

  setUp(() async {
    await TagDictionaryService.instance.ensureLoaded(rawTsvContent: sampleTsv);
  });

  testWidgets('ResizableTextField triggers autocomplete overlay and applies selection on tap', (tester) async {
    final controller = TextEditingController();
    String updated = '';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: ResizableTextField(
              controller: controller,
              onChanged: (val) => updated = val,
              hintText: '输入提示词...',
              defaultHeight: 120,
            ),
          ),
        ),
      ),
    );

    // 聚焦输入框并输入 "lo"
    final textFieldFinder = find.byType(TextField);
    expect(textFieldFinder, findsOneWidget);

    await tester.tap(textFieldFinder);
    await tester.pump();

    await tester.enterText(textFieldFinder, 'lo');
    await tester.pumpAndSettle(const Duration(milliseconds: 250));

    // 悬浮补全卡片出现 (纯净无头部栏)
    expect(find.textContaining('long hair'), findsOneWidget);
    expect(find.text('长发'), findsOneWidget);
    expect(find.text('通用'), findsAtLeast(1));

    // 点击建议项
    await tester.tap(find.textContaining('long hair'));
    await tester.pumpAndSettle();

    // 成功上屏并追加逗号与空格
    expect(controller.text, 'long hair, ');
    expect(updated, 'long hair, ');
  });

  testWidgets('positions autocomplete overlay to the right (image column) in multi-column layout', (tester) async {
    tester.view.physicalSize = const Size(1380, 860);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final controller = TextEditingController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              SizedBox(
                width: 320,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: ResizableTextField(
                    controller: controller,
                    onChanged: (val) {},
                    hintText: '输入提示词...',
                    defaultHeight: 120,
                  ),
                ),
              ),
              const Expanded(
                child: ColoredBox(
                  color: Colors.grey,
                  child: Center(child: Text('Image Column')),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final textFieldFinder = find.byType(TextField);
    await tester.tap(textFieldFinder);
    await tester.pump();

    await tester.enterText(textFieldFinder, 'lo');
    await tester.pumpAndSettle(const Duration(milliseconds: 250));

    expect(find.textContaining('long hair'), findsOneWidget);

    // 验证补全卡片位于 X > 320px 的中间图片栏区域
    final cardCenter = tester.getCenter(find.textContaining('long hair'));
    expect(cardCenter.dx, greaterThan(320.0));

    // 点击建议项
    await tester.tap(find.textContaining('long hair'));
    await tester.pumpAndSettle();

    expect(controller.text, 'long hair, ');
  });

  testWidgets('ArrowDown navigates items naturally and Enter applies it', (tester) async {
    final controller = TextEditingController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: ResizableTextField(
              controller: controller,
              onChanged: (val) {},
              hintText: '输入提示词...',
              defaultHeight: 120,
            ),
          ),
        ),
      ),
    );

    final textFieldFinder = find.byType(TextField);
    await tester.tap(textFieldFinder);
    await tester.pump();

    // 输入 "s" 触发搜索 -> 会匹配到 solo / shirt 等
    await tester.enterText(textFieldFinder, 's');
    await tester.pumpAndSettle(const Duration(milliseconds: 250));

    expect(find.textContaining('solo'), findsOneWidget);

    // 按下 ArrowDown 键
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    // 按下 Enter 键确认上屏
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    // 验证成功上屏
    expect(controller.text.isNotEmpty, isTrue);
    expect(controller.text.endsWith(', '), isTrue);
  });

  testWidgets('applies suggestions within braces without inserting comma inside', (tester) async {
    final controller = TextEditingController(text: '{lo}');
    controller.selection = const TextSelection.collapsed(offset: 3); // 光标在 "lo" 后面

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: ResizableTextField(
              controller: controller,
              onChanged: (val) {},
              hintText: '输入提示词...',
              defaultHeight: 120,
            ),
          ),
        ),
      ),
    );

    final textFieldFinder = find.byType(TextField);
    await tester.tap(textFieldFinder);
    await tester.pump();
    await tester.pumpAndSettle(const Duration(milliseconds: 250));

    expect(find.textContaining('long hair'), findsOneWidget);

    // 点击建议项
    await tester.tap(find.textContaining('long hair'));
    await tester.pumpAndSettle();

    // 验证：花括号内部保留 long hair，逗号追加在花括号外部
    expect(controller.text, '{long hair}, ');
  });

  testWidgets('applies suggestions within NAI numeric weights accurately', (tester) async {
    final controller = TextEditingController(text: '1.2::lo::');
    controller.selection = const TextSelection.collapsed(offset: 7); // 光标在 "lo" 后面

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: ResizableTextField(
              controller: controller,
              onChanged: (val) {},
              hintText: '输入提示词...',
              defaultHeight: 120,
            ),
          ),
        ),
      ),
    );

    final textFieldFinder = find.byType(TextField);
    await tester.tap(textFieldFinder);
    await tester.pump();
    await tester.pumpAndSettle(const Duration(milliseconds: 250));

    expect(find.textContaining('long hair'), findsOneWidget);

    // 点击建议项
    await tester.tap(find.textContaining('long hair'));
    await tester.pumpAndSettle();

    // 验证：数值权重语法保持合法，逗号在 :: 之后
    expect(controller.text, '1.2::long hair::, ');
  });
}
