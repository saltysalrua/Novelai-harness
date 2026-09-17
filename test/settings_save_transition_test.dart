import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/data/services/config_service.dart';
import 'package:novelai_harness/l10n/app_localizations.dart';
import 'package:novelai_harness/ui/core/theme/app_theme.dart';
import 'package:novelai_harness/ui/core/widgets/app_dropdown.dart';
import 'package:novelai_harness/ui/features/settings/views/settings_dialog.dart';
import 'package:novelai_harness/ui/features/studio/view_models/studio_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

// No application startup, filesystem, credential discovery or network calls.
class _SettingsViewModel implements StudioViewModel {
  @override
  AppConfig get config => const AppConfig(
    localePreference: AppLocalePreference.zh,
    enableTagDictionaryAutoUpdate: false,
  );

  final List<AppConfig> saved = [];
  VoidCallback? onApply;

  @override
  Future<void> updateConfig(AppConfig config) async {
    onApply?.call();
    saved.add(config);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<_SettingsViewModel> openEnglishDraft(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final vm = _SettingsViewModel();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        theme: AppTheme.darkTheme,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => SettingsDialog.show(context, vm),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(AppDropdown<AppLocalePreference>));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(AppDropdown<AppLocalePreference>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English').last);
    await tester.pumpAndSettle();
    expect(vm.saved, isEmpty);
    return vm;
  }

  testWidgets('save applies locale only after the dialog leaves the tree', (
    tester,
  ) async {
    final vm = await openEnglishDraft(tester);
    bool? dialogPresentAtApply;
    vm.onApply = () => dialogPresentAtApply = find
        .byType(SettingsDialog)
        .evaluate()
        .isNotEmpty;
    await tester.tap(find.text('保存设置'));
    await tester.pumpAndSettle();
    expect(dialogPresentAtApply, isFalse);
    expect(find.byType(SettingsDialog), findsNothing);
    expect(vm.saved.single.localePreference, AppLocalePreference.en);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('cancel discards a changed language draft', (tester) async {
    final vm = await openEnglishDraft(tester);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(vm.saved, isEmpty);
    expect(find.byType(SettingsDialog), findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
