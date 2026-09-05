import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/ui/core/widgets/app_dropdown.dart';

void main() {
  testWidgets('收起态只挂载当前选项，菜单仍能选择其他模型', (tester) async {
    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return AppDropdown<int>(
                value: selected,
                items: List.generate(
                  100,
                  (index) =>
                      AppDropdownItem(value: index, label: 'model-$index'),
                ),
                onChanged: (value) => setState(() => selected = value),
              );
            },
          ),
        ),
      ),
    );
    expect(find.text('model-0', skipOffstage: false), findsOneWidget);
    expect(find.text('model-1', skipOffstage: false), findsNothing);
    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('model-1').last);
    await tester.pumpAndSettle();
    expect(selected, 1);
    expect(find.text('model-1'), findsOneWidget);
    expect(find.text('model-0', skipOffstage: false), findsNothing);
  });
}
