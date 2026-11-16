import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/l10n/app_localizations.dart';
import 'package:novelai_harness/ui/core/theme/app_theme.dart';
import 'package:novelai_harness/ui/core/widgets/app_dropdown.dart';
import 'package:novelai_harness/ui/core/widgets/overlay_anchor.dart';

void main() {
  testWidgets(
    'showAnchoredPopover removes MediaQuery padding so inner ListView has no status-bar gap',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(400, 800),
            padding: EdgeInsets.only(top: 48, bottom: 24),
          ),
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.only(top: 120, left: 20),
                child: Builder(
                  builder: (context) => ElevatedButton(
                    onPressed: () {
                      showAnchoredPopover<void>(
                        context: context,
                        preferAbove: false,
                        minWidth: 200,
                        maxWidth: 240,
                        builder: (_) => Padding(
                          padding: const EdgeInsets.all(6),
                          child: ListView(
                            shrinkWrap: true,
                            children: const [
                              SizedBox(
                                key: ValueKey('first_popover_item'),
                                height: 32,
                                child: Text('第一项'),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    child: const Text('打开浮层'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开浮层'));
      await tester.pumpAndSettle();

      final listRect = tester.getRect(find.byType(ListView));
      final itemRect = tester.getRect(
        find.byKey(const ValueKey('first_popover_item')),
      );
      // 未剥离状态栏高度时 itemRect.top 会被推下 48px；剥离后应紧贴 ListView 顶部
      expect(itemRect.top - listRect.top, lessThan(1.0));
    },
  );

  testWidgets(
    'AppDropdown popover does not inject mobile top padding above selected item',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(400, 800),
            padding: EdgeInsets.only(top: 48, bottom: 24),
          ),
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.only(top: 120, left: 20),
                child: AppDropdown<String>.simple(
                  value: 'standard',
                  items: const ['standard', 'light', 'none'],
                  labelOf: (v) => '质量词: $v',
                  variant: AppDropdownVariant.chip,
                  isExpanded: false,
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('质量词: standard'));
      await tester.pumpAndSettle();

      final listRect = tester.getRect(find.byType(ListView));
      final firstItemRect = tester.getRect(find.text('质量词: standard').last);
      expect(firstItemRect.top - listRect.top, lessThan(16.0));
    },
  );
}
