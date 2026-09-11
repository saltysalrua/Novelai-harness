import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/data/models/novelai_models.dart';
import 'package:novelai_harness/l10n/app_localizations.dart';
import 'package:novelai_harness/ui/features/studio/view_models/studio_view_model.dart';
import 'package:novelai_harness/ui/features/studio/widgets/character_position_canvas_view.dart';
import 'package:novelai_harness/ui/features/studio/widgets/resolution_pad_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _host(
  Widget child,
  PageController pages,
  ScrollController list, {
  double height = 300,
}) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: PageView(
      controller: pages,
      children: [
        const SizedBox.expand(),
        ListView(
          controller: list,
          children: [
            const SizedBox(
              height: 80,
              child: ColoredBox(key: ValueKey('outside'), color: Colors.blue),
            ),
            Center(
              child: SizedBox(width: 300, height: height, child: child),
            ),
            const SizedBox(height: 1600),
          ],
        ),
        const SizedBox.expand(),
      ],
    ),
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final target in [
    'resolution',
    'character-v5',
    'character-v4',
    'watermark',
    'watermark-resize',
  ]) {
    for (final delta in [
      const Offset(-8, 0),
      const Offset(0, -8),
      const Offset(-6, -6),
    ]) {
      if (target == 'watermark-resize' && delta.dx == 0) continue;
      for (final cancel in [false, true]) {
        testWidgets(
          '$target $delta ${cancel ? 'cancel' : 'release'} owns the drag, without moving either ancestor',
          (tester) async {
            tester.view.physicalSize = const Size(390, 700);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final pages = PageController(initialPage: 1);
            final list = ScrollController();
            final vm = StudioViewModel();
            addTearDown(pages.dispose);
            addTearDown(list.dispose);
            addTearDown(vm.dispose);
            vm.updateParams(
              vm.params.copyWith(
                model: target == 'character-v4'
                    ? NaiModel.v4Full
                    : NaiModel.v5Full,
                characterPrompts: [
                  const NaiCharacterPrompt(
                    id: 'a',
                    name: 'A',
                    prompt: 'girl',
                    useCustomPosition: true,
                    positionX: 0.5,
                    positionY: 0.5,
                  ),
                ],
              ),
            );
            vm.selectCharacterId('a');
            vm.updateWatermarkConfig(
              vm.watermarkConfig.copyWith(
                posX: 0.5,
                posY: 0.5,
                scalePercent: 40,
              ),
            );
            var width = 832;
            var height = 1216;
            final commits = <({int width, int height})>[];
            var notifications = 0;
            vm.addListener(() => notifications++);
            final Widget child = switch (target) {
              'resolution' => StatefulBuilder(
                builder: (context, setState) => ResolutionPadPicker(
                  width: width,
                  height: height,
                  onChanged: (value) {
                    commits.add(value);
                    setState(() {
                      width = value.width;
                      height = value.height;
                    });
                  },
                ),
              ),
              'watermark' ||
              'watermark-resize' => WatermarkPositionOverlay(viewModel: vm),
              _ => CharacterPositionOverlay(viewModel: vm),
            };
            await tester.pumpWidget(
              _host(
                child,
                pages,
                list,
                height: target == 'resolution' ? 470 : 300,
              ),
            );
            await tester.pumpAndSettle();
            final key = switch (target) {
              'resolution' => 'resolution_pan_surface',
              'watermark' => 'watermark_move_surface',
              'watermark-resize' => 'watermark_resize_surface',
              _ => 'anchor-a',
            };
            final gesture = await tester.startGesture(
              tester.getCenter(find.byKey(ValueKey(key))),
            );
            for (var frame = 0; frame < 12; frame++) {
              await gesture.moveBy(delta);
              await tester.pump(const Duration(milliseconds: 16));
              expect(
                pages.page,
                closeTo(1, 0.0001),
                reason: 'page, frame=$frame',
              );
              expect(list.offset, 0, reason: 'vertical list, frame=$frame');
              expect(
                commits,
                isEmpty,
                reason: 'resolution commits only on release',
              );
              expect(notifications, 0, reason: 'no global per-frame rebuild');
            }
            if (cancel) {
              await gesture.cancel();
              await tester.pump(const Duration(milliseconds: 350));
              expect(commits, isEmpty);
              expect(notifications, 0);
              expect(vm.params.characterPrompts.single.positionX, 0.5);
              expect(vm.params.characterPrompts.single.positionY, 0.5);
              expect(vm.watermarkConfig.posX, 0.5);
              expect(vm.watermarkConfig.posY, 0.5);
              expect(vm.watermarkConfig.scalePercent, 40);
              expect(tester.takeException(), isNull);
              return;
            }
            await gesture.up();
            await tester.pumpAndSettle();
            switch (target) {
              case 'resolution':
                expect(commits, hasLength(1));
                expect((width, height), isNot((832, 1216)));
              case 'watermark':
                expect((
                  vm.watermarkConfig.posX,
                  vm.watermarkConfig.posY,
                ), isNot((0.5, 0.5)));
                expect(notifications, 1);
              case 'watermark-resize':
                expect(vm.watermarkConfig.scalePercent, lessThan(40));
                expect(notifications, 1);
              default:
                final c = vm.params.characterPrompts.single;
                expect((c.positionX, c.positionY), isNot((0.5, 0.5)));
                expect(notifications, 1);
            }
            await tester.pump(const Duration(milliseconds: 350));
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  testWidgets(
    'resolution tap still works; pointer cancellation discards preview; outside still scrolls',
    (tester) async {
      final pages = PageController(initialPage: 1);
      final list = ScrollController();
      addTearDown(pages.dispose);
      addTearDown(list.dispose);
      final commits = <({int width, int height})>[];
      await tester.pumpWidget(
        _host(
          ResolutionPadPicker(width: 832, height: 1216, onChanged: commits.add),
          pages,
          list,
          height: 470,
        ),
      );
      await tester.pumpAndSettle();
      final surface = find.byKey(const ValueKey('resolution_pan_surface'));
      await tester.tap(surface);
      await tester.pumpAndSettle();
      expect(commits, hasLength(1));
      commits.clear();
      final gesture = await tester.startGesture(tester.getCenter(surface));
      await gesture.moveBy(const Offset(-80, 0));
      await tester.pump();
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(commits, isEmpty);
      expect(pages.page, 1);
      expect(list.offset, 0);
      await tester.drag(
        find.byKey(const ValueKey('outside')),
        const Offset(0, -80),
      );
      await tester.pumpAndSettle();
      expect(list.offset, greaterThan(0));
      list.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const ValueKey('outside')),
        const Offset(-700, 0),
      );
      await tester.pumpAndSettle();
      expect(pages.page, 2);
      expect(tester.takeException(), isNull);
    },
  );
}
