import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:novelai_harness/data/models/novelai_models.dart';
import 'package:novelai_harness/data/models/prompt_library_models.dart';
import 'package:novelai_harness/data/repositories/novelai_repository.dart';
import 'package:novelai_harness/data/services/config_service.dart';
import 'package:novelai_harness/l10n/app_localizations.dart';
import 'package:novelai_harness/ui/core/theme/app_theme.dart';
import 'package:novelai_harness/ui/core/widgets/app_action_button.dart';
import 'package:novelai_harness/ui/core/widgets/app_image_detail_layout.dart';
import 'package:novelai_harness/ui/features/studio/view_models/studio_view_model.dart';
import 'package:novelai_harness/ui/features/studio/widgets/metadata_reader_dialog.dart';
import 'package:novelai_harness/ui/features/studio/widgets/prompt_combo_edit_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _LibraryViewModel extends StudioViewModel {
  final Uint8List preview;
  PromptComboEntry? savedEntry;

  _LibraryViewModel(this.preview)
    : super(configService: ConfigService(), repository: NovelAiRepository());

  @override
  Uint8List? getCurrentCanvasImageBytes() => preview;

  @override
  Future<PromptComboEntry> addPromptCombo(PromptComboEntry entry) async {
    savedEntry = entry;
    return entry;
  }

  @override
  Future<void> updatePromptCombo(PromptComboEntry entry) async {
    savedEntry = entry;
  }

  @override
  Future<String?> savePromptPreviewFromBytes(
    Uint8List bytes, {
    String extension = 'png',
  }) async => 'prompt_previews/test.$extension';
}

void main() {
  late _LibraryViewModel viewModel;
  late Uint8List bytes;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    bytes = Uint8List.fromList(
      img.encodePng(img.Image(width: 320, height: 480)),
    );
    viewModel = _LibraryViewModel(bytes);
  });

  tearDown(() => viewModel.dispose());

  Future<void> openDialog(
    WidgetTester tester, {
    required bool metadata,
    Size size = const Size(1440, 1000),
    bool dark = false,
    Locale locale = const Locale('zh'),
    Uint8List? imageBytes,
    PromptComboEntry? entry,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                if (metadata) {
                  MetadataReaderDialog.show(
                    context,
                    metadata: ImageMetadataResult(
                      prompt: List.filled(
                        100,
                        'landscape, mountains',
                      ).join(', '),
                      negativePrompt: 'lowres',
                      width: 320,
                      height: 480,
                      software: 'NovelAI',
                      rawJson: '{"seed":42}',
                    ),
                    fileName:
                        '${List.filled(30, 'long_filename').join('_')}.png',
                    imageBytes: imageBytes,
                    viewModel: viewModel,
                  );
                } else {
                  PromptComboEditDialog.show(
                    context,
                    viewModel: viewModel,
                    initialEntry: entry,
                  );
                }
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Finder previewImage() => find.descendant(
    of: find.byType(AppImageDetailLayout),
    matching: find.byType(Image),
  );

  void expectUnobscuredImage(WidgetTester tester, {required bool wide}) {
    final image = tester.widget<Image>(previewImage());
    final rect = tester.getRect(previewImage());
    expect(image.fit, BoxFit.contain);
    expect(rect.width, greaterThan(wide ? 500 : 450));
    expect(rect.height, greaterThan(wide ? 500 : 150));
    for (final element in find.byType(AppActionButton).evaluate()) {
      final buttonRect = tester.getRect(find.byWidget(element.widget));
      expect(rect.overlaps(buttonRect), isFalse, reason: '任何操作按钮都不得覆盖图片');
    }
    final scroll = find
        .descendant(
          of: find.byType(AppImageDetailLayout),
          matching: find.byType(SingleChildScrollView),
        )
        .first;
    final detailsRect = tester.getRect(scroll);
    expect(rect.overlaps(detailsRect), isFalse);
    if (wide) {
      expect(rect.right, lessThan(detailsRect.left));
      expect(rect.width, greaterThan(detailsRect.width));
    } else {
      expect(rect.bottom, lessThan(detailsRect.top));
    }
    expect(tester.takeException(), isNull);
  }

  for (final metadata in [true, false]) {
    for (final dark in [false, true]) {
      testWidgets(
        '${metadata ? 'Metadata' : 'Library'} large unoccluded preview, dark=$dark',
        (tester) async {
          await openDialog(
            tester,
            metadata: metadata,
            dark: dark,
            imageBytes: bytes,
          );
          if (!metadata) {
            await tester.tap(find.text('使用画板当前图'));
            await tester.pumpAndSettle();
          }
          expectUnobscuredImage(tester, wide: true);
          final before = tester.getRect(previewImage());
          final details = find
              .descendant(
                of: find.byType(AppImageDetailLayout),
                matching: find.byType(SingleChildScrollView),
              )
              .first;
          await tester.drag(details, const Offset(0, -400));
          await tester.pumpAndSettle();
          expect(tester.getRect(previewImage()), before);
          expect(tester.takeException(), isNull);
        },
      );
    }

    for (final locale in [const Locale('zh'), const Locale('en')]) {
      testWidgets(
        '${metadata ? 'Metadata' : 'Library'} narrow window $locale',
        (tester) async {
          await openDialog(
            tester,
            metadata: metadata,
            imageBytes: bytes,
            size: const Size(640, 720),
            locale: locale,
          );
          if (!metadata) {
            final context = tester.element(find.byType(PromptComboEditDialog));
            final l10n = AppLocalizations.of(context);
            await tester.tap(find.text(l10n.libraryEditUseCanvasImage));
            await tester.pumpAndSettle();
          }
          expectUnobscuredImage(tester, wide: false);
        },
      );
    }
  }

  testWidgets(
    'Library preview can be removed and edit saved without losing fields',
    (tester) async {
      final now = DateTime(2026);
      await openDialog(
        tester,
        metadata: false,
        entry: PromptComboEntry(
          id: 'existing',
          title: '角色测试',
          prompt: 'girl, blue hair',
          negativePrompt: 'bad hands',
          tags: const ['blue', 'portrait'],
          createdAt: now,
          updatedAt: now,
        ),
      );
      final context = tester.element(find.byType(PromptComboEditDialog));
      final l10n = AppLocalizations.of(context);
      await tester.tap(find.text(l10n.libraryEditUseCanvasImage));
      await tester.pumpAndSettle();
      expect(previewImage(), findsOneWidget);
      await tester.tap(find.text(l10n.libraryEditRemovePreviewImage));
      await tester.pumpAndSettle();
      expect(previewImage(), findsNothing);
      expect(find.text('角色测试'), findsOneWidget);
      await tester.tap(find.text(l10n.libraryEditSaveButton));
      await tester.pumpAndSettle();
      expect(find.byType(PromptComboEditDialog), findsNothing);
      expect(viewModel.savedEntry?.id, 'existing');
      expect(viewModel.savedEntry?.prompt, 'girl, blue hair');
      expect(viewModel.savedEntry?.negativePrompt, 'bad hands');
      expect(viewModel.savedEntry?.tags, ['blue', 'portrait']);
      expect(viewModel.savedEntry?.previewImagePath, isNull);
    },
  );

  testWidgets(
    'Library validates required fields and saves a new image preset',
    (tester) async {
      await openDialog(tester, metadata: false);
      final context = tester.element(find.byType(PromptComboEditDialog));
      final l10n = AppLocalizations.of(context);
      await tester.tap(find.text(l10n.libraryEditCreateButton));
      await tester.pumpAndSettle();
      expect(viewModel.savedEntry, isNull);
      expect(find.byType(PromptComboEditDialog), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, l10n.libraryEditFieldTitleHint),
        '新预设',
      );
      await tester.enterText(
        find.widgetWithText(TextField, l10n.libraryEditFieldPromptHint),
        'girl, green eyes',
      );
      await tester.tap(find.text(l10n.libraryEditUseCanvasImage));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.libraryEditCreateButton));
      await tester.pumpAndSettle();
      expect(viewModel.savedEntry?.title, '新预设');
      expect(viewModel.savedEntry?.prompt, 'girl, green eyes');
      expect(
        viewModel.savedEntry?.previewImagePath,
        'prompt_previews/test.png',
      );
      expect(find.byType(PromptComboEditDialog), findsNothing);
    },
  );

  for (final size in [const Size(480, 320), const Size(400, 400)]) {
    testWidgets('Landscape and square images retain contain fit: $size', (
      tester,
    ) async {
      final image = img.Image(
        width: size.width.toInt(),
        height: size.height.toInt(),
      );
      await openDialog(
        tester,
        metadata: true,
        imageBytes: Uint8List.fromList(img.encodePng(image)),
      );
      expectUnobscuredImage(tester, wide: true);
    });
  }

  testWidgets('Metadata without image uses full-width details', (tester) async {
    await openDialog(tester, metadata: true);
    expect(find.byType(AppImageDetailLayout), findsNothing);
    expect(find.text('NovelAI'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Invalid image falls back without hiding metadata', (
    tester,
  ) async {
    await openDialog(tester, metadata: true, imageBytes: Uint8List(0));
    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    expect(find.text('NovelAI'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
