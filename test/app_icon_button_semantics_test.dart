import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/ui/core/widgets/app_icon_button.dart';
import 'package:novelai_harness/ui/core/widgets/app_async_icon_button.dart';

void main() {
  testWidgets('icon actions expose a name, role and enabled state', (
    tester,
  ) async {
    var activations = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              AppIconButton(
                icon: Icons.add,
                tooltip: '添加附件',
                onPressed: () => activations++,
              ),
              const AppIconButton(icon: Icons.delete, tooltip: '删除'),
            ],
          ),
        ),
      ),
    );
    final add = tester.getSemantics(find.bySemanticsLabel('添加附件'));
    expect(add.flagsCollection.isButton, isTrue);
    expect(add.flagsCollection.isEnabled == ui.Tristate.isTrue, isTrue);
    tester.platformDispatcher.onSemanticsActionEvent!(
      ui.SemanticsActionEvent(
        type: ui.SemanticsAction.tap,
        viewId: tester.view.viewId,
        nodeId: add.id,
      ),
    );
    await tester.pump();
    expect(activations, 1);
    final remove = tester.getSemantics(find.bySemanticsLabel('删除'));
    expect(remove.flagsCollection.isButton, isTrue);
    expect(remove.flagsCollection.isEnabled != ui.Tristate.none, isTrue);
    expect(remove.flagsCollection.isEnabled == ui.Tristate.isTrue, isFalse);
    expect(
      remove.getSemanticsData().hasAction(ui.SemanticsAction.tap),
      isFalse,
    );
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(200, 200));
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byIcon(Icons.add)));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    final hovered = tester.getSemantics(find.byIcon(Icons.add));
    expect(hovered.label, '添加附件');
    expect(hovered.flagsCollection.isButton, isTrue);
    expect(
      hovered.getSemanticsData().hasAction(ui.SemanticsAction.tap),
      isTrue,
    );
  });

  testWidgets('busy icon actions keep a name but cannot be activated', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppAsyncIconButton(
            icon: Icons.send,
            tooltip: '发送',
            loadingTooltip: '正在回复',
            isLoading: true,
            onPressed: () => fail('Busy action must not be invoked'),
          ),
        ),
      ),
    );
    final busy = tester.getSemantics(find.bySemanticsLabel('正在回复'));
    expect(busy.flagsCollection.isButton, isTrue);
    expect(busy.flagsCollection.isEnabled != ui.Tristate.none, isTrue);
    expect(busy.flagsCollection.isEnabled == ui.Tristate.isTrue, isFalse);
    expect(busy.getSemanticsData().hasAction(ui.SemanticsAction.tap), isFalse);
  });
}
