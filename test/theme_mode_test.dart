import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/l10n/app_localizations.dart';
import 'package:novelai_harness/data/services/config_service.dart';
import 'package:novelai_harness/ui/core/theme/theme_mode_controller.dart';
import 'package:novelai_harness/ui/features/settings/widgets/general_settings_tab.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppThemeModePreference 解析与存储', () {
    test('未知/缺失存储值一律回退亮色 (保持旧行为)', () {
      expect(parseThemeModePreference(null), AppThemeModePreference.light);
      expect(parseThemeModePreference(''), AppThemeModePreference.light);
      expect(parseThemeModePreference('garbage'), AppThemeModePreference.light);
      expect(parseThemeModePreference('dark'), AppThemeModePreference.dark);
      expect(parseThemeModePreference('system'), AppThemeModePreference.system);
      expect(parseThemeModePreference('light'), AppThemeModePreference.light);
    });

    test('枚举 ↔ 存储字符串往返一致', () {
      for (final mode in AppThemeModePreference.values) {
        expect(
          parseThemeModePreference(themeModePreferenceStorage(mode)),
          mode,
        );
      }
    });

    test('AppConfig 默认出厂为亮色 (阶段 3 颜色清洗完成前锁定)', () {
      expect(const AppConfig().themeMode, AppThemeModePreference.light);
    });

    test('copyWith 透传 themeMode', () {
      const config = AppConfig();
      expect(
        config.copyWith(themeMode: AppThemeModePreference.dark).themeMode,
        AppThemeModePreference.dark,
      );
      // 不传时保持原值
      expect(
        config
            .copyWith(themeMode: AppThemeModePreference.dark)
            .copyWith()
            .themeMode,
        AppThemeModePreference.dark,
      );
    });
  });

  group('AppThemeModePreference 持久化', () {
    test('saveConfig → loadConfig 往返不丢失', () async {
      SharedPreferences.setMockInitialValues({});
      final service = ConfigService();
      await service.saveConfig(
        const AppConfig(themeMode: AppThemeModePreference.dark),
      );
      final loaded = await service.loadConfig();
      expect(loaded.themeMode, AppThemeModePreference.dark);
    });

    test('旧版本无 themeMode 键时回退亮色默认', () async {
      // 模拟老用户磁盘状态：只有其它键，没有 novelai_theme_mode
      SharedPreferences.setMockInitialValues({'novelai_opus_free_mode': false});
      final loaded = await ConfigService().loadConfig();
      expect(loaded.themeMode, AppThemeModePreference.light);
    });
  });

  group('AppThemeModeController', () {
    setUp(() {
      AppThemeModeController.instance.resetForTest();
    });

    test('偏好枚举映射到 Material ThemeMode', () {
      expect(
        AppThemeModeController.mapPreference(AppThemeModePreference.system),
        ThemeMode.system,
      );
      expect(
        AppThemeModeController.mapPreference(AppThemeModePreference.light),
        ThemeMode.light,
      );
      expect(
        AppThemeModeController.mapPreference(AppThemeModePreference.dark),
        ThemeMode.dark,
      );
    });

    test('syncFromConfig 值变化时才通知监听者', () {
      final controller = AppThemeModeController.instance;
      expect(controller.mode.value, ThemeMode.light);

      var notifications = 0;
      void listener() => notifications++;
      controller.mode.addListener(listener);

      // 值未变化 → 不触发通知
      controller.syncFromConfig(const AppConfig());
      expect(notifications, 0);

      // 值变化 → 恰好一次通知
      controller.syncFromConfig(
        const AppConfig(themeMode: AppThemeModePreference.dark),
      );
      expect(controller.mode.value, ThemeMode.dark);
      expect(notifications, 1);

      controller.mode.removeListener(listener);
    });
  });

  group('GeneralSettingsTab 主题模式选择器', () {
    testWidgets('渲染主题模式卡片并在下拉切换时更新草稿', (tester) async {
      final draft = GeneralSettingsDraft(const AppConfig());
      addTearDown(draft.dispose);
      expect(draft.themeMode, AppThemeModePreference.light);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: GeneralSettingsTab(draft: draft)),
        ),
      );

      // 主题模式卡片标题与当前亮色值可见
      expect(find.text('主题模式'), findsOneWidget);
      expect(find.text('亮色'), findsOneWidget);

      // 展开下拉并选择「深色」
      await tester.tap(find.byType(DropdownButton<AppThemeModePreference>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('深色').last);
      await tester.pumpAndSettle();

      expect(draft.themeMode, AppThemeModePreference.dark);
    });
  });
}
