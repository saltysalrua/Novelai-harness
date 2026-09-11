import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/data/models/novelai_models.dart';
import 'package:novelai_harness/data/models/prompt_library_models.dart';
import 'package:novelai_harness/data/repositories/novelai_repository.dart';
import 'package:novelai_harness/l10n/app_localizations.dart';
import 'package:novelai_harness/ui/core/widgets/context_menu.dart';
import 'package:novelai_harness/ui/features/studio/view_models/studio_view_model.dart';
import 'package:novelai_harness/ui/features/studio/widgets/canvas_history_sidebar.dart';
import 'package:novelai_harness/ui/features/studio/widgets/image_stream_view.dart';
import 'package:novelai_harness/ui/features/studio/widgets/prompt_combo_card.dart';

void main() {
  for (final target in ['canvas', 'history', 'library']) {
    testWidgets('$target long press opens the existing context menu', (
      tester,
    ) async {
      final repo = NovelAiRepository();
      final vm = StudioViewModel(repository: repo);
      final stream = CanvasStreamController();
      addTearDown(vm.dispose);
      addTearDown(stream.dispose);
      final image = NaiGeneratedImage(
        id: 'test',
        bytes: base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg==',
        ),
        params: const NaiGenerationParams(prompt: 'landscape'),
        createdAt: DateTime(2026),
        seed: 42,
        isOpusFree: true,
      );
      repo.addImageForTesting(image);
      var deleted = false;
      final Widget card = switch (target) {
        'canvas' => CanvasImageCard(
          viewModel: vm,
          controller: stream,
          item: image,
          isSelected: true,
          maxCardWidth: 220,
          maxCardHeight: 280,
        ),
        'history' => CanvasHistorySidebar(
          viewModel: vm,
          stream: stream,
          selectedImage: image,
          onClose: () {},
        ),
        _ => PromptComboCard(
          combo: PromptComboEntry(
            id: 'test',
            title: 'landscape',
            prompt: 'landscape',
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
          ),
          onApply: (_, _) {},
          onEdit: () {},
          onDelete: () => deleted = true,
        ),
      };
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Center(child: SizedBox(width: 220, height: 320, child: card)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.longPress(find.byType(StudioContextMenuRegion).first);
      await tester.pumpAndSettle();
      final deleteIcon = target == 'library'
          ? Icons.delete_outline
          : Icons.delete_outline_rounded;
      // 实际菜单的删除动作是 InkWell；词库卡片自身还有一个删除按钮。
      expect(
        find.byIcon(deleteIcon),
        target == 'library' ? findsNWidgets(2) : findsOneWidget,
      );
      if (target == 'library') {
        await tester.tap(find.byIcon(deleteIcon).last);
        await tester.pumpAndSettle();
        expect(deleted, isTrue);
      } else {
        expect(vm.selectedImage?.id, image.id);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byIcon(deleteIcon), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('context region preserves tap/drag and mouse secondary click', (
    tester,
  ) async {
    var taps = 0;
    final positions = <Offset>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              StudioContextMenuRegion(
                onShow: positions.add,
                child: GestureDetector(
                  onTap: () => taps++,
                  child: const SizedBox(
                    height: 250,
                    child: ColoredBox(color: Colors.blue),
                  ),
                ),
              ),
              const SizedBox(height: 2000),
            ],
          ),
        ),
      ),
    );
    final region = find.byType(StudioContextMenuRegion);
    await tester.tap(region);
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(positions, isEmpty);
    final point = tester.getCenter(region);
    await tester.tapAt(
      point,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    expect(positions, [point]);
    await tester.longPress(region);
    await tester.pumpAndSettle();
    expect(positions, [point, point]);
    expect(taps, 1);
    await tester.drag(region, const Offset(0, -180));
    await tester.pumpAndSettle();
    expect(positions.length, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'touch menu fits a short viewport, scrolls, and back does not reach page',
    (tester) async {
      tester.view.physicalSize = const Size(390, 320);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var underlyingBacks = 0;
      var selected = -1;
      await tester.pumpWidget(
        MaterialApp(
          home: PopScope(
            canPop: false,
            onPopInvokedWithResult: (_, _) => underlyingBacks++,
            child: Scaffold(
              body: Builder(
                builder: (context) => StudioContextMenuRegion(
                  onShow: (position) => showStudioContextMenu(
                    context,
                    position: position,
                    actions: [
                      for (var i = 0; i < 14; i++)
                        ContextMenuItem(
                          icon: Icons.check,
                          label: 'action $i',
                          onTap: () => selected = i,
                        ),
                    ],
                  ),
                  child: const Center(child: Text('hold')),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.longPress(find.text('hold'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -700),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('action 13'));
      await tester.pumpAndSettle();
      expect(selected, 13);
      expect(find.text('action 13'), findsNothing);
      await tester.longPress(find.text('hold'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('action 0'), findsNothing);
      expect(underlyingBacks, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
