import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/ui/core/theme/app_theme.dart';
import 'package:novelai_harness/ui/core/widgets/stable_edge_selection.dart';
import 'package:novelai_harness/ui/features/studio/widgets/agent_chat_messages.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('输入框拖出下边缘后匀速续选到全文，视口不来回跳', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final text = List.generate(
      30,
      (i) => 'line ${i.toString().padLeft(2, '0')} chat draft',
    ).join('\n');
    final tail = 'TAIL_TOKEN_END';
    final full = '$text\n$tail';
    final controller = TextEditingController(text: full);
    final scroll = ScrollController();
    final deltas = <double>[];
    scroll.addListener(() {
      final offset = scroll.offset;
      deltas.add(offset);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 280,
              height: 96,
              child: StableEdgeSelection(
                controller: scroll,
                child: TextField(
                  controller: controller,
                  scrollController: scroll,
                  scrollPhysics: const StableSelectionScrollPhysics(),
                  scrollPadding: EdgeInsets.zero,
                  maxLines: null,
                  expands: true,
                  decoration: const InputDecoration(border: InputBorder.none),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final box = tester.getRect(find.byType(TextField));
    final gesture = await tester.startGesture(
      box.topLeft + const Offset(12, 8),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveTo(Offset(box.left + 12, box.bottom + 24));
    for (var i = 0; i < 360 && controller.selection.end < full.length; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump();
    debugDefaultTargetPlatformOverride = null;

    expect(controller.selection.end, full.length);
    expect(full.substring(controller.selection.start), contains(tail));
    expect(deltas, isNotEmpty);
    for (var i = 1; i < deltas.length; i++) {
      final step = deltas[i] - deltas[i - 1];
      expect(step, greaterThanOrEqualTo(-0.5));
      expect(step, lessThanOrEqualTo(8.5));
    }
  });

  testWidgets('触控按住输入框下边缘同样能选到末尾', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final text =
        '${List.filled(24, 'touch line of the draft').join('\n')}\nEND';
    final controller = TextEditingController(text: text);
    final scroll = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 260,
              height: 80,
              child: StableEdgeSelection(
                controller: scroll,
                child: TextField(
                  controller: controller,
                  scrollController: scroll,
                  scrollPhysics: const StableSelectionScrollPhysics(),
                  scrollPadding: EdgeInsets.zero,
                  maxLines: null,
                  expands: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final box = tester.getRect(find.byType(TextField));
    final gesture = await tester.startGesture(
      box.topLeft + const Offset(10, 8),
      kind: PointerDeviceKind.touch,
    );
    await gesture.moveTo(Offset(box.left + 10, box.bottom + 20));
    for (var i = 0; i < 360 && controller.selection.end < text.length; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    expect(controller.selection.end, text.length);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('限高文本框拖出边缘时只滚自己，外层列表不动', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final text = List.generate(
      40,
      (i) => 'tool line $i ${'x' * 12}',
    ).join('\n');
    final tail = 'TOOL_TAIL';
    final full = '$text\n$tail';
    final parent = ScrollController();
    final deltas = <double>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 360,
            child: ListView(
              controller: parent,
              children: [
                const SizedBox(height: 48, child: Text('above')),
                BoundedSelectableText(
                  text: full,
                  maxHeight: 100,
                  style: const TextStyle(fontSize: 14, height: 1.4),
                ),
                const SizedBox(height: 480, child: Text('below')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final box = tester.getRect(find.byType(BoundedSelectableText));
    final inner = tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(BoundedSelectableText),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;
    inner.addListener(() => deltas.add(inner.pixels));
    int selectionEnd() {
      final selection = tester
          .state<EditableTextState>(find.byType(EditableText))
          .textEditingValue
          .selection;
      return selection.isValid ? selection.end : -1;
    }

    final gesture = await tester.startGesture(
      box.topLeft + const Offset(8, 8),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveTo(Offset(box.left + 8, box.bottom + 16));
    for (var i = 0; i < 400 && selectionEnd() < full.length; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump();

    final selection = tester
        .state<EditableTextState>(find.byType(EditableText))
        .textEditingValue
        .selection;
    expect(selection.end, full.length);
    expect(parent.offset, 0);
    expect(deltas, isNotEmpty);
    for (var i = 1; i < deltas.length; i++) {
      final step = deltas[i] - deltas[i - 1];
      expect(step, greaterThanOrEqualTo(-0.5));
      expect(step, lessThanOrEqualTo(8.5));
    }
    debugDefaultTargetPlatformOverride = null;
    parent.dispose();
  });

  testWidgets('Markdown 拖出列表下边缘会平稳滚出全文并选中末尾', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final data = [
      ...List.generate(10, (i) => 'Paragraph $i. ${'word ' * 12}'),
      'TAIL_TOKEN_END is the last paragraph of this message.',
    ].join('\n\n');
    final parent = ScrollController();
    final offsets = <double>[];
    parent.addListener(() => offsets.add(parent.offset));
    String selected = '';
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: SizedBox(
            height: 160,
            child: SelectionArea(
              onSelectionChanged: (content) {
                selected = content?.plainText ?? '';
              },
              child: ListView(
                controller: parent,
                children: [AgentMarkdownBody(data: data)],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<MarkdownBody>(find.byType(MarkdownBody)).selectable,
      isFalse,
    );
    final viewport = tester.getRect(find.byType(ListView));
    final gesture = await tester.startGesture(
      viewport.topLeft + const Offset(16, 12),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveTo(Offset(viewport.left + 16, viewport.bottom + 28));
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump();

    expect(offsets, isNotEmpty);
    expect(parent.offset, greaterThan(40));
    for (var i = 1; i < offsets.length; i++) {
      expect(offsets[i], greaterThanOrEqualTo(offsets[i - 1] - 0.5));
    }
    expect(selected, contains('TAIL_TOKEN_END'));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('代码块拖出右边缘时横向滚动不来回跳，并能选到行尾', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final line = '${'abcdefghij' * 8}CODE_TAIL';
    final data = 'intro\n\n```\n$line\n```\n';
    final samples = <double>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: SizedBox(
            width: 180,
            child: SelectionArea(child: AgentMarkdownBody(data: data)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final scrollable = tester.state<ScrollableState>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.right,
      ),
    );
    scrollable.position.addListener(
      () => samples.add(scrollable.position.pixels),
    );
    final box = tester.getRect(find.byType(SingleChildScrollView));
    final gesture = await tester.startGesture(
      box.centerLeft + const Offset(8, 0),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveTo(Offset(box.right + 30, box.center.dy));
    String selectedText() {
      final value = tester
          .state<EditableTextState>(find.byType(EditableText))
          .textEditingValue;
      final selection = value.selection;
      if (!selection.isValid) return '';
      return selection.textInside(value.text);
    }

    for (var i = 0; i < 500 && !selectedText().contains('CODE_TAIL'); i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump();
    expect(samples, isNotEmpty);
    for (var i = 1; i < samples.length; i++) {
      final step = samples[i] - samples[i - 1];
      expect(step, greaterThanOrEqualTo(-0.5));
      expect(step, lessThanOrEqualTo(8.5));
    }
    expect(selectedText(), contains('CODE_TAIL'));
    debugDefaultTargetPlatformOverride = null;
  });
}
