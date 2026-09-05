import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/ui/core/theme/app_theme.dart';
import 'package:novelai_harness/ui/core/widgets/app_number_slider.dart';
import 'package:novelai_harness/ui/features/studio/widgets/prompt_resize_handle.dart';

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.lightTheme,
  home: Scaffold(body: SizedBox(width: 400, child: child)),
);

void main() {
  testWidgets('slider previews locally and commits once on release', (
    tester,
  ) async {
    final commits = <double>[];
    var value = 5.0;
    var builds = 0;
    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) {
            builds++;
            return AppNumberSlider(
              value: value,
              min: 1,
              max: 15,
              fractionDigits: 1,
              onChanged: (v) {
                commits.add(v);
                setState(() => value = v);
              },
            );
          },
        ),
      ),
    );
    final baseline = builds;
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(Slider)),
    );
    for (var i = 0; i < 5; i++) {
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump();
    }
    expect(commits, isEmpty);
    expect(builds, baseline);
    expect(tester.widget<Slider>(find.byType(Slider)).value, greaterThan(5));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(commits, hasLength(1));
    expect(value, greaterThan(5));
    expect(builds, baseline + 1);
  });

  testWidgets('external slider value supersedes pending drag', (tester) async {
    final commits = <double>[];
    Widget slider(double value) => _host(
      AppNumberSlider(value: value, min: 1, max: 15, onChanged: commits.add),
    );
    await tester.pumpWidget(slider(5));
    tester.widget<Slider>(find.byType(Slider)).onChanged!(10);
    await tester.pump();
    await tester.pumpWidget(slider(3));
    tester.widget<Slider>(find.byType(Slider)).onChangeEnd!(10);
    await tester.pump();
    expect(commits, isEmpty);
    expect(tester.widget<Slider>(find.byType(Slider)).value, 3);
  });

  for (final cancel in [false, true]) {
    testWidgets(
      'prompt resize isolates editor and commits once (cancel=$cancel)',
      (tester) async {
        final controller = TextEditingController(text: '1girl, solo');
        addTearDown(controller.dispose);
        final commits = <double>[];
        await tester.pumpWidget(
          _host(
            ResizableTextField(
              controller: controller,
              onChanged: (_) {},
              hintText: '',
              defaultHeight: 120,
              maxHeight: 240,
              enableAutocomplete: false,
              onHeightChanged: commits.add,
            ),
          ),
        );
        final editor = tester.widget<TextField>(find.byType(TextField));
        final before = tester.getSize(find.byType(TextField)).height;
        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(PromptResizeHandle)),
        );
        for (var i = 0; i < 5; i++) {
          await gesture.moveBy(const Offset(0, 15));
          await tester.pump();
        }
        expect(commits, isEmpty);
        expect(
          tester.getSize(find.byType(TextField)).height,
          greaterThan(before),
        );
        expect(
          identical(editor, tester.widget<TextField>(find.byType(TextField))),
          isTrue,
        );
        if (cancel) {
          await gesture.cancel();
        } else {
          await gesture.up();
        }
        await tester.pumpAndSettle();
        expect(commits, hasLength(1));
        expect(commits.single, greaterThan(120));
      },
    );
  }
}
