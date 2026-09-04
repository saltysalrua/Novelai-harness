import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/ui/core/theme/app_theme.dart';
import 'package:novelai_harness/ui/core/widgets/app_floating_dock.dart';

void main() {
  group('AppFloatingDock Tests', () {
    testWidgets('renders child content in light theme', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: AppFloatingDock(
              child: Text('Dock Action'),
            ),
          ),
        ),
      );

      expect(find.text('Dock Action'), findsOneWidget);
    });

    testWidgets('renders with blur and dark theme', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(
            body: AppFloatingDock(
              enableBlur: true,
              child: Icon(Icons.brush),
            ),
          ),
        ),
      );

      expect(find.byType(Icon), findsOneWidget);
      expect(find.byType(BackdropFilter), findsOneWidget);
    });
  });
}
