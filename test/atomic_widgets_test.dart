import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/ui/core/theme/app_colors_extension.dart';
import 'package:novelai_harness/ui/core/theme/app_theme.dart';
import 'package:novelai_harness/ui/core/theme/app_tokens.dart';
import 'package:novelai_harness/ui/core/theme/theme_context_extensions.dart';
import 'package:novelai_harness/ui/core/widgets/app_dialog_scaffold.dart';
import 'package:novelai_harness/ui/core/widgets/app_dropdown.dart';
import 'package:novelai_harness/ui/core/widgets/app_number_slider.dart';
import 'package:novelai_harness/ui/core/widgets/app_section_header.dart';
import 'package:novelai_harness/ui/core/widgets/app_setting_tile.dart';
import 'package:novelai_harness/ui/core/widgets/app_thumbnail_card.dart';

void main() {
  group('Theme Tokens & Extension Tests', () {
    test('AppColorsExtension provides distinct light and dark palettes', () {
      const light = AppColorsExtension.light;
      const dark = AppColorsExtension.dark;

      expect(light.canvasBackground, isNot(equals(dark.canvasBackground)));
      expect(light.cardBackground, isNot(equals(dark.cardBackground)));
      expect(light.textPrimary, isNot(equals(dark.textPrimary)));
    });

    test('AppTokens have valid positive scales', () {
      expect(AppSpacing.xs < AppSpacing.sm, isTrue);
      expect(AppSpacing.sm < AppSpacing.md, isTrue);
      expect(AppRadius.sm < AppRadius.md, isTrue);
      expect(AppRadius.pill, equals(9999.0));
    });

    testWidgets('ThemeContextX accesses colors in widget tree', (tester) async {
      late AppColorsExtension resolvedColors;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              resolvedColors = context.colors;
              return Container(color: context.colors.cardBackground);
            },
          ),
        ),
      );

      expect(resolvedColors.cardBackground, equals(const Color(0xFFFFFFFF)));
    });
  });

  group('Atomic Widgets Tests', () {
    testWidgets('AppDropdown displays items and triggers selection', (tester) async {
      String selected = 'opt1';

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return AppDropdown<String>.simple(
                  value: selected,
                  items: const ['opt1', 'opt2'],
                  labelOf: (item) => 'Label $item',
                  onChanged: (v) => setState(() => selected = v),
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('Label opt1'), findsOneWidget);
    });

    testWidgets('AppNumberSlider updates on value change', (tester) async {
      int currentValue = 20;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return AppNumberSlider.integer(
                  title: 'Test Steps',
                  value: currentValue,
                  min: 1,
                  max: 50,
                  onChanged: (val) => setState(() => currentValue = val),
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('Test Steps'), findsOneWidget);
      expect(find.text('20'), findsOneWidget);
    });

    testWidgets('AppSettingTile renders title, subtitle and switch', (tester) async {
      bool toggleVal = true;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return AppSettingTile.switchTile(
                  title: 'Auto Save',
                  subtitle: 'Save images to local directory',
                  value: toggleVal,
                  onChanged: (v) => setState(() => toggleVal = v),
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('Auto Save'), findsOneWidget);
      expect(find.text('Save images to local directory'), findsOneWidget);
      expect(find.byType(Switch), findsOneWidget);
    });

    testWidgets('AppSectionHeader renders title and subtitle', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: AppSectionHeader(
              title: 'Model Options',
              subtitle: 'Select base diffusion model',
            ),
          ),
        ),
      );

      expect(find.text('Model Options'), findsOneWidget);
      expect(find.text('Select base diffusion model'), findsOneWidget);
    });

    testWidgets('AppDialogScaffold displays modal with title and actions', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: AppDialogScaffold(
              title: 'Test Dialog',
              subtitle: 'Dialog Description',
              body: const Text('Dialog Content'),
              actions: [
                ElevatedButton(onPressed: () {}, child: const Text('OK')),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Test Dialog'), findsOneWidget);
      expect(find.text('Dialog Description'), findsOneWidget);
      expect(find.text('Dialog Content'), findsOneWidget);
      expect(find.text('OK'), findsOneWidget);
    });

    testWidgets('AppThumbnailCard displays with badge', (tester) async {
      final dummyBytes = Uint8List(100);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: AppThumbnailCard(
              imageBytes: dummyBytes,
              badgeLabel: '放大',
              isSelected: true,
            ),
          ),
        ),
      );

      expect(find.text('放大'), findsOneWidget);
    });
  });
}
