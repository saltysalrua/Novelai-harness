import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/data/services/config_service.dart';
import 'package:novelai_harness/main.dart';
import 'package:novelai_harness/ui/core/locale/app_locale_controller.dart';
import 'package:novelai_harness/ui/core/theme/ui_zoom_controller.dart';
import 'package:novelai_harness/ui/core/widgets/app_dropdown.dart';
import 'package:novelai_harness/ui/core/widgets/app_icon_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The desktop engine accepts only nodes connected to its root. Widget-level
// label tests do not detect detached overlay nodes sent across this boundary.
class _TreeRecorder {
  final nodes = <int, List<int>>{};
  final violations = <String>[];

  void accept(Map<int, ({String label, List<int> children})> updates) {
    if (updates.isEmpty) return;
    if (nodes.isEmpty && !updates.containsKey(0)) {
      violations.add('Initial update is missing root 0');
    }
    for (final entry in updates.entries) {
      nodes[entry.key] = entry.value.children;
    }
    if (!nodes.containsKey(0)) return;
    final reachable = <int>{};
    void visit(int id) {
      if (!reachable.add(id)) return;
      final children = nodes[id];
      if (children == null) {
        violations.add('Missing referenced node $id');
        return;
      }
      for (final child in children) {
        visit(child);
      }
    }

    visit(0);
    for (final entry in updates.entries) {
      if (!reachable.contains(entry.key)) {
        violations.add('${entry.key}: ${entry.value.label}');
      }
    }
    nodes.removeWhere((id, _) => !reachable.contains(id));
  }
}

class _RecordingBinding extends AutomatedTestWidgetsFlutterBinding {
  final recorder = _TreeRecorder();

  @override
  ui.SemanticsUpdateBuilder createSemanticsUpdateBuilder() =>
      _RecordingBuilder(recorder);
}

class _RecordingBuilder extends Fake implements ui.SemanticsUpdateBuilder {
  _RecordingBuilder(this.recorder);
  final _TreeRecorder recorder;
  final updates = <int, ({String label, List<int> children})>{};

  @override
  Object? noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #updateNode) {
      final args = invocation.namedArguments;
      updates[args[#id]! as int] = (
        label: args[#label]! as String,
        children: List<int>.of(args[#childrenInTraversalOrder]! as List<int>),
      );
      return null;
    }
    if (invocation.memberName == #updateCustomAction) return null;
    return super.noSuchMethod(invocation);
  }

  @override
  ui.SemanticsUpdate build() {
    recorder.accept(updates);
    return ui.SemanticsUpdateBuilder().build();
  }
}

void main() {
  final binding = _RecordingBinding();
  WidgetController.hitTestWarningShouldBeFatal = true;

  setUp(() {
    binding.recorder.nodes.clear();
    binding.recorder.violations.clear();
  });

  test('tree validator rejects incomplete native update batches', () {
    final missingRoot = _TreeRecorder()
      ..accept({7: (label: 'child', children: <int>[])})
      ..accept({
        0: (label: 'root', children: <int>[7]),
      });
    expect(missingRoot.violations, isNotEmpty);
    final missingChild = _TreeRecorder()
      ..accept({
        0: (label: 'root', children: <int>[42]),
      });
    expect(missingChild.violations, isNotEmpty);
    final complete = _TreeRecorder()
      ..accept({
        0: (label: 'root', children: <int>[7]),
        7: (label: 'child', children: <int>[]),
      });
    expect(complete.violations, isEmpty);
  });

  testWidgets('adjacent icon tooltips keep their overlay nodes connected', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              Row(
                children: [
                  AppIconButton(
                    icon: Icons.add,
                    tooltip: 'Add',
                    onPressed: () {},
                  ),
                  AppIconButton(
                    icon: Icons.close,
                    tooltip: 'Close',
                    onPressed: () {},
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(binding.recorder.nodes.length, greaterThan(1));
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(200, 200));
    addTearDown(mouse.removePointer);
    for (final icon in [Icons.add, Icons.close]) {
      await mouse.moveTo(tester.getCenter(find.byIcon(icon)));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(binding.recorder.violations, isEmpty);
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets(
    'late macOS semantics activation and settings stay connected',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'llm_api_key': '',
        'novelai_enable_tag_dictionary_auto_update': false,
        'novelai_enable_image_persistence': false,
      });
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      AppLocaleController.instance.syncFromConfig(
        const AppConfig(localePreference: AppLocalePreference.zh),
      );
      addTearDown(AppLocaleController.instance.resetForTest);
      addTearDown(AppUiZoomController.instance.resetForTest);
      await tester.pumpWidget(const NovelAiHarnessApp());
      await tester.pumpAndSettle();
      expect(binding.recorder.nodes, isEmpty);
      final handle = tester.ensureSemantics();
      try {
        await tester.pumpAndSettle();
        expect(binding.recorder.nodes.length, greaterThan(10));

        final mouse = await tester.createGesture(
          kind: ui.PointerDeviceKind.mouse,
        );
        await mouse.addPointer(location: const Offset(1, 1));
        addTearDown(mouse.removePointer);
        for (final label in ['参数', '提示词', '修复', '词库', '设置']) {
          final target = find.text(label).first;
          await mouse.moveTo(tester.getCenter(target));
          await tester.pump(const Duration(seconds: 1));
          await tester.pumpAndSettle();
          expect(binding.recorder.violations, isEmpty, reason: 'hover $label');
          final hovered = tester.getSemantics(target);
          expect(hovered.label, label);
          expect(hovered.flagsCollection.isButton, isTrue);
        }

        await tester.tap(find.text('设置'));
        await tester.pumpAndSettle();
        final language = find.byType(AppDropdown<AppLocalePreference>);
        await tester.ensureVisible(language);
        await tester.tap(language);
        await tester.pumpAndSettle();
        await mouse.moveTo(tester.getCenter(find.text('English').last));
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        expect(
          binding.recorder.violations,
          isEmpty,
          reason: 'language popup tooltip',
        );
        await mouse.moveTo(const Offset(1, 1));
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byWidgetPredicate(
            (widget) =>
                widget is DropdownMenuItem<AppLocalePreference> &&
                widget.value == AppLocalePreference.en,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(
          binding.recorder.violations,
          isEmpty,
          reason: 'dismiss settings',
        );
        expect(AppLocaleController.instance.locale.value, const Locale('zh'));

        Future<void> choose<T>(T value) async {
          final dropdown = find.byType(AppDropdown<T>);
          await tester.ensureVisible(dropdown);
          await tester.tap(dropdown);
          await tester.pumpAndSettle();
          await tester.tap(
            find.byWidgetPredicate(
              (widget) =>
                  widget is DropdownMenuItem<T> && widget.value == value,
            ),
          );
          await tester.pumpAndSettle();
        }

        for (final (language, zoom, settingsLabel, saveLabel) in [
          (AppLocalePreference.en, 1.25, '设置', '保存设置'),
          (AppLocalePreference.zh, 1.0, 'Settings', 'Save Settings'),
        ]) {
          await tester.tap(find.text(settingsLabel));
          await tester.pumpAndSettle();
          await choose(language);
          await choose(zoom);
          await tester.tap(find.text(saveLabel));
          await tester.pumpAndSettle();
          expect(AppUiZoomController.instance.zoom.value, zoom);
          expect(
            binding.recorder.violations,
            isEmpty,
            reason: 'save $language/$zoom',
          );
          expect(binding.recorder.nodes.length, greaterThan(10));
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      } finally {
        handle.dispose();
      }
    },
    semanticsEnabled: false,
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
