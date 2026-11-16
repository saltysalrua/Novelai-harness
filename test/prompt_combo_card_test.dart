import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:novelai_harness/data/models/prompt_library_models.dart';
import 'package:novelai_harness/data/services/prompt_image_probe.dart';
import 'package:novelai_harness/l10n/app_localizations.dart';
import 'package:novelai_harness/ui/features/studio/widgets/prompt_combo_card.dart';

void main() {
  late Directory tempDir;
  late String portraitPngPath;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('prompt_card_test_');
    final portrait = img.Image(width: 100, height: 200);
    img.fill(portrait, color: img.ColorRgb8(120, 180, 240));
    portraitPngPath = '${tempDir.path}${Platform.pathSeparator}portrait.png';
    File(portraitPngPath).writeAsBytesSync(img.encodePng(portrait));
    PromptImageProbe.invalidate(portraitPngPath);
  });

  tearDown(() {
    PromptImageProbe.invalidate(portraitPngPath);
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  for (final width in [200.0, 280.0]) {
    testWidgets(
      'card renders full portrait image without empty borders at width $width',
      (tester) async {
        await tester.runAsync(() => PromptImageProbe.probeFile(portraitPngPath));

        final applied = <(bool, bool)>[];
        var edits = 0;
        var deletes = 0;
        final entry = PromptComboEntry(
          id: 'compact',
          title: '一个很长的角色组合名称用于验证单行截断',
          prompt: 'long hair, golden eyes, white dress, detailed background',
          negativePrompt: 'lowres, blurry',
          previewImagePath: portraitPngPath,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );

        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SingleChildScrollView(
                child: Center(
                  child: SizedBox(
                    width: width,
                    child: PromptComboCard(
                      combo: entry,
                      onApply: (replace, character) =>
                          applied.add((replace, character)),
                      onEdit: () => edits++,
                      onDelete: () => deletes++,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        final imageFinder = find.byType(Image);
        expect(imageFinder, findsOneWidget);
        final imageWidget = tester.widget<Image>(imageFinder);
        expect(imageWidget.fit, BoxFit.contain);
        expect(imageWidget.image, isA<ResizeImage>());

        // 图片渲染尺寸严格贴合原图 1:2 比例，零留白边框
        final imgSize = tester.getSize(imageFinder);
        expect(imgSize.width, closeTo(width - 2, 2.0));
        expect(imgSize.height, closeTo(imgSize.width * 2, 2.0));

        await tester.ensureVisible(find.byIcon(Icons.bolt_outlined));
        await tester.tap(find.byIcon(Icons.bolt_outlined));
        await tester.tap(find.byIcon(Icons.person_add_alt_1_outlined));
        await tester.tap(find.byIcon(Icons.edit_outlined));
        await tester.tap(find.byIcon(Icons.delete_outline));
        expect(applied, [(false, false), (false, true)]);
        expect(edits, 1);
        expect(deletes, 1);
        expect(tester.takeException(), isNull);
        expect(
          find.byTooltip('${entry.prompt}\nUC: ${entry.negativePrompt}'),
          findsOneWidget,
        );
      },
    );
  }

  testWidgets('card without preview image collapses into compact text card', (
    tester,
  ) async {
    final entry = PromptComboEntry(
      id: 'no_img',
      title: '纯文本词条',
      prompt: 'masterpiece, best quality',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 260,
              child: PromptComboCard(
                combo: entry,
                onApply: (_, _) {},
                onEdit: () {},
                onDelete: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(Image), findsNothing);
    expect(tester.getSize(find.byType(PromptComboCard)).height, lessThan(140));
  });
}
