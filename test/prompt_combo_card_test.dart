import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/data/models/prompt_library_models.dart';
import 'package:novelai_harness/l10n/app_localizations.dart';
import 'package:novelai_harness/ui/features/studio/widgets/prompt_combo_card.dart';

void main() {
  for (final width in [200.0, 280.0]) {
    testWidgets('compact card keeps large preview at width $width', (
      tester,
    ) async {
      final applied = <(bool, bool)>[];
      var edits = 0;
      var deletes = 0;
      final entry = PromptComboEntry(
        id: 'compact',
        title: '一个很长的角色组合名称用于验证单行截断',
        prompt: 'long hair, golden eyes, white dress, detailed background',
        negativePrompt: 'lowres, blurry',
        previewImagePath: 'missing-preview.png',
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
                width: width,
                height: 320,
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
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final card = find.byType(PromptComboCard);
      final preview = find
          .descendant(of: card, matching: find.byType(Stack))
          .first;
      expect(tester.getSize(card).height, 320);
      expect(tester.getSize(preview).height, greaterThan(220));
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
    });
  }
}
